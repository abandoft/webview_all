#include "plugin/webview_all_linux_plugin_private.h"
#include "common/method_channel_utils.h"
#include "webview/webview_environment.h"
#include "webview/webview_internal.h"

#include <libsoup/soup.h>

#include <cstring>
#include <string>
#include <vector>
#include <memory>

namespace {
const guint64 scoped_data_flags[] = {
    WEBKIT_WEBSITE_DATA_COOKIES,
    WEBKIT_WEBSITE_DATA_MEMORY_CACHE | WEBKIT_WEBSITE_DATA_DISK_CACHE | WEBKIT_WEBSITE_DATA_OFFLINE_APPLICATION_CACHE,
    WEBKIT_WEBSITE_DATA_LOCAL_STORAGE, WEBKIT_WEBSITE_DATA_SESSION_STORAGE,
    WEBKIT_WEBSITE_DATA_INDEXEDDB_DATABASES, WEBKIT_WEBSITE_DATA_WEBSQL_DATABASES,
    WEBKIT_WEBSITE_DATA_DOM_CACHE, WEBKIT_WEBSITE_DATA_SERVICE_WORKER_REGISTRATIONS};
struct ScopedDataRequest {
  FlMethodCall* call;
  WebKitWebsiteDataManager* manager;
  GList* records = nullptr;
  std::string domain;
  bool filter, clearing;
  guint64 mask;
  std::vector<int> types;
  ~ScopedDataRequest() {
    g_list_free_full(records, reinterpret_cast<GDestroyNotify>(webkit_website_data_unref));
    g_object_unref(call); g_object_unref(manager);
  }
};
void handle_scoped_data(WebKitWebsiteDataManager* manager, FlMethodCall* call, FlValue* args, bool clearing) {
  auto* target = map_lookup(args, "target");
  const auto* domain = map_lookup_string(target, "value");
  const auto* scope = map_lookup_string(target, "scope");
  if ((target && fl_value_get_type(target) != FL_VALUE_TYPE_NULL && (!scope || strcmp(scope, "domain"))) || (clearing && (!domain || !*domain))) {
    respond(call, error_response("unsupported_scope", "WebKitGTK records use domain scope; origins are never widened.")); return;
  }
  auto* types = map_lookup(args, "dataTypes");
  if (!types || fl_value_get_type(types) != FL_VALUE_TYPE_LIST) {
    respond(call, error_response("invalid_types", "Website-data categories are required.")); return;
  }
  auto request = std::make_unique<ScopedDataRequest>();
  request->call = FL_METHOD_CALL(g_object_ref(call));
  request->manager = WEBKIT_WEBSITE_DATA_MANAGER(g_object_ref(manager));
  request->clearing = clearing; request->filter = domain != nullptr;
  request->domain = domain ? domain : ""; request->mask = 0;
  for (size_t i = 0; i < fl_value_get_length(types); i++) {
    auto* type = fl_value_get_list_value(types, i);
    if (fl_value_get_type(type) != FL_VALUE_TYPE_INT || fl_value_get_int(type) < 0 || fl_value_get_int(type) >= 8) {
      respond(call, error_response("invalid_types", "Unknown website-data category.")); return;
    }
    int index = fl_value_get_int(type);
    request->types.push_back(index); request->mask |= scoped_data_flags[index];
  }
  if (!request->mask) { respond(call, success_response(clearing ? nullptr : fl_value_new_list())); return; }
  webkit_website_data_manager_fetch(manager, static_cast<WebKitWebsiteDataTypes>(request->mask), nullptr,
    +[](GObject* object, GAsyncResult* result, gpointer data) {
      std::unique_ptr<ScopedDataRequest> request(static_cast<ScopedDataRequest*>(data));
      GError* error = nullptr;
      auto* records = webkit_website_data_manager_fetch_finish(WEBKIT_WEBSITE_DATA_MANAGER(object), result, &error);
      request->records = records;
      if (error) { respond(request->call, error_response("website_data_error", error->message)); g_clear_error(&error); return; }
      if (!request->clearing) {
        auto* output = fl_value_new_list();
        for (auto* item = records; item; item = item->next) {
          auto* record = static_cast<WebKitWebsiteData*>(item->data);
          if (request->filter && request->domain != webkit_website_data_get_name(record)) continue;
          if (fl_value_get_length(output) >= 4096) {
            fl_value_unref(output); respond(request->call, error_response("record_limit", "Request a specific domain to limit the record list.")); return;
          }
          auto* value = fl_value_new_map(); auto* types = fl_value_new_list();
          auto present = webkit_website_data_get_types(record);
          for (int type : request->types) if (present & scoped_data_flags[type]) fl_value_append_take(types, fl_value_new_int(type));
          fl_value_set_string_take(value, "scope", fl_value_new_string("domain"));
          fl_value_set_string_take(value, "value", fl_value_new_string(webkit_website_data_get_name(record)));
          fl_value_set_string_take(value, "dataTypes", types);
          fl_value_set_string_take(value, "sizeBytes", fl_value_new_int(webkit_website_data_get_size(record, static_cast<WebKitWebsiteDataTypes>(request->mask))));
          fl_value_append_take(output, value);
        }
        respond(request->call, success_response(output)); return;
      }
      GList* selected = nullptr;
      for (auto* item = records; item; item = item->next) {
        auto* record = static_cast<WebKitWebsiteData*>(item->data);
        if (request->domain == webkit_website_data_get_name(record)) selected = g_list_prepend(selected, record);
      }
      if (!selected) { respond(request->call, success_response()); return; }
      auto mask = static_cast<WebKitWebsiteDataTypes>(request->mask);
      auto* pending = request.release();
      webkit_website_data_manager_remove(WEBKIT_WEBSITE_DATA_MANAGER(object), mask, selected, nullptr,
        +[](GObject* object, GAsyncResult* result, gpointer data) {
          std::unique_ptr<ScopedDataRequest> request(static_cast<ScopedDataRequest*>(data));
          GError* error = nullptr;
          auto ok = webkit_website_data_manager_remove_finish(WEBKIT_WEBSITE_DATA_MANAGER(object), result, &error);
          respond(request->call, ok ? success_response() : error_response("website_data_error", error ? error->message : "Removing website data failed."));
          g_clear_error(&error);
        }, pending);
      g_list_free(selected);
    }, request.release());
}
}  // namespace

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

