import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/core/instance_manager.dart';

class _CopyableObject with Copyable {
  const _CopyableObject(this.value);

  final String value;

  @override
  _CopyableObject copy() => _CopyableObject(value);
}

void main() {
  test('native disposal retires live and detached references', () {
    final List<int> releases = <int>[];
    final InstanceManager manager = InstanceManager(
      onWeakReferenceRemoved: releases.add,
    );
    const _CopyableObject instance = _CopyableObject('original');
    manager.addHostCreatedInstance(instance, 65536);

    final _CopyableObject? detached = manager.remove<_CopyableObject>(65536);

    expect(detached?.value, 'original');
    expect(manager.containsIdentifier(65536), isFalse);
    expect(manager.getIdentifier(instance), isNull);
    expect(manager.getIdentifier(detached!), isNull);
    expect(
      manager.getInstanceWithWeakReference<_CopyableObject>(65536),
      isNull,
    );
    expect(manager.removeWeakReference(instance), isNull);
    expect(releases, isEmpty);
  });

  test('removing an old object cannot release a reused host identifier', () {
    final List<int> releases = <int>[];
    final InstanceManager manager = InstanceManager(
      onWeakReferenceRemoved: releases.add,
    );
    const _CopyableObject oldInstance = _CopyableObject('old');
    const _CopyableObject newInstance = _CopyableObject('new');
    manager.addHostCreatedInstance(oldInstance, 65536);
    manager.remove(65536);
    manager.addHostCreatedInstance(newInstance, 65536);

    expect(manager.removeWeakReference(oldInstance), isNull);
    expect(
      manager.getInstanceWithWeakReference<_CopyableObject>(65536),
      same(newInstance),
    );
    expect(manager.getIdentifier(newInstance), 65536);
    expect(releases, isEmpty);
  });

  test('releases each weak copy once until native disposal is confirmed', () {
    final List<int> releases = <int>[];
    final InstanceManager manager = InstanceManager(
      onWeakReferenceRemoved: releases.add,
    );
    const _CopyableObject instance = _CopyableObject('copyable');
    manager.addHostCreatedInstance(instance, 65536);

    expect(manager.removeWeakReference(instance), 65536);
    expect(manager.removeWeakReference(instance), isNull);
    final _CopyableObject recreated = manager
        .getInstanceWithWeakReference<_CopyableObject>(65536)!;
    expect(recreated, isNot(same(instance)));
    expect(manager.getIdentifier(recreated), 65536);
    manager.remove(65536);

    expect(manager.removeWeakReference(recreated), isNull);
    expect(
      manager.getInstanceWithWeakReference<_CopyableObject>(65536),
      isNull,
    );
    expect(releases, <int>[65536]);
  });

  test('rejects invalid registrations without replacing a live instance', () {
    final InstanceManager manager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    const _CopyableObject instance = _CopyableObject('original');
    const _CopyableObject other = _CopyableObject('other');
    expect(
      () => manager.addHostCreatedInstance(instance, -1),
      throwsArgumentError,
    );
    manager.addHostCreatedInstance(instance, 65536);

    expect(
      () => manager.addHostCreatedInstance(other, 65536),
      throwsStateError,
    );
    expect(
      () => manager.addHostCreatedInstance(instance, 65537),
      throwsStateError,
    );
    expect(
      manager.getInstanceWithWeakReference<_CopyableObject>(65536),
      same(instance),
    );
    expect(manager.getIdentifier(other), isNull);
    expect(manager.containsIdentifier(65537), isFalse);
  });
}
