#pragma once

#include <windows.graphics.capture.h>
#include <wrl.h>

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>

#include "rendering/graphics_context.h"

namespace webview_all_windows {

struct Size {
  size_t width;
  size_t height;
};

class TextureBridge {
public:
  typedef std::function<void()> FrameAvailableCallback;
  typedef std::function<void(Size size)> SurfaceSizeChangedCallback;
  typedef std::chrono::duration<double, std::milli> FrameDuration;

  TextureBridge(GraphicsContext *graphics_context,
                ABI::Windows::UI::Composition::IVisual *visual);
  virtual ~TextureBridge();

  bool Start();
  void Stop();
  bool IsValid() const { return capture_item_ != nullptr; }

  void SetOnFrameAvailable(FrameAvailableCallback callback) {
    frame_available_ = std::move(callback);
  }

  void SetOnSurfaceSizeChanged(SurfaceSizeChangedCallback callback) {
    surface_size_changed_ = std::move(callback);
  }

  void NotifySurfaceSizeChanged();
  void SetFpsLimit(std::optional<int> max_fps);

protected:
  struct FrameCallbackState {
    explicit FrameCallbackState(TextureBridge *owner) : owner(owner) {}

    std::mutex mutex;
    std::condition_variable idle;
    TextureBridge *owner;
    std::size_t active_callbacks = 0;
    bool accepting_callbacks = false;
  };

  bool is_running_ = false;

  const GraphicsContext *graphics_context_;
  std::mutex mutex_;
  std::optional<FrameDuration> frame_duration_ = std::nullopt;

  FrameAvailableCallback frame_available_;
  SurfaceSizeChangedCallback surface_size_changed_;
  std::atomic<bool> needs_update_ = false;
  winrt::com_ptr<ID3D11Texture2D> last_frame_;
  std::optional<std::chrono::high_resolution_clock::time_point>
      last_frame_timestamp_;

  winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>
      capture_item_;
  winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool>
      frame_pool_;
  winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureSession>
      capture_session_;

  EventRegistrationToken on_closed_token_ = {};
  EventRegistrationToken on_frame_arrived_token_ = {};
  bool closed_handler_registered_ = false;
  bool frame_arrived_handler_registered_ = false;
  std::shared_ptr<FrameCallbackState> frame_callback_state_;

  virtual void StopInternal();
  void OnFrameArrived();
  bool ShouldDropFrame();

  // corresponds to DXGI_FORMAT_B8G8R8A8_UNORM
  static constexpr auto kPixelFormat = ABI::Windows::Graphics::DirectX::
      DirectXPixelFormat::DirectXPixelFormat_B8G8R8A8UIntNormalized;
};

} // namespace webview_all_windows
