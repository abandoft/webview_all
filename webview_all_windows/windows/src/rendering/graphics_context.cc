#include "rendering/graphics_context.h"

#include <utility>

#include "util/d3dutil.h"
#include "util/direct3d11.interop.h"

namespace webview_all_windows {

GraphicsContext::GraphicsContext(WinrtRuntime *runtime) : runtime_(runtime) {
  util::D3DDeviceCreationResult device_result = util::CreateD3DDevice();
  device_ = std::move(device_result.device);
  using_software_renderer_ = device_result.used_software_renderer;
  if (!device_) {
    initialization_stage_ = GraphicsContextInitializationStage::kD3DDevice;
    initialization_hresult_ = device_result.hresult();
    return;
  }

  device_->GetImmediateContext(device_context_.put());
  if (!device_context_) {
    initialization_stage_ = GraphicsContextInitializationStage::kD3DDevice;
    initialization_hresult_ = E_POINTER;
    return;
  }

  const winrt::com_ptr<IDXGIDevice> dxgi_device = device_.try_as<IDXGIDevice>();
  if (!dxgi_device) {
    initialization_stage_ = GraphicsContextInitializationStage::kDxgiDevice;
    initialization_hresult_ = E_NOINTERFACE;
    return;
  }

  const HRESULT interop_result = util::CreateDirect3D11DeviceFromDXGIDevice(
      dxgi_device.get(),
      reinterpret_cast<IInspectable **>(device_winrt_.put()));
  if (FAILED(interop_result) || !device_winrt_) {
    initialization_stage_ =
        GraphicsContextInitializationStage::kWinrtD3DInterop;
    initialization_hresult_ =
        FAILED(interop_result) ? interop_result : E_POINTER;
    return;
  }

  valid_ = true;
}

HRESULT GraphicsContext::CreateCompositor(
    winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor> &compositor) {
  compositor = nullptr;
  HSTRING className;
  HSTRING_HEADER classNameHeader;

  HRESULT result = runtime_->CreateStringReference(
      RuntimeClass_Windows_UI_Composition_Compositor, &className,
      &classNameHeader);
  if (FAILED(result)) {
    return result;
  }

  winrt::com_ptr<IActivationFactory> af;
  result = runtime_->GetActivationFactory(
      className, __uuidof(IActivationFactory), af.put_void());
  if (FAILED(result) || !af) {
    return FAILED(result) ? result : E_POINTER;
  }

  result =
      af->ActivateInstance(reinterpret_cast<IInspectable **>(compositor.put()));
  if (FAILED(result) || !compositor) {
    compositor = nullptr;
    return FAILED(result) ? result : E_POINTER;
  }

  return S_OK;
}

winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>
GraphicsContext::CreateGraphicsCaptureItemFromVisual(
    ABI::Windows::UI::Composition::IVisual *visual) const {
  HSTRING className;
  HSTRING_HEADER classNameHeader;

  if (FAILED(runtime_->CreateStringReference(
          RuntimeClass_Windows_Graphics_Capture_GraphicsCaptureItem, &className,
          &classNameHeader))) {
    return nullptr;
  }

  winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItemStatics>
      capture_item_statics;
  if (FAILED(runtime_->GetActivationFactory(
          className,
          __uuidof(
              ABI::Windows::Graphics::Capture::IGraphicsCaptureItemStatics),
          capture_item_statics.put_void()))) {
    return nullptr;
  }

  winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>
      capture_item;
  if (FAILED(
          capture_item_statics->CreateFromVisual(visual, capture_item.put()))) {
    return nullptr;
  }

  return capture_item;
}

winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool>
GraphicsContext::CreateFreeThreadedCaptureFramePool(
    ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice *device,
    ABI::Windows::Graphics::DirectX::DirectXPixelFormat pixelFormat,
    INT32 numberOfBuffers, ABI::Windows::Graphics::SizeInt32 size) const {
  HSTRING className;
  HSTRING_HEADER classNameHeader;

  if (FAILED(runtime_->CreateStringReference(
          RuntimeClass_Windows_Graphics_Capture_Direct3D11CaptureFramePool,
          &className, &classNameHeader))) {
    return nullptr;
  }

  winrt::com_ptr<
      ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePoolStatics2>
      capture_frame_pool_statics;
  if (FAILED(runtime_->GetActivationFactory(
          className,
          __uuidof(ABI::Windows::Graphics::Capture::
                       IDirect3D11CaptureFramePoolStatics2),
          capture_frame_pool_statics.put_void()))) {
    return nullptr;
  }

  winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool>
      capture_frame_pool;

  if (FAILED(capture_frame_pool_statics->CreateFreeThreaded(
          device, pixelFormat, numberOfBuffers, size,
          capture_frame_pool.put()))) {
    return nullptr;
  }

  return capture_frame_pool;
}

} // namespace webview_all_windows
