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
simulator="$(python3 "$tools/create_ios_test_simulator.py" "webview_all_$name")"
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
    tail -n 120 "$logs/flutter-command.log" >&2
    tail -n 120 "$logs/device.log" >&2
  fi
  bounded 30 xcrun simctl shutdown "$simulator" || true
  bounded 30 xcrun simctl delete "$simulator" || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Flutter does not share an XCTest simulator or a prior Flutter launch. Each
# target runs once on a fresh device, with startup logs retained on failure.
bounded 60 xcrun simctl boot "$simulator"
bounded 600 xcrun simctl bootstatus "$simulator" -b
xcrun simctl spawn "$simulator" log stream --style compact --level debug \
  --predicate 'process == "Runner"' > "$logs/device.log" 2>&1 &
log_pid=$!
set +e
flutter test "$target" -d "$simulator" --no-uninstall \
  --debug-logs-dir="$logs/flutter" --reporter expanded --verbose \
  2>&1 | tee "$logs/flutter-command.log"
status="${PIPESTATUS[0]}"
set -e
exit "$status"