struct DeleteCookieRequest {
  FlMethodCall* call;
  std::string name;
  std::string domain;
  std::string path;
  guint pending = 0;
  std::string error;
};

static void finish_delete_cookie(DeleteCookieRequest* request) {
  if (request->error.empty())
    respond(request->call, success_response());
  else
    respond(request->call,
            error_response("cookie_error", request->error.c_str()));
  g_object_unref(request->call);
  delete request;
}

static void delete_cookie_finished_cb(GObject* object, GAsyncResult* result,
                                      gpointer data) {
  auto* request = static_cast<DeleteCookieRequest*>(data);
  GError* error = nullptr;
  webkit_cookie_manager_delete_cookie_finish(WEBKIT_COOKIE_MANAGER(object),
                                             result, &error);
  if (error) {
    request->error = error->message;
    g_clear_error(&error);
  }
  if (--request->pending == 0) finish_delete_cookie(request);
}

static void delete_matching_cookies_cb(GObject* object, GAsyncResult* result,
                                       gpointer data) {
  auto* request = static_cast<DeleteCookieRequest*>(data);
  GError* error = nullptr;
  GList* cookies = webkit_cookie_manager_get_cookies_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (error) {
    request->error = error->message;
    g_clear_error(&error);
    finish_delete_cookie(request);
    return;
  }
  std::vector<SoupCookie*> matches;
  for (GList* entry = cookies; entry; entry = entry->next) {
    auto* cookie = static_cast<SoupCookie*>(entry->data);
    if (request->name == soup_cookie_get_name(cookie) &&
        g_ascii_strcasecmp(request->domain.c_str(),
                           soup_cookie_get_domain(cookie)) == 0 &&
        request->path == soup_cookie_get_path(cookie))
      matches.push_back(cookie);
  }
  request->pending = matches.size();
  if (matches.empty())
    finish_delete_cookie(request);
  else
    for (auto* cookie : matches)
      webkit_cookie_manager_delete_cookie(WEBKIT_COOKIE_MANAGER(object), cookie,
                                          nullptr, delete_cookie_finished_cb,
                                          request);
  g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
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
    fl_value_set_string_take(map, "isSecure",
                             fl_value_new_bool(soup_cookie_get_secure(cookie)));
    fl_value_set_string_take(
        map, "isHttpOnly",
        fl_value_new_bool(soup_cookie_get_http_only(cookie)));
    fl_value_set_string_take(
        map, "sameSite",
        fl_value_new_int(soup_cookie_get_same_site_policy(cookie)));
    GDateTime* expires = soup_cookie_get_expires(cookie);
    fl_value_set_string_take(map, "isSession",
                             fl_value_new_bool(expires == nullptr));
    if (expires)
      fl_value_set_string_take(
          map, "expires",
          fl_value_new_int(g_date_time_to_unix(expires) * 1000));
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

  if (handle_browser_root_method(self, method_call)) return;

  if (strcmp(method, "profileManagementCapabilities") == 0) {
    FlValue* value = fl_value_new_map();
    fl_value_set_string_take(value, "listing", fl_value_new_bool(TRUE));
    fl_value_set_string_take(value, "deletion", fl_value_new_bool(TRUE));
    fl_value_set_string_take(value, "limitation", fl_value_new_string("Only plugin-owned named profiles are managed. Close their views and dispose saved navigation states before deletion."));
    respond(method_call, success_response(value)); return;
  }
  if (strcmp(method, "listProfiles") == 0) {
    FlValue* values = fl_value_new_list();
    for (const auto& profile : list_linux_profiles()) {
      FlValue* value = fl_value_new_map();
      fl_value_set_string_take(value, "name", fl_value_new_string(profile.name.c_str()));
      fl_value_set_string_take(value, "deletionPending", fl_value_new_bool(profile.pending));
      fl_value_append_take(values, value);
    }
    respond(method_call, success_response(values)); return;
  }
  if (strcmp(method, "requestProfileDeletion") == 0) {
    const auto* name = map_lookup_string(args, "name");
    g_object_ref(method_call);
    delete_linux_profile(name ? name : "", [method_call](LinuxProfileDeletion outcome) {
      FlValue* value = fl_value_new_map();
      fl_value_set_string_take(value, "status", fl_value_new_string(outcome.status.c_str()));
      fl_value_set_string_take(value, "description", fl_value_new_string(outcome.description.c_str()));
      respond(method_call, success_response(value)); g_object_unref(method_call);
    }); return;
  }

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

  if (strcmp(method, "createWebView") == 0 || strcmp(method, "createRelatedWebView") == 0) {
    GError* error = nullptr;
    WebKitWebView* related = nullptr;
    if (strcmp(method, "createRelatedWebView") == 0) {
      auto parent_id = map_lookup_int(args, "parentId", -1);
      if (parent_id <= 0 || parent_id > G_MAXINT) { respond(method_call, success_response()); return; }
      auto* parent = static_cast<LinuxWebView*>(g_hash_table_lookup(self->webviews, GINT_TO_POINTER(static_cast<gint>(parent_id))));
      if (!parent) { respond(method_call, success_response()); return; }
      related = parent->web_view;
    }
    LinuxWebView* webview = create_linux_webview(
        self, &error, map_lookup_bool(args, "incognito", FALSE), related,
        map_lookup_string(args, "profileName"));
    if (webview == nullptr) {
      respond_environment_error(method_call, error);
      return;
    }
    respond(method_call, success_response(fl_value_new_int(webview->id)));
    return;
  }

  const bool set_cookie = strcmp(method, "setCookie") == 0;
  const bool delete_cookie = strcmp(method, "deleteCookie") == 0;
  const bool get_cookies = strcmp(method, "getCookies") == 0;
  if (!set_cookie && !delete_cookie && !get_cookies &&
      strcmp(method, "clearCookies") != 0 &&
      strcmp(method, "clearAllWebsiteData") != 0 &&
      strcmp(method, "getWebsiteDataRecords") != 0 &&
      strcmp(method, "clearWebsiteDataFor") != 0 &&
      strcmp(method, "clearWebsiteData") != 0) {
    respond(method_call,
            FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
    return;
  }
  const gchar* name = map_lookup_string(args, "name");
  const gchar* value = map_lookup_string(args, "value");
  const gchar* domain = map_lookup_string(args, "domain");
  const gchar* path = map_lookup_string(args, "path");
  const gchar* url = map_lookup_string(args, "url");
  if ((set_cookie || delete_cookie) &&
      (name == nullptr || strlen(name) == 0 ||
       (set_cookie && value == nullptr) || domain == nullptr ||
       strlen(domain) == 0)) {
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
  WebKitWebContext* context = nullptr;
  FlValue* scoped_id = map_lookup(args, "webViewId");
  if (scoped_id != nullptr) {
    LinuxWebView* scoped_view = fl_value_get_type(scoped_id) == FL_VALUE_TYPE_INT &&
        fl_value_get_int(scoped_id) > 0 && fl_value_get_int(scoped_id) <= G_MAXINT
        ? static_cast<LinuxWebView*>(g_hash_table_lookup(
            self->webviews, GINT_TO_POINTER(fl_value_get_int(scoped_id))))
        : nullptr;
    if (scoped_view == nullptr) {
      respond(method_call, error_response("invalid_session", "The WebView session has closed or does not exist."));
      return;
    }
    context = webkit_web_view_get_context(scoped_view->web_view);
  } else {
    context = get_linux_environment_context(&error);
  }
  if (!context) {
    respond_environment_error(method_call, error);
    return;
  }
  WebKitCookieManager* cookie_manager =
      webkit_web_context_get_cookie_manager(context);
  WebKitWebsiteDataManager* website_data_manager =
      webkit_web_context_get_website_data_manager(context);
  if (!strcmp(method, "getWebsiteDataRecords") || !strcmp(method, "clearWebsiteDataFor")) {
    handle_scoped_data(website_data_manager, method_call, args, !strcmp(method, "clearWebsiteDataFor")); return;
  }

  if (strcmp(method, "clearCookies") == 0) {
    g_object_ref(method_call);
    webkit_website_data_manager_clear(
        website_data_manager, WEBKIT_WEBSITE_DATA_COOKIES, 0, nullptr,
        clear_cookies_finished_cb, method_call);
    return;
  }

  if (strcmp(method, "clearWebsiteData") == 0) {
    auto* types = map_lookup(args, "dataTypes");
    if (!types || fl_value_get_type(types) != FL_VALUE_TYPE_LIST) {
      respond(method_call,
              error_response("invalid_argument",
                             "Website data categories are required."));
      return;
    }
    const WebKitWebsiteDataTypes flags[] = {
        WEBKIT_WEBSITE_DATA_COOKIES,
        static_cast<WebKitWebsiteDataTypes>(
            WEBKIT_WEBSITE_DATA_MEMORY_CACHE | WEBKIT_WEBSITE_DATA_DISK_CACHE |
            WEBKIT_WEBSITE_DATA_OFFLINE_APPLICATION_CACHE),
        WEBKIT_WEBSITE_DATA_LOCAL_STORAGE,
        WEBKIT_WEBSITE_DATA_SESSION_STORAGE,
        WEBKIT_WEBSITE_DATA_INDEXEDDB_DATABASES,
        WEBKIT_WEBSITE_DATA_WEBSQL_DATABASES,
        WEBKIT_WEBSITE_DATA_DOM_CACHE,
        WEBKIT_WEBSITE_DATA_SERVICE_WORKER_REGISTRATIONS,
    };
    guint64 mask = 0;
    for (size_t index = 0; index < fl_value_get_length(types); index++) {
      auto* value = fl_value_get_list_value(types, index);
      if (fl_value_get_type(value) != FL_VALUE_TYPE_INT ||
          fl_value_get_int(value) < 0 || fl_value_get_int(value) >= 8) {
        respond(method_call, error_response("invalid_argument",
                                            "Unknown website data category."));
        return;
      }
      mask |= flags[fl_value_get_int(value)];
    }
    if (!mask) {
      respond(method_call, success_response());
      return;
    }
    g_object_ref(method_call);
    webkit_website_data_manager_clear(
        website_data_manager, static_cast<WebKitWebsiteDataTypes>(mask), 0,
        nullptr, clear_website_data_finished_cb, method_call);
    return;
  }

  if (strcmp(method, "clearAllWebsiteData") == 0) {
    g_object_ref(method_call);
    webkit_website_data_manager_clear(
        website_data_manager, WEBKIT_WEBSITE_DATA_ALL, 0, nullptr,
        clear_website_data_finished_cb, method_call);
    return;
  }

  if (delete_cookie) {
    if (!url || !*url) {
      respond(method_call,
              error_response("invalid_url", "A cookie URL is required."));
      return;
    }
    auto* request =
        new DeleteCookieRequest{FL_METHOD_CALL(g_object_ref(method_call)), name,
                                domain, path ? path : "/"};
    webkit_cookie_manager_get_cookies(cookie_manager, url, nullptr,
                                      delete_matching_cookies_cb, request);
    return;
  }
  if (set_cookie) {
    SoupCookie* cookie =
        soup_cookie_new(name, value != nullptr ? value : "", domain,
                        path != nullptr ? path : "/", -1);
    if (!cookie) {
      respond(method_call,
              error_response("invalid_cookie",
                             "The cookie was rejected by the native store."));
      return;
    }
    FlValue* expiration = map_lookup(args, "expires");
    if (expiration && fl_value_get_type(expiration) == FL_VALUE_TYPE_INT) {
      GDateTime* date =
          g_date_time_new_from_unix_utc(fl_value_get_int(expiration) / 1000);
      if (date) {
        soup_cookie_set_expires(cookie, date);
        g_date_time_unref(date);
      }
    }
    soup_cookie_set_secure(cookie, map_lookup_bool(args, "isSecure", FALSE));
    soup_cookie_set_http_only(cookie,
                              map_lookup_bool(args, "isHttpOnly", FALSE));
    const gint64 same_site = map_lookup_int(args, "sameSite", -1);
    if (same_site >= 0 && same_site <= 2)
      soup_cookie_set_same_site_policy(
          cookie, static_cast<SoupSameSitePolicy>(same_site));
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
