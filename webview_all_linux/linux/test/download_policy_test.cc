#include "webview/download_policy.h"

#include <glib/gstdio.h>
#include <libsoup/soup.h>

#include <functional>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace {
void Wait(const std::function<bool()> &condition) {
  if (condition())
    return;
  struct State {
    GMainLoop *loop;
    const std::function<bool()> *condition;
    bool timeout = false;
  } state{g_main_loop_new(nullptr, FALSE), &condition};
  guint poll = g_timeout_add(
      10,
      +[](gpointer value) -> gboolean {
        auto *state = static_cast<State *>(value);
        if ((*state->condition)())
          g_main_loop_quit(state->loop);
        return G_SOURCE_CONTINUE;
      },
      &state);
  guint timeout = g_timeout_add_seconds(
      15,
      +[](gpointer value) -> gboolean {
        auto *state = static_cast<State *>(value);
        state->timeout = true;
        g_main_loop_quit(state->loop);
        return G_SOURCE_REMOVE;
      },
      &state);
  g_main_loop_run(state.loop);
  g_source_remove(poll);
  if (!state.timeout)
    g_source_remove(timeout);
  g_main_loop_unref(state.loop);
  g_assert_false(state.timeout);
}

std::string Read(const std::string &path) {
  gchar *contents = nullptr;
  gsize length = 0;
  g_assert_true(g_file_get_contents(path.c_str(), &contents, &length, nullptr));
  std::string text(contents, length);
  g_free(contents);
  return text;
}

void AssertContents(const std::string &path, const char *expected) {
  const std::string actual = Read(path);
  g_assert_cmpstr(actual.c_str(), ==, expected);
}

class Fixture {
public:
  Fixture() {
    GError *error = nullptr;
    gchar *directory =
        g_dir_make_tmp("webview-all-download-test-XXXXXX", &error);
    g_assert_no_error(error);
    directory_ = directory;
    g_free(directory);
    server_ = soup_server_new(nullptr, nullptr);
    soup_server_add_handler(
        server_, nullptr,
        +[](SoupServer *, SoupServerMessage *message, const char *,
            GHashTable *, gpointer data) {
          auto *fixture = static_cast<Fixture *>(data);
          soup_server_message_set_status(message, SOUP_STATUS_OK, nullptr);
          if (fixture->attachment_)
            soup_message_headers_append(
                soup_server_message_get_response_headers(message),
                "Content-Disposition", "attachment; filename=test.txt");
          soup_server_message_set_response(
              message, fixture->mime_, SOUP_MEMORY_STATIC, "download test", 13);
        },
        this, nullptr);
    soup_server_listen_local(server_, 0, SOUP_SERVER_LISTEN_IPV4_ONLY, &error);
    g_assert_no_error(error);
    GSList *uris = soup_server_get_uris(server_);
    gchar *uri = g_uri_to_string(static_cast<GUri *>(uris->data));
    url_ = uri;
    g_free(uri);
    g_slist_free_full(uris, reinterpret_cast<GDestroyNotify>(g_uri_unref));
    context_ = webkit_web_context_new_ephemeral();
    first_ = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context_));
    second_ = WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context_));
    g_object_ref_sink(first_);
    g_object_ref_sink(second_);
    first_policy_ = std::make_unique<DownloadPolicy>(
        first_,
        [this](const DownloadEvent &event) {
          Handle(first_policy_.get(), event);
        },
        directory_);
    second_policy_ = std::make_unique<DownloadPolicy>(
        second_,
        [this](const DownloadEvent &event) {
          Handle(second_policy_.get(), event);
        },
        directory_);
    first_policy_->SetDelegateEnabled(true);
    second_policy_->SetDelegateEnabled(true);
  }

  ~Fixture() {
    if (first_policy_)
      g_signal_handlers_disconnect_by_data(first_, first_policy_.get());
    if (second_policy_)
      g_signal_handlers_disconnect_by_data(second_, second_policy_.get());
    first_policy_.reset();
    second_policy_.reset();
    while (g_main_context_pending(nullptr))
      g_main_context_iteration(nullptr, FALSE);
    gtk_widget_destroy(GTK_WIDGET(first_));
    gtk_widget_destroy(GTK_WIDGET(second_));
    g_object_unref(first_);
    g_object_unref(second_);
    g_object_unref(context_);
    soup_server_disconnect(server_);
    g_object_unref(server_);
    GDir *directory = g_dir_open(directory_.c_str(), 0, nullptr);
    const gchar *name;
    while ((name = g_dir_read_name(directory)))
      g_assert_cmpint(g_remove((directory_ + "/" + name).c_str()), ==, 0);
    g_dir_close(directory);
    g_assert_cmpint(g_rmdir(directory_.c_str()), ==, 0);
  }

  void Handle(DownloadPolicy *policy, const DownloadEvent &event) {
    if (event.type == "downloadRequest") {
      ++requests_;
      if (defer_) {
        pending_.emplace_back(policy, event.id);
      } else {
        g_assert_true(policy->Resolve(event.id, action_, target_));
      }
    } else if (event.type == "downloadResult") {
      results_.push_back(event);
    }
  }

  void Start(WebKitWebView *view = nullptr) {
    WebKitDownload *download =
        webkit_web_view_download_uri(view ? view : first_, url_.c_str());
    g_object_unref(download);
  }

  void Await(size_t count) {
    Wait([this, count] { return results_.size() == count; });
  }

  std::string directory_;
  std::string url_;
  WebKitWebView *first_;
  WebKitWebView *second_;
  std::unique_ptr<DownloadPolicy> first_policy_;
  std::unique_ptr<DownloadPolicy> second_policy_;
  std::vector<DownloadEvent> results_;
  std::vector<std::pair<DownloadPolicy *, std::string>> pending_;
  std::string action_ = "platformDefault";
  std::string target_;
  bool defer_ = false;
  unsigned requests_ = 0;
  bool attachment_ = true;
  const char *mime_ = "text/plain";

