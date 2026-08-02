#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: OHOS_FLUTTER=/absolute/path/to/flutter $0 [--workdir DIR] -- <flutter arguments>"
}

task_workdir="webview_all_ohos"
if [[ "${1:-}" == "--workdir" ]]; then
  if [[ $# -lt 3 ]]; then
    usage
    exit 64
  fi
  task_workdir="$2"
  shift 2
fi

if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ $# -eq 0 || -z "${OHOS_FLUTTER:-}" ]]; then
  usage
  exit 64
fi

if [[ "$OHOS_FLUTTER" != /* || ! -x "$OHOS_FLUTTER" ]]; then
  echo "OHOS_FLUTTER must point to an executable absolute path."
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(cd "$script_dir/.." && pwd)"
if [[ "$task_workdir" == /* || "$task_workdir" == *".."* ]]; then
  echo "--workdir must be a repository-relative path without '..'."
  exit 64
fi
if [[ ! -d "$repository_dir/$task_workdir" ]]; then
  echo "Work directory does not exist: $task_workdir"
  exit 66
fi

temporary_base="${TMPDIR:-/tmp}"
temporary_base="${temporary_base%/}"
temporary_root="$(mktemp -d "$temporary_base/webview_all_ohos.XXXXXX")"
cleanup() {
  if [[ -d "$temporary_root" &&
        "$temporary_root" == "$temporary_base"/webview_all_ohos.* ]]; then
    rm -rf -- "$temporary_root"
  else
    echo "Refusing to remove an unexpected temporary path: $temporary_root"
  fi
}
trap cleanup EXIT INT TERM

temporary_repository="$temporary_root/repository"
rsync -a \
  --exclude=".git/" \
  --exclude=".dart_tool/" \
  --exclude="build/" \
  --exclude="node_modules/" \
  --exclude="oh_modules/" \
  --exclude=".hvigor/" \
  "$repository_dir/" "$temporary_repository/"

temporary_repository="$(
  cd "$temporary_repository"
  pwd -P
)"
temporary_workdir="$(
  cd "$temporary_repository/$task_workdir"
  pwd -P
)"
if [[ "$temporary_workdir" != "$temporary_repository" &&
      "$temporary_workdir" != "$temporary_repository/"* ]]; then
  echo "The copied work directory resolves outside the temporary repository."
  exit 66
fi

cd "$temporary_workdir"
"$OHOS_FLUTTER" "$@"
