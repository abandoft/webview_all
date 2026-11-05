#!/usr/bin/env python3
"""Create an owned simulator on the newest available iOS runtime."""
import json
import re
import subprocess
import sys


def create(name):
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
        text=True, timeout=60))['devices']
    candidates = []
    for runtime, group in devices.items():
        match = re.search(r'\.iOS-(\d+(?:-\d+)*)$', runtime)
        if match:
            version = tuple(map(int, match.group(1).split('-')))
            candidates.extend((version, runtime, device['deviceTypeIdentifier'])
                              for device in group if device['name'].startswith('iPhone'))
    if not candidates:
        raise SystemExit('No available iOS simulator')
    _, runtime, device_type = max(candidates, key=lambda candidate: candidate[0])
    simulator = subprocess.check_output(
        ['xcrun', 'simctl', 'create', name, device_type, runtime],
        text=True, timeout=120).strip()
    if not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', simulator):
        raise SystemExit('Invalid created simulator identifier')
    return simulator


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Specify a simulator name')
    print(create(sys.argv[1]))
