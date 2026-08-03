#!/usr/bin/env python3

import hashlib
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


def fail(message: str, exit_code: int = 66) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(exit_code)


def object_block(project: str, object_id: str) -> re.Match[str]:
    match = re.search(
        rf"^\t\t{re.escape(object_id)} /\* [^\n]* \*/ = "
        r"\{(?:[^\n]*\};|\n.*?^\t\t\};)\n?",
        project,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        fail(f"Xcode project object does not exist: {object_id}")
    return match


def target_sources_phase(project: str, target_name: str) -> str:
    for match in re.finditer(
        r"^\t\t([A-F0-9]{24}) /\* [^\n]* \*/ = \{\n(.*?)^\t\t\};$",
        project,
        re.MULTILINE | re.DOTALL,
    ):
        body = match.group(2)
        if "isa = PBXNativeTarget;" not in body:
            continue
        name_match = re.search(r"^\s*name = (.+);$", body, re.MULTILINE)
        if name_match is None or name_match.group(1).strip('"') != target_name:
            continue

        phases_match = re.search(
            r"^\s*buildPhases = \(\n(.*?)^\s*\);$",
            body,
            re.MULTILINE | re.DOTALL,
        )
        if phases_match is None:
            fail(f"Xcode target has no build phases: {target_name}")
        for phase_id in re.findall(r"\b[A-F0-9]{24}\b", phases_match.group(1)):
            if "isa = PBXSourcesBuildPhase;" in object_block(project, phase_id).group(0):
                return phase_id
        fail(f"Xcode target has no sources build phase: {target_name}")

    fail(f"Xcode target does not exist: {target_name}")


def stable_object_id(kind: str, value: str) -> str:
    return hashlib.sha1(f"{kind}:{value}".encode()).hexdigest()[:24].upper()


def quoted_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def insert_before(project: str, marker: str, entries: list[str]) -> str:
    if not entries:
        return project
    marker_index = project.find(marker)
    if marker_index < 0:
        fail(f"Xcode project section marker does not exist: {marker}")
    return project[:marker_index] + "".join(entries) + project[marker_index:]


def write_atomically(path: Path, content: str) -> None:
    original_mode = stat.S_IMODE(path.stat().st_mode)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as temporary:
            temporary.write(content)
            temporary_name = temporary.name
        os.chmod(temporary_name, original_mode)
        os.replace(temporary_name, path)
        temporary_name = None
    finally:
        if temporary_name is not None:
            Path(temporary_name).unlink(missing_ok=True)


def main() -> None:
    if len(sys.argv) != 4:
        fail(
            "Usage: add_swift_tests_to_xcode_target.py "
            "PROJECT TARGET TESTS_DIRECTORY",
            64,
        )

    project_path = Path(sys.argv[1]).expanduser().resolve()
    target_name = sys.argv[2]
    tests_directory = Path(sys.argv[3]).expanduser().resolve()
    project_file = project_path / "project.pbxproj"

    if not project_path.is_dir() or not project_file.is_file():
        fail(f"Xcode project does not exist: {project_path}")
    if not tests_directory.is_dir():
        fail(f"Swift tests directory does not exist: {tests_directory}")

    test_files = sorted(tests_directory.rglob("*.swift"))
    if not test_files:
        fail(f"No Swift tests found in: {tests_directory}")

    project = project_file.read_text(encoding="utf-8")
    sources_phase_id = target_sources_phase(project, target_name)
    build_entries: list[str] = []
    reference_entries: list[str] = []
    source_entries: list[str] = []

    for test_file in test_files:
        name = test_file.name
        relative_path = os.path.relpath(test_file, project_path.parent)
        reference_id = stable_object_id("file-reference", relative_path)
        build_id = stable_object_id(
            "build-file",
            f"{target_name}:{relative_path}",
        )
        encoded_path = quoted_value(relative_path)

        if reference_id in project:
            reference = object_block(project, reference_id).group(0)
            if (
                "isa = PBXFileReference;" not in reference
                or f'path = "{encoded_path}";' not in reference
            ):
                fail(f"Xcode object ID collision: {reference_id}")
        else:
            reference_entries.append(
                f"\t\t{reference_id} /* {name} */ = "
                "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
                f'path = "{encoded_path}"; sourceTree = SOURCE_ROOT; }};\n'
            )
        if build_id in project:
            build = object_block(project, build_id).group(0)
            if (
                "isa = PBXBuildFile;" not in build
                or f"fileRef = {reference_id} " not in build
            ):
                fail(f"Xcode object ID collision: {build_id}")
        else:
            build_entries.append(
                f"\t\t{build_id} /* {name} in Sources */ = "
                f"{{isa = PBXBuildFile; fileRef = {reference_id} /* {name} */; }};\n"
            )
        source_entries.append(f"\t\t\t\t{build_id} /* {name} in Sources */,\n")

    project = insert_before(
        project,
        "/* End PBXBuildFile section */",
        build_entries,
    )
    project = insert_before(
        project,
        "/* End PBXFileReference section */",
        reference_entries,
    )

    phase_match = object_block(project, sources_phase_id)
    phase = phase_match.group(0)
    files_end = phase.find("\t\t\t);")
    if files_end < 0:
        fail(f"Sources build phase has no files list: {sources_phase_id}")
    missing_sources = [
        entry for entry in source_entries if entry.strip() not in phase
    ]
    if missing_sources:
        phase = phase[:files_end] + "".join(missing_sources) + phase[files_end:]
        project = project[: phase_match.start()] + phase + project[phase_match.end() :]

    original = project_file.read_text(encoding="utf-8")
    if project != original:
        write_atomically(project_file, project)
        print(f"Attached {len(test_files)} Swift test files to {target_name}.")
    else:
        print(f"Swift test files are already attached to {target_name}.")


if __name__ == "__main__":
    main()