private:
  WebKitWebContext *context_;
  SoupServer *server_;
};

void TestDefaultExistingAndConcurrentNames() {
  Fixture fixture;
  const std::string existing = fixture.directory_ + "/test.txt";
  g_assert_true(
      g_file_set_contents(existing.c_str(), "original user file", -1, nullptr));
  fixture.Start();
  fixture.Start(fixture.second_);
  fixture.Await(2);
  AssertContents(existing, "original user file");
  std::set<std::string> paths;
  for (const auto &result : fixture.results_) {
    g_assert_cmpstr(result.status.c_str(), ==, "completed");
    AssertContents(result.path, "download test");
    g_assert_true(paths.insert(result.path).second);
    g_assert_cmpstr(result.path.c_str(), !=, existing.c_str());
  }
}

void TestExplicitTargetNeverOverwrites() {
  Fixture fixture;
  fixture.action_ = "saveToFile";
  fixture.target_ = fixture.directory_ + "/selected.txt";
  g_assert_true(
      g_file_set_contents(fixture.target_.c_str(), "original", -1, nullptr));
  fixture.Start();
  fixture.Await(1);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "failed");
  AssertContents(fixture.target_, "original");
  g_assert_cmpint(g_remove(fixture.target_.c_str()), ==, 0);
  fixture.Start();
  fixture.Await(2);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "completed");
  g_assert_cmpstr(fixture.results_.back().path.c_str(), ==,
                  fixture.target_.c_str());
  AssertContents(fixture.target_, "download test");
}

void TestDecisionsAndLateDecision() {
  Fixture fixture;
  fixture.action_ = "cancel";
  fixture.Start();
  fixture.Await(1);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "cancelled");
  fixture.action_ = "handledExternally";
  fixture.Start();
  fixture.Await(2);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "handedOff");
  fixture.defer_ = true;
  fixture.Start();
  Wait([&] { return fixture.pending_.size() == 1; });
  // The original response may already have arrived in the private staging file;
  // selecting a destination later must not reissue the HTTP request.
  const auto pending = fixture.pending_.front();
  g_assert_true(pending.first->Resolve(pending.second, "platformDefault", ""));
  g_assert_false(pending.first->Resolve(pending.second, "platformDefault", ""));
  fixture.Await(3);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "completed");
  AssertContents(fixture.results_.back().path, "download test");
  g_assert_cmpuint(fixture.requests_, ==, 3);
}

