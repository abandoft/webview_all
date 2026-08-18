#pragma once

#include <WebView2.h>
#include <wil/com.h>
#include <windows.ui.composition.h>
#include <winrt/base.h>

#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

namespace webview_all_windows {

class WebviewHost;

enum class WebviewLoadingState { None, Loading, NavigationCompleted };

enum class WebviewPointerButton { None, Primary, Secondary, Tertiary };

enum class WebviewPointerEventKind { Activate, Down, Enter, Leave, Up, Update };

enum class WebviewDownloadEventKind {
  DownloadStarted,
  DownloadCompleted,
  DownloadProgress
};

enum class WebviewPermissionKind {
  Unknown,
  Microphone,
  Camera,
  GeoLocation,
  Notifications,
  OtherSensors,
  ClipboardRead
};

enum class WebviewPermissionState { Default, Allow, Deny };

enum class WebviewPopupWindowPolicy { Allow, Deny, ShowInSameWindow };

enum class WebviewHostResourceAccessKind { Deny, Allow, DenyCors };

enum class WebviewJavaScriptDialogKind { Alert, Confirm, Prompt, BeforeUnload };

struct WebviewHistoryChanged {
  BOOL can_go_back;
  BOOL can_go_forward;
};

struct WebviewDownloadEvent {
  WebviewDownloadEventKind kind;
  std::string url;
  std::string resultFilePath;
  INT64 bytesReceived;
  INT64 totalBytesToReceive;
};

struct WebviewCookie {
  std::string name;
  std::string value;
  std::string domain;
  std::string path;
  std::optional<double> expires;
  std::optional<bool> is_http_only;
  std::optional<bool> is_secure;
  std::optional<int64_t> same_site;
  std::optional<bool> is_session;
};

struct WebviewJavaScriptDialogRequest {
  WebviewJavaScriptDialogKind kind;
  std::string url;
  std::string message;
  std::optional<std::string> default_text;
};

struct WebviewHttpResponseError {
  std::string url;
  std::string method;
  std::map<std::string, std::string> request_headers;
  int status_code;
  std::map<std::string, std::string> response_headers;
  std::optional<std::string> reason_phrase;
};

struct WebviewHttpAuthRequest {
  std::string url;
  std::string challenge;
};

struct WebviewSslAuthError {
  std::string url;
  COREWEBVIEW2_WEB_ERROR_STATUS status;
};

struct VirtualKeyState {
public:
  inline void set_isLeftButtonDown(bool is_down) {
    set(COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS::
            COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_LEFT_BUTTON,
        is_down);
  }

  inline void set_isRightButtonDown(bool is_down) {
    set(COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS::
            COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_RIGHT_BUTTON,
        is_down);
  }

  inline void set_isMiddleButtonDown(bool is_down) {
    set(COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS::
            COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_MIDDLE_BUTTON,
        is_down);
  }

  inline COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS state() const { return state_; }

private:
  COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS state_ =
      COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS::
          COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_NONE;

  inline void set(COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS key, bool flag) {
    if (flag) {
      state_ |= key;
    } else {
      state_ &= ~key;
    }
  }
};

struct EventRegistrations {
  EventRegistrationToken source_changed_token_{};
  EventRegistrationToken content_loading_token_{};
  EventRegistrationToken navigation_starting_token_{};
  EventRegistrationToken navigation_completed_token_{};
  EventRegistrationToken history_changed_token_{};
  EventRegistrationToken document_title_changed_token_{};
  EventRegistrationToken cursor_changed_token_{};
  EventRegistrationToken got_focus_token_{};
  EventRegistrationToken lost_focus_token_{};
  EventRegistrationToken web_message_received_token_{};
  EventRegistrationToken web_resource_response_received_token_{};
  EventRegistrationToken basic_authentication_requested_token_{};
  EventRegistrationToken server_certificate_error_detected_token_{};
  EventRegistrationToken permission_requested_token_{};
  EventRegistrationToken script_dialog_opening_token_{};
  EventRegistrationToken devtools_protocol_event_token_{};
  EventRegistrationToken new_windows_requested_token_{};
  EventRegistrationToken contains_fullscreen_element_changed_token_{};
  EventRegistrationToken download_starting_token_{};
};

class Webview {
public:
  friend class WebviewHost;

