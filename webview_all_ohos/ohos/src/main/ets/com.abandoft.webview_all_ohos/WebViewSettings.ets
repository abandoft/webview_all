import web_webview from '@ohos.web.webview';
import { WebSettings } from './WebSettingsHostApiImpl';
import { WebViewPlatformView } from './WebViewPlatformView';
import { WebViewSettingsSnapshot } from './WebViewSettingsSnapshot';

interface SettingsAppliedWaiter {
  revision: number;
  resolve: () => void;
  reject: (error: Error) => void;
}

export class WebViewSettings implements WebSettings {
  private readonly webView: WebViewPlatformView;
  private defaultUserAgent: string = '';
  private domStorageEnabled: boolean = false;
  private javaScriptCanOpenWindows: boolean = false;
  private multipleWindowsEnabled: boolean = false;
  private backgroundColor: string = '';
  private javaScriptEnabled: boolean = false;
  private mediaRequiresUserGesture: boolean = false;
  private zoomEnabled: boolean = true;
  private overviewModeEnabled: boolean = false;
  private wideViewportEnabled: boolean = false;
  private fileAccessEnabled: boolean = true;
  private mixedContentMode: MixedMode = MixedMode.None;
  private mixedContentModeCallback?: (mode: MixedMode) => void;
  private textZoomRatio: number = 100;
  private textZoomCallback?: (ratio: number) => void;
  private fullScreenRotateEnabled: boolean = false;
  private settingsChangedCallback?: (snapshot: WebViewSettingsSnapshot) => void;
  private revision: number = 0;
  private appliedRevision: number = -1;
  private appliedWaiters: Array<SettingsAppliedWaiter> = [];

  constructor(webView: WebViewPlatformView) {
    this.webView = webView;
  }

  getSnapshot(): WebViewSettingsSnapshot {
    const snapshot = new WebViewSettingsSnapshot();
    snapshot.revision = this.revision;
    snapshot.backgroundColor = this.backgroundColor;
    snapshot.domStorageEnabled = this.domStorageEnabled;
    snapshot.javaScriptCanOpenWindowsAutomatically = this.javaScriptCanOpenWindows;
    snapshot.supportMultipleWindows = this.multipleWindowsEnabled;
    snapshot.javaScriptEnabled = this.javaScriptEnabled;
    snapshot.mediaPlaybackRequiresUserGesture = this.mediaRequiresUserGesture;
    snapshot.supportZoom = this.zoomEnabled;
    snapshot.loadWithOverviewMode = this.overviewModeEnabled;
    snapshot.useWideViewPort = this.wideViewportEnabled;
    snapshot.allowFileAccess = this.fileAccessEnabled;
    snapshot.mixedContentMode = this.mixedContentMode;
    snapshot.textZoom = this.textZoomRatio;
    return snapshot;
  }

  onSettingsChanged(callback?: (snapshot: WebViewSettingsSnapshot) => void): void {
    this.settingsChangedCallback = callback;
    if (callback == null) {
      this.appliedRevision = -1;
      const waiters = this.appliedWaiters;
      this.appliedWaiters = [];
      for (const waiter of waiters) {
        waiter.reject(new Error('WebView settings detached before they were applied.'));
      }
    }
  }

  markApplied(revision: number): void {
    if (this.settingsChangedCallback == null || revision > this.revision || revision < this.appliedRevision) {
      return;
    }
    this.appliedRevision = revision;
    const pending: Array<SettingsAppliedWaiter> = [];
    for (const waiter of this.appliedWaiters) {
      if (waiter.revision <= revision) {
        waiter.resolve();
      } else {
        pending.push(waiter);
      }
    }
    this.appliedWaiters = pending;
  }

  async waitUntilApplied(): Promise<void> {
    if (this.settingsChangedCallback == null || this.appliedRevision >= this.revision) {
      return;
    }
    await new Promise<void>((resolve, reject) => {
      this.appliedWaiters.push({ revision: this.revision, resolve: resolve, reject: reject });
    });
  }

  private notifySettingsChanged(): void {
    this.revision++;
    this.settingsChangedCallback?.(this.getSnapshot());
  }

  setDomStorageEnabled(flag: boolean): void {
    this.domStorageEnabled = flag;
    this.notifySettingsChanged();
  }

  getDomStorageEnabled(): boolean {
    return this.domStorageEnabled;
  }

  setJavaScriptCanOpenWindowsAutomatically(flag: boolean): void {
    this.javaScriptCanOpenWindows = flag;
    this.notifySettingsChanged();
  }

  getJavaScriptCanOpenWindowsAutomatically(): boolean {
    return this.javaScriptCanOpenWindows;
  }

