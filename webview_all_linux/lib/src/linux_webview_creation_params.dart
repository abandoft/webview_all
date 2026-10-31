import 'package:flutter/widgets.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

@immutable
class LinuxWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  const LinuxWebViewControllerCreationParams({
    bool incognito = false,
    WebViewSessionMode sessionMode = WebViewSessionMode.shared,
    this.developerExtrasEnabled,
    this.downloadsEnabled,
    this.javascriptCanOpenWindowsAutomatically,
    this.mediaPlaybackRequiresUserGesture,
    this.mediaPlaybackAllowsInline,
    this.pageCacheEnabled,
    this.allowFileAccessFromFileUrls,
    this.allowUniversalAccessFromFileUrls,
    this.zoomTextOnly,
    this.defaultFontSize,
    this.defaultMonospaceFontSize,
    this.minimumFontSize,
    this.zoomFactor,
  }) : super(
         sessionMode: incognito
             ? WebViewSessionMode.isolatedIncognito
             : sessionMode,
       );

  const LinuxWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    PlatformWebViewControllerCreationParams params, {
    bool incognito = false,
    this.developerExtrasEnabled,
    this.downloadsEnabled,
    this.javascriptCanOpenWindowsAutomatically,
    this.mediaPlaybackRequiresUserGesture,
    this.mediaPlaybackAllowsInline,
    this.pageCacheEnabled,
    this.allowFileAccessFromFileUrls,
    this.allowUniversalAccessFromFileUrls,
    this.zoomTextOnly,
    this.defaultFontSize,
    this.defaultMonospaceFontSize,
    this.minimumFontSize,
    this.zoomFactor,
  }) : super.fromPlatformWebViewControllerCreationParams(
         params,
         sessionMode: incognito ? WebViewSessionMode.isolatedIncognito : null,
       );

  /// Uses a separate, ephemeral WebKitGTK context for this controller.
  ///
  /// Cookies and website data are isolated from other controllers and from the
  /// shared cookie/data managers. Nothing is persisted to the shared profile.
  /// This option must be selected when creating the controller.
  bool get incognito => sessionMode != WebViewSessionMode.shared;

  /// Whether WebKitGTK developer extras are enabled for this WebView.
  final bool? developerExtrasEnabled;

  /// Whether this WebView can start downloads. Null preserves the WebKitGTK
  /// default (enabled). Disabled downloads are cancelled before saving a file.
  final bool? downloadsEnabled;

  /// Whether JavaScript is allowed to open windows automatically.
  final bool? javascriptCanOpenWindowsAutomatically;

  /// Whether media playback requires a user gesture.
  final bool? mediaPlaybackRequiresUserGesture;

  /// Whether inline media playback is allowed.
  final bool? mediaPlaybackAllowsInline;

  /// Whether WebKitGTK's page cache is enabled.
  final bool? pageCacheEnabled;

  /// Whether file URLs can read other file URLs.
  final bool? allowFileAccessFromFileUrls;

  /// Whether file URLs can access all origins.
  final bool? allowUniversalAccessFromFileUrls;

  /// Whether zooming affects only text.
  final bool? zoomTextOnly;

  /// Default proportional font size in CSS pixels.
  final int? defaultFontSize;

  /// Default monospace font size in CSS pixels.
  final int? defaultMonospaceFontSize;

  /// Minimum font size in CSS pixels.
  final int? minimumFontSize;

  /// Initial page zoom factor.
  final double? zoomFactor;
}

@immutable
class LinuxWebViewWidgetCreationParams
    extends PlatformWebViewWidgetCreationParams {
  const LinuxWebViewWidgetCreationParams({
    super.key,
    required super.controller,
    super.layoutDirection,
    super.gestureRecognizers,
  });

  LinuxWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
    PlatformWebViewWidgetCreationParams params,
  ) : this(
        key: params.key,
        controller: params.controller,
        layoutDirection: params.layoutDirection,
        gestureRecognizers: params.gestureRecognizers,
      );
}

@immutable
class LinuxNavigationDelegateCreationParams
    extends PlatformNavigationDelegateCreationParams {
  const LinuxNavigationDelegateCreationParams();

  const LinuxNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
    PlatformNavigationDelegateCreationParams params,
  );
}
