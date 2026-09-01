#include "plugin/windows_host_api.h"

#include <shellapi.h>
#include <shlobj.h>
#include <windows.h>

#include <cstdint>
#include <filesystem>
#include <functional>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>

#include "util/logging.h"
#include "util/string_converter.h"

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "shell32.lib")

namespace webview_all_windows {
namespace {

constexpr auto kErrorCodeInvalidId = "invalid_id";
constexpr auto kErrorCodeEnvironmentCreationFailed =
    "environment_creation_failed";
constexpr auto kErrorCodeEnvironmentAlreadyInitialized =
    "environment_already_initialized";
constexpr auto kErrorCodeEnvironmentConfigurationConflict =
    "environment_configuration_conflict";
constexpr auto kErrorCodeWebviewCreationFailed = "webview_creation_failed";
constexpr auto kErrorCodeInvalidParentWindow = "invalid_parent_window";
constexpr auto kErrorCodeOpenUrlFailed = "open_url_failed";
constexpr auto kErrorMethodFailed = "method_failed";
constexpr auto kErrorNotSupported = "not_supported";
constexpr auto kErrorScriptFailed = "script_failed";

std::string FormatHresult(HRESULT result) {
  std::ostringstream value;
  value << "0x" << std::hex << std::setw(8) << std::setfill('0')
        << static_cast<uint32_t>(result);
  return value.str();
}

FlutterError CreateInitializationError(
    const std::string &code, const std::string &stage,
    const std::string &message, HRESULT result,
    const std::optional<std::string> &webview_runtime_version = std::nullopt) {
  flutter::EncodableMap details{
      {flutter::EncodableValue("stage"), flutter::EncodableValue(stage)},
      {flutter::EncodableValue("hresult"),
       flutter::EncodableValue(FormatHresult(result))},
      {flutter::EncodableValue("hresultValue"),
       flutter::EncodableValue(
           static_cast<int64_t>(static_cast<int32_t>(result)))},
      {flutter::EncodableValue("remoteSession"),
       flutter::EncodableValue(GetSystemMetrics(SM_REMOTESESSION) != 0)},
  };
  if (webview_runtime_version.has_value()) {
    details[flutter::EncodableValue("webView2RuntimeVersion")] =
        flutter::EncodableValue(webview_runtime_version.value());
  }

  const std::string diagnostic = message + " (stage: " + stage +
                                 ", HRESULT: " + FormatHresult(result) + ")";
  util::LogWarning(code + ": " + diagnostic);
  return FlutterError(code, diagnostic, flutter::EncodableValue(details));
}

std::optional<std::wstring> GetDefaultDataDirectory() {
  PWSTR local_app_data = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                  &local_app_data)) ||
      local_app_data == nullptr) {
    return std::nullopt;
  }

  std::filesystem::path path(local_app_data);
  CoTaskMemFree(local_app_data);

  wchar_t executable_path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return std::nullopt;
  }
  path /= L"webview_all_windows";
  path /= std::filesystem::path(executable_path).stem();
  return path.wstring();
}

std::optional<std::wstring>
NormalizeEnvironmentPath(std::optional<std::wstring> path) {
  if (!path || path->empty()) {
    return std::nullopt;
  }
  std::error_code error;
  std::filesystem::path normalized =
      std::filesystem::absolute(std::filesystem::path(*path), error);
  if (error) {
    normalized = std::filesystem::path(*path);
  }
  normalized = normalized.lexically_normal();
  while (!normalized.has_filename() && normalized != normalized.root_path()) {
    normalized = normalized.parent_path();
  }
  return normalized.make_preferred().wstring();
}

std::optional<std::string>
NormalizeEnvironmentArguments(const std::string *arguments) {
  if (arguments == nullptr || arguments->empty()) {
    return std::nullopt;
  }
  return *arguments;
}

} // namespace

