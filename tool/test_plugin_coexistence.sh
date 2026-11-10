#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <web|android|apple>" >&2
  exit 64
fi

target="$1"
case "$target" in
  web)
    platforms="web"
    official_dependency="webview_flutter_web:0.2.3+4"
    ;;
  android)
    platforms="android"
    official_dependency="webview_flutter:4.14.1"
    ;;
  apple)
    platforms="ios,macos"
    official_dependency="webview_flutter:4.14.1"
    ;;
  *)
    echo "Unsupported coexistence test target: $target" >&2
    exit 64
    ;;
esac

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/webview_all_coexistence.XXXXXX")"
project_directory="$temporary_root/app"

cleanup() {
  rm -rf -- "$temporary_root"
}
trap cleanup EXIT

flutter create \
  --project-name webview_all_coexistence \
  --platforms "$platforms" \
  "$project_directory"

if [[ "$target" == "apple" ]]; then
  python3 - "$project_directory" "$repository_root" <<'PY'
from pathlib import Path
import re
import shutil
import sys

project, repository = map(Path, sys.argv[1:])
for platform, setting, minimum in (
    ('ios', 'IPHONEOS_DEPLOYMENT_TARGET', (14, 0)),
    ('macos', 'MACOSX_DEPLOYMENT_TARGET', (11, 0)),
):
    target = project / platform / 'Runner.xcodeproj/project.pbxproj'
    def raise_minimum(match):
        version = tuple(map(int, match[2].split('.')))
        return match[1] + ('.'.join(map(str, minimum)) if version < minimum else match[2])
    target.write_text(re.sub(rf'({setting} = )([0-9.]+)', raise_minimum, target.read_text()))
    shutil.copyfile(repository / 'webview_all/example' / platform / 'Podfile',
                    project / platform / 'Podfile')
PY
fi

dependencies=(
  "webview_all:{path: $repository_root/webview_all}"
  "$official_dependency"
  "override:webview_platform_interface:{path: $repository_root/webview_platform_interface}"
  "override:webview_all_android:{path: $repository_root/webview_all_android}"
  "override:webview_all_wkwebview:{path: $repository_root/webview_all_wkwebview}"
  "override:webview_all_windows:{path: $repository_root/webview_all_windows}"
  "override:webview_all_linux:{path: $repository_root/webview_all_linux}"
  "override:webview_all_web:{path: $repository_root/webview_all_web}"
  "override:webview_all_ohos:{path: $repository_root/webview_all_ohos}"
)
dart pub add \
  --directory "$project_directory" \
  --no-example \
  "${dependencies[@]}"

case "$target" in
  web)
    (
      cd "$project_directory"
      flutter build web
    )
    ;;
  android)
    (
      cd "$project_directory"
      flutter build apk --debug --target-platform android-arm64
    )
    ;;
  apple)
    (
      cd "$project_directory"
      flutter build ios --simulator --debug
      flutter build macos --debug
    )
    ;;
esac
