#include "webview/webview_internal.h"
#include "common/method_channel_utils.h"
#include <libsoup/soup.h>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <cstring>

namespace {
constexpr char kSchemes[] = "webview-all-custom-schemes";
constexpr char kRegistered[] = "webview-all-registered-schemes";
struct SchemePolicy;
struct SchemeRequest : public std::enable_shared_from_this<SchemeRequest> {
  std::weak_ptr<SchemePolicy> owner;
  WebKitURISchemeRequest* request;
  FlMethodChannel* channel;
  GCancellable* cancelled = g_cancellable_new();
  FlValue* metadata = nullptr;
  GInputStream* body = nullptr;
  std::vector<uint8_t> upload;
  std::string id, base;
  guint timer = 0;
  bool done = false;
  SchemeRequest(WebKitURISchemeRequest* request, FlMethodChannel* channel,
                const std::string& base)
      : request(WEBKIT_URI_SCHEME_REQUEST(g_object_ref(request))),
        channel(FL_METHOD_CHANNEL(g_object_ref(channel))),
        base(base) {
    auto* uuid = g_uuid_string_random();
    id = uuid;
    g_free(uuid);
  }
  ~SchemeRequest() {
    if (timer) g_source_remove(timer);
    if (metadata) fl_value_unref(metadata);
    g_clear_object(&body);
    g_object_unref(cancelled);
    g_object_unref(channel);
    g_object_unref(request);
  }
  void cancel_dart() {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "id", fl_value_new_string(id.c_str()));
    fl_method_channel_invoke_method(channel, "cancel", args, nullptr, nullptr,
                                    nullptr);
  }
  void complete(GInputStream* stream, FlValue* response);
  void fail();
  void open(bool body_available);
  void read_upload();
  void start();
};
struct SchemePolicy {
  FlBinaryMessenger* messenger;
  FlMethodChannel* channel = nullptr;
  SoupSession* session = soup_session_new();
  std::string name, base;
  std::unordered_set<std::string> schemes;
  std::unordered_map<std::string, std::shared_ptr<SchemeRequest>> pending;
  bool enabled = false, closed = false;
  explicit SchemePolicy(FlBinaryMessenger* messenger)
      : messenger(FL_BINARY_MESSENGER(g_object_ref(messenger))) {}
  void cancel() {
    auto requests = pending;
    for (auto& entry : requests) entry.second->fail();
    soup_session_abort(session);
  }
  void close_channel(bool notify = true, bool clear_handler = true) {
    if (!channel) return;
    if (notify)
      fl_method_channel_invoke_method(channel, "closed", nullptr, nullptr,
                                      nullptr, nullptr);
    if (clear_handler)
      fl_binary_messenger_set_message_handler_on_channel(
          messenger, name.c_str(), nullptr, nullptr, nullptr);
    g_clear_object(&channel);
  }
  ~SchemePolicy() {
    cancel();
    close_channel();
    g_object_unref(session);
    g_object_unref(messenger);
  }
};
void SchemeRequest::fail() {
  if (done) return;
  done = true;
  if (timer) {
    g_source_remove(timer);
    timer = 0;
  }
  g_cancellable_cancel(cancelled);
  auto* error =
      g_error_new_literal(G_IO_ERROR, G_IO_ERROR_CANCELLED,
                          "The custom scheme request was cancelled or failed.");
  webkit_uri_scheme_request_finish_error(request, error);
  g_error_free(error);
  cancel_dart();
  if (auto state = owner.lock()) state->pending.erase(id);
}
void SchemeRequest::complete(GInputStream* stream, FlValue* response) {
  if (done) return;
  const auto status = map_lookup_int(response, "statusCode", 500);
  const auto* mime = map_lookup_string(response, "mimeType");
  auto length = map_lookup_int(response, "contentLength", -1);
  const auto* method = webkit_uri_scheme_request_get_http_method(request);
  if (method && !strcmp(method, "HEAD")) length = 0;
  if (!mime ||
      !((status >= 200 && status < 300) || (status >= 400 && status < 600)) ||
      length < -1) {
    fail();
    return;
  }
  auto* result = webkit_uri_scheme_response_new(stream, length);
  webkit_uri_scheme_response_set_status(result, status, "Resource");
  webkit_uri_scheme_response_set_content_type(result, mime);
  auto* headers = soup_message_headers_new(SOUP_MESSAGE_HEADERS_RESPONSE);
  auto* values = map_lookup(response, "headers");
  if (values && fl_value_get_type(values) == FL_VALUE_TYPE_MAP)
    for (size_t i = 0; i < fl_value_get_length(values); i++) {
      auto* key = fl_value_get_map_key(values, i);
      auto* value = fl_value_get_map_value(values, i);
      if (fl_value_get_type(key) == FL_VALUE_TYPE_STRING &&
          fl_value_get_type(value) == FL_VALUE_TYPE_STRING)
        soup_message_headers_append(headers, fl_value_get_string(key),
                                    fl_value_get_string(value));
    }
  // WebKit takes full ownership of headers and reads them asynchronously.
  webkit_uri_scheme_response_set_http_headers(result, headers);
  done = true;
  if (timer) {
    g_source_remove(timer);
    timer = 0;
  }
  webkit_uri_scheme_request_finish_with_response(request, result);
  g_object_unref(result);
  if (auto state = owner.lock()) state->pending.erase(id);
  if (length == 0) cancel_dart();
}
void SchemeRequest::open(bool body_available) {
  if (done) return;
  auto state = owner.lock();
  if (!state || state->closed || !state->enabled) {
    fail();
    return;
  }
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(id.c_str()));
  fl_value_set_string_take(
      args, "uri",
      fl_value_new_string(webkit_uri_scheme_request_get_uri(request)));
  const auto* method = webkit_uri_scheme_request_get_http_method(request);
  fl_value_set_string_take(args, "method",
                           fl_value_new_string(method ? method : "GET"));
  auto* headers = fl_value_new_map();
  if (auto* native = webkit_uri_scheme_request_get_http_headers(request)) {
    SoupMessageHeadersIter iter;
    soup_message_headers_iter_init(&iter, native);
    const gchar *name, *value;
    while (soup_message_headers_iter_next(&iter, &name, &value))
      fl_value_set_string_take(headers, name, fl_value_new_string(value));
  }
  fl_value_set_string_take(args, "headers", headers);
  fl_value_set_string_take(args, "bodyAvailable",
                           fl_value_new_bool(body_available));
  if (body_available)
    fl_value_set_string_take(
        args, "body", fl_value_new_uint8_list(upload.data(), upload.size()));
  fl_method_channel_invoke_method(
      channel, "open", args, cancelled,
      +[](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::shared_ptr<SchemeRequest>> holder(
            static_cast<std::shared_ptr<SchemeRequest>*>(data));
        auto request = *holder;
        GError* error = nullptr;
        g_autoptr(FlMethodResponse) reply =
            fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object),
                                                   result, &error);
        if (request->done) {
          g_clear_error(&error);
          return;
        }
        auto* response =
            error == nullptr && reply && FL_IS_METHOD_SUCCESS_RESPONSE(reply)
                ? fl_method_success_response_get_result(
                      FL_METHOD_SUCCESS_RESPONSE(reply))
                : nullptr;
        if (!response || fl_value_get_type(response) != FL_VALUE_TYPE_MAP) {
          request->fail();
          g_clear_error(&error);
          return;
        }
        request->metadata = fl_value_ref(response);
        auto length = map_lookup_int(response, "contentLength", -1);
        const auto* method =
            webkit_uri_scheme_request_get_http_method(request->request);
        if (length == 0 || (method && !strcmp(method, "HEAD"))) {
          auto* stream = g_memory_input_stream_new();
          request->complete(stream, response);
          g_object_unref(stream);
          return;
        }
        auto state = request->owner.lock();
        if (!state || state->closed) {
          request->fail();
          return;
        }
        auto uri = request->base + "read/" + request->id;
        auto* message = soup_message_new("GET", uri.c_str());
        if (!message) {
          request->fail();
          return;
        }
        // Only the token-protected body pipe is requested over loopback. The
        // application's original URI, method and headers already reached Dart.
        soup_session_send_async(
            state->session, message, G_PRIORITY_DEFAULT, request->cancelled,
            +[](GObject* object, GAsyncResult* result, gpointer data) {
              std::unique_ptr<std::shared_ptr<SchemeRequest>> holder(
                  static_cast<std::shared_ptr<SchemeRequest>*>(data));
              auto request = *holder;
              GError* error = nullptr;
              auto* stream = soup_session_send_finish(SOUP_SESSION(object),
                                                      result, &error);
              if (!stream || error || request->done) {
                if (!request->done) request->fail();
              } else
                request->complete(stream, request->metadata);
              if (stream) g_object_unref(stream);
              g_clear_error(&error);
            },
            new std::shared_ptr<SchemeRequest>(request));
        g_object_unref(message);
      },
      new std::shared_ptr<SchemeRequest>(shared_from_this()));
}
void SchemeRequest::read_upload() {
  if (done) return;
  g_input_stream_read_bytes_async(
      body, 65536, G_PRIORITY_DEFAULT, cancelled,
      +[](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::shared_ptr<SchemeRequest>> holder(
            static_cast<std::shared_ptr<SchemeRequest>*>(data));
        auto request = *holder;
        GError* error = nullptr;
        auto* chunk = g_input_stream_read_bytes_finish(G_INPUT_STREAM(object),
                                                       result, &error);
        if (request->done) {
          if (chunk) g_bytes_unref(chunk);
          g_clear_error(&error);
          return;
        }
        if (!chunk) {
          request->upload.clear();
          request->open(false);
          g_clear_error(&error);
          return;
        }
        gsize size = 0;
        auto* bytes =
            static_cast<const uint8_t*>(g_bytes_get_data(chunk, &size));
        if (request->upload.size() + size > 4 * 1024 * 1024) {
          request->upload.clear();
          g_bytes_unref(chunk);
          request->open(false);
          return;
        }
        if (size)
          request->upload.insert(request->upload.end(), bytes, bytes + size);
        g_bytes_unref(chunk);
        if (!size)
          request->open(true);
        else
          request->read_upload();
      },
      new std::shared_ptr<SchemeRequest>(shared_from_this()));
}
void SchemeRequest::start() {
  timer = g_timeout_add_full(
      G_PRIORITY_DEFAULT, 30000,
      +[](gpointer data) -> gboolean {
        auto request = *static_cast<std::shared_ptr<SchemeRequest>*>(data);
        request->timer = 0;
        request->fail();
        return G_SOURCE_REMOVE;
      },
      new std::shared_ptr<SchemeRequest>(shared_from_this()),
      +[](gpointer data) {
        delete static_cast<std::shared_ptr<SchemeRequest>*>(data);
      });
#if WEBKIT_CHECK_VERSION(2, 40, 0)
  if (auto* input = webkit_uri_scheme_request_get_http_body(request)) {
    body = G_INPUT_STREAM(g_object_ref(input));
    read_upload();
    return;
  }
  open(true);
#else
  open(false);
#endif
}
void scheme_requested(WebKitURISchemeRequest* request, gpointer) {
  auto* view = webkit_uri_scheme_request_get_web_view(request);
  auto* pointer = view ? static_cast<std::shared_ptr<SchemePolicy>*>(
                             g_object_get_data(G_OBJECT(view), kSchemes))
                       : nullptr;
  auto state = pointer ? *pointer : nullptr;
  const auto* name = webkit_uri_scheme_request_get_scheme(request);
  if (!state || state->closed || !state->enabled || !name ||
      !state->schemes.count(name) || state->pending.size() >= 64) {
    auto* error = g_error_new_literal(
        G_IO_ERROR, G_IO_ERROR_NOT_FOUND,
        "No custom scheme handler is configured for this view.");
    webkit_uri_scheme_request_finish_error(request, error);
    g_error_free(error);
    return;
  }
  auto pending =
      std::make_shared<SchemeRequest>(request, state->channel, state->base);
  pending->owner = state;
  state->pending[pending->id] = pending;
  pending->start();
}
}  // namespace

