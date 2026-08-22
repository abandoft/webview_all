#include "plugin/webview_all_linux_plugin_private.h"
#include "common/method_channel_utils.h"

#include <libsoup/soup.h>

#include <cstring>

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

  if (strcmp(method, "createWebView") == 0) {
    LinuxWebView* webview = create_linux_webview(self);
    if (webview == nullptr) {
      respond(method_call, error_response("creation_error",
                                          "Unable to create Linux WebView."));
      return;
    }
    respond(method_call, success_response(fl_value_new_int(webview->id)));
    return;
  }

  WebKitWebContext* context = webkit_web_context_get_default();
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

  if (strcmp(method, "setCookie") == 0) {
    const gchar* name = map_lookup_string(args, "name");
    const gchar* value = map_lookup_string(args, "value");
    const gchar* domain = map_lookup_string(args, "domain");
    const gchar* path = map_lookup_string(args, "path");
    if (name == nullptr || strlen(name) == 0 || value == nullptr ||
        domain == nullptr || strlen(domain) == 0) {
      respond(method_call,
              error_response("invalid_cookie",
                             "Cookie name, value, and domain are required."));
      return;
    }

    SoupCookie* cookie =
        soup_cookie_new(name, value, domain, path != nullptr ? path : "/", -1);
    g_object_ref(method_call);
    webkit_cookie_manager_add_cookie(cookie_manager, cookie, nullptr,
                                     add_cookie_finished_cb, method_call);
    soup_cookie_free(cookie);
    return;
  }

  if (strcmp(method, "getCookies") == 0) {
    const gchar* url = map_lookup_string(args, "url");
    if (url == nullptr || strlen(url) == 0) {
      respond(method_call,
              error_response("invalid_url", "A non-empty URL is required."));
      return;
    }

    g_object_ref(method_call);
    webkit_cookie_manager_get_cookies(cookie_manager, url, nullptr,
                                      get_cookies_finished_cb, method_call);
    return;
  }

  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}
