#pragma once

#include <D3d11.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.System.h>

namespace webview_all_windows::util {

struct D3DDeviceCreationResult {
  winrt::com_ptr<ID3D11Device> device;
  HRESULT hardware_hresult = E_FAIL;
  HRESULT fallback_hresult = E_FAIL;
  bool used_software_renderer = false;

  HRESULT hresult() const {
    if (device) {
      return used_software_renderer ? fallback_hresult : hardware_hresult;
    }
    if (FAILED(fallback_hresult)) {
      return fallback_hresult;
    }
    if (FAILED(hardware_hresult)) {
      return hardware_hresult;
    }
    return E_POINTER;
  }
};

inline HRESULT CreateD3DDevice(D3D_DRIVER_TYPE const type,
                               winrt::com_ptr<ID3D11Device> &device) {
  WINRT_ASSERT(!device);

  // Windows.Graphics.Capture requires BGRA interoperability. Video-device
  // support is not required and can reject otherwise usable display drivers.
  constexpr UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

  // #ifdef _DEBUG
  //	flags |= D3D11_CREATE_DEVICE_DEBUG;
  // #endif

  return D3D11CreateDevice(nullptr, type, nullptr, flags, nullptr, 0,
                           D3D11_SDK_VERSION, device.put(), nullptr, nullptr);
}

inline D3DDeviceCreationResult CreateD3DDevice() {
  D3DDeviceCreationResult result;
  result.hardware_hresult =
      CreateD3DDevice(D3D_DRIVER_TYPE_HARDWARE, result.device);
  if (SUCCEEDED(result.hardware_hresult) && result.device) {
    result.fallback_hresult = result.hardware_hresult;
    return result;
  }

  result.device = nullptr;
  result.fallback_hresult =
      CreateD3DDevice(D3D_DRIVER_TYPE_WARP, result.device);
  result.used_software_renderer =
      SUCCEEDED(result.fallback_hresult) && static_cast<bool>(result.device);
  return result;
}

} // namespace webview_all_windows::util
