#include <webkit2/webkit2.h>

#include <glib/gstdio.h>
#include <libsoup/soup.h>

#include <functional>
#include <string>
#include <vector>

#include "../src/webview/webview_environment.h"
#include "javascript_test_helpers.h"

namespace {

std::string test_root;

std::string path(const char *name) { return test_root + "/" + name; }

void isolated(const std::function<void()> &body) {
  if (g_test_subprocess()) {
    body();
    return;
  }
  g_test_trap_subprocess(nullptr, 30 * G_TIME_SPAN_SECOND,
                         G_TEST_SUBPROCESS_DEFAULT);
  g_test_trap_assert_passed();
}

void assert_error(GError **error, LinuxEnvironmentError code) {
  g_assert_error(*error, linux_environment_error_quark(), code);
  g_clear_error(error);
}

void default_environment_test() {
  isolated([] {
    GError *error = nullptr;
    g_assert_true(ensure_linux_environment(nullptr, nullptr, FALSE, &error));
    g_assert_no_error(error);
    WebKitWebContext *context = get_linux_environment_context(&error);
    g_assert_true(context == webkit_web_context_get_default());
    WebKitWebsiteDataManager *manager =
        webkit_web_context_get_website_data_manager(context);
    g_assert_null(webkit_website_data_manager_get_base_data_directory(manager));
    g_assert_null(
        webkit_website_data_manager_get_base_cache_directory(manager));
    g_assert_true(ensure_linux_environment("", "", FALSE, &error));
    g_autofree gchar *default_data =
        g_build_filename(g_get_user_data_dir(), g_get_prgname(), nullptr);
    g_autofree gchar *default_cache =
        g_build_filename(g_get_user_cache_dir(), g_get_prgname(), nullptr);
    g_assert_true(
        ensure_linux_environment(default_data, default_cache, FALSE, &error));
    g_assert_no_error(error);
    g_assert_false(ensure_linux_environment(path("other").c_str(), nullptr,
                                            FALSE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT);
  });
}

void custom_environment_test() {
  isolated([] {
    GError *error = nullptr;
    const std::string data = path("profile/data");
    const std::string cache = path("profile/cache");
    g_assert_true(ensure_linux_environment(
        (data + "/./").c_str(), (cache + "/unused/..").c_str(), FALSE, &error));
    g_assert_no_error(error);
    WebKitWebContext *context = get_linux_environment_context(&error);
    g_assert_true(context != webkit_web_context_get_default());
    WebKitWebsiteDataManager *manager =
        webkit_web_context_get_website_data_manager(context);
    g_assert_cmpstr(
        webkit_website_data_manager_get_base_data_directory(manager), ==,
        data.c_str());
    g_assert_cmpstr(
        webkit_website_data_manager_get_base_cache_directory(manager), ==,
        cache.c_str());
    g_assert_true(g_file_test(data.c_str(), G_FILE_TEST_IS_DIR));
    g_assert_true(g_file_test(cache.c_str(), G_FILE_TEST_IS_DIR));
    // Separate callers/engines reuse the process-wide selection.
    g_assert_true(ensure_linux_environment(nullptr, nullptr, FALSE, &error));
    g_assert_true(ensure_linux_environment((data + "/").c_str(), cache.c_str(),
                                           FALSE, &error));
    g_assert_true(get_linux_environment_context(&error) == context);
    g_assert_no_error(error);
    g_assert_false(ensure_linux_environment("", "", FALSE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT);
    g_assert_false(
        ensure_linux_environment(data.c_str(), nullptr, FALSE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT);
  });
}

void partial_configuration_test() {
  isolated([] {
    GError *error = nullptr;
    const std::string data = path("partial-data");
    g_assert_true(
        ensure_linux_environment(data.c_str(), nullptr, FALSE, &error));
    g_assert_true(ensure_linux_environment(data.c_str(), "", FALSE, &error));
    g_assert_no_error(error);
    g_autofree gchar *default_cache =
        g_build_filename(g_get_user_cache_dir(), g_get_prgname(), nullptr);
    WebKitWebsiteDataManager *manager =
        webkit_web_context_get_website_data_manager(
            get_linux_environment_context(&error));
    g_assert_cmpstr(
        webkit_website_data_manager_get_base_cache_directory(manager), ==,
        default_cache);
    // An omitted field in an explicit request means the platform default,
    // rather than inheriting the custom field from the active environment.
    g_assert_false(
        ensure_linux_environment(nullptr, default_cache, FALSE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT);
  });
}

void relative_path_test() {
  isolated([] {
    GError *error = nullptr;
    g_assert_cmpint(g_chdir(test_root.c_str()), ==, 0);
    g_assert_true(
        ensure_linux_environment(" profile /./data", "cache", FALSE, &error));
    g_assert_no_error(error);
    g_assert_true(ensure_linux_environment(
        path(" profile /data").c_str(), path("cache").c_str(), FALSE, &error));
    g_assert_no_error(error);
    g_assert_true(
        g_file_test(path(" profile /data").c_str(), G_FILE_TEST_IS_DIR));
  });
}

void strict_initialization_test() {
  isolated([] {
    GError *error = nullptr;
    g_assert_true(ensure_linux_environment(nullptr, nullptr, TRUE, &error));
    g_assert_no_error(error);
    g_assert_false(ensure_linux_environment(nullptr, nullptr, TRUE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_ALREADY_INITIALIZED);
    g_assert_false(
        ensure_linux_environment(path("other").c_str(), nullptr, TRUE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_ALREADY_INITIALIZED);
    g_assert_true(ensure_linux_environment(nullptr, nullptr, FALSE, &error));
    g_assert_no_error(error);
  });
}

void implicit_view_initialization_test() {
  isolated([] {
    GError *error = nullptr;
    WebKitUserContentManager *manager = webkit_user_content_manager_new();
    WebKitWebView *view = create_linux_environment_web_view(manager, &error);
    g_assert_no_error(error);
    g_assert_true(webkit_web_view_get_context(view) ==
                  webkit_web_context_get_default());
    g_object_ref_sink(view);
    gtk_widget_destroy(GTK_WIDGET(view));
    g_object_unref(view);
    g_object_unref(manager);
    g_assert_false(ensure_linux_environment(path("other").c_str(), nullptr,
                                            FALSE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT);
    g_assert_false(ensure_linux_environment(nullptr, nullptr, TRUE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_ALREADY_INITIALIZED);
  });
}

void failure_retry_test() {
  isolated([] {
    GError *error = nullptr;
    const std::string data = path("blocked");
    const std::string cache = path("cache");
    g_assert_true(g_file_set_contents(data.c_str(), "file", -1, &error));
    g_assert_no_error(error);
    g_assert_false(
        ensure_linux_environment(data.c_str(), cache.c_str(), TRUE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CREATION_FAILED);
    g_assert_cmpint(g_unlink(data.c_str()), ==, 0);
    g_assert_true(g_file_set_contents(cache.c_str(), "file", -1, &error));
    g_assert_false(
        ensure_linux_environment(data.c_str(), cache.c_str(), TRUE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CREATION_FAILED);
    g_assert_cmpint(g_unlink(cache.c_str()), ==, 0);
    g_assert_true(
        ensure_linux_environment(data.c_str(), cache.c_str(), TRUE, &error));
    g_assert_no_error(error);
    g_assert_true(get_linux_environment_context(&error) !=
                  webkit_web_context_get_default());
  });
}

void explicit_default_failure_test() {
  isolated([] {
    GError *error = nullptr;
    g_assert_cmpint(g_mkdir_with_parents(g_get_user_data_dir(), 0700), ==, 0);
    g_autofree gchar *default_data =
        g_build_filename(g_get_user_data_dir(), g_get_prgname(), nullptr);
    g_assert_true(g_file_set_contents(default_data, "file", -1, &error));
    g_assert_false(
        ensure_linux_environment(default_data, nullptr, TRUE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CREATION_FAILED);
    g_assert_cmpint(g_unlink(default_data), ==, 0);
    g_assert_true(ensure_linux_environment("", "", TRUE, &error));
    g_assert_no_error(error);
    g_assert_true(get_linux_environment_context(&error) ==
                  webkit_web_context_get_default());
  });
}

void await(bool *done) {
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  while (!*done && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_assert_true(*done);
}

void add_cookie(WebKitWebContext *context, const char *name) {
  bool done = false;
  SoupCookie *cookie =
      soup_cookie_new(name, "value", "environment.example", "/", -1);
  webkit_cookie_manager_add_cookie(
      webkit_web_context_get_cookie_manager(context), cookie, nullptr,
      [](GObject *object, GAsyncResult *result, gpointer data) {
        GError *error = nullptr;
        webkit_cookie_manager_add_cookie_finish(WEBKIT_COOKIE_MANAGER(object),
                                                result, &error);
        g_assert_no_error(error);
        *static_cast<bool *>(data) = true;
      },
      &done);
  soup_cookie_free(cookie);
  await(&done);
}

std::vector<std::string> cookie_names(WebKitWebContext *context) {
  struct Result {
    bool done = false;
    std::vector<std::string> names;
  } result;
  webkit_cookie_manager_get_cookies(
      webkit_web_context_get_cookie_manager(context),
      "http://environment.example/", nullptr,
      [](GObject *object, GAsyncResult *async_result, gpointer data) {
        auto *result = static_cast<Result *>(data);
        GError *error = nullptr;
        GList *cookies = webkit_cookie_manager_get_cookies_finish(
            WEBKIT_COOKIE_MANAGER(object), async_result, &error);
        g_assert_no_error(error);
        for (GList *item = cookies; item; item = item->next) {
          result->names.emplace_back(
              soup_cookie_get_name(static_cast<SoupCookie *>(item->data)));
        }
        g_list_free_full(cookies,
                         reinterpret_cast<GDestroyNotify>(soup_cookie_free));
        result->done = true;
      },
      &result);
  await(&result.done);
  return result.names;
}

void clear_data(WebKitWebContext *context) {
  bool done = false;
  webkit_website_data_manager_clear(
      webkit_web_context_get_website_data_manager(context),
      WEBKIT_WEBSITE_DATA_ALL, 0, nullptr,
      [](GObject *object, GAsyncResult *result, gpointer data) {
        GError *error = nullptr;
        webkit_website_data_manager_clear_finish(
            WEBKIT_WEBSITE_DATA_MANAGER(object), result, &error);
        g_assert_no_error(error);
        *static_cast<bool *>(data) = true;
      },
      &done);
  await(&done);
}

void shared_storage_test() {
  isolated([] {
    GError *error = nullptr;
    g_assert_true(ensure_linux_environment(
        path("data").c_str(), path("cache").c_str(), FALSE, &error));
    g_assert_no_error(error);
    WebKitWebContext *context = get_linux_environment_context(&error);
    WebKitWebContext *default_context = webkit_web_context_get_default();
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), box);
    WebKitUserContentManager *first_manager = webkit_user_content_manager_new();
    WebKitUserContentManager *second_manager =
        webkit_user_content_manager_new();
    WebKitWebView *first =
        create_linux_environment_web_view(first_manager, &error);
    WebKitWebView *second =
        create_linux_environment_web_view(second_manager, &error);
    WebKitWebView *other =
        WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(default_context));
    g_assert_no_error(error);
    g_assert_true(webkit_web_view_get_context(first) == context);
    g_assert_true(webkit_web_view_get_context(second) == context);
    g_assert_true(webkit_web_view_get_user_content_manager(first) ==
                  first_manager);
    g_assert_true(webkit_web_view_get_user_content_manager(second) ==
                  second_manager);
    for (WebKitWebView *view : {first, second, other}) {
      gtk_box_pack_start(GTK_BOX(box), GTK_WIDGET(view), TRUE, TRUE, 0);
    }
    gtk_widget_show_all(window);
    g_object_unref(first_manager);
    g_object_unref(second_manager);
    webview_test::load_html(first, "<body>First</body>",
                            "http://environment.example/");
    webview_test::evaluate(
        first, "localStorage.setItem('environment', 'custom'); null;");
    webview_test::load_html(second, "<body>Second</body>",
                            "http://environment.example/");
    webview_test::evaluate(
        second, "if (localStorage.getItem('environment') !== 'custom') throw "
                "new Error('Storage not shared'); null;");
    webview_test::load_html(other, "<body>Default</body>",
                            "http://environment.example/");
    webview_test::evaluate(
        other, "if (localStorage.getItem('environment') !== null) throw new "
               "Error('Default storage polluted'); "
               "localStorage.setItem('environment','default'); null;");
    add_cookie(context, "custom");
    add_cookie(default_context, "default");
    const auto custom_cookies = cookie_names(context);
    const auto default_cookies = cookie_names(default_context);
    g_assert_cmpuint(custom_cookies.size(), ==, 1);
    g_assert_cmpstr(custom_cookies.front().c_str(), ==, "custom");
    g_assert_cmpuint(default_cookies.size(), ==, 1);
    g_assert_cmpstr(default_cookies.front().c_str(), ==, "default");
    clear_data(context);
    g_assert_true(cookie_names(context).empty());
    g_assert_cmpuint(cookie_names(default_context).size(), ==, 1);
    webview_test::evaluate(
        first, "if (localStorage.getItem('environment') !== null) throw new "
               "Error('Custom storage not cleared'); null;");
    webview_test::evaluate(
        other, "if (localStorage.getItem('environment') !== 'default') throw "
               "new Error('Default storage cleared'); null;");
    gtk_widget_destroy(window);
    // Disposing every view/engine must not unlock or replace the profile.
    g_assert_true(get_linux_environment_context(&error) == context);
    g_assert_false(ensure_linux_environment("", "", FALSE, &error));
    assert_error(&error, LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT);
  });
}

void incognito_storage_test() {
  isolated([] {
    GError *error = nullptr;
    g_autoptr(WebKitUserContentManager) manager =
        webkit_user_content_manager_new();
    WebKitWebView *first =
        create_linux_environment_web_view(manager, &error, TRUE);
    g_assert_no_error(error);
    // Private views must not lock the persistent environment configuration.
    g_assert_true(ensure_linux_environment(
        path("data").c_str(), path("cache").c_str(), FALSE, &error));
    g_assert_no_error(error);
    WebKitWebView *shared =
        create_linux_environment_web_view(manager, &error);
    WebKitWebView *second =
        create_linux_environment_web_view(manager, &error, TRUE);
    g_assert_no_error(error);
    WebKitWebContext *first_context = webkit_web_view_get_context(first);
    WebKitWebContext *second_context = webkit_web_view_get_context(second);
    WebKitWebContext *shared_context = webkit_web_view_get_context(shared);
    g_assert_true(webkit_web_view_is_ephemeral(first));
    g_assert_true(webkit_web_view_is_ephemeral(second));
    g_assert_false(webkit_web_view_is_ephemeral(shared));
    g_assert_true(first_context != second_context);
    g_assert_true(first_context != shared_context);

    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), box);
    for (WebKitWebView *view : {first, shared, second}) {
      gtk_box_pack_start(GTK_BOX(box), GTK_WIDGET(view), TRUE, TRUE, 0);
    }
    gtk_widget_show_all(window);
    add_cookie(shared_context, "shared");
    add_cookie(first_context, "private");
    const auto shared_cookies = cookie_names(shared_context);
    const auto private_cookies = cookie_names(first_context);
    g_assert_cmpuint(shared_cookies.size(), ==, 1);
    g_assert_cmpuint(private_cookies.size(), ==, 1);
    g_assert_cmpstr(shared_cookies.front().c_str(), ==, "shared");
    g_assert_cmpstr(private_cookies.front().c_str(), ==, "private");
    g_assert_true(cookie_names(second_context).empty());
    webview_test::load_html(shared, "<body>Shared</body>",
                            "http://environment.example/");
    webview_test::evaluate(
        shared, "localStorage.setItem('session', 'shared'); null;");
    webview_test::load_html(first, "<body>Private</body>",
                            "http://environment.example/");
    webview_test::evaluate(
        first, "if (localStorage.getItem('session') !== null) throw new "
               "Error('Shared storage leaked'); "
               "localStorage.setItem('session', 'private'); null;");
    webview_test::load_html(second, "<body>New private</body>",
                            "http://environment.example/");
    webview_test::evaluate(
        second, "if (localStorage.getItem('session') !== null) throw new "
                "Error('Private storage leaked'); null;");
    webview_test::evaluate(
        shared, "if (localStorage.getItem('session') !== 'shared') throw new "
                "Error('Shared storage changed'); null;");
    gtk_widget_destroy(window);
  });
}

} // namespace

int main(int argc, char **argv) {
  // Protect real user data even when tests create WebKit's default context.
  GError *error = nullptr;
  g_autofree gchar *directory =
      g_dir_make_tmp("webview-environment-XXXXXX", &error);
  g_assert_no_error(error);
  test_root = directory;
  g_setenv("XDG_DATA_HOME", path("xdg-data").c_str(), TRUE);
  g_setenv("XDG_CACHE_HOME", path("xdg-cache").c_str(), TRUE);
  g_set_prgname("webview-environment-test");
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/environment/default", default_environment_test);
  g_test_add_func("/environment/custom", custom_environment_test);
  g_test_add_func("/environment/partial", partial_configuration_test);
  g_test_add_func("/environment/relative", relative_path_test);
  g_test_add_func("/environment/strict", strict_initialization_test);
  g_test_add_func("/environment/implicit-view",
                  implicit_view_initialization_test);
  g_test_add_func("/environment/failure-retry", failure_retry_test);
  g_test_add_func("/environment/explicit-default-failure",
                  explicit_default_failure_test);
  g_test_add_func("/environment/shared-storage", shared_storage_test);
  g_test_add_func("/environment/incognito-storage", incognito_storage_test);
  return g_test_run();
}
