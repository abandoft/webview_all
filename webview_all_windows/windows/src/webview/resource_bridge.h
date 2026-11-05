#pragma once

#include <WebView2.h>
#include <flutter/binary_messenger.h>
#include <memory>
#include <string>

namespace webview_all_windows {
class ResourceBridgeWindows {
public:
  explicit ResourceBridgeWindows(ICoreWebView2 *view);
  ~ResourceBridgeWindows();
  HRESULT Configure(flutter::BinaryMessenger *messenger,
                    const std::string &channel, const std::string &host,
                    bool enabled, UINT request_timeout_millis = 30000);

private:
  struct State;
  ICoreWebView2 *view_;
  EventRegistrationToken token_{};
  bool registered_ = false;
  std::wstring filter_;
  std::shared_ptr<State> state_;
};
} // namespace webview_all_windows
