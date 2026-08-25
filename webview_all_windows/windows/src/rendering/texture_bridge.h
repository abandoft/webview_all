#pragma once

#include <windows.graphics.capture.h>
#include <wrl.h>

#include <chrono>
#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <string>

#include "rendering/graphics_context.h"

namespace webview_all_windows {

struct Size {
  size_t width;
  size_t height;
};

struct WindowsRenderingError {
  std::string code;
  std::string stage;
  std::string message;
  HRESULT hresult;
};

class TextureBridge {
public:
  typedef std::function<void()> FrameAvailableCallback;
  typedef std::chrono::duration<double, std::milli> FrameDuration;

  TextureBridge(GraphicsContext *graphics_context,
                ABI::Windows::UI::Composition::IVisual *visual);
  virtual ~TextureBridge();

  std::optional<WindowsRenderingError> Start();
  std::optional<WindowsRenderingError> Resize();
  void Stop();
  bool IsValid() const { return !initialization_error_.has_value(); }
  const std::optional<WindowsRenderingError> &initialization_error() const {
    return initialization_error_;
  }

  void SetOnFrameAvailable(FrameAvailableCallback callback) {
    frame_available_ = std::move(callback);
  }

  void SetFpsLimit(std::optional<int> max_fps);

protected:
  bool is_running_ = false;

  const GraphicsContext *graphics_context_;
  std::mutex mutex_;
  std::optional<FrameDuration> frame_duration_ = std::nullopt;

  FrameAvailableCallback frame_available_;
  winrt::com_ptr<ID3D11Texture2D> last_frame_;
  std::optional<std::chrono::high_resolution_clock::time_point>
      last_frame_timestamp_;

  winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>
      capture_item_;
  winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool>
      frame_pool_;
  winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureSession>
      capture_session_;

  EventRegistrationToken on_frame_arrived_token_ = {};
  bool frame_arrived_handler_registered_ = false;
  std::optional<WindowsRenderingError> initialization_error_;

  virtual void StopInternal();
  void OnFrameArrived();
  bool ShouldDropFrame();

  // corresponds to DXGI_FORMAT_B8G8R8A8_UNORM
  static constexpr auto kPixelFormat = ABI::Windows::Graphics::DirectX::
      DirectXPixelFormat::DirectXPixelFormat_B8G8R8A8UIntNormalized;
};

} // namespace webview_all_windows
