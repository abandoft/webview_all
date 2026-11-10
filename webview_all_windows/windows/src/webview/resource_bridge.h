#pragma once

#include <WebView2.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <string>
#include <vector>

namespace webview_all_windows {
class ResourceBridgeWindows {
public:
  explicit ResourceBridgeWindows(ICoreWebView2 *view);
  ~ResourceBridgeWindows();
  HRESULT Configure(flutter::BinaryMessenger *messenger,
                    const std::string &channel, const std::string &host,
                    bool enabled);
  HRESULT ConfigureNetwork(flutter::BinaryMessenger* messenger,
                           const flutter::EncodableMap& configuration);
  HRESULT ConfigureRules(const flutter::EncodableList& rules);
  // NewWindow replaces the target's web contents. Keep the configured Dart
  // delegates, but register native request handling against the new contents.
  HRESULT Reattach();

private:
  struct State;
  struct Registry;
  HRESULT EnsureHandler();
  HRESULT UpdateFilters();
  ICoreWebView2 *view_;
  EventRegistrationToken token_{};
  bool registered_ = false;
  std::vector<std::wstring> filters_;
  std::shared_ptr<Registry> registry_;
};
} // namespace webview_all_windows
