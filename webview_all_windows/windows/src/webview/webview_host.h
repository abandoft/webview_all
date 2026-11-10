#pragma once

#include <WebView2.h>
// The SDK's custom-scheme property setters shadow WRL storage members.
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4458)
#endif
#include <WebView2EnvironmentOptions.h>
#ifdef _MSC_VER
#pragma warning(pop)
#endif
#include <wil/com.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "webview/webview.h"
#include <windows.ui.composition.h>

namespace webview_all_windows {

struct WebviewCreationError {
  HRESULT hr;
  std::string message;

  explicit WebviewCreationError(HRESULT hr, std::string message)
      : hr(hr), message(message) {}

  static std::unique_ptr<WebviewCreationError>
  create(HRESULT hr, const std::string message) {
    return std::make_unique<WebviewCreationError>(hr, message);
  }
};

class WebviewHost;

struct WebviewHostCreationResult {
  std::shared_ptr<WebviewHost> host;
  HRESULT hresult = E_FAIL;
  std::string message;

  bool succeeded() const { return host != nullptr; }
};

struct WebviewHostWebsiteDataClearingResult {
  bool supported = true;
  bool succeeded = false;
  HRESULT hresult = E_FAIL;
  std::string stage;
  std::string message;
};

class WebviewHost : public std::enable_shared_from_this<WebviewHost> {
public:
  typedef std::function<void(WebviewHostCreationResult)>
      WebviewHostCreationCallback;
  typedef std::function<void(std::unique_ptr<Webview>,
                             std::unique_ptr<WebviewCreationError>)>
      WebviewCreationCallback;
  typedef std::function<void(wil::com_ptr<ICoreWebView2CompositionController>,
                             std::unique_ptr<WebviewCreationError>)>
      CompositionControllerCreationCallback;
  typedef std::function<void(wil::com_ptr<ICoreWebView2PointerInfo>,
                             std::unique_ptr<WebviewCreationError>)>
      PointerInfoCreationCallback;
  typedef std::function<void(WebviewHostWebsiteDataClearingResult)>
      WebsiteDataClearingCallback;

  static void Create(std::optional<std::wstring> user_data_directory,
                     std::optional<std::wstring> browser_exe_path,
                     std::optional<std::string> arguments,
                     WebviewHostCreationCallback callback,
                     const std::vector<std::string>& custom_schemes = {});

  void CreateWebview(
      HWND parent_window,
      winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor,
      WebviewCreationCallback callback, bool incognito = false, std::optional<std::wstring> profile_name = std::nullopt, bool profile_management = false);

  bool SupportsIncognito() const;
  wil::com_ptr<ICoreWebView2FindOptions> CreateFindOptions();
  wil::com_ptr<ICoreWebView2PrintSettings> CreatePrintSettings();

  void CreateWebViewPointerInfo(PointerInfoCreationCallback cb);

  static void ClearAllWebsiteData(ICoreWebView2 *webview,
                                  WebsiteDataClearingCallback callback);
  void ClearAllWebsiteData(WebsiteDataClearingCallback callback);
  static void ClearWebsiteData(ICoreWebView2 *webview, uint64_t kinds,
                               WebsiteDataClearingCallback callback);
  void ClearWebsiteData(uint64_t kinds, WebsiteDataClearingCallback callback);

  wil::com_ptr<ICoreWebView2WebResourceRequest>
  CreateWebResourceRequest(const std::string &url, const std::string &method,
                           const std::string &headers,
                           const std::vector<uint8_t> *body);

private:
  wil::com_ptr<ICoreWebView2Environment3> webview_env_;

  explicit WebviewHost(wil::com_ptr<ICoreWebView2Environment3> webview_env);
  void
  CreateWebViewCompositionController(HWND hwnd,
                                     CompositionControllerCreationCallback cb,
                                     bool incognito = false, std::optional<std::wstring> profile_name = std::nullopt);
};

} // namespace webview_all_windows