// static
void WindowsHostApi::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar, HWND parent_window) {
  auto plugin = std::make_unique<WindowsHostApi>(
      registrar->texture_registrar(), registrar->messenger(), parent_window);
  plugin->registrar_ = registrar;

  const std::shared_ptr<LifetimeState> lifetime_state = plugin->lifetime_state_;
  plugin->window_proc_delegate_id_ =
      registrar->RegisterTopLevelWindowProcDelegate(
          [lifetime_state](HWND hwnd, UINT message, WPARAM wparam,
                           LPARAM lparam) -> std::optional<LRESULT> {
            if (lifetime_state->owner == nullptr) {
              return std::nullopt;
            }
            return lifetime_state->owner->HandleWindowMessage(hwnd, message,
                                                              wparam, lparam);
          });

  webview_all_windows::WindowsWebViewHostApi::SetUp(registrar->messenger(),
                                                    plugin.get());

  registrar->AddPlugin(std::move(plugin));
}

WindowsHostApi::WindowsHostApi(flutter::TextureRegistrar *textures,
                               flutter::BinaryMessenger *messenger,
                               HWND parent_window)
    : textures_(textures), messenger_(messenger),
      parent_window_(parent_window) {
  lifetime_state_->owner = this;
}

WindowsHostApi::~WindowsHostApi() {
  lifetime_state_->owner = nullptr;
  // Deliberately no SetUp(messenger_, nullptr) here. This destructor only runs
  // from a plugin registrar destruction callback, which FlutterWindowsEngine
  // fires from Stop() *after* its own destructor has already nulled the
  // messenger's engine pointer -- so unregistering would dereference null
  // inside FlutterDesktopMessengerSetCallback. The dispatcher is torn down
  // with the engine anyway. See flutter/flutter#118611 and the contract
  // documented on flutter::MethodChannel::SetMethodCallHandler.
  instances_.clear();
  if (registrar_ != nullptr && window_proc_delegate_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
}

std::optional<LRESULT> WindowsHostApi::HandleWindowMessage(HWND, UINT message,
                                                           WPARAM, LPARAM) {
  switch (message) {
  case WM_DISPLAYCHANGE:
  case WM_DPICHANGED:
  case WM_MOVE:
  case WM_SIZE:
  case WM_WINDOWPOSCHANGED:
    NotifyParentWindowPositionChanged();
    break;
  default:
    break;
  }
  return std::nullopt;
}

void WindowsHostApi::NotifyParentWindowPositionChanged() {
  for (const auto &instance : instances_) {
    instance.second->NotifyParentWindowPositionChanged();
  }
}

void WindowsHostApi::InitializeEnvironment(
    const webview_all_windows::WindowsEnvironmentOptions &options,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (webview_host_ || pending_environment_configuration_.has_value()) {
    result(webview_all_windows::FlutterError(
        kErrorCodeEnvironmentAlreadyInitialized,
        "The WebView2 environment is already initialized or initializing."));
    return;
  }

  CreateEnvironment(ResolveEnvironmentConfiguration(options),
                    std::move(result));
}

void WindowsHostApi::EnsureEnvironment(
    const webview_all_windows::WindowsEnvironmentOptions &options,
    std::function<void(std::optional<FlutterError> reply)> result) {
  const EnvironmentConfiguration requested =
      ResolveEnvironmentConfiguration(options);
  if (webview_host_) {
    if (environment_configuration_ &&
        *environment_configuration_ == requested) {
      result(std::nullopt);
    } else {
      result(webview_all_windows::FlutterError(
          kErrorCodeEnvironmentConfigurationConflict,
          "The active WebView2 environment uses different configuration "
          "options."));
    }
    return;
  }

  if (pending_environment_configuration_.has_value()) {
    if (*pending_environment_configuration_ == requested) {
      pending_environment_callbacks_.push_back(std::move(result));
    } else {
      result(webview_all_windows::FlutterError(
          kErrorCodeEnvironmentConfigurationConflict,
          "The WebView2 environment being initialized uses different "
          "configuration options."));
    }
    return;
  }

  CreateEnvironment(requested, std::move(result));
}

WindowsHostApi::EnvironmentConfiguration
WindowsHostApi::ResolveEnvironmentConfiguration(
    const webview_all_windows::WindowsEnvironmentOptions &options) {
  std::optional<std::wstring> user_data_path;
  if (options.user_data_path() != nullptr &&
      !options.user_data_path()->empty()) {
    user_data_path = util::Utf16FromUtf8(*options.user_data_path());
  } else {
    user_data_path = GetDefaultDataDirectory();
  }
  std::optional<std::wstring> browser_exe_path;
  if (options.browser_exe_path() != nullptr &&
      !options.browser_exe_path()->empty()) {
    browser_exe_path = util::Utf16FromUtf8(*options.browser_exe_path());
  }
  return EnvironmentConfiguration{
      NormalizeEnvironmentPath(std::move(user_data_path)),
      NormalizeEnvironmentPath(std::move(browser_exe_path)),
      NormalizeEnvironmentArguments(options.additional_arguments())};
}

void WindowsHostApi::CreateEnvironment(
    const EnvironmentConfiguration &configuration,
    EnvironmentInitializationCallback callback) {
  wil::unique_cotaskmem_string version_info;
  HRESULT version_result = GetAvailableCoreWebView2BrowserVersionString(
      configuration.browser_exe_path.has_value()
          ? configuration.browser_exe_path->c_str()
          : nullptr,
      &version_info);
  if (FAILED(version_result) || version_info == nullptr) {
    if (SUCCEEDED(version_result)) {
      version_result = HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
    }
    callback(CreateInitializationError(
        "webview2_runtime_unavailable", "webview2_runtime",
        "Microsoft Edge WebView2 Runtime is not available for the requested "
        "configuration.",
        version_result));
    return;
  }
  webview_runtime_version_ = util::Utf8FromUtf16(version_info.get());

  pending_environment_configuration_ = configuration;
  pending_environment_callbacks_.push_back(std::move(callback));
  WebviewHost::Create(
      configuration.user_data_path, configuration.browser_exe_path,
      configuration.additional_arguments,
      [lifetime_state = lifetime_state_,
       configuration](WebviewHostCreationResult creation_result) mutable {
        WindowsHostApi *const owner = lifetime_state->owner;
        if (owner != nullptr) {
          owner->CompleteEnvironmentCreation(configuration,
                                             std::move(creation_result));
        }
      });
}

void WindowsHostApi::CompleteEnvironmentCreation(
    const EnvironmentConfiguration &configuration,
    WebviewHostCreationResult creation_result) {
  if (!pending_environment_configuration_.has_value() ||
      !(*pending_environment_configuration_ == configuration)) {
    util::LogWarning(
        "Ignoring a stale WebView2 environment creation completion.");
    return;
  }

  std::optional<FlutterError> error;
  if (!creation_result.succeeded()) {
    error = CreateInitializationError(
        kErrorCodeEnvironmentCreationFailed, "webview2_environment",
        creation_result.message.empty()
            ? "Creating the WebView2 environment failed."
            : creation_result.message,
        creation_result.hresult, webview_runtime_version_);
  } else {
    webview_host_ = std::move(creation_result.host);
    environment_configuration_ = configuration;
  }

  pending_environment_configuration_.reset();
  std::vector<EnvironmentInitializationCallback> callbacks =
      std::move(pending_environment_callbacks_);
  pending_environment_callbacks_.clear();
  for (EnvironmentInitializationCallback &callback : callbacks) {
    callback(error);
  }
}

webview_all_windows::ErrorOr<std::optional<std::string>>
WindowsHostApi::GetWebViewVersion() {
  wil::unique_cotaskmem_string version_info;
  auto hr =
      GetAvailableCoreWebView2BrowserVersionString(nullptr, &version_info);
  if (SUCCEEDED(hr) && version_info != nullptr) {
    return std::optional<std::string>(util::Utf8FromUtf16(version_info.get()));
  }
  return std::optional<std::string>();
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::OpenWebView2DownloadPage() {
  constexpr wchar_t kWebView2DownloadUrl[] =
      L"https://developer.microsoft.com/en-us/microsoft-edge/webview2/"
      L"#download-section";
  const auto result = ShellExecuteW(nullptr, L"open", kWebView2DownloadUrl,
                                    nullptr, nullptr, SW_SHOWNORMAL);
  if (reinterpret_cast<INT_PTR>(result) <= 32) {
    return webview_all_windows::FlutterError(
        kErrorCodeOpenUrlFailed,
        "Failed to open the Microsoft WebView2 Runtime download page.");
  }
  return std::nullopt;
}

void WindowsHostApi::ClearAllWebsiteDataForEnvironment(
    std::function<void(ErrorOr<bool> reply)> result) {
  if (!webview_host_) {
    return result(
        FlutterError(kErrorCodeEnvironmentCreationFailed,
                     "The WebView2 environment has not been initialized."));
  }
  webview_host_->ClearAllWebsiteData(
      [lifetime_state = lifetime_state_, result = std::move(result)](
          WebviewHostWebsiteDataClearingResult clear_result) mutable {
        WindowsHostApi *const owner = lifetime_state->owner;
        if (owner == nullptr) {
          return;
        }
        if (!clear_result.supported) {
          return result(false);
        }
        if (clear_result.succeeded) {
          return result(true);
        }
        result(CreateInitializationError(
            "website_data_clearing_failed", clear_result.stage,
            clear_result.message, clear_result.hresult,
            owner->webview_runtime_version_));
      });
}

void WindowsHostApi::CreateWebView(
    std::function<void(webview_all_windows::ErrorOr<
                       webview_all_windows::WindowsCreateWebViewResult>
                           reply)>
        result) {
  if (parent_window_ == nullptr || !IsWindow(parent_window_)) {
    return result(webview_all_windows::FlutterError(
        kErrorCodeInvalidParentWindow,
        "The Flutter view window is unavailable."));
  }

  if (webview_host_) {
    CreateWebViewWithEnvironment(std::move(result));
    return;
  }

  EnvironmentInitializationCallback continue_creation =
      [lifetime_state = lifetime_state_,
       result = std::move(result)](std::optional<FlutterError> error) mutable {
        WindowsHostApi *const owner = lifetime_state->owner;
        if (owner == nullptr) {
          return;
        }
        if (error.has_value()) {
          result(*error);
          return;
        }
        owner->CreateWebViewWithEnvironment(std::move(result));
      };
  if (pending_environment_configuration_.has_value()) {
    pending_environment_callbacks_.push_back(std::move(continue_creation));
    return;
  }

  const WindowsEnvironmentOptions default_options;
  CreateEnvironment(ResolveEnvironmentConfiguration(default_options),
                    std::move(continue_creation));
}

void WindowsHostApi::CreateWebViewWithEnvironment(
    std::function<void(webview_all_windows::ErrorOr<
                       webview_all_windows::WindowsCreateWebViewResult>
                           reply)>
        result) {
  if (const std::optional<FlutterError> platform_error =
          EnsureRenderingPlatform()) {
    return result(*platform_error);
  }

  webview_host_->CreateWebview(
      parent_window_, platform_->compositor(),
      [lifetime_state = lifetime_state_, result = std::move(result)](
          std::unique_ptr<Webview> webview,
          std::unique_ptr<WebviewCreationError> error) mutable {
        WindowsHostApi *const owner = lifetime_state->owner;
        if (owner == nullptr) {
          return;
        }
        if (!webview) {
          if (error) {
            return result(CreateInitializationError(
                kErrorCodeWebviewCreationFailed, "webview2_controller",
                error->message, error->hr, owner->webview_runtime_version_));
          }
          return result(CreateInitializationError(
              kErrorCodeWebviewCreationFailed, "webview2_controller",
              "Creating the WebView2 controller failed.", E_FAIL,
              owner->webview_runtime_version_));
        }

        auto bridge = std::make_unique<WebviewBridge>(
            owner->messenger_, owner->textures_,
            owner->platform_->graphics_context(), std::move(webview));
        if (!bridge->IsValid()) {
          if (const auto &rendering_error = bridge->initialization_error()) {
            return result(CreateInitializationError(
                rendering_error->code, rendering_error->stage,
                rendering_error->message, rendering_error->hresult,
                owner->webview_runtime_version_));
          }
          return result(CreateInitializationError(
              kErrorCodeWebviewCreationFailed, "graphics_capture_texture",
              "Creating the WebView graphics capture texture failed.", E_FAIL,
              owner->webview_runtime_version_));
        }
        auto texture_id = bridge->texture_id();
        owner->instances_[texture_id] = std::move(bridge);

        result(webview_all_windows::WindowsCreateWebViewResult(texture_id));
      });
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::DisposeWebView(int64_t texture_id) {
  const auto it = instances_.find(texture_id);
  if (it != instances_.end()) {
    instances_.erase(it);
    return std::nullopt;
  }
  return webview_all_windows::FlutterError(kErrorCodeInvalidId);
}

WebviewBridge *WindowsHostApi::FindBridge(int64_t texture_id) {
  const auto it = instances_.find(texture_id);
  if (it == instances_.end()) {
    return nullptr;
  }
  return it->second.get();
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::InvalidIdError() {
  return webview_all_windows::FlutterError(kErrorCodeInvalidId);
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::MethodFailedError(const std::string &message) {
  return webview_all_windows::FlutterError(kErrorMethodFailed, message);
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::LoadUrl(int64_t texture_id, const std::string &url) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->LoadUrl(url);
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError> WindowsHostApi::LoadRequest(
    int64_t texture_id,
    const webview_all_windows::WindowsLoadRequestData &request) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->LoadRequest(request.url(), request.method(), request.headers(),
                           request.body())) {
    return MethodFailedError("Loading the request failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::LoadStringContent(int64_t texture_id,
                                  const std::string &content) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->LoadStringContent(content);
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::Reload(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->Reload()) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::Stop(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->Stop()) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::GoBack(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->GoBack()) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::GoForward(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->GoForward()) {
    return MethodFailedError();
  }
  return std::nullopt;
}

void WindowsHostApi::AddScriptToExecuteOnDocumentCreated(
    int64_t texture_id, const std::string &script,
    std::function<
        void(webview_all_windows::ErrorOr<std::optional<std::string>> reply)>
        result) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return result(webview_all_windows::FlutterError(kErrorCodeInvalidId));
  }
  bridge->AddScriptToExecuteOnDocumentCreated(
      script, [result = std::move(result)](
                  bool success, const std::string &script_id) mutable {
        if (success) {
          return result(std::optional<std::string>(script_id));
        }
        return result(webview_all_windows::FlutterError(
            kErrorScriptFailed, "Adding the document-created script failed."));
      });
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::RemoveScriptToExecuteOnDocumentCreated(
    int64_t texture_id, const std::string &script_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->RemoveScriptToExecuteOnDocumentCreated(script_id)) {
    return webview_all_windows::FlutterError(
        kErrorScriptFailed, "Removing the document-created script failed.");
  }
  return std::nullopt;
}

void WindowsHostApi::ExecuteScript(
    int64_t texture_id, const std::string &script,
    std::function<void(webview_all_windows::ErrorOr<std::string> reply)>
        result) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return result(webview_all_windows::FlutterError(kErrorCodeInvalidId));
  }
  bridge->ExecuteScript(
      script, [result = std::move(result)](
                  bool success, const std::string &json_result) mutable {
        if (success) {
          return result(json_result);
        }
        return result(webview_all_windows::FlutterError(
            kErrorScriptFailed, "Executing the script failed."));
      });
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::PostWebMessage(int64_t texture_id, const std::string &message) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->PostWebMessage(message)) {
    return webview_all_windows::FlutterError(kErrorNotSupported,
                                             "Posting the message failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetUserAgent(int64_t texture_id,
                             const std::string *user_agent) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->SetUserAgent(user_agent)) {
    return webview_all_windows::FlutterError(kErrorNotSupported,
                                             "Setting the user agent failed.");
  }
  return std::nullopt;
}

