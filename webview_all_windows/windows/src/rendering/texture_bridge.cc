#include "rendering/texture_bridge.h"

#include <windows.foundation.h>

#include <algorithm>
#include <string>

#include "util/direct3d11.interop.h"

namespace webview_all_windows {
namespace {
const int kNumBuffers = 1;

WindowsRenderingError RenderingError(const std::string &code,
                                     const std::string &stage,
                                     const std::string &message,
                                     HRESULT hresult) {
  return WindowsRenderingError{code, stage, message, hresult};
}
} // namespace

TextureBridge::TextureBridge(GraphicsContext *graphics_context,
                             ABI::Windows::UI::Composition::IVisual *visual)
    : graphics_context_(graphics_context) {
  const HRESULT capture_item_result =
      graphics_context_->CreateGraphicsCaptureItemFromVisual(visual,
                                                             capture_item_);
  if (FAILED(capture_item_result) || !capture_item_) {
    initialization_error_ = RenderingError(
        "graphics_capture_item_creation_failed", "graphics_capture_item",
        "Creating the graphics capture item failed.",
        FAILED(capture_item_result) ? capture_item_result : E_POINTER);
    return;
  }
}

TextureBridge::~TextureBridge() { Stop(); }

std::optional<WindowsRenderingError> TextureBridge::Start() {
  const std::lock_guard<std::mutex> lock(mutex_);
  if (is_running_) {
    return std::nullopt;
  }
  if (initialization_error_) {
    return initialization_error_;
  }
  if (!capture_item_ || !graphics_context_) {
    return RenderingError(
        "graphics_capture_item_unavailable", "graphics_capture_item",
        "The graphics capture item is unavailable.", E_POINTER);
  }

  ABI::Windows::Graphics::SizeInt32 size = {};
  const HRESULT size_result = capture_item_->get_Size(&size);
  if (FAILED(size_result) || size.Width <= 0 || size.Height <= 0) {
    return RenderingError("graphics_capture_size_unavailable",
                          "graphics_capture_size",
                          "Reading the graphics capture size failed.",
                          FAILED(size_result) ? size_result : E_INVALIDARG);
  }

  const HRESULT frame_pool_result = graphics_context_->CreateCaptureFramePool(
      graphics_context_->device(),
      static_cast<ABI::Windows::Graphics::DirectX::DirectXPixelFormat>(
          kPixelFormat),
      kNumBuffers, size, frame_pool_);
  if (FAILED(frame_pool_result) || !frame_pool_) {
    return RenderingError("graphics_capture_frame_pool_creation_failed",
                          "graphics_capture_frame_pool",
                          "Creating the graphics capture frame pool failed.",
                          FAILED(frame_pool_result) ? frame_pool_result
                                                    : E_POINTER);
  }

  const HRESULT frame_handler_hr = frame_pool_->add_FrameArrived(
      Microsoft::WRL::Callback<ABI::Windows::Foundation::ITypedEventHandler<
          ABI::Windows::Graphics::Capture::Direct3D11CaptureFramePool *,
          IInspectable *>>(
          [this](ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool
                     *pool,
                 IInspectable *args) -> HRESULT {
            try {
              OnFrameArrived();
            } catch (...) {
              return E_FAIL;
            }
            return S_OK;
          })
          .Get(),
      &on_frame_arrived_token_);
  if (FAILED(frame_handler_hr)) {
    StopInternal();
    return RenderingError(
        "graphics_capture_frame_handler_registration_failed",
        "graphics_capture_frame_handler",
        "Registering the graphics capture frame handler failed.",
        frame_handler_hr);
  }
  frame_arrived_handler_registered_ = true;

  const HRESULT session_result = frame_pool_->CreateCaptureSession(
      capture_item_.get(), capture_session_.put());
  if (FAILED(session_result) || !capture_session_) {
    StopInternal();
    return RenderingError("graphics_capture_session_creation_failed",
                          "graphics_capture_session",
                          "Creating the graphics capture session failed.",
                          FAILED(session_result) ? session_result : E_POINTER);
  }

  const HRESULT start_result = capture_session_->StartCapture();
  if (FAILED(start_result)) {
    StopInternal();
    return RenderingError("graphics_capture_start_failed",
                          "graphics_capture_start",
                          "Starting graphics capture failed.", start_result);
  }

  is_running_ = true;
  return std::nullopt;
}

std::optional<WindowsRenderingError> TextureBridge::Resize() {
  const std::lock_guard<std::mutex> lock(mutex_);
  if (!is_running_ || !frame_pool_) {
    return std::nullopt;
  }

  ABI::Windows::Graphics::SizeInt32 size = {};
  const HRESULT size_result = capture_item_->get_Size(&size);
  if (FAILED(size_result) || size.Width <= 0 || size.Height <= 0) {
    StopInternal();
    return RenderingError(
        "graphics_capture_size_unavailable", "graphics_capture_size",
        "Reading the resized graphics capture surface failed.",
        FAILED(size_result) ? size_result : E_INVALIDARG);
  }

  const HRESULT resize_result = frame_pool_->Recreate(
      graphics_context_->device(),
      static_cast<ABI::Windows::Graphics::DirectX::DirectXPixelFormat>(
          kPixelFormat),
      kNumBuffers, size);
  if (FAILED(resize_result)) {
    StopInternal();
    return RenderingError(
        "graphics_capture_resize_failed", "graphics_capture_resize",
        "Resizing the graphics capture frame pool failed.", resize_result);
  }
  return std::nullopt;
}

void TextureBridge::Stop() {
  const std::lock_guard<std::mutex> lock(mutex_);
  StopInternal();
}

void TextureBridge::StopInternal() {
  is_running_ = false;
  if (frame_pool_ && frame_arrived_handler_registered_) {
    frame_pool_->remove_FrameArrived(on_frame_arrived_token_);
    frame_arrived_handler_registered_ = false;
  }
  if (capture_session_) {
    auto closable =
        capture_session_.try_as<ABI::Windows::Foundation::IClosable>();
    if (closable) {
      closable->Close();
    }
    capture_session_ = nullptr;
  }
  if (frame_pool_) {
    auto closable = frame_pool_.try_as<ABI::Windows::Foundation::IClosable>();
    if (closable) {
      closable->Close();
    }
    frame_pool_ = nullptr;
  }
  last_frame_ = nullptr;
}

void TextureBridge::OnFrameArrived() {
  const std::lock_guard<std::mutex> lock(mutex_);
  if (!is_running_) {
    return;
  }

  bool has_frame = false;

  winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFrame>
      frame;
  auto hr = frame_pool_->TryGetNextFrame(frame.put());
  if (SUCCEEDED(hr) && frame) {
    winrt::com_ptr<
        ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface>
        frame_surface;

    if (SUCCEEDED(frame->get_Surface(frame_surface.put()))) {
      last_frame_ =
          util::TryGetDXGIInterfaceFromObject<ID3D11Texture2D>(frame_surface);
      has_frame = !ShouldDropFrame();
    }
  }

  if (has_frame && frame_available_) {
    frame_available_();
  }
}

bool TextureBridge::ShouldDropFrame() {
  if (!frame_duration_.has_value()) {
    return false;
  }
  auto now = std::chrono::high_resolution_clock::now();

  bool should_drop_frame = false;
  if (last_frame_timestamp_.has_value()) {
    auto diff = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - last_frame_timestamp_.value());
    should_drop_frame = diff < frame_duration_.value();
  }

  if (!should_drop_frame) {
    last_frame_timestamp_ = now;
  }
  return should_drop_frame;
}

void TextureBridge::SetFpsLimit(std::optional<int> max_fps) {
  const std::lock_guard<std::mutex> lock(mutex_);
  auto value = max_fps.value_or(0);
  if (value != 0) {
    frame_duration_ = FrameDuration(1000.0 / value);
  } else {
    frame_duration_.reset();
    last_frame_timestamp_.reset();
  }
}

} // namespace webview_all_windows
