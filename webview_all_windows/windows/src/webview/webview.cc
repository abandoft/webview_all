#include "webview/webview.h"
#include <mutex>

#include <wrl.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <limits>
#include <map>
#include <memory>
#include <utility>

#include <winrt/Windows.Foundation.h>

#include "util/logging.h"
#include "util/string_converter.h"
#include "webview/webview_host.h"

using namespace Microsoft::WRL;

namespace webview_all_windows {
namespace {

std::map<UINT_PTR, std::function<void()>> &WebviewTimers() {
  static auto *timers = new std::map<UINT_PTR, std::function<void()>>();
  return *timers;
}

void CALLBACK WebviewTimerProc(HWND, UINT, UINT_PTR id, DWORD) {
  auto &timers = WebviewTimers();
  const auto found = timers.find(id);
  if (found == timers.end())
    return;
  auto callback = std::move(found->second);
  timers.erase(found);
  KillTimer(nullptr, id);
  callback();
}

UINT_PTR ScheduleWebviewTimeout(std::function<void()> callback,
                                UINT delay_ms = 35000) {
  const UINT_PTR id = SetTimer(nullptr, 0, delay_ms, WebviewTimerProc);
  if (id != 0) WebviewTimers().emplace(id, std::move(callback));
  return id;
}

void CancelWebviewTimeout(UINT_PTR id) {
  if (id == 0)
    return;
  KillTimer(nullptr, id);
  WebviewTimers().erase(id);
}

bool PrepareDownloadTarget(const std::string &requested,
                           std::wstring &directory, std::wstring &temporary,
                           std::wstring &target) {
  if (requested.empty() || requested.find('\0') != std::string::npos)
    return false;
  const std::filesystem::path path =
      std::filesystem::path(util::Utf16FromUtf8(requested)).lexically_normal();
  if (!path.is_absolute() || !path.has_filename())
    return false;
  target = path.wstring();
  // Publishing later also uses a non-replacing operation, closing the race
  // between selecting a filename and finishing the download.
  if (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES)
    return false;
  const DWORD attributes = GetFileAttributesW(path.parent_path().c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    return false;
  GUID guid{};
  if (FAILED(CoCreateGuid(&guid)))
    return false;
  wchar_t token[40]{};
  if (StringFromGUID2(guid, token, 40) == 0)
    return false;
  // Keep staging on the target filesystem: final publication can be a
  // non-replacing rename, rather than blocking the UI on a cross-volume copy.
  directory =
      (path.parent_path() / (std::wstring(L".webview-download-") + token))
          .wstring();
  if (!CreateDirectoryW(directory.c_str(), nullptr))
    return false;
  SetFileAttributesW(directory.c_str(), FILE_ATTRIBUTE_HIDDEN);
  temporary = (std::filesystem::path(directory) / L"payload").wstring();
  return true;
}

void RemoveOwnedDownloadDirectory(const std::wstring &directory) {
  if (directory.empty())
    return;
  // Only the two paths this plugin owns are removed; never touch the user's
  // final destination, including on an engine failure.
  DeleteFileW((std::filesystem::path(directory) / L"payload").c_str());
  RemoveDirectoryW(directory.c_str());
}

inline void ConvertColor(COREWEBVIEW2_COLOR &webview_color, int32_t color) {
  webview_color.B = color & 0xFF;
  webview_color.G = (color >> 8) & 0xFF;
  webview_color.R = (color >> 16) & 0xFF;
  webview_color.A = (color >> 24) & 0xFF;
}

std::map<std::string, std::string>
ReadHttpHeaders(ICoreWebView2HttpHeadersCollectionIterator *iterator) {
  std::map<std::string, std::string> headers;
  if (iterator == nullptr) {
    return headers;
  }

  BOOL has_current = FALSE;
  if (FAILED(iterator->get_HasCurrentHeader(&has_current))) {
    return headers;
  }

  while (has_current) {
    wil::unique_cotaskmem_string name;
    wil::unique_cotaskmem_string value;
    if (SUCCEEDED(iterator->GetCurrentHeader(&name, &value)) &&
        name != nullptr && value != nullptr) {
      headers[util::Utf8FromUtf16(name.get())] =
          util::Utf8FromUtf16(value.get());
    }

    if (FAILED(iterator->MoveNext(&has_current))) {
      break;
    }
  }

  return headers;
}

std::map<std::string, std::string>
ReadHttpHeaders(ICoreWebView2HttpRequestHeaders *headers) {
  wil::com_ptr<ICoreWebView2HttpHeadersCollectionIterator> iterator;
  if (headers == nullptr || FAILED(headers->GetIterator(iterator.put()))) {
    return {};
  }
  return ReadHttpHeaders(iterator.get());
}

std::map<std::string, std::string>
ReadHttpHeaders(ICoreWebView2HttpResponseHeaders *headers) {
  wil::com_ptr<ICoreWebView2HttpHeadersCollectionIterator> iterator;
  if (headers == nullptr || FAILED(headers->GetIterator(iterator.put()))) {
    return {};
  }
  return ReadHttpHeaders(iterator.get());
}

double GetFlutterScrollOffsetMultiplier() {
  constexpr UINT kDefaultLinesPerScroll = 3;
  UINT lines_per_scroll = kDefaultLinesPerScroll;
  SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, &lines_per_scroll, 0);
  if (lines_per_scroll == 0 || lines_per_scroll == WHEEL_PAGESCROLL) {
    lines_per_scroll = kDefaultLinesPerScroll;
  }
  return static_cast<double>(lines_per_scroll) * 100.0 / 3.0;
}

inline WebviewPermissionKind
CW2PermissionKindToPermissionKind(COREWEBVIEW2_PERMISSION_KIND kind) {
  using k = COREWEBVIEW2_PERMISSION_KIND;
  switch (kind) {
  case k::COREWEBVIEW2_PERMISSION_KIND_MICROPHONE:
    return WebviewPermissionKind::Microphone;
  case k::COREWEBVIEW2_PERMISSION_KIND_CAMERA:
    return WebviewPermissionKind::Camera;
  case k::COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION:
    return WebviewPermissionKind::GeoLocation;
  case k::COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS:
    return WebviewPermissionKind::Notifications;
  case k::COREWEBVIEW2_PERMISSION_KIND_OTHER_SENSORS:
    return WebviewPermissionKind::OtherSensors;
  case k::COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ:
    return WebviewPermissionKind::ClipboardRead;
  default:
    return WebviewPermissionKind::Unknown;
  }
}

inline COREWEBVIEW2_PERMISSION_STATE
WebViewPermissionStateToCW2PermissionState(WebviewPermissionState state) {
  using s = COREWEBVIEW2_PERMISSION_STATE;
  switch (state) {
  case WebviewPermissionState::Allow:
    return s::COREWEBVIEW2_PERMISSION_STATE_ALLOW;
  case WebviewPermissionState::Deny:
    return s::COREWEBVIEW2_PERMISSION_STATE_DENY;
  default:
    return s::COREWEBVIEW2_PERMISSION_STATE_DEFAULT;
  }
}

inline WebviewJavaScriptDialogKind CW2ScriptDialogKindToJavaScriptDialogKind(
    COREWEBVIEW2_SCRIPT_DIALOG_KIND kind) {
  using k = COREWEBVIEW2_SCRIPT_DIALOG_KIND;
  switch (kind) {
  case k::COREWEBVIEW2_SCRIPT_DIALOG_KIND_ALERT:
    return WebviewJavaScriptDialogKind::Alert;
  case k::COREWEBVIEW2_SCRIPT_DIALOG_KIND_CONFIRM:
    return WebviewJavaScriptDialogKind::Confirm;
  case k::COREWEBVIEW2_SCRIPT_DIALOG_KIND_PROMPT:
    return WebviewJavaScriptDialogKind::Prompt;
  case k::COREWEBVIEW2_SCRIPT_DIALOG_KIND_BEFOREUNLOAD:
    return WebviewJavaScriptDialogKind::BeforeUnload;
  default:
    return WebviewJavaScriptDialogKind::Alert;
  }
}

inline bool ReadCookieString(ICoreWebView2Cookie *cookie,
                             HRESULT (ICoreWebView2Cookie::*getter)(LPWSTR *),
                             std::string &value) {
  wil::unique_cotaskmem_string raw_value;
  if (FAILED((cookie->*getter)(&raw_value))) {
    return false;
  }
  value = util::Utf8FromUtf16(raw_value.get());
  return true;
}

bool ApplyCookieProperties(ICoreWebView2Cookie *native_cookie,
                           const WebviewCookie &cookie) {
  if (cookie.expires.has_value() &&
      FAILED(native_cookie->put_Expires(cookie.expires.value()))) {
    return false;
  }
  if (cookie.is_http_only.has_value() &&
      FAILED(native_cookie->put_IsHttpOnly(cookie.is_http_only.value()))) {
    return false;
  }
  if (cookie.is_secure.has_value() &&
      FAILED(native_cookie->put_IsSecure(cookie.is_secure.value()))) {
    return false;
  }
  if (cookie.same_site.has_value() &&
      FAILED(native_cookie->put_SameSite(
          static_cast<COREWEBVIEW2_COOKIE_SAME_SITE_KIND>(
              cookie.same_site.value())))) {
    return false;
  }
  return true;
}

bool CreateNativeCookie(ICoreWebView2CookieManager *cookie_manager,
                        const WebviewCookie &cookie,
                        wil::com_ptr<ICoreWebView2Cookie> &native_cookie) {
  const std::wstring name = util::Utf16FromUtf8(cookie.name);
  const std::wstring value = util::Utf16FromUtf8(cookie.value);
  const std::wstring domain = util::Utf16FromUtf8(cookie.domain);
  const std::wstring path = util::Utf16FromUtf8(cookie.path);

  if (FAILED(cookie_manager->CreateCookie(name.c_str(), value.c_str(),
                                          domain.c_str(), path.c_str(),
                                          native_cookie.put()))) {
    return false;
  }
  return ApplyCookieProperties(native_cookie.get(), cookie);
}

std::string CanonicalizeNavigationUrl(const std::string &url) {
  try {
    const winrt::Windows::Foundation::Uri uri(winrt::to_hstring(url));
    return winrt::to_string(uri.AbsoluteCanonicalUri());
  } catch (...) {
    return url;
  }
}

} // namespace

struct Webview::PendingDownload {
  WebviewDownloadRequest request;
  wil::com_ptr<ICoreWebView2DownloadStartingEventArgs> args;
  wil::com_ptr<ICoreWebView2DownloadOperation> operation;
  wil::com_ptr<ICoreWebView2Deferral> deferral;
  UINT_PTR timeout = 0;
  bool completed = false;
};

struct Webview::ActiveDownload {
  std::string id;
  wil::com_ptr<ICoreWebView2DownloadOperation> operation;
  bool managed = false;
  bool completed = false;
  std::wstring temporary_directory;
  std::wstring target;
  EventRegistrationToken bytes_token{};
  EventRegistrationToken state_token{};
};

namespace {
std::mutex active_profiles_mutex;
std::map<const Webview*, std::wstring> active_profiles;
}
wil::com_ptr<ICoreWebView2Profile> Webview::GetProfile() const {
  wil::com_ptr<ICoreWebView2Profile> profile;
  auto view = webview_ ? webview_.try_query<ICoreWebView2_13>() : nullptr;
  if (view) view->get_Profile(profile.put());
  return profile;
}
bool Webview::IsProfileActive(const std::wstring& path, const Webview* excluding) {
  std::lock_guard<std::mutex> guard(active_profiles_mutex);
  for (const auto& entry : active_profiles) {
    if (entry.first != excluding && CompareStringOrdinal(entry.second.c_str(), -1, path.c_str(), -1, TRUE) == CSTR_EQUAL) return true;
  }
  return false;
}

namespace {
wil::unique_handle LockProfileFiles(const std::wstring& path, bool deletion) {
  const std::filesystem::path profile(path);
  const auto root = profile.parent_path() / L"webview_all_profile_locks";
  std::error_code error;
  std::filesystem::create_directories(root, error);
  if (error) return {};
  auto name = profile.filename().wstring() + L".lock";
  auto lock_path = root / name;
  return wil::unique_handle(CreateFileW(lock_path.c_str(), deletion ? GENERIC_WRITE : GENERIC_READ,
      deletion ? 0 : FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr));
}
}
wil::unique_handle Webview::AcquireProfileDeletionLock(const std::wstring& path) {
  return LockProfileFiles(path, true);
}

Webview::Webview(
    wil::com_ptr<ICoreWebView2CompositionController> composition_controller,
    std::shared_ptr<WebviewHost> host, HWND parent_window,
    winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor, bool profile_management)
    : parent_window_(parent_window),
      composition_controller_(std::move(composition_controller)),
      host_(std::move(host)) {
  lifetime_state_->owner = this;
  webview_controller_ =
      composition_controller_.try_query<ICoreWebView2Controller3>();

  if (!webview_controller_ ||
      FAILED(webview_controller_->get_CoreWebView2(webview_.put()))) {
    return;
  }

  if (FAILED(webview_controller_->put_BoundsMode(
          COREWEBVIEW2_BOUNDS_MODE_USE_RAW_PIXELS)) ||
      FAILED(webview_controller_->put_ShouldDetectMonitorScaleChanges(FALSE)) ||
      FAILED(webview_controller_->put_RasterizationScale(1.0))) {
    return;
  }

  wil::com_ptr<ICoreWebView2Settings> settings;
  if (SUCCEEDED(webview_->get_Settings(settings.put()))) {
    settings_ = settings;
    settings2_ = settings.try_query<ICoreWebView2Settings2>();
    settings3_ = settings.try_query<ICoreWebView2Settings3>();
    if (settings2_) {
      wil::unique_cotaskmem_string default_user_agent;
      if (SUCCEEDED(settings2_->get_UserAgent(&default_user_agent)) &&
          default_user_agent != nullptr) {
        default_user_agent_ = util::Utf8FromUtf16(default_user_agent.get());
      }
    }

    settings->put_IsStatusBarEnabled(FALSE);
    settings->put_AreDefaultContextMenusEnabled(FALSE);
  }

  if (auto profile = GetProfile()) {
    wil::unique_cotaskmem_string path;
    if (SUCCEEDED(profile->get_ProfilePath(path.put())) && path) {
      managed_profile_path_ = path.get();
      wil::unique_cotaskmem_string name;
      if (!profile_management && SUCCEEDED(profile->get_ProfileName(name.put())) && name && std::wstring(name.get()).rfind(L"webview_all_", 0) == 0) {
        managed_profile_lock_ = LockProfileFiles(managed_profile_path_, false);
        if (!managed_profile_lock_) return;
      }
      std::lock_guard<std::mutex> guard(active_profiles_mutex);
      active_profiles[this] = managed_profile_path_;
    }
  }
  EnableSecurityUpdates();
  RegisterEventHandlers();

  is_valid_ = CreateSurface(std::move(compositor));
}

Webview::~Webview() {
  {
    std::lock_guard<std::mutex> guard(active_profiles_mutex);
    active_profiles.erase(this);
  }
  SetNewWindowDelegateEnabled(false);
  CompleteCapture(pending_capture_, nullptr, "The WebView was disposed.");
  ClearFind();
  resource_bridge_.reset();
  DisposeDownloads();
  InvalidatePendingNavigationRequests();
  lifetime_state_->owner = nullptr;
  navigation_requested_callback_ = nullptr;
  download_event_callback_ = nullptr;
  download_requested_callback_ = nullptr;

  if (webview_controller_) {
    SetFocus(false, COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    webview_controller_->put_IsVisible(FALSE);
  }
  if (composition_controller_) {
    composition_controller_->put_RootVisualTarget(nullptr);
  }
  if (webview_controller_) {
    webview_controller_->Close();
  }

  devtools_protocol_event_receiver_ = nullptr;
  settings2_ = nullptr;
  settings_ = nullptr;
  webview_ = nullptr;
  webview_controller_ = nullptr;
  composition_controller_ = nullptr;
  surface_ = nullptr;
  host_.reset();
}

bool Webview::CreateSurface(
    winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor) {
  if (!compositor || !composition_controller_ || !webview_controller_) {
    return false;
  }

  winrt::com_ptr<ABI::Windows::UI::Composition::IContainerVisual> root;
  if (FAILED(compositor->CreateContainerVisual(root.put())) || !root) {
    return false;
  }

  surface_ = root.try_as<ABI::Windows::UI::Composition::IVisual>();
  if (!surface_) {
    return false;
  }

  // The initial bounds must be outside the virtual desktop before WebView2 is
  // connected or made visible. The texture is resized to the Flutter widget
  // after its first layout.
  if (FAILED(surface_->put_Size({1280, 720})) ||
      FAILED(surface_->put_IsVisible(true)) ||
      !UpdateControllerBounds(1280, 720, 1.0f)) {
    return false;
  }

  winrt::com_ptr<ABI::Windows::UI::Composition::IVisual> webview_visual;
  if (FAILED(compositor->CreateContainerVisual(
          reinterpret_cast<ABI::Windows::UI::Composition::IContainerVisual **>(
              webview_visual.put()))) ||
      !webview_visual) {
    return false;
  }

  auto webview_visual2 =
      webview_visual.try_as<ABI::Windows::UI::Composition::IVisual2>();
  if (!webview_visual2 ||
      FAILED(webview_visual2->put_RelativeSizeAdjustment({1.0f, 1.0f}))) {
    return false;
  }

  winrt::com_ptr<ABI::Windows::UI::Composition::IVisualCollection> children;
  if (FAILED(root->get_Children(children.put())) || !children ||
      FAILED(children->InsertAtTop(webview_visual.get())) ||
      FAILED(composition_controller_->put_RootVisualTarget(
          webview_visual2.get())) ||
      FAILED(webview_controller_->put_IsVisible(FALSE))) {
    return false;
  }

  return true;
}

void Webview::EnableSecurityUpdates() {
  if (SUCCEEDED(webview_->CallDevToolsProtocolMethod(L"Security.enable", L"{}",
                                                     nullptr)) &&
      SUCCEEDED(webview_->GetDevToolsProtocolEventReceiver(
          L"Security.securityStateChanged",
          &devtools_protocol_event_receiver_))) {
    devtools_protocol_event_receiver_->add_DevToolsProtocolEventReceived(
        Callback<ICoreWebView2DevToolsProtocolEventReceivedEventHandler>(
            [this](ICoreWebView2 *sender,
                   ICoreWebView2DevToolsProtocolEventReceivedEventArgs *args)
                -> HRESULT {
              if (devtools_protocol_event_callback_) {
                wil::unique_cotaskmem_string json_args;
                if (args->get_ParameterObjectAsJson(&json_args) == S_OK) {
                  std::string json = util::Utf8FromUtf16(json_args.get());
                  devtools_protocol_event_callback_(json.c_str());
                }
              }

              return S_OK;
            })
            .Get(),
        &event_registrations_.devtools_protocol_event_token_);
  }
}

void Webview::RegisterEventHandlers() {
  if (!webview_) {
    return;
  }

  webview_->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [this](ICoreWebView2 *sender,
                 ICoreWebView2NavigationStartingEventArgs *args) -> HRESULT {
            if (!args) {
              return S_OK;
            }

            wil::unique_cotaskmem_string wuri;
            if (FAILED(args->get_Uri(&wuri)) || wuri == nullptr) {
              return S_OK;
            }
            const std::string url = util::Utf8FromUtf16(wuri.get());
            UINT64 navigation_id = 0;
            if (SUCCEEDED(args->get_NavigationId(&navigation_id))) {
              navigation_urls_[navigation_id] = url;
            }

            if (ConsumeApprovedNavigation(url) ||
                !navigation_request_callbacks_enabled_ ||
                !navigation_requested_callback_) {
              ClearFind();
              while (!pending_windows_.empty())
                CompleteNewWindow(pending_windows_.begin()->first, nullptr);
              return S_OK;
            }

            if (FAILED(args->put_Cancel(TRUE))) {
              return S_OK;
            }

            if (SUCCEEDED(args->get_NavigationId(&navigation_id))) {
              policy_cancelled_navigation_ids_.insert(navigation_id);
            }

            BOOL is_user_initiated = FALSE;
            BOOL is_redirected = FALSE;
            args->get_IsUserInitiated(&is_user_initiated);
            args->get_IsRedirected(&is_redirected);

            const uint64_t request_id = ++latest_navigation_request_id_;
            const std::weak_ptr<LifetimeState> weak_state = lifetime_state_;
            navigation_requested_callback_(
                url, is_user_initiated == TRUE, is_redirected == TRUE,
                [weak_state, request_id, url](bool allow) {
                  if (!allow) {
                    return;
                  }
                  const std::shared_ptr<LifetimeState> state =
                      weak_state.lock();
                  if (state && state->owner) {
                    state->owner->ResumeNavigation(request_id, url);
                  }
                });
            return S_OK;
          })
          .Get(),
      &event_registrations_.navigation_starting_token_);

