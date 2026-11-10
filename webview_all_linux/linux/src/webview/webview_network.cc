#include "webview/webview_internal.h"
#include "common/method_channel_utils.h"
#include <glib/gstdio.h>
#include <memory>
#include <string>
#include <cstring>

namespace {
struct ContentPolicy;
struct RuleUpdate : public std::enable_shared_from_this<RuleUpdate> {
  std::weak_ptr<ContentPolicy> owner;
  FlMethodCall* call;
  GCancellable* cancelled = g_cancellable_new();
  WebKitUserContentFilterStore* store = nullptr;
  guint timer = 0;
  std::string path, id;
  explicit RuleUpdate(FlMethodCall* call)
      : call(FL_METHOD_CALL(g_object_ref(call))) {}
  ~RuleUpdate() {
    if (timer) g_source_remove(timer);
    if (call) g_object_unref(call);
    g_object_unref(cancelled);
    if (store) g_object_unref(store);
    if (!path.empty()) {
      // The compiler directory is private and created by g_dir_make_tmp.
      // Unlink files without following symlinks or removing external paths.
      if (auto* dir = g_dir_open(path.c_str(), 0, nullptr)) {
        while (auto* name = g_dir_read_name(dir)) {
          auto file = path + "/" + name;
          g_unlink(file.c_str());
        }
        g_dir_close(dir);
      }
      g_rmdir(path.c_str());
    }
  }
  void finish(bool accepted) {
    if (!call) return;
    auto* reply = call;
    call = nullptr;
    if (timer) {
      g_source_remove(timer);
      timer = 0;
    }
    g_cancellable_cancel(cancelled);
    respond(reply, success_response(fl_value_new_bool(accepted)));
    g_object_unref(reply);
  }
};
struct ContentPolicy {
  WebKitUserContentManager* manager;
  WebKitUserContentFilter* filter = nullptr;
  std::shared_ptr<RuleUpdate> pending;
  bool closed = false;
  explicit ContentPolicy(WebKitUserContentManager* manager)
      : manager(WEBKIT_USER_CONTENT_MANAGER(g_object_ref(manager))) {}
  ~ContentPolicy() {
    if (pending) pending->finish(false);
    if (filter) {
      webkit_user_content_manager_remove_filter(manager, filter);
      webkit_user_content_filter_unref(filter);
    }
    g_object_unref(manager);
  }
};
constexpr char kPolicy[] = "webview-all-content-policy";
std::shared_ptr<ContentPolicy> policy(LinuxWebView* view) {
  auto* value = static_cast<std::shared_ptr<ContentPolicy>*>(
      g_object_get_data(G_OBJECT(view->web_view), kPolicy));
  if (value) return *value;
  auto result = std::make_shared<ContentPolicy>(view->content_manager);
  g_object_set_data_full(
      G_OBJECT(view->web_view), kPolicy,
      new std::shared_ptr<ContentPolicy>(result), +[](gpointer value) {
        delete static_cast<std::shared_ptr<ContentPolicy>*>(value);
      });
  return result;
}
}  // namespace

bool handle_network_method(LinuxWebView* view, FlMethodCall* call) {
  if (handle_scheme_method(view, call)) return true;
  if (strcmp(fl_method_call_get_name(call), "setContentRules")) return false;
  auto* json = map_lookup_string(fl_method_call_get_args(call), "json");
  auto state = policy(view);
  if (!json || strlen(json) > 2 * 1024 * 1024 || state->closed) {
    respond(call, success_response(fl_value_new_bool(false)));
    return true;
  }
  if (state->pending) state->pending->finish(false);
  if (!strcmp(json, "[]")) {
    if (state->filter) {
      webkit_user_content_manager_remove_filter(state->manager, state->filter);
      webkit_user_content_filter_unref(state->filter);
      state->filter = nullptr;
    }
    state->pending.reset();
    respond(call, success_response(fl_value_new_bool(true)));
    return true;
  }
  auto request = std::make_shared<RuleUpdate>(call);
  request->owner = state;
  state->pending = request;
  GError* error = nullptr;
  auto* path = g_dir_make_tmp("webview-all-rules-XXXXXX", &error);
  if (!path) {
    g_clear_error(&error);
    request->finish(false);
    return true;
  }
  request->path = path;
  g_free(path);
  auto* id = g_uuid_string_random();
  request->id = id;
  g_free(id);
  request->store = webkit_user_content_filter_store_new(request->path.c_str());
  request->timer = g_timeout_add_full(
      G_PRIORITY_DEFAULT, 30000,
      +[](gpointer data) -> gboolean {
        auto value = *static_cast<std::shared_ptr<RuleUpdate>*>(data);
        value->timer = 0;
        value->finish(false);
        return G_SOURCE_REMOVE;
      },
      new std::shared_ptr<RuleUpdate>(request),
      +[](gpointer data) {
        delete static_cast<std::shared_ptr<RuleUpdate>*>(data);
      });
  auto* source = g_bytes_new(json, strlen(json));
  webkit_user_content_filter_store_save(
      request->store, request->id.c_str(), source, request->cancelled,
      +[](GObject* object, GAsyncResult* result, gpointer data) {
        std::unique_ptr<std::shared_ptr<RuleUpdate>> holder(
            static_cast<std::shared_ptr<RuleUpdate>*>(data));
        auto request = *holder;
        GError* error = nullptr;
        auto* filter = webkit_user_content_filter_store_save_finish(
            WEBKIT_USER_CONTENT_FILTER_STORE(object), result, &error);
        auto state = request->owner.lock();
        if (filter && request->call && state && !state->closed &&
            state->pending == request) {
          if (state->filter) {
            webkit_user_content_manager_remove_filter(state->manager,
                                                      state->filter);
            webkit_user_content_filter_unref(state->filter);
          }
          state->filter = filter;
          webkit_user_content_manager_add_filter(state->manager, filter);
          request->finish(true);
        } else {
          if (filter) webkit_user_content_filter_unref(filter);
          request->finish(false);
        }
        if (state && state->pending == request) state->pending.reset();
        g_clear_error(&error);
      },
      new std::shared_ptr<RuleUpdate>(request));
  g_bytes_unref(source);
  return true;
}

void dispose_network_operations(LinuxWebView* view) {
  dispose_scheme_operations(view);
  auto* value = static_cast<std::shared_ptr<ContentPolicy>*>(
      g_object_get_data(G_OBJECT(view->web_view), kPolicy));
  if (!value) return;
  auto state = *value;
  state->closed = true;
  if (state->pending) state->pending->finish(false);
  state->pending.reset();
  g_object_set_data(G_OBJECT(view->web_view), kPolicy, nullptr);
}