void TestDisabledScopeAndDisposal() {
  Fixture fixture;
  fixture.first_policy_->SetEnabled(false);
  fixture.Start();
  fixture.Start(fixture.second_);
  fixture.Await(2);
  g_assert_cmpuint(fixture.requests_, ==, 1);
  bool cancelled = false, completed = false;
  for (const auto &result : fixture.results_) {
    cancelled |= result.status == "cancelled";
    completed |= result.status == "completed";
  }
  g_assert_true(cancelled);
  g_assert_true(completed);
  fixture.first_policy_->SetEnabled(true);
  fixture.defer_ = true;
  fixture.Start();
  Wait([&] { return fixture.pending_.size() == 1; });
  fixture.first_policy_.reset();
  while (g_main_context_pending(nullptr))
    g_main_context_iteration(nullptr, FALSE);
}

void TestDefaultWithoutDelegate() {
  Fixture fixture;
  fixture.first_policy_->SetDelegateEnabled(false);
  fixture.Start();
  const std::string path = fixture.directory_ + "/test.txt";
  Wait([&] { return g_file_test(path.c_str(), G_FILE_TEST_EXISTS); });
  AssertContents(path, "download test");
  g_assert_cmpuint(fixture.requests_, ==, 0);
  g_assert_true(fixture.results_.empty());
}

void TestInvalidTargetAndCallbackError() {
  Fixture fixture;
  fixture.action_ = "saveToFile";
  fixture.target_ = "relative.txt";
  fixture.Start();
  fixture.Await(1);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "failed");
  g_assert_cmpstr(fixture.results_.back().error_code.c_str(), ==,
                  "invalid_destination");
  fixture.defer_ = true;
  fixture.Start();
  Wait([&] { return fixture.pending_.size() == 1; });
  const auto pending = fixture.pending_.front();
  g_assert_true(pending.first->Resolve(pending.second, "cancel", "",
                                       "Application handler failed"));
  fixture.Await(2);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "failed");
  g_assert_cmpstr(fixture.results_.back().description.c_str(), ==,
                  "Application handler failed");
}

void TestNavigationErrorCorrelation() {
  Fixture fixture;
  GError *error = g_error_new_literal(
      WEBKIT_POLICY_ERROR,
      WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE,
      "Frame load interrupted");
  g_assert_false(fixture.first_policy_->ShouldIgnoreLoadFailure(
      error, fixture.url_.c_str()));
  g_signal_connect(
      fixture.first_, "decide-policy",
      G_CALLBACK(+[](WebKitWebView *, WebKitPolicyDecision *decision,
                     WebKitPolicyDecisionType type, gpointer data) -> gboolean {
        return type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE &&
               static_cast<DownloadPolicy *>(data)->HandleResponsePolicy(
                   decision);
      }),
      fixture.first_policy_.get());
  bool ignored = false;
  struct ErrorState {
    DownloadPolicy *policy;
    bool *ignored;
  } state{fixture.first_policy_.get(), &ignored};
  g_signal_connect(
      fixture.first_, "load-failed",
      G_CALLBACK(+[](WebKitWebView *, WebKitLoadEvent, const gchar *uri,
                     GError *error, gpointer value) -> gboolean {
        auto *state = static_cast<ErrorState *>(value);
        *state->ignored = state->policy->ShouldIgnoreLoadFailure(error, uri);
        return FALSE;
      }),
      &state);
  webkit_web_view_load_uri(fixture.first_, fixture.url_.c_str());
  fixture.Await(1);
  g_assert_true(ignored);
  g_assert_false(fixture.first_policy_->ShouldIgnoreLoadFailure(
      error, fixture.url_.c_str()));
  // WebKit already downloads unsupported MIME types without a delegate. Make
  // that conversion explicit as well, so only its policy error is suppressed.
  fixture.first_policy_->SetDelegateEnabled(false);
  fixture.attachment_ = false;
  fixture.mime_ = "application/octet-stream";
  ignored = false;
  webkit_web_view_load_uri(fixture.first_, fixture.url_.c_str());
  Wait([&] { return ignored; });
  Wait([&] {
    GDir *directory = g_dir_open(fixture.directory_.c_str(), 0, nullptr);
    unsigned count = 0;
    while (g_dir_read_name(directory))
      ++count;
    g_dir_close(directory);
    return count == 2;
  });
  g_assert_cmpuint(fixture.requests_, ==, 1);
  g_signal_handlers_disconnect_by_data(fixture.first_, &state);
  g_error_free(error);
}

