#include "webview/webview_host.h"

#include <wrl.h>

#include <atomic>
#include <cstring>
#include <mutex>
#include <utility>

#include "util/string_converter.h"

using namespace Microsoft::WRL;

namespace webview_all_windows {
namespace {

WebviewHostWebsiteDataClearingResult
WebsiteDataFailure(const std::string &stage, const std::string &message,
                   HRESULT hresult);

class WebsiteDataClearingOperation
    : public std::enable_shared_from_this<WebsiteDataClearingOperation> {
public:
  explicit WebsiteDataClearingOperation(
      WebviewHost::WebsiteDataClearingCallback callback)
      : callback_(std::move(callback)) {}

  void SetHostWindow(HWND host_window) { host_window_ = host_window; }

  void ClearWithController(wil::com_ptr<ICoreWebView2Controller> controller) {
    controller_ = std::move(controller);

    wil::com_ptr<ICoreWebView2> webview;
    const HRESULT webview_result = controller_->get_CoreWebView2(webview.put());
    if (FAILED(webview_result) || !webview) {
      Complete(WebsiteDataFailure(
          "webview2_data_webview",
          "Accessing the WebView2 data controller failed.",
          FAILED(webview_result) ? webview_result : E_POINTER));
      return;
    }
    const auto self = shared_from_this();
    WebviewHost::ClearAllWebsiteData(
        webview.get(), [self](WebviewHostWebsiteDataClearingResult result) {
          self->Complete(std::move(result));
        });
  }

  void Complete(WebviewHostWebsiteDataClearingResult result) {
    if (completed_.exchange(true)) {
      return;
    }
    if (controller_) {
      controller_->Close();
      controller_.reset();
    }
    if (host_window_ != nullptr) {
      DestroyWindow(host_window_);
      host_window_ = nullptr;
    }
    auto callback = std::move(callback_);
    callback(std::move(result));
  }

private:
  std::atomic_bool completed_ = false;
  WebviewHost::WebsiteDataClearingCallback callback_;
  wil::com_ptr<ICoreWebView2Controller> controller_;
  HWND host_window_ = nullptr;
};

WebviewHostWebsiteDataClearingResult
WebsiteDataFailure(const std::string &stage, const std::string &message,
                   HRESULT hresult) {
  return WebviewHostWebsiteDataClearingResult{true, false, hresult, stage,
                                              message};
}

} // namespace

// static
void WebviewHost::Create(std::optional<std::wstring> user_data_directory,
                         std::optional<std::wstring> browser_exe_path,
                         std::optional<std::string> arguments,
                         WebviewHostCreationCallback callback) {
  wil::com_ptr<CoreWebView2EnvironmentOptions> opts;
  if (arguments.has_value()) {
    opts = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
    if (!opts) {
      callback(WebviewHostCreationResult{
          nullptr, E_OUTOFMEMORY,
          "Allocating WebView2 environment options failed."});
      return;
    }
    const std::wstring warguments = util::Utf16FromUtf8(arguments.value());
    const HRESULT options_result =
        opts->put_AdditionalBrowserArguments(warguments.c_str());
    if (FAILED(options_result)) {
      callback(WebviewHostCreationResult{
          nullptr, options_result,
          "Applying WebView2 environment arguments failed."});
      return;
    }
  }

  auto callback_holder =
      std::make_shared<WebviewHostCreationCallback>(std::move(callback));
  auto callback_mutex = std::make_shared<std::mutex>();
  const auto complete = [callback_holder, callback_mutex](
                            WebviewHostCreationResult creation_result) {
    WebviewHostCreationCallback callback;
    {
      const std::lock_guard<std::mutex> lock(*callback_mutex);
      if (!*callback_holder) {
        return;
      }
      callback = std::move(*callback_holder);
      *callback_holder = nullptr;
    }
    callback(std::move(creation_result));
  };

  HRESULT result = CreateCoreWebView2EnvironmentWithOptions(
      browser_exe_path.has_value() ? browser_exe_path->c_str() : nullptr,
      user_data_directory.has_value() ? user_data_directory->c_str() : nullptr,
      opts.get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [complete](HRESULT result,
                     ICoreWebView2Environment *environment) -> HRESULT {
            if (FAILED(result)) {
              complete(WebviewHostCreationResult{
                  nullptr, result,
                  "Creating the WebView2 environment failed."});
              return S_OK;
            }
            if (environment == nullptr) {
              complete(WebviewHostCreationResult{
                  nullptr, E_POINTER,
                  "WebView2 environment creation completed without an "
                  "environment."});
              return S_OK;
            }

            wil::com_ptr<ICoreWebView2Environment> environment_pointer(
                environment);
            auto webview_environment =
                environment_pointer.try_query<ICoreWebView2Environment3>();
            if (!webview_environment) {
              complete(WebviewHostCreationResult{
                  nullptr, E_NOINTERFACE,
                  "The installed WebView2 Runtime does not provide the "
                  "required environment interface."});
              return S_OK;
            }

            complete(WebviewHostCreationResult{
                std::shared_ptr<WebviewHost>(
                    new WebviewHost(std::move(webview_environment))),
                S_OK,
                {}});
            return S_OK;
          })
          .Get());

