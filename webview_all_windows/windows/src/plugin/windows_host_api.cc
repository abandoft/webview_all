#include "plugin/windows_host_api.h"
#include "plugin/profile_name.h"
#include <mutex>
#include <algorithm>

#include <shellapi.h>
#include <shlobj.h>
#include <windows.h>

#include <cstdint>
#include <cmath>
#include <filesystem>
#include <functional>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>

#include "plugin/environment_request.h"
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

std::optional<FlutterError> SettingResult(const char *setting, HRESULT result) {
  if (SUCCEEDED(result)) {
    return std::nullopt;
  }
  return FlutterError(result == E_NOINTERFACE ? kErrorNotSupported
                                              : kErrorMethodFailed,
                      std::string("Applying ") + setting +
                          " failed (HRESULT: " + FormatHresult(result) + ").",
                      flutter::EncodableValue(flutter::EncodableMap{
                          {flutter::EncodableValue("setting"),
                           flutter::EncodableValue(setting)},
                          {flutter::EncodableValue("hresult"),
                           flutter::EncodableValue(FormatHresult(result))},
                      }));
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
  browser_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.abandoft.webview_all_windows/browser",
          &flutter::StandardMethodCodec::GetInstance());
  browser_channel_->SetMethodCallHandler(
      [weak = std::weak_ptr<LifetimeState>(lifetime_state_)](
          const flutter::MethodCall<flutter::EncodableValue> &call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        const auto state = weak.lock();
        if (!state || !state->owner) return;
        if (call.method_name() == "profileManagementCapabilities" || call.method_name() == "listProfiles" ||
            call.method_name() == "requestProfileDeletion") {
          state->owner->HandleProfileMethod(call, std::move(result)); return;
        }
        if (call.method_name() != "attachNewWindow") {
          result->NotImplemented();
          return;
        }
        const auto *args =
            call.arguments()
                ? std::get_if<flutter::EncodableMap>(call.arguments())
                : nullptr;
        if (!args) {
          result->Error("invalid_argument",
                        "Window attachment parameters are required.");
          return;
        }
        auto number = [args](const char *name) -> int64_t {
          const auto value = args->find(flutter::EncodableValue(name));
          if (value == args->end()) return -1;
          if (const auto *int_value = std::get_if<int32_t>(&value->second))
            return *int_value;
          if (const auto *large = std::get_if<int64_t>(&value->second))
            return *large;
          return -1;
        };
        const auto id = args->find(flutter::EncodableValue("requestId"));
        const auto *request_id =
            id == args->end() ? nullptr : std::get_if<std::string>(&id->second);
        auto *parent = state->owner->FindBridge(number("parentId"));
        auto *child = state->owner->FindBridge(number("childId"));
        result->Success(flutter::EncodableValue(
            parent && request_id &&
            parent->AttachNewWindow(*request_id, child)));
      });

  data_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.abandoft.webview_all_windows/data",
          &flutter::StandardMethodCodec::GetInstance());
  data_channel_->SetMethodCallHandler(
      [weak = std::weak_ptr<LifetimeState>(lifetime_state_)](
          const flutter::MethodCall<flutter::EncodableValue> &call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        const auto state = weak.lock();
        if (!state || !state->owner) return;
        if (call.method_name() != "clearWebsiteData") {
          result->NotImplemented();
          return;
        }
        int64_t kinds = -1;
        if (call.arguments()) {
          if (const auto *value = std::get_if<int32_t>(call.arguments()))
            kinds = *value;
          else if (const auto *value64 = std::get_if<int64_t>(call.arguments()))
            kinds = *value64;
        }
        if (kinds < 0 || (kinds & ~0x15eLL) != 0) {
          result->Error("invalid_argument", "Invalid website data categories.");
          return;
        }
        if (!state->owner->webview_host_) {
          result->Error("environment_unavailable",
                        "The WebView2 environment has not been initialized.");
          return;
        }
        auto reply =
            std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
                std::move(result));
        state->owner->webview_host_->ClearWebsiteData(
            static_cast<uint64_t>(kinds),
            [weak, reply](WebviewHostWebsiteDataClearingResult outcome) {
              const auto state = weak.lock();
              if (!state || !state->owner) return;
              if (outcome.supported && !outcome.succeeded)
                reply->Error("data_clearing_failed", outcome.message);
              else
                reply->Success(flutter::EncodableValue(outcome.supported));
            });
      });
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
  for (auto &entry : instances_) entry.second->DisableAsyncReplies();
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
  std::optional<EnvironmentConfiguration> requested;
  if (HasExplicitEnvironmentOptions(options.user_data_path(),
                                    options.browser_exe_path(),
                                    options.additional_arguments())) {
    requested = ResolveEnvironmentConfiguration(options);
  }
  const auto* active = environment_configuration_ ? &*environment_configuration_ :
      pending_environment_configuration_ ? &*pending_environment_configuration_ : nullptr;
  if (options.custom_schemes() && !requested) {
    requested = active ? *active : ResolveEnvironmentConfiguration(options);
    requested->custom_schemes = ResolveEnvironmentConfiguration(options).custom_schemes;
  }
  if (active && requested) {
    if (!options.custom_schemes() || std::includes(active->custom_schemes.begin(), active->custom_schemes.end(),
        requested->custom_schemes.begin(), requested->custom_schemes.end()))
      requested->custom_schemes = active->custom_schemes;
  }

  switch (SelectEnvironmentRequestAction(requested, webview_host_ != nullptr,
                                         environment_configuration_,
                                         pending_environment_configuration_)) {
  case EnvironmentRequestAction::reuse:
    result(std::nullopt);
    return;
  case EnvironmentRequestAction::wait:
    pending_environment_callbacks_.push_back(std::move(result));
    return;
  case EnvironmentRequestAction::conflict:
    result(webview_all_windows::FlutterError(
        kErrorCodeEnvironmentConfigurationConflict,
        webview_host_
            ? "The active WebView2 environment uses different configuration "
              "options."
            : "The WebView2 environment being initialized uses different "
              "configuration options."));
    return;
  case EnvironmentRequestAction::create:
    CreateEnvironment(requested ? *requested
                                : ResolveEnvironmentConfiguration(options),
                      std::move(result));
    return;
  }
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
  std::vector<std::string> schemes;
  if (options.custom_schemes()) for (const auto& value : *options.custom_schemes()) {
    const auto* name = std::get_if<std::string>(&value);
    schemes.push_back(name ? *name : "?invalid");
  }
  std::sort(schemes.begin(), schemes.end());
  schemes.erase(std::unique(schemes.begin(), schemes.end()), schemes.end());
  return EnvironmentConfiguration{
      NormalizeEnvironmentPath(std::move(user_data_path)),
      NormalizeEnvironmentPath(std::move(browser_exe_path)),
      NormalizeEnvironmentArguments(options.additional_arguments()), std::move(schemes)};
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
      }, configuration.custom_schemes);
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
    std::function<void(ErrorOr<WindowsCreateWebViewResult>)> result) {
  CreateWebViewForMode(std::move(result), false);
}

