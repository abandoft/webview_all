#pragma once

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "platform/webview_platform.h"
#include "webview/webview_bridge.h"
#include "webview/webview_host.h"
#include "windows_webview_api.g.h"

namespace webview_all_windows {

class WindowsHostApi : public flutter::Plugin, public WindowsWebViewHostApi {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar,
                                    HWND parent_window);

  WindowsHostApi(flutter::TextureRegistrar *textures,
                 flutter::BinaryMessenger *messenger, HWND parent_window);
  ~WindowsHostApi() override;

private:
  struct EnvironmentConfiguration {
    std::optional<std::wstring> user_data_path;
    std::optional<std::wstring> browser_exe_path;
    std::optional<std::string> additional_arguments;

    bool operator==(const EnvironmentConfiguration &other) const {
      return PathsEqual(user_data_path, other.user_data_path) &&
             PathsEqual(browser_exe_path, other.browser_exe_path) &&
             additional_arguments == other.additional_arguments;
    }

  private:
    static bool PathsEqual(const std::optional<std::wstring> &left,
                           const std::optional<std::wstring> &right) {
      if (left.has_value() != right.has_value()) {
        return false;
      }
      return !left || CompareStringOrdinal(left->c_str(), -1, right->c_str(),
                                           -1, TRUE) == CSTR_EQUAL;
    }
  };

  struct LifetimeState {
    WindowsHostApi *owner = nullptr;
  };

  using EnvironmentInitializationCallback =
      std::function<void(std::optional<FlutterError>)>;

  std::unique_ptr<WinrtRuntime> runtime_;
  std::unique_ptr<WebviewPlatform> platform_;
  std::shared_ptr<WebviewHost> webview_host_;
  std::optional<std::string> webview_runtime_version_;
  std::optional<EnvironmentConfiguration> environment_configuration_;
  std::optional<EnvironmentConfiguration> pending_environment_configuration_;
  std::vector<EnvironmentInitializationCallback> pending_environment_callbacks_;
  std::unordered_map<int64_t, std::unique_ptr<WebviewBridge>> instances_;

  flutter::TextureRegistrar *textures_;
  flutter::BinaryMessenger *messenger_;
  flutter::PluginRegistrarWindows *registrar_ = nullptr;
  HWND parent_window_ = nullptr;
  int window_proc_delegate_id_ = -1;
  std::shared_ptr<LifetimeState> lifetime_state_ =
      std::make_shared<LifetimeState>();

