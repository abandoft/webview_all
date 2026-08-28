#!/usr/bin/env python3

"""Normalizes generated Pigeon channels to webview_all-owned namespaces."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class NamespaceTarget:
    package: str
    generated_files: tuple[str, ...]

    @property
    def generated_namespace(self) -> str:
        return f"dev.flutter.pigeon.{self.package}"

    @property
    def owned_namespace(self) -> str:
        return f"com.abandoft.pigeon.{self.package}"


TARGETS = {
    "android": NamespaceTarget(
        package="webview_all_android",
        generated_files=(
            "lib/src/android_webkit.g.dart",
            "android/src/main/java/com/abandoft/webview_all_android/AndroidWebkitLibrary.g.kt",
        ),
    ),
    "wkwebview": NamespaceTarget(
        package="webview_all_wkwebview",
        generated_files=(
            "lib/src/common/web_kit.g.dart",
            "darwin/webview_all_wkwebview/Sources/webview_all_wkwebview/WebKitLibrary.g.swift",
        ),
    ),
    "windows": NamespaceTarget(
        package="webview_all_windows",
        generated_files=(
            "lib/src/windows_webview_api.g.dart",
            "windows/generated/windows_webview_api.g.cpp",
            "windows/generated/windows_webview_api.g.h",
        ),
    ),
}


def normalize(repository_root: Path, target: NamespaceTarget) -> None:
    package_root = repository_root / target.package
    owned_count = 0
    for relative_path in target.generated_files:
        generated_file = package_root / relative_path
        contents = generated_file.read_text(encoding="utf-8")
        normalized_contents = contents.replace(
            target.generated_namespace, target.owned_namespace
        )
        if normalized_contents != contents:
            generated_file.write_text(normalized_contents, encoding="utf-8")
        owned_count += normalized_contents.count(target.owned_namespace)

    if owned_count == 0:
        raise RuntimeError(
            f"No Pigeon channels were found for {target.package}; verify the "
            "generated file list."
        )


def check(repository_root: Path, target: NamespaceTarget) -> None:
    package_root = repository_root / target.package
    combined_contents = "".join(
        (package_root / relative_path).read_text(encoding="utf-8")
        for relative_path in target.generated_files
    )
    if target.generated_namespace in combined_contents:
        raise RuntimeError(
            f"Generated bindings for {target.package} still contain "
            f"{target.generated_namespace!r}."
        )
    if target.owned_namespace not in combined_contents:
        raise RuntimeError(
            f"Generated bindings for {target.package} do not contain "
            f"{target.owned_namespace!r}."
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify generated namespaces without modifying bindings.",
    )
    parser.add_argument(
        "targets",
        choices=(*TARGETS, "all"),
        nargs="*",
        default=("all",),
    )
    arguments = parser.parse_args()

    repository_root = Path(__file__).resolve().parent.parent
    selected_targets = (
        TARGETS.values()
        if "all" in arguments.targets
        else (TARGETS[name] for name in arguments.targets)
    )
    for target in selected_targets:
        if arguments.check:
            check(repository_root, target)
        else:
            normalize(repository_root, target)


if __name__ == "__main__":
    main()
