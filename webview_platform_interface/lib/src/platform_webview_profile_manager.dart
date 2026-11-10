import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'types/webview_profile.dart';

/// Native profile management. Platform adapters can use the bounded channel
/// protocol; the default implementation safely reports no support.
class PlatformWebViewProfileManager {
  PlatformWebViewProfileManager() : _channel = null;
  PlatformWebViewProfileManager.channel(String name)
    : _channel = MethodChannel(name);
  final MethodChannel? _channel;

  Future<WebViewProfileManagementCapabilities> getCapabilities() async {
    try {
      final result = await _channel
          ?.invokeMapMethod<String, Object?>('profileManagementCapabilities')
          .timeout(const Duration(seconds: 10));
      return WebViewProfileManagementCapabilities(
        listing: result?['listing'] == true,
        deletion: result?['deletion'] == true,
        limitation: result?['limitation'] as String?,
      );
    } catch (error) {
      debugPrint(
        'webview_all: profile-management capabilities are unavailable: $error',
      );
      return const WebViewProfileManagementCapabilities();
    }
  }

  Future<List<WebViewProfileInfo>?> listProfiles() async {
    if (!(await getCapabilities()).listing) {
      debugPrint(
        'webview_all: listing plugin-owned named profiles is unavailable on this platform/runtime. Ordinary and private stores are not enumerated.',
      );
      return null;
    }
    try {
      final rows = await _channel!
          .invokeListMethod<Object?>('listProfiles')
          .timeout(const Duration(seconds: 30));
      if (rows == null) return null;
      final result = <WebViewProfileInfo>[];
      for (final row in rows) {
        if (row is! Map ||
            row['name'] is! String ||
            !_validName(row['name'] as String)) {
          throw const FormatException('Invalid native profile record.');
        }
        result.add(
          WebViewProfileInfo(
            name: row['name'] as String,
            deletionPending: row['deletionPending'] == true,
          ),
        );
      }
      result.sort((a, b) => a.name.compareTo(b.name));
      return List.unmodifiable(result);
    } catch (error) {
      debugPrint('webview_all: profile enumeration failed: $error');
      return null;
    }
  }

  Future<WebViewProfileDeletionResult> requestDeletion(String name) async {
    if (!_validName(name)) {
      return _result(
        WebViewProfileDeletionStatus.failed,
        'Invalid profile name; no deletion was requested.',
      );
    }
    if (!(await getCapabilities()).deletion) {
      return _result(
        WebViewProfileDeletionStatus.unsupported,
        'Deleting named profiles is unavailable on this platform/runtime. No shared or private store was cleared.',
      );
    }
    try {
      final row = await _channel!
          .invokeMapMethod<String, Object?>('requestProfileDeletion', {
            'name': name,
          })
          .timeout(const Duration(seconds: 30));
      if (row == null) {
        return _result(
          WebViewProfileDeletionStatus.unknown,
          'The native deletion outcome is unavailable. Query profiles before retrying.',
        );
      }
      final status = WebViewProfileDeletionStatus.values.firstWhere(
        (v) => v.name == row['status'],
        orElse: () => WebViewProfileDeletionStatus.unknown,
      );
      return _result(status, row['description'] as String?);
    } on TimeoutException {
      return _result(
        WebViewProfileDeletionStatus.unknown,
        'Deletion may still be running natively. Query profiles before retrying.',
      );
    } catch (error) {
      return _result(
        WebViewProfileDeletionStatus.unknown,
        'The native deletion outcome could not be confirmed: $error. Query profiles before retrying.',
      );
    }
  }

  static bool _validName(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value);
  WebViewProfileDeletionResult _result(
    WebViewProfileDeletionStatus status,
    String? description,
  ) {
    if (description != null &&
        description.isNotEmpty &&
        status != WebViewProfileDeletionStatus.deleted &&
        status != WebViewProfileDeletionStatus.notFound) {
      debugPrint('webview_all: $description');
    }
    return WebViewProfileDeletionResult(
      status: status,
      description: description,
    );
  }
}
