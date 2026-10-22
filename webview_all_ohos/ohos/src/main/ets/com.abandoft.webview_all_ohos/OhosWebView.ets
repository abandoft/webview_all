import web_webview from '@ohos.web.webview';
import PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { WebViewPlatformView } from './WebViewPlatformView';
import { DocumentStartScriptSnapshot, DocumentStartScriptState } from './DocumentStartScriptState';
import { WebViewSettingsSnapshot } from './WebViewSettingsSnapshot';

@Observed
export declare class Params {
  direction: Direction;
  platformView: PlatformView;
}

@Component
export struct OhosWebView {
  @ObjectLink params: Params;

  webView: WebViewPlatformView = this.params.platformView as WebViewPlatformView;
  controller: web_webview.WebviewController = this.webView.getController();
  scriptState: DocumentStartScriptState = this.webView.getDocumentStartScriptState();

  @State settings: WebViewSettingsSnapshot = this.webView.getWebSettings().getSnapshot();
  @State disposed: boolean = false;
  @State documentStartScripts: DocumentStartScriptSnapshot = this.scriptState.getSnapshot();

  aboutToAppear(): void {
    this.disposed = this.scriptState.isDisposed();
    if (this.disposed) {
      return;
    }
    this.webView.aboutToAppear();
    this.scriptState.subscribe((snapshot: DocumentStartScriptSnapshot) => {
      this.documentStartScripts = snapshot;
    });
    this.settings = this.webView.getWebSettings().getSnapshot();
    this.webView.getWebSettings().onSettingsChanged((snapshot: WebViewSettingsSnapshot) => {
      this.settings = snapshot;
    });
    this.webView.setOnDisposeCallback(() => {
      this.disposed = true;
    });
  }

  aboutToDisappear(): void {
    this.webView.aboutToDisappear();
    this.webView.getWebSettings().onSettingsChanged(undefined);
    this.webView.getWebSettings().onMixedContentModeChanged(undefined);
    this.webView.getWebSettings().onTextZoomChanged(undefined);
    this.webView.setOnDisposeCallback(undefined);
  }

  private documentStartScriptsForBuild(): Array<ScriptItem> {
    const snapshot = this.documentStartScripts;
    const generation = this.scriptState.getGeneration();
    const settingsRevision = this.settings.revision;
    // This argument is evaluated immediately before the synchronous native
    // modifier below. The microtask runs after that modifier chain completes.
    Promise.resolve().then(() => {
      if (generation !== this.scriptState.getGeneration() || this.scriptState.isDisposed()) {
        return;
      }
      this.scriptState.markApplied(snapshot.revision, generation);
      this.webView.getWebSettings().markApplied(settingsRevision);
    });
    return snapshot.sources.map((source: string): ScriptItem => {
      return { script: source, scriptRules: ['*'] };
    });
  }

  build() {
    Column() {
      if (!this.disposed) {
        Web({ src: this.webView.getUrl(), controller: this.controller })
          .runJavaScriptOnDocumentStart(this.documentStartScriptsForBuild())
          .keyboardAvoidMode(WebKeyboardAvoidMode.RESIZE_VISUAL)
          .backgroundColor(this.settings.backgroundColor)
          .domStorageAccess(this.settings.domStorageEnabled)
          .allowWindowOpenMethod(this.settings.javaScriptCanOpenWindowsAutomatically)
          .multiWindowAccess(false)
          .javaScriptAccess(this.settings.javaScriptEnabled)
          .mediaPlayGestureAccess(this.settings.mediaPlaybackRequiresUserGesture)
          .zoomAccess(this.settings.supportZoom)
          .zoomControlAccess(this.settings.supportZoom)
          .overviewModeAccess(this.settings.loadWithOverviewMode)
          .wideViewModeAccess(this.settings.useWideViewPort)
          .metaViewport(this.settings.useWideViewPort)
          .fileAccess(this.settings.allowFileAccess)
          .textZoomRatio(this.settings.textZoom)
          .mixedMode(this.settings.mixedContentMode)
          .onControllerAttached(this.webView.onControllerAttached)
          .onDownloadStart(this.webView.onDownloadStart)
          .onPageBegin(this.webView.onPageBegin)
          .onPageEnd(this.webView.onPageEnd)
          .onErrorReceive(this.webView.onErrorReceive)
          .onHttpErrorReceive(this.webView.onHttpErrorReceive)
          .onRefreshAccessedHistory(this.webView.onRefreshAccessedHistory)
          .onProgressChange(this.webView.onProgressChange)
          .onGeolocationShow(this.webView.onGeolocationShow)
          .onGeolocationHide(this.webView.onGeolocationHide)
          .onShowFileSelector(this.webView.onShowFileSelector)
          .onPermissionRequest(this.webView.onPermissionRequest)
          .onConsole(this.webView.onConsoleMessage)
          .onWindowExit(this.webView.onWindowExit)
          .onWindowNew(this.webView.onWindowNew)
          .onSslErrorEventReceive(this.webView.onSslErrorEventReceive)
          .onHttpAuthRequest(this.webView.onHttpAuthRequest)
          .onAlert(this.webView.onJsAlert)
          .onConfirm(this.webView.onJsConfirm)
          .onPrompt(this.webView.onJsPrompt)
          .onOverrideUrlLoading(this.webView.onOverrideUrlLoading)
          .onFullScreenEnter(this.webView.onFullScreenEnter)
          .onFullScreenExit(this.webView.onFullScreenExit)
          .onScroll(this.webView.onScroll)
      }
    }
  }
}

@Builder
export function WebBuilder(params: Params) {
  OhosWebView({
    params: params,
    webView: params.platformView as WebViewPlatformView,
    controller: (params.platformView as WebViewPlatformView).getController()
  }).backgroundColor(Color.Transparent)
}

@CustomDialog
struct PopupWebView {
  controller?: CustomDialogController;
  webViewController: web_webview.WebviewController = new web_webview.WebviewController();

  build() {
    Web({ src: '', controller: this.webViewController })
      .javaScriptAccess(true)
      .multiWindowAccess(false)
      .onWindowExit(() => {
        if (this.controller) {
          this.controller.close();
        }
      })
  }
}
