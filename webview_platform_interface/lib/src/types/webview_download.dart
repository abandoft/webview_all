import 'dart:async';

import 'package:flutter/foundation.dart';

/// Extracts a suggested basename, preferring RFC 5987's UTF-8 filename.
/// This is untrusted metadata, not permission to overwrite an existing file.
String webViewDownloadSuggestedFilename({
  required String url,
  String? contentDisposition,
}) {
  String? name;
  final disposition = contentDisposition ?? '';
  final extended = RegExp(
    r'''(?:^|;)\s*filename\*\s*=\s*([^;]+)''',
    caseSensitive: false,
  ).firstMatch(disposition);
  if (extended != null) {
    final value = extended.group(1)!.trim().replaceAll(RegExp(r'^"|"$'), '');
    final parts = value.split("'");
    if (parts.length >= 3 && parts.first.toLowerCase() == 'utf-8') {
      try {
        name = Uri.decodeComponent(parts.skip(2).join("'"));
      } on ArgumentError {
        /* Fall back to filename. */
      } on FormatException {
        /* Fall back to filename. */
      }
    }
  }
  final plain = RegExp(
    r'''(?:^|;)\s*filename\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]*))''',
    caseSensitive: false,
  ).firstMatch(disposition);
  name ??=
      plain
          ?.group(1)
          ?.replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!) ??
      plain?.group(2)?.trim();
  if (name == null || name.isEmpty) {
    try {
      name = Uri.parse(url).pathSegments.lastOrNull;
    } on ArgumentError {
      name = null;
    } on FormatException {
      name = null;
    }
  }
  name = (name ?? '')
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .trim();
  if (name.isEmpty || name == '.' || name == '..') return 'download';
  return String.fromCharCodes(name.runes.take(200));
}

/// Operations available for a particular download request.
enum WebViewDownloadAction {
  /// Decline the request without starting another URL request.
  cancel,

  /// Use the default download behavior advertised by this platform.
  platformDefault,

  /// Save the original download to a new file in an existing writable directory.
  saveToFile,

  /// Let the application handle the request without another plugin handler.
  handledExternally,
}

/// The final outcome known to this plugin.
enum WebViewDownloadStatus { completed, cancelled, failed, handedOff }

// Keep completed requests collectible while a controller's cancellation signal
// stays pending for subsequent downloads.
void _watchDownloadCancellation(
  Future<void> cancelled,
  WeakReference<Completer<WebViewDownloadDecision>> reference,
) {
  void cancel(Object error, StackTrace stack) {
    final completion = reference.target;
    if (completion != null && !completion.isCompleted) {
      completion.completeError(error, stack);
    }
  }

  cancelled.then(
    (_) => cancel(
      StateError('The download decision was cancelled.'),
      StackTrace.current,
    ),
    onError: (Object error, StackTrace stack) => cancel(error, stack),
  );
}

void _watchDownloadDecision(
  Future<WebViewDownloadDecision> decision,
  WeakReference<Completer<WebViewDownloadDecision>> reference,
) {
  decision.then(
    (value) {
      final completion = reference.target;
      if (completion != null && !completion.isCompleted) {
        completion.complete(value);
      }
    },
    onError: (Object error, StackTrace stack) {
      final completion = reference.target;
      if (completion != null && !completion.isCompleted) {
        completion.completeError(error, stack);
      }
    },
  );
}

/// A download reported by the engine. Unavailable metadata is null.
@immutable
class WebViewDownloadRequest {
  WebViewDownloadRequest({
    required this.id,
    required this.url,
    this.suggestedFilename,
    this.mimeType,
    this.contentDisposition,
    this.contentLength,
    this.userAgent,
    required Set<WebViewDownloadAction> supportedActions,
  }) : supportedActions = Set<WebViewDownloadAction>.unmodifiable(
         supportedActions,
       );

  /// Identifies this download within its controller.
  final String id;
  final String url;
  final String? suggestedFilename;
  final String? mimeType;
  final String? contentDisposition;
  final int? contentLength;
  final String? userAgent;

  /// Decisions this platform can perform for this particular request.
  final Set<WebViewDownloadAction> supportedActions;
}

