import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import web_webview from '@ohos.web.webview';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DownloadListener } from './DownloadListenerFlutterApiImpl';
import { DocumentStartScriptState } from './DocumentStartScriptState';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannel } from './JavaScriptChannel';
import { HttpAuthHandler, SslAuthHandler } from './OhosWebViewCallbackApiChannel';
import { WebBuilder } from './OhosWebView';
import { WebChromeClient } from './WebChromeClientHostApiImpl';
import { WebSettings } from './WebSettingsHostApiImpl';
import { WebViewClient } from './WebViewClientHostApiImpl';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl';
import { WebViewSettings } from './WebViewSettings';
import { WebDownloadCoordinator } from './WebDownloadCoordinator';
import { WebResourceCoordinator } from './WebResourceCoordinator';

const TAG: string = 'WebViewPlatformView';

export declare class PlatformViewVisibleAreaEventOptions {
  enable: boolean;
  ratios: Array<number>;
  expectedUpdateInterval: number;
  onInactiveThreshold: number;
  onActiveThreshold: number;
}

class OhosHttpAuthHandler implements HttpAuthHandler {
  private readonly nativeHandler: ESObject;

  constructor(handler: ESObject) {
    this.nativeHandler = handler;
  }

  cancel(): void {
    this.nativeHandler.cancel();
  }

  proceed(username: string, password: string): void {
    this.nativeHandler.confirm(username, password);
  }

  useHttpAuthUsernamePassword(): boolean {
    return this.nativeHandler.isHttpAuthInfoSaved?.() ?? false;
  }
}

class OhosSslAuthHandler implements SslAuthHandler {
  private readonly nativeHandler: ESObject;
  private completed: boolean = false;

  constructor(handler: ESObject) {
    this.nativeHandler = handler;
  }

  cancel(): void {
    if (this.completed) {
      return;
    }
    this.completed = true;
    if (deviceInfo.sdkApiVersion >= 20) {
      this.nativeHandler.handleCancel(true);
    } else {
      this.nativeHandler.handleCancel();
    }
  }

  proceed(): void {
    if (this.completed) {
      return;
    }
    this.completed = true;
    this.nativeHandler.handleConfirm();
  }
}

export class WebViewPlatformView extends PlatformView {
  denyPopups: boolean = false;
  private findQuery: string = '';
  private findMatches: number = 0;
  private findBackward: boolean = false;
  private findResolve: ((value: Map<string, boolean | number> | null) => void) | undefined;
  private findTimer: number | undefined;

  cancelFind(): void {
    if (this.findTimer !== undefined) clearTimeout(this.findTimer);
    this.findTimer = undefined;
    const resolve = this.findResolve;
    this.findResolve = undefined;
    this.findQuery = '';
    this.findMatches = 0;
    if (resolve) resolve(null);
  }

  findText(text: string, forward: boolean): Promise<Map<string, boolean | number> | null> {
    const continueSearch = this.findQuery === text && this.findMatches > 0;
    if (this.findResolve) this.cancelFind();
    this.findQuery = text;
    return new Promise<Map<string, boolean | number> | null>((resolve) => {
      this.findResolve = resolve;
      this.findTimer = setTimeout(() => this.cancelFind(), 10000);
      try {
        if (continueSearch) {
          this.findBackward = false;
          this.controller.searchNext(forward);
        } else {
          this.findBackward = !forward;
          this.controller.searchAllAsync(text);
        }
      } catch (error) {
        this.cancelFind();
        Log.e(TAG, 'Text search failed: ' + error);
      }
    });
  }

  onSearchResultReceive = (event: OnSearchResultReceiveEvent): void => {
    if (!event.isDoneCounting || !this.findResolve) return;
    this.findMatches = event.numberOfMatches;
    if (this.findBackward && this.findMatches > 1) {
      this.findBackward = false;
      this.controller.searchNext(false);
      return;
    }
    const result = new Map<string, boolean | number>();
    result.set('matchFound', this.findMatches > 0);
    result.set('matchCount', this.findMatches);
    if (this.findMatches > 0) result.set('activeMatchIndex', event.activeMatchOrdinal);
    if (this.findTimer !== undefined) clearTimeout(this.findTimer);
    this.findTimer = undefined;
    const resolve = this.findResolve;
    this.findResolve = undefined;
    resolve(result);
  };

  private readonly cookieManager: web_webview.WebCookieManager = new web_webview.WebCookieManager();
  private readonly controller: web_webview.WebviewController = new web_webview.WebviewController();
  private readonly webViewFlutterApi: WebViewFlutterApiImpl;
  private readonly javaScriptChannels: Map<string, JavaScriptChannel> = new Map();

