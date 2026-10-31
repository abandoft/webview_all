import common from '@ohos.app.ability.common';
import web_webview from '@ohos.web.webview';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { DisplayListenerProxy } from './DisplayListenerProxy';
import { DownloadListener } from './DownloadListenerFlutterApiImpl';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannel } from './JavaScriptChannel';
import { Result, WebViewPoint } from './OhosWebViewTypes';
import { WebChromeClient } from './WebChromeClientHostApiImpl';
import { WebViewClient } from './WebViewClientHostApiImpl';
import {
  PlatformViewVisibleAreaEventOptions,
  WebViewPlatformView
} from './WebViewPlatformView';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl';

const TAG: string = 'WebViewHostApiImpl';

export { PlatformViewVisibleAreaEventOptions, WebViewPlatformView } from './WebViewPlatformView';

export class WebViewProxy {
  createWebView(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager): WebViewPlatformView {
    return new WebViewPlatformView(binaryMessenger, instanceManager);
  }

  setWebContentsDebuggingEnabled(enabled: boolean): void {
    web_webview.WebviewController.setWebDebuggingAccess(enabled);
  }
}

export class WebViewHostApiImpl {
  private readonly instanceManager: InstanceManager;
  private readonly webViewProxy: WebViewProxy;
  private readonly binaryMessenger: BinaryMessenger;
  private context: common.Context;
  private api?: WebViewFlutterApiImpl;

  constructor(
    instanceManager: InstanceManager,
    webViewProxy: WebViewProxy,
    binaryMessenger: BinaryMessenger,
    context: common.Context
  ) {
    this.instanceManager = instanceManager;
    this.webViewProxy = webViewProxy;
    this.binaryMessenger = binaryMessenger;
    this.context = context;
  }

  setContext(context: common.Context): void {
    this.context = context;
  }

  create(instanceId: number): void {
    const displayProxy = new DisplayListenerProxy();
    displayProxy.onPreWebViewInitialization();
    const webView = this.webViewProxy.createWebView(this.binaryMessenger, this.instanceManager);
    displayProxy.onPostWebViewInitialization();
    this.instanceManager.addDartCreatedInstance(webView, instanceId);
  }

