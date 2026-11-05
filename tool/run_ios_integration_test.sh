#!/usr/bin/env bash
set -euo pipefail

target="${1:?Specify an integration test}"
if [[ ! "$target" =~ ^integration_test/[a-zA-Z0-9_]+_test\.dart$ ]]; then
  echo 'Expected an integration_test/*_test.dart target.' >&2
  exit 64
fi
if [[ ! -f pubspec.yaml || ! -f "$target" ]]; then
  echo 'Run from the example directory containing pubspec.yaml and the test target.' >&2
  exit 66
fi
tools="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
name="$(basename "$target" .dart)"
logs="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/webview-all-ios-diagnostics/$name"
mkdir -p "$logs"
simulator="${2:-}"
owned=0
if [[ -z "$simulator" ]]; then
  simulator="$(python3 "$tools/create_ios_test_simulator.py" "webview_all_$name")"
  owned=1
elif [[ ! "$simulator" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
  echo 'Expected an iOS simulator UUID.' >&2
  exit 64
fi
printf '%s\n' "$simulator" > "$logs/simulator-id"
log_pid=''
bounded() {
  python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' "$@"
}
cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ -n "$log_pid" ]]; then
    kill "$log_pid" 2>/dev/null
    wait "$log_pid" 2>/dev/null
  fi
  if [[ "$status" != 0 ]]; then
    bounded 15 xcrun simctl list devices -j > "$logs/devices.json" 2>&1
    tail -n 120 "$logs/flutter-config.log" >&2
    tail -n 120 "$logs/xcodebuild.log" >&2
    tail -n 120 "$logs/device.log" >&2
  fi
  if [[ "$owned" == 1 ]]; then
    bounded 30 xcrun simctl shutdown "$simulator" || true
    bounded 30 xcrun simctl delete "$simulator" || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$owned" == 1 ]]; then bounded 60 xcrun simctl boot "$simulator"; fi
bounded 600 xcrun simctl bootstatus "$simulator" -b
xcrun simctl spawn "$simulator" log stream --style compact --level debug \
  --predicate 'process == "Runner"' > "$logs/device.log" 2>&1 &
log_pid=$!
# The SDK's native integration_test bridge runs the same Dart assertions via
# XCTest. It does not discover a VM URL from simulator logs (flutter#181771).
set +e
flutter build ios --config-only --simulator --debug --target "$target" \
  --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=true \
  2>&1 | tee "$logs/flutter-config.log"
status="${PIPESTATUS[0]}"
set -e
if [[ "$status" != 0 ]]; then exit "$status"; fi
ruby "$tools/add_ios_ui_test_target.rb" ios/Runner.xcodeproj Runner \
  ios/WebViewResourceIntegrationTests --integration
set +e
xcodebuild test -workspace ios/Runner.xcworkspace \
  -scheme WebViewResourceIntegrationTests -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" \
  -only-testing:WebViewResourceIntegrationTests \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath "$logs/result.xcresult" \
  FLUTTER_TARGET="$target" CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$logs/xcodebuild.log"
status="${PIPESTATUS[0]}"
set -e
exit "$status"
