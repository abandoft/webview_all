import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_webview_creation_params.dart';

class LinuxNavigationDelegate extends PlatformNavigationDelegate {
  LinuxNavigationDelegate(PlatformNavigationDelegateCreationParams params)
    : super.implementation(
        params is LinuxNavigationDelegateCreationParams
            ? params
            : LinuxNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
                params,
              ),
      );

  PageEventCallback? _onPageFinished;
  PageEventCallback? _onPageStarted;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  NavigationRequestCallback? _onNavigationRequest;
  UrlChangeCallback? _onUrlChange;
  HttpResponseErrorCallback? _onHttpError;
  HttpAuthRequestCallback? _onHttpAuthRequest;
  SslAuthErrorCallback? _onSslAuthError;

  bool get hasNavigationRequestHandler => _onNavigationRequest != null;

  bool get hasHttpAuthRequestHandler => _onHttpAuthRequest != null;

  bool get hasSslAuthErrorHandler => _onSslAuthError != null;

  void handleUrlChange(String url) {
    _onUrlChange?.call(UrlChange(url: url));
  }

  void handlePageStarted(String url) {
    _onPageStarted?.call(url);
  }

  void handlePageFinished(String url) {
    _onProgress?.call(100);
    _onPageFinished?.call(url);
  }

  void handleProgress(int progress) {
    _onProgress?.call(progress);
  }

  void handleWebResourceError(WebResourceError error) {
    _onWebResourceError?.call(error);
  }

  void handleHttpError(HttpResponseError error) {
    _onHttpError?.call(error);
  }

  Future<NavigationDecision?> decideNavigation(
    NavigationRequest request,
  ) async {
    return _onNavigationRequest?.call(request);
  }

  void handleHttpAuthRequest(HttpAuthRequest request) {
    _onHttpAuthRequest?.call(request);
  }

  void handleSslAuthError(PlatformSslAuthError error) {
    _onSslAuthError?.call(error);
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    _onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    _onHttpError = onHttpError;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    _onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    _onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    _onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {
    _onHttpAuthRequest = onHttpAuthRequest;
  }

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {
    _onSslAuthError = onSslAuthError;
  }
}