void WindowsHostApi::CreatePrivateWebView(
    std::function<void(ErrorOr<WindowsCreateWebViewResult>)> result) {
  CreateWebViewForMode(std::move(result), true);
}

void WindowsHostApi::CreateProfileWebView(const std::string& name, bool incognito,
    std::function<void(ErrorOr<WindowsCreateWebViewResult> reply)> result) {
  if (name.empty() || name.size() > 64 ||
      name.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-") != std::string::npos) {
    result(FlutterError("invalid_profile", "Profile names require 1-64 ASCII letters, numbers, underscores or hyphens.")); return;
  }
  if (ProfileDeletionPending(name)) {
    result(FlutterError("profile_deleting", "WebView2 is still deleting this profile. Close its browser process before reusing the name.")); return;
  }
  CreateWebViewForMode(std::move(result), incognito, util::Utf16FromUtf8(name));
}

void WindowsHostApi::IsIncognitoSupported(
    std::function<void(ErrorOr<bool>)> result) {
  if (webview_host_) { result(webview_host_->SupportsIncognito()); return; }
  // A capability query must not start a browser process and permanently lock
  // custom scheme registrations. The runtime floor for Environment10 is 101.
  const auto* selected = pending_environment_configuration_ ? &*pending_environment_configuration_ : nullptr;
  wil::unique_cotaskmem_string version;
  auto hr = GetAvailableCoreWebView2BrowserVersionString(
      selected && selected->browser_exe_path ? selected->browser_exe_path->c_str() : nullptr, version.put());
  int comparison = -1;
  if (SUCCEEDED(hr) && version) hr = CompareBrowserVersions(version.get(), L"101.0.1210.39", &comparison);
  result(SUCCEEDED(hr) && comparison >= 0);
}

