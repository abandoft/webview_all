import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import web_webview from '@ohos.web.webview';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DownloadListener } from './DownloadListenerFlutterApiImpl';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannel } from './JavaScriptChannel';
import { HttpAuthHandler, SslAuthHandler } from './OhosWebViewCallbackApiChannel';
import { WebBuilder } from './OhosWebView';
import { WebChromeClient } from './WebChromeClientHostApiImpl';
import { WebSettings } from './WebSettingsHostApiImpl';
import { WebViewClient } from './WebViewClientHostApiImpl';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl';
import { WebViewSettings } from './WebViewSettings';

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
  private readonly cookieManager: web_webview.WebCookieManager = new web_webview.WebCookieManager();
  private readonly controller: web_webview.WebviewController = new web_webview.WebviewController();
  private readonly webViewFlutterApi: WebViewFlutterApiImpl;
  private readonly javaScriptChannels: Map<string, JavaScriptChannel> = new Map();

  private url: string = '';
  private downloadListener: DownloadListener | null = null;
  private webChromeClient: WebChromeClient | null = null;
  private webViewClient: WebViewClient | null = null;
  private webSettings: WebSettings | null = null;
  private dialogController: CustomDialogController | null = null;
  private scrollX: number = 0;
  private scrollY: number = 0;
  private controllerAttached: boolean = false;
  private onDisposeCallback?: () => void;
  private rotation: number = 0;
  private visibleAreaEventEnable: boolean = true;
  private visibleAreaEventRatios: Array<number> = [0, 0.1, 0.2, 0.5, 0.8, 1];
  private visibleAreaEventExpectedUpdateInterval: number = 1;
  private visibleAreaEventInactiveThreshold: number = 0;
  private visibleAreaEventActiveThreshold: number = 0.1;

  userAgentString: string = '';
  isWebviewBinding: boolean = false;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    super();
    this.webViewFlutterApi = new WebViewFlutterApiImpl(binaryMessenger, instanceManager);
  }

  onDownloadStart = (event: ESObject): void => {
    if (this.downloadListener) {
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
    if (this.webViewClient) {
      this.webViewClient.onPageStarted(this, event.url);
    }
  }

  onPageEnd = (event: ESObject): void => {
    if (this.webViewClient) {
      this.webViewClient.onPageFinished(this, event.url);
    }
  }

  onErrorReceive = (event: ESObject): void => {
    if (this.webViewClient) {
      this.webViewClient.onReceivedError(this, event.request, event.error);
    }
  }

  onHttpErrorReceive = (event: ESObject): void => {
    if (this.webViewClient) {
      this.webViewClient.onReceivedHttpError(this, event.request, event.response);
    }
  }

  onOverrideUrlLoading = (request: WebResourceRequest): boolean => {
    const requestUrl = request.getRequestUrl();
    if (requestUrl === 'loaded:///') {
      return true;
    }
    if (this.webViewClient) {
      return this.webViewClient.shouldOverrideUrlLoading(this, request);
    }
    return false;
  }

  onRefreshAccessedHistory = (event: ESObject): void => {
    if (this.webViewClient) {
      this.webViewClient.doUpdateVisitedHistory(this, event.url, event.isRefreshed);
    }
  }

  onHttpAuthRequest = (event: ESObject): boolean => {
    if (this.webViewClient) {
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
    if (this.webViewClient) {
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

  onProgressChange = (event: ESObject): void => {
    if (this.webChromeClient) {
      this.webChromeClient.onProgressChanged(this, event.newProgress);
    }
  }

  onGeolocationShow = (event: ESObject): void => {
    if (this.webChromeClient) {
      this.webChromeClient.onGeolocationPermissionsShowPrompt(event.origin, event.geolocation);
    }
  }

  onGeolocationHide = (): void => {
    if (this.webChromeClient) {
      this.webChromeClient.onGeolocationPermissionsHidePrompt();
    }
  }

  onShowFileSelector = (event: ESObject): boolean => {
    if (this.webChromeClient) {
      return this.webChromeClient.onShowFileChooser(this, event.result, event.fileSelector);
    }
    return false;
  }

  onPermissionRequest = (event: ESObject): void => {
    if (this.webChromeClient) {
      this.webChromeClient.onPermissionRequest(event.request);
    }
  }

  onConsoleMessage = (event: ESObject): boolean => {
    if (this.webChromeClient) {
      this.webChromeClient.onConsoleMessage(event.message);
      return true;
    }
    const message = event.message as ConsoleMessage;
    Log.d(TAG, 'console[' + message.getMessageLevel() + '] ' + message.getMessage());
    return true;
  }

  onWindowNew = (event: ESObject): void => {
    if (this.webChromeClient) {
      this.webChromeClient.onCreateWindow(this, event.isAlert, event.isUserTrigger, event.handler);
    }
  }

  onWindowExit = (): void => {
    if (this.dialogController) {
      this.dialogController.close();
      this.dialogController = null;
    }
  }

  onScroll = (event: ESObject): void => {
    const oldX = this.scrollX;
    const oldY = this.scrollY;
    this.scrollX = event.xOffset;
    this.scrollY = event.yOffset;
    this.webViewFlutterApi.onScrollChanged(this, this.scrollX, this.scrollY, oldX, oldY, { reply: () => {} });
  }

  onControllerAttached = (): void => {
    this.controllerAttached = true;
    if (this.userAgentString.length > 0) {
      this.setCustomUserAgent(this.userAgentString);
      this.controller.refresh();
    }
    this.reRegisterJavaScriptChannels();
  }

  onJsAlert = (event: ESObject): boolean => {
    if (this.webChromeClient && event) {
      return this.webChromeClient.onJsAlert(this, event.url, event.message, event.result);
    }
    return true;
  }

  onJsConfirm = (event: ESObject): boolean => {
    if (this.webChromeClient && event) {
      return this.webChromeClient.onJsConfirm(this, event.url, event.message, event.result);
    }
    return true;
  }

  onJsPrompt = (event: ESObject): boolean => {
    if (this.webChromeClient && event) {
      return this.webChromeClient.onJsPrompt(this, event.url, event.message, event.value, event.result);
    }
    return true;
  }

  onFullScreenEnter = (_event: ESObject): void => {
    const context = getContext(this) as common.UIAbilityContext;
    const windowClass = context.windowStage.getMainWindowSync();
    windowClass.setWindowSystemBarEnable([]);
    this.rotation = windowClass.getPreferredOrientation();
    if (this.getWebSettings().getAllowFullScreenRotate()) {
      windowClass.setPreferredOrientation(window.Orientation.LANDSCAPE);
    }
  }

  onFullScreenExit = (): void => {
    const context = getContext(this) as common.UIAbilityContext;
    const windowClass = context.windowStage.getMainWindowSync();
    windowClass.setWindowSystemBarEnable(['status', 'navigation']);
    windowClass.setPreferredOrientation(this.rotation);
    this.reRegisterJavaScriptChannels();
  }

  aboutToAppear(): void {
    this.isWebviewBinding = true;
  }

  aboutToDisappear(): void {
    this.isWebviewBinding = false;
  }

  getType(): string {
    return 'web';
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(WebBuilder);
  }

  dispose(): void {
    this.controller.stopAllMedia();
    if (this.onDisposeCallback) {
      this.onDisposeCallback();
    }
  }

  onInactive(): void {
    this.controller.onInactive();
  }

  onActive(): void {
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
    this.userAgentString = userAgentString;
    this.controller.setCustomUserAgent(userAgentString);
  }

  setOnDisposeCallback(callback: () => void): void {
    this.onDisposeCallback = callback;
  }

  setDownloadListener(listener: DownloadListener): void {
    this.downloadListener = listener;
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
    if (this.controllerAttached) {
      return;
    }
    await new Promise<void>((resolve, reject) => {
      try {
        const intervalId = setInterval(() => {
          if (this.controllerAttached) {
            clearInterval(intervalId);
            resolve();
          }
        }, 20);
      } catch (err) {
        reject(err);
      }
    });
  }

  addJavaScriptChannel(channel: JavaScriptChannel): void {
    this.javaScriptChannels.set(channel.getJavaScriptChannelName(), channel);
  }

  removeJavaScriptChannel(channelName: string): void {
    this.javaScriptChannels.delete(channelName);
  }

  reRegisterJavaScriptChannels(): void {
    if (this.javaScriptChannels.size === 0) {
      return;
    }
    try {
      this.javaScriptChannels.forEach((channel: JavaScriptChannel, channelName: string) => {
        this.controller.registerJavaScriptProxy(
          channel.createJavaScriptProxy(this.controller),
          channelName,
          ['postMessage']
        );
      });
      this.controller.refresh();
    } catch (err) {
      Log.e(TAG, 'Failed to re-register JavaScript channels: ' + err);
    }
  }
}
