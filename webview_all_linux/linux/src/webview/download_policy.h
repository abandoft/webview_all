#ifndef WEBVIEW_ALL_LINUX_DOWNLOAD_POLICY_H_
#define WEBVIEW_ALL_LINUX_DOWNLOAD_POLICY_H_

#include <webkit2/webkit2.h>

// Owned by a single WebView and destroyed before that WebView is released.
class DownloadPolicy {
public:
  explicit DownloadPolicy(WebKitWebView *web_view);
  ~DownloadPolicy();
  DownloadPolicy(const DownloadPolicy &) = delete;
  DownloadPolicy &operator=(const DownloadPolicy &) = delete;

  void SetEnabled(bool enabled) { enabled_ = enabled; }

private:
  static void OnDownloadStarted(WebKitWebContext *context,
                                WebKitDownload *download, gpointer user_data);
  WebKitWebView *web_view_;
  gulong signal_id_;
  bool enabled_ = true;
};

#endif // WEBVIEW_ALL_LINUX_DOWNLOAD_POLICY_H_
