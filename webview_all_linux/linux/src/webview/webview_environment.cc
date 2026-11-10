#include "webview/webview_environment.h"

#include <glib/gstdio.h>

#include <cerrno>
#include <string>
#include <unordered_map>
#include <memory>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <filesystem>
#include <unordered_set>

namespace {

struct NamedContext {
  GWeakRef value;
  int lock;
  NamedContext(WebKitWebContext* context, int descriptor) : lock(descriptor) { g_weak_ref_init(&value, context); }
  ~NamedContext() { g_weak_ref_clear(&value); if (lock >= 0) close(lock); }
};
std::unordered_map<std::string, std::unique_ptr<NamedContext>> profiles;
std::unordered_set<std::string> deleting_profiles;
bool valid_profile(const std::string& name) {
  return g_regex_match_simple("^[A-Za-z0-9_-]{1,64}$", name.c_str(), G_REGEX_DEFAULT, G_REGEX_MATCH_DEFAULT);
}
void prune_profiles() {
  for (auto it = profiles.begin(); it != profiles.end();) {
    auto* context = g_weak_ref_get(&it->second->value);
    if (!context) it = profiles.erase(it);
    else { g_object_unref(context); ++it; }
  }
}
bool plain_directory(const std::string& path) {
  struct stat info;
  return lstat(path.c_str(), &info) == 0 && S_ISDIR(info.st_mode);
}
bool owned_profile(const std::string& root, const std::string& name) {
  if (!plain_directory(root) || !plain_directory(root + "/" + name)) return false;
  auto marker = root + "/" + name + "/.webview_all_profile";
  struct stat info;
  if (lstat(marker.c_str(), &info) || !S_ISREG(info.st_mode) || info.st_size > 64) return false;
  gchar* value = nullptr;
  if (!g_file_get_contents(marker.c_str(), &value, nullptr, nullptr)) return false;
  const bool owned = name == value; g_free(value); return owned;
}
int profile_lock(const std::string& root, const std::string& name) {
  if (!plain_directory(root)) return -1;
  auto locks = root + "/.locks";
  if (g_mkdir_with_parents(locks.c_str(), 0700) || !plain_directory(locks)) return -1;
  auto path = locks + "/" + name;
  int descriptor = open(path.c_str(), O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (descriptor < 0) return -1;
  if (flock(descriptor, LOCK_EX | LOCK_NB)) { close(descriptor); return -1; }
  return descriptor;
}

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
                                  GError **error, gboolean incognito,
                                  const gchar* profile_name) {
  if (profile_name) {
    if (incognito || !g_regex_match_simple("^[A-Za-z0-9_-]{1,64}$", profile_name, G_REGEX_DEFAULT, G_REGEX_MATCH_DEFAULT)) {
      g_set_error_literal(error, linux_environment_error_quark(), LINUX_ENVIRONMENT_CREATION_FAILED, "Invalid named profile or private-mode combination."); return nullptr;
    }
    if (!get_linux_environment_context(error)) return nullptr;
    prune_profiles();
    if (deleting_profiles.count(profile_name)) {
      g_set_error_literal(error, linux_environment_error_quark(), LINUX_ENVIRONMENT_CREATION_FAILED, "The named profile is being deleted."); return nullptr;
    }
    auto found = profiles.find(profile_name);
    g_autoptr(WebKitWebContext) selected = found == profiles.end() ? nullptr :
        WEBKIT_WEB_CONTEXT(g_weak_ref_get(&found->second->value));
    if (!selected) {
      if (profiles.size() >= 32) {
        g_set_error_literal(error, linux_environment_error_quark(), LINUX_ENVIRONMENT_CREATION_FAILED, "The process named-profile limit was reached."); return nullptr;
      }
      auto data = environment().user_data_path + "/webview_all_profiles/" + profile_name;
      auto cache = environment().cache_path + "/webview_all_profiles/" + profile_name;
      auto data_root = environment().user_data_path + "/webview_all_profiles";
      auto cache_root = environment().cache_path + "/webview_all_profiles";
      if (!prepare_directory(data_root, error) || !plain_directory(data_root) ||
          !prepare_directory(cache_root, error) || !plain_directory(cache_root)) {
        if (error && !*error) g_set_error_literal(error, linux_environment_error_quark(), LINUX_ENVIRONMENT_CREATION_FAILED, "Named profile roots cannot be symbolic links.");
        return nullptr;
      }
      int descriptor = profile_lock(data_root, profile_name);
      if (descriptor < 0) {
        g_set_error_literal(error, linux_environment_error_quark(), LINUX_ENVIRONMENT_CREATION_FAILED, "This named profile is in use by another process or its lock is inaccessible."); return nullptr;
      }
      if (!prepare_directory(data, error) || !plain_directory(data) || !prepare_directory(cache, error) || !plain_directory(cache)) {
        close(descriptor);
        if (error && !*error) g_set_error_literal(error, linux_environment_error_quark(), LINUX_ENVIRONMENT_CREATION_FAILED, "Named profile directories cannot be symbolic links.");
        return nullptr;
      }
      auto marker = data + "/.webview_all_profile";
      if (!g_file_set_contents(marker.c_str(), profile_name, -1, error)) { close(descriptor); return nullptr; }
      if (cache != data && !g_file_set_contents((cache + "/.webview_all_profile").c_str(), profile_name, -1, error)) { close(descriptor); return nullptr; }
      auto* manager = webkit_website_data_manager_new("base-data-directory", data.c_str(), "base-cache-directory", cache.c_str(), nullptr);
      selected = webkit_web_context_new_with_website_data_manager(manager);
      g_object_unref(manager);
      auto cookie_path = data + "/cookies.sqlite";
      webkit_cookie_manager_set_persistent_storage(webkit_web_context_get_cookie_manager(selected),
          cookie_path.c_str(), WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
      profiles[profile_name] = std::make_unique<NamedContext>(selected, descriptor);
    }
    return WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", selected, "user-content-manager", content_manager, nullptr));
  }
  g_autoptr(WebKitWebContext) ephemeral_context =
      incognito ? webkit_web_context_new_ephemeral() : nullptr;
  WebKitWebContext *context =
      incognito ? ephemeral_context : get_linux_environment_context(error);
  if (!context)
    return nullptr;
  return WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context",
                                      context, "user-content-manager",
                                      content_manager, nullptr));
}