  std::optional<FlutterError> EnsureWinrtRuntime();
  std::optional<FlutterError> EnsureRenderingPlatform();
  EnvironmentConfiguration
  ResolveEnvironmentConfiguration(const WindowsEnvironmentOptions &options);
  void CreateEnvironment(const EnvironmentConfiguration &configuration,
                         EnvironmentInitializationCallback callback);
  void
  CompleteEnvironmentCreation(const EnvironmentConfiguration &configuration,
                              WebviewHostCreationResult creation_result);
  void CreateWebViewWithEnvironment(
      std::function<void(ErrorOr<WindowsCreateWebViewResult> reply)> result);
  void NotifyParentWindowPositionChanged();
  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam);

  void InitializeEnvironment(
      const WindowsEnvironmentOptions &options,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void EnsureEnvironment(
      const WindowsEnvironmentOptions &options,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  ErrorOr<std::optional<std::string>> GetWebViewVersion() override;
  std::optional<FlutterError> OpenWebView2DownloadPage() override;
  void ClearAllWebsiteDataForEnvironment(
      std::function<void(ErrorOr<bool> reply)> result) override;
  void CreateWebView(
      std::function<void(ErrorOr<WindowsCreateWebViewResult> reply)> result)
      override;
  std::optional<FlutterError> DisposeWebView(int64_t texture_id) override;
  std::optional<FlutterError> LoadUrl(int64_t texture_id,
                                      const std::string &url) override;
  std::optional<FlutterError>
  LoadRequest(int64_t texture_id,
              const WindowsLoadRequestData &request) override;
  std::optional<FlutterError>
  LoadStringContent(int64_t texture_id, const std::string &content) override;
  std::optional<FlutterError> Reload(int64_t texture_id) override;
  std::optional<FlutterError> Stop(int64_t texture_id) override;
  std::optional<FlutterError> GoBack(int64_t texture_id) override;
  std::optional<FlutterError> GoForward(int64_t texture_id) override;
  void AddScriptToExecuteOnDocumentCreated(
      int64_t texture_id, const std::string &script,
      std::function<void(ErrorOr<std::optional<std::string>> reply)> result)
      override;
  std::optional<FlutterError>
  RemoveScriptToExecuteOnDocumentCreated(int64_t texture_id,
                                         const std::string &script_id) override;
  void ExecuteScript(
      int64_t texture_id, const std::string &script,
      std::function<void(ErrorOr<std::string> reply)> result) override;
  std::optional<FlutterError>
  PostWebMessage(int64_t texture_id, const std::string &message) override;
  std::optional<FlutterError>
  SetUserAgent(int64_t texture_id, const std::string *user_agent) override;
  ErrorOr<std::optional<std::string>> GetUserAgent(int64_t texture_id) override;
  std::optional<FlutterError> SetJavaScriptEnabled(int64_t texture_id,
                                                   bool enabled) override;
  void ClearCookies(int64_t texture_id,
                    std::function<void(ErrorOr<bool> reply)> result) override;
  std::optional<FlutterError>
  SetCookie(int64_t texture_id, const WindowsCookieData &cookie) override;
  void GetCookies(int64_t texture_id, const std::string &url,
                  std::function<void(ErrorOr<flutter::EncodableList> reply)>
                      result) override;
  std::optional<FlutterError>
  DeleteCookie(int64_t texture_id, const WindowsCookieData &cookie) override;
  std::optional<FlutterError>
  DeleteCookiesWithNameAndUrl(int64_t texture_id, const std::string &name,
                              const std::string &url) override;
  std::optional<FlutterError> DeleteCookiesWithNameDomainAndPath(
      int64_t texture_id, const std::string &name, const std::string &domain,
      const std::string &path) override;
  std::optional<FlutterError> ClearCache(int64_t texture_id) override;
  void ClearLocalStorage(
      int64_t texture_id,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void
  ClearAllWebsiteData(int64_t texture_id,
                      std::function<void(ErrorOr<bool> reply)> result) override;
  std::optional<FlutterError> SetCacheDisabled(int64_t texture_id,
                                               bool disabled) override;
  std::optional<FlutterError> OpenDevTools(int64_t texture_id) override;
  std::optional<FlutterError> SetBackgroundColor(int64_t texture_id,
                                                 int64_t color) override;
  std::optional<FlutterError> SetZoomControlEnabled(int64_t texture_id,
                                                    bool enabled) override;
  std::optional<FlutterError> SetZoomFactor(int64_t texture_id,
                                            double zoom_factor) override;
  std::optional<FlutterError> SetPopupWindowPolicy(int64_t texture_id,
                                                   int64_t policy) override;
  std::optional<FlutterError>
  SetNavigationRequestCallbacksEnabled(int64_t texture_id,
                                       bool enabled) override;
  std::optional<FlutterError>
  SetJavaScriptDialogCallbacksEnabled(int64_t texture_id, bool alert,
                                      bool confirm, bool prompt) override;
  std::optional<FlutterError> Suspend(int64_t texture_id) override;
  std::optional<FlutterError> Resume(int64_t texture_id) override;
  std::optional<FlutterError> SetVirtualHostNameMapping(
      int64_t texture_id,
      const WindowsVirtualHostMappingData &mapping) override;
  std::optional<FlutterError>
  ClearVirtualHostNameMapping(int64_t texture_id,
                              const std::string &host_name) override;
  std::optional<FlutterError> SetFpsLimit(int64_t texture_id,
                                          int64_t max_fps) override;
  std::optional<FlutterError>
  SetPointerUpdate(int64_t texture_id,
                   const WindowsPointerUpdateData &update) override;
  std::optional<FlutterError>
  SetCursorPos(int64_t texture_id, const WindowsPointData &position) override;
  std::optional<FlutterError>
  SetPointerButton(int64_t texture_id,
                   const WindowsPointerButtonData &button) override;
  std::optional<FlutterError>
  SetScrollDelta(int64_t texture_id, const WindowsPointData &delta) override;
  std::optional<FlutterError> SetSize(int64_t texture_id,
                                      const WindowsSizeData &size) override;
  std::optional<FlutterError> SetSurfaceAttached(int64_t texture_id,
                                                 bool attached) override;

  WebviewBridge *FindBridge(int64_t texture_id);
  std::optional<FlutterError> InvalidIdError();
  std::optional<FlutterError>
  MethodFailedError(const std::string &message = "");
};

} // namespace webview_all_windows
