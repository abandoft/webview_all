#include "webview/webview_internal.h"
#include "common/method_channel_utils.h"
#include <memory>
#include <string>
#include <vector>
#include <algorithm>
#include <cstring>
#include <cmath>
#include <unordered_map>
#include <unistd.h>
#include <glib/gstdio.h>

namespace {
struct NavigationSnapshot {
  WebKitWebViewSessionState* data;
  WebKitWebContext* context;
  explicit NavigationSnapshot(WebKitWebView* view)
      : data(webkit_web_view_get_session_state(view)),
        context(WEBKIT_WEB_CONTEXT(
            g_object_ref(webkit_web_view_get_context(view)))) {}
  ~NavigationSnapshot() {
    if (data) webkit_web_view_session_state_unref(data);
    g_object_unref(context);
  }
};
std::unordered_map<
    WebviewAllLinuxPlugin*,
    std::unordered_map<std::string, std::shared_ptr<NavigationSnapshot>>>
    navigation_snapshots;
struct NativePrintJob {
  std::string state = "presented";
};
std::unordered_map<
    WebviewAllLinuxPlugin*,
    std::unordered_map<std::string, std::shared_ptr<NativePrintJob>>>
    print_jobs;
struct FileSelection {
  WebKitFileChooserRequest* request;
  explicit FileSelection(WebKitFileChooserRequest* value)
      : request(WEBKIT_FILE_CHOOSER_REQUEST(g_object_ref(value))) {}
  void cancel() {
    if (!request) return;
    webkit_file_chooser_request_cancel(request);
    g_object_unref(request);
    request = nullptr;
  }
  ~FileSelection() { cancel(); }
};
constexpr size_t kMaxCaptureBytes = 64 * 1024 * 1024;
struct PageCapture : public std::enable_shared_from_this<PageCapture> {
  FlMethodCall* call;
  GCancellable* cancelled = g_cancellable_new();
  guint timer = 0;
  WebKitPrintOperation* print = nullptr;
  gulong failed_signal = 0;
  gulong finished_signal = 0;
  std::string path;
  std::string error;
  bool full_document = false;
  explicit PageCapture(FlMethodCall* value)
      : call(FL_METHOD_CALL(g_object_ref(value))) {}
  ~PageCapture() {
    if (timer) g_source_remove(timer);
    g_object_unref(cancelled);
    if (print) g_object_unref(print);
    if (!path.empty()) g_unlink(path.c_str());
    if (call) g_object_unref(call);
  }
  void finish(const std::vector<uint8_t>* bytes,
              const char* message = nullptr) {
    if (!call) return;
    auto* reply = call;
    call = nullptr;
    if (timer) {
      g_source_remove(timer);
      timer = 0;
    }
    g_cancellable_cancel(cancelled);
    if (bytes && !bytes->empty())
      respond(reply, success_response(fl_value_new_uint8_list(bytes->data(),
                                                              bytes->size())));
    else
      respond(reply, FL_METHOD_RESPONSE(fl_method_error_response_new(
                         "capture_failed",
                         message ? message : "The capture produced no data.",
                         nullptr)));
    g_object_unref(reply);
  }
  static void release(gpointer value) {
    delete static_cast<std::shared_ptr<PageCapture>*>(value);
  }
  void start_timer() {
    timer = g_timeout_add_full(
        G_PRIORITY_DEFAULT, 30000,
        [](gpointer data) -> gboolean {
          auto request = *static_cast<std::shared_ptr<PageCapture>*>(data);
          request->timer = 0;
          request->finish(nullptr, "The native capture timed out.");
          return G_SOURCE_REMOVE;
        },
        new std::shared_ptr<PageCapture>(shared_from_this()), release);
  }
};
void capture_snapshot(WebKitWebView* webview,
                      std::shared_ptr<PageCapture> request) {
  const auto width = gtk_widget_get_allocated_width(GTK_WIDGET(webview));
  const auto height = gtk_widget_get_allocated_height(GTK_WIDGET(webview));
  const auto scale = gtk_widget_get_scale_factor(GTK_WIDGET(webview));
  if (width <= 0 || height <= 0 ||
      static_cast<uint64_t>(width) * height * scale * scale >
          kMaxCaptureBytes / 4) {
    request->finish(nullptr,
                    "The viewport is empty or exceeds the capture size limit.");
    return;
  }
  webkit_web_view_get_snapshot(
      webview, request->full_document ? WEBKIT_SNAPSHOT_REGION_FULL_DOCUMENT : WEBKIT_SNAPSHOT_REGION_VISIBLE, WEBKIT_SNAPSHOT_OPTIONS_NONE,
      request->cancelled,
      [](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::shared_ptr<PageCapture>> holder(
            static_cast<std::shared_ptr<PageCapture>*>(data));
        auto request = *holder;
        GError* error = nullptr;
        auto* surface = webkit_web_view_get_snapshot_finish(
            WEBKIT_WEB_VIEW(object), result, &error);
        if (!request->call) {
          if (surface) cairo_surface_destroy(surface);
          g_clear_error(&error);
          return;
        }
        if (!surface) {
          request->finish(
              nullptr, error ? error->message : "The native snapshot failed.");
          g_clear_error(&error);
          return;
        }
        const bool is_image = cairo_surface_get_type(surface) == CAIRO_SURFACE_TYPE_IMAGE;
        if ((!is_image && request->full_document) ||
            (is_image && static_cast<uint64_t>(cairo_image_surface_get_width(surface)) *
              cairo_image_surface_get_height(surface) > 16 * 1024 * 1024)) {
          cairo_surface_destroy(surface);
          request->finish(nullptr, "The document exceeds the 16 Mi pixel screenshot limit.");
          g_clear_error(&error); return;
        }
        std::vector<uint8_t> bytes;
        const auto status = cairo_surface_write_to_png_stream(
            surface,
            [](void* value, const unsigned char* buffer,
               unsigned int length) -> cairo_status_t {
              auto* bytes = static_cast<std::vector<uint8_t>*>(value);
              if (length > kMaxCaptureBytes - bytes->size())
                return CAIRO_STATUS_WRITE_ERROR;
              bytes->insert(bytes->end(), buffer, buffer + length);
              return CAIRO_STATUS_SUCCESS;
            },
            &bytes);
        cairo_surface_destroy(surface);
        request->finish(
            status == CAIRO_STATUS_SUCCESS ? &bytes : nullptr,
            "The native snapshot could not be encoded within the size limit.");
        g_clear_error(&error);
      },
      new std::shared_ptr<PageCapture>(request));
}
void capture_pdf(WebKitWebView* webview, std::shared_ptr<PageCapture> request,
                 FlValue* options) {
  double width = 0, height = 0, top = 0, bottom = 0, left = 0, right = 0;
  bool landscape = false;
  if (options && fl_value_get_type(options) != FL_VALUE_TYPE_NULL) {
    width = map_lookup_double(options, "paperWidth", NAN);
    height = map_lookup_double(options, "paperHeight", NAN);
    top = map_lookup_double(options, "marginTop", NAN);
    bottom = map_lookup_double(options, "marginBottom", NAN);
    left = map_lookup_double(options, "marginLeft", NAN);
    right = map_lookup_double(options, "marginRight", NAN);
    landscape = map_lookup_bool(options, "landscape", false);
    bool valid = true;
    for (auto v : {width, height, top, bottom, left, right})
      valid &= std::isfinite(v) && v >= 0 && v <= 14400;
    if (!valid || (landscape ? height : width) <= left + right ||
        (landscape ? width : height) <= top + bottom) {
      request->finish(nullptr, "Invalid PDF paper size or margins.");
      return;
    }
  }
  GError* error = nullptr;
  gchar* path = nullptr;
  const int descriptor =
      g_file_open_tmp("webview-all-pdf-XXXXXX", &path, &error);
  if (descriptor < 0) {
    request->finish(nullptr, error ? error->message
                                   : "Creating a PDF temporary file failed.");
    g_clear_error(&error);
    return;
  }
  close(descriptor);
  request->path = path;
  g_free(path);
  request->print = webkit_print_operation_new(webview);
  auto* settings = gtk_print_settings_new();
  auto* uri = g_filename_to_uri(request->path.c_str(), nullptr, nullptr);
  // GTK localizes the virtual printer name; never fall back to the default
  // printer.
  gtk_print_settings_set_printer(settings,
                                 g_dgettext("gtk30", "Print to File"));
  gtk_print_settings_set(settings, GTK_PRINT_SETTINGS_OUTPUT_FILE_FORMAT,
                         "pdf");
  gtk_print_settings_set(settings, GTK_PRINT_SETTINGS_OUTPUT_URI, uri);
  g_free(uri);
  webkit_print_operation_set_print_settings(request->print, settings);
  g_object_unref(settings);
  auto* setup = gtk_page_setup_new();
  auto* paper = width > 0
                    ? gtk_paper_size_new_custom("webview-all", "Custom", width,
                                                height, GTK_UNIT_POINTS)
                    : gtk_paper_size_new(GTK_PAPER_NAME_A4);
  gtk_page_setup_set_paper_size(setup, paper);
  gtk_paper_size_free(paper);
  if (width > 0) {
    gtk_page_setup_set_orientation(setup, landscape
                                              ? GTK_PAGE_ORIENTATION_LANDSCAPE
                                              : GTK_PAGE_ORIENTATION_PORTRAIT);
    gtk_page_setup_set_top_margin(setup, top, GTK_UNIT_POINTS);
    gtk_page_setup_set_bottom_margin(setup, bottom, GTK_UNIT_POINTS);
    gtk_page_setup_set_left_margin(setup, left, GTK_UNIT_POINTS);
    gtk_page_setup_set_right_margin(setup, right, GTK_UNIT_POINTS);
  }
  webkit_print_operation_set_page_setup(request->print, setup);
  g_object_unref(setup);
  request->failed_signal = g_signal_connect(
      request->print, "failed",
      G_CALLBACK(+[](WebKitPrintOperation*, GError* error, gpointer data) {
        auto* request = static_cast<PageCapture*>(data);
        request->error = error ? error->message : "PDF export failed.";
      }),
      request.get());
  request->finished_signal = g_signal_connect_data(
      request->print, "finished",
      G_CALLBACK(+[](WebKitPrintOperation*, gpointer data) {
        auto request = *static_cast<std::shared_ptr<PageCapture>*>(data);
        if (request->call && request->error.empty()) {
          GStatBuf status;
          gchar* contents = nullptr;
          gsize size = 0;
          if (g_stat(request->path.c_str(), &status) == 0 &&
              status.st_size > 0 &&
              static_cast<uint64_t>(status.st_size) <= kMaxCaptureBytes &&
              g_file_get_contents(request->path.c_str(), &contents, &size,
                                  nullptr)) {
            std::vector<uint8_t> bytes(contents, contents + size);
            request->finish(&bytes);
          } else
            request->finish(nullptr,
                            "The PDF is empty, unreadable or exceeds the "
                            "export size limit.");
          g_free(contents);
        } else if (request->call)
          request->finish(nullptr, request->error.c_str());
        auto* recent_uri =
            g_filename_to_uri(request->path.c_str(), nullptr, nullptr);
        if (recent_uri) {
          // GTK records the file after invoking its print completion callback.
          g_idle_add_full(
              G_PRIORITY_DEFAULT_IDLE,
              [](gpointer uri) -> gboolean {
                gtk_recent_manager_remove_item(gtk_recent_manager_get_default(),
                                               static_cast<const gchar*>(uri),
                                               nullptr);
                return G_SOURCE_REMOVE;
              },
              recent_uri, g_free);
        }
        g_unlink(request->path.c_str());
        request->path.clear();
        // A cancelled print must retain its temporary file until the native job
        // finishes.
        g_signal_handler_disconnect(request->print, request->failed_signal);
        g_signal_handler_disconnect(request->print, request->finished_signal);
      }),
      new std::shared_ptr<PageCapture>(request),
      +[](gpointer data, GClosure*) { PageCapture::release(data); },
      G_CONNECT_DEFAULT);
  webkit_print_operation_print(request->print);
}
struct ArchiveReader : public std::enable_shared_from_this<ArchiveReader> {
  std::shared_ptr<PageCapture> capture;
  GInputStream* stream;
  std::vector<uint8_t> bytes;
  ArchiveReader(std::shared_ptr<PageCapture> capture, GInputStream* stream)
      : capture(std::move(capture)), stream(stream) {}
  ~ArchiveReader() { g_object_unref(stream); }
  void read() {
    if (!capture->call) return;
    g_input_stream_read_bytes_async(
        stream, 65536, G_PRIORITY_DEFAULT, capture->cancelled,
        +[](GObject* object, GAsyncResult* result, gpointer data) {
          std::unique_ptr<std::shared_ptr<ArchiveReader>> holder(
              static_cast<std::shared_ptr<ArchiveReader>*>(data));
          auto reader = *holder;
          GError* error = nullptr;
          auto* chunk = g_input_stream_read_bytes_finish(G_INPUT_STREAM(object),
                                                         result, &error);
          if (!chunk) {
            reader->capture->finish(
                nullptr, error ? error->message : "Archive reading failed.");
            g_clear_error(&error);
            return;
          }
          gsize size = 0;
          auto* bytes =
              static_cast<const uint8_t*>(g_bytes_get_data(chunk, &size));
          if (reader->bytes.size() > kMaxCaptureBytes - size) {
            g_bytes_unref(chunk);
            reader->capture->finish(
                nullptr, "The archive exceeds the 64 MiB output limit.");
            return;
          }
          if (size)
            reader->bytes.insert(reader->bytes.end(), bytes, bytes + size);
          g_bytes_unref(chunk);
          if (!size)
            reader->capture->finish(&reader->bytes);
          else
            reader->read();
        },
        new std::shared_ptr<ArchiveReader>(shared_from_this()));
  }
};
void capture_archive(WebKitWebView* view,
                     std::shared_ptr<PageCapture> request) {
  webkit_web_view_save(
      view, WEBKIT_SAVE_MODE_MHTML, request->cancelled,
      +[](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::shared_ptr<PageCapture>> holder(
            static_cast<std::shared_ptr<PageCapture>*>(data));
        GError* error = nullptr;
        auto* stream = webkit_web_view_save_finish(WEBKIT_WEB_VIEW(object),
                                                   result, &error);
        if (!stream) {
          (*holder)->finish(
              nullptr, error ? error->message : "Native archiving failed.");
          g_clear_error(&error);
          return;
        }
        std::make_shared<ArchiveReader>(*holder, stream)->read();
      },
      new std::shared_ptr<PageCapture>(request));
}
struct PendingWindow;
struct BrowserState {
  std::shared_ptr<PageCapture> capture;
  FlMethodCall* pending_find = nullptr;
  std::string query;
  guint options = 0;
  bool file_selector = false;
  bool deny_popups = false;
  bool delegate_windows = false;
  bool delegate_fullscreen = false;
  bool fullscreen = false;
  bool context_menus = true;
  std::unordered_map<gint, std::shared_ptr<PendingWindow>> windows;
  std::weak_ptr<PendingWindow> incoming_window;
  std::vector<std::shared_ptr<FileSelection>> selections;
  gulong found_signal = 0;
  gulong failed_signal = 0;
  gulong chooser_signal = 0;
};
BrowserState* state(LinuxWebView* view) {
  return static_cast<BrowserState*>(view->browser_state);
}
struct PendingWindow {
  LinuxWebView* parent = nullptr;
  LinuxWebView* child = nullptr;
  gint id = 0;
  bool claimed = false;
  bool resolved = false;
  guint timer = 0;
  std::vector<std::pair<WebKitPolicyDecision*, WebKitPolicyDecisionType>> gates;
  ~PendingWindow() {
    if (timer) g_source_remove(timer);
    for (auto& gate : gates) {
      webkit_policy_decision_ignore(gate.first);
      g_object_unref(gate.first);
    }
  }
};
void finish_window(const std::shared_ptr<PendingWindow>& pending, bool accept) {
  if (pending->resolved) return;
  pending->resolved = true;
  if (pending->timer) {
    g_source_remove(pending->timer);
    pending->timer = 0;
  }
  auto* child = pending->child;
  auto* parent = pending->parent;
  if (parent && state(parent)) state(parent)->windows.erase(pending->id);
  pending->parent = nullptr;
  if (child && state(child)) state(child)->incoming_window.reset();
  auto gates = std::move(pending->gates);
  WebKitWebView* widget =
      child ? WEBKIT_WEB_VIEW(g_object_ref(child->web_view)) : nullptr;
  for (auto& gate : gates) {
    auto* current = widget ? static_cast<LinuxWebView*>(g_object_get_data(
                                 G_OBJECT(widget), kLinuxWebViewInstanceKey))
                           : nullptr;
    if (accept && current)
      resume_browser_window_navigation(current, gate.first, gate.second);
    else
      webkit_policy_decision_ignore(gate.first);
    g_object_unref(gate.first);
  }
  if (widget) g_object_unref(widget);
  if (!accept && child) {
    webkit_web_view_stop_loading(child->web_view);
    if (!pending->claimed && !child->plugin->disposing)
      g_hash_table_remove(child->plugin->webviews, GINT_TO_POINTER(child->id));
  }
  pending->child = nullptr;
}
void window_close_requested(WebKitWebView*, gpointer data) {
  auto* view = static_cast<LinuxWebView*>(data);
  if (!state(view)) return;
  if (auto incoming = state(view)->incoming_window.lock()) {
    // The opener can close a blank child before Dart has adopted it.
    send_event(view, make_event("windowCloseRequested"));
    finish_window(incoming, false);
    return;
  }
  send_event(view, make_event("windowCloseRequested"));
}
void complete_find(LinuxWebView* view, bool found, gint64 count) {
  auto* browser = state(view);
  if (!browser || !browser->pending_find) return;
  auto* call = browser->pending_find;
  browser->pending_find = nullptr;
  FlValue* result = fl_value_new_map();
  fl_value_set_string_take(result, "matchFound", fl_value_new_bool(found));
  if (count >= 0)
    fl_value_set_string_take(result, "matchCount", fl_value_new_int(count));
  respond(call, success_response(result));
  g_object_unref(call);
}
void found_text(WebKitFindController*, guint count, gpointer data) {
  complete_find(static_cast<LinuxWebView*>(data), count > 0, count);
}
void failed_text(WebKitFindController*, gpointer data) {
  auto* view = static_cast<LinuxWebView*>(data);
  complete_find(
      view, false,
      state(view)->options & WEBKIT_FIND_OPTIONS_WRAP_AROUND ? 0 : -1);
}
gboolean select_file(WebKitWebView*, WebKitFileChooserRequest* request,
                     gpointer data) {
  auto* view = static_cast<LinuxWebView*>(data);
  auto* browser = state(view);
  if (!browser->file_selector) return FALSE;
  browser->selections.erase(
      std::remove_if(browser->selections.begin(), browser->selections.end(),
                     [](const auto& item) { return item->request == nullptr; }),
      browser->selections.end());
  auto pending = std::make_shared<FileSelection>(request);
  browser->selections.push_back(pending);
  FlValue* params = fl_value_new_map();
  fl_value_set_string_take(
      params, "multiple",
      fl_value_new_bool(
          webkit_file_chooser_request_get_select_multiple(request)));
  FlValue* accepted = fl_value_new_list();
  const gchar* const* types =
      webkit_file_chooser_request_get_mime_types(request);
  for (size_t i = 0; types && types[i]; ++i)
    fl_value_append_take(accepted, fl_value_new_string(types[i]));
  fl_value_set_string_take(params, "acceptTypes", accepted);
  auto* context = new std::shared_ptr<FileSelection>(pending);
  fl_method_channel_invoke_method(
      view->method_channel, "fileSelectorRequested", params, nullptr,
      [](GObject* object, GAsyncResult* result, gpointer user_data) {
        std::unique_ptr<std::shared_ptr<FileSelection>> holder(
            static_cast<std::shared_ptr<FileSelection>*>(user_data));
        auto selection = *holder;
        if (!selection->request) return;
        GError* error = nullptr;
        g_autoptr(FlMethodResponse) response =
            fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object),
                                                   result, &error);
        FlValue* values = error == nullptr && response &&
                                  FL_IS_METHOD_SUCCESS_RESPONSE(response)
                              ? fl_method_success_response_get_result(
                                    FL_METHOD_SUCCESS_RESPONSE(response))
                              : nullptr;
        std::vector<const gchar*> files;
        if (values && fl_value_get_type(values) == FL_VALUE_TYPE_LIST) {
          for (size_t i = 0; i < fl_value_get_length(values); ++i) {
            FlValue* item = fl_value_get_list_value(values, i);
            if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING &&
                *fl_value_get_string(item))
              files.push_back(fl_value_get_string(item));
          }
        }
        if (!files.empty()) {
          if (!webkit_file_chooser_request_get_select_multiple(
                  selection->request))
            files.resize(1);
          files.push_back(nullptr);
          webkit_file_chooser_request_select_files(selection->request,
                                                   files.data());
          g_object_unref(selection->request);
          selection->request = nullptr;
        } else
          selection->cancel();
        g_clear_error(&error);
      },
      context);
  fl_value_unref(params);
  return TRUE;
}
}  // namespace