webview_all_windows::ErrorOr<std::optional<std::string>>
WindowsHostApi::GetUserAgent(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return webview_all_windows::FlutterError(kErrorCodeInvalidId);
  }
  return bridge->GetUserAgent();
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetJavaScriptEnabled(int64_t texture_id, bool enabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->SetJavaScriptEnabled(enabled)) {
    return webview_all_windows::FlutterError(kErrorNotSupported,
                                             "Setting JavaScript mode failed.");
  }
  return std::nullopt;
}

void WindowsHostApi::ClearCookies(
    int64_t texture_id,
    std::function<void(webview_all_windows::ErrorOr<bool> reply)> result) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return result(webview_all_windows::FlutterError(kErrorCodeInvalidId));
  }
  bridge->ClearCookies(
      [result = std::move(result)](bool success, bool had_cookies) mutable {
        if (success) {
          return result(had_cookies);
        }
        return result(webview_all_windows::FlutterError(kErrorMethodFailed));
      });
}

std::optional<webview_all_windows::FlutterError> WindowsHostApi::SetCookie(
    int64_t texture_id, const webview_all_windows::WindowsCookieData &cookie) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  WebviewCookie native_cookie{cookie.name(), cookie.value(), cookie.domain(),
                              cookie.path()};
  if (cookie.expires()) {
    native_cookie.expires = *cookie.expires();
  }
  if (cookie.is_http_only()) {
    native_cookie.is_http_only = *cookie.is_http_only();
  }
  if (cookie.is_secure()) {
    native_cookie.is_secure = *cookie.is_secure();
  }
  if (cookie.same_site()) {
    native_cookie.same_site = *cookie.same_site();
  }
  if (!bridge->SetCookie(native_cookie)) {
    return MethodFailedError();
  }
  return std::nullopt;
}