namespace {
std::string profile_root(bool cache) {
  auto& state = environment();
  const auto base = cache ? state.cache_path : state.user_data_path;
  return (base.empty() ? default_path(cache ? g_get_user_cache_dir() : g_get_user_data_dir()) : base) + "/webview_all_profiles";
}
void remove_owned_profile_directory(const std::string& root, const std::string& name,
                                    std::error_code& error) {
  const std::filesystem::path directory = root + "/" + name;
  const auto status = std::filesystem::symlink_status(directory, error);
  if (error == std::errc::no_such_file_or_directory) { error.clear(); return; }
  if (error) return;
  if (!std::filesystem::exists(status)) return;
  if (!owned_profile(root, name)) { error = std::make_error_code(std::errc::permission_denied); return; }
  const auto marker = directory / ".webview_all_profile";
  // Preserve ownership until every child has gone. An I/O/permission failure
  // must leave the profile listed and allow a later explicit retry.
  std::filesystem::directory_iterator item(directory, error), end;
  for (; !error && item != end; item.increment(error)) {
    const auto child = item->path();
    if (child == marker) continue;
    std::filesystem::remove_all(child, error);
    if (error) return;
  }
  if (error) return;
  std::filesystem::remove(marker, error);
  if (error) return;
  std::filesystem::remove(directory, error);
  if (error) g_file_set_contents(marker.c_str(), name.c_str(), -1, nullptr);
}
struct ProfileDeleteTask {
  std::string name, data_root, cache_root;
  int lock;
  std::function<void(LinuxProfileDeletion)> callback;
  LinuxProfileDeletion outcome{"failed", "Profile deletion failed."};
  ~ProfileDeleteTask() { if (lock >= 0) close(lock); }
};
}
std::vector<LinuxProfileInfo> list_linux_profiles() {
  std::vector<LinuxProfileInfo> result;
  auto root = profile_root(false);
  if (!plain_directory(root)) return result;
  g_autoptr(GDir) directory = g_dir_open(root.c_str(), 0, nullptr);
  if (!directory) return result;
  while (auto* name = g_dir_read_name(directory)) {
    if (valid_profile(name) && owned_profile(root, name)) result.push_back({name, deleting_profiles.count(name) != 0});
  }
  return result;
}
void delete_linux_profile(const std::string& name,
    std::function<void(LinuxProfileDeletion)> callback) {
  if (!valid_profile(name)) { callback({"failed", "Invalid named profile; no files were removed."}); return; }
  if (deleting_profiles.count(name)) { callback({"pending", "Deletion is already running."}); return; }
  prune_profiles();
  if (profiles.count(name)) { callback({"busy", "Close this profile's views and dispose saved navigation states before deletion."}); return; }
  auto data = profile_root(false), cache = profile_root(true);
  if (!owned_profile(data, name)) { callback({"notFound", "No plugin-owned named profile was found."}); return; }
  int descriptor = profile_lock(data, name);
  if (descriptor < 0) { callback({"busy", "Another process is using this profile, or its lock is inaccessible."}); return; }
  std::error_code cache_error;
  const auto cache_status = std::filesystem::symlink_status(cache + "/" + name, cache_error);
  if (cache_error == std::errc::no_such_file_or_directory) cache_error.clear();
  const bool cache_exists = std::filesystem::exists(cache_status);
  if (cache_error || (cache != data && cache_exists && !owned_profile(cache, name))) {
    close(descriptor); callback({"failed", "The cache ownership marker is unavailable; no files were removed."}); return;
  }
  deleting_profiles.insert(name);
  auto* work = new ProfileDeleteTask{name, data, cache, descriptor, std::move(callback)};
  GTask* task = g_task_new(nullptr, nullptr, [](GObject*, GAsyncResult* result, gpointer) {
    auto* task = G_TASK(result);
    auto* work = static_cast<ProfileDeleteTask*>(g_task_get_task_data(task));
    deleting_profiles.erase(work->name);
    // Release the advisory lock before notifying Dart, which may immediately reopen.
    close(work->lock); work->lock = -1;
    work->callback(work->outcome);
  }, nullptr);
  g_task_set_task_data(task, work, [](gpointer value) { delete static_cast<ProfileDeleteTask*>(value); });
  g_task_run_in_thread(task, [](GTask* task, gpointer, gpointer data, GCancellable*) {
    auto* work = static_cast<ProfileDeleteTask*>(data);
    std::error_code error;
    // remove_all removes child symlinks themselves; it does not follow them.
    // Keep the data ownership marker if cache removal fails so a retry is possible.
    if (work->cache_root != work->data_root)
      remove_owned_profile_directory(work->cache_root, work->name, error);
    if (!error) remove_owned_profile_directory(work->data_root, work->name, error);
    work->outcome = error ? LinuxProfileDeletion{"failed", error.message()} : LinuxProfileDeletion{"deleted", "The named profile and its cache were removed."};
    g_task_return_boolean(task, !error);
  });
  g_object_unref(task);
}
