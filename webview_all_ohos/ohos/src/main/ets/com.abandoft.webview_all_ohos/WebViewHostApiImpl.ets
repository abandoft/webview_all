import common from '@ohos.app.ability.common';
import web_webview from '@ohos.web.webview';
import util from '@ohos.util';
import print from '@ohos.print';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { WebSchemeRegistry } from './WebSchemeRegistry';
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
  setContentRules(instanceId: number, rules: Array<Map<string, ESObject>>): boolean {
    this.webView(instanceId).configureContentRules(this.binaryMessenger, rules); return true;
  }
  async takeScreenshot(instanceId: number): Promise<Uint8Array> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    // Capture the WebView surface itself, without Flutter overlays or a
    // process-wide whole-page drawing setting.
    const pixels = await image.createPixelMapFromSurface(view.getController().getSurfaceId());
    try {
      const info = await pixels.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0 || info.size.width * info.size.height > 16 * 1024 * 1024) throw new Error('The WebView surface exceeds the 16 megapixel capture limit.');
      const packer = image.createImagePacker();
      try {
        const data = await packer.packing(pixels, {format: 'image/png', quality: 100, bufferSize: 64 * 1024 * 1024});
        if (data.byteLength === 0 || data.byteLength > 64 * 1024 * 1024) throw new Error('The screenshot is empty or exceeds the 64 MiB output limit.');
        return new Uint8Array(data);
      } finally { await packer.release(); }
    } finally { await pixels.release(); }
  }
  async createPdf(instanceId: number, options: Map<string, ESObject>): Promise<Uint8Array> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    const width = options.get('paperWidth') as number;
    const height = options.get('paperHeight') as number;
    const top = options.get('marginTop') as number;
    const bottom = options.get('marginBottom') as number;
    const left = options.get('marginLeft') as number;
    const right = options.get('marginRight') as number;
    const landscape = options.get('landscape') === true;
    const w = landscape ? height : width;
    const h = landscape ? width : height;
    if (![width, height, top, bottom, left, right].every((v: number) => Number.isFinite(v) && v >= 0 && v <= 14400) || w <= left + right || h <= top + bottom) throw new Error('Invalid PDF paper or margins.');
    const data = await view.getController().createPdf({width: w / 72, height: h / 72,
      marginTop: top / 72, marginBottom: bottom / 72, marginLeft: left / 72, marginRight: right / 72});
    const bytes = data.pdfArrayBuffer();
    if (bytes.byteLength === 0 || bytes.byteLength > 64 * 1024 * 1024) throw new Error('The PDF is empty or exceeds the 64 MiB limit.');
    return bytes;
  }
  async createArchive(instanceId: number): Promise<Uint8Array> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    const path = this.context.cacheDir + '/webview-all-archive-' + util.generateRandomUUID(true) + '.mht';
    try {
      const saved = await view.getController().storeWebArchive(path, false);
      if (saved !== path) throw new Error('The native archive could not be saved.');
      const size = fs.statSync(path).size;
      if (size <= 0 || size > 64 * 1024 * 1024) throw new Error('The archive is empty or exceeds the 64 MiB limit.');
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const bytes = new Uint8Array(size);
        let offset = 0;
        while (offset < size) {
          const chunk = new ArrayBuffer(Math.min(65536, size - offset));
          const read = fs.readSync(file.fd, chunk, {offset: offset, length: chunk.byteLength});
          if (read <= 0) throw new Error('Reading the archive failed.');
          bytes.set(new Uint8Array(chunk, 0, read), offset);
          offset += read;
        }
        return bytes;
      } finally { fs.closeSync(file); }
    } finally { try { fs.unlinkSync(path); } catch (_) {} }
  }
  async mediaOperation(instanceId: number, method: string, muted: boolean): Promise<boolean> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    if (method === 'setAudioMuted') view.getController().setAudioMuted(muted);
    else if (method === 'pauseMedia') view.getController().pauseAllMedia();
    else return false;
    return true;
  }
  private printJobs: Map<string, print.PrintTask> = new Map<string, print.PrintTask>();
  private printStates: Map<string, string> = new Map<string, string>();

  async printPage(instanceId: number, jobName: string): Promise<Map<string, ESObject> | null> {
    if (jobName.trim().length === 0 || jobName.length > 256 || this.printJobs.size >= 32) return null;
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    const adapter = view.getController().createWebPrintDocumentAdapter(jobName);
    const task = await print.print(jobName, adapter, {}, this.context);
    const id = util.generateRandomUUID(true);
    this.printJobs.set(id, task);
    this.printStates.set(id, 'presented');
    try {
    task.on('block', () => { if (this.printStates.has(id)) this.printStates.set(id, 'blocked'); });
    task.on('succeed', () => { if (this.printStates.has(id)) this.printStates.set(id, 'completed'); });
    task.on('fail', () => { if (this.printStates.has(id)) this.printStates.set(id, 'failed'); });
    task.on('cancel', () => { if (this.printStates.has(id)) this.printStates.set(id, 'cancelled'); });
    } catch (error) { this.releasePrintJob(id); throw new Error('Registering print task events failed: ' + error); }
    const result: Map<string, ESObject> = new Map<string, ESObject>();
    result.set('jobId', id); result.set('state', 'presented');
    result.set('canQuery', true); result.set('canCancel', false);
    return result;
  }
  printJobState(id: string): string { return this.printStates.get(id) ?? 'unknown'; }
  releasePrintJob(id: string): void {
    const task = this.printJobs.get(id);
    if (task) {
      try { task.off('block'); } catch (_) {}
      try { task.off('succeed'); } catch (_) {}
      try { task.off('fail'); } catch (_) {}
      try { task.off('cancel'); } catch (_) {}
    }
    this.printJobs.delete(id); this.printStates.delete(id);
  }
  private navigationStates: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  private navigationModes: Map<string, boolean> = new Map<string, boolean>();

  releaseNavigationState(stateId: string): void {
    this.navigationStates.delete(stateId);
    this.navigationModes.delete(stateId);
  }
  clearNavigationStates(): void {
    this.printJobs.forEach((_task: print.PrintTask, id: string) => this.releasePrintJob(id));
    this.navigationStates.clear();
    this.navigationModes.clear();
  }
  async clearNavigationHistory(instanceId: number): Promise<boolean> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    view.getController().clearHistory();
    return true;
  }
  async saveNavigationState(instanceId: number): Promise<string | null> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    if (this.navigationStates.size >= 16) return null;
    const state: Uint8Array = view.getController().serializeWebState();
    if (state.byteLength === 0 || state.byteLength > 4 * 1024 * 1024) return null;
    const id = util.generateRandomUUID(true);
    this.navigationStates.set(id, state.slice());
    this.navigationModes.set(id, view.isIncognito());
    return id;
  }
  async restoreNavigationState(instanceId: number, stateId: string): Promise<boolean> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    const state = this.navigationStates.get(stateId);
    if (!state || this.navigationModes.get(stateId) !== view.isIncognito()) return false;
    view.getController().restoreWebState(state.slice());
    return true;
  }
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

  create(instanceId: number, incognito: boolean = false, schemes: Array<string> = []): void {
    const registered = WebSchemeRegistry.register(schemes);
    const displayProxy = new DisplayListenerProxy();
    displayProxy.onPreWebViewInitialization();
    const webView = this.webViewProxy.createWebView(this.binaryMessenger, this.instanceManager);
    webView.setIncognito(incognito);
    webView.declaredCustomSchemes = registered;
    displayProxy.onPostWebViewInitialization();
    this.instanceManager.addDartCreatedInstance(webView, instanceId);
  }
  supportsCustomSchemes(instanceId: number, schemes: Array<string>): boolean {
    return schemes.every((name: string) => this.webView(instanceId).declaredCustomSchemes.includes(name));
  }
  configureNetworkBridge(instanceId: number, name: string, schemes: Array<string>, enabled: boolean): boolean {
    const view = this.webView(instanceId);
    if (schemes.length === 0 || !schemes.every((scheme: string) => view.declaredCustomSchemes.includes(scheme))) return false;
    view.configureCustomSchemes(this.binaryMessenger, name, schemes, enabled); return true;
  }

  closeSession(instanceId: number): void {
    this.webView(instanceId).dispose();
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

  async stopLoading(instanceId: number): Promise<void> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    view.getController().stop();
  }
  async getNavigationHistory(instanceId: number): Promise<Map<string, number | Array<Map<string, string>>>> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    const history: web_webview.BackForwardList = view.getController().getBackForwardEntries();
    const items: Array<Map<string, string>> = [];
    for (let index = 0; index < history.size; index++) {
      const item = history.getItemAtIndex(index);
      const data = new Map<string, string>();
      data.set('url', item.historyUrl);
      data.set('originalUrl', item.historyRawUrl);
      data.set('title', item.title);
      items.push(data);
    }
    const result = new Map<string, number | Array<Map<string, string>>>();
    result.set('currentIndex', history.size > 0 ? history.currentIndex : -1);
    result.set('items', items);
    return result;
  }
  async goToHistoryIndex(instanceId: number, index: number): Promise<boolean> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    const history: web_webview.BackForwardList = view.getController().getBackForwardEntries();
    if (!Number.isInteger(index) || index < 0 || index >= history.size) return false;
    if (index !== history.currentIndex) view.getController().backOrForward(index - history.currentIndex);
    return true;
  }
  async findText(instanceId: number, text: string, forward: boolean): Promise<Map<string, boolean | number> | null> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    return view.findText(text, forward);
  }
  async clearFindMatches(instanceId: number): Promise<void> {
    const view = this.webView(instanceId);
    await view.waitControllerAttached();
    view.cancelFind();
    view.getController().clearMatches();
  }
  setPopupWindowPolicy(instanceId: number, policy: number): void {
    const view = this.webView(instanceId);
    view.ensureNotDisposed();
    view.denyPopups = policy === 1;
  }
  setFullscreenDelegateEnabled(instanceId: number, enabled: boolean): void {
    const view = this.webView(instanceId);
    view.ensureNotDisposed();
    view.fullscreenDelegateEnabled = enabled;
  }
  exitFullscreen(instanceId: number): boolean {
    return this.webView(instanceId).exitFullscreen();
  }

  async reload(instanceId: number): Promise<void> {
    const webView = this.webView(instanceId);
    await webView.waitControllerAttached();
    webView.getController().refresh();
  }

  setDocumentStartScripts(instanceId: number, scripts: Array<string>, endScripts: Array<string> = []): Promise<void> {
    return this.webView(instanceId).setDocumentStartScripts(scripts, endScripts);
  }

  clearCache(instanceId: number, includeDiskFiles: boolean): void {
    const view = this.webView(instanceId);
    view.ensureNotDisposed();
    if (view.isIncognito()) {
      Log.e(TAG, 'Private cache clearing is unavailable: ArkWeb only exposes a global cache operation.');
      return;
    }
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

  configureResources(instanceId: number, channel: string, host: string, enabled: boolean): void {
    this.webView(instanceId).configureResources(this.binaryMessenger, channel, host, enabled);
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
