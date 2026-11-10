#pragma once
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <optional>
#include <string>
#pragma comment(lib, "bcrypt.lib")

namespace webview_all_windows {
// WebView2 permits at most 64 characters, including our ownership namespace.
// Keep the mapping stable: case folding follows Windows profile-name semantics.
inline std::optional<std::wstring> ManagedProfileName(const std::wstring& name) {
  if (name.empty() || name.size() > 64) return std::nullopt;
  std::string input = "webview_all/profile/";
  for (const auto character : name) {
    if (!((character >= L'a' && character <= L'z') || (character >= L'A' && character <= L'Z') ||
          (character >= L'0' && character <= L'9') || character == L'_' || character == L'-')) return std::nullopt;
    input.push_back(static_cast<char>(character >= L'A' && character <= L'Z' ? character + 32 : character));
  }
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) return std::nullopt;
  std::array<UCHAR, 32> digest{};
  const auto status = BCryptHash(algorithm, nullptr, 0, reinterpret_cast<PUCHAR>(input.data()),
      static_cast<ULONG>(input.size()), digest.data(), static_cast<ULONG>(digest.size()));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status < 0) return std::nullopt;
  constexpr wchar_t hex[] = L"0123456789abcdef";
  std::wstring result = L"webview_all_";
  // 208 bits leave room for the prefix within the native 64-character limit.
  for (size_t index = 0; index < 26; ++index) {
    result += hex[digest[index] >> 4]; result += hex[digest[index] & 15];
  }
  return result;
}
}  // namespace webview_all_windows