void WindowsHostApi::GetCookies(
    int64_t texture_id, const std::string &url,
    std::function<
        void(webview_all_windows::ErrorOr<flutter::EncodableList> reply)>
        result) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return result(webview_all_windows::FlutterError(kErrorCodeInvalidId));
  }
  bridge->GetCookies(url, [result = std::move(result)](
                              bool success,
                              std::vector<WebviewCookie> cookies) mutable {
    if (!success) {
      return result(webview_all_windows::FlutterError(kErrorMethodFailed));
    }
    flutter::EncodableList encoded_cookies;
    encoded_cookies.reserve(cookies.size());
    for (const auto &cookie : cookies) {
      const double *expires =
          cookie.expires.has_value() ? &cookie.expires.value() : nullptr;
      const bool *is_http_only = cookie.is_http_only.has_value()
                                     ? &cookie.is_http_only.value()
                                     : nullptr;
      const bool *is_secure =
          cookie.is_secure.has_value() ? &cookie.is_secure.value() : nullptr;
      const int64_t *same_site =
          cookie.same_site.has_value() ? &cookie.same_site.value() : nullptr;
      const bool *is_session =
          cookie.is_session.has_value() ? &cookie.is_session.value() : nullptr;
      encoded_cookies.push_back(
          flutter::CustomEncodableValue(webview_all_windows::WindowsCookieData(
              cookie.name, cookie.value, cookie.domain, cookie.path, expires,
              is_http_only, is_secure, same_site, is_session)));
    }
    return result(std::move(encoded_cookies));
  });
}

