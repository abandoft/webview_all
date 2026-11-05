import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
FAKE = '''#!/usr/bin/env python3
import json,os,pathlib,sys,time
root=pathlib.Path(os.environ['FAKE_STATE'])
args=sys.argv[1:]
name=pathlib.Path(sys.argv[0]).name
with (root/'calls').open('a') as f: f.write(json.dumps([name,*args])+'\\n')
if name in ['flutter','xcodebuild']:
    for _ in range(100):
        if (root/'logging').exists(): break
        time.sleep(.01)
    print(name+' diagnostic',flush=True)
    sys.exit(int(os.environ.get('BUILD_STATUS' if name=='flutter' else 'TEST_STATUS','0')))
if args[:3]==['simctl','list','devices']:
    print((root/'devices.json').read_text());sys.exit(0)
if args[:2]==['simctl','create']:
    counter=root/'counter';value=int(counter.read_text())+1 if counter.exists() else 1
    counter.write_text(str(value));print('00000000-0000-0000-0000-'+str(value).zfill(12));sys.exit(0)
if args[:2] in [['simctl','boot'],['simctl','bootstatus']]:
    sys.exit(int(os.environ.get('BOOT_STATUS','0')))
if args[:2]==['simctl','spawn']:
    (root/'logging').touch();print('Native startup diagnostic',flush=True);time.sleep(60)
sys.exit(0)
'''


class IOSIntegrationRunnerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'pubspec.yaml').write_text('name: fixture\n')
        (self.root / 'integration_test').mkdir()
        (self.root / 'integration_test/resource_test.dart').touch()
        for name in ['xcrun', 'flutter', 'ruby', 'xcodebuild']:
            file = self.root / name
            file.write_text(FAKE)
            file.chmod(0o700)
        devices = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-4': [
                {'name': 'iPhone old', 'deviceTypeIdentifier': 'old-phone'}],
            'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
                {'name': 'iPhone new', 'deviceTypeIdentifier': 'new-phone'},
                {'name': 'iPhone small', 'deviceTypeIdentifier': 'zz-small-phone'}],
            'com.apple.CoreSimulator.SimRuntime.watchOS-30-0': [
                {'name': 'Watch', 'deviceTypeIdentifier': 'watch'}],
        }}
        (self.root / 'devices.json').write_text(json.dumps(devices))
        test_path = os.pathsep.join([str(self.root), str(Path(sys.executable).parent), os.defpath])
        self.env = dict(os.environ, PATH=test_path, FAKE_STATE=str(self.root),
                        RUNNER_TEMP=str(self.root))

    def run_test(self, simulator=None):
        return subprocess.run(['bash', str(TOOLS / 'run_ios_integration_test.sh'),
                               'integration_test/resource_test.dart',
                               *([simulator] if simulator is not None else [])],
                              cwd=self.root, env=self.env, capture_output=True, text=True, timeout=15)

    def calls(self):
        return [json.loads(line) for line in (self.root / 'calls').read_text().splitlines()]

    def test_fresh_simulator_uses_latest_ios_and_is_deleted_after_success(self):
        result = self.run_test()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        creation = next(c for c in calls if c[1:3] == ['simctl', 'create'])
        self.assertEqual(creation[-2:], ['new-phone', 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'])
        flutter = next(c for c in calls if c[0] == 'flutter')
        native = next(c for c in calls if c[0] == 'xcodebuild')
        simulator = native[native.index('-destination') + 1].split('id=')[1]
        self.assertIn(['xcrun', 'simctl', 'shutdown', simulator], calls)
        self.assertIn(['xcrun', 'simctl', 'delete', simulator], calls)
        self.assertIn('--config-only', flutter)
        self.assertNotIn('test', flutter)
        self.assertEqual(native[1], 'test')
        self.assertIn('-test-timeouts-enabled', native)

    def test_test_failure_is_not_retried_or_masked_and_retains_logs(self):
        self.env['TEST_STATUS'] = '71'
        result = self.run_test()
        self.assertEqual(result.returncode, 71, result.stderr)
        self.assertEqual(sum(c[0] == 'xcodebuild' for c in self.calls()), 1)
        logs = self.root / 'webview-all-ios-diagnostics/resource_test'
        self.assertIn('flutter diagnostic', (logs / 'flutter-config.log').read_text())
        self.assertIn('xcodebuild diagnostic', (logs / 'xcodebuild.log').read_text())
        self.assertIn('Native startup diagnostic', (logs / 'device.log').read_text())
        self.assertTrue((logs / 'devices.json').is_file())

    def test_boot_failure_does_not_launch_tests_and_still_deletes_owned_device(self):
        self.env['BOOT_STATUS'] = '72'
        result = self.run_test()
        self.assertEqual(result.returncode, 72, result.stderr)
        calls = self.calls()
        self.assertFalse(any(c[0] == 'flutter' for c in calls))
        self.assertTrue(any(c[1:3] == ['simctl', 'delete'] for c in calls))

    def test_missing_ios_runtime_fails_before_creation(self):
        (self.root / 'devices.json').write_text('{"devices": {}}')
        result = self.run_test()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No available iOS simulator', result.stderr)
        self.assertFalse(any(c[1:3] == ['simctl', 'create'] for c in self.calls()))

    def test_wrong_working_directory_fails_before_touching_a_simulator(self):
        (self.root / 'pubspec.yaml').unlink()
        result = self.run_test()
        self.assertEqual(result.returncode, 66)
        self.assertIn('example directory', result.stderr)
        self.assertFalse((self.root / 'calls').exists())

    def test_each_default_invocation_creates_a_different_device(self):
        self.assertEqual(self.run_test().returncode, 0)
        self.assertEqual(self.run_test().returncode, 0)
        ids = [c[c.index('-destination') + 1] for c in self.calls() if c[0] == 'xcodebuild']
        self.assertEqual(len(set(ids)), 2)

    def test_config_failure_stops_before_xctest_and_preserves_status(self):
        self.env['BUILD_STATUS'] = '69'
        result = self.run_test()
        self.assertEqual(result.returncode, 69)
        self.assertFalse(any(c[0] == 'xcodebuild' for c in self.calls()))

    def test_caller_simulator_is_reused_and_never_deleted_even_on_failure(self):
        self.env['TEST_STATUS'] = '71'
        simulator = '11111111-1111-1111-1111-111111111111'
        result = self.run_test(simulator)
        self.assertEqual(result.returncode, 71, result.stderr)
        calls = self.calls()
        self.assertFalse(any(c[1:3] in [['simctl', 'create'], ['simctl', 'shutdown'],
                                      ['simctl', 'delete']] for c in calls))
        native = next(c for c in calls if c[0] == 'xcodebuild')
        self.assertIn('platform=iOS Simulator,id='+simulator, native)

    def test_invalid_simulator_fails_before_any_native_command(self):
        result = self.run_test('not-a-uuid')
        self.assertEqual(result.returncode, 64)
        self.assertFalse((self.root / 'calls').exists())


if __name__ == '__main__':
    unittest.main()