  private url: string = '';
  private downloadListener: DownloadListener | null = null;
  private downloadCoordinator?: WebDownloadCoordinator;
  private resourceCoordinator?: WebResourceCoordinator;
  declaredCustomSchemes: Array<string> = [];
  private webChromeClient: WebChromeClient | null = null;
  private webViewClient: WebViewClient | null = null;
  private webSettings: WebSettings | null = null;
  private dialogController: CustomDialogController | null = null;
  private scrollX: number = 0;
  private scrollY: number = 0;
  private readonly documentStartScripts: DocumentStartScriptState = new DocumentStartScriptState();
  private onDisposeCallback?: () => void;
  private rotation: number = 0;
  private fullScreen: boolean = false;
  fullscreenDelegateEnabled: boolean = false;
  private fullscreenExitHandler: FullScreenExitHandler | undefined;
  private ownsFullscreenSystemChrome: boolean = false;
  private visibleAreaEventEnable: boolean = true;
  private visibleAreaEventRatios: Array<number> = [0, 0.1, 0.2, 0.5, 0.8, 1];
  private visibleAreaEventExpectedUpdateInterval: number = 1;
  private visibleAreaEventInactiveThreshold: number = 0;
  private visibleAreaEventActiveThreshold: number = 0.1;

  private incognito: boolean = false;

  setIncognito(incognito: boolean): void { this.incognito = incognito; }
  isIncognito(): boolean { return this.incognito; }