std::optional<webview_all_windows::FlutterError> WindowsHostApi::DeleteCookie(
    int64_t texture_id, const webview_all_windows::WindowsCookieData &cookie) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  WebviewCookie native_cookie{cookie.name(), cookie.value(), cookie.domain(),
                              cookie.path()};
  if (cookie.expires()) {
    native_cookie.expires = *cookie.expires();
  }
  if (cookie.is_http_only()) {
    native_cookie.is_http_only = *cookie.is_http_only();
  }
  if (cookie.is_secure()) {
    native_cookie.is_secure = *cookie.is_secure();
  }
  if (cookie.same_site()) {
    native_cookie.same_site = *cookie.same_site();
  }
  if (!bridge->DeleteCookie(native_cookie)) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::DeleteCookiesWithNameAndUrl(int64_t texture_id,
                                            const std::string &name,
                                            const std::string &url) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->DeleteCookiesWithNameAndUrl(name, url)) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::DeleteCookiesWithNameDomainAndPath(int64_t texture_id,
                                                   const std::string &name,
                                                   const std::string &domain,
                                                   const std::string &path) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->DeleteCookiesWithNameDomainAndPath(name, domain, path)) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::ClearCache(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->ClearCache()) {
    return MethodFailedError();
  }
  return std::nullopt;
}

