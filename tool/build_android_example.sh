#!/usr/bin/env bash
set -euo pipefail

logs="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/webview-all-android-build.XXXXXX")"
for attempt in 1 2 3; do
  log="$logs/attempt-$attempt.log"
  set +e
  flutter build apk --debug "$@" 2>&1 | tee "$log"
  status=$?
  set -e
  if [[ "$status" == 0 ]]; then exit 0; fi
  # Flutter can retry internally. Inspect only its final Gradle failure so a
  # later compilation error is never classified as an earlier network error.
  if ! python3 - "$log" <<'PY'
import re
import sys
from pathlib import Path

text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', Path(sys.argv[1]).read_text())
failure = text.rfind('FAILURE: Build failed with an exception.')
final = text[failure:] if failure >= 0 else text
network = 'Gradle threw an error while downloading artifacts from the network'
sys.exit(0 if network in final else 1)
PY
  then
    exit "$status"
  fi
  if [[ "$attempt" == 3 ]]; then exit "$status"; fi
  echo "Dependency download failed; retrying Android build setup ($attempt/3)." >&2
  sleep "$((attempt * 5))"
done
