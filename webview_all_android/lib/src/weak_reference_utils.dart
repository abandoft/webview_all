// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Creates a value with a weak reference to [reference].
///
/// This avoids retaining [reference] through closures stored by longer-lived
/// platform objects.
S withWeakReferenceTo<T extends Object, S extends Object>(
  T reference,
  S Function(WeakReference<T> weakReference) onCreate,
) {
  final weakReference = WeakReference<T>(reference);
  return onCreate(weakReference);
}
