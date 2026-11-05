import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
FAKE = '''#!/usr/bin/env python3
import json,os,pathlib,sys
root=pathlib.Path(os.environ['FAKE_STATE'])
if pathlib.Path(sys.argv[0]).name=='sleep':
    with (root/'sleeps').open('a') as f:f.write(sys.argv[1]+'\\n')
    sys.exit(0)
with (root/'calls').open('a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
attempt=len((root/'calls').read_text().splitlines())
mode=os.environ['FAILURE_MODE']
if mode=='success' or mode=='transient' and attempt==2:sys.exit(0)
print('FAILURE: Build failed with an exception.')
if mode in ['transient','persistent','mixed']:
    print('Could not GET compiler.jar: HTTP 504')
    print('[!] Gradle threw an error while downloading artifacts from the network.')
if mode in ['compiler','mixed']:
    print('FAILURE: Build failed with an exception.')
    print('Compilation failed: unresolved symbol')
sys.exit(71)
'''


class AndroidBuildRunnerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ['flutter', 'sleep']:
            p = self.root / name
            p.write_text(FAKE)
            p.chmod(0o700)
        self.env = dict(os.environ, RUNNER_TEMP=str(self.root),
                        FAKE_STATE=str(self.root),
                        PATH=os.pathsep.join([str(self.root), str(Path(sys.executable).parent), os.defpath]))

    def run_build(self, mode, *args):
        return subprocess.run(['bash', str(TOOLS / 'build_android_example.sh'), *args],
                              env=dict(self.env, FAILURE_MODE=mode),
                              capture_output=True, text=True, timeout=10)

    def calls(self):
        return [json.loads(x) for x in (self.root / 'calls').read_text().splitlines()]

    def test_success_preserves_build_arguments(self):
        self.assertEqual(self.run_build('success', '--target-platform', 'android-arm64').returncode, 0)
        self.assertEqual(self.calls(), [['build', 'apk', '--debug', '--target-platform', 'android-arm64']])

    def test_transient_download_recovers_and_retains_first_failure(self):
        result = self.run_build('transient')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 2)
        self.assertEqual((self.root / 'sleeps').read_text(), '5\n')
        first = next(self.root.glob('webview-all-android-build.*/attempt-1.log'))
        self.assertIn('HTTP 504', first.read_text())

    def test_persistent_download_failure_is_bounded_and_preserves_status(self):
        self.assertEqual(self.run_build('persistent').returncode, 71)
        self.assertEqual(len(self.calls()), 3)
        self.assertEqual((self.root / 'sleeps').read_text(), '5\n10\n')

    def test_compilation_failure_is_never_retried(self):
        self.assertEqual(self.run_build('compiler').returncode, 71)
        self.assertEqual(len(self.calls()), 1)
        self.assertFalse((self.root / 'sleeps').exists())

    def test_final_compilation_failure_overrides_earlier_download_failure(self):
        self.assertEqual(self.run_build('mixed').returncode, 71)
        self.assertEqual(len(self.calls()), 1)
        self.assertFalse((self.root / 'sleeps').exists())


if __name__ == '__main__':
    unittest.main()