  if (FAILED(result)) {
    complete(WebviewHostCreationResult{
        nullptr, result, "Starting WebView2 environment creation failed."});
  }
}

WebviewHost::WebviewHost(wil::com_ptr<ICoreWebView2Environment3> webview_env)
    : webview_env_(std::move(webview_env)) {}

void WebviewHost::CreateWebview(
    HWND parent_window,
    winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor,
    WebviewCreationCallback callback) {
  CreateWebViewCompositionController(
      parent_window,
      [callback = std::move(callback), parent_window,
       compositor = std::move(compositor), self = shared_from_this()](
          wil::com_ptr<ICoreWebView2CompositionController> controller,
          std::unique_ptr<WebviewCreationError> error) mutable {
        if (controller) {
          std::unique_ptr<Webview> webview(new Webview(
              std::move(controller), self, parent_window, compositor));
          if (!webview->IsValid()) {
            callback(
                nullptr,
                WebviewCreationError::create(
                    E_FAIL,
                    "The WebView composition surface could not be created."));
            return;
          }
          callback(std::move(webview), nullptr);
        } else {
          callback(nullptr, std::move(error));
        }
      });
}

void WebviewHost::CreateWebViewPointerInfo(
    PointerInfoCreationCallback callback) {

  ICoreWebView2PointerInfo *pointer;
  auto hr = webview_env_->CreateCoreWebView2PointerInfo(&pointer);

  if (FAILED(hr)) {
    callback(nullptr, WebviewCreationError::create(
                          hr, "CreateWebViewPointerInfo failed."));
  } else if (SUCCEEDED(hr)) {
    callback(std::move(wil::com_ptr<ICoreWebView2PointerInfo>(pointer)),
             nullptr);
  }
}

// static
void WebviewHost::ClearAllWebsiteData(ICoreWebView2 *webview,
                                      WebsiteDataClearingCallback callback) {
  if (webview == nullptr) {
    callback(WebsiteDataFailure("webview2_data_webview",
                                "The WebView2 instance is unavailable.",
                                E_POINTER));
    return;
  }

  wil::com_ptr<ICoreWebView2> webview_pointer(webview);
  auto webview13 = webview_pointer.try_query<ICoreWebView2_13>();
  if (!webview13) {
    callback(WebviewHostWebsiteDataClearingResult{false, false, S_OK, {}, {}});
    return;
  }

  wil::com_ptr<ICoreWebView2Profile> profile;
  const HRESULT profile_result = webview13->get_Profile(profile.put());
  if (FAILED(profile_result) || !profile) {
    callback(WebsiteDataFailure(
        "webview2_profile", "Accessing the WebView2 profile failed.",
        FAILED(profile_result) ? profile_result : E_POINTER));
    return;
  }

  auto profile2 = profile.try_query<ICoreWebView2Profile2>();
  if (!profile2) {
    callback(WebviewHostWebsiteDataClearingResult{false, false, S_OK, {}, {}});
    return;
  }

  const auto website_data = static_cast<COREWEBVIEW2_BROWSING_DATA_KINDS>(
      COREWEBVIEW2_BROWSING_DATA_KINDS_ALL_SITE |
      COREWEBVIEW2_BROWSING_DATA_KINDS_DISK_CACHE);
  auto completion =
      std::make_shared<WebsiteDataClearingCallback>(std::move(callback));
  auto completed = std::make_shared<std::atomic_bool>(false);
  const auto complete =
      [completion, completed](WebviewHostWebsiteDataClearingResult result) {
        if (!completed->exchange(true)) {
          auto callback = std::move(*completion);
          callback(std::move(result));
        }
      };
  const HRESULT clear_result = profile2->ClearBrowsingData(
      website_data,
      Callback<ICoreWebView2ClearBrowsingDataCompletedHandler>(
          [complete](HRESULT result) -> HRESULT {
            complete(FAILED(result)
                         ? WebsiteDataFailure(
                               "webview2_website_data",
                               "Clearing WebView2 website data failed.", result)
                         : WebviewHostWebsiteDataClearingResult{
                               true, true, S_OK, {}, {}});
            return S_OK;
          })
          .Get());
  if (FAILED(clear_result)) {
    complete(WebsiteDataFailure(
        "webview2_website_data",
        "Starting WebView2 website-data clearing failed.", clear_result));
  }
}

