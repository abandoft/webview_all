import 'package:flutter/foundation.dart';

@immutable
class WebViewProfileManagementCapabilities {
  const WebViewProfileManagementCapabilities({
    this.listing = false,
    this.deletion = false,
    this.limitation,
  });
  final bool listing;
  final bool deletion;
  final String? limitation;
}

/// Plugin-owned named persistent profile. Ordinary and private stores are excluded.
@immutable
class WebViewProfileInfo {
  const WebViewProfileInfo({required this.name, this.deletionPending = false});
  final String name;
  final bool deletionPending;
}

enum WebViewProfileDeletionStatus {
  deleted,
  pending,
  busy,
  requiresRestart,
  notFound,
  unsupported,
  failed,

  /// The native outcome could not be confirmed. Query before retrying.
  unknown,
}

@immutable
class WebViewProfileDeletionResult {
  const WebViewProfileDeletionResult({required this.status, this.description});
  final WebViewProfileDeletionStatus status;
  final String? description;
  bool get isDeleted => status == WebViewProfileDeletionStatus.deleted;
}
