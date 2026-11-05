#!/usr/bin/env bash
set -euo pipefail

target="${1:?Specify an integration test}"
device="${2:-emulator-5554}"
case "$target" in
  integration_test/*_test.dart) ;;
  *) echo 'Expected an integration_test/*_test.dart target.' >&2; exit 64 ;;
esac
logs="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/webview-all-android-diagnostics/$(basename "$target" .dart)"
mkdir -p "$logs"
adb -s "$device" logcat -v threadtime > "$logs/logcat.txt" 2>&1 &
logcat_pid=$!
cleanup() {
  local status=$?
  trap - EXIT
  set +e
  kill "$logcat_pid" 2>/dev/null
  wait "$logcat_pid" 2>/dev/null
  if [[ "$status" != 0 ]]; then
    adb -s "$device" shell dumpsys activity exit-info > "$logs/process-exits.txt" 2>&1
    adb -s "$device" shell dumpsys meminfo > "$logs/memory.txt" 2>&1
    adb -s "$device" shell dumpsys webviewupdate > "$logs/webview-provider.txt" 2>&1
    tail -n 300 "$logs/logcat.txt" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Reuse the SDK integration driver without flutter test's DDS golden proxy.
flutter drive --driver=test_driver/integration_test.dart --target="$target" \
  -d "$device" --no-dds --debug-logs-dir="$logs/flutter"
