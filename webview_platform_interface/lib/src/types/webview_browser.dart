import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'webview_export.dart';

/// Requested autoplay behavior; engine, site and system restrictions still apply.
enum WebViewMediaPlaybackPolicy { requireUserGesture, allowWithoutUserGesture }

/// How a request to open another browsing window is handled.
enum WebViewPopupWindowPolicy {
  /// Retains the platform implementation's normal behavior.
  platformDefault,

  /// Rejects requests to open another window.
  deny,

  /// Loads the target in the current view. This does not create a child window;
  /// window.opener and form POST semantics cannot be guaranteed.
  sameView,
}

/// Browser operations available in this WebView and engine version.
@immutable
class WebViewBrowserCapabilities {
  const WebViewBrowserCapabilities({
    this.newWindowDelegate = false,
    this.windowCloseRequests = false,
    this.fullscreenEvents = false,
    this.fullscreenCustomContent = false,
    this.processFailureEvents = false,
    this.clearHistory = false,
    this.navigationState = false,
    this.navigationStateRequiresNewView = false,
    this.fullDocumentScreenshot = false,
    this.screenshotRegion = false,
    this.screenshotScale = false,
    this.pdfPageLayout = false,
    this.printing = false,
    this.printJobState = false,
    this.printCancellation = false,
    this.archiveFormats = const {},
    this.contextMenuControl = false,
    this.audioMuting = false,
    this.pauseMedia = false,
    this.suspendMedia = false,
    this.viewportScreenshot = false,
    this.pdfExport = false,
    this.stopLoading = false,
    this.navigationHistory = false,
    this.historyNavigation = false,
    this.historyIsEmulated = false,
    this.findText = false,
    this.findMatchCount = false,
    this.findCaseSensitive = false,
    this.findWithoutWrapping = false,
    this.fileSelector = false,
    this.mediaPlaybackRequiresUserGesture = false,
    this.mediaPlaybackPolicyAtCreation = false,
    this.popupWindowPolicies = const {},
    this.limitation,
  });

  /// Can attach a fresh child controller to a native popup request.
  final bool newWindowDelegate;
  final bool windowCloseRequests;

  /// Native fullscreen notifications; platform video UI may remain system-owned.
  final bool fullscreenEvents;

  /// Fullscreen can supply a separate widget instead of resizing the same view.
  final bool fullscreenCustomContent;

  /// Engine process failures are observable through public native APIs.
  final bool processFailureEvents;
  final bool clearHistory;
  final bool navigationState;

  /// Native restoration must happen before the target begins any navigation.
  final bool navigationStateRequiresNewView;

  /// Captures the whole document natively without scrolling/stitching.
  final bool fullDocumentScreenshot;
  final bool screenshotRegion;
  final bool screenshotScale;
  final bool pdfPageLayout;
  final bool printing;
  final bool printJobState;
  final bool printCancellation;
  final Set<WebViewArchiveFormat> archiveFormats;
  final bool contextMenuControl;
  final bool audioMuting;
  final bool pauseMedia;
  final bool suspendMedia;

  /// Captures the native page viewport, excluding Flutter overlays.
  final bool viewportScreenshot;

  /// Exports PDF data using the engine's native layout defaults.
  final bool pdfExport;

  final bool stopLoading;
  final bool navigationHistory;
  final bool historyNavigation;

  /// History covers controller-managed loads instead of the engine's full list.
  final bool historyIsEmulated;
  final bool findText;
  final bool findMatchCount;
  final bool findCaseSensitive;
  final bool findWithoutWrapping;

  /// Whether a custom file-selector callback can handle native file inputs.
  final bool fileSelector;

  /// Whether the gesture requirement can be changed on an existing view.
  final bool mediaPlaybackRequiresUserGesture;

  /// Whether [WebViewMediaPlaybackPolicy] can be applied at view creation.
  final bool mediaPlaybackPolicyAtCreation;
  final Set<WebViewPopupWindowPolicy> popupWindowPolicies;
  final String? limitation;
}

/// A native fullscreen presentation. The app owns layout and system chrome.
///
/// Display [content] when supplied (Android video); otherwise keep the existing
/// WebView and adjust its layout. Calling [exit] requests a native exit without
/// changing application routes, orientation or system bars.
class WebViewFullscreenRequest {
  WebViewFullscreenRequest({
    this.content,
    required Future<bool> Function() onExit,
  }) : _onExit = onExit;

  final Widget? content;
  final Future<bool> Function() _onExit;
  Future<bool>? _exit;

  /// Repeats return the first exit result. Returns false if the presentation
  /// ended before this request was used.
  Future<bool> exit() => _exit ??= _onExit();
}

