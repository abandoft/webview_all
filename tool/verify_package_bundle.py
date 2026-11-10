#!/usr/bin/env python3
"""Validate a clean package snapshot in a fresh hosted consumer.

Requires Python 3.10+, PyYAML, and Flutter. Uses publish --dry-run only: nothing
is uploaded. The localhost package server serves the selected files and forwards
public third-party package metadata to pub.dev. All build/cache files are kept
in a temporary directory. Run from any directory with --flutter /path/to/flutter.
"""
from __future__ import annotations

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import threading
from urllib.request import urlopen
import yaml

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ['webview_platform_interface', 'webview_all_android',
            'webview_all_wkwebview', 'webview_all_windows', 'webview_all_linux',
            'webview_all_ohos', 'webview_all_web', 'webview_all']


def run(command: list[str], cwd: Path, env: dict[str, str], log: Path) -> None:
    result = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=600)
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f'{command[-1]} failed; see {log}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default='flutter')
    args = parser.parse_args()
    flutter = args.flutter
    manifests = {name: yaml.safe_load((ROOT / name / 'pubspec.yaml').read_text())
                 for name in PACKAGES}
    versions = {spec['version'] for spec in manifests.values()}
    if len(versions) != 1:
        raise RuntimeError('Owned packages must use one release version.')
    version = versions.pop()
    for name, spec in manifests.items():
        for dependency, constraint in spec.get('dependencies', {}).items():
            if dependency in PACKAGES and constraint != f'^{version}':
                raise RuntimeError(f'{name}: {dependency} must require ^{version}')
    with tempfile.TemporaryDirectory(prefix='webview-package-bundle-') as directory:
        work = Path(directory)
        env = dict(os.environ, CI='true')
        archives = {}
        # Pub validation may resolve development dependencies. Isolate it from
        # workspace package_config/lock files, including when testing another SDK.
        snapshot = work / 'source'
        selected = subprocess.check_output(
            ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT
        ).decode().split('\0')
        for relative in selected:
            if not relative or Path(relative).parts[0] not in PACKAGES:
                continue
            source = ROOT / relative
            if source.is_file():
                target = snapshot / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
        for name in PACKAGES:
            dependencies = {dep: {'path': '../' + dep}
                            for dep in manifests[name].get('dependencies', {}) if dep in PACKAGES}
            if dependencies:
                # Preview only: these unpublished siblings are resolved locally.
                # Pub must exclude this file from the served archive, and the
                # consumer below resolves every sibling through hosted metadata.
                (snapshot / name / 'pubspec_overrides.yaml').write_text(
                    yaml.safe_dump({'dependency_overrides': dependencies}))
        for name in PACKAGES:
            package = snapshot / name
            # Pub chooses files using .pubignore and its built-in exclusions.
            # A not-yet-published dependency can fail validation after the list
            # is generated; this check independently resolves the whole bundle.
            preview = subprocess.run([flutter, 'pub', 'publish', '--dry-run', '--verbose'],
                                     cwd=package, env=env, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, timeout=300)
            (work / f'{name}-preview.log').write_text(preview.stdout)
            marker = 'Creating .tar.gz stream containing:\n'
            if marker not in preview.stdout:
                raise RuntimeError(f'{name}: pub did not report its archive file list.')
            block = preview.stdout.split(marker, 1)[1]
            files = []
            for line in block.splitlines():
                if not line.startswith('    | '):
                    break
                path = Path(line[6:])
                if not path.is_absolute():
                    path = package / path
                if path.is_file():
                    relative = path.relative_to(package)
                    if path.is_symlink() or not path.resolve().is_relative_to(package.resolve()):
                        raise RuntimeError(f'{name}: archive source escapes its package: {relative}')
                    if relative.name in ('pubspec_overrides.yaml', 'local.properties') or any(
                            part in ('FORME', '.dart_tool', 'Pods', 'oh_modules', 'ephemeral') for part in relative.parts):
                        raise RuntimeError(f'{name}: local-only file selected by pub: {relative}')
                    files.append(relative)
            required = {'pubspec.yaml', 'LICENSE', 'README.md', 'CHANGELOG.md', f'lib/{name}.dart'}
            if not required.issubset({str(path) for path in files}):
                raise RuntimeError(f'{name}: required public package files are missing.')
            published = set(files)
            for tree in ('lib', 'android/src/main', 'windows/src', 'windows/include',
                         'linux/src', 'linux/include', 'ohos/src/main',
                         'darwin/webview_all_wkwebview/Sources'):
                for runtime in (package / tree).rglob('*'):
                    if runtime.is_file() and runtime.relative_to(package) not in published:
                        raise RuntimeError(f'{name}: runtime source missing from pub archive: {runtime.relative_to(package)}')
            archive = work / f'{name}-{version}.tar.gz'
            with tarfile.open(archive, 'w:gz') as output:
                for path in files:
                    output.add(package / path, arcname=str(path), recursive=False)
            archives[name] = archive.read_bytes()
            print(f'{name} {version}: {len(files)} pub-selected files', flush=True)

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                try:
                    archive = re.fullmatch(r'/api/archives/([a-z_]+)-' + re.escape(version) + r'\.tar\.gz', self.path)
                    package = re.fullmatch(r'/api/packages/([a-z_]+)', self.path)
                    if archive and archive[1] in archives:
                        body = archives[archive[1]]; content_type = 'application/octet-stream'
                    elif package and package[1] in manifests:
                        name = package[1]
                        item = {'version': version, 'pubspec': manifests[name],
                                'archive_url': f'http://127.0.0.1:{self.server.server_port}/api/archives/{name}-{version}.tar.gz',
                                'archive_sha256': hashlib.sha256(archives[name]).hexdigest(),
                                'published': '2026-01-01T00:00:00.000Z'}
                        body = json.dumps({'name': name, 'latest': item, 'versions': [item]}).encode()
                        content_type = 'application/json'
                    elif self.path.startswith('/api/packages/'):
                        # Public package metadata only; never forward credentials.
                        with urlopen('https://pub.dev' + self.path, timeout=60) as response:
                            body = response.read(); content_type = 'application/json'
                    else:
                        self.send_error(404); return
                    self.send_response(200)
                    self.send_header('Content-Type', content_type)
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers(); self.wfile.write(body)
                except Exception:
                    self.send_error(502)

            def log_message(self, *_: object) -> None:
                pass

        class BundleServer(ThreadingHTTPServer):
            # Pub can fetch many dependency/version records concurrently.
            # Base HTTPServer's five-connection backlog can reset these local
            # connections even though each handler succeeds.
            request_queue_size = 128
            daemon_threads = True

        server = BundleServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        consumer = work / 'consumer'; consumer.mkdir()
        (consumer / 'pubspec.yaml').write_text(f'''name: webview_bundle_consumer
publish_to: none
environment:
  sdk: '>=3.9.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  webview_all: ^{version}
dev_dependencies:
  flutter_test:
    sdk: flutter
''')
        (consumer / 'lib').mkdir(); (consumer / 'test').mkdir()
        (consumer / 'lib/main.dart').write_text('''import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';
void main() => runApp(const SizedBox.shrink());
final manager = WebViewProfileManager();
final screenshot = WebViewScreenshotOptions(fullDocument: true);
final rule = WebViewContentRule(urlPattern: '*',
    action: WebViewContentRuleAction.hideElements, selector: '.ad',
    loadTypes: {WebViewContentRuleLoadType.thirdParty});
''')
        (consumer / 'test/bundle_test.dart').write_text('''import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';
void main() {
  test('new public types survive the published package boundary', () {
    expect(const WebViewProfileDeletionResult(status: WebViewProfileDeletionStatus.pending).isDeleted, isFalse);
    expect(const WebViewScreenshotOptions(fullDocument: true).fullDocument, isTrue);
    expect(WebViewContentRule(urlPattern: '*', ifDomains: ['example.com']).isValid, isTrue);
  });
}
''')
        env.update(PUB_HOSTED_URL=f'http://127.0.0.1:{server.server_port}', PUB_CACHE=str(work / 'cache'))
        try:
            run([flutter, 'pub', 'get'], consumer, env, work / 'consumer-get.log')
            lock = yaml.safe_load((consumer / 'pubspec.lock').read_text())['packages']
            for name in PACKAGES:
                resolved = lock[name]
                if resolved['source'] != 'hosted' or resolved['version'] != version:
                    raise RuntimeError(f'{name}: consumer did not resolve the hosted release bundle.')
            run([flutter, 'analyze', '--no-pub', '--fatal-infos'], consumer, env, work / 'consumer-analyze.log')
            run([flutter, 'test', '--no-pub'], consumer, env, work / 'consumer-test.log')
            print('Fresh hosted consumer: resolution, analysis and tests passed; no path overrides.', flush=True)
        except Exception:
            # Preserve only diagnostic text; package/cache files are temporary.
            diagnostic = Path(tempfile.mkdtemp(prefix='webview-bundle-failure-'))
            for log in work.glob('*.log'):
                shutil.copyfile(log, diagnostic / log.name)
            print(f'Logs: {diagnostic}', flush=True)
            raise
        finally:
            server.shutdown(); server.server_close(); thread.join()


if __name__ == '__main__':
    main()
