import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannel } from './JavaScriptChannel';
import { OhosWebViewCallbackApiChannel, Reply } from './OhosWebViewCallbackApiChannel';

export class JavaScriptChannelFlutterApiImpl {
  private instanceManager: InstanceManager;
  private callbackApi: OhosWebViewCallbackApiChannel;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
    this.callbackApi = new OhosWebViewCallbackApiChannel(binaryMessenger);
  }

  postMessage(
    javaScriptChannel: JavaScriptChannel,
    message: string,
    sourceUrl: string | null,
    callback?: Reply<void>
  ): void {
    this.callbackApi.invoke('JavaScriptChannel.postMessage', new Map<string, ESObject>()
      .set('instanceId', this.getIdentifierForJavaScriptChannel(javaScriptChannel))
      .set('message', message)
      .set('sourceUrl', sourceUrl), callback);
  }

  private getIdentifierForJavaScriptChannel(javaScriptChannel: JavaScriptChannel): number {
    const identifier: number = this.instanceManager.getIdentifier(javaScriptChannel);
    if (identifier == null) {
      throw new Error('Could not find identifier for JavaScriptChannel.');
    }
    return identifier;
  }
}