/// The application's decision. A file target is only valid when advertised by
/// [WebViewDownloadRequest.supportedActions], and must be an absolute file path.
@immutable
class WebViewDownloadDecision {
  const WebViewDownloadDecision.cancel()
    : action = WebViewDownloadAction.cancel,
      path = null;
  const WebViewDownloadDecision.platformDefault()
    : action = WebViewDownloadAction.platformDefault,
      path = null;
  const WebViewDownloadDecision.saveToFile(String this.path)
    : action = WebViewDownloadAction.saveToFile;
  const WebViewDownloadDecision.handledExternally()
    : action = WebViewDownloadAction.handledExternally,
      path = null;

  final WebViewDownloadAction action;
  final String? path;

  /// Message-channel representation for platform implementations.
  Map<String, Object?> toMap() => <String, Object?>{
    'action': action.name,
    'path': path,
  };
}

/// Progress of an engine-owned download, independent of page loading progress.
@immutable
class WebViewDownloadProgress {
  const WebViewDownloadProgress({
    required this.id,
    required this.bytesReceived,
    this.totalBytes,
  });
  final String id;
  final int bytesReceived;

  /// Expected response size, or null when it is unknown.
  final int? totalBytes;
}

/// A terminal result. [WebViewDownloadStatus.handedOff] does not establish that
/// the browser or application has saved a file.
@immutable
class WebViewDownloadResult {
  const WebViewDownloadResult({
    required this.id,
    required this.status,
    this.path,
    this.errorCode,
    this.description,
  });
  final String id;
  final WebViewDownloadStatus status;

  /// Saved file path when available; browser/application handoffs have no path.
  final String? path;
  final String? errorCode;
  final String? description;
}

/// Optional download handling. This delegate does not create a save dialog or
/// provide a background download manager. Native requests retain their engine
/// context; notification-only platforms cannot offer every action.
/// Updating the delegate cancels unanswered requests. Accepted downloads keep
/// reporting to their original delegate until completion or controller disposal.
class WebViewDownloadDelegate {
  const WebViewDownloadDelegate({
    required this.onDownloadRequest,
    this.onDownloadProgress,
    this.onDownloadResult,
  });

  final FutureOr<WebViewDownloadDecision> Function(
    WebViewDownloadRequest request,
  )
  onDownloadRequest;
  final void Function(WebViewDownloadProgress progress)? onDownloadProgress;
  final void Function(WebViewDownloadResult result)? onDownloadResult;

  /// Resolves one decision with a bounded wait and checks advertised actions.
  /// Platform implementations must cancel and report failures if this throws.
  Future<WebViewDownloadDecision> decide(
    WebViewDownloadRequest request, {
    Future<void>? cancelled,
  }) async {
    final completion = Completer<WebViewDownloadDecision>();
    void fail(Object error, StackTrace stack) {
      if (!completion.isCompleted) completion.completeError(error, stack);
    }

    final timer = Timer(const Duration(seconds: 30), () {
      fail(
        TimeoutException('The download decision timed out.'),
        StackTrace.current,
      );
    });
    _watchDownloadDecision(
      Future<WebViewDownloadDecision>.sync(() => onDownloadRequest(request)),
      WeakReference(completion),
    );
    if (cancelled != null) {
      _watchDownloadCancellation(cancelled, WeakReference(completion));
    }
    final WebViewDownloadDecision decision;
    try {
      decision = await completion.future;
    } finally {
      timer.cancel();
    }
    if (!request.supportedActions.contains(decision.action)) {
      throw UnsupportedError('The requested download action is not supported.');
    }
    if (decision.action == WebViewDownloadAction.saveToFile &&
        (decision.path == null ||
            decision.path!.isEmpty ||
            decision.path!.contains('\u0000'))) {
      throw ArgumentError.value(
        decision.path,
        'path',
        'A non-empty file path is required.',
      );
    }
    return decision;
  }

  void notifyProgress(WebViewDownloadProgress progress) =>
      _notify(() => onDownloadProgress?.call(progress));
  void notifyResult(WebViewDownloadResult result) =>
      _notify(() => onDownloadResult?.call(result));

  void _notify(VoidCallback callback) {
    try {
      callback();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'webview_all',
          context: ErrorDescription('while handling a download callback'),
        ),
      );
    }
  }
}
