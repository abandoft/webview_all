#include "webview/download_policy.h"

DownloadPolicy::DownloadPolicy(WebKitWebView *web_view) : web_view_(web_view) {
  signal_id_ =
      g_signal_connect(webkit_web_view_get_context(web_view_),
                       "download-started", G_CALLBACK(OnDownloadStarted), this);
}

DownloadPolicy::~DownloadPolicy() {
  g_signal_handler_disconnect(webkit_web_view_get_context(web_view_),
                              signal_id_);
}

void DownloadPolicy::OnDownloadStarted(WebKitWebContext *context,
                                       WebKitDownload *download,
                                       gpointer user_data) {
  auto *policy = static_cast<DownloadPolicy *>(user_data);
  // A shared context must not let one view cancel another view's downloads.
  if (!policy->enabled_ &&
      webkit_download_get_web_view(download) == policy->web_view_) {
    webkit_download_cancel(download);
  }
}
