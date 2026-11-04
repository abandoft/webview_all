import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


TOOLS = Path(__file__).resolve().parent
FAKE = '''#!/usr/bin/env python3
import os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
state = pathlib.Path(os.environ['FAKE_STATE'])
if name == 'sdkmanager':
    if '--licenses' in sys.argv:
        sys.exit(int(os.environ.get('LICENSE_STATUS', '0')))
    attempt = int(state.read_text()) + 1 if state.exists() else 1
    state.write_text(str(attempt))
    sys.exit(0 if attempt >= int(os.environ['SDK_SUCCESS_AT']) else 1)
if name == 'sleep':
    sys.exit(0)
if name == 'adb':
    if 'logcat' in sys.argv:
        state.with_suffix('.logcat').touch()
        print('native startup diagnostic', flush=True)
        time.sleep(60)
    else:
        print('native diagnostic snapshot')
    sys.exit(0)
state.write_text(state.read_text() + 'test\\n' if state.exists() else 'test\\n')
for _ in range(100):
    if state.with_suffix('.logcat').exists():
        break
    time.sleep(0.01)
sys.exit(int(os.environ.get('TEST_STATUS', '0')))
'''


class AndroidIntegrationRunnerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ['sdkmanager', 'sleep', 'adb', 'flutter']:
            file = self.root / name
            file.write_text(FAKE)
            file.chmod(0o700)
        self.state = self.root / 'calls'
        test_path = os.pathsep.join([str(self.root), str(Path(sys.executable).parent), os.defpath])
        self.env = dict(os.environ, PATH=test_path,
                        RUNNER_TEMP=str(self.root), FAKE_STATE=str(self.state))

    def run_tool(self, name, *args):
        return subprocess.run(['bash', str(TOOLS / name), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_image_install_recovers_on_third_attempt(self):
        self.env['SDK_SUCCESS_AT'] = '3'
        self.assertEqual(self.run_tool('prepare_android_test_image.sh').returncode, 0)
        self.assertEqual(self.state.read_text(), '3')

    def test_image_install_failure_is_bounded(self):
        self.env['SDK_SUCCESS_AT'] = '4'
        self.assertNotEqual(self.run_tool('prepare_android_test_image.sh').returncode, 0)
        self.assertEqual(self.state.read_text(), '3')

    def test_sdk_tools_resolve_from_android_home_when_absent_from_path(self):
        tools = self.root / 'android-sdk/cmdline-tools/latest/bin'
        tools.mkdir(parents=True)
        (self.root / 'sdkmanager').rename(tools / 'sdkmanager')
        self.env.pop('ANDROID_SDK_ROOT', None)
        self.env['ANDROID_HOME'] = str(self.root / 'android-sdk')
        self.env['SDK_SUCCESS_AT'] = '1'
        result = self.run_tool('prepare_android_test_image.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), '1')

    def test_license_failure_is_reported_before_installation(self):
        self.env['LICENSE_STATUS'] = '2'
        self.assertEqual(self.run_tool('prepare_android_test_image.sh').returncode, 2)
        self.assertFalse(self.state.exists())

    def test_test_failure_is_not_retried_or_masked(self):
        self.env['TEST_STATUS'] = '71'
        result = self.run_tool('run_android_integration_test.sh', 'integration_test/resource_test.dart')
        self.assertEqual(result.returncode, 71, result.stderr)
        self.assertEqual(self.state.read_text(), 'test\n')
        logs = self.root / 'webview-all-android-diagnostics/resource_test'
        self.assertIn('native startup', (logs / 'logcat.txt').read_text())
        self.assertTrue((logs / 'process-exits.txt').is_file())

    def test_success_survives_logcat_cleanup(self):
        result = self.run_tool('run_android_integration_test.sh', 'integration_test/resource_test.dart')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), 'test\n')


if __name__ == '__main__':
    unittest.main()