void WindowsHostApi::CreateWebViewForMode(
    std::function<void(webview_all_windows::ErrorOr<
                       webview_all_windows::WindowsCreateWebViewResult>
                           reply)>
        result,
    bool incognito, std::optional<std::wstring> profile_name) {
  if (parent_window_ == nullptr || !IsWindow(parent_window_)) {
    return result(webview_all_windows::FlutterError(
        kErrorCodeInvalidParentWindow,
        "The Flutter view window is unavailable."));
  }

  if (webview_host_) {
    CreateWebViewWithEnvironment(std::move(result), incognito, profile_name);
    return;
  }

  EnvironmentInitializationCallback continue_creation =
      [lifetime_state = lifetime_state_, incognito, profile_name,
       result = std::move(result)](std::optional<FlutterError> error) mutable {
        WindowsHostApi *const owner = lifetime_state->owner;
        if (owner == nullptr) {
          return;
        }
        if (error.has_value()) {
          result(*error);
          return;
        }
        owner->CreateWebViewWithEnvironment(std::move(result), incognito, profile_name);
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
        result,
    bool incognito, std::optional<std::wstring> profile_name) {
  if (const std::optional<FlutterError> platform_error =
          EnsureRenderingPlatform()) {
    return result(*platform_error);
  }

  std::optional<std::wstring> native_name;
  if (profile_name) {
    native_name = ManagedProfileName(*profile_name);
    if (!native_name) return result(FlutterError("profile_name_failed", "Unable to prepare the native named profile."));
  }
  webview_host_->CreateWebview(
      parent_window_, platform_->compositor(),
      [lifetime_state = lifetime_state_, result = std::move(result), incognito, profile_name](
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

        if (!incognito && profile_name) {
          auto name = *profile_name;
          auto registry = owner->ProfileRegistryPath();
          auto profile = webview->GetProfile();
          wil::unique_cotaskmem_string path;
          if (!registry.empty() && profile && SUCCEEDED(profile->get_ProfilePath(path.put())) && path) {
            if (GetPrivateProfileIntW(name.c_str(), L"pending", 0, registry.c_str()) != 0) {
              return result(FlutterError("profile_deleting", "This profile is awaiting native deletion."));
            }
            wil::unique_cotaskmem_string native;
            if (FAILED(profile->get_ProfileName(native.put())) || !native ||
                !WritePrivateProfileStringW(name.c_str(), L"path", path.get(), registry.c_str()) ||
                !WritePrivateProfileStringW(name.c_str(), L"nativeName", native.get(), registry.c_str())) {
              return result(FlutterError("profile_registry_failed", "Unable to record ownership of the named profile."));
            }
          }
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
      },
      incognito, native_name);
}

namespace {
std::mutex deleting_profiles_mutex;
std::vector<std::wstring> deleting_profiles;
bool IsProfileDeletionInFlight(const std::wstring& path) {
  std::lock_guard<std::mutex> guard(deleting_profiles_mutex);
  return std::any_of(deleting_profiles.begin(), deleting_profiles.end(), [&](const auto& item) {
    return CompareStringOrdinal(item.c_str(), -1, path.c_str(), -1, TRUE) == CSTR_EQUAL;
  });
}
struct ProfileDeletionReservation {
  std::wstring path;
  wil::unique_handle lock;
  ProfileDeletionReservation(std::wstring profile, wil::unique_handle file_lock)
      : path(std::move(profile)), lock(std::move(file_lock)) {
    std::lock_guard<std::mutex> guard(deleting_profiles_mutex);
    deleting_profiles.push_back(path);
  }
  ~ProfileDeletionReservation() {
    std::lock_guard<std::mutex> guard(deleting_profiles_mutex);
    deleting_profiles.erase(std::remove(deleting_profiles.begin(), deleting_profiles.end(), path), deleting_profiles.end());
  }
};
bool ValidManagedProfile(const std::string& name) {
  return !name.empty() && name.size() <= 64 &&
      name.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-") == std::string::npos;
}
flutter::EncodableValue ProfileOutcome(const char* status, const std::string& description = "") {
  return flutter::EncodableValue(flutter::EncodableMap{
    {flutter::EncodableValue("status"), flutter::EncodableValue(status)},
    {flutter::EncodableValue("description"), flutter::EncodableValue(description)}});
}
std::wstring RegistryProfilePath(const std::wstring& registry, const std::wstring& name) {
  std::vector<wchar_t> value(32768);
  auto count = GetPrivateProfileStringW(name.c_str(), L"path", L"", value.data(), static_cast<DWORD>(value.size()), registry.c_str());
  return std::wstring(value.data(), count);
}
}
std::wstring WindowsHostApi::ProfileRegistryPath() {
  const auto* config = environment_configuration_ ? &*environment_configuration_ :
      pending_environment_configuration_ ? &*pending_environment_configuration_ : nullptr;
  auto directory = config ? config->user_data_path : GetDefaultDataDirectory();
  if (!directory) return L"";
  return (std::filesystem::path(*directory) / L"webview_all_profiles.ini").wstring();
}
bool WindowsHostApi::ProfileDeletionPending(const std::string& name) {
  auto registry = ProfileRegistryPath();
  if (registry.empty()) return false;
  auto wide = util::Utf16FromUtf8(name);
  auto path = RegistryProfilePath(registry, wide);
  if (!path.empty() && IsProfileDeletionInFlight(path)) return true;
  if (!GetPrivateProfileIntW(wide.c_str(), L"pending", 0, registry.c_str())) return false;
  std::error_code error;
  const bool exists = path.empty() || std::filesystem::exists(path, error);
  if (!exists && !error) { WritePrivateProfileStringW(wide.c_str(), nullptr, nullptr, registry.c_str()); return false; }
  return true;
}
void WindowsHostApi::HandleProfileMethod(const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "profileManagementCapabilities") {
    const auto* config = environment_configuration_ ? &*environment_configuration_ :
        pending_environment_configuration_ ? &*pending_environment_configuration_ : nullptr;
    wil::unique_cotaskmem_string version;
    auto hr = GetAvailableCoreWebView2BrowserVersionString(config && config->browser_exe_path ? config->browser_exe_path->c_str() : nullptr, version.put());
    int comparison = -1;
    if (SUCCEEDED(hr) && version) hr = CompareBrowserVersions(version.get(), L"120.0.0.0", &comparison);
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("listing"), flutter::EncodableValue(true)},
      {flutter::EncodableValue("deletion"), flutter::EncodableValue(SUCCEEDED(hr) && comparison >= 0)},
      {flutter::EncodableValue("limitation"), flutter::EncodableValue("Only plugin-owned named profiles are managed; names are case-insensitive. Close their views before deletion. WebView2 removes pending profile files after its browser process exits; a pending name cannot be reopened.")}})); return;
  }
  if (call.method_name() == "listProfiles") {
    auto registry = ProfileRegistryPath();
    std::vector<wchar_t> names(65536);
    auto count = registry.empty() ? 0 : GetPrivateProfileSectionNamesW(names.data(), static_cast<DWORD>(names.size()), registry.c_str());
    if (count >= names.size() - 2) { result->Error("profile_registry_failed", "The profile registry exceeded its supported size."); return; }
    flutter::EncodableList rows;
    for (const wchar_t* item = names.data(); *item; item += wcslen(item) + 1) {
      auto name = util::Utf8FromUtf16(item);
      if (!ValidManagedProfile(name)) continue;
      const bool pending = ProfileDeletionPending(name);
      auto path = RegistryProfilePath(registry, item);
      std::error_code error;
      if (path.empty() || (!std::filesystem::exists(path, error) && !error)) continue;
      rows.emplace_back(flutter::EncodableMap{
        {flutter::EncodableValue("name"), flutter::EncodableValue(name)},
        {flutter::EncodableValue("deletionPending"), flutter::EncodableValue(pending)}});
    }
    result->Success(flutter::EncodableValue(rows)); return;
  }
  const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
  auto entry = args ? args->find(flutter::EncodableValue("name")) : flutter::EncodableMap::const_iterator();
  const auto* name = args && entry != args->end() ? std::get_if<std::string>(&entry->second) : nullptr;
  if (!name || !ValidManagedProfile(*name)) { result->Success(ProfileOutcome("failed", "Invalid named profile; no data was deleted.")); return; }
  RequestProfileDeletion(*name, std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result)));
}
void WindowsHostApi::RequestProfileDeletion(const std::string& name,
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (ProfileDeletionPending(name)) { result->Success(ProfileOutcome("pending")); return; }
  auto registry = ProfileRegistryPath(), wide = util::Utf16FromUtf8(name);
  auto path = registry.empty() ? L"" : RegistryProfilePath(registry, wide);
  if (path.empty()) { result->Success(ProfileOutcome("notFound")); return; }
  if (Webview::IsProfileActive(path)) { result->Success(ProfileOutcome("busy", "Close this profile's views before requesting deletion.")); return; }
  if (!webview_host_) {
    auto resume = [state = lifetime_state_, name, result](std::optional<FlutterError> error) {
      if (!state->owner) return;
      if (error) { result->Success(ProfileOutcome("failed", "The WebView2 environment could not be initialized.")); return; }
      state->owner->RequestProfileDeletion(name, result);
    };
    if (pending_environment_configuration_) pending_environment_callbacks_.push_back(std::move(resume));
    else CreateEnvironment(ResolveEnvironmentConfiguration(WindowsEnvironmentOptions()), std::move(resume));
    return;
  }
  if (EnsureRenderingPlatform()) { result->Success(ProfileOutcome("failed", "The native controller could not be created.")); return; }
  auto lock = Webview::AcquireProfileDeletionLock(path);
  if (!lock) { result->Success(ProfileOutcome("busy", "Another process is using this profile, or its lock is inaccessible.")); return; }
  std::vector<wchar_t> stored_name(128);
  GetPrivateProfileStringW(wide.c_str(), L"nativeName", L"", stored_name.data(), static_cast<DWORD>(stored_name.size()), registry.c_str());
  std::wstring native_name = stored_name.data();
  // Earlier local builds recorded only the verified SDK path. Keep those
  // plugin-owned profiles manageable without guessing arbitrary SDK names.
  if (native_name.empty()) native_name = std::filesystem::path(path).filename().wstring();
  if (native_name.rfind(L"webview_all_", 0) != 0 || native_name.size() > 64) {
    result->Success(ProfileOutcome("failed", "The native profile mapping is unavailable.")); return;
  }
  // Probe registry writability without claiming that SDK deletion has begun.
  // Only persist pending=1 after Delete succeeds: closing an engine during
  // controller creation must not strand a profile in a durable pending state.
  if (!WritePrivateProfileStringW(wide.c_str(), L"pending", L"0", registry.c_str())) {
    result->Success(ProfileOutcome("failed", "Unable to record profile management state; no deletion was requested.")); return;
  }
  auto reservation = std::make_shared<ProfileDeletionReservation>(path, std::move(lock));
  webview_host_->CreateWebview(parent_window_, platform_->compositor(),
      [state = lifetime_state_, result, registry, wide, path, reservation](std::unique_ptr<Webview> view,
          std::unique_ptr<WebviewCreationError>) {
        (void)reservation;  // Hold the exclusive profile lock through the SDK callback.
        if (!state->owner) return;
        auto profile = view ? view->GetProfile() : nullptr;
        auto profile8 = profile ? profile.try_query<ICoreWebView2Profile8>() : nullptr;
        wil::unique_cotaskmem_string actual;
        if (profile) profile->get_ProfilePath(actual.put());
        if (!actual || CompareStringOrdinal(actual.get(), -1, path.c_str(), -1, TRUE) != CSTR_EQUAL) {
          result->Success(ProfileOutcome("failed", "The native profile identity could not be verified.")); return;
        }
        if (Webview::IsProfileActive(path, view.get())) {
          result->Success(ProfileOutcome("busy", "Another view opened this profile before deletion could begin.")); return;
        }
        const auto hr = profile8 ? profile8->Delete() : E_NOINTERFACE;
        if (FAILED(hr)) {
          result->Success(ProfileOutcome(hr == E_NOINTERFACE ? "unsupported" : "failed", "WebView2 did not accept profile deletion.")); return;
        }
        if (!WritePrivateProfileStringW(wide.c_str(), L"pending", L"1", registry.c_str())) {
          result->Success(ProfileOutcome("pending", "WebView2 accepted deletion, but its pending state could not be saved. Wait for the browser process to exit before reopening this profile.")); return;
        }
        result->Success(ProfileOutcome("pending", "WebView2 accepted deletion. Its browser process must exit before the profile files and name can be reused."));
      }, false, native_name, true);
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
  const HRESULT result = bridge->LoadStringContent(content);
  if (FAILED(result)) {
    return FlutterError(
        kErrorMethodFailed,
        "Loading HTML content failed (HRESULT: " + FormatHresult(result) + ").",
        flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("operation"),
             flutter::EncodableValue("NavigateToString")},
            {flutter::EncodableValue("hresult"),
             flutter::EncodableValue(FormatHresult(result))},
        }));
  }
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
WindowsHostApi::SetDevToolsEnabled(int64_t texture_id, bool enabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  return SettingResult("devToolsEnabled", bridge->SetDevToolsEnabled(enabled));
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetBrowserAcceleratorKeysEnabled(int64_t texture_id,
                                                 bool enabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  return SettingResult("browserAcceleratorKeysEnabled",
                       bridge->SetBrowserAcceleratorKeysEnabled(enabled));
}

std::optional<webview_all_windows::FlutterError>
WindowsHostApi::SetDownloadsEnabled(int64_t texture_id, bool enabled) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  return SettingResult("downloadsEnabled",
                       bridge->SetDownloadsEnabled(enabled));
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
  // A view can move beneath a stationary pointer. Use the coordinates carried
  // by this button event, rather than the last hover event's old local point.
  if (const auto* point = button.position();
      point && std::isfinite(point->x()) && std::isfinite(point->y())) {
    bridge->SetCursorPos(point->x(), point->y());
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
          bridge->SetSize(size.width(), size.height(), size.scale_factor(),
                          size.origin() ? std::optional<SurfaceOrigin>(
                              SurfaceOrigin{size.origin()->x(), size.origin()->y()})
                                        : std::nullopt)) {
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

std::optional<FlutterError>
WindowsHostApi::SetFocus(int64_t texture_id, bool focused, int64_t reason) {
  auto bridge = FindBridge(texture_id);
  if (!bridge) {
    return InvalidIdError();
  }
  if (FAILED(bridge->SetFocus(focused, reason))) {
    return MethodFailedError("Updating the WebView focus failed.");
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
