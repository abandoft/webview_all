#include "platform/webview_platform.h"

#include <DispatcherQueue.h>
#include <windows.graphics.capture.h>

#include <utility>

#include "util/logging.h"

namespace webview_all_windows {

WebviewPlatform::WebviewPlatform(WinrtRuntime *runtime) : runtime_(runtime) {
  if (runtime_ == nullptr || !runtime_->available()) {
    error_ = WebviewPlatformInitializationError{
        "winrt_runtime_unavailable", "winrt_runtime",
        "Windows Runtime initialization is unavailable.", E_FAIL};
    return;
  }

  bool capture_supported = false;
  const HRESULT capture_result = GetGraphicsCaptureSupport(capture_supported);
  if (FAILED(capture_result)) {
    error_ = WebviewPlatformInitializationError{
        "graphics_capture_initialization_failed", "graphics_capture",
        "Windows graphics capture capability detection failed.",
        capture_result};
    return;
  }
  if (!capture_supported) {
    error_ = WebviewPlatformInitializationError{
        "graphics_capture_unavailable", "graphics_capture",
        "Windows graphics capture is unavailable in the current device or "
        "session.",
        S_FALSE};
    return;
  }

  const HRESULT dispatcher_queue_result = EnsureDispatcherQueue();
  if (FAILED(dispatcher_queue_result)) {
    error_ = WebviewPlatformInitializationError{
        "dispatcher_queue_initialization_failed", "dispatcher_queue",
        "Creating or reusing the UI-thread DispatcherQueue required by "
        "Windows Composition failed.",
        dispatcher_queue_result};
    return;
  }

  graphics_context_ = std::make_unique<GraphicsContext>(runtime_);
  if (!graphics_context_->IsValid()) {
    std::string code = "d3d_device_creation_failed";
    std::string stage = "d3d_device";
    std::string message = "Creating a Direct3D 11 device failed.";
    switch (graphics_context_->initialization_stage()) {
    case GraphicsContextInitializationStage::kDxgiDevice:
      code = "dxgi_device_initialization_failed";
      stage = "dxgi_device";
      message = "The Direct3D device does not expose the required DXGI "
                "interface.";
      break;
    case GraphicsContextInitializationStage::kWinrtD3DInterop:
      code = "d3d_interop_initialization_failed";
      stage = "d3d_interop";
      message = "Creating the Windows Runtime Direct3D interop device failed.";
      break;
    case GraphicsContextInitializationStage::kNone:
    case GraphicsContextInitializationStage::kD3DDevice:
      break;
    }
    error_ = WebviewPlatformInitializationError{
        std::move(code), std::move(stage), std::move(message),
        graphics_context_->initialization_hresult()};
    graphics_context_.reset();
    return;
  }

  const HRESULT compositor_result =
      graphics_context_->CreateCompositor(compositor_);
  if (FAILED(compositor_result) || !compositor_) {
    error_ = WebviewPlatformInitializationError{
        "composition_initialization_failed", "composition",
        "Creating the Windows composition renderer failed.",
        FAILED(compositor_result) ? compositor_result : E_POINTER};
    compositor_ = nullptr;
    graphics_context_.reset();
    return;
  }

  if (graphics_context_->using_software_renderer()) {
    util::LogWarning(
        "The hardware Direct3D device was unavailable; using the Windows "
        "software renderer.");
  }

  valid_ = true;
}

HRESULT WebviewPlatform::EnsureDispatcherQueue() {
  try {
    dispatcher_queue_ =
        winrt::Windows::System::DispatcherQueue::GetForCurrentThread();
  } catch (const winrt::hresult_error &error) {
    return error.code();
  }
  if (dispatcher_queue_) {
    return S_OK;
  }

  const DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),
                                       DQTYPE_THREAD_CURRENT, DQTAT_COM_NONE};
  HRESULT result = runtime_->CreateDispatcherQueueController(
      options, dispatcher_queue_controller_.put());
  if (SUCCEEDED(result) && dispatcher_queue_controller_) {
    try {
      dispatcher_queue_ =
          winrt::Windows::System::DispatcherQueue::GetForCurrentThread();
    } catch (const winrt::hresult_error &error) {
      return error.code();
    }
    return dispatcher_queue_ ? S_OK : E_POINTER;
  }

  // Another component can install a queue between the first lookup and the
  // creation request. Treat that as a reusable queue instead of a failure.
  try {
    dispatcher_queue_ =
        winrt::Windows::System::DispatcherQueue::GetForCurrentThread();
  } catch (const winrt::hresult_error &) {
    return FAILED(result) ? result : E_FAIL;
  }
  return dispatcher_queue_ ? S_OK : (FAILED(result) ? result : E_POINTER);
}

HRESULT WebviewPlatform::GetGraphicsCaptureSupport(bool &supported) {
  supported = false;
  HSTRING className;
  HSTRING_HEADER classNameHeader;

  HRESULT result = runtime_->CreateStringReference(
      RuntimeClass_Windows_Graphics_Capture_GraphicsCaptureSession, &className,
      &classNameHeader);
  if (FAILED(result)) {
    return result;
  }

  winrt::com_ptr<
      ABI::Windows::Graphics::Capture::IGraphicsCaptureSessionStatics>
      capture_session_statics;
  result = runtime_->GetActivationFactory(
      className,
      __uuidof(ABI::Windows::Graphics::Capture::IGraphicsCaptureSessionStatics),
      capture_session_statics.put_void());
  if (FAILED(result) || !capture_session_statics) {
    return FAILED(result) ? result : E_POINTER;
  }

  boolean is_supported = false;
  result = capture_session_statics->IsSupported(&is_supported);
  if (FAILED(result)) {
    return result;
  }

  supported = is_supported != false;
  return S_OK;
}

} // namespace webview_all_windows