  webview_->add_ContentLoading(
      Callback<ICoreWebView2ContentLoadingEventHandler>(
          [this](ICoreWebView2 *sender, IUnknown *args) -> HRESULT {
            if (loading_state_changed_callback_) {
              loading_state_changed_callback_(WebviewLoadingState::Loading);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.content_loading_token_);

  webview_->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this](ICoreWebView2 *sender,
                 ICoreWebView2NavigationCompletedEventArgs *args) -> HRESULT {
            UINT64 navigation_id = 0;
            args->get_NavigationId(&navigation_id);
            const auto navigation = navigation_urls_.find(navigation_id);
            const std::string url =
                navigation == navigation_urls_.end() ? "" : navigation->second;
            navigation_urls_.erase(navigation_id);
            if (policy_cancelled_navigation_ids_.erase(navigation_id) > 0 ||
                download_navigation_ids_.erase(navigation_id) > 0) {
              return S_OK;
            }

            BOOL is_success;
            args->get_IsSuccess(&is_success);
            if (!is_success && on_load_error_callback_) {
              COREWEBVIEW2_WEB_ERROR_STATUS web_error_status;
              args->get_WebErrorStatus(&web_error_status);
              if (web_error_status ==
                      COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED &&
                  !url.empty()) {
                // WebView2 reports an aborted navigation immediately before
                // DownloadStarting. Keep its identity briefly so that event
                // can consume only the matching download conversion. Genuine
                // connection failures still reach the application.
                const std::weak_ptr<LifetimeState> weak = lifetime_state_;
                const UINT_PTR timer = ScheduleWebviewTimeout(
                    [weak, navigation_id]() {
                      const auto state = weak.lock();
                      if (!state || !state->owner)
                        return;
                      auto *owner = state->owner;
                      if (owner->deferred_download_navigation_errors_.erase(
                              navigation_id) == 0)
                        return;
                      if (owner->on_load_error_callback_)
                        owner->on_load_error_callback_(
                            COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED);
                    },
                    100);
                if (timer != 0) {
                  deferred_download_navigation_errors_[navigation_id] = {url,
                                                                         timer};
                  if (loading_state_changed_callback_)
                    loading_state_changed_callback_(
                        WebviewLoadingState::NavigationCompleted);
                  return S_OK;
                }
              }
              on_load_error_callback_(web_error_status);
            }

            if (loading_state_changed_callback_) {
              loading_state_changed_callback_(
                  WebviewLoadingState::NavigationCompleted);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.navigation_completed_token_);

  auto webview2 = webview_.try_query<ICoreWebView2_2>();
  if (webview2) {
    webview2->add_WebResourceResponseReceived(
        Callback<ICoreWebView2WebResourceResponseReceivedEventHandler>(
            [this](ICoreWebView2 *sender,
                   ICoreWebView2WebResourceResponseReceivedEventArgs *args)
                -> HRESULT {
              if (!http_response_error_callback_) {
                return S_OK;
              }

              wil::com_ptr<ICoreWebView2WebResourceResponseView> response;
              if (FAILED(args->get_Response(response.put())) || !response) {
                return S_OK;
              }

              int status_code = 0;
              if (FAILED(response->get_StatusCode(&status_code)) ||
                  status_code < 400) {
                return S_OK;
              }

              wil::com_ptr<ICoreWebView2WebResourceRequest> request;
              if (FAILED(args->get_Request(request.put())) || !request) {
                return S_OK;
              }

              wil::unique_cotaskmem_string wuri;
              if (FAILED(request->get_Uri(&wuri))) {
                return S_OK;
              }

              std::string url;
              if (wuri != nullptr) {
                url = util::Utf8FromUtf16(wuri.get());
              }

              std::string method;
              wil::unique_cotaskmem_string wmethod;
              if (SUCCEEDED(request->get_Method(&wmethod)) &&
                  wmethod != nullptr) {
                method = util::Utf8FromUtf16(wmethod.get());
              }

              std::map<std::string, std::string> request_headers;
              wil::com_ptr<ICoreWebView2HttpRequestHeaders>
                  native_request_headers;
              if (SUCCEEDED(
                      request->get_Headers(native_request_headers.put()))) {
                request_headers = ReadHttpHeaders(native_request_headers.get());
              }

              std::map<std::string, std::string> response_headers;
              wil::com_ptr<ICoreWebView2HttpResponseHeaders>
                  native_response_headers;
              if (SUCCEEDED(
                      response->get_Headers(native_response_headers.put()))) {
                response_headers =
                    ReadHttpHeaders(native_response_headers.get());
              }

              std::optional<std::string> reason_phrase;
              wil::unique_cotaskmem_string wreason_phrase;
              if (SUCCEEDED(response->get_ReasonPhrase(&wreason_phrase)) &&
                  wreason_phrase != nullptr) {
                reason_phrase = util::Utf8FromUtf16(wreason_phrase.get());
              }

              http_response_error_callback_({url, method, request_headers,
                                             status_code, response_headers,
                                             reason_phrase});
              return S_OK;
            })
            .Get(),
        &event_registrations_.web_resource_response_received_token_);
  }

  webview_->add_HistoryChanged(
      Callback<ICoreWebView2HistoryChangedEventHandler>(
          [this](ICoreWebView2 *sender, IUnknown *args) -> HRESULT {
            if (history_changed_callback_) {
              BOOL can_go_back;
              BOOL can_go_forward;
              sender->get_CanGoBack(&can_go_back);
              sender->get_CanGoForward(&can_go_forward);
              history_changed_callback_({can_go_back, can_go_forward});
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.history_changed_token_);

  webview_->add_SourceChanged(
      Callback<ICoreWebView2SourceChangedEventHandler>(
          [this](ICoreWebView2 *sender, IUnknown *args) -> HRESULT {
            wil::unique_cotaskmem_string wurl;
            if (url_changed_callback_ &&
                SUCCEEDED(webview_->get_Source(&wurl)) && wurl != nullptr) {
              std::string url = util::Utf8FromUtf16(wurl.get());
              url_changed_callback_(url);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.source_changed_token_);

  webview_->add_DocumentTitleChanged(
      Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
          [this](ICoreWebView2 *sender, IUnknown *args) -> HRESULT {
            wil::unique_cotaskmem_string wtitle;
            if (document_title_changed_callback_ &&
                SUCCEEDED(webview_->get_DocumentTitle(&wtitle)) &&
                wtitle != nullptr) {
              std::string title = util::Utf8FromUtf16(wtitle.get());
              document_title_changed_callback_(title);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.document_title_changed_token_);

  composition_controller_->add_CursorChanged(
      Callback<ICoreWebView2CursorChangedEventHandler>(
          [this](ICoreWebView2CompositionController *sender,
                 IUnknown *args) -> HRESULT {
            HCURSOR cursor;
            if (cursor_changed_callback_ &&
                sender->get_Cursor(&cursor) == S_OK) {
              cursor_changed_callback_(cursor);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.cursor_changed_token_);

  webview_controller_->add_GotFocus(
      Callback<ICoreWebView2FocusChangedEventHandler>(
          [this](ICoreWebView2Controller *sender, IUnknown *args) -> HRESULT {
            has_focus_ = true;
            if (focus_changed_callback_) {
              focus_changed_callback_(true);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.got_focus_token_);

  webview_controller_->add_LostFocus(
      Callback<ICoreWebView2FocusChangedEventHandler>(
          [this](ICoreWebView2Controller *sender, IUnknown *args) -> HRESULT {
            has_focus_ = false;
            if (focus_changed_callback_) {
              focus_changed_callback_(false);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.lost_focus_token_);

  webview_controller_->add_MoveFocusRequested(
      Callback<ICoreWebView2MoveFocusRequestedEventHandler>(
          [this](ICoreWebView2Controller *,
                 ICoreWebView2MoveFocusRequestedEventArgs *args) -> HRESULT {
            COREWEBVIEW2_MOVE_FOCUS_REASON reason;
            if (move_focus_requested_callback_ &&
                SUCCEEDED(args->get_Reason(&reason)) &&
                move_focus_requested_callback_(
                    reason == COREWEBVIEW2_MOVE_FOCUS_REASON_PREVIOUS)) {
              return args->put_Handled(TRUE);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.move_focus_requested_token_);

  webview_->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [this](ICoreWebView2 *sender,
                 ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
            wil::unique_cotaskmem_string wmessage;
            if (web_message_received_callback_ &&
                args->get_WebMessageAsJson(&wmessage) == S_OK) {
              const std::string message = util::Utf8FromUtf16(wmessage.get());
              // The URI of the document that sent this web message; only the
              // top-level document raises this event.
              wil::unique_cotaskmem_string wsource;
              const std::string source =
                  args->get_Source(&wsource) == S_OK && wsource
                      ? util::Utf8FromUtf16(wsource.get())
                      : std::string();
              web_message_received_callback_(message, source);
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.web_message_received_token_);

  webview_->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [this](ICoreWebView2 *sender,
                 ICoreWebView2PermissionRequestedEventArgs *args) -> HRESULT {
            if (!permission_requested_callback_) {
              return S_OK;
            }

            wil::unique_cotaskmem_string wuri;
            COREWEBVIEW2_PERMISSION_KIND kind =
                COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
            BOOL is_user_initiated = false;

            if (args->get_Uri(&wuri) == S_OK &&
                args->get_PermissionKind(&kind) == S_OK &&
                args->get_IsUserInitiated(&is_user_initiated) == S_OK) {
              wil::com_ptr<ICoreWebView2Deferral> deferral;
              if (FAILED(args->GetDeferral(deferral.put())) || !deferral) {
                return S_OK;
              }

              const std::string uri = util::Utf8FromUtf16(wuri.get());
              wil::com_ptr<ICoreWebView2PermissionRequestedEventArgs>
                  permission_args;
              args->AddRef();
              permission_args.attach(args);
              permission_requested_callback_(
                  uri, CW2PermissionKindToPermissionKind(kind),
                  is_user_initiated == TRUE,
                  [deferral = std::move(deferral),
                   permission_args = std::move(permission_args)](
                      WebviewPermissionState state) {
                    permission_args->put_State(
                        WebViewPermissionStateToCW2PermissionState(state));
                    deferral->Complete();
                  });
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.permission_requested_token_);

  auto webview10 = webview_.try_query<ICoreWebView2_10>();
  if (webview10) {
    webview10->add_BasicAuthenticationRequested(
        Callback<ICoreWebView2BasicAuthenticationRequestedEventHandler>(
            [this](ICoreWebView2 *sender,
                   ICoreWebView2BasicAuthenticationRequestedEventArgs *args)
                -> HRESULT {
              if (!http_auth_requested_callback_) {
                return S_OK;
              }

              wil::unique_cotaskmem_string wuri;
              wil::unique_cotaskmem_string wchallenge;
              wil::com_ptr<ICoreWebView2BasicAuthenticationResponse> response;
              if (FAILED(args->get_Uri(&wuri)) ||
                  FAILED(args->get_Challenge(&wchallenge)) ||
                  FAILED(args->get_Response(response.put())) || !response) {
                return S_OK;
              }

              wil::com_ptr<ICoreWebView2Deferral> deferral;
              if (FAILED(args->GetDeferral(deferral.put())) || !deferral) {
                return S_OK;
              }

              wil::com_ptr<ICoreWebView2BasicAuthenticationRequestedEventArgs>
                  auth_args;
              args->AddRef();
              auth_args.attach(args);

              WebviewHttpAuthRequest request{
                  util::Utf8FromUtf16(wuri.get()),
                  util::Utf8FromUtf16(wchallenge.get())};
              http_auth_requested_callback_(
                  request, [deferral = std::move(deferral),
                            auth_args = std::move(auth_args),
                            response = std::move(response)](
                               bool accepted, const std::string &user,
                               const std::string &password) mutable {
                    if (accepted) {
                      const std::wstring user_utf16 = util::Utf16FromUtf8(user);
                      const std::wstring password_utf16 =
                          util::Utf16FromUtf8(password);
                      response->put_UserName(user_utf16.c_str());
                      response->put_Password(password_utf16.c_str());
                      auth_args->put_Cancel(FALSE);
                    } else {
                      auth_args->put_Cancel(TRUE);
                    }
                    deferral->Complete();
                  });

              return S_OK;
            })
            .Get(),
        &event_registrations_.basic_authentication_requested_token_);
  }

  auto webview14 = webview_.try_query<ICoreWebView2_14>();
  if (webview14) {
    webview14->add_ServerCertificateErrorDetected(
        Callback<ICoreWebView2ServerCertificateErrorDetectedEventHandler>(
            [this](ICoreWebView2 *sender,
                   ICoreWebView2ServerCertificateErrorDetectedEventArgs *args)
                -> HRESULT {
              if (!ssl_auth_error_callback_) {
                args->put_Action(
                    COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
                return S_OK;
              }

              COREWEBVIEW2_WEB_ERROR_STATUS status =
                  COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
              wil::unique_cotaskmem_string request_uri;
              if (FAILED(args->get_ErrorStatus(&status)) ||
                  FAILED(args->get_RequestUri(&request_uri))) {
                args->put_Action(
                    COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
                return S_OK;
              }

              wil::com_ptr<ICoreWebView2Deferral> deferral;
              if (FAILED(args->GetDeferral(deferral.put())) || !deferral) {
                args->put_Action(
                    COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
                return S_OK;
              }

              wil::com_ptr<ICoreWebView2ServerCertificateErrorDetectedEventArgs>
                  error_args;
              args->AddRef();
              error_args.attach(args);

              ssl_auth_error_callback_(
                  {util::Utf8FromUtf16(request_uri.get()), status},
                  [deferral = std::move(deferral),
                   error_args = std::move(error_args)](bool proceed) mutable {
                    error_args->put_Action(
                        proceed
                            ? COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_ALWAYS_ALLOW
                            : COREWEBVIEW2_SERVER_CERTIFICATE_ERROR_ACTION_CANCEL);
                    deferral->Complete();
                  });

              return S_OK;
            })
            .Get(),
        &event_registrations_.server_certificate_error_detected_token_);
  }

  webview_->add_ScriptDialogOpening(
      Callback<ICoreWebView2ScriptDialogOpeningEventHandler>(
          [this](ICoreWebView2 *sender,
                 ICoreWebView2ScriptDialogOpeningEventArgs *args) -> HRESULT {
            if (!java_script_dialog_requested_callback_) {
              return S_OK;
            }

            COREWEBVIEW2_SCRIPT_DIALOG_KIND raw_kind =
                COREWEBVIEW2_SCRIPT_DIALOG_KIND_ALERT;
            if (FAILED(args->get_Kind(&raw_kind))) {
              return S_OK;
            }

            const WebviewJavaScriptDialogKind kind =
                CW2ScriptDialogKindToJavaScriptDialogKind(raw_kind);
            bool enabled = false;
            switch (kind) {
            case WebviewJavaScriptDialogKind::Alert:
              enabled = java_script_alert_dialog_enabled_;
              break;
            case WebviewJavaScriptDialogKind::Confirm:
              enabled = java_script_confirm_dialog_enabled_;
              break;
            case WebviewJavaScriptDialogKind::Prompt:
              enabled = java_script_prompt_dialog_enabled_;
              break;
            case WebviewJavaScriptDialogKind::BeforeUnload:
              enabled = false;
              break;
            }
            if (!enabled) {
              return S_OK;
            }

            wil::unique_cotaskmem_string wuri;
            wil::unique_cotaskmem_string wmessage;
            if (FAILED(args->get_Uri(&wuri)) ||
                FAILED(args->get_Message(&wmessage))) {
              return S_OK;
            }

            WebviewJavaScriptDialogRequest request{
                kind, util::Utf8FromUtf16(wuri.get()),
                util::Utf8FromUtf16(wmessage.get()), std::nullopt};
            if (kind == WebviewJavaScriptDialogKind::Prompt) {
              wil::unique_cotaskmem_string wdefault_text;
              if (SUCCEEDED(args->get_DefaultText(&wdefault_text))) {
                request.default_text = util::Utf8FromUtf16(wdefault_text.get());
              }
            }

            wil::com_ptr<ICoreWebView2Deferral> deferral;
            if (FAILED(args->GetDeferral(deferral.put())) || !deferral) {
              return S_OK;
            }

            wil::com_ptr<ICoreWebView2ScriptDialogOpeningEventArgs> dialog_args;
            args->AddRef();
            dialog_args.attach(args);
            java_script_dialog_requested_callback_(
                request, [deferral = std::move(deferral),
                          dialog_args = std::move(dialog_args), kind](
                             bool accepted,
                             const std::optional<std::string> &text) mutable {
                  if (accepted) {
                    if (kind == WebviewJavaScriptDialogKind::Prompt && text) {
                      const std::wstring text_utf16 =
                          util::Utf16FromUtf8(*text);
                      dialog_args->put_ResultText(text_utf16.c_str());
                    }
                    dialog_args->Accept();
                  }
                  deferral->Complete();
                });

            return S_OK;
          })
          .Get(),
      &event_registrations_.script_dialog_opening_token_);

  webview_->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [this](ICoreWebView2 *sender,
                 ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
            if (new_window_delegate_enabled_ && new_window_callback_ &&
                popup_window_policy_ != WebviewPopupWindowPolicy::Deny) {
              args->put_Handled(TRUE);
              auto pending = std::make_shared<PendingWindow>();
              if (FAILED(args->GetDeferral(pending->deferral.put())))
                return S_OK;
              pending->args = args;
              const std::string id = std::to_string(++next_window_id_);
              pending_windows_[id] = pending;
              const std::weak_ptr<LifetimeState> weak = lifetime_state_;
              pending->timeout = ScheduleWebviewTimeout(
                  [weak, id]() {
                    const auto state = weak.lock();
                    if (state && state->owner)
                      state->owner->CompleteNewWindow(id, nullptr);
                  },
                  25000);
              if (!pending->timeout) {
                CompleteNewWindow(id, nullptr);
                return S_OK;
              }
              wil::unique_cotaskmem_string uri;
              BOOL gesture = FALSE;
              args->get_Uri(&uri);
              args->get_IsUserInitiated(&gesture);
              new_window_callback_(
                  id, uri ? util::Utf8FromUtf16(uri.get()) : "", gesture);
              return S_OK;
            }
            switch (popup_window_policy_) {
              case WebviewPopupWindowPolicy::Deny:
                args->put_Handled(TRUE);
                break;
              case WebviewPopupWindowPolicy::ShowInSameWindow: {
                wil::unique_cotaskmem_string wuri;
                if (SUCCEEDED(args->get_Uri(&wuri)) && wuri != nullptr) {
                  args->put_Handled(TRUE);
                  webview_->Navigate(wuri.get());
                }
                break;
              }
              case WebviewPopupWindowPolicy::Allow:
                break;
            }

            return S_OK;
          })
          .Get(),
      &event_registrations_.new_windows_requested_token_);

  webview_->add_WindowCloseRequested(
      Callback<ICoreWebView2WindowCloseRequestedEventHandler>(
          [this](ICoreWebView2 *, IUnknown *) -> HRESULT {
            if (window_close_callback_) window_close_callback_();
            return S_OK;
          })
          .Get(),
      &event_registrations_.window_close_requested_token_);

  webview_->add_ContainsFullScreenElementChanged(
      Callback<ICoreWebView2ContainsFullScreenElementChangedEventHandler>(
          [this](ICoreWebView2 *sender, IUnknown *args) -> HRESULT {
            BOOL flag = FALSE;
            if (contains_fullscreen_element_changed_callback_ &&
                SUCCEEDED(sender->get_ContainsFullScreenElement(&flag))) {
              contains_fullscreen_element_changed_callback_(flag);
            }
            return S_OK;
          })
          .Get(),
      &event_registrations_.contains_fullscreen_element_changed_token_);

  webview_->add_ProcessFailed(
      Callback<ICoreWebView2ProcessFailedEventHandler>(
          [this](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT {
            COREWEBVIEW2_PROCESS_FAILED_KIND kind;
            if (FAILED(args->get_ProcessFailedKind(&kind))) return S_OK;
            if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED ||
                kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED) {
              while (!pending_windows_.empty())
                CompleteNewWindow(pending_windows_.begin()->first, nullptr);
              CompleteCapture(pending_capture_, nullptr, "The renderer process exited.");
              ClearFind();
              InvalidatePendingNavigationRequests();
            }
            if (process_failed_callback_) process_failed_callback_(static_cast<int>(kind));
            return S_OK;
          }).Get(), &event_registrations_.process_failed_token_);

  auto webview24 = webview_.try_query<ICoreWebView2_4>();
  if (webview24) {
    download_handler_result_ = webview24->add_DownloadStarting(
        Callback<ICoreWebView2DownloadStartingEventHandler>(
            [this](ICoreWebView2 *sender,
                   ICoreWebView2DownloadStartingEventArgs *args) -> HRESULT {
              return StartDownload(args);
            })
            .Get(),
        &event_registrations_.download_starting_token_);
  }
}

std::optional<RECT>
Webview::CalculateControllerBounds(double width, double height,
                                   float scale_factor,
                                   std::optional<SurfaceOrigin> origin) const {
  POINT parent_origin{};
  if (!parent_window_ || !IsWindow(parent_window_) ||
      !ClientToScreen(parent_window_, &parent_origin)) {
    return std::nullopt;
  }
  const auto bounds = CalculateSurfaceBounds(
      width, height, scale_factor, origin, parent_origin.x, parent_origin.y,
      GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN));
  if (!bounds)
    return std::nullopt;
  return RECT{bounds->left, bounds->top, bounds->right, bounds->bottom};
}

bool Webview::UpdateControllerBounds(double width, double height,
                                     float scale_factor) {
  const auto bounds = CalculateControllerBounds(
      width, height, scale_factor,
      surface_visible_ ? surface_origin_ : std::nullopt);
  if (!bounds || !webview_controller_ ||
      FAILED(
          webview_controller_->put_RasterizationScale(rasterization_scale_)) ||
      FAILED(webview_controller_->put_Bounds(*bounds))) {
    return false;
  }
  surface_width_ = width;
  surface_height_ = height;
  scale_factor_ = scale_factor;
  return true;
}

HRESULT Webview::SetSurfaceSize(double width, double height, float scale_factor,
                                std::optional<SurfaceOrigin> origin) {
  if (!IsValid() || !surface_)
    return E_UNEXPECTED;
  // Validate the eventual visible placement even while the view is parked.
  const auto visible_bounds =
      CalculateControllerBounds(width, height, scale_factor, origin);
  if (!visible_bounds)
    return E_INVALIDARG;
  const auto bounds =
      surface_visible_ ? visible_bounds
                       : CalculateControllerBounds(width, height, scale_factor,
                                                   std::nullopt);
  if (!bounds)
    return E_INVALIDARG;
  const bool resized = width != surface_width_ || height != surface_height_ ||
                       scale_factor != scale_factor_;
  const UINT dpi = GetDpiForWindow(parent_window_);
  if (!dpi)
    return E_UNEXPECTED;
  const double dpi_scale = dpi / 96.0;
  double current_zoom;
  HRESULT result = webview_controller_->get_ZoomFactor(&current_zoom);
  if (FAILED(result))
    return result;
  const auto zoom =
      CalculateSurfaceZoom(current_zoom, scale_factor_, rasterization_scale_,
                           scale_factor, dpi_scale);
  if (!zoom)
    return E_INVALIDARG;
  // Native IME uses the HWND's DPI. An additional Flutter visual scale belongs
  // in page zoom; changing rasterization DPI instead offsets IME candidates.
  // Updating zoom and bounds together also preserves the page's CSS viewport.
  result = webview_controller_->put_RasterizationScale(dpi_scale);
  if (FAILED(result))
    return result;
  if (*zoom == current_zoom) {
    result = webview_controller_->put_Bounds(*bounds);
  } else {
    result = webview_controller_->SetBoundsAndZoomFactor(*bounds, *zoom);
  }
  if (FAILED(result))
    return result;
  // Keep the scale state consistent even if resizing the capture surface fails.
  scale_factor_ = scale_factor;
  rasterization_scale_ = dpi_scale;
  if (resized) {
    result =
        surface_->put_Size({static_cast<float>(bounds->right - bounds->left),
                            static_cast<float>(bounds->bottom - bounds->top)});
    if (FAILED(result))
      return result;
  }
  surface_width_ = width;
  surface_height_ = height;
  surface_origin_ = origin;
  return webview_controller_->NotifyParentWindowPositionChanged();
}

HRESULT Webview::SetVisible(bool visible) {
  if (!IsValid() || !webview_controller_)
    return E_UNEXPECTED;
  if (!visible) {
    SetFocus(false, COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    const HRESULT result = webview_controller_->put_IsVisible(FALSE);
    if (FAILED(result))
      return result;
    surface_visible_ = false;
    return UpdateControllerBounds(surface_width_, surface_height_,
                                  scale_factor_)
               ? S_OK
               : E_FAIL;
  }
  surface_visible_ = true;
  if (!UpdateControllerBounds(surface_width_, surface_height_, scale_factor_)) {
    surface_visible_ = false;
    return E_FAIL;
  }
  const HRESULT result = webview_controller_->put_IsVisible(TRUE);
  if (FAILED(result)) {
    surface_visible_ = false;
    UpdateControllerBounds(surface_width_, surface_height_, scale_factor_);
  }
  return result;
}

HRESULT Webview::SetFocus(bool focused, COREWEBVIEW2_MOVE_FOCUS_REASON reason) {
  if (!IsValid()) {
    return E_UNEXPECTED;
  }
  if (!focused) {
    // Do not take focus away from another WebView or an external window.
    if (has_focus_ && IsChild(parent_window_, ::GetFocus()) &&
        GetAncestor(parent_window_, GA_ROOT) == GetForegroundWindow()) {
      ::SetFocus(parent_window_);
    }
    return S_OK;
  }
  if (has_focus_ && reason == COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC) {
    return S_OK;
  }
  BOOL visible = FALSE;
  if (FAILED(webview_controller_->get_IsVisible(&visible)) || !visible ||
      !IsWindowVisible(parent_window_) ||
      GetAncestor(parent_window_, GA_ROOT) != GetForegroundWindow()) {
    return S_FALSE;
  }
  return webview_controller_->MoveFocus(reason);
}

void Webview::NotifyParentWindowPositionChanged() {
  if (!IsValid() || !webview_controller_) {
    return;
  }
  if (!UpdateControllerBounds(surface_width_, surface_height_, scale_factor_) ||
      FAILED(webview_controller_->NotifyParentWindowPositionChanged())) {
    util::LogWarning("Updating WebView parent window position failed.");
  }
}

bool Webview::OpenDevTools() {
  if (!IsValid()) {
    return false;
  }
  webview_->OpenDevToolsWindow();
  return true;
}

wil::com_ptr<ICoreWebView2CookieManager> Webview::GetCookieManager() {
  wil::com_ptr<ICoreWebView2_2> webview2 =
      webview_.try_query<ICoreWebView2_2>();
  if (!webview2) {
    return nullptr;
  }

  wil::com_ptr<ICoreWebView2CookieManager> cookie_manager;
  if (FAILED(webview2->get_CookieManager(cookie_manager.put()))) {
    return nullptr;
  }
  return cookie_manager;
}

void Webview::ClearCookies(CookiesClearedCallback callback) {
  if (!IsValid()) {
    callback(false, false);
    return;
  }

  auto cookie_manager = GetCookieManager();
  if (!cookie_manager) {
    callback(false, false);
    return;
  }

  cookie_manager->GetCookies(
      nullptr, Callback<ICoreWebView2GetCookiesCompletedHandler>(
                   [cookie_manager, callback = std::move(callback)](
                       HRESULT error_code,
                       ICoreWebView2CookieList *cookie_list) -> HRESULT {
                     UINT cookie_count = 0;
                     if (SUCCEEDED(error_code) && cookie_list) {
                       cookie_list->get_Count(&cookie_count);
                     }

                     const HRESULT delete_result =
                         cookie_manager->DeleteAllCookies();
                     callback(SUCCEEDED(error_code) && SUCCEEDED(delete_result),
                              cookie_count > 0);
                     return S_OK;
                   })
                   .Get());
}

bool Webview::SetCookie(const WebviewCookie &cookie) {
  if (!IsValid()) {
    return false;
  }

  auto cookie_manager = GetCookieManager();
  if (!cookie_manager) {
    return false;
  }

  wil::com_ptr<ICoreWebView2Cookie> native_cookie;
  if (!CreateNativeCookie(cookie_manager.get(), cookie, native_cookie)) {
    return false;
  }

  return SUCCEEDED(cookie_manager->AddOrUpdateCookie(native_cookie.get()));
}

void Webview::GetCookies(const std::string &url,
                         CookiesRetrievedCallback callback) {
  if (!IsValid()) {
    callback(false, {});
    return;
  }

  auto cookie_manager = GetCookieManager();
  if (!cookie_manager) {
    callback(false, {});
    return;
  }

  const std::wstring url_utf16 = util::Utf16FromUtf8(url);
  cookie_manager->GetCookies(
      url_utf16.c_str(),
      Callback<ICoreWebView2GetCookiesCompletedHandler>(
          [callback = std::move(callback)](
              HRESULT error_code,
              ICoreWebView2CookieList *cookie_list) -> HRESULT {
            if (FAILED(error_code) || !cookie_list) {
              callback(false, {});
              return S_OK;
            }

            UINT cookie_count = 0;
            if (FAILED(cookie_list->get_Count(&cookie_count))) {
              callback(false, {});
              return S_OK;
            }

            std::vector<WebviewCookie> cookies;
            cookies.reserve(cookie_count);
            for (UINT index = 0; index < cookie_count; index++) {
              wil::com_ptr<ICoreWebView2Cookie> native_cookie;
              if (FAILED(cookie_list->GetValueAtIndex(index,
                                                      native_cookie.put()))) {
                callback(false, {});
                return S_OK;
              }

              WebviewCookie cookie;
              if (!ReadCookieString(native_cookie.get(),
                                    &ICoreWebView2Cookie::get_Name,
                                    cookie.name) ||
                  !ReadCookieString(native_cookie.get(),
                                    &ICoreWebView2Cookie::get_Value,
                                    cookie.value) ||
                  !ReadCookieString(native_cookie.get(),
                                    &ICoreWebView2Cookie::get_Domain,
                                    cookie.domain) ||
                  !ReadCookieString(native_cookie.get(),
                                    &ICoreWebView2Cookie::get_Path,
                                    cookie.path)) {
                callback(false, {});
                return S_OK;
              }

              double expires = 0;
              BOOL is_http_only = false;
              BOOL is_secure = false;
              COREWEBVIEW2_COOKIE_SAME_SITE_KIND same_site =
                  COREWEBVIEW2_COOKIE_SAME_SITE_KIND_NONE;
              BOOL is_session = false;
              if (FAILED(native_cookie->get_Expires(&expires)) ||
                  FAILED(native_cookie->get_IsHttpOnly(&is_http_only)) ||
                  FAILED(native_cookie->get_IsSecure(&is_secure)) ||
                  FAILED(native_cookie->get_SameSite(&same_site)) ||
                  FAILED(native_cookie->get_IsSession(&is_session))) {
                callback(false, {});
                return S_OK;
              }
              cookie.expires = expires;
              cookie.is_http_only = is_http_only;
              cookie.is_secure = is_secure;
              cookie.same_site = static_cast<int64_t>(same_site);
              cookie.is_session = is_session;
              cookies.push_back(std::move(cookie));
            }

            callback(true, std::move(cookies));
            return S_OK;
          })
          .Get());
}

bool Webview::DeleteCookie(const WebviewCookie &cookie) {
  if (!IsValid()) {
    return false;
  }

  auto cookie_manager = GetCookieManager();
  if (!cookie_manager) {
    return false;
  }

  wil::com_ptr<ICoreWebView2Cookie> native_cookie;
  if (!CreateNativeCookie(cookie_manager.get(), cookie, native_cookie)) {
    return false;
  }

  return SUCCEEDED(cookie_manager->DeleteCookie(native_cookie.get()));
}

bool Webview::DeleteCookiesWithNameAndUrl(const std::string &name,
                                          const std::string &url) {
  if (!IsValid()) {
    return false;
  }

  auto cookie_manager = GetCookieManager();
  if (!cookie_manager) {
    return false;
  }

  const std::wstring name_utf16 = util::Utf16FromUtf8(name);
  const std::wstring url_utf16 = util::Utf16FromUtf8(url);
  return SUCCEEDED(
      cookie_manager->DeleteCookies(name_utf16.c_str(), url_utf16.c_str()));
}

bool Webview::DeleteCookiesWithNameDomainAndPath(const std::string &name,
                                                 const std::string &domain,
                                                 const std::string &path) {
  if (!IsValid()) {
    return false;
  }

  auto cookie_manager = GetCookieManager();
  if (!cookie_manager) {
    return false;
  }

  const std::wstring name_utf16 = util::Utf16FromUtf8(name);
  const std::wstring domain_utf16 = util::Utf16FromUtf8(domain);
  const std::wstring path_utf16 = util::Utf16FromUtf8(path);
  return SUCCEEDED(cookie_manager->DeleteCookiesWithDomainAndPath(
      name_utf16.c_str(), domain_utf16.c_str(), path_utf16.c_str()));
}

bool Webview::ClearCache() {
  if (!IsValid()) {
    return false;
  }
  return webview_->CallDevToolsProtocolMethod(L"Network.clearBrowserCache",
                                              L"{}", nullptr) == S_OK;
}

void Webview::ClearLocalStorage(OperationCompletedCallback callback) {
  if (!IsValid()) {
    callback(false);
    return;
  }

  auto webview13 = webview_.try_query<ICoreWebView2_13>();
  if (!webview13) {
    callback(false);
    return;
  }

  wil::com_ptr<ICoreWebView2Profile> profile;
  if (FAILED(webview13->get_Profile(profile.put())) || !profile) {
    callback(false);
    return;
  }

  auto profile2 = profile.try_query<ICoreWebView2Profile2>();
  if (!profile2) {
    callback(false);
    return;
  }

  auto completion =
      std::make_shared<OperationCompletedCallback>(std::move(callback));
  HRESULT hr = profile2->ClearBrowsingData(
      COREWEBVIEW2_BROWSING_DATA_KINDS_ALL_DOM_STORAGE,
      Callback<ICoreWebView2ClearBrowsingDataCompletedHandler>(
          [completion](HRESULT error_code) -> HRESULT {
            (*completion)(SUCCEEDED(error_code));
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) {
    (*completion)(false);
  }
}

void Webview::ClearAllWebsiteData(WebsiteDataClearedCallback callback) {
  WebviewHost::ClearAllWebsiteData(
      IsValid() ? webview_.get() : nullptr,
      [callback =
           std::move(callback)](WebviewHostWebsiteDataClearingResult result) {
        callback(result.supported, result.succeeded);
      });
}

void Webview::ClearWebsiteData(uint64_t kinds,
                               WebsiteDataClearedCallback callback) {
  WebviewHost::ClearWebsiteData(
      webview_.get(), kinds,
      [callback =
           std::move(callback)](WebviewHostWebsiteDataClearingResult result) {
        callback(result.supported, result.succeeded);
      });
}

bool Webview::SetCacheDisabled(bool disabled) {
  if (!IsValid()) {
    return false;
  }
  const std::string json =
      disabled ? R"({"disableCache":true})" : R"({"disableCache":false})";
  return webview_->CallDevToolsProtocolMethod(L"Network.setCacheDisabled",
                                              util::Utf16FromUtf8(json).c_str(),
                                              nullptr) == S_OK;
}

void Webview::SetPopupWindowPolicy(WebviewPopupWindowPolicy policy) {
  popup_window_policy_ = policy;
  if (policy == WebviewPopupWindowPolicy::Deny) {
    while (!pending_windows_.empty())
      CompleteNewWindow(pending_windows_.begin()->first, nullptr);
  }
}

void Webview::SetNavigationRequestCallbacksEnabled(bool enabled) {
  navigation_request_callbacks_enabled_ = enabled;
  InvalidatePendingNavigationRequests();
}

void Webview::SetJavaScriptDialogCallbacksEnabled(bool alert, bool confirm,
                                                  bool prompt) {
  java_script_alert_dialog_enabled_ = alert;
  java_script_confirm_dialog_enabled_ = confirm;
  java_script_prompt_dialog_enabled_ = prompt;
}

void Webview::InvalidatePendingNavigationRequests() {
  ++latest_navigation_request_id_;
  approved_navigation_urls_.clear();
  bypass_next_navigation_count_ = 0;
}

void Webview::MarkNavigationApproved(const std::string &url) {
  approved_navigation_urls_.insert(CanonicalizeNavigationUrl(url));
}

bool Webview::ConsumeApprovedNavigation(const std::string &url) {
  const auto approved =
      approved_navigation_urls_.find(CanonicalizeNavigationUrl(url));
  if (approved != approved_navigation_urls_.end()) {
    approved_navigation_urls_.erase(approved);
    return true;
  }
  if (bypass_next_navigation_count_ > 0) {
    --bypass_next_navigation_count_;
    return true;
  }
  return false;
}

void Webview::ResumeNavigation(uint64_t request_id, const std::string &url) {
  if (!IsValid() || request_id != latest_navigation_request_id_) {
    return;
  }

  MarkNavigationApproved(url);
  if (FAILED(webview_->Navigate(util::Utf16FromUtf8(url).c_str()))) {
    ConsumeApprovedNavigation(url);
  }
}

bool Webview::SetUserAgent(const std::string *user_agent) {
  if (settings2_) {
    if (user_agent == nullptr && default_user_agent_.empty()) {
      return false;
    }
    const std::string &resolved_user_agent =
        user_agent != nullptr ? *user_agent : default_user_agent_;
    return settings2_->put_UserAgent(
               util::Utf16FromUtf8(resolved_user_agent).c_str()) == S_OK;
  }
  return false;
}

std::optional<std::string> Webview::GetUserAgent() {
  if (!settings2_) {
    return std::nullopt;
  }

  wil::unique_cotaskmem_string user_agent;
  if (FAILED(settings2_->get_UserAgent(&user_agent)) || user_agent == nullptr) {
    return std::nullopt;
  }
  return util::Utf8FromUtf16(user_agent.get());
}

bool Webview::SetJavaScriptEnabled(bool enabled) {
  if (settings_) {
    return settings_->put_IsScriptEnabled(enabled ? TRUE : FALSE) == S_OK;
  }
  return false;
}

bool Webview::SetZoomControlEnabled(bool enabled) {
  if (settings_) {
    return settings_->put_IsZoomControlEnabled(enabled ? TRUE : FALSE) == S_OK;
  }
  return false;
}

HRESULT Webview::SetDevToolsEnabled(bool enabled) {
  if (settings_) {
    return settings_->put_AreDevToolsEnabled(enabled ? TRUE : FALSE);
  }
  return E_NOINTERFACE;
}

HRESULT Webview::SetBrowserAcceleratorKeysEnabled(bool enabled) {
  if (settings3_) {
    return settings3_->put_AreBrowserAcceleratorKeysEnabled(
        enabled ? TRUE : FALSE);
  }
  // Older runtimes always allow browser accelerators.
  return enabled ? S_OK : E_NOINTERFACE;
}

HRESULT Webview::SetDownloadsEnabled(bool enabled) {
  if (!enabled && FAILED(download_handler_result_)) {
    return download_handler_result_;
  }
  downloads_enabled_ = enabled;
  if (!enabled)
    CancelPendingDownloads();
  return S_OK;
}

bool Webview::SetBackgroundColor(int32_t color) {
  if (!IsValid()) {
    return false;
  }

  COREWEBVIEW2_COLOR webview_color;
  ConvertColor(webview_color, color);

  // Semi-transparent backgrounds are not supported.
  // Valid alpha values are 0 or 255.
  if (webview_color.A > 0) {
    webview_color.A = 0xFF;
  }

  return webview_controller_->put_DefaultBackgroundColor(webview_color) == S_OK;
}

bool Webview::SetZoomFactor(double factor) {
  if (!IsValid()) {
    return false;
  }
  const auto zoom = CalculateSurfaceZoom(factor, 1, 1, scale_factor_,
                                         rasterization_scale_);
  return zoom && webview_controller_->put_ZoomFactor(*zoom) == S_OK;
}

void Webview::SetCursorPos(double x, double y) {
  if (!IsValid()) {
    return;
  }

  POINT point;
  point.x = static_cast<LONG>(x * scale_factor_);
  point.y = static_cast<LONG>(y * scale_factor_);
  last_cursor_pos_ = point;

  // https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2?view=webview2-1.0.774.44
  composition_controller_->SendMouseInput(
      COREWEBVIEW2_MOUSE_EVENT_KIND::COREWEBVIEW2_MOUSE_EVENT_KIND_MOVE,
      virtual_keys_.state(), 0, point);
}

void Webview::SetPointerUpdate(int32_t pointer,
                               WebviewPointerEventKind eventKind, double x,
                               double y, double size, double pressure) {
  if (!IsValid()) {
    return;
  }

  COREWEBVIEW2_POINTER_EVENT_KIND event =
      COREWEBVIEW2_POINTER_EVENT_KIND_UPDATE;
  UINT32 pointerFlags = POINTER_FLAG_NONE;
  switch (eventKind) {
  case WebviewPointerEventKind::Activate:
    event = COREWEBVIEW2_POINTER_EVENT_KIND_ACTIVATE;
    break;
  case WebviewPointerEventKind::Down:
    SetFocus(true, COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    event = COREWEBVIEW2_POINTER_EVENT_KIND_DOWN;
    pointerFlags =
        POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
    break;
  case WebviewPointerEventKind::Enter:
    event = COREWEBVIEW2_POINTER_EVENT_KIND_ENTER;
    break;
  case WebviewPointerEventKind::Leave:
    event = COREWEBVIEW2_POINTER_EVENT_KIND_LEAVE;
    break;
  case WebviewPointerEventKind::Up:
    event = COREWEBVIEW2_POINTER_EVENT_KIND_UP;
    pointerFlags = POINTER_FLAG_UP;
    break;
  case WebviewPointerEventKind::Update:
    event = COREWEBVIEW2_POINTER_EVENT_KIND_UPDATE;
    pointerFlags =
        POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
    break;
  }

  POINT point;
  point.x = static_cast<LONG>(x * scale_factor_);
  point.y = static_cast<LONG>(y * scale_factor_);

  RECT rect;
  rect.left = point.x - 2;
  rect.right = point.x + 2;
  rect.top = point.y - 2;
  rect.bottom = point.y + 2;

  host_->CreateWebViewPointerInfo(
      [this, pointer, event, pointerFlags, point, rect,
       pressure](wil::com_ptr<ICoreWebView2PointerInfo> pointerInfo,
                 std::unique_ptr<WebviewCreationError> error) {
        if (pointerInfo) {
          ICoreWebView2PointerInfo *pInfo = pointerInfo.get();
          pInfo->put_PointerId(pointer);
          pInfo->put_PointerKind(PT_TOUCH);
          pInfo->put_PointerFlags(pointerFlags);
          pInfo->put_TouchFlags(TOUCH_FLAG_NONE);
          pInfo->put_TouchMask(TOUCH_MASK_CONTACTAREA | TOUCH_MASK_PRESSURE);
          pInfo->put_TouchPressure(
              std::clamp((UINT32)(pressure == 0.0 ? 1024 : 1024 * pressure),
                         (UINT32)0, (UINT32)1024));
          pInfo->put_PixelLocationRaw(point);
          pInfo->put_TouchContactRaw(rect);
          composition_controller_->SendPointerInput(event, pInfo);
        }
      });
}

void Webview::SetPointerButtonState(WebviewPointerButton button, bool is_down) {
  if (!IsValid()) {
    return;
  }

  if (is_down) {
    SetFocus(true, COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
  }

  COREWEBVIEW2_MOUSE_EVENT_KIND kind;
  switch (button) {
  case WebviewPointerButton::Primary:
    virtual_keys_.set_isLeftButtonDown(is_down);
    kind = is_down ? COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_DOWN
                   : COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_UP;
    break;
  case WebviewPointerButton::Secondary:
    virtual_keys_.set_isRightButtonDown(is_down);
    kind = is_down ? COREWEBVIEW2_MOUSE_EVENT_KIND_RIGHT_BUTTON_DOWN
                   : COREWEBVIEW2_MOUSE_EVENT_KIND_RIGHT_BUTTON_UP;
    break;
  case WebviewPointerButton::Tertiary:
    virtual_keys_.set_isMiddleButtonDown(is_down);
    kind = is_down ? COREWEBVIEW2_MOUSE_EVENT_KIND_MIDDLE_BUTTON_DOWN
                   : COREWEBVIEW2_MOUSE_EVENT_KIND_MIDDLE_BUTTON_UP;
    break;
  default:
    kind = static_cast<COREWEBVIEW2_MOUSE_EVENT_KIND>(0);
  }

  composition_controller_->SendMouseInput(kind, virtual_keys_.state(), 0,
                                          last_cursor_pos_);
}

void Webview::SendScroll(double delta, bool horizontal) {
  auto &remainder =
      horizontal ? horizontal_scroll_remainder_ : vertical_scroll_remainder_;
  const auto native_delta =
      (delta / GetFlutterScrollOffsetMultiplier()) * WHEEL_DELTA + remainder;
  auto wheel_delta = static_cast<long>(std::round(native_delta));
  remainder = native_delta - static_cast<double>(wheel_delta);

  if (wheel_delta == 0) {
    return;
  }

  wheel_delta =
      std::clamp<long>(wheel_delta, (std::numeric_limits<short>::min)(),
                       (std::numeric_limits<short>::max)());
  auto offset = static_cast<short>(wheel_delta);

  if (horizontal) {
    composition_controller_->SendMouseInput(
        COREWEBVIEW2_MOUSE_EVENT_KIND_HORIZONTAL_WHEEL, virtual_keys_.state(),
        offset, last_cursor_pos_);
  } else {
    composition_controller_->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_WHEEL,
                                            virtual_keys_.state(), offset,
                                            last_cursor_pos_);
  }
}

void Webview::SetScrollDelta(double delta_x, double delta_y) {
  if (!IsValid()) {
    return;
  }

  if (delta_x != 0.0) {
    SendScroll(delta_x, true);
  }
  if (delta_y != 0.0) {
    SendScroll(delta_y, false);
  }
}

void Webview::LoadUrl(const std::string &url) {
  window_target_available_ = false;
  if (IsValid()) {
    InvalidatePendingNavigationRequests();
    MarkNavigationApproved(url);
    if (FAILED(webview_->Navigate(util::Utf16FromUtf8(url).c_str()))) {
      ConsumeApprovedNavigation(url);
    }
  }
}

bool Webview::LoadRequest(const std::string &url, const std::string &method,
                          const std::string &headers,
                          const std::vector<uint8_t> *body) {
  window_target_available_ = false;
  if (!IsValid()) {
    return false;
  }

  auto webview2 = webview_.try_query<ICoreWebView2_2>();
  if (!webview2) {
    return false;
  }

  wil::com_ptr<ICoreWebView2WebResourceRequest> request =
      host_->CreateWebResourceRequest(url, method, headers, body);
  if (!request) {
    return false;
  }

  InvalidatePendingNavigationRequests();
  MarkNavigationApproved(url);
  if (FAILED(webview2->NavigateWithWebResourceRequest(request.get()))) {
    ConsumeApprovedNavigation(url);
    return false;
  }
  return true;
}

HRESULT Webview::LoadStringContent(const std::string &content) {
  window_target_available_ = false;
  if (!IsValid()) {
    return E_UNEXPECTED;
  }

  InvalidatePendingNavigationRequests();
  constexpr auto kStringContentNavigationUrl = "about:blank";
  MarkNavigationApproved(kStringContentNavigationUrl);
  const HRESULT result =
      webview_->NavigateToString(util::Utf16FromUtf8(content).c_str());
  if (FAILED(result)) {
    ConsumeApprovedNavigation(kStringContentNavigationUrl);
  }
  return result;
}

bool Webview::Stop() {
  if (!IsValid()) {
    return false;
  }
  InvalidatePendingNavigationRequests();
  return SUCCEEDED(webview_->Stop());
}

void Webview::NavigateToHistoryEntry(int64_t entry_id,
                                     ScriptExecutedCallback callback) {
  InvalidatePendingNavigationRequests();
  const auto generation = latest_navigation_request_id_;
  ++bypass_next_navigation_count_;
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  CallBrowserProtocol(
      "Page.navigateToHistoryEntry",
      "{\"entryId\":" + std::to_string(entry_id) + "}",
      [weak, generation, callback = std::move(callback)](
          bool success, const std::string &data) {
        const auto state = weak.lock();
        if (!success && state && state->owner &&
            state->owner->latest_navigation_request_id_ == generation &&
            state->owner->bypass_next_navigation_count_ > 0) {
          --state->owner->bypass_next_navigation_count_;
        }
        callback(success, data);
      });
}

void Webview::CallBrowserProtocol(const std::string &method,
                                  const std::string &params,
                                  ScriptExecutedCallback callback) {
  if (!IsValid()) {
    callback(false, "");
    return;
  }
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  auto complete = std::make_shared<ScriptExecutedCallback>(std::move(callback));
  auto timeout = std::make_shared<UINT_PTR>(0);
  auto reply = [weak, complete, timeout](bool success, const std::string &data) {
    if (!*complete) return;
    CancelWebviewTimeout(*timeout);
    *timeout = 0;
    auto callback = std::move(*complete);
    const auto state = weak.lock();
    callback(success && state && state->owner, data);
  };
  *timeout = ScheduleWebviewTimeout([reply]() { reply(false, ""); }, 30000);
  if (!*timeout) {
    reply(false, "");
    return;
  }
  HRESULT hr = webview_->CallDevToolsProtocolMethod(
      util::Utf16FromUtf8(method).c_str(), util::Utf16FromUtf8(params).c_str(),
      Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
          [reply](HRESULT error, LPCWSTR data) {
            reply(SUCCEEDED(error), data ? util::Utf8FromUtf16(data) : "");
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) reply(false, "");
}

bool Webview::SupportsNewWindows() {
  if (!IsValid()) return false;
  auto view = webview_.try_query<ICoreWebView2_13>();
  wil::com_ptr<ICoreWebView2Profile> profile;
  BOOL private_mode = TRUE;
  return view && SUCCEEDED(view->get_Profile(profile.put())) && profile &&
         SUCCEEDED(profile->get_IsInPrivateModeEnabled(&private_mode));
}

void Webview::SetNewWindowDelegateEnabled(bool enabled) {
  new_window_delegate_enabled_ = enabled && SupportsNewWindows();
  if (!new_window_delegate_enabled_) {
    while (!pending_windows_.empty())
      CompleteNewWindow(pending_windows_.begin()->first, nullptr);
  }
}

bool Webview::CompleteNewWindow(const std::string &id, Webview *child) {
  const auto item = pending_windows_.find(id);
  if (item == pending_windows_.end()) return false;
  auto pending = item->second;
  pending_windows_.erase(item);
  CancelWebviewTimeout(pending->timeout);
  bool attached = false;
  // Private views use independent profiles; never attach a controller from
  // another store.
  if (new_window_delegate_enabled_ &&
      popup_window_policy_ != WebviewPopupWindowPolicy::Deny && child &&
      child != this && child->IsValid() && child->host_ == host_ &&
      child->window_target_available_ && SupportsNewWindows() &&
      child->SupportsNewWindows()) {
    wil::com_ptr<ICoreWebView2Profile> parent_profile, child_profile;
    auto parent_view = webview_.try_query<ICoreWebView2_13>();
    auto child_view = child->webview_.try_query<ICoreWebView2_13>();
    wil::unique_cotaskmem_string parent_name, child_name;
    BOOL parent_private = FALSE, child_private = FALSE;
    if (SUCCEEDED(parent_view->get_Profile(parent_profile.put())) &&
        parent_profile &&
        SUCCEEDED(child_view->get_Profile(child_profile.put())) &&
        child_profile &&
        SUCCEEDED(parent_profile->get_ProfileName(&parent_name)) &&
        parent_name && SUCCEEDED(child_profile->get_ProfileName(&child_name)) &&
        child_name && wcscmp(parent_name.get(), child_name.get()) == 0 &&
        SUCCEEDED(parent_profile->get_IsInPrivateModeEnabled(&parent_private)) &&
        SUCCEEDED(child_profile->get_IsInPrivateModeEnabled(&child_private)) &&
        parent_private == child_private) {
      attached = SUCCEEDED(pending->args->put_NewWindow(child->webview_.get()));
      if (attached) child->window_target_available_ = false;
    }
  }
  pending->args->put_Handled(TRUE);
  pending->deferral->Complete();
  return attached;
}

bool Webview::SupportsPdf() {
  return IsValid() && !!webview_.try_query<ICoreWebView2_16>();
}

void Webview::CompleteCapture(std::shared_ptr<PendingCapture> request,
                              IStream *stream, const std::string &error) {
  if (!request || pending_capture_ != request) return;
  pending_capture_.reset();
  CancelWebviewTimeout(request->timeout);
  std::vector<uint8_t> bytes;
  std::string failure = error;
  constexpr size_t max_bytes = 64 * 1024 * 1024;
  if (failure.empty() && stream) {
    STATSTG info{};
    LARGE_INTEGER start{};
    if (FAILED(stream->Stat(&info, STATFLAG_NONAME)) ||
        info.cbSize.QuadPart == 0 || info.cbSize.QuadPart > max_bytes ||
        FAILED(stream->Seek(start, STREAM_SEEK_SET, nullptr))) {
      failure =
          "The capture is empty, unreadable or exceeds the export size limit.";
    } else {
      bytes.resize(static_cast<size_t>(info.cbSize.QuadPart));
      ULONG read = 0;
      if (FAILED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()),
                              &read)) ||
          read != bytes.size()) {
        bytes.clear();
        failure = "Reading the native capture failed.";
      }
    }
  } else if (failure.empty())
    failure = "The native capture produced no data.";
  auto completion = std::move(request->completion);
  completion(std::move(bytes), failure);
}

void Webview::CapturePage(bool pdf, CaptureCallback callback,
                          std::optional<PdfOptions> options) {
  if (!IsValid() || pending_capture_) {
    callback({}, "The WebView is closed or another capture is in progress.");
    return;
  }
  const double pixel_width = std::ceil(surface_width_ * scale_factor_);
  const double pixel_height = std::ceil(surface_height_ * scale_factor_);
  if (!pdf && (pixel_width <= 0 || pixel_height <= 0 ||
               pixel_width > 16 * 1024 * 1024 / pixel_height)) {
    callback({}, "The viewport is empty or exceeds the capture size limit.");
    return;
  }
  auto request = std::make_shared<PendingCapture>();
  request->completion = std::move(callback);
  pending_capture_ = request;
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  request->timeout = ScheduleWebviewTimeout(
      [weak, request]() {
        const auto state = weak.lock();
        if (state && state->owner)
          state->owner->CompleteCapture(request, nullptr,
                                        "The native capture timed out.");
      },
      30000);
  if (!request->timeout) {
    CompleteCapture(request, nullptr,
                    "Creating the native capture timeout failed.");
    return;
  }
  auto complete = [weak, request](HRESULT hr, IStream *stream) {
    const auto state = weak.lock();
    if (state && state->owner)
      state->owner->CompleteCapture(
          request, stream,
          SUCCEEDED(hr) ? ""
                        : "The native page capture failed or is unavailable.");
  };
  HRESULT hr;
  if (pdf) {
    auto view = webview_.try_query<ICoreWebView2_16>();
    if (!view) {
      complete(E_NOINTERFACE, nullptr);
      return;
    }
    wil::com_ptr<ICoreWebView2PrintSettings> settings;
    if (options) {
      settings = host_->CreatePrintSettings();
      if (!settings) { complete(E_NOINTERFACE, nullptr); return; }
      // Public settings use inches; the common interface uses points.
      HRESULT configured = settings->put_PageWidth(options->width / 72.0);
      if (SUCCEEDED(configured)) configured = settings->put_PageHeight(options->height / 72.0);
      if (SUCCEEDED(configured)) configured = settings->put_MarginTop(options->top / 72.0);
      if (SUCCEEDED(configured)) configured = settings->put_MarginBottom(options->bottom / 72.0);
      if (SUCCEEDED(configured)) configured = settings->put_MarginLeft(options->left / 72.0);
      if (SUCCEEDED(configured)) configured = settings->put_MarginRight(options->right / 72.0);
      if (SUCCEEDED(configured)) configured = settings->put_Orientation(options->landscape ? COREWEBVIEW2_PRINT_ORIENTATION_LANDSCAPE : COREWEBVIEW2_PRINT_ORIENTATION_PORTRAIT);
      if (FAILED(configured)) { complete(configured, nullptr); return; }
    }
    hr = view->PrintToPdfStream(
        settings.get(), Callback<ICoreWebView2PrintToPdfStreamCompletedHandler>(
                     [complete](HRESULT error, IStream *stream) {
                       complete(error, stream);
                       return S_OK;
                     })
                     .Get());
  } else {
    hr = CreateStreamOnHGlobal(nullptr, TRUE, request->stream.put());
    if (SUCCEEDED(hr))
      hr = webview_->CapturePreview(
          COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, request->stream.get(),
          Callback<ICoreWebView2CapturePreviewCompletedHandler>(
              [complete, request](HRESULT error) {
                complete(error, request->stream.get());
                return S_OK;
              })
              .Get());
  }
  if (FAILED(hr)) complete(hr, nullptr);
}

bool Webview::SupportsFind() {
  if (!IsValid()) return false;
  auto view = webview_.try_query<ICoreWebView2_28>();
  if (!view || !host_->CreateFindOptions()) return false;
  if (!find_) view->get_Find(find_.put());
  return find_ != nullptr;
}

bool Webview::ShowPrintUI() {
  if (!IsValid() || pending_capture_) return false;
  auto view = webview_.try_query<ICoreWebView2_16>();
  return view && SUCCEEDED(view->ShowPrintUI(COREWEBVIEW2_PRINT_DIALOG_KIND_SYSTEM));
}
bool Webview::SetNativeContextMenus(bool enabled) {
  if (!IsValid()) return false;
  wil::com_ptr<ICoreWebView2Settings> settings;
  return SUCCEEDED(webview_->get_Settings(settings.put())) && settings && SUCCEEDED(settings->put_AreDefaultContextMenusEnabled(enabled ? TRUE : FALSE));
}
bool Webview::SupportsAudioMuting() { return IsValid() && !!webview_.try_query<ICoreWebView2_8>(); }
bool Webview::SetAudioMuted(bool muted) {
  if (!IsValid()) return false;
  auto view = webview_.try_query<ICoreWebView2_8>();
  return view && SUCCEEDED(view->put_IsMuted(muted ? TRUE : FALSE));
}

void Webview::CompleteFind(std::shared_ptr<PendingFind> pending,
                           bool available) {
  if (!pending || pending_find_ != pending) return;
  pending_find_.reset();
  if (pending->subscribed && find_)
    find_->remove_ActiveMatchIndexChanged(pending->token);
  CancelWebviewTimeout(pending->timeout);
  INT32 count = 0, active = -1;
  if (available && find_) {
    available = SUCCEEDED(find_->get_MatchCount(&count)) &&
                SUCCEEDED(find_->get_ActiveMatchIndex(&active));
  }
  auto completion = std::move(pending->completion);
  if (completion) completion(available, count, active > 0 ? active - 1 : -1);
}

void Webview::AdvanceFind(std::shared_ptr<PendingFind> pending, bool forward) {
  INT32 count = 0;
  if (!find_ || FAILED(find_->get_MatchCount(&count))) {
    CompleteFind(pending, false);
    return;
  }
  if (count <= 1) {
    CompleteFind(pending, true);
    return;
  }
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  HRESULT hr = find_->add_ActiveMatchIndexChanged(
      Callback<ICoreWebView2FindActiveMatchIndexChangedEventHandler>(
          [weak, pending](ICoreWebView2Find *, IUnknown *) {
            const auto state = weak.lock();
            if (state && state->owner)
              state->owner->CompleteFind(pending, true);
            return S_OK;
          })
          .Get(),
      &pending->token);
  pending->subscribed = SUCCEEDED(hr);
  if (SUCCEEDED(hr)) hr = forward ? find_->FindNext() : find_->FindPrevious();
  if (FAILED(hr)) CompleteFind(pending, false);
}

void Webview::FindText(const std::string &text, bool forward,
                       bool case_sensitive, FindCallback callback) {
  if (!SupportsFind()) {
    callback(false, 0, -1);
    return;
  }
  if (pending_find_) CompleteFind(pending_find_, false);
  auto pending = std::make_shared<PendingFind>();
  pending->completion = std::move(callback);
  pending_find_ = pending;
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  pending->timeout = ScheduleWebviewTimeout(
      [weak, pending]() {
        const auto state = weak.lock();
        if (state && state->owner) state->owner->CompleteFind(pending, false);
      },
      10000);
  INT32 previous_count = 0;
  if (find_text_ == text && find_case_sensitive_ == case_sensitive &&
      SUCCEEDED(find_->get_MatchCount(&previous_count)) && previous_count > 0) {
    AdvanceFind(pending, forward);
    return;
  }
  find_->Stop();
  find_text_ = text;
  find_case_sensitive_ = case_sensitive;
  auto options = host_->CreateFindOptions();
  if (!options) {
    CompleteFind(pending, false);
    return;
  }
  options->put_FindTerm(util::Utf16FromUtf8(text).c_str());
  options->put_IsCaseSensitive(case_sensitive);
  options->put_ShouldHighlightAllMatches(TRUE);
  options->put_SuppressDefaultFindDialog(TRUE);
  const HRESULT hr = find_->Start(
      options.get(),
      Callback<ICoreWebView2FindStartCompletedHandler>([weak, pending, forward](
                                                           HRESULT error) {
        const auto state = weak.lock();
        if (!state || !state->owner || state->owner->pending_find_ != pending)
          return S_OK;
        if (FAILED(error))
          state->owner->CompleteFind(pending, false);
        else if (!forward)
          state->owner->AdvanceFind(pending, false);
        else
          state->owner->CompleteFind(pending, true);
        return S_OK;
      }).Get());
  if (FAILED(hr)) CompleteFind(pending, false);
}

void Webview::ClearFind() {
  if (pending_find_) CompleteFind(pending_find_, false);
  if (find_) find_->Stop();
  find_text_.clear();
}

bool Webview::Reload() {
  if (!IsValid()) {
    return false;
  }
  InvalidatePendingNavigationRequests();
  ++bypass_next_navigation_count_;
  if (FAILED(webview_->Reload())) {
    --bypass_next_navigation_count_;
    return false;
  }
  return true;
}

bool Webview::GoBack() {
  if (!IsValid()) {
    return false;
  }
  BOOL can_go_back = FALSE;
  if (FAILED(webview_->get_CanGoBack(&can_go_back)) || can_go_back != TRUE) {
    return false;
  }
  InvalidatePendingNavigationRequests();
  ++bypass_next_navigation_count_;
  if (FAILED(webview_->GoBack())) {
    --bypass_next_navigation_count_;
    return false;
  }
  return true;
}

bool Webview::GoForward() {
  if (!IsValid()) {
    return false;
  }
  BOOL can_go_forward = FALSE;
  if (FAILED(webview_->get_CanGoForward(&can_go_forward)) ||
      can_go_forward != TRUE) {
    return false;
  }
  InvalidatePendingNavigationRequests();
  ++bypass_next_navigation_count_;
  if (FAILED(webview_->GoForward())) {
    --bypass_next_navigation_count_;
    return false;
  }
  return true;
}

void Webview::AddScriptToExecuteOnDocumentCreated(
    const std::string &script,
    AddScriptToExecuteOnDocumentCreatedCallback callback) {
  if (IsValid()) {
    if (SUCCEEDED(webview_->AddScriptToExecuteOnDocumentCreated(
            util::Utf16FromUtf8(script).c_str(),
            Callback<
                ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
                [callback](HRESULT result, LPCWSTR wsid) -> HRESULT {
                  if (SUCCEEDED(result) && wsid != nullptr) {
                    callback(true, util::Utf8FromUtf16(wsid));
                  } else {
                    callback(false, std::string());
                  }
                  return S_OK;
                })
                .Get()))) {
      return;
    }
  }

  callback(false, std::string());
}

bool Webview::RemoveScriptToExecuteOnDocumentCreated(
    const std::string &script_id) {
  if (!IsValid()) {
    return false;
  }
  return SUCCEEDED(webview_->RemoveScriptToExecuteOnDocumentCreated(
      util::Utf16FromUtf8(script_id).c_str()));
}

void Webview::ExecuteScript(const std::string &script,
                            ScriptExecutedCallback callback) {
  if (IsValid()) {
    if (SUCCEEDED(webview_->ExecuteScript(
            util::Utf16FromUtf8(script).c_str(),
            Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
                [callback](HRESULT result, LPCWSTR json_result_object) {
                  callback(SUCCEEDED(result),
                           util::Utf8FromUtf16(json_result_object));
                  return S_OK;
                })
                .Get()))) {
      return;
    }
  }

  callback(false, std::string());
}

bool Webview::PostWebMessage(const std::string &json) {
  if (!IsValid()) {
    return false;
  }
  return webview_->PostWebMessageAsJson(util::Utf16FromUtf8(json).c_str()) ==
         S_OK;
}

bool Webview::Suspend() {
  if (!IsValid()) {
    return false;
  }

  wil::com_ptr<ICoreWebView2_3> webview = webview_.try_query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }

  return SUCCEEDED(SetVisible(false)) &&
         webview->TrySuspend(
             Callback<ICoreWebView2TrySuspendCompletedHandler>(
                 [](HRESULT error_code, BOOL is_successful) -> HRESULT {
                   return S_OK;
                 })
                 .Get()) == S_OK;
}

bool Webview::Resume() {
  if (!IsValid()) {
    return false;
  }

  wil::com_ptr<ICoreWebView2_3> webview = webview_.try_query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }
  return webview->Resume() == S_OK;
}

bool Webview::SetVirtualHostNameMapping(
    const std::string &hostName, const std::string &path,
    WebviewHostResourceAccessKind accessKind) {
  if (!IsValid()) {
    return false;
  }

  wil::com_ptr<ICoreWebView2_3> webview;
  webview = webview_.query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }

  COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND accessKindIntValue =
      COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY;
  switch (accessKind) {
  case WebviewHostResourceAccessKind::Allow:
    accessKindIntValue = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW;
    break;
  case WebviewHostResourceAccessKind::DenyCors:
    accessKindIntValue = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS;
    break;
  case WebviewHostResourceAccessKind::Deny:
    accessKindIntValue = COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY;
    break;
  }

  return webview->SetVirtualHostNameToFolderMapping(
      util::Utf16FromUtf8(hostName).c_str(), util::Utf16FromUtf8(path).c_str(),
      accessKindIntValue);
}

bool Webview::ClearVirtualHostNameMapping(const std::string &hostName) {
  if (!IsValid()) {
    return false;
  }

  wil::com_ptr<ICoreWebView2_3> webview;
  webview = webview_.query<ICoreWebView2_3>();
  if (!webview) {
    return false;
  }

  return webview->ClearVirtualHostNameToFolderMapping(
      util::Utf16FromUtf8(hostName).c_str());
}

HRESULT Webview::SetDownloadDelegateEnabled(bool enabled) {
  if (enabled && FAILED(download_handler_result_))
    return download_handler_result_;
  // Every successful setter call replaces the handler, even true -> true.
  // Existing tasks retain their owner; only unresolved decisions are cancelled.
  CancelPendingDownloads();
  download_delegate_enabled_ = enabled;
  return S_OK;
}

HRESULT Webview::ConfigureResources(flutter::BinaryMessenger *messenger,
                                    const std::string &channel,
                                    const std::string &host, bool enabled) {
  if (!resource_bridge_)
    resource_bridge_ = std::make_unique<ResourceBridgeWindows>(webview_.get());
  return resource_bridge_->Configure(messenger, channel, host, enabled);
}
HRESULT Webview::ConfigureNetworkBridge(flutter::BinaryMessenger* messenger,
    const flutter::EncodableMap& configuration) {
  if (!IsValid()) return E_ABORT;
  if (!resource_bridge_) resource_bridge_ = std::make_unique<ResourceBridgeWindows>(webview_.get());
  return resource_bridge_->ConfigureNetwork(messenger, configuration);
}
HRESULT Webview::ConfigureContentRules(const flutter::EncodableList& rules) {
  if (!IsValid()) return E_ABORT;
  if (!resource_bridge_) resource_bridge_ = std::make_unique<ResourceBridgeWindows>(webview_.get());
  return resource_bridge_->ConfigureRules(rules);
}

HRESULT Webview::StartDownload(ICoreWebView2DownloadStartingEventArgs *args) {
  const std::string id = std::to_string(++next_download_id_);
  wil::com_ptr<ICoreWebView2DownloadOperation> operation;
  if (FAILED(args->get_DownloadOperation(operation.put())) || !operation) {
    args->put_Cancel(TRUE);
    return E_FAIL;
  }
  wil::unique_cotaskmem_string uri, path, mime, disposition;
  operation->get_Uri(&uri);
  args->get_ResultFilePath(&path);
  operation->get_MimeType(&mime);
  operation->get_ContentDisposition(&disposition);
  INT64 total = -1;
  operation->get_TotalBytesToReceive(&total);
  const std::string url = uri ? util::Utf8FromUtf16(uri.get()) : "";
  // Account for either native event ordering, using the most recent matching
  // top-level navigation rather than suppressing every aborted load.
  const auto deferred = std::find_if(
      deferred_download_navigation_errors_.rbegin(),
      deferred_download_navigation_errors_.rend(),
      [&url](const auto &entry) { return entry.second.url == url; });
  const auto navigating =
      std::find_if(navigation_urls_.rbegin(), navigation_urls_.rend(),
                   [&url](const auto &entry) { return entry.second == url; });
  if (deferred != deferred_download_navigation_errors_.rend() &&
      (navigating == navigation_urls_.rend() ||
       deferred->first > navigating->first)) {
    CancelWebviewTimeout(deferred->second.timer);
    deferred_download_navigation_errors_.erase(deferred->first);
  } else if (navigating != navigation_urls_.rend()) {
    download_navigation_ids_.insert(navigating->first);
  }
  const std::string destination = path ? util::Utf8FromUtf16(path.get()) : "";
  if (!downloads_enabled_) {
    const HRESULT result = args->put_Cancel(TRUE);
    if (download_event_callback_) {
      download_event_callback_(
          {SUCCEEDED(result) ? WebviewDownloadEventKind::DownloadCancelled
                             : WebviewDownloadEventKind::DownloadFailed,
           url, destination, 0, total, id,
           SUCCEEDED(result) ? "" : "download_cancel_failed", "",
           download_delegate_enabled_});
    }
    return result;
  }
  // The WebView is rendered through a texture at offscreen native bounds.
  // Download UI belongs to the host application, not this invisible surface.
  args->put_Handled(TRUE);
  if (!download_delegate_enabled_) {
    TrackDownload(id, operation.get(), false);
    return S_OK;
  }
  auto pending = std::make_shared<PendingDownload>();
  pending->request = {
      id,
      url,
      path ? util::Utf8FromUtf16(
                 std::filesystem::path(path.get()).filename().wstring())
           : "",
      mime ? util::Utf8FromUtf16(mime.get()) : "",
      disposition ? util::Utf8FromUtf16(disposition.get()) : "",
      total};
  pending->args = args;
  pending->operation = operation;
  if (FAILED(args->GetDeferral(pending->deferral.put())) ||
      !pending->deferral) {
    args->put_Cancel(TRUE);
    if (download_event_callback_)
      download_event_callback_({WebviewDownloadEventKind::DownloadFailed, url,
                                "", 0, total, id, "download_deferral_failed",
                                "The download could not wait for a decision.",
                                true});
    return S_OK;
  }
  pending_downloads_[id] = pending;
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  pending->timeout = ScheduleWebviewTimeout([weak, id]() {
    const auto state = weak.lock();
    if (!state || !state->owner)
      return;
    const auto found = state->owner->pending_downloads_.find(id);
    if (found != state->owner->pending_downloads_.end())
      state->owner->ResolveDownload(found->second,
                                    {"cancel", "", "download_decision_timeout",
                                     "The download decision timed out."});
  });
  if (pending->timeout == 0 || !download_requested_callback_) {
    ResolveDownload(pending, {"cancel", "", "download_delegate_unavailable",
                              "The download delegate is unavailable."});
    return S_OK;
  }
  download_requested_callback_(
      pending->request, [weak, pending](WebviewDownloadDecision decision) {
        const auto state = weak.lock();
        if (state && state->owner)
          state->owner->ResolveDownload(pending, decision);
      });
  return S_OK;
}

void Webview::ResolveDownload(std::shared_ptr<PendingDownload> pending,
                              const WebviewDownloadDecision &decision) {
  if (pending->completed)
    return;
  pending->completed = true;
  CancelWebviewTimeout(pending->timeout);
  pending_downloads_.erase(pending->request.id);
  std::string error = decision.error_code;
  std::string description = decision.description;
  std::wstring directory, temporary, target;
  bool proceed = error.empty() && (decision.action == "platformDefault" ||
                                   decision.action == "saveToFile");
  if (proceed && decision.action == "saveToFile") {
    if (!PrepareDownloadTarget(decision.path, directory, temporary, target) ||
        FAILED(pending->args->put_ResultFilePath(temporary.c_str()))) {
      proceed = false;
      error = "invalid_download_destination";
      description = "The file target must be absolute, new, and inside an "
                    "existing directory.";
      RemoveOwnedDownloadDirectory(directory);
      directory.clear();
    }
  }
  if (proceed) {
    TrackDownload(pending->request.id, pending->operation.get(), true,
                  directory, target);
  } else {
    const HRESULT cancelled = pending->args->put_Cancel(TRUE);
    if (FAILED(cancelled) && error.empty())
      error = "download_cancel_failed";
    if (decision.action != "cancel" && decision.action != "handledExternally" &&
        error.empty())
      error = "invalid_download_decision";
    const auto kind = !error.empty() ? WebviewDownloadEventKind::DownloadFailed
                      : decision.action == "handledExternally"
                          ? WebviewDownloadEventKind::DownloadHandedOff
                          : WebviewDownloadEventKind::DownloadCancelled;
    if (download_event_callback_)
      download_event_callback_({kind, pending->request.url, "", 0,
                                pending->request.content_length,
                                pending->request.id, error, description, true});
  }
  pending->deferral->Complete();
  pending->deferral = nullptr;
  pending->args = nullptr;
  pending->operation = nullptr;
}

void Webview::TrackDownload(const std::string &id,
                            ICoreWebView2DownloadOperation *operation,
                            bool managed, const std::wstring &directory,
                            const std::wstring &target) {
  auto active = std::make_shared<ActiveDownload>();
  active->id = id;
  active->operation = operation;
  active->managed = managed;
  active->temporary_directory = directory;
  active->target = target;
  active_downloads_[id] = active;
  const std::weak_ptr<LifetimeState> weak = lifetime_state_;
  const std::weak_ptr<ActiveDownload> weak_download = active;
  const HRESULT bytes_result = operation->add_BytesReceivedChanged(
      Callback<ICoreWebView2BytesReceivedChangedEventHandler>(
          [weak, weak_download](ICoreWebView2DownloadOperation *,
                                IUnknown *) -> HRESULT {
            const auto state = weak.lock();
            const auto download = weak_download.lock();
            if (state && state->owner && download)
              state->owner->ReportDownloadState(download);
            return S_OK;
          })
          .Get(),
      &active->bytes_token);
  const HRESULT state_result = operation->add_StateChanged(
      Callback<ICoreWebView2StateChangedEventHandler>(
          [weak, weak_download](ICoreWebView2DownloadOperation *,
                                IUnknown *) -> HRESULT {
            const auto state = weak.lock();
            const auto download = weak_download.lock();
            if (state && state->owner && download)
              state->owner->ReportDownloadState(download);
            return S_OK;
          })
          .Get(),
      &active->state_token);
  if (FAILED(bytes_result) || FAILED(state_result)) {
    FinishDownload(active, WebviewDownloadEventKind::DownloadFailed,
                   "download_observer_failed",
                   "Download progress could not be observed.");
    return;
  }
  wil::unique_cotaskmem_string uri, path;
  operation->get_Uri(&uri);
  operation->get_ResultFilePath(&path);
  INT64 total = -1;
  operation->get_TotalBytesToReceive(&total);
  if (download_event_callback_)
    download_event_callback_({WebviewDownloadEventKind::DownloadStarted,
                              uri ? util::Utf8FromUtf16(uri.get()) : "",
                              path ? util::Utf8FromUtf16(path.get()) : "", 0,
                              total, id, "", "", managed});
}

void Webview::ReportDownloadState(
    const std::shared_ptr<ActiveDownload> &download) {
  if (download->completed)
    return;
  COREWEBVIEW2_DOWNLOAD_STATE state;
  if (FAILED(download->operation->get_State(&state))) {
    FinishDownload(download, WebviewDownloadEventKind::DownloadFailed,
                   "download_state_failed");
    return;
  }
  if (state == COREWEBVIEW2_DOWNLOAD_STATE_COMPLETED) {
    if (!download->target.empty()) {
      const std::wstring temporary =
          (std::filesystem::path(download->temporary_directory) / L"payload")
              .wstring();
      if (!MoveFileW(temporary.c_str(), download->target.c_str())) {
        FinishDownload(download, WebviewDownloadEventKind::DownloadFailed,
                       "download_publish_failed",
                       "Saving the completed download failed; existing files "
                       "were not replaced.");
        return;
      }
    }
    FinishDownload(download, WebviewDownloadEventKind::DownloadCompleted);
    return;
  }
  if (state == COREWEBVIEW2_DOWNLOAD_STATE_INTERRUPTED) {
    COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON reason =
        COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON_NONE;
    if (FAILED(download->operation->get_InterruptReason(&reason))) {
      FinishDownload(download, WebviewDownloadEventKind::DownloadFailed,
                     "download_interrupted");
      return;
    }
    FinishDownload(
        download,
        reason == COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON_USER_CANCELED
            ? WebviewDownloadEventKind::DownloadCancelled
            : WebviewDownloadEventKind::DownloadFailed,
        reason == COREWEBVIEW2_DOWNLOAD_INTERRUPT_REASON_USER_CANCELED
            ? ""
            : std::to_string(static_cast<int>(reason)));
    return;
  }
  wil::unique_cotaskmem_string uri, path;
  INT64 bytes = 0, total = -1;
  download->operation->get_Uri(&uri);
  download->operation->get_ResultFilePath(&path);
  download->operation->get_BytesReceived(&bytes);
  download->operation->get_TotalBytesToReceive(&total);
  if (download_event_callback_)
    download_event_callback_({WebviewDownloadEventKind::DownloadProgress,
                              uri ? util::Utf8FromUtf16(uri.get()) : "",
                              path ? util::Utf8FromUtf16(path.get()) : "",
                              bytes, total, download->id, "", "",
                              download->managed});
}

void Webview::FinishDownload(const std::shared_ptr<ActiveDownload> &download,
                             WebviewDownloadEventKind kind,
                             const std::string &error,
                             const std::string &description) {
  if (download->completed)
    return;
  download->completed = true;
  download->operation->remove_BytesReceivedChanged(download->bytes_token);
  download->operation->remove_StateChanged(download->state_token);
  // A reported terminal failure must not later resume silently. Detach first
  // so Cancel cannot turn this failure into a reentrant cancellation result.
  if (kind == WebviewDownloadEventKind::DownloadFailed)
    download->operation->Cancel();
  wil::unique_cotaskmem_string uri, path;
  INT64 bytes = 0, total = -1;
  download->operation->get_Uri(&uri);
  download->operation->get_ResultFilePath(&path);
  download->operation->get_BytesReceived(&bytes);
  download->operation->get_TotalBytesToReceive(&total);
  const std::string result_path =
      !download->target.empty()
          ? (kind == WebviewDownloadEventKind::DownloadCompleted
                 ? util::Utf8FromUtf16(download->target)
                 : "")
          : (path ? util::Utf8FromUtf16(path.get()) : "");
  RemoveOwnedDownloadDirectory(download->temporary_directory);
  active_downloads_.erase(download->id);
  if (download_event_callback_)
    download_event_callback_({kind, uri ? util::Utf8FromUtf16(uri.get()) : "",
                              result_path, bytes, total, download->id, error,
                              description, download->managed});
}

void Webview::CancelPendingDownloads() {
  const auto pending = pending_downloads_;
  for (const auto &entry : pending)
    ResolveDownload(entry.second, {});
}

void Webview::DisposeDownloads() {
  for (const auto &entry : deferred_download_navigation_errors_)
    CancelWebviewTimeout(entry.second.timer);
  deferred_download_navigation_errors_.clear();
  navigation_urls_.clear();
  download_navigation_ids_.clear();
  CancelPendingDownloads();
  const auto active = active_downloads_;
  for (const auto &entry : active) {
    if (entry.second->managed)
      entry.second->operation->Cancel();
    FinishDownload(entry.second, WebviewDownloadEventKind::DownloadCancelled);
  }
}

} // namespace webview_all_windows