void WebviewHost::ClearAllWebsiteData(WebsiteDataClearingCallback callback) {
  auto operation =
      std::make_shared<WebsiteDataClearingOperation>(std::move(callback));
  const HWND host_window = CreateWindowExW(
      0, L"STATIC", L"webview_all_windows_data", WS_OVERLAPPED, 0, 0, 1, 1,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (host_window == nullptr) {
    const DWORD error = GetLastError();
    operation->Complete(WebsiteDataFailure(
        "webview2_data_window",
        "Creating the WebView2 data-controller window failed.",
        HRESULT_FROM_WIN32(error == ERROR_SUCCESS ? ERROR_INVALID_WINDOW_HANDLE
                                                  : error)));
    return;
  }
  operation->SetHostWindow(host_window);
  CreateWebViewCompositionController(
      host_window,
      [operation](wil::com_ptr<ICoreWebView2CompositionController> composition,
                  std::unique_ptr<WebviewCreationError> error) {
        if (!composition) {
          operation->Complete(WebsiteDataFailure(
              "webview2_data_controller",
              error ? error->message
                    : "Creating the WebView2 data controller failed.",
              error ? error->hr : E_POINTER));
          return;
        }
        auto controller = composition.try_query<ICoreWebView2Controller>();
        if (!controller) {
          operation->Complete(WebsiteDataFailure(
              "webview2_data_controller",
              "The WebView2 data controller interface is unavailable.",
              E_NOINTERFACE));
          return;
        }
        operation->ClearWithController(std::move(controller));
      });
}

wil::com_ptr<ICoreWebView2WebResourceRequest>
WebviewHost::CreateWebResourceRequest(const std::string &url,
                                      const std::string &method,
                                      const std::string &headers,
                                      const std::vector<uint8_t> *body) {
  wil::com_ptr<IStream> body_stream;
  if (body != nullptr && !body->empty()) {
    HGLOBAL global = GlobalAlloc(GMEM_MOVEABLE, body->size());
    if (global == nullptr) {
      return nullptr;
    }

    void *data = GlobalLock(global);
    if (data == nullptr) {
      GlobalFree(global);
      return nullptr;
    }
    std::memcpy(data, body->data(), body->size());
    GlobalUnlock(global);

    IStream *stream = nullptr;
    if (FAILED(CreateStreamOnHGlobal(global, TRUE, &stream))) {
      GlobalFree(global);
      return nullptr;
    }
    body_stream.attach(stream);
  }

  wil::com_ptr<ICoreWebView2WebResourceRequest> request;
  if (FAILED(webview_env_->CreateWebResourceRequest(
          util::Utf16FromUtf8(url).c_str(), util::Utf16FromUtf8(method).c_str(),
          body_stream.get(), util::Utf16FromUtf8(headers).c_str(),
          request.put()))) {
    return nullptr;
  }
  return request;
}

void WebviewHost::CreateWebViewCompositionController(
    HWND hwnd, CompositionControllerCreationCallback callback) {
  auto hr = webview_env_->CreateCoreWebView2CompositionController(
      hwnd,
      Callback<
          ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler>(
          [callback](HRESULT hr,
                     ICoreWebView2CompositionController *compositionController)
              -> HRESULT {
            if (SUCCEEDED(hr)) {
              callback(
                  std::move(wil::com_ptr<ICoreWebView2CompositionController>(
                      compositionController)),
                  nullptr);
            } else {
              callback(nullptr,
                       WebviewCreationError::create(
                           hr, "CreateCoreWebView2CompositionController "
                               "completion handler failed."));
            }

            return S_OK;
          })
          .Get());

  if (FAILED(hr)) {
    callback(nullptr,
             WebviewCreationError::create(
                 hr, "CreateCoreWebView2CompositionController failed."));
  }
}

} // namespace webview_all_windows
