#include "webview/download_policy.h"

#include <glib/gstdio.h>
#include <libsoup/soup.h>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
std::string Text(const gchar *text) { return text == nullptr ? "" : text; }

bool IsAttachment(const gchar *header) {
  if (!header)
    return false;
  while (g_ascii_isspace(*header))
    ++header;
  return g_ascii_strncasecmp(header, "attachment", 10) == 0 &&
         (header[10] == '\0' || header[10] == ';' ||
          g_ascii_isspace(header[10]));
}

std::string SafeFilename(const gchar *name) {
  std::string value = Text(name);
  const size_t slash = value.find_last_of("/\\");
  if (slash != std::string::npos)
    value = value.substr(slash + 1);
  for (char &c : value) {
    if (static_cast<unsigned char>(c) < 32 || c == 127)
      c = '_';
  }
  if (value.empty() || value == "." || value == "..")
    value = "download";
  if (value.size() > 200) {
    size_t end = 200;
    while (end > 0 && (static_cast<unsigned char>(value[end]) & 0xc0) == 0x80)
      --end;
    value.resize(end);
  }
  return value;
}

std::string UniqueName(const std::string &name, unsigned index) {
  if (index == 0)
    return name;
  const size_t dot = name.find_last_of('.');
  const size_t split = dot == 0 || dot == std::string::npos ? name.size() : dot;
  return name.substr(0, split) + " (" + std::to_string(index) + ")" +
         name.substr(split);
}

bool SetErrno(GError **error) {
  g_set_error(error, G_IO_ERROR, g_io_error_from_errno(errno), "%s",
              g_strerror(errno));
  return false;
}

// Same-filesystem publication is an atomic, non-overwriting hard link. Across
// filesystems O_EXCL reserves the destination; cleanup only removes our inode.
bool PublishFile(const std::string &source, const std::string &destination,
                 GCancellable *cancel, GError **error) {
  if (g_cancellable_set_error_if_cancelled(cancel, error))
    return false;
  if (link(source.c_str(), destination.c_str()) == 0)
    return true;
  if (errno != EXDEV && errno != EPERM && errno != EOPNOTSUPP)
    return SetErrno(error);
  const int output =
      open(destination.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
  if (output < 0)
    return SetErrno(error);
  struct stat ours{};
  const bool identified = fstat(output, &ours) == 0;
  const int input = open(source.c_str(), O_RDONLY | O_NOFOLLOW);
  bool success = input >= 0;
  if (!success)
    SetErrno(error);
  char buffer[65536];
  while (success) {
    if (g_cancellable_set_error_if_cancelled(cancel, error)) {
      success = false;
      break;
    }
    const ssize_t count = read(input, buffer, sizeof(buffer));
    if (count == 0)
      break;
    if (count < 0) {
      if (errno == EINTR)
        continue;
      success = SetErrno(error);
      break;
    }
    ssize_t offset = 0;
    while (offset < count) {
      const ssize_t written =
          write(output, buffer + offset, static_cast<size_t>(count - offset));
      if (written < 0 && errno == EINTR)
        continue;
      if (written <= 0) {
        success = SetErrno(error);
        break;
      }
      offset += written;
    }
  }
  if (success && fsync(output) != 0)
    success = SetErrno(error);
  if (input >= 0)
    close(input);
  if (close(output) != 0 && success)
    success = SetErrno(error);
  if (!success && identified) {
    struct stat current{};
    if (lstat(destination.c_str(), &current) == 0 &&
        current.st_dev == ours.st_dev && current.st_ino == ours.st_ino)
      unlink(destination.c_str());
  }
  return success;
}
} // namespace

struct DownloadPolicy::Task {
  DownloadPolicy *owner;
  WebKitDownload *download;
  GBytes *buffered_response = nullptr;
  DownloadEvent event;
  std::string staging_directory;
  std::string staging_file;
  std::string destination;
  std::string default_directory;
  bool default_destination = true;
  bool delegated = false;
  bool decided = false;
  bool finished = false;
  bool failed = false;
  bool publishing = false;
  guint timeout = 0;
  GCancellable *cancel = g_cancellable_new();

