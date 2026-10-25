#include "plugin/webview_all_linux_plugin_private.h"
#include "common/method_channel_utils.h"
#include "webview/webview_environment.h"

#include <libsoup/soup.h>

#include <cstring>

static void respond_environment_error(FlMethodCall* method_call, GError* error) {
  respond(method_call,
          error_response(linux_environment_error_code(error),
                         error ? error->message
                               : "Unable to create the Linux WebView environment."));
  g_clear_error(&error);
}

static void add_cookie_finished_cb(GObject* object,
                                   GAsyncResult* result,
                                   gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  webkit_cookie_manager_add_cookie_finish(WEBKIT_COOKIE_MANAGER(object), result,
                                          &error);
  if (error != nullptr) {
    respond(method_call, error_response("cookie_error", error->message));
    g_clear_error(&error);
  } else {
    respond(method_call, success_response());
  }
  g_object_unref(method_call);
}

static void clear_cookies_finished_cb(GObject* object,
                                      GAsyncResult* result,
                                      gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  webkit_website_data_manager_clear_finish(
      WEBKIT_WEBSITE_DATA_MANAGER(object), result, &error);
  if (error != nullptr) {
    respond(method_call, error_response("cookie_error", error->message));
    g_clear_error(&error);
  } else {
    respond(method_call, success_response(fl_value_new_bool(true)));
  }
  g_object_unref(method_call);
}

static void clear_website_data_finished_cb(GObject* object,
                                           GAsyncResult* result,
                                           gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  webkit_website_data_manager_clear_finish(
      WEBKIT_WEBSITE_DATA_MANAGER(object), result, &error);
  if (error != nullptr) {
    respond(method_call,
            error_response("website_data_error", error->message));
    g_clear_error(&error);
  } else {
    respond(method_call, success_response());
  }
  g_object_unref(method_call);
}

static void get_cookies_finished_cb(GObject* object,
                                    GAsyncResult* result,
                                    gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  GList* cookies = webkit_cookie_manager_get_cookies_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (error != nullptr) {
    respond(method_call, error_response("cookie_error", error->message));
    g_clear_error(&error);
    g_object_unref(method_call);
    return;
  }

  FlValue* list = fl_value_new_list();
  for (GList* item = cookies; item != nullptr; item = item->next) {
    SoupCookie* cookie = static_cast<SoupCookie*>(item->data);
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(
        map, "name",
        fl_value_new_string(soup_cookie_get_name(cookie) != nullptr
                                ? soup_cookie_get_name(cookie)
                                : ""));
    fl_value_set_string_take(
        map, "value",
        fl_value_new_string(soup_cookie_get_value(cookie) != nullptr
                                ? soup_cookie_get_value(cookie)
                                : ""));
    fl_value_set_string_take(
        map, "domain",
        fl_value_new_string(soup_cookie_get_domain(cookie) != nullptr
                                ? soup_cookie_get_domain(cookie)
                                : ""));
    fl_value_set_string_take(
        map, "path",
        fl_value_new_string(soup_cookie_get_path(cookie) != nullptr
                                ? soup_cookie_get_path(cookie)
                                : "/"));
    fl_value_append_take(list, map);
  }

  g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  respond(method_call, success_response(list));
  g_object_unref(method_call);
}

void root_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  WebviewAllLinuxPlugin* self = static_cast<WebviewAllLinuxPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "ensureEnvironment") == 0 ||
      strcmp(method, "initializeEnvironment") == 0) {
    FlValue* user_data = map_lookup(args, "userDataPath");
    FlValue* cache = map_lookup(args, "cachePath");
    if ((args && fl_value_get_type(args) != FL_VALUE_TYPE_NULL &&
         fl_value_get_type(args) != FL_VALUE_TYPE_MAP) ||
        (user_data && fl_value_get_type(user_data) != FL_VALUE_TYPE_NULL &&
         fl_value_get_type(user_data) != FL_VALUE_TYPE_STRING) ||
        (cache && fl_value_get_type(cache) != FL_VALUE_TYPE_NULL &&
         fl_value_get_type(cache) != FL_VALUE_TYPE_STRING)) {
      respond(method_call,
              error_response("environment_creation_failed",
                             "Environment paths must be strings or null."));
      return;
    }
    GError* error = nullptr;
    if (!ensure_linux_environment(map_lookup_string(args, "userDataPath"),
                                  map_lookup_string(args, "cachePath"),
                                  strcmp(method, "initializeEnvironment") == 0,
                                  &error)) {
      respond_environment_error(method_call, error);
      return;
    }
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "createWebView") == 0) {
    GError* error = nullptr;
    LinuxWebView* webview = create_linux_webview(self, &error);
    if (webview == nullptr) {
      respond_environment_error(method_call, error);
      return;
    }
    respond(method_call, success_response(fl_value_new_int(webview->id)));
    return;
  }

  const bool set_cookie = strcmp(method, "setCookie") == 0;
  const bool get_cookies = strcmp(method, "getCookies") == 0;
  if (!set_cookie && !get_cookies && strcmp(method, "clearCookies") != 0 &&
      strcmp(method, "clearAllWebsiteData") != 0) {
    respond(method_call,
            FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
    return;
  }
  const gchar* name = map_lookup_string(args, "name");
  const gchar* value = map_lookup_string(args, "value");
  const gchar* domain = map_lookup_string(args, "domain");
  const gchar* path = map_lookup_string(args, "path");
  const gchar* url = map_lookup_string(args, "url");
  if (set_cookie && (name == nullptr || strlen(name) == 0 || value == nullptr ||
                     domain == nullptr || strlen(domain) == 0)) {
    respond(method_call,
            error_response("invalid_cookie",
                           "Cookie name, value, and domain are required."));
    return;
  }
  if (get_cookies && (url == nullptr || strlen(url) == 0)) {
    respond(method_call,
            error_response("invalid_url", "A non-empty URL is required."));
    return;
  }

  GError* error = nullptr;
  WebKitWebContext* context = get_linux_environment_context(&error);
  if (!context) {
    respond_environment_error(method_call, error);
    return;
  }
  WebKitCookieManager* cookie_manager =
      webkit_web_context_get_cookie_manager(context);
  WebKitWebsiteDataManager* website_data_manager =
      webkit_web_context_get_website_data_manager(context);

  if (strcmp(method, "clearCookies") == 0) {
    g_object_ref(method_call);
    webkit_website_data_manager_clear(
        website_data_manager, WEBKIT_WEBSITE_DATA_COOKIES, 0, nullptr,
        clear_cookies_finished_cb, method_call);
    return;
  }

  if (strcmp(method, "clearAllWebsiteData") == 0) {
    g_object_ref(method_call);
    webkit_website_data_manager_clear(
        website_data_manager, WEBKIT_WEBSITE_DATA_ALL, 0, nullptr,
        clear_website_data_finished_cb, method_call);
    return;
  }

  if (set_cookie) {
    SoupCookie* cookie =
        soup_cookie_new(name, value, domain, path != nullptr ? path : "/", -1);
    g_object_ref(method_call);
    webkit_cookie_manager_add_cookie(cookie_manager, cookie, nullptr,
                                     add_cookie_finished_cb, method_call);
    soup_cookie_free(cookie);
    return;
  }

  if (get_cookies) {
    g_object_ref(method_call);
    webkit_cookie_manager_get_cookies(cookie_manager, url, nullptr,
                                      get_cookies_finished_cb, method_call);
    return;
  }

  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}