  typedef std::function<void(const std::string &)> UrlChangedCallback;
  typedef std::function<void(WebviewLoadingState)> LoadingStateChangedCallback;
  typedef std::function<void(COREWEBVIEW2_WEB_ERROR_STATUS)>
      OnLoadErrorCallback;
  typedef std::function<void(const WebviewHttpResponseError &)>
      HttpResponseErrorCallback;
  typedef std::function<void(WebviewHistoryChanged)> HistoryChangedCallback;
  typedef std::function<void(const std::string &)>
      DevtoolsProtocolEventCallback;
  typedef std::function<void(const std::string &)> DocumentTitleChangedCallback;
  typedef std::function<void(size_t width, size_t height)>
      SurfaceSizeChangedCallback;
  typedef std::function<void(const HCURSOR)> CursorChangedCallback;
  typedef std::function<void(bool)> FocusChangedCallback;
  typedef std::function<void(bool, const std::string &)>
      AddScriptToExecuteOnDocumentCreatedCallback;
  typedef std::function<void(bool, const std::string &)> ScriptExecutedCallback;
  typedef std::function<void(bool)> OperationCompletedCallback;
  typedef std::function<void(const std::string &)> WebMessageReceivedCallback;
  typedef std::function<void(WebviewPermissionState state)>
      WebviewPermissionRequestedCompleter;
  typedef std::function<void(bool allow)> WebviewNavigationRequestedCompleter;
  typedef std::function<void(const std::string &url, bool is_user_initiated,
                             bool is_redirected,
                             WebviewNavigationRequestedCompleter completer)>
      NavigationRequestedCallback;
  typedef std::function<void(bool accepted, const std::string &user,
                             const std::string &password)>
      WebviewHttpAuthRequestedCompleter;
  typedef std::function<void(const WebviewHttpAuthRequest &request,
                             WebviewHttpAuthRequestedCompleter completer)>
      HttpAuthRequestedCallback;
  typedef std::function<void(bool proceed)> WebviewSslAuthErrorCompleter;
  typedef std::function<void(const WebviewSslAuthError &error,
                             WebviewSslAuthErrorCompleter completer)>
      SslAuthErrorCallback;
  typedef std::function<void(const std::string &url, WebviewPermissionKind kind,
                             bool is_user_initiated,
                             WebviewPermissionRequestedCompleter completer)>
      PermissionRequestedCallback;
  typedef std::function<void(bool accepted,
                             const std::optional<std::string> &text)>
      WebviewJavaScriptDialogCompleter;
  typedef std::function<void(const WebviewJavaScriptDialogRequest &request,
                             WebviewJavaScriptDialogCompleter completer)>
      JavaScriptDialogRequestedCallback;
  typedef std::function<void(bool contains_fullscreen_element)>
      ContainsFullScreenElementChangedCallback;
  typedef std::function<void(WebviewDownloadEvent)> DownloadEventCallback;
  typedef std::function<void(bool success, bool had_cookies)>
      CookiesClearedCallback;
  typedef std::function<void(bool success, std::vector<WebviewCookie> cookies)>
      CookiesRetrievedCallback;

  ~Webview();

  ABI::Windows::UI::Composition::IVisual *const surface() {
    return surface_.get();
  }

  bool IsValid() { return is_valid_; }