  Task(DownloadPolicy *policy, WebKitDownload *value)
      : owner(policy),
        download(value ? WEBKIT_DOWNLOAD(g_object_ref(value)) : nullptr) {}
  ~Task() {
    if (timeout)
      g_source_remove(timeout);
    if (download) {
      g_signal_handlers_disconnect_by_data(download, this);
      g_object_unref(download);
    }
    if (buffered_response)
      g_bytes_unref(buffered_response);
    g_object_unref(cancel);
    if (!staging_file.empty())
      g_unlink(staging_file.c_str());
    if (!staging_directory.empty())
      g_rmdir(staging_directory.c_str());
  }
};

DownloadPolicy::DownloadPolicy(WebKitWebView *web_view, EventCallback callback,
                               std::string default_directory)
    : web_view_(web_view), callback_(std::move(callback)),
      default_directory_(std::move(default_directory)) {
  if (default_directory_.empty()) {
    const gchar *directory = g_get_user_special_dir(G_USER_DIRECTORY_DOWNLOAD);
    default_directory_ = directory ? directory : g_get_home_dir();
  }
  signal_id_ =
      g_signal_connect(webkit_web_view_get_context(web_view_),
                       "download-started", G_CALLBACK(OnDownloadStarted), this);
}

DownloadPolicy::~DownloadPolicy() {
  g_signal_handler_disconnect(webkit_web_view_get_context(web_view_),
                              signal_id_);
  callback_ = {};
  for (auto &entry : tasks_) {
    Task &task = *entry.second;
    task.owner = nullptr;
    if (task.download)
      g_signal_handlers_disconnect_by_data(task.download, &task);
    if (task.timeout) {
      g_source_remove(task.timeout);
      task.timeout = 0;
    }
    g_cancellable_cancel(task.cancel);
    if (task.download && !task.finished)
      webkit_download_cancel(task.download);
  }
  tasks_.clear();
}

void DownloadPolicy::OnDownloadStarted(WebKitWebContext *,
                                       WebKitDownload *download,
                                       gpointer data) {
  auto *policy = static_cast<DownloadPolicy *>(data);
  if (webkit_download_get_web_view(download) != policy->web_view_)
    return;
  auto task = std::make_shared<Task>(policy, download);
  task->event.id = std::to_string(policy->next_id_++);
  task->event.url =
      Text(webkit_uri_request_get_uri(webkit_download_get_request(download)));
  task->delegated = policy->delegate_enabled_;
  task->default_directory = policy->default_directory_;
  task->decided = !task->delegated;
  policy->tasks_.emplace(task->event.id, task);
  g_signal_connect(download, "decide-destination", G_CALLBACK(OnDestination),
                   task.get());
  g_signal_connect(download, "received-data", G_CALLBACK(OnReceived),
                   task.get());
  g_signal_connect(download, "failed", G_CALLBACK(OnFailed), task.get());
  g_signal_connect(download, "finished", G_CALLBACK(OnFinished), task.get());
  if (!policy->enabled_) {
    task->decided = true;
    task->event.status = "cancelled";
    webkit_download_cancel(download);
  }
}

void DownloadPolicy::Emit(Task &task, const std::string &type) {
  if (!callback_ || !task.delegated)
    return;
  task.event.type = type;
  callback_(task.event);
}

bool DownloadPolicy::PrepareStaging(Task &task, GError **error) {
  gchar *directory = g_dir_make_tmp("webview-all-download-XXXXXX", error);
  if (!directory)
    return false;
  task.staging_directory = directory;
  g_free(directory);
  task.staging_file = task.staging_directory + "/payload";
  return true;
}

void DownloadPolicy::RequestDecision(Task &task) {
  if (!task.delegated)
    return;
  task.timeout = g_timeout_add_seconds(
      35,
      +[](gpointer value) -> gboolean {
        auto *task = static_cast<Task *>(value);
        task->timeout = 0;
        task->owner->Resolve(task->event.id, "cancel", "",
                             "Download decision timed out.");
        return G_SOURCE_REMOVE;
      },
      &task);
  Emit(task, "downloadRequest");
}