void initialize_browser_operations(LinuxWebView* view) {
  auto* browser = new BrowserState();
  view->browser_state = browser;
  auto* find = webkit_web_view_get_find_controller(view->web_view);
  browser->found_signal =
      g_signal_connect(find, "found-text", G_CALLBACK(found_text), view);
  browser->failed_signal = g_signal_connect(find, "failed-to-find-text",
                                            G_CALLBACK(failed_text), view);
  browser->chooser_signal = g_signal_connect(view->web_view, "run-file-chooser",
                                             G_CALLBACK(select_file), view);
  g_signal_connect(
      view->web_view, "context-menu",
      G_CALLBACK(+[](WebKitWebView*, WebKitContextMenu*, GdkEvent*,
                     WebKitHitTestResult*, gpointer data) -> gboolean {
        auto* browser = state(static_cast<LinuxWebView*>(data));
        return browser && !browser->context_menus;
      }),
      view);
  g_signal_connect(view->web_view, "close", G_CALLBACK(window_close_requested),
                   view);
  g_signal_connect(view->web_view, "enter-fullscreen",
                   G_CALLBACK(+[](WebKitWebView*, gpointer data) -> gboolean {
                     auto* view = static_cast<LinuxWebView*>(data);
                     if (!state(view)) return FALSE;
                     state(view)->fullscreen = true;
                     if (!state(view)->delegate_fullscreen) return FALSE;
                     auto* event = make_event("fullscreenChanged");
                     fl_value_set_string_take(event, "active",
                                              fl_value_new_bool(true));
                     send_event(view, event);
                     return TRUE;
                   }),
                   view);
  g_signal_connect(view->web_view, "leave-fullscreen",
                   G_CALLBACK(+[](WebKitWebView*, gpointer data) -> gboolean {
                     auto* view = static_cast<LinuxWebView*>(data);
                     if (!state(view)) return FALSE;
                     state(view)->fullscreen = false;
                     if (!state(view)->delegate_fullscreen) return FALSE;
                     auto* event = make_event("fullscreenChanged");
                     fl_value_set_string_take(event, "active",
                                              fl_value_new_bool(false));
                     send_event(view, event);
                     return TRUE;
                   }),
                   view);
  g_signal_connect(
      view->web_view, "web-process-terminated",
      G_CALLBACK(+[](WebKitWebView*, WebKitWebProcessTerminationReason reason,
                     gpointer data) {
        auto* view = static_cast<LinuxWebView*>(data);
        if (!state(view)) return;
        cancel_browser_windows(view);
        cancel_linux_load_request(view);
        resolve_all_pending_requests(view);
        reset_browser_find(view);
        cancel_browser_file_selections(view);
        state(view)->fullscreen = false;
        if (state(view)->capture)
          state(view)->capture->finish(nullptr, "The renderer process exited.");
        auto* event = make_event("processFailed");
        fl_value_set_string_take(event, "nativeCode", fl_value_new_int(reason));
        fl_value_set_string_take(
            event, "didCrash",
            fl_value_new_bool(reason == WEBKIT_WEB_PROCESS_CRASHED));
        send_event(view, event);
        // Losing a child renderer also invalidates the opener's pending native
        // attachment. This may destroy an unclaimed child; do it last.
        if (auto incoming = state(view)->incoming_window.lock())
          finish_window(incoming, false);
      }),
      view);
}
void reset_browser_find(LinuxWebView* view) {
  auto* browser = state(view);
  if (!browser) return;
  if (browser->pending_find) {
    respond(browser->pending_find, success_response());
    g_object_unref(browser->pending_find);
    browser->pending_find = nullptr;
  }
  browser->query.clear();
  webkit_find_controller_search_finish(
      webkit_web_view_get_find_controller(view->web_view));
}
void cancel_browser_file_selections(LinuxWebView* view) {
  auto* browser = state(view);
  if (!browser) return;
  for (auto& selection : browser->selections) selection->cancel();
  browser->selections.clear();
}
void dispose_browser_operations(LinuxWebView* view) {
  dispose_network_operations(view);
  auto* browser = state(view);
  if (!browser) return;
  cancel_browser_windows(view);
  if (auto incoming = browser->incoming_window.lock()) {
    incoming->child = nullptr;
    finish_window(incoming, false);
  }
  reset_browser_find(view);
  if (browser->capture)
    browser->capture->finish(nullptr, "The WebView was disposed.");
  cancel_browser_file_selections(view);
  auto* find = webkit_web_view_get_find_controller(view->web_view);
  g_signal_handler_disconnect(find, browser->found_signal);
  g_signal_handler_disconnect(find, browser->failed_signal);
  g_signal_handler_disconnect(view->web_view, browser->chooser_signal);
  delete browser;
  view->browser_state = nullptr;
}
bool browser_denies_popups(LinuxWebView* view) {
  return state(view) && state(view)->deny_popups;
}
bool browser_delegates_windows(LinuxWebView* view) {
  return state(view) && state(view)->delegate_windows &&
         !state(view)->deny_popups;
}
bool defer_browser_window_navigation(LinuxWebView* view,
                                     WebKitPolicyDecision* decision,
                                     WebKitPolicyDecisionType type) {
  if (!state(view)) return false;
  auto pending = state(view)->incoming_window.lock();
  if (!pending || pending->resolved ||
      type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION)
    return false;
  pending->gates.emplace_back(WEBKIT_POLICY_DECISION(g_object_ref(decision)),
                              type);
  return true;
}
void cancel_browser_windows(LinuxWebView* view) {
  if (!state(view)) return;
  auto windows = state(view)->windows;
  for (auto& pair : windows) finish_window(pair.second, false);
}
WebKitWebView* create_browser_window(LinuxWebView* view,
                                     WebKitNavigationAction* action) {
  if (!browser_delegates_windows(view)) return nullptr;
  GError* error = nullptr;
  auto* child =
      create_linux_webview(view->plugin, &error, FALSE, view->web_view);
  if (!child) {
    g_warning("webview_all_linux: creating a related child window failed: %s",
              error ? error->message : "unknown error");
    g_clear_error(&error);
    return nullptr;
  }
  auto pending = std::make_shared<PendingWindow>();
  pending->parent = view;
  pending->child = child;
  pending->id = child->id;
  state(view)->windows[child->id] = pending;
  state(child)->incoming_window = pending;
  pending->timer = g_timeout_add_full(
      G_PRIORITY_DEFAULT, 25000,
      [](gpointer data) -> gboolean {
        auto pending = *static_cast<std::shared_ptr<PendingWindow>*>(data);
        pending->timer = 0;
        finish_window(pending, false);
        return G_SOURCE_REMOVE;
      },
      new std::shared_ptr<PendingWindow>(pending),
      [](gpointer data) {
        delete static_cast<std::shared_ptr<PendingWindow>*>(data);
      });
  auto* event = make_event("newWindowRequested");
  fl_value_set_string_take(event, "requestId", fl_value_new_int(child->id));
  auto* request = webkit_navigation_action_get_request(action);
  auto* uri = request ? webkit_uri_request_get_uri(request) : nullptr;
  if (uri) fl_value_set_string_take(event, "url", fl_value_new_string(uri));
  fl_value_set_string_take(
      event, "isUserGesture",
      fl_value_new_bool(webkit_navigation_action_is_user_gesture(action)));
  send_event(view, event);
  return child->web_view;
}
bool handle_browser_method(LinuxWebView* view, FlMethodCall* call) {
  const std::string method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  auto* browser = state(view);
  if (method == "saveNavigationState") {
    auto& snapshots = navigation_snapshots[view->plugin];
    if (snapshots.size() >= 16) {
      respond(
          call,
          error_response(
              "snapshot_limit",
              "Dispose unused navigation snapshots before saving another."));
      return true;
    }
    auto snapshot = std::make_shared<NavigationSnapshot>(view->web_view);
    gchar* id = g_uuid_string_random();
    snapshots[id] = snapshot;
    respond(call, success_response(fl_value_new_string(id)));
    g_free(id);
    return true;
  } else if (method == "restoreNavigationState") {
    const gchar* id = map_lookup_string(args, "stateId");
    auto& snapshots = navigation_snapshots[view->plugin];
    auto found = id ? snapshots.find(id) : snapshots.end();
    bool accepted =
        found != snapshots.end() &&
        found->second->context == webkit_web_view_get_context(view->web_view);
    if (accepted) {
      cancel_browser_windows(view);
      cancel_pending_navigation_requests(view);
      cancel_linux_load_request(view);
      webkit_web_view_restore_session_state(view->web_view,
                                            found->second->data);
      auto* item = webkit_back_forward_list_get_current_item(
          webkit_web_view_get_back_forward_list(view->web_view));
      if (item)
        webkit_web_view_go_to_back_forward_list_item(view->web_view, item);
    }
    respond(call, success_response(fl_value_new_bool(accepted)));
    return true;
  }
  if (method == "setContextMenuEnabled") {
    browser->context_menus = map_lookup_bool(args, "enabled", true);
    respond(call, success_response(fl_value_new_bool(true)));
    return true;
  }
  if (method == "setAudioMuted") {
    webkit_web_view_set_is_muted(view->web_view,
                                 map_lookup_bool(args, "muted", false));
    respond(call, success_response(fl_value_new_bool(true)));
    return true;
  }
  if (method == "takeScreenshot" || method == "createPdf" ||
      method == "createArchive") {
    if (browser->capture && browser->capture->call) {
      respond(call, FL_METHOD_RESPONSE(fl_method_error_response_new(
                        "capture_busy",
                        "A native capture is already in progress.", nullptr)));
      return true;
    }
    auto request = std::make_shared<PageCapture>(call);
    browser->capture = request;
    request->start_timer();
    if (method == "takeScreenshot") {
      request->full_document = map_lookup_bool(fl_method_call_get_args(call), "fullDocument", FALSE);
      if (request->full_document) {
        // Reject ordinary oversized pages before asking WebKit to allocate the
        // full native surface. Validate the returned surface independently too.
        webkit_web_view_evaluate_javascript(view->web_view,
          "(()=>{const e=document.documentElement,b=document.body;return Math.max(e.scrollWidth,b?.scrollWidth||0)*Math.max(e.scrollHeight,b?.scrollHeight||0)*devicePixelRatio*devicePixelRatio})()",
          -1, "com.abandoft.webview_all.capture", nullptr, request->cancelled,
          +[](GObject* object, GAsyncResult* result, gpointer data) {
            std::unique_ptr<std::shared_ptr<PageCapture>> holder(static_cast<std::shared_ptr<PageCapture>*>(data));
            auto request = *holder;
            GError* error = nullptr;
            auto* value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(object), result, &error);
            const auto pixels = value && jsc_value_is_number(value) ? jsc_value_to_double(value) : 0;
            if (value) g_object_unref(value);
            g_clear_error(&error);
            if (!request->call) return;
            if (!std::isfinite(pixels) || pixels <= 0 || pixels > 16 * 1024 * 1024) {
              request->finish(nullptr, "The document is unavailable or exceeds the 16 Mi pixel screenshot limit."); return;
            }
            capture_snapshot(WEBKIT_WEB_VIEW(object), request);
          }, new std::shared_ptr<PageCapture>(request));
      } else capture_snapshot(view->web_view, request);
    }
    else if (method == "createArchive")
      capture_archive(view->web_view, request);
    else
      capture_pdf(view->web_view, request,
                  fl_value_lookup_string(args, "options"));
    return true;
  } else if (method == "printPage") {
    auto* top = gtk_widget_get_toplevel(GTK_WIDGET(view->web_view));
    auto* plugin = view->plugin;
    if (!GTK_IS_WINDOW(top) || print_jobs[plugin].size() >= 32) {
      respond(call, success_response());
      return true;
    }
    auto job = std::make_shared<NativePrintJob>();
    auto* operation = webkit_print_operation_new(view->web_view);
    g_signal_connect_data(
        operation, "failed",
        G_CALLBACK(+[](WebKitPrintOperation*, GError*, gpointer data) {
          (*static_cast<std::shared_ptr<NativePrintJob>*>(data))->state =
              "failed";
        }),
        new std::shared_ptr<NativePrintJob>(job),
        +[](gpointer data, GClosure*) {
          delete static_cast<std::shared_ptr<NativePrintJob>*>(data);
        },
        G_CONNECT_DEFAULT);
    // The finished handler owns the operation while printing. Releasing the
    // Dart handle leaves an OS-owned job running.
    g_signal_connect_data(
        operation, "finished",
        G_CALLBACK(+[](WebKitPrintOperation* operation, gpointer data) {
          auto job = *static_cast<std::shared_ptr<NativePrintJob>*>(data);
          if (job->state != "failed") job->state = "completed";
          g_object_unref(operation);
        }),
        new std::shared_ptr<NativePrintJob>(job),
        +[](gpointer data, GClosure*) {
          delete static_cast<std::shared_ptr<NativePrintJob>*>(data);
        },
        G_CONNECT_DEFAULT);
    // The modal dialog runs a nested main loop; the view may close meanwhile.
    g_object_ref(plugin);
    auto response =
        webkit_print_operation_run_dialog(operation, GTK_WINDOW(top));
    if (response == WEBKIT_PRINT_OPERATION_RESPONSE_CANCEL) {
      job->state = "cancelled";
      g_object_unref(operation);
    } else if (job->state == "presented")
      job->state = "queued";
    gchar* uuid = g_uuid_string_random();
    std::string id(uuid);
    g_free(uuid);
    if (!plugin->disposing) print_jobs[plugin][id] = job;
    g_object_unref(plugin);
    auto* value = fl_value_new_map();
    fl_value_set_string_take(value, "jobId", fl_value_new_string(id.c_str()));
    fl_value_set_string_take(value, "state",
                             fl_value_new_string(job->state.c_str()));
    fl_value_set_string_take(value, "canQuery", fl_value_new_bool(true));
    fl_value_set_string_take(value, "canCancel", fl_value_new_bool(false));
    respond(call, success_response(value));
    return true;
  } else if (method == "setFullscreenDelegateEnabled") {
    browser->delegate_fullscreen = map_lookup_bool(args, "enabled", FALSE);
    if (browser->delegate_fullscreen && browser->fullscreen) {
      auto* event = make_event("fullscreenChanged");
      fl_value_set_string_take(event, "active", fl_value_new_bool(true));
      send_event(view, event);
    }
  } else if (method == "setNewWindowDelegateEnabled") {
    browser->delegate_windows = map_lookup_bool(args, "enabled", FALSE);
    if (!browser->delegate_windows) cancel_browser_windows(view);
  } else if (method == "claimNewWindow" || method == "attachNewWindow") {
    const gint id = map_lookup_int(args, "requestId", -1);
    auto iterator = browser->windows.find(id);
    auto pending =
        iterator == browser->windows.end() ? nullptr : iterator->second;
    if (method == "claimNewWindow") {
      if (pending && !pending->claimed && !pending->resolved) {
        pending->claimed = true;
        respond(call, success_response(fl_value_new_int(id)));
      } else
        respond(call, success_response());
    } else {
      const bool accepted = pending && pending->claimed &&
                            !browser->deny_popups &&
                            browser->delegate_windows &&
                            map_lookup_int(args, "childWebViewId", -1) == id;
      if (pending) finish_window(pending, accepted);
      respond(call, success_response(fl_value_new_bool(accepted)));
    }
    return true;
  } else if (method == "stopLoading") {
    cancel_browser_windows(view);
    cancel_pending_navigation_requests(view);
    cancel_linux_load_request(view);
    webkit_web_view_stop_loading(view->web_view);
  } else if (method == "setPopupWindowPolicy") {
    browser->deny_popups = map_lookup_int(args, "policy", 0) == 1;
    if (browser->deny_popups) cancel_browser_windows(view);
  } else if (method == "setFileSelectorEnabled") {
    browser->file_selector = map_lookup_bool(args, "enabled", FALSE);
    if (!browser->file_selector) {
      for (auto& item : browser->selections) item->cancel();
      browser->selections.clear();
    }
  } else if (method == "getNavigationHistory") {
    auto* list = webkit_web_view_get_back_forward_list(view->web_view);
    const guint length = webkit_back_forward_list_get_length(list);
    GList* back = webkit_back_forward_list_get_back_list(list);
    const gint current = length ? static_cast<gint>(g_list_length(back)) : -1;
    g_list_free(back);
    FlValue* result = fl_value_new_map();
    FlValue* items = fl_value_new_list();
    for (guint index = 0; index < length; ++index) {
      auto* entry = webkit_back_forward_list_get_nth_item(
          list, static_cast<gint>(index) - current);
      FlValue* item = fl_value_new_map();
      const gchar* url = webkit_back_forward_list_item_get_uri(entry);
      const gchar* original =
          webkit_back_forward_list_item_get_original_uri(entry);
      const gchar* title = webkit_back_forward_list_item_get_title(entry);
      fl_value_set_string_take(item, "url",
                               fl_value_new_string(url ? url : ""));
      if (original)
        fl_value_set_string_take(item, "originalUrl",
                                 fl_value_new_string(original));
      if (title)
        fl_value_set_string_take(item, "title", fl_value_new_string(title));
      fl_value_append_take(items, item);
    }
    fl_value_set_string_take(result, "items", items);
    fl_value_set_string_take(result, "currentIndex", fl_value_new_int(current));
    respond(call, success_response(result));
    return true;
  } else if (method == "goToHistoryIndex") {
    auto* list = webkit_web_view_get_back_forward_list(view->web_view);
    const gint64 index = map_lookup_int(args, "index", -1);
    const guint length = webkit_back_forward_list_get_length(list);
    bool accepted = index >= 0 && index < length;
    if (accepted) {
      GList* back = webkit_back_forward_list_get_back_list(list);
      const gint current = g_list_length(back);
      g_list_free(back);
      auto* item = webkit_back_forward_list_get_nth_item(
          list, static_cast<gint>(index) - current);
      if (item)
        webkit_web_view_go_to_back_forward_list_item(view->web_view, item);
      else
        accepted = false;
    }
    respond(call, success_response(fl_value_new_bool(accepted)));
    return true;
  } else if (method == "findText") {
    const gchar* query = map_lookup_string(args, "text");
    const guint options = (map_lookup_bool(args, "caseSensitive", FALSE)
                               ? 0
                               : WEBKIT_FIND_OPTIONS_CASE_INSENSITIVE) |
                          (map_lookup_bool(args, "wrapAround", TRUE)
                               ? WEBKIT_FIND_OPTIONS_WRAP_AROUND
                               : 0);
    auto* find = webkit_web_view_get_find_controller(view->web_view);
    if (browser->pending_find) {
      respond(browser->pending_find, success_response());
      g_object_unref(browser->pending_find);
      browser->pending_find = nullptr;
      webkit_find_controller_search_finish(find);
      browser->query.clear();
    }
    browser->pending_find = FL_METHOD_CALL(g_object_ref(call));
    const bool forward = map_lookup_bool(args, "forward", TRUE);
    if (query && browser->query == query && browser->options == options) {
      if (forward)
        webkit_find_controller_search_next(find);
      else
        webkit_find_controller_search_previous(find);
    } else {
      browser->query = query ? query : "";
      browser->options = options;
      webkit_find_controller_search(
          find, browser->query.c_str(),
          options | (forward ? 0 : WEBKIT_FIND_OPTIONS_BACKWARDS), G_MAXUINT);
    }
    return true;
  } else if (method == "clearFindMatches") {
    reset_browser_find(view);
  } else
    return false;
  respond(call, success_response());
  return true;
}

