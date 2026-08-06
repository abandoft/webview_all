import 'package:flutter/foundation.dart';

/// Object that can create a detached copy for native callback dispatch.
///
/// The manager stores a strong detached copy for each object so callbacks can
/// be reconstructed after the UI-facing object has been garbage collected.
@immutable
mixin Copyable {
  /// Returns a functionally equivalent detached copy of this object.
  @protected
  Copyable copy();
}

/// Keeps Dart objects and native OHOS object identifiers in sync.
///
/// Dart-created objects use identifiers below [_maxDartCreatedIdentifier].
/// Native-created objects use identifiers outside that range. Each registered
/// object has a weak UI-facing reference and a strong detached copy. When the
/// weak reference disappears, [onWeakReferenceRemoved] is invoked so the native
/// side can release its matching reference.
class InstanceManager {
  /// Creates an [InstanceManager].
  InstanceManager({required void Function(int) onWeakReferenceRemoved})
    : _nativeDispose = onWeakReferenceRemoved {
    _finalizer = Finalizer<int>(_handleFinalizedWeakReference);
  }

  static const int _maxDartCreatedIdentifier = 65536;

  final void Function(int) _nativeDispose;
  final Expando<int> _identifiers = Expando<int>();
  final Map<int, WeakReference<Copyable>> _weakInstances =
      <int, WeakReference<Copyable>>{};
  final Map<int, Copyable> _strongCopies = <int, Copyable>{};
  late final Finalizer<int> _finalizer;
  int _nextIdentifier = 0;

  /// Adds an object that Dart created and returns its generated identifier.
  int addDartCreatedInstance(Copyable instance) {
    final int identifier = _nextUniqueIdentifier();
    _addInstance(instance, identifier);
    return identifier;
  }

  /// Adds an object created by the native OHOS side.
  void addHostCreatedInstance(Copyable instance, int identifier) {
    _addInstance(instance, identifier);
  }

  /// Removes the weak reference for [instance] and requests native disposal.
  ///
  /// The strong detached copy remains available until [remove] is called.
  int? removeWeakReference(Copyable instance) {
    final int? identifier = getIdentifier(instance);
    if (identifier == null) {
      return null;
    }

    _identifiers[instance] = null;
    _finalizer.detach(instance);
    _releaseWeakReference(identifier);
    return identifier;
  }

  /// Removes the strong detached copy for [identifier].
  T? remove<T extends Copyable>(int identifier) {
    return _strongCopies.remove(identifier) as T?;
  }

  /// Returns the object for [identifier], recreating a weak copy when needed.
  T? getInstanceWithWeakReference<T extends Copyable>(int identifier) {
    final Copyable? liveInstance = _weakInstances[identifier]?.target;
    if (liveInstance != null) {
      return liveInstance as T;
    }

    final Copyable? strongCopy = _strongCopies[identifier];
    if (strongCopy == null) {
      return null;
    }

    final Copyable weakCopy = strongCopy.copy();
    _identifiers[weakCopy] = identifier;
    _weakInstances[identifier] = WeakReference<Copyable>(weakCopy);
    _finalizer.attach(weakCopy, identifier, detach: weakCopy);
    return weakCopy as T;
  }

  /// Returns the identifier assigned to [instance], if it is registered.
  int? getIdentifier(Copyable instance) {
    return _identifiers[instance];
  }

  /// Whether an object or detached copy is registered for [identifier].
  bool containsIdentifier(int identifier) {
    return _weakInstances.containsKey(identifier) ||
        _strongCopies.containsKey(identifier);
  }

  void _addInstance(Copyable instance, int identifier) {
    assert(identifier >= 0);
    assert(!containsIdentifier(identifier));
    assert(getIdentifier(instance) == null);

    _identifiers[instance] = identifier;
    _weakInstances[identifier] = WeakReference<Copyable>(instance);
    _finalizer.attach(instance, identifier, detach: instance);

    final Copyable strongCopy = instance.copy();
    _identifiers[strongCopy] = identifier;
    _strongCopies[identifier] = strongCopy;
  }

  void _handleFinalizedWeakReference(int identifier) {
    _releaseWeakReference(identifier);
  }

  void _releaseWeakReference(int identifier) {
    _weakInstances.remove(identifier);
    _nativeDispose(identifier);
  }

  int _nextUniqueIdentifier() {
    for (int attempts = 0; attempts < _maxDartCreatedIdentifier; attempts++) {
      final int identifier = _nextIdentifier;
      _nextIdentifier = (_nextIdentifier + 1) % _maxDartCreatedIdentifier;
      if (!containsIdentifier(identifier)) {
        return identifier;
      }
    }
    throw StateError(
      'No OHOS instance identifiers are available. Dispose unused objects '
      'before creating more bridge objects.',
    );
  }
}
