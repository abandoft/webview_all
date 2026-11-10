import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { InstanceManager } from './InstanceManager';
import { OhosWebViewCallbackApiChannel, Reply } from './OhosWebViewCallbackApiChannel';
import { WebViewPlatformView } from './WebViewPlatformView';

export class WebViewFlutterApiImpl {
  private instanceManager: InstanceManager;
  private callbackApi: OhosWebViewCallbackApiChannel;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
    this.callbackApi = new OhosWebViewCallbackApiChannel(binaryMessenger);
  }

  create(instance: WebViewPlatformView, callback?: Reply<void>): void {
    if (!this.instanceManager.containsInstance(instance)) {
      this.callbackApi.createWebView(
        this.instanceManager.addHostCreatedInstance(instance),
        callback
      );
    }
  }

  onBrowserEvent(instance: WebViewPlatformView, event: Map<string, ESObject>): void {
    this.callbackApi.invoke<void>('WebView.browserEvent', new Map<string, ESObject>()
      .set('webViewInstanceId', this.instanceManager.getIdentifier(instance))
      .set('event', event));
  }

  onScrollChanged(
    instance: WebViewPlatformView,
    left: number,
    top: number,
    oldLeft: number,
    oldTop: number,
    callback?: Reply<void>
  ): void {
    this.callbackApi.onWebViewScrollChanged(
      this.instanceManager.getIdentifier(instance),
      left,
      top,
      oldLeft,
      oldTop,
      callback
    );
  }
}
