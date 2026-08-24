#pragma once

#include <winrt/Windows.System.h>
#include <winrt/base.h>

#include <memory>
#include <optional>
#include <string>

#include "platform/winrt_runtime.h"
#include "rendering/graphics_context.h"

namespace webview_all_windows {

struct WebviewPlatformInitializationError {
  std::string code;
  std::string stage;
  std::string message;
  HRESULT hresult;
};

class WebviewPlatform {
public:
  explicit WebviewPlatform(WinrtRuntime *runtime);
  bool IsSupported() { return valid_; }
  const std::optional<WebviewPlatformInitializationError> &error() const {
    return error_;
  }
  GraphicsContext *graphics_context() const { return graphics_context_.get(); };
  winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor>
  compositor() const {
    return compositor_;
  }

private:
  HRESULT EnsureDispatcherQueue();
  HRESULT GetGraphicsCaptureSupport(bool &supported);

  WinrtRuntime *runtime_;
  winrt::com_ptr<ABI::Windows::System::IDispatcherQueueController>
      dispatcher_queue_controller_;
  winrt::Windows::System::DispatcherQueue dispatcher_queue_{nullptr};
  std::unique_ptr<GraphicsContext> graphics_context_;
  winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> compositor_;
  std::optional<WebviewPlatformInitializationError> error_;
  bool valid_ = false;
};

} // namespace webview_all_windows
