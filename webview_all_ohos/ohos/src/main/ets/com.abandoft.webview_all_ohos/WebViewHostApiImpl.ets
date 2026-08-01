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

  loadData(instanceId: number, data: string, mimeType: string, encoding: string): void {
    const webView = this.webView(instanceId);
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
      throw err;
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
      throw err;
    }
  }

  async postUrl(instanceId: number, url: string, data: Uint8Array): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    try {
      webView.getController().postUrl(url, data.buffer);
    } catch (err) {
      Log.e(TAG, 'postUrl failed: ' + err);
      throw err;
    }
  }

  async getUrl(instanceId: number): Promise<string> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    return webView.getController().getUrl();
  }

  canGoBack(instanceId: number): boolean {
    return this.webView(instanceId).getController().accessBackward();
  }

  canGoForward(instanceId: number): boolean {
    return this.webView(instanceId).getController().accessForward();
  }

  goBack(instanceId: number): void {
    this.webView(instanceId).getController().backward();
  }

  goForward(instanceId: number): void {
    this.webView(instanceId).getController().forward();
  }

  reload(instanceId: number): void {
    this.webView(instanceId).getController().refresh();
  }

  clearCache(instanceId: number, includeDiskFiles: boolean): void {
    const webView = this.webView(instanceId);
    webView.waitControllerAttached().then(() => {
      webView.getController().removeCache(includeDiskFiles);
    }).catch((err: Error) => {
      Log.e(TAG, 'clearCache failed: ' + err.message);
    });
  }

  evaluateJavascript(instanceId: number, javascriptString: string, result: Result<string>): void {
    const webView = this.webView(instanceId);
    webView.getController().runJavaScript(javascriptString).then((scriptResult: string) => {
      result.success(scriptResult);
    }).catch((error: Error) => {
      result.error(error);
    });
  }

  getTitle(instanceId: number): string {
    return this.webView(instanceId).getController().getTitle();
  }

  scrollTo(instanceId: number, x: number, y: number): void {
    const webView = this.webView(instanceId);
    webView.waitControllerAttached().then(() => {
      webView.getController().scrollTo(x, y);
      webView.setScrollPosition(x, y);
    });
  }

  scrollBy(instanceId: number, x: number, y: number): void {
    const webView = this.webView(instanceId);
    webView.waitControllerAttached().then(() => {
      const nextX = webView.getScrollX() + x;
      const nextY = webView.getScrollY() + y;
      webView.getController().scrollBy(x, y);
      webView.setScrollPosition(nextX, nextY);
    });
  }

  getScrollX(instanceId: number): number {
    return this.webView(instanceId).getScrollX();
  }

  getScrollY(instanceId: number): number {
    return this.webView(instanceId).getScrollY();
  }

  getScrollPosition(instanceId: number): WebViewPoint {
    const webView = this.webView(instanceId);
    return WebViewPoint.Builder()
      .setX(webView.getScrollX())
      .setY(webView.getScrollY())
      .build();
  }

  setWebContentsDebuggingEnabled(enabled: boolean): void {
    this.webViewProxy.setWebContentsDebuggingEnabled(enabled);
  }

  setWebViewClient(instanceId: number, webViewClientInstanceId: number): void {
    this.webView(instanceId).setWebViewClient(this.instanceManager.getInstance<WebViewClient>(webViewClientInstanceId));
  }

  async addJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): Promise<void> {
    const webView = this.webView(instanceId);
    const channel = this.instanceManager.getInstance<JavaScriptChannel>(javaScriptChannelInstanceId);
    await webView.waitControllerAttached();
    try {
      webView.addJavaScriptChannel(channel);
      webView.getController().registerJavaScriptProxy(
        {
          postMessage: (message: ESObject): void => {
            channel.postMessage(String(message));
          }
        },
        channel.getJavaScriptChannelName(),
        ['postMessage']
      );
      webView.getController().refresh();
    } catch (err) {
      Log.e(TAG, 'addJavaScriptChannel failed: ' + err);
    }
  }

  removeJavaScriptChannel(instanceId: number, javaScriptChannelInstanceId: number): void {
    const webView = this.webView(instanceId);
    const channel = this.instanceManager.getInstance<JavaScriptChannel>(javaScriptChannelInstanceId);
    const channelName = channel.getJavaScriptChannelName();
    webView.removeJavaScriptChannel(channelName);
    webView.getController().deleteJavaScriptRegister(channelName);
    this.instanceManager.remove(javaScriptChannelInstanceId);
  }

  setDownloadListener(instanceId: number, listenerInstanceId: number): void {
    this.webView(instanceId).setDownloadListener(this.instanceManager.getInstance<DownloadListener>(listenerInstanceId));
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