  bool SetSurfaceSize(size_t width, size_t height, float scale_factor);
  bool SetVisible(bool visible);
  void NotifyParentWindowPositionChanged();
  void SetCursorPos(double x, double y);
  void SetPointerUpdate(int32_t pointer, WebviewPointerEventKind eventKind,
                        double x, double y, double size, double pressure);
  void SetPointerButtonState(WebviewPointerButton button, bool isDown);
  void SetScrollDelta(double delta_x, double delta_y);
  void LoadUrl(const std::string &url);
  bool LoadRequest(const std::string &url, const std::string &method,
                   const std::string &headers,
                   const std::vector<uint8_t> *body);
  void LoadStringContent(const std::string &content);
  bool Stop();
  bool Reload();
  bool GoBack();
  bool GoForward();
  void AddScriptToExecuteOnDocumentCreated(
      const std::string &script,
      AddScriptToExecuteOnDocumentCreatedCallback callback);
  void RemoveScriptToExecuteOnDocumentCreated(const std::string &script_id);
  void ExecuteScript(const std::string &script,
                     ScriptExecutedCallback callback);
  bool PostWebMessage(const std::string &json);
  void ClearCookies(CookiesClearedCallback callback);
  bool SetCookie(const WebviewCookie &cookie);
  void GetCookies(const std::string &url, CookiesRetrievedCallback callback);
  bool DeleteCookie(const WebviewCookie &cookie);
  bool DeleteCookiesWithNameAndUrl(const std::string &name,
                                   const std::string &url);
  bool DeleteCookiesWithNameDomainAndPath(const std::string &name,
                                          const std::string &domain,
                                          const std::string &path);
  bool ClearCache();
  void ClearLocalStorage(OperationCompletedCallback callback);
  bool SetCacheDisabled(bool disabled);
  void SetPopupWindowPolicy(WebviewPopupWindowPolicy policy);
  void SetNavigationRequestCallbacksEnabled(bool enabled);
  bool SetUserAgent(const std::string *user_agent);
  std::optional<std::string> GetUserAgent();
  bool SetJavaScriptEnabled(bool enabled);
  bool SetZoomControlEnabled(bool enabled);
  bool OpenDevTools();
  bool SetBackgroundColor(int32_t color);
  bool SetZoomFactor(double factor);
  bool Suspend();
  bool Resume();
  void SetJavaScriptDialogCallbacksEnabled(bool alert, bool confirm,
                                           bool prompt);

  bool SetVirtualHostNameMapping(const std::string &hostName,
                                 const std::string &path,
                                 WebviewHostResourceAccessKind accessKind);
  bool ClearVirtualHostNameMapping(const std::string &hostName);

  void UpdateDownloadProgress(ICoreWebView2DownloadOperation *download);

  void OnUrlChanged(UrlChangedCallback callback) {
    url_changed_callback_ = std::move(callback);
  }

  void OnLoadError(OnLoadErrorCallback callback) {
    on_load_error_callback_ = std::move(callback);
  }

  void OnHttpResponseError(HttpResponseErrorCallback callback) {
    http_response_error_callback_ = std::move(callback);
  }

  void OnLoadingStateChanged(LoadingStateChangedCallback callback) {
    loading_state_changed_callback_ = std::move(callback);
  }

  void OnDownloadEvent(DownloadEventCallback callback) {
    download_event_callback_ = std::move(callback);
  }

  void OnHistoryChanged(HistoryChangedCallback callback) {
    history_changed_callback_ = std::move(callback);
  }

  void OnSurfaceSizeChanged(SurfaceSizeChangedCallback callback) {
    surface_size_changed_callback_ = std::move(callback);
  }

  void OnDocumentTitleChanged(DocumentTitleChangedCallback callback) {
    document_title_changed_callback_ = std::move(callback);
  }

  void OnCursorChanged(CursorChangedCallback callback) {
    cursor_changed_callback_ = std::move(callback);
  }

  void OnFocusChanged(FocusChangedCallback callback) {
    focus_changed_callback_ = std::move(callback);
  }

  void OnWebMessageReceived(WebMessageReceivedCallback callback) {
    web_message_received_callback_ = std::move(callback);
  }

  void OnPermissionRequested(PermissionRequestedCallback callback) {
    permission_requested_callback_ = std::move(callback);
  }

  void OnNavigationRequested(NavigationRequestedCallback callback) {
    navigation_requested_callback_ = std::move(callback);
  }

  void OnHttpAuthRequested(HttpAuthRequestedCallback callback) {
    http_auth_requested_callback_ = std::move(callback);
  }

  void OnSslAuthError(SslAuthErrorCallback callback) {
    ssl_auth_error_callback_ = std::move(callback);
  }

  void OnJavaScriptDialogRequested(JavaScriptDialogRequestedCallback callback) {
    java_script_dialog_requested_callback_ = std::move(callback);
  }

  void OnDevtoolsProtocolEvent(DevtoolsProtocolEventCallback callback) {
    devtools_protocol_event_callback_ = std::move(callback);
  }

