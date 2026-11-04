#!/usr/bin/env bash
set -euo pipefail

# Retry SDK installation only. Application tests must retain their first result.
image='system-images;android-35;google_apis;x86_64'
# sdkmanager is the last pipeline command. Ignore yes exiting after the reader
# closes its input, while retaining a license-command failure.
set +o pipefail
yes | sdkmanager --licenses > /dev/null
set -o pipefail
for attempt in 1 2 3; do
  if sdkmanager --install "$image"; then
    exit 0
  fi
  echo "Android system image installation failed (attempt $attempt/3)." >&2
  df -h "${ANDROID_HOME:-.}" >&2 || true
  if [[ "$attempt" != 3 ]]; then sleep 5; fi
done
exit 1