bool DownloadPolicy::HandleResponseData(GBytes *bytes, SoupMessage *message) {
  SoupMessageHeaders *headers = soup_message_get_response_headers(message);
  const gchar *mime = soup_message_headers_get_content_type(headers, nullptr);
  const gchar *disposition =
      soup_message_headers_get_one(headers, "Content-Disposition");
  if (!IsAttachment(disposition) &&
      !(mime && !webkit_web_view_can_show_mime_type(web_view_, mime)))
    return false;
  auto task = std::make_shared<Task>(this, nullptr);
  task->event.id = std::to_string(next_id_++);
  gchar *url = g_uri_to_string(soup_message_get_uri(message));
  task->event.url = Text(url);
  g_free(url);
  task->event.mime_type = Text(mime);
  task->event.content_disposition = Text(disposition);
  task->event.user_agent = Text(soup_message_headers_get_one(
      soup_message_get_request_headers(message), "User-Agent"));
  GHashTable *parameters = nullptr;
  gchar *disposition_type = nullptr;
  soup_message_headers_get_content_disposition(headers, &disposition_type,
                                               &parameters);
  const gchar *name = parameters
                          ? static_cast<const gchar *>(
                                g_hash_table_lookup(parameters, "filename"))
                          : nullptr;
  gchar *basename =
      g_path_get_basename(g_uri_get_path(soup_message_get_uri(message)));
  gchar *decoded = g_uri_unescape_string(basename, nullptr);
  task->event.suggested_filename =
      SafeFilename(name ? name : (decoded ? decoded : basename));
  g_free(decoded);
  g_free(basename);
  if (parameters)
    g_hash_table_unref(parameters);
  g_free(disposition_type);
  task->event.bytes_received = static_cast<gint64>(g_bytes_get_size(bytes));
  task->event.total_bytes = task->event.bytes_received;
  task->buffered_response = g_bytes_ref(bytes);
  task->delegated = delegate_enabled_;
  task->decided = !task->delegated;
  task->default_directory = default_directory_;
  task->finished = true;
  tasks_.emplace(task->event.id, task);
  if (!enabled_) {
    task->decided = true;
    Result(*task, "cancelled");
    return true;
  }
  GError *error = nullptr;
  if (!PrepareStaging(*task, &error)) {
    Result(*task, "failed", "temporary_file_failed",
           Text(error ? error->message : nullptr));
    g_clear_error(&error);
    return true;
  }
  RequestDecision(*task);
  if (tasks_.find(task->event.id) == tasks_.end())
    return true;
  Emit(*task, "downloadProgress");
  Complete(*task);
  return true;
}

gboolean DownloadPolicy::OnDestination(WebKitDownload *download,
                                       const gchar *suggested, gpointer data) {
  auto *task = static_cast<Task *>(data);
  auto *policy = task->owner;
  task->event.suggested_filename = SafeFilename(suggested);
  WebKitURIResponse *response = webkit_download_get_response(download);
  if (response) {
    task->event.mime_type = Text(webkit_uri_response_get_mime_type(response));
    const guint64 length = webkit_uri_response_get_content_length(response);
    if (length > 0 && length <= G_MAXINT64)
      task->event.total_bytes = static_cast<gint64>(length);
    SoupMessageHeaders *headers =
        webkit_uri_response_get_http_headers(response);
    if (headers)
      task->event.content_disposition =
          Text(soup_message_headers_get_one(headers, "Content-Disposition"));
  }
  SoupMessageHeaders *request_headers = webkit_uri_request_get_http_headers(
      webkit_download_get_request(download));
  if (request_headers)
    task->event.user_agent =
        Text(soup_message_headers_get_one(request_headers, "User-Agent"));
  GError *error = nullptr;
  if (!policy->PrepareStaging(*task, &error)) {
    task->event.status = "failed";
    task->event.error_code = "temporary_file_failed";
    task->event.description = Text(error ? error->message : nullptr);
    g_clear_error(&error);
    task->decided = true;
    webkit_download_cancel(download);
    return TRUE;
  }
  gchar *uri = g_filename_to_uri(task->staging_file.c_str(), nullptr, &error);
  if (!uri) {
    task->event.status = "failed";
    task->event.error_code = "temporary_file_failed";
    task->event.description = Text(error ? error->message : nullptr);
    g_clear_error(&error);
    task->decided = true;
    webkit_download_cancel(download);
    return TRUE;
  }
  webkit_download_set_allow_overwrite(download, FALSE);
  webkit_download_set_destination(download, uri);
  g_free(uri);
  policy->RequestDecision(*task);
  return TRUE;
}

