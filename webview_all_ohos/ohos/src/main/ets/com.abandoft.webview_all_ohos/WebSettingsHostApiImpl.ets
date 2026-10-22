import { InstanceManager } from './InstanceManager';
import { WebViewPlatformView } from './WebViewPlatformView';
import { WebViewSettingsSnapshot } from './WebViewSettingsSnapshot';

export interface WebSettings {
  getSnapshot(): WebViewSettingsSnapshot;
  onSettingsChanged(callback?: (snapshot: WebViewSettingsSnapshot) => void): void;
  markApplied(revision: number): void;
  waitUntilApplied(): Promise<void>;
  setDomStorageEnabled(flag: boolean): void;
  getDomStorageEnabled(): boolean;
  setJavaScriptCanOpenWindowsAutomatically(flag: boolean): void;
  getJavaScriptCanOpenWindowsAutomatically(): boolean;
  setSupportMultipleWindows(support: boolean): void;
  getSupportMultipleWindows(): boolean;
  setBackgroundColor(color: number): void;
  getBackgroundColor(): string;
  setJavaScriptEnabled(flag: boolean): void;
  getJavaScriptEnabled(): boolean;
  setUserAgentString(userAgentString: string | null): Promise<void>;
  setMediaPlaybackRequiresUserGesture(require: boolean): void;
  getMediaPlaybackRequiresUserGesture(): boolean;
  setSupportZoom(support: boolean): void;
  getSupportZoom(): boolean;
  setLoadWithOverviewMode(overview: boolean): void;
  getLoadWithOverviewMode(): boolean;
  setUseWideViewPort(use: boolean): void;
  getUseWideViewPort(): boolean;
  setDisplayZoomControls(enabled: boolean): void;
  setBuiltInZoomControls(enabled: boolean): void;
  setAllowFileAccess(enabled: boolean): void;
  getAllowFileAccess(): boolean;
  setMixedContentMode(mode: string): void;
  getMixedContentMode(): MixedMode;
  onMixedContentModeChanged(callback?: (mode: MixedMode) => void): void;
  setTextZoom(textZoom: number): void;
  getTextZoom(): number;
  getUserAgentString(): Promise<string>;
  onTextZoomChanged(callback?: (ratio: number) => void): void;
  setAllowFullScreenRotate(enabled: boolean): void;
  getAllowFullScreenRotate(): boolean;
}

export class WebSettingsCreator {
  createWebSettings(webView: WebViewPlatformView): WebSettings {
    return webView.getWebSettings();
  }
}

export class WebSettingsHostApiImpl {
  private readonly instanceManager: InstanceManager;
  private readonly creator: WebSettingsCreator;

  constructor(instanceManager: InstanceManager, creator: WebSettingsCreator) {
    this.instanceManager = instanceManager;
    this.creator = creator;
  }

  create(instanceId: number, webViewInstanceId: number): void {
    const webView = this.instanceManager.getInstance<WebViewPlatformView>(webViewInstanceId);
    this.instanceManager.addDartCreatedInstance(this.creator.createWebSettings(webView), instanceId);
  }

  setDomStorageEnabled(instanceId: number, flag: boolean): void {
    this.settings(instanceId).setDomStorageEnabled(flag);
  }

  setJavaScriptCanOpenWindowsAutomatically(instanceId: number, flag: boolean): void {
    this.settings(instanceId).setJavaScriptCanOpenWindowsAutomatically(flag);
  }

  setSupportMultipleWindows(instanceId: number, support: boolean): void {
    this.settings(instanceId).setSupportMultipleWindows(support);
  }

  setBackgroundColor(instanceId: number, color: number): void {
    this.settings(instanceId).setBackgroundColor(color);
  }

  setJavaScriptEnabled(instanceId: number, flag: boolean): void {
    this.settings(instanceId).setJavaScriptEnabled(flag);
  }

  setUserAgentString(instanceId: number, userAgentString: string | null): Promise<void> {
    return this.settings(instanceId).setUserAgentString(userAgentString);
  }

  setMediaPlaybackRequiresUserGesture(instanceId: number, require: boolean): void {
    this.settings(instanceId).setMediaPlaybackRequiresUserGesture(require);
  }

  setSupportZoom(instanceId: number, support: boolean): void {
    this.settings(instanceId).setSupportZoom(support);
  }

  setLoadWithOverviewMode(instanceId: number, overview: boolean): void {
    this.settings(instanceId).setLoadWithOverviewMode(overview);
  }

  setUseWideViewPort(instanceId: number, use: boolean): void {
    this.settings(instanceId).setUseWideViewPort(use);
  }

  setDisplayZoomControls(instanceId: number, enabled: boolean): void {
    this.settings(instanceId).setDisplayZoomControls(enabled);
  }

  setBuiltInZoomControls(instanceId: number, enabled: boolean): void {
    this.settings(instanceId).setBuiltInZoomControls(enabled);
  }

  setAllowFileAccess(instanceId: number, enabled: boolean): void {
    this.settings(instanceId).setAllowFileAccess(enabled);
  }

  setMixedContentMode(instanceId: number, mode: string): void {
    this.settings(instanceId).setMixedContentMode(mode);
  }

  setTextZoom(instanceId: number, textZoom: number): void {
    this.settings(instanceId).setTextZoom(textZoom);
  }

  getUserAgentString(instanceId: number): Promise<string> {
    return this.settings(instanceId).getUserAgentString();
  }

  setAllowFullScreenRotate(instanceId: number, enabled: boolean): void {
    this.settings(instanceId).setAllowFullScreenRotate(enabled);
  }

  private settings(instanceId: number): WebSettings {
    return this.instanceManager.getInstance<WebSettings>(instanceId);
  }
}
