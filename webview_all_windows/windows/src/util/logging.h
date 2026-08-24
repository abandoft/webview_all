#pragma once

#include <windows.h>

#include <cstdio>
#include <string>
#include <string_view>

namespace webview_all_windows::util {

inline void LogWarning(std::string_view message) {
  std::string output = "[webview_all_windows] ";
  for (const char character : message) {
    output.push_back(character == '\r' || character == '\n' ? ' ' : character);
  }
  output.append("\n");
  OutputDebugStringA(output.c_str());
  std::fwrite(output.data(), sizeof(char), output.size(), stderr);
  std::fflush(stderr);
}

} // namespace webview_all_windows::util
