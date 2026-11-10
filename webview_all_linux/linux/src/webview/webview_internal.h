#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_INTERNAL_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_INTERNAL_H_

#include "plugin/webview_all_linux_plugin_private.h"

void initialize_browser_operations(LinuxWebView *view);
void reset_browser_find(LinuxWebView *view);
void cancel_browser_file_selections(LinuxWebView *view);
void dispose_browser_operations(LinuxWebView *view);
bool browser_denies_popups(LinuxWebView *view);
bool browser_delegates_windows(LinuxWebView *view);
WebKitWebView *create_browser_window(LinuxWebView *view,
                                    WebKitNavigationAction *action);
bool defer_browser_window_navigation(LinuxWebView *view,
                                      WebKitPolicyDecision *decision,
                                      WebKitPolicyDecisionType type);
void resume_browser_window_navigation(LinuxWebView *view,
                                       WebKitPolicyDecision *decision,
                                       WebKitPolicyDecisionType type);
void cancel_browser_windows(LinuxWebView *view);
bool handle_browser_method(LinuxWebView *view, FlMethodCall *call);
bool handle_network_method(LinuxWebView *view, FlMethodCall *call);
void dispose_network_operations(LinuxWebView *view);
bool handle_scheme_method(LinuxWebView *view, FlMethodCall *call);
void dispose_scheme_operations(LinuxWebView *view);
bool handle_browser_root_method(WebviewAllLinuxPlugin *plugin, FlMethodCall *call);
void dispose_browser_navigation_states(WebviewAllLinuxPlugin *plugin);
void cancel_linux_load_request(LinuxWebView *view);
void cancel_pending_navigation_requests(LinuxWebView *view);
void resolve_all_pending_requests(LinuxWebView *view);

void send_event(LinuxWebView *webview, FlValue *event);
void update_history(LinuxWebView *webview);
void emit_url_change(LinuxWebView *webview);
void emit_title_change(LinuxWebView *webview);
void emit_load_error(LinuxWebView *webview, GError *error,
                     const gchar *failing_url);
void use_navigation_decision(LinuxWebView *webview,
                             WebKitPolicyDecision *decision);
void evaluate_javascript(WebKitWebView *web_view, const gchar *script,
                         FlMethodCall *method_call,
                         const gchar *world_name = nullptr);
gchar *build_scrollbar_style_script(LinuxWebView *webview);
gchar *build_overscroll_style_script(LinuxWebView *webview);
void rebuild_user_scripts(LinuxWebView *webview);
void register_message_metadata_handler(LinuxWebView *webview);
void unregister_message_metadata_handler(LinuxWebView *webview);
void console_message_received_cb(WebKitUserContentManager *manager,
                                 WebKitJavascriptResult *result,
                                 gpointer user_data);
void scroll_message_received_cb(WebKitUserContentManager *manager,
                                WebKitJavascriptResult *result,
                                gpointer user_data);
void async_javascript_message_received_cb(WebKitUserContentManager *manager,
                                          WebKitJavascriptResult *result,
                                          gpointer user_data);
void javascript_channel_message_received_cb(WebKitUserContentManager *manager,
                                            WebKitJavascriptResult *result,
                                            gpointer user_data);
void destroy_js_channel_handler_data(gpointer data, GClosure *closure);
void instance_method_call_cb(FlMethodChannel *channel,
                             FlMethodCall *method_call, gpointer user_data);

#endif // WEBVIEW_ALL_LINUX_WEBVIEW_INTERNAL_H_