  void OnContainsFullScreenElementChanged(
      ContainsFullScreenElementChangedCallback callback) {
    contains_fullscreen_element_changed_callback_ = std::move(callback);
  }

private:
  struct LifetimeState {
    Webview *owner = nullptr;
  };

  HWND parent_window_;
  bool is_valid_ = false;
  float scale_factor_ = 1.0;
  size_t surface_width_ = 1280;
  size_t surface_height_ = 720;
  wil::com_ptr<ICoreWebView2CompositionController> composition_controller_;
  wil::com_ptr<ICoreWebView2Controller3> webview_controller_;
  wil::com_ptr<ICoreWebView2> webview_;
  wil::com_ptr<ICoreWebView2DevToolsProtocolEventReceiver>
      devtools_protocol_event_receiver_;
  wil::com_ptr<ICoreWebView2Settings> settings_;
  wil::com_ptr<ICoreWebView2Settings2> settings2_;
  std::string default_user_agent_;
  POINT last_cursor_pos_ = {0, 0};
  VirtualKeyState virtual_keys_;
  WebviewPopupWindowPolicy popup_window_policy_ =
      WebviewPopupWindowPolicy::Allow;
  bool java_script_alert_dialog_enabled_ = false;
  bool java_script_confirm_dialog_enabled_ = false;
  bool java_script_prompt_dialog_enabled_ = false;
  bool navigation_request_callbacks_enabled_ = false;
  uint64_t latest_navigation_request_id_ = 0;
  size_t bypass_next_navigation_count_ = 0;
  std::unordered_multiset<std::string> approved_navigation_urls_;
  std::unordered_set<uint64_t> policy_cancelled_navigation_ids_;
  double horizontal_scroll_remainder_ = 0.0;
  double vertical_scroll_remainder_ = 0.0;
  std::shared_ptr<LifetimeState> lifetime_state_ =
      std::make_shared<LifetimeState>();

  winrt::com_ptr<ABI::Windows::UI::Composition::IVisual> surface_;

  std::shared_ptr<WebviewHost> host_;
  EventRegistrations event_registrations_{};

  UrlChangedCallback url_changed_callback_;
  LoadingStateChangedCallback loading_state_changed_callback_;
  DownloadEventCallback download_event_callback_;
  OnLoadErrorCallback on_load_error_callback_;
  HttpResponseErrorCallback http_response_error_callback_;
  HistoryChangedCallback history_changed_callback_;
  DocumentTitleChangedCallback document_title_changed_callback_;
  SurfaceSizeChangedCallback surface_size_changed_callback_;
  CursorChangedCallback cursor_changed_callback_;
  FocusChangedCallback focus_changed_callback_;
  WebMessageReceivedCallback web_message_received_callback_;
  PermissionRequestedCallback permission_requested_callback_;
  NavigationRequestedCallback navigation_requested_callback_;
  HttpAuthRequestedCallback http_auth_requested_callback_;
  SslAuthErrorCallback ssl_auth_error_callback_;
  JavaScriptDialogRequestedCallback java_script_dialog_requested_callback_;
  DevtoolsProtocolEventCallback devtools_protocol_event_callback_;
  ContainsFullScreenElementChangedCallback
      contains_fullscreen_element_changed_callback_;

  Webview(
      wil::com_ptr<ICoreWebView2CompositionController> composition_controller,
      std::shared_ptr<WebviewHost> host, HWND parent_window);

  bool CreateSurface(
      winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor);
  std::optional<RECT> CalculateOffscreenBounds(size_t width, size_t height,
                                               float scale_factor) const;
  bool UpdateControllerBounds(size_t width, size_t height, float scale_factor);
  void RegisterEventHandlers();
  void InvalidatePendingNavigationRequests();
  void MarkNavigationApproved(const std::string &url);
  bool ConsumeApprovedNavigation(const std::string &url);
  void ResumeNavigation(uint64_t request_id, const std::string &url);
  void EnableSecurityUpdates();
  void SendScroll(double offset, bool horizontal);
  wil::com_ptr<ICoreWebView2CookieManager> GetCookieManager();
};

} // namespace webview_all_windows