  setSupportMultipleWindows(support: boolean): void {
    this.multipleWindowsEnabled = support;
    this.notifySettingsChanged();
  }

  getSupportMultipleWindows(): boolean {
    return this.multipleWindowsEnabled;
  }

  setBackgroundColor(color: number): void {
    this.backgroundColor = '#' + color.toString(16).padStart(8, '0');
    this.notifySettingsChanged();
  }

  getBackgroundColor(): string {
    return this.backgroundColor;
  }

  setJavaScriptEnabled(flag: boolean): void {
    this.javaScriptEnabled = flag;
    this.notifySettingsChanged();
  }

  getJavaScriptEnabled(): boolean {
    return this.javaScriptEnabled;
  }

  async setUserAgentString(userAgentString: string | null): Promise<void> {
    this.webView.ensureNotDisposed();
    const userAgent = userAgentString ?? '';
    if (!this.webView.isWebviewBinding) {
      // Settings can be configured before the platform view is mounted.
      this.webView.userAgentString = userAgent;
      return;
    }
    await this.webView.waitControllerAttached();
    this.webView.setCustomUserAgent(userAgent);
  }

  setMediaPlaybackRequiresUserGesture(require: boolean): void {
    this.mediaRequiresUserGesture = require;
    this.notifySettingsChanged();
  }

  getMediaPlaybackRequiresUserGesture(): boolean {
    return this.mediaRequiresUserGesture;
  }

  setSupportZoom(support: boolean): void {
    this.zoomEnabled = support;
    this.notifySettingsChanged();
  }

  getSupportZoom(): boolean {
    return this.zoomEnabled;
  }

  setLoadWithOverviewMode(overview: boolean): void {
    this.overviewModeEnabled = overview;
    this.notifySettingsChanged();
  }

  getLoadWithOverviewMode(): boolean {
    return this.overviewModeEnabled;
  }

  setUseWideViewPort(use: boolean): void {
    this.wideViewportEnabled = use;
    this.notifySettingsChanged();
  }

  getUseWideViewPort(): boolean {
    return this.wideViewportEnabled;
  }

  setDisplayZoomControls(_enabled: boolean): void {
  }

  setBuiltInZoomControls(_enabled: boolean): void {
  }

  setAllowFileAccess(enabled: boolean): void {
    this.fileAccessEnabled = enabled;
    this.notifySettingsChanged();
  }

  getAllowFileAccess(): boolean {
    return this.fileAccessEnabled;
  }

  setMixedContentMode(mode: string): void {
    switch (mode) {
      case 'neverAllow':
        this.mixedContentMode = MixedMode.None;
        break;
      case 'alwaysAllow':
        this.mixedContentMode = MixedMode.All;
        break;
      case 'compatibilityMode':
        this.mixedContentMode = MixedMode.Compatible;
        break;
      default:
        throw new Error('Invalid mixed content mode.');
    }
    this.notifySettingsChanged();
    this.mixedContentModeCallback?.(this.mixedContentMode);
  }

  getMixedContentMode(): MixedMode {
    return this.mixedContentMode;
  }

  onMixedContentModeChanged(callback?: (mode: MixedMode) => void): void {
    this.mixedContentModeCallback = callback;
  }

  setTextZoom(textZoom: number): void {
    this.textZoomRatio = textZoom;
    this.notifySettingsChanged();
    if (this.textZoomCallback) {
      this.textZoomCallback(textZoom);
    }
  }

  getTextZoom(): number {
    return this.textZoomRatio;
  }

  async getUserAgentString(): Promise<string> {
    this.webView.ensureNotDisposed();
    if (this.webView.userAgentString.length > 0) {
      return this.webView.userAgentString;
    }
    if (this.webView.isWebviewBinding) {
      await this.webView.waitControllerAttached();
      const customUserAgent = this.webView.getController().getCustomUserAgent();
      if (customUserAgent.length > 0) {
        return customUserAgent;
      }
    }
    if (this.defaultUserAgent.length > 0) {
      return this.defaultUserAgent;
    }
    web_webview.WebviewController.initializeWebEngine();
    this.defaultUserAgent = web_webview.WebviewController.getDefaultUserAgent();
    return this.defaultUserAgent;
  }

  onTextZoomChanged(callback?: (ratio: number) => void): void {
    this.textZoomCallback = callback;
  }

  setAllowFullScreenRotate(enabled: boolean): void {
    this.fullScreenRotateEnabled = enabled;
  }

  getAllowFullScreenRotate(): boolean {
    return this.fullScreenRotateEnabled;
  }
}
