#include "plugin/environment_request.h"

#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>
#include <tuple>

using webview_all_windows::EnvironmentRequestAction;
using webview_all_windows::HasExplicitEnvironmentOptions;
using webview_all_windows::SelectEnvironmentRequestAction;

namespace {

using Configuration = std::tuple<std::string, std::string, std::string>;
using OptionalConfiguration = std::optional<Configuration>;

void Check(bool condition, const char *message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
  }
}

void CheckAction(EnvironmentRequestAction expected,
                 const OptionalConfiguration &requested, bool active,
                 const OptionalConfiguration &active_configuration,
                 const OptionalConfiguration &pending_configuration,
                 const char *message) {
  Check(SelectEnvironmentRequestAction(requested, active, active_configuration,
                                       pending_configuration) == expected,
        message);
}

} // namespace

int main() {
  const std::string empty;
  const std::string path = "custom-data";
  Check(!HasExplicitEnvironmentOptions(nullptr, nullptr, nullptr),
        "only omitted options inherit the shared environment");
  Check(HasExplicitEnvironmentOptions(&empty, nullptr, nullptr),
        "an empty data path explicitly requests the default configuration");
  Check(HasExplicitEnvironmentOptions(nullptr, &empty, nullptr),
        "an empty runtime path is an explicit configuration request");
  Check(HasExplicitEnvironmentOptions(nullptr, nullptr, &empty),
        "empty browser arguments are an explicit configuration request");
  Check(HasExplicitEnvironmentOptions(&path, nullptr, nullptr),
        "a custom data path is an explicit configuration request");

  // These represent configurations after the host's existing canonicalization.
  const OptionalConfiguration defaults = Configuration{"default-data", "", ""};
  const OptionalConfiguration custom =
      Configuration{"custom-data", "runtime", "args"};
  const OptionalConfiguration omitted;

  CheckAction(EnvironmentRequestAction::create, omitted, false, {}, {},
              "omitted options initialize defaults when no environment exists");
  CheckAction(EnvironmentRequestAction::create, custom, false, {}, {},
              "an explicit request initializes its configuration");
  CheckAction(EnvironmentRequestAction::reuse, omitted, true, custom, {},
              "default consumers inherit an active custom environment");
  CheckAction(EnvironmentRequestAction::wait, omitted, false, {}, custom,
              "default consumers wait for pending custom initialization");
  CheckAction(EnvironmentRequestAction::reuse, custom, true, custom, {},
              "the same explicit configuration reuses the active environment");
  CheckAction(EnvironmentRequestAction::wait, custom, false, {}, custom,
              "the same explicit configuration joins pending initialization");
  CheckAction(
      EnvironmentRequestAction::conflict, defaults, true, custom, {},
      "explicit defaults do not silently inherit an active custom environment");
  CheckAction(EnvironmentRequestAction::conflict, defaults, false, {}, custom,
              "explicit defaults do not join pending custom initialization");
  CheckAction(EnvironmentRequestAction::reuse, defaults, true, defaults, {},
              "explicit defaults reuse an active default environment");
  for (const Configuration &different : {
           Configuration{"other-data", "runtime", "args"},
           Configuration{"custom-data", "other-runtime", "args"},
           Configuration{"custom-data", "runtime", "other-args"},
           // Supplying only the custom path is still a complete request: its
           // omitted runtime and arguments resolve to their defaults.
           Configuration{"custom-data", "", ""},
       }) {
    CheckAction(EnvironmentRequestAction::conflict, different, true, custom, {},
                "every explicitly requested canonical option must match");
    CheckAction(EnvironmentRequestAction::conflict, different, false, {},
                custom,
                "a conflicting request must not join pending initialization");
  }
  std::cout << "PASS: shared environment inheritance and explicit "
               "configuration decisions\n";
  return 0;
}
