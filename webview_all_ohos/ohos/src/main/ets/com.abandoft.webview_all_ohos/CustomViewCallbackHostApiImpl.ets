import { CustomViewCallback } from './OhosWebViewCallbackApiChannel';
import { InstanceManager } from './InstanceManager';
import { completeNativeCallback } from './NativeCallback';

export class CustomViewCallbackHostApiImpl {
  private readonly instanceManager: InstanceManager;

  constructor(_binaryMessenger: ESObject, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
  }

  onCustomViewHidden(identifier: number): void {
    completeNativeCallback<CustomViewCallback>(this.instanceManager, identifier, (callback: CustomViewCallback) => {
      callback.onCustomViewHidden();
    });
  }
}