  async loadData(instanceId: number, data: string, mimeType: string, encoding: string): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().loadData(data, mimeType, encoding, ' ', ' ');
  }

  async loadDataWithBaseUrl(
    instanceId: number,
    baseUrl: string,
    data: string,
    mimeType: string,
    encoding: string,
    historyUrl: string
  ): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    try {
      const resolvedBaseUrl = baseUrl == null || baseUrl.trim().length === 0 ? 'resource://rawfile/' : baseUrl;
      const resolvedHistoryUrl = historyUrl == null ? ' ' : historyUrl;
      webView.getController().loadData(data, mimeType, encoding, resolvedBaseUrl, resolvedHistoryUrl);
    } catch (err) {
      Log.e(TAG, 'loadDataWithBaseUrl failed: ' + err);
      throw new Error(String(err));
    }
  }

  async loadUrl(instanceId: number, url: string, headers: Map<string, string>): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    try {
      const webHeaders = this.toWebHeaders(headers);
      if (url.startsWith('resources/rawfile/')) {
        this.allowRawFileUniversalAccess(webView);
        webView.getController().loadUrl($rawfile(url.replace('resources/rawfile/', '')), webHeaders);
      } else {
        webView.getController().loadUrl(url, webHeaders);
      }
      webView.setUrl(webView.getController().getUrl());
    } catch (err) {
      Log.e(TAG, 'loadUrl failed: ' + err);
      throw new Error(String(err));
    }
  }

  async postUrl(instanceId: number, url: string, data: Uint8Array): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    try {
      // A codec may return a view into a larger message buffer.
      const body = new ArrayBuffer(data.byteLength);
      new Uint8Array(body).set(data);
      webView.getController().postUrl(url, body);
    } catch (err) {
      Log.e(TAG, 'postUrl failed: ' + err);
      throw new Error(String(err));
    }
  }

  async getUrl(instanceId: number): Promise<string> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    return webView.getController().getUrl();
  }

  async canGoBack(instanceId: number): Promise<boolean> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    return webView.getController().accessBackward();
  }

  async canGoForward(instanceId: number): Promise<boolean> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    return webView.getController().accessForward();
  }

  async goBack(instanceId: number): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().backward();
  }

  async goForward(instanceId: number): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().forward();
  }

  async reload(instanceId: number): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().refresh();
  }

  setDocumentStartScripts(instanceId: number, scripts: Array<string>): Promise<void> {
    return this.webView(instanceId).setDocumentStartScripts(scripts);
  }

  clearCache(instanceId: number, includeDiskFiles: boolean): void {
    this.webView(instanceId).ensureNotDisposed();
    this.clearAllCache(includeDiskFiles);
  }

  clearAllCache(includeDiskFiles: boolean): void {
    web_webview.WebviewController.initializeWebEngine();
    web_webview.WebviewController.removeAllCache(includeDiskFiles);
  }

  evaluateJavascript(instanceId: number, javascriptString: string, result: Result<string>): void {
    const webView = this.webView(instanceId);
    webView.waitControllerAttached().then(() =>
      webView.getController().runJavaScript(javascriptString)
    ).then((scriptResult: string) => {
      result.success(scriptResult);
    }).catch((error: Error) => {
      result.error(error);
    });
  }

  async getTitle(instanceId: number): Promise<string> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    return webView.getController().getTitle();
  }

  async scrollTo(instanceId: number, x: number, y: number): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().scrollTo(x, y);
  }

  async scrollBy(instanceId: number, x: number, y: number): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().scrollBy(x, y);
  }

  async getScrollX(instanceId: number): Promise<number> {
    return (await this.getScrollPosition(instanceId)).getX();
  }

  async getScrollY(instanceId: number): Promise<number> {
    return (await this.getScrollPosition(instanceId)).getY();
  }

  async getScrollPosition(instanceId: number): Promise<WebViewPoint> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    const controller = webView.getController();
    let offset: web_webview.ScrollOffset;
    try {
      offset = controller.getPageOffset();
    } catch (error) {
      if ((error as ESObject).code !== 801) {
        throw error as Error;
      }
      // Some devices lack getPageOffset despite meeting the SDK baseline.
      offset = controller.getScrollOffset();
    }
    return WebViewPoint.Builder()
      .setX(Math.trunc(offset.x))
      .setY(Math.trunc(offset.y))
      .build();
  }

  setWebContentsDebuggingEnabled(enabled: boolean): void {
    this.webViewProxy.setWebContentsDebuggingEnabled(enabled);
  }

  setWebViewClient(instanceId: number, webViewClientInstanceId: number): void {
    this.webView(instanceId).setWebViewClient(this.instanceManager.getInstance<WebViewClient>(webViewClientInstanceId));
  }

  addJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): void {
    const webView = this.webView(instanceId);
    const channel = this.instanceManager.getInstance<JavaScriptChannel>(javaScriptChannelInstanceId);
    webView.addJavaScriptChannel(channel);
  }

  removeJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): void {
    const webView = this.webView(instanceId);
    const channel = this.instanceManager.getInstance<JavaScriptChannel>(javaScriptChannelInstanceId);
    const channelName = channel.getJavaScriptChannelName();
    webView.removeJavaScriptChannel(channelName);
    this.instanceManager.release(javaScriptChannelInstanceId);
  }

  setDownloadListener(instanceId: number, listenerInstanceId: number): void {
    this.webView(instanceId).setDownloadListener(this.instanceManager.getInstance<DownloadListener>(listenerInstanceId));
  }

  setDownloadDelegate(instanceId: number, enabled: boolean): void {
    if (typeof enabled !== 'boolean') throw new Error('enabled must be a boolean.');
    this.webView(instanceId).setDownloadDelegate(enabled, this.binaryMessenger, instanceId, this.context);
  }

  setWebChromeClient(instanceId: number, clientInstanceId: number): void {
    this.webView(instanceId).setWebChromeClient(this.instanceManager.getInstance<WebChromeClient>(clientInstanceId));
  }

  getInstanceManager(): InstanceManager {
    return this.instanceManager;
  }

  setApi(api: WebViewFlutterApiImpl): void {
    this.api = api;
  }

  private webView(instanceId: number): WebViewPlatformView {
    return this.instanceManager.getInstance<WebViewPlatformView>(instanceId);
  }

  private toWebHeaders(headers: Map<string, string>): Array<web_webview.WebHeader> {
    const result = new Array<web_webview.WebHeader>();
    if (headers == null || headers.size === 0) {
      return result;
    }
    for (const entry of headers) {
      result.push({ headerKey: entry[0], headerValue: entry[1] });
    }
    return result;
  }

  private allowRawFileUniversalAccess(webView: WebViewPlatformView): void {
    try {
      webView.getController().setPathAllowingUniversalAccess([getContext().resourceDir]);
    } catch (err) {
      Log.e(TAG, 'setPathAllowingUniversalAccess failed: ' + err);
    }
  }
}
