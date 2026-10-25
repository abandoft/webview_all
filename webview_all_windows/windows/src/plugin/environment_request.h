#pragma once

#include <optional>
#include <string>

namespace webview_all_windows {

// Omitted options inherit a shared environment. An explicit empty string still
// requests the platform default for that option, rather than inheritance.
inline bool HasExplicitEnvironmentOptions(const std::string *user_data_path,
                                          const std::string *browser_exe_path,
                                          const std::string *arguments) {
  return user_data_path != nullptr || browser_exe_path != nullptr ||
         arguments != nullptr;
}

enum class EnvironmentRequestAction { create, reuse, wait, conflict };

// The caller canonicalizes an explicit request before comparing it with the
// stored configuration. A missing request represents inheritance, not defaults.
template <typename Configuration>
EnvironmentRequestAction SelectEnvironmentRequestAction(
    const std::optional<Configuration> &requested, bool has_active_environment,
    const std::optional<Configuration> &active_configuration,
    const std::optional<Configuration> &pending_configuration) {
  if (has_active_environment) {
    if (!requested ||
        (active_configuration && *active_configuration == *requested)) {
      return EnvironmentRequestAction::reuse;
    }
    return EnvironmentRequestAction::conflict;
  }
  if (pending_configuration) {
    return !requested || *pending_configuration == *requested
               ? EnvironmentRequestAction::wait
               : EnvironmentRequestAction::conflict;
  }
  return EnvironmentRequestAction::create;
}

} // namespace webview_all_windows
