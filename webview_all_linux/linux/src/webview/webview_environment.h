#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_ENVIRONMENT_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_ENVIRONMENT_H_

#include <webkit2/webkit2.h>

enum LinuxEnvironmentError {
  LINUX_ENVIRONMENT_CREATION_FAILED,
  LINUX_ENVIRONMENT_CONFIGURATION_CONFLICT,
  LINUX_ENVIRONMENT_ALREADY_INITIALIZED,
};

GQuark linux_environment_error_quark();
const gchar *linux_environment_error_code(const GError *error);

// A single environment is shared by every Flutter engine in this process.
// Both null paths mean reuse the current environment, or the WebKit default.
// An empty path explicitly requests its platform default. Other paths are
// canonicalized to absolute paths without resolving symbolic links.
gboolean ensure_linux_environment(const gchar *user_data_path,
                                  const gchar *cache_path,
                                  gboolean initialize_only, GError **error);

// Borrowed process-lifetime context. First use selects the default environment
// when no explicit configuration has been initialized yet.
WebKitWebContext *get_linux_environment_context(GError **error);

// The returned widget has the usual floating GtkWidget reference.
WebKitWebView *
create_linux_environment_web_view(WebKitUserContentManager *content_manager,
                                  GError **error);

#endif // WEBVIEW_ALL_LINUX_WEBVIEW_ENVIRONMENT_H_
