#!/usr/bin/env bash
set -euo pipefail

# Retry SDK installation only. Application tests must retain their first result.
image='system-images;android-35;google_apis;x86_64'
sdk_manager="$(command -v sdkmanager || true)"
if [[ -z "$sdk_manager" ]]; then
  android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  sdk_manager="$android_sdk_root/cmdline-tools/latest/bin/sdkmanager"
fi
if [[ ! -x "$sdk_manager" ]]; then
  echo 'Android SDK command-line tools are unavailable.' >&2
  exit 64
fi
# sdkmanager is the last pipeline command. Ignore yes exiting after the reader
# closes its input, while retaining a license-command failure.
set +o pipefail
yes | "$sdk_manager" --licenses > /dev/null
set -o pipefail
for attempt in 1 2 3; do
  if "$sdk_manager" --install "$image"; then
    exit 0
  fi
  echo "Android system image installation failed (attempt $attempt/3)." >&2
  df -h "${ANDROID_HOME:-.}" >&2 || true
  if [[ "$attempt" != 3 ]]; then sleep 5; fi
done
exit 1