void DownloadPolicy::OnReceived(WebKitDownload *download, guint64,
                                gpointer data) {
  auto *task = static_cast<Task *>(data);
  task->event.bytes_received =
      static_cast<gint64>(webkit_download_get_received_data_length(download));
  task->owner->Emit(*task, "downloadProgress");
}

void DownloadPolicy::OnFailed(WebKitDownload *, GError *error, gpointer data) {
  auto *task = static_cast<Task *>(data);
  task->failed = true;
  if (task->event.status.empty()) {
    task->event.status =
        error && error->domain == WEBKIT_DOWNLOAD_ERROR &&
                error->code == WEBKIT_DOWNLOAD_ERROR_CANCELLED_BY_USER
            ? "cancelled"
            : "failed";
    task->event.error_code =
        error ? std::to_string(error->code) : "download_failed";
    task->event.description = Text(error ? error->message : nullptr);
  }
}

void DownloadPolicy::OnFinished(WebKitDownload *, gpointer data) {
  auto *task = static_cast<Task *>(data);
  task->finished = true;
  task->owner->Complete(*task);
}

bool DownloadPolicy::Resolve(const std::string &id, const std::string &action,
                             const std::string &path,
                             const std::string &error) {
  const auto found = tasks_.find(id);
  if (found == tasks_.end() || found->second->decided)
    return false;
  auto task = found->second;
  task->decided = true;
  if (task->timeout) {
    g_source_remove(task->timeout);
    task->timeout = 0;
  }
  if (!error.empty() ||
      (action != "cancel" && action != "handledExternally" &&
       action != "platformDefault" && action != "saveToFile")) {
    task->event.status = "failed";
    task->event.error_code = "download_decision_failed";
    task->event.description =
        error.empty() ? "Invalid download decision." : error;
  } else if (action == "cancel" || action == "handledExternally") {
    task->event.status = action == "cancel" ? "cancelled" : "handedOff";
  } else if (action == "saveToFile") {
    if (!g_path_is_absolute(path.c_str()) ||
        path.find('\0') != std::string::npos) {
      task->event.status = "failed";
      task->event.error_code = "invalid_destination";
      task->event.description =
          "Download destination must be an absolute file path.";
    } else {
      task->default_destination = false;
      task->destination = path;
    }
  }
  if (!task->event.status.empty() && !task->finished)
    webkit_download_cancel(task->download);
  else
    Complete(*task);
  return true;
}

void DownloadPolicy::Complete(Task &task) {
  if (!task.finished || !task.decided || task.publishing)
    return;
  if (task.failed || !task.event.status.empty()) {
    Result(task, task.event.status.empty() ? "failed" : task.event.status);
    return;
  }
  task.publishing = true;
  GTask *job = g_task_new(nullptr, task.cancel, Published, nullptr);
  g_task_set_task_data(
      job, new std::shared_ptr<Task>(tasks_.at(task.event.id)),
      +[](gpointer value) {
        delete static_cast<std::shared_ptr<Task> *>(value);
      });
  g_task_run_in_thread(job, PublishThread);
  g_object_unref(job);
}