void WindowsHostApi::ClearLocalStorage(
    int64_t texture_id,
    std::function<void(std::optional<webview_all_windows::FlutterError> reply)>
        result) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return result(InvalidIdError());
  }

  bridge->ClearLocalStorage([result = std::move(result)](bool success) mutable {
    if (success) {
      return result(std::nullopt);
    }
    result(webview_all_windows::FlutterError(kErrorMethodFailed));
  });
}

void WindowsHostApi::ClearAllWebsiteData(
    int64_t texture_id,
    std::function<void(webview_all_windows::ErrorOr<bool> reply)> result) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return result(webview_all_windows::FlutterError(kErrorCodeInvalidId));
  }

  bridge->ClearAllWebsiteData(
      [result = std::move(result)](bool supported, bool success) mutable {
        if (!supported) {
          return result(false);
        }
        if (success) {
          return result(true);
        }
        result(webview_all_windows::FlutterError(kErrorMethodFailed));
      });
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetCacheDisabled(int64_t texture_id, bool disabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->SetCacheDisabled(disabled)) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::OpenDevTools(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->OpenDevTools()) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetBackgroundColor(int64_t texture_id, int64_t color) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->SetBackgroundColor(color)) {
    return webview_all_windows::FlutterError(
        kErrorNotSupported, "Setting the background color failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetZoomControlEnabled(int64_t texture_id, bool enabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->SetZoomControlEnabled(enabled)) {
    return webview_all_windows::FlutterError(
        kErrorNotSupported, "Setting the zoom control mode failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetZoomFactor(int64_t texture_id, double zoom_factor) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->SetZoomFactor(zoom_factor)) {
    return webview_all_windows::FlutterError(kErrorNotSupported,
                                             "Setting the zoom factor failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetPopupWindowPolicy(int64_t texture_id, int64_t policy) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetPopupWindowPolicy(policy);
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetNavigationRequestCallbacksEnabled(int64_t texture_id,
                                                     bool enabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetNavigationRequestCallbacksEnabled(enabled);
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetJavaScriptDialogCallbacksEnabled(int64_t texture_id,
                                                    bool alert, bool confirm,
                                                    bool prompt) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetJavaScriptDialogCallbacksEnabled(alert, confirm, prompt);
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::Suspend(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->Suspend()) {
    return MethodFailedError("Suspending the WebView failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::Resume(int64_t texture_id) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->Resume()) {
    return webview_all_windows::FlutterError(
        kErrorMethodFailed, "Resuming WebView graphics capture failed.");
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetVirtualHostNameMapping(
    int64_t texture_id,
    const webview_all_windows::WindowsVirtualHostMappingData &mapping) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetVirtualHostNameMapping(mapping.host_name(), mapping.path(),
                                    mapping.access_kind());
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::ClearVirtualHostNameMapping(int64_t texture_id,
                                            const std::string &host_name) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (!bridge->ClearVirtualHostNameMapping(host_name)) {
    return MethodFailedError();
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetFpsLimit(int64_t texture_id, int64_t max_fps) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetFpsLimit(max_fps);
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetPointerUpdate(
    int64_t texture_id,
    const webview_all_windows::WindowsPointerUpdateData &update) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetPointerUpdate(update.pointer(), update.event(), update.x(),
                           update.y(), update.size(), update.pressure());
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError> WindowsHostApi::SetCursorPos(
    int64_t texture_id, const webview_all_windows::WindowsPointData &position) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetCursorPos(position.x(), position.y());
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetPointerButton(
    int64_t texture_id,
    const webview_all_windows::WindowsPointerButtonData &button) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetPointerButtonState(button.button(), button.is_down());
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError> WindowsHostApi::SetScrollDelta(
    int64_t texture_id, const webview_all_windows::WindowsPointData &delta) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  bridge->SetScrollDelta(delta.x(), delta.y());
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetSize(int64_t texture_id,
                        const webview_all_windows::WindowsSizeData &size) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (const auto error =
          bridge->SetSize(size.width(), size.height(), size.scale_factor())) {
    return CreateInitializationError(error->code, error->stage, error->message,
                                     error->hresult, webview_runtime_version_);
  }
  return std::nullopt;
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetSurfaceAttached(int64_t texture_id, bool attached) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (const auto error = bridge->SetSurfaceAttached(attached)) {
    return CreateInitializationError(error->code, error->stage, error->message,
                                     error->hresult, webview_runtime_version_);
  }
  return std::nullopt;
}

std::optional<FlutterError> WindowsHostApi::EnsureWinrtRuntime() {
  if (runtime_ && runtime_->available()) {
    return std::nullopt;
  }

  runtime_ = std::make_unique<WinrtRuntime>(RO_INIT_SINGLETHREADED);
  if (runtime_->available()) {
    return std::nullopt;
  }

  std::string code = "winrt_runtime_unavailable";
  std::string stage = "winrt_runtime";
  std::string message =
      "The Windows Runtime libraries required by the WebView renderer are "
      "unavailable.";
  if (runtime_->failure() ==
      WinrtRuntimeFailure::kRuntimeInitializationFailed) {
    code = "winrt_initialization_failed";
    stage = "winrt_initialization";
    message = "Initializing the Windows Runtime apartment failed.";
  } else if (runtime_->failure() ==
             WinrtRuntimeFailure::kRequiredFunctionUnavailable) {
    stage = "winrt_functions";
    message = "Required Windows Runtime functions are unavailable.";
  }

  const HRESULT result = runtime_->initialization_hresult();
  runtime_.reset();
  return CreateInitializationError(code, stage, message, result);
}

std::optional<FlutterError> WindowsHostApi::EnsureRenderingPlatform() {
  if (const std::optional<FlutterError> runtime_error = EnsureWinrtRuntime()) {
    return runtime_error;
  }
  if (platform_ && platform_->IsSupported()) {
    return std::nullopt;
  }

  platform_ = std::make_unique<WebviewPlatform>(runtime_.get());
  if (platform_->IsSupported()) {
    return std::nullopt;
  }

  const std::optional<WebviewPlatformInitializationError> platform_error =
      platform_->error();
  platform_.reset();
  if (!platform_error.has_value()) {
    return CreateInitializationError(
        "windows_rendering_initialization_failed", "windows_rendering",
        "Initializing the Windows WebView rendering platform failed.", E_FAIL,
        webview_runtime_version_);
  }
  return CreateInitializationError(
      platform_error->code, platform_error->stage, platform_error->message,
      platform_error->hresult, webview_runtime_version_);
}

} // namespace webview_all_windows