class WebViewFullscreenDelegate {
  const WebViewFullscreenDelegate({
    required this.onEnter,
    required this.onExit,
  });

  final FutureOr<void> Function(WebViewFullscreenRequest request) onEnter;
  final FutureOr<void> Function() onExit;
}

enum WebViewProcessFailureKind {
  rendererExited,
  browserExited,
  rendererUnresponsive,
  other,
}

/// The recovery action an application may choose; the plugin never reloads.
enum WebViewProcessRecovery { reload, recreate, none }

@immutable
class WebViewProcessFailure {
  const WebViewProcessFailure({
    required this.kind,
    required this.recovery,
    this.didCrash,
    this.nativeCode,
    this.description,
  });

  final WebViewProcessFailureKind kind;
  final WebViewProcessRecovery recovery;
  final bool? didCrash;
  final int? nativeCode;
  final String? description;
}

/// An entry in the current back/forward list, rather than global browser history.
@immutable
class WebViewHistoryItem {
  const WebViewHistoryItem({required this.url, this.title, this.originalUrl});

  final String url;
  final String? title;
  final String? originalUrl;
}

/// A snapshot of this view's back/forward list.
///
/// Indices apply to the current list. Query again after navigation; entries are
/// not persistent identifiers and this snapshot cannot restore a session.
@immutable
class WebViewNavigationHistory {
  WebViewNavigationHistory({
    Iterable<WebViewHistoryItem> items = const [],
    this.currentIndex = -1,
  }) : items = List.unmodifiable(items) {
    if (currentIndex < -1 ||
        currentIndex >= this.items.length ||
        (this.items.isNotEmpty && currentIndex == -1)) {
      throw ArgumentError.value(currentIndex, 'currentIndex');
    }
  }

  factory WebViewNavigationHistory.fromMap(Map<Object?, Object?> data) {
    final rawItems = data['items'] as List<Object?>? ?? const [];
    return WebViewNavigationHistory(
      currentIndex: (data['currentIndex'] as num?)?.toInt() ?? -1,
      items: rawItems.whereType<Map<Object?, Object?>>().map(
        (item) => WebViewHistoryItem(
          url: item['url'] as String? ?? '',
          title: item['title'] as String?,
          originalUrl: item['originalUrl'] as String?,
        ),
      ),
    );
  }

  final List<WebViewHistoryItem> items;
  final int currentIndex;
}

/// The outcome of an engine text search. Counts may be unavailable.
@immutable
class WebViewFindResult {
  const WebViewFindResult({
    required this.matchFound,
    this.matchCount,
    this.activeMatchIndex,
  });

  final bool matchFound;
  final int? matchCount;

  /// Zero-based, or null when the engine does not report a selected match.
  final int? activeMatchIndex;

  factory WebViewFindResult.fromMap(Map<Object?, Object?> data) =>
      WebViewFindResult(
        matchFound: data['matchFound'] == true,
        matchCount: (data['matchCount'] as num?)?.toInt(),
        activeMatchIndex: (data['activeMatchIndex'] as num?)?.toInt(),
      );
}

enum WebViewFileSelectorMode { open, openMultiple, save }

/// A native file input request. Return an empty list to cancel.
@immutable
class WebViewFileSelectorParams {
  WebViewFileSelectorParams({
    this.mode = WebViewFileSelectorMode.open,
    Iterable<String> acceptTypes = const [],
    this.isCaptureEnabled,
    this.filenameHint,
    this.allowsDirectories,
  }) : acceptTypes = List.unmodifiable(acceptTypes);

  final WebViewFileSelectorMode mode;
  final List<String> acceptTypes;

  /// Null when the native request does not expose capture information.
  final bool? isCaptureEnabled;
  final String? filenameHint;

  /// Null when the native request does not expose directory selection.
  final bool? allowsDirectories;
}

/// Returns file paths or platform-supported content URIs; empty cancels.
typedef WebViewFileSelector =
    Future<List<String>> Function(WebViewFileSelectorParams params);

/// Runs an application picker and cancels failed or empty selections.
Future<List<String>> invokeWebViewFileSelector(
  WebViewFileSelector selector,
  WebViewFileSelectorParams params,
) async {
  try {
    final files = (await selector(params)).where((path) => path.isNotEmpty);
    return List.unmodifiable(
      params.mode == WebViewFileSelectorMode.openMultiple
          ? files
          : files.take(1),
    );
  } catch (error) {
    debugPrint(
      'webview_all: the custom file selector failed; selection was cancelled: $error',
    );
    return const [];
  }
}