bool handle_browser_root_method(WebviewAllLinuxPlugin* plugin,
                                FlMethodCall* call) {
  const auto* method = fl_method_call_get_name(call);
  if (!strcmp(method, "printJobState") || !strcmp(method, "releasePrintJob") ||
      !strcmp(method, "cancelPrintJob")) {
    const auto* id = map_lookup_string(fl_method_call_get_args(call), "jobId");
    auto& jobs = print_jobs[plugin];
    auto found = id ? jobs.find(id) : jobs.end();
    if (!strcmp(method, "printJobState"))
      respond(call, success_response(fl_value_new_string(
                        found == jobs.end() ? "unknown"
                                            : found->second->state.c_str())));
    else if (!strcmp(method, "releasePrintJob")) {
      if (found != jobs.end()) jobs.erase(found);
      respond(call, success_response());
    } else
      respond(call, success_response(fl_value_new_bool(false)));
    return true;
  }
  if (strcmp(fl_method_call_get_name(call), "releaseNavigationState") != 0)
    return false;
  const gchar* id = map_lookup_string(fl_method_call_get_args(call), "stateId");
  auto found = navigation_snapshots.find(plugin);
  if (id && found != navigation_snapshots.end()) found->second.erase(id);
  respond(call, success_response());
  return true;
}
void dispose_browser_navigation_states(WebviewAllLinuxPlugin* plugin) {
  navigation_snapshots.erase(plugin);
  print_jobs.erase(plugin);
}