  userAgentString: string = '';
  isWebviewBinding: boolean = false;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super();
    this.webViewFlutterApi = new WebViewFlutterApiImpl(binaryMessenger, instanceManager);
  }

  onDownloadStart = (event: ESObject): void => {
    if (this.downloadCoordinator?.ownsNotifications()) return;
    if (!this.documentStartScripts.isDisposed() && this.downloadListener) {
      this.downloadListener.onDownloadStart(
        event.url,
        event.userAgent,
        event.contentDisposition,
        event.mimetype,
        event.contentLength
      );
    }
  }

  onPageBegin = (event: ESObject): void => {
    if (this.documentStartScripts.isDisposed()) {
      return;
    }
    this.cancelFind();
    this.setUrl(event.url);
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      this.webViewClient.onPageStarted(this, event.url);
    }
  }

  onPageEnd = (event: ESObject): void => {
    if (this.documentStartScripts.isDisposed()) {
      return;
    }
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      this.webViewClient.onPageFinished(this, event.url);
    }
  }

  onErrorReceive = (event: ESObject): void => {
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      this.webViewClient.onReceivedError(this, event.request, event.error);
    }
  }

  onHttpErrorReceive = (event: ESObject): void => {
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      this.webViewClient.onReceivedHttpError(this, event.request, event.response);
    }
  }

  onOverrideUrlLoading = (request: WebResourceRequest): boolean => {
    if (this.documentStartScripts.isDisposed()) {
      return true;
    }
    const requestUrl = request.getRequestUrl();
    if (requestUrl === 'loaded:///') {
      return true;
    }
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      return this.webViewClient.shouldOverrideUrlLoading(this, request);
    }
    return false;
  }

  onRefreshAccessedHistory = (event: ESObject): void => {
    if (this.documentStartScripts.isDisposed() || event.isMainFrame === false) {
      return;
    }
    this.setUrl(event.url);
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      this.webViewClient.doUpdateVisitedHistory(this, event.url, event.isRefreshed);
    }
  }

  onHttpAuthRequest = (event: ESObject): boolean => {
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      this.webViewClient.onReceivedHttpAuthRequest(
        this,
        new OhosHttpAuthHandler(event.handler),
        event.host,
        event.realm
      );
      return true;
    }
    return false;
  }

  onSslErrorEventReceive = (event: ESObject): void => {
    const handler = new OhosSslAuthHandler(event.handler as ESObject);
    if (!this.documentStartScripts.isDisposed() && this.webViewClient) {
      const error: ESObject = event.error as ESObject;
      const url: string = (event.url as string) ?? this.url;
      const errorCode: number = (event.errorCode as number) ?? (error?.getErrorCode?.() as number) ?? 0;
      const description: string =
        (event.description as string) ??
        (error?.getErrorInfo?.() as string) ??
        'SSL certificate error';
      this.webViewClient.onReceivedSslAuthError(
        this,
        handler,
        url,
        errorCode,
        description
      );
      return;
    }
    handler.cancel();
  }

  onTitleReceive = (event: ESObject): void => {
    if (!this.documentStartScripts.isDisposed() && event) {
      this.webChromeClient?.onReceivedTitle(this, event.title ?? '');
    }
  };

  onProgressChange = (event: ESObject): void => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      this.webChromeClient.onProgressChanged(this, event.newProgress);
    }
  }

  onGeolocationShow = (event: ESObject): void => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      this.webChromeClient.onGeolocationPermissionsShowPrompt(event.origin, event.geolocation);
    } else {
      event.geolocation.invoke(event.origin, false, false);
    }
  }

  onGeolocationHide = (): void => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      this.webChromeClient.onGeolocationPermissionsHidePrompt();
    }
  }

  onShowFileSelector = (event: ESObject): boolean => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      return this.webChromeClient.onShowFileChooser(this, event.result, event.fileSelector);
    }
    return false;
  }

  onPermissionRequest = (event: ESObject): void => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      this.webChromeClient.onPermissionRequest(event.request);
    } else {
      event.request.deny();
    }
  }

  onConsoleMessage = (event: ESObject): boolean => {
    if (this.documentStartScripts.isDisposed()) {
      return false;
    }
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      this.webChromeClient.onConsoleMessage(event.message);
      return true;
    }
    const message = event.message as ConsoleMessage;
    Log.d(TAG, 'console[' + message.getMessageLevel() + '] ' + message.getMessage());
    return true;
  }

  onWindowNew = (event: ESObject): void => {
    if (this.denyPopups) {
      event.handler.setWebController(null);
      return;
    }
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient) {
      this.webChromeClient.onCreateWindow(this, event.isAlert, event.isUserTrigger, event.handler);
    } else {
      event.handler.setWebController(null);
    }
  }

  onWindowExit = (): void => {
    const dialog = this.dialogController;
    this.dialogController = null;
    if (dialog) {
      dialog.close();
    }
  }

  onScroll = (event: ESObject): void => {
    if (this.documentStartScripts.isDisposed()) {
      return;
    }
    const oldX = this.scrollX;
    const oldY = this.scrollY;
    this.scrollX = event.xOffset;
    this.scrollY = event.yOffset;
    this.webViewFlutterApi.onScrollChanged(this, this.scrollX, this.scrollY, oldX, oldY, { reply: () => {} });
  }

  onControllerAttached = (): void => {
    if (this.documentStartScripts.isDisposed()) {
      return;
    }
    try {
      if (this.userAgentString.length > 0) {
        this.setCustomUserAgent(this.userAgentString);
      }
      this.reRegisterJavaScriptChannels();
      this.resourceCoordinator?.onAttached();
      this.downloadCoordinator?.onAttached();
      this.documentStartScripts.markControllerAttached();
    } catch (error) {
      const failure = error instanceof Error ? error : new Error(String(error));
      this.documentStartScripts.failAttachment(failure);
      Log.e(TAG, 'Failed to initialize attached WebView: ' + failure.message);
    }
  }

  onJsAlert = (event: ESObject): boolean => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient && event) {
      return this.webChromeClient.onJsAlert(this, event.url, event.message, event.result);
    }
    return false;
  }

  onJsConfirm = (event: ESObject): boolean => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient && event) {
      return this.webChromeClient.onJsConfirm(this, event.url, event.message, event.result);
    }
    return false;
  }

  onJsPrompt = (event: ESObject): boolean => {
    if (!this.documentStartScripts.isDisposed() && this.webChromeClient && event) {
      return this.webChromeClient.onJsPrompt(this, event.url, event.message, event.value, event.result);
    }
    return false;
  }

  onFullScreenEnter = (event: FullScreenEnterEvent): void => {
    if (this.documentStartScripts.isDisposed()) {
      return;
    }
    this.fullscreenExitHandler = event.handler;
    this.fullScreen = true;
    if (this.fullscreenDelegateEnabled) {
      this.webViewFlutterApi.onBrowserEvent(this, new Map<string, ESObject>()
        .set('type', 'fullscreenChanged').set('active', true));
      return;
    }
    this.ownsFullscreenSystemChrome = true;
    const context = getContext(this) as common.UIAbilityContext;
    const windowClass = context.windowStage.getMainWindowSync();
    windowClass.setWindowSystemBarEnable([]);
    this.rotation = windowClass.getPreferredOrientation();
    if (this.getWebSettings().getAllowFullScreenRotate()) {
      windowClass.setPreferredOrientation(window.Orientation.LANDSCAPE);
    }
  }

  onFullScreenExit = (): void => {
    if (!this.fullScreen) {
      return;
    }
    this.fullScreen = false;
    this.fullscreenExitHandler = undefined;
    if (this.fullscreenDelegateEnabled && !this.documentStartScripts.isDisposed()) {
      this.webViewFlutterApi.onBrowserEvent(this, new Map<string, ESObject>()
        .set('type', 'fullscreenChanged').set('active', false));
    }
    if (!this.ownsFullscreenSystemChrome) return;
    this.ownsFullscreenSystemChrome = false;
    const context = getContext(this) as common.UIAbilityContext;
    const windowClass = context.windowStage.getMainWindowSync();
    windowClass.setWindowSystemBarEnable(['status', 'navigation']);
    windowClass.setPreferredOrientation(this.rotation);
  }

  exitFullscreen(): boolean {
    const handler = this.fullscreenExitHandler;
    if (!this.fullScreen || !handler) return false;
    try {
      handler.exitFullScreen();
      this.fullscreenExitHandler = undefined;
      return true;
    } catch (error) {
      Log.e(TAG, 'Exiting fullscreen failed: ' + error);
      return false;
    }
  }

  onRenderExited = (event: OnRenderExitedEvent): void => {
    if (this.documentStartScripts.isDisposed()) return;
    this.cancelFind();
    this.exitFullscreen();
    this.onFullScreenExit();
    const failure: Map<string, ESObject> = new Map<string, ESObject>()
      .set('type', 'processFailed').set('nativeCode', event.renderExitReason);
    if (event.renderExitReason === RenderExitReason.ProcessCrashed) {
      failure.set('didCrash', true);
    } else if (event.renderExitReason === RenderExitReason.ProcessWasKilled ||
        event.renderExitReason === RenderExitReason.ProcessOom) {
      failure.set('didCrash', false);
    }
    this.webViewFlutterApi.onBrowserEvent(this, failure);
  }

  aboutToAppear(): void {
    this.isWebviewBinding = true;
  }

  aboutToDisappear(): void {
    this.isWebviewBinding = false;
    this.cancelFind();
    this.documentStartScripts.detach();
  }

  getType(): string {
    return 'web';
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(WebBuilder);
  }

  dispose(): void {
    if (this.documentStartScripts.isDisposed()) {
      return;
    }
    const attached = this.documentStartScripts.isControllerAttached();
    this.downloadCoordinator?.dispose();
    this.resourceCoordinator?.dispose();
    this.cancelFind();
    this.documentStartScripts.dispose();
    this.isWebviewBinding = false;
    this.webSettings?.onSettingsChanged(undefined);
    try {
      this.onWindowExit();
    } catch (error) {
      Log.e(TAG, 'Failed to close popup while disposing WebView: ' + error);
    }
    try {
      this.exitFullscreen();
      this.onFullScreenExit();
    } catch (error) {
      Log.e(TAG, 'Failed to restore fullscreen state: ' + error);
    }
    if (attached) {
      try {
        this.controller.stopAllMedia();
      } catch (error) {
        Log.e(TAG, 'Failed to stop media while disposing WebView: ' + error);
      }
    }
    const disposeCallback = this.onDisposeCallback;
    this.onDisposeCallback = undefined;
    this.javaScriptChannels.clear();
    this.webChromeClient = null;
    this.webViewClient = null;
    this.downloadListener = null;
    if (disposeCallback) {
      try {
        disposeCallback();
      } catch (error) {
        Log.e(TAG, 'Failed to update disposed WebView component: ' + error);
      }
    }
  }

  onInactive(): void {
    if (!this.documentStartScripts.isControllerAttached() || this.documentStartScripts.isDisposed()) {
      return;
    }
    this.controller.onInactive();
  }

  onActive(): void {
    if (!this.documentStartScripts.isControllerAttached() || this.documentStartScripts.isDisposed()) {
      return;
    }
    this.controller.onActive();
  }

  getPlatformViewVisibleAreaEventOptions(): PlatformViewVisibleAreaEventOptions {
    return {
      enable: this.visibleAreaEventEnable,
      ratios: this.visibleAreaEventRatios,
      expectedUpdateInterval: this.visibleAreaEventExpectedUpdateInterval,
      onInactiveThreshold: this.visibleAreaEventInactiveThreshold,
      onActiveThreshold: this.visibleAreaEventActiveThreshold
    } as PlatformViewVisibleAreaEventOptions;
  }

  getController(): web_webview.WebviewController {
    return this.controller;
  }

  configureResources(messenger: BinaryMessenger, name: string, host: string, enabled: boolean): void {
    if (!this.resourceCoordinator) this.resourceCoordinator = new WebResourceCoordinator(messenger, this.controller);
    this.resourceCoordinator.configure(name, host, enabled, this.documentStartScripts.isControllerAttached());
  }
  configureContentRules(messenger: BinaryMessenger, rules: Array<Map<string, ESObject>>): void {
    if (!this.resourceCoordinator) this.resourceCoordinator = new WebResourceCoordinator(messenger, this.controller);
    this.resourceCoordinator.configureRules(rules, this.documentStartScripts.isControllerAttached());
  }
  configureCustomSchemes(messenger: BinaryMessenger, name: string, schemes: Array<string>, enabled: boolean): void {
    if (!this.resourceCoordinator) this.resourceCoordinator = new WebResourceCoordinator(messenger, this.controller);
    this.resourceCoordinator.configureSchemes(name, schemes, enabled, this.documentStartScripts.isControllerAttached());
  }

  getWebCookieManager(): web_webview.WebCookieManager {
    return this.cookieManager;
  }

  getUrl(): string {
    return this.url;
  }

  setUrl(url: string): void {
    this.url = url;
  }

  setCustomUserAgent(userAgentString: string): void {
    this.controller.setCustomUserAgent(userAgentString);
    this.userAgentString = userAgentString;
  }

  setOnDisposeCallback(callback?: () => void): void {
    this.onDisposeCallback = callback;
  }

  setDownloadListener(listener: DownloadListener): void {
    this.downloadListener = listener;
  }

  setDownloadDelegate(enabled: boolean, messenger: BinaryMessenger, identifier: number,
    context: common.Context): void {
    this.ensureNotDisposed();
    if (!this.downloadCoordinator && !enabled) return;
    if (!this.downloadCoordinator) {
      this.downloadCoordinator = new WebDownloadCoordinator(messenger, identifier,
        this.controller, context, (item: web_webview.WebDownloadItem): void => {
          this.downloadListener?.onDownloadStart(item.getUrl(), '', '', item.getMimeType(), item.getTotalBytes());
        });
    }
    this.downloadCoordinator.setEnabled(enabled, this.documentStartScripts.isControllerAttached());
  }

  setWebViewClient(webViewClient: WebViewClient): void {
    this.webViewClient = webViewClient;
  }

  setWebChromeClient(webChromeClient: WebChromeClient): void {
    this.webChromeClient = webChromeClient;
  }

  setDialogController(dialogController: CustomDialogController): void {
    this.dialogController = dialogController;
  }

  getDialogController(): CustomDialogController | null {
    return this.dialogController;
  }

  getWebSettings(): WebSettings {
    if (this.webSettings == null) {
      this.webSettings = new WebViewSettings(this);
    }
    return this.webSettings;
  }

  getScrollX(): number {
    return this.scrollX;
  }

  getScrollY(): number {
    return this.scrollY;
  }

  setScrollPosition(x: number, y: number): void {
    const oldX = this.scrollX;
    const oldY = this.scrollY;
    this.scrollX = x;
    this.scrollY = y;
    this.webViewFlutterApi.onScrollChanged(this, x, y, oldX, oldY, { reply: () => {} });
  }

  async waitControllerAttached(): Promise<void> {
    await this.documentStartScripts.waitUntilReady();
    await this.getWebSettings().waitUntilApplied();
    this.ensureNotDisposed();
  }

  ensureNotDisposed(): void {
    if (this.documentStartScripts.isDisposed()) {
      throw new Error('The WebView has been disposed.');
    }
  }

  getDocumentStartScriptState(): DocumentStartScriptState {
    return this.documentStartScripts;
  }

  setDocumentStartScripts(scripts: Array<string>, endScripts: Array<string> = []): Promise<void> {
    return this.documentStartScripts.setScripts(scripts, endScripts);
  }

  addJavaScriptChannel(channel: JavaScriptChannel): void {
    this.ensureNotDisposed();
    if (this.documentStartScripts.isControllerAttached()) {
      this.controller.registerJavaScriptProxy(
        channel.createJavaScriptProxy(this.controller), channel.getJavaScriptChannelName(), ['postMessage']);
    }
    this.javaScriptChannels.set(channel.getJavaScriptChannelName(), channel);
  }

  removeJavaScriptChannel(channelName: string): void {
    this.ensureNotDisposed();
    if (this.documentStartScripts.isControllerAttached() && this.javaScriptChannels.has(channelName)) {
      this.controller.deleteJavaScriptRegister(channelName);
    }
    this.javaScriptChannels.delete(channelName);
  }

  reRegisterJavaScriptChannels(): void {
    if (this.javaScriptChannels.size === 0) {
      return;
    }
    this.javaScriptChannels.forEach((channel: JavaScriptChannel, channelName: string) => {
        this.controller.registerJavaScriptProxy(
          channel.createJavaScriptProxy(this.controller),
          channelName,
          ['postMessage']
        );
    });
  }
}
