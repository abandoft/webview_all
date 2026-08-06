#ifndef WEBVIEW_ALL_LINUX_PLUGIN_PRIVATE_H_
#define WEBVIEW_ALL_LINUX_PLUGIN_PRIVATE_H_

#include "webview_all_linux/webview_all_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

struct _WebviewAllLinuxPlugin {
  GObject parent_instance;

  FlPluginRegistrar *registrar;
  FlMethodChannel *root_channel;
  GtkOverlay *overlay;
  GHashTable *webviews;
  gint next_webview_id;
};

typedef struct {
  WebviewAllLinuxPlugin *plugin;
  gint id;
  WebKitUserContentManager *content_manager;
  WebKitWebView *web_view;
  FlMethodChannel *method_channel;
  FlEventChannel *event_channel;
  gboolean event_listening;
  GHashTable *pending_nav_decisions;
  GHashTable *pending_auth_requests;
  GHashTable *pending_permission_requests;
  GHashTable *pending_script_dialogs;
  GHashTable *pending_tls_errors;
  GHashTable *pending_request_timeouts;
  GHashTable *js_channel_signal_ids;
  GHashTable *js_channels;
  gint next_request_id;
  gboolean console_enabled;
  gboolean scroll_enabled;
  gboolean java_script_alert_dialog_enabled;
  gboolean java_script_confirm_dialog_enabled;
  gboolean java_script_prompt_dialog_enabled;
  gboolean vertical_scrollbar_enabled;
  gboolean horizontal_scrollbar_enabled;
  gboolean zoom_enabled;
  gint media_playback_requires_user_gesture;
  const gchar *over_scroll_behavior;
  gint frame_x;
  gint frame_y;
  gint frame_width;
  gint frame_height;
  gboolean visible;
  double last_scroll_x;
  double last_scroll_y;
} LinuxWebView;

typedef struct {
  LinuxWebView *webview;
  gchar *name;
} JavaScriptChannelHandlerData;

typedef struct {
  GTlsCertificate *certificate;
  gchar *host;
  gchar *uri;
} PendingTlsError;

typedef struct {
  WebKitPolicyDecision *decision;
  gchar *uri;
  gboolean open_in_place;
} PendingNavigationDecision;

LinuxWebView *create_linux_webview(WebviewAllLinuxPlugin *self);
void destroy_linux_webview(gpointer data);
void root_method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                         gpointer user_data);
GtkOverlay *ensure_overlay(WebviewAllLinuxPlugin *self);
void update_flutter_view_input_region(WebviewAllLinuxPlugin *self);
void cancel_pending_request_timeout(LinuxWebView *webview, gint request_id);

#endif // WEBVIEW_ALL_LINUX_PLUGIN_PRIVATE_H_
