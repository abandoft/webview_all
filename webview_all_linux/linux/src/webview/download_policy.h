#ifndef WEBVIEW_ALL_LINUX_DOWNLOAD_POLICY_H_
#define WEBVIEW_ALL_LINUX_DOWNLOAD_POLICY_H_

#include <libsoup/soup.h>
#include <webkit2/webkit2.h>

#include <functional>
#include <map>
#include <memory>
#include <string>

struct DownloadEvent {
  std::string type;
  std::string id;
  std::string url;
  std::string suggested_filename;
  std::string mime_type;
  std::string content_disposition;
  std::string user_agent;
  std::string status;
  std::string path;
  std::string error_code;
  std::string description;
  gint64 bytes_received = 0;
  gint64 total_bytes = -1;
};

// Owned by one WebView. Engines only write private staging files; existing
// application/user files are never exposed to WebKit's failure cleanup.
class DownloadPolicy {
public:
  using EventCallback = std::function<void(const DownloadEvent &)>;
  explicit DownloadPolicy(WebKitWebView *web_view, EventCallback callback = {},
                          std::string default_directory = {});
  ~DownloadPolicy();
  DownloadPolicy(const DownloadPolicy &) = delete;
  DownloadPolicy &operator=(const DownloadPolicy &) = delete;

  void SetEnabled(bool enabled) { enabled_ = enabled; }
  void SetDelegateEnabled(bool enabled) { delegate_enabled_ = enabled; }
  bool Resolve(const std::string &id, const std::string &action,
               const std::string &path, const std::string &error = {});
  bool HandleResponsePolicy(WebKitPolicyDecision *decision);
  // Custom-method/header requests use Soup. Consume their original response
  // body without replaying a POST (or losing authenticated request state).
  bool HandleResponseData(GBytes *bytes, SoupMessage *message);
  bool ShouldIgnoreLoadFailure(GError *error, const gchar *uri);

private:
  struct Task;
  static void OnDownloadStarted(WebKitWebContext *, WebKitDownload *, gpointer);
  static gboolean OnDestination(WebKitDownload *, const gchar *, gpointer);
  static void OnReceived(WebKitDownload *, guint64, gpointer);
  static void OnFailed(WebKitDownload *, GError *, gpointer);
  static void OnFinished(WebKitDownload *, gpointer);
  static void PublishThread(GTask *, gpointer, gpointer, GCancellable *);
  static void Published(GObject *, GAsyncResult *, gpointer);
  void Emit(Task &task, const std::string &type);
  bool PrepareStaging(Task &task, GError **error);
  void RequestDecision(Task &task);
  void Complete(Task &task);
  void Result(Task &task, const std::string &status,
              const std::string &code = {},
              const std::string &description = {});

  WebKitWebView *web_view_;
  gulong signal_id_;
  bool enabled_ = true;
  bool delegate_enabled_ = false;
  guint64 next_id_ = 1;
  EventCallback callback_;
  std::string default_directory_;
  std::map<std::string, std::shared_ptr<Task>> tasks_;
  std::map<std::string, gint64> converted_navigations_;
};

#endif // WEBVIEW_ALL_LINUX_DOWNLOAD_POLICY_H_
