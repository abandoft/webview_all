#pragma once

#include <D3d11.h>
#include <windows.graphics.capture.h>
#include <windows.ui.composition.h>
#include <winrt/Windows.Foundation.h>

#include "platform/winrt_runtime.h"

namespace webview_all_windows {

enum class GraphicsContextInitializationStage {
  kNone,
  kD3DDevice,
  kDxgiDevice,
  kWinrtD3DInterop,
};

class GraphicsContext {
public:
  explicit GraphicsContext(WinrtRuntime *runtime);

  inline bool IsValid() const { return valid_; }
  inline GraphicsContextInitializationStage initialization_stage() const {
    return initialization_stage_;
  }
  inline HRESULT initialization_hresult() const {
    return initialization_hresult_;
  }
  inline bool using_software_renderer() const {
    return using_software_renderer_;
  }

  ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice *device() const {
    return device_winrt_.get();
  }
  ID3D11Device *d3d_device() const { return device_.get(); }
  ID3D11DeviceContext *d3d_device_context() const {
    return device_context_.get();
  }

  HRESULT CreateCompositor(
      winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> &compositor);

  HRESULT CreateGraphicsCaptureItemFromVisual(
      ABI::Windows::UI::Composition::IVisual *visual,
      winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>
          &capture_item) const;

  HRESULT CreateCaptureFramePool(
      ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice *device,
      ABI::Windows::Graphics::DirectX::DirectXPixelFormat pixelFormat,
      INT32 numberOfBuffers, ABI::Windows::Graphics::SizeInt32 size,
      winrt::com_ptr<
          ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool>
          &capture_frame_pool) const;

private:
  bool valid_ = false;
  WinrtRuntime *runtime_;
  winrt::com_ptr<ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice>
      device_winrt_;
  winrt::com_ptr<ID3D11Device> device_{nullptr};
  winrt::com_ptr<ID3D11DeviceContext> device_context_{nullptr};
  GraphicsContextInitializationStage initialization_stage_ =
      GraphicsContextInitializationStage::kNone;
  HRESULT initialization_hresult_ = S_OK;
  bool using_software_renderer_ = false;
};

} // namespace webview_all_windows
