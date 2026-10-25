#include "webview/webview_environment.h"

#include <glib/gstdio.h>

#include <cerrno>
#include <string>
#include <unistd.h>

namespace {

struct Environment {
  Environment() { g_mutex_init(&mutex); }

  GMutex mutex;
  WebKitWebContext *context = nullptr;
  std::string user_data_path;
  std::string cache_path;
};

Environment &environment() {
  // Keep the selected context alive across registrar/engine disposal, just as
  // WebKit keeps its default context alive for the lifetime of the process.
  static Environment *instance = new Environment();
  return *instance;
}

std::string canonical_path(const gchar *path) {
  g_autofree gchar *canonical = g_canonicalize_filename(path, nullptr);
  return canonical;
}

std::string default_path(const gchar *base) {
  const gchar *program_name = g_get_prgname();
  g_autofree gchar *path = g_build_filename(
      base, program_name ? program_name : "webkitgtk", nullptr);
  return canonical_path(path);
}

gboolean prepare_directory(const std::string &path, GError **error) {
  if (g_mkdir_with_parents(path.c_str(), 0700) < 0) {
    g_set_error(error, linux_environment_error_quark(),
                LINUX_ENVIRONMENT_CREATION_FAILED,
                "Unable to create WebKit directory '%s': %s", path.c_str(),
                g_strerror(errno));
    return FALSE;
  }
  if (!g_file_test(path.c_str(), G_FILE_TEST_IS_DIR) ||
      g_access(path.c_str(), W_OK | X_OK) < 0) {
    g_set_error(
        error, linux_environment_error_quark(),
        LINUX_ENVIRONMENT_CREATION_FAILED,
        "WebKit directory '%s' is not an accessible writable directory.",
        path.c_str());
    return FALSE;
  }
  return TRUE;
}

} // namespace

GQuark linux_environment_error_quark() {
  return g_quark_from_static_string("webview-all-linux-environment");
}

const gchar *linux_environment_error_code(const GError *error) {
  if (error && error->domain == linux_environment_error_quark()) {
    switch (error->code) {
    case LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT:
      return "environment_configuration_conflict";
    case LINUX_ENVIRONMENT_ALREADY_INITIALIZED:
      return "environment_already_initialized";
    default:
      break;
    }
  }
  return "environment_creation_failed";
}

gboolean ensure_linux_environment(const gchar *user_data_path,
                                  const gchar *cache_path,
                                  gboolean initialize_only, GError **error) {
  Environment &state = environment();
  g_mutex_lock(&state.mutex);
  if (state.context && initialize_only) {
    g_set_error_literal(
        error, linux_environment_error_quark(),
        LINUX_ENVIRONMENT_ALREADY_INITIALIZED,
        "The Linux WebView environment is already initialized.");
    g_mutex_unlock(&state.mutex);
    return FALSE;
  }
  const bool explicit_configuration = user_data_path || cache_path;
  if (state.context && !explicit_configuration) {
    g_mutex_unlock(&state.mutex);
    return TRUE;
  }

  const std::string default_data = default_path(g_get_user_data_dir());
  const std::string default_cache = default_path(g_get_user_cache_dir());
  const std::string data = user_data_path && *user_data_path
                               ? canonical_path(user_data_path)
                               : default_data;
  const std::string cache =
      cache_path && *cache_path ? canonical_path(cache_path) : default_cache;
  if (state.context) {
    const bool matches =
        state.user_data_path == data && state.cache_path == cache;
    if (!matches) {
      g_set_error_literal(error, linux_environment_error_quark(),
                          LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT,
                          "The requested Linux WebView environment differs "
                          "from the active environment.");
    }
    g_mutex_unlock(&state.mutex);
    return matches;
  }

  WebKitWebContext *context = nullptr;
  if (explicit_configuration &&
      (!prepare_directory(data, error) || !prepare_directory(cache, error))) {
    g_mutex_unlock(&state.mutex);
    return FALSE;
  }
  if (data == default_data && cache == default_cache) {
    // Preserve the default context and its existing persistence behavior.
    context =
        WEBKIT_WEB_CONTEXT(g_object_ref(webkit_web_context_get_default()));
  } else {
    WebKitWebsiteDataManager *manager = webkit_website_data_manager_new(
        "base-data-directory", data.c_str(), "base-cache-directory",
        cache.c_str(), nullptr);
    context = webkit_web_context_new_with_website_data_manager(manager);
    g_object_unref(manager);
  }
  if (!context) {
    g_set_error_literal(error, linux_environment_error_quark(),
                        LINUX_ENVIRONMENT_CREATION_FAILED,
                        "Unable to create the Linux WebView environment.");
    g_mutex_unlock(&state.mutex);
    return FALSE;
  }
  // Publish only after successful validation and construction, so callers can
  // correct a failed path and retry without locking in a partial environment.
  state.user_data_path = data;
  state.cache_path = cache;
  state.context = context;
  g_mutex_unlock(&state.mutex);
  return TRUE;
}

WebKitWebContext *get_linux_environment_context(GError **error) {
  if (!ensure_linux_environment(nullptr, nullptr, FALSE, error))
    return nullptr;
  return environment().context;
}

WebKitWebView *
create_linux_environment_web_view(WebKitUserContentManager *content_manager,
                                  GError **error) {
  WebKitWebContext *context = get_linux_environment_context(error);
  if (!context)
    return nullptr;
  return WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context",
                                      context, "user-content-manager",
                                      content_manager, nullptr));
}
