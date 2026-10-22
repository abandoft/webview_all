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

class _WeakReferenceToken {
  const _WeakReferenceToken(this.identifier);

  final int identifier;
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
    _finalizer = Finalizer<_WeakReferenceToken>(_releaseWeakReference);
  }

  static const int _maxDartCreatedIdentifier = 65536;

  final void Function(int) _nativeDispose;
  final Expando<int> _identifiers = Expando<int>();
  final Map<int, WeakReference<Copyable>> _weakInstances =
      <int, WeakReference<Copyable>>{};
  final Map<int, Copyable> _strongCopies = <int, Copyable>{};
  final Map<int, _WeakReferenceToken> _weakReferenceTokens =
      <int, _WeakReferenceToken>{};
  late final Finalizer<_WeakReferenceToken> _finalizer;
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
    if (identifier == null ||
        !identical(_weakInstances[identifier]?.target, instance)) {
      return null;
    }

    _identifiers[instance] = null;
    _finalizer.detach(instance);
    _releaseWeakReference(_weakReferenceTokens[identifier]!);
    return identifier;
  }

  /// Removes all references after the native instance has been released.
  ///
  /// A callback received after this point must not recreate a disposed object.
  T? remove<T extends Copyable>(int identifier) {
    final Copyable? weakInstance = _weakInstances.remove(identifier)?.target;
    if (weakInstance != null) {
      _identifiers[weakInstance] = null;
      _finalizer.detach(weakInstance);
    }
    _weakReferenceTokens.remove(identifier);
    final Copyable? strongCopy = _strongCopies.remove(identifier);
    if (strongCopy != null) {
      _identifiers[strongCopy] = null;
    }
    return strongCopy as T?;
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
    _attachWeakReference(weakCopy, identifier);
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
    if (identifier < 0) {
      throw ArgumentError.value(
        identifier,
        'identifier',
        'Must be nonnegative.',
      );
    }
    if (containsIdentifier(identifier)) {
      throw StateError(
        'OHOS instance identifier is already registered: $identifier.',
      );
    }
    if (getIdentifier(instance) != null) {
      throw StateError('The OHOS instance is already registered.');
    }

    _identifiers[instance] = identifier;
    _attachWeakReference(instance, identifier);

    final Copyable strongCopy = instance.copy();
    _identifiers[strongCopy] = identifier;
    _strongCopies[identifier] = strongCopy;
  }

  void _attachWeakReference(Copyable instance, int identifier) {
    final _WeakReferenceToken token = _WeakReferenceToken(identifier);
    _weakInstances[identifier] = WeakReference<Copyable>(instance);
    _weakReferenceTokens[identifier] = token;
    _finalizer.attach(instance, token, detach: instance);
  }

  void _releaseWeakReference(_WeakReferenceToken token) {
    final int identifier = token.identifier;
    // A callback may have recreated a weak copy before an older finalizer runs.
    // Only the token for the currently registered weak copy may release it.
    if (!identical(_weakReferenceTokens[identifier], token)) {
      return;
    }
    _weakReferenceTokens.remove(identifier);
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