void TestOriginalCustomResponse() {
  Fixture fixture;
  SoupMessage *message = soup_message_new("POST", fixture.url_.c_str());
  SoupMessageHeaders *headers = soup_message_get_response_headers(message);
  soup_message_headers_append(headers, "Content-Disposition",
                              "attachment; filename=original.txt");
  soup_message_headers_append(headers, "Content-Type", "text/plain");
  GBytes *body = g_bytes_new_static("original POST response", 22);
  fixture.action_ = "saveToFile";
  fixture.target_ = fixture.directory_ + "/posted.txt";
  g_assert_true(fixture.first_policy_->HandleResponseData(body, message));
  fixture.Await(1);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "completed");
  AssertContents(fixture.target_, "original POST response");
  // A second response cannot replace the first file, even if its body is
  // already buffered. Cancellation likewise publishes no destination.
  g_assert_true(fixture.first_policy_->HandleResponseData(body, message));
  fixture.Await(2);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "failed");
  AssertContents(fixture.target_, "original POST response");
  fixture.action_ = "cancel";
  g_assert_true(fixture.first_policy_->HandleResponseData(body, message));
  fixture.Await(3);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "cancelled");
  fixture.first_policy_->SetEnabled(false);
  g_assert_true(fixture.first_policy_->HandleResponseData(body, message));
  fixture.Await(4);
  g_assert_cmpstr(fixture.results_.back().status.c_str(), ==, "cancelled");
  g_assert_cmpuint(fixture.requests_, ==, 3);
  soup_message_headers_remove(headers, "Content-Disposition");
  g_assert_false(fixture.first_policy_->HandleResponseData(body, message));
  soup_message_headers_remove(headers, "Content-Type");
  // An absent Content-Type is not itself a request to download an error page.
  g_assert_false(fixture.first_policy_->HandleResponseData(body, message));
  soup_message_headers_append(headers, "Content-Type",
                              "application/octet-stream");
  fixture.first_policy_->SetEnabled(true);
  fixture.first_policy_->SetDelegateEnabled(false);
  g_assert_true(fixture.first_policy_->HandleResponseData(body, message));
  const std::string default_path = fixture.directory_ + "/download";
  Wait([&] { return g_file_test(default_path.c_str(), G_FILE_TEST_EXISTS); });
  AssertContents(default_path, "original POST response");
  g_bytes_unref(body);
  g_object_unref(message);
}
} // namespace

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/downloads/default-existing-concurrent",
                  TestDefaultExistingAndConcurrentNames);
  g_test_add_func("/downloads/explicit-target-no-overwrite",
                  TestExplicitTargetNeverOverwrites);
  g_test_add_func("/downloads/decisions", TestDecisionsAndLateDecision);
  g_test_add_func("/downloads/scope-and-disposal",
                  TestDisabledScopeAndDisposal);
  g_test_add_func("/downloads/default-without-delegate",
                  TestDefaultWithoutDelegate);
  g_test_add_func("/downloads/invalid-target-and-callback-error",
                  TestInvalidTargetAndCallbackError);
  g_test_add_func("/downloads/navigation-error-correlation",
                  TestNavigationErrorCorrelation);
  g_test_add_func("/downloads/original-custom-response",
                  TestOriginalCustomResponse);
  return g_test_run();
}