void DownloadPolicy::PublishThread(GTask *job, gpointer, gpointer data,
                                   GCancellable *cancel) {
  auto task = *static_cast<std::shared_ptr<Task> *>(data);
  GError *error = nullptr;
  if (task->buffered_response) {
    GFile *file = g_file_new_for_path(task->staging_file.c_str());
    GFileOutputStream *stream =
        g_file_create(file, G_FILE_CREATE_PRIVATE, cancel, &error);
    g_object_unref(file);
    if (stream) {
      gsize size = 0;
      const void *bytes = g_bytes_get_data(task->buffered_response, &size);
      if (g_output_stream_write_all(G_OUTPUT_STREAM(stream), bytes, size,
                                    nullptr, cancel, &error))
        g_output_stream_close(G_OUTPUT_STREAM(stream), cancel, &error);
      g_object_unref(stream);
    }
    if (error) {
      g_task_return_error(job, error);
      return;
    }
  }
  std::string target = task->destination;
  if (task->default_destination) {
    const std::string &directory = task->default_directory;
    if (g_mkdir_with_parents(directory.c_str(), 0700) != 0) {
      SetErrno(&error);
      g_task_return_error(job, error);
      return;
    }
    for (unsigned index = 0; index < 10000; ++index) {
      target =
          directory + "/" + UniqueName(task->event.suggested_filename, index);
      if (PublishFile(task->staging_file, target, cancel, &error))
        break;
      if (!g_error_matches(error, G_IO_ERROR, G_IO_ERROR_EXISTS)) {
        g_task_return_error(job, error);
        return;
      }
      g_clear_error(&error);
      if (index == 9999) {
        g_task_return_new_error(job, G_IO_ERROR, G_IO_ERROR_EXISTS,
                                "No unused download filename is available.");
        return;
      }
    }
  } else if (!PublishFile(task->staging_file, target, cancel, &error)) {
    g_task_return_error(job, error);
    return;
  }
  task->event.path = target;
  g_task_return_boolean(job, TRUE);
}

void DownloadPolicy::Published(GObject *, GAsyncResult *result, gpointer) {
  GTask *job = G_TASK(result);
  auto task = *static_cast<std::shared_ptr<Task> *>(g_task_get_task_data(job));
  GError *error = nullptr;
  const bool success = g_task_propagate_boolean(job, &error);
  if (task->owner) {
    if (success)
      task->owner->Result(*task, "completed");
    else
      task->owner->Result(*task, "failed",
                          error ? std::to_string(error->code) : "save_failed",
                          Text(error ? error->message : nullptr));
  }
  g_clear_error(&error);
}

void DownloadPolicy::Result(Task &task, const std::string &status,
                            const std::string &code,
                            const std::string &description) {
  task.event.status = status;
  if (!code.empty())
    task.event.error_code = code;
  if (!description.empty())
    task.event.description = description;
  Emit(task, "downloadResult");
  tasks_.erase(task.event.id);
}

bool DownloadPolicy::HandleResponsePolicy(WebKitPolicyDecision *decision) {
  auto *response_decision = WEBKIT_RESPONSE_POLICY_DECISION(decision);
  WebKitURIResponse *response =
      webkit_response_policy_decision_get_response(response_decision);
  SoupMessageHeaders *headers = webkit_uri_response_get_http_headers(response);
  const gchar *header =
      headers ? soup_message_headers_get_one(headers, "Content-Disposition")
              : nullptr;
  const bool attachment = IsAttachment(header);
  if (!attachment &&
      webkit_response_policy_decision_is_mime_type_supported(response_decision))
    return false;
  const gint64 now = g_get_monotonic_time();
  for (auto entry = converted_navigations_.begin();
       entry != converted_navigations_.end();) {
    if (entry->second < now)
      entry = converted_navigations_.erase(entry);
    else
      ++entry;
  }
  converted_navigations_[Text(webkit_uri_response_get_uri(response))] =
      now + 3 * G_USEC_PER_SEC;
  webkit_policy_decision_download(decision);
  return true;
}

bool DownloadPolicy::ShouldIgnoreLoadFailure(GError *error, const gchar *uri) {
  if (!error || error->domain != WEBKIT_POLICY_ERROR ||
      error->code !=
          WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE)
    return false;
  const auto found = converted_navigations_.find(Text(uri));
  if (found == converted_navigations_.end())
    return false;
  const bool recent = found->second >= g_get_monotonic_time();
  converted_navigations_.erase(found);
  return recent;
}