bool handle_scheme_method(LinuxWebView* view, FlMethodCall* call) {
  const auto* method = fl_method_call_get_name(call);
  if (!strcmp(method, "getNetworkCapabilities")) {
    auto* value = fl_value_new_map();
    fl_value_set_string_take(value, "customSchemeRequestBodies",
                             fl_value_new_bool(WEBKIT_CHECK_VERSION(2, 40, 0)));
    respond(call, success_response(value));
    return true;
  }
  if (strcmp(method, "configureCustomSchemes")) return false;
  auto* args = fl_method_call_get_args(call);
  const auto* name = map_lookup_string(args, "channel");
  auto* holder = static_cast<std::shared_ptr<SchemePolicy>*>(
      g_object_get_data(G_OBJECT(view->web_view), kSchemes));
  auto previous = holder ? *holder : nullptr;
  if (!map_lookup_bool(args, "enabled", false)) {
    if (previous && name && previous->name == name) {
      previous->enabled = false;
      previous->cancel();
    }
    respond(call, success_response(fl_value_new_bool(true)));
    return true;
  }
  const auto* base = map_lookup_string(args, "baseUri");
  auto* schemes = map_lookup(args, "schemes");
  g_autoptr(GUri) uri =
      base ? g_uri_parse(base, G_URI_FLAGS_NONE, nullptr) : nullptr;
  if (!name || !uri || g_strcmp0(g_uri_get_scheme(uri), "http") ||
      g_strcmp0(g_uri_get_host(uri), "127.0.0.1") || g_uri_get_userinfo(uri) ||
      g_uri_get_query(uri) || g_uri_get_fragment(uri) ||
      g_uri_get_port(uri) <= 0 || !schemes ||
      fl_value_get_type(schemes) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(schemes) == 0 || fl_value_get_length(schemes) > 16) {
    respond(call, success_response(fl_value_new_bool(false)));
    return true;
  }
  auto state = std::make_shared<SchemePolicy>(
      fl_plugin_registrar_get_messenger(view->plugin->registrar));
  state->name = name;
  state->base = base;
  for (size_t i = 0; i < fl_value_get_length(schemes); i++) {
    auto* value = fl_value_get_list_value(schemes, i);
    const auto* scheme = fl_value_get_type(value) == FL_VALUE_TYPE_STRING
                             ? fl_value_get_string(value)
                             : nullptr;
    if (!scheme ||
        !g_regex_match_simple("^[a-z][a-z0-9+.-]{0,31}$", scheme,
                              G_REGEX_DEFAULT, G_REGEX_MATCH_DEFAULT) ||
        !strcmp(scheme, "http") || !strcmp(scheme, "https") ||
        !strcmp(scheme, "file") || !strcmp(scheme, "data") ||
        !strcmp(scheme, "about") || !strcmp(scheme, "javascript")) {
      respond(call, success_response(fl_value_new_bool(false)));
      return true;
    }
    state->schemes.insert(scheme);
  }
  auto* context = webkit_web_view_get_context(view->web_view);
  auto* registered = static_cast<std::unordered_set<std::string>*>(
      g_object_get_data(G_OBJECT(context), kRegistered));
  if (!registered) {
    registered = new std::unordered_set<std::string>();
    g_object_set_data_full(
        G_OBJECT(context), kRegistered, registered, +[](gpointer data) {
          delete static_cast<std::unordered_set<std::string>*>(data);
        });
  }
  for (const auto& scheme : state->schemes)
    if (registered->insert(scheme).second) {
      webkit_web_context_register_uri_scheme(
          context, scheme.c_str(), scheme_requested, nullptr, nullptr);
      webkit_security_manager_register_uri_scheme_as_cors_enabled(
          webkit_web_context_get_security_manager(context), scheme.c_str());
    }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel =
      fl_method_channel_new(state->messenger, name, FL_METHOD_CODEC(codec));
  state->enabled = true;
  if (previous) {
    previous->closed = true;
    previous->cancel();
    previous->close_channel(previous->name != name, previous->name != name);
  }
  g_object_set_data_full(
      G_OBJECT(view->web_view), kSchemes,
      new std::shared_ptr<SchemePolicy>(state), +[](gpointer data) {
        delete static_cast<std::shared_ptr<SchemePolicy>*>(data);
      });
  respond(call, success_response(fl_value_new_bool(true)));
  return true;
}
void dispose_scheme_operations(LinuxWebView* view) {
  auto* pointer = static_cast<std::shared_ptr<SchemePolicy>*>(
      g_object_get_data(G_OBJECT(view->web_view), kSchemes));
  if (!pointer) return;
  auto state = *pointer;
  state->closed = true;
  state->cancel();
  state->close_channel();
  g_object_set_data(G_OBJECT(view->web_view), kSchemes, nullptr);
}
