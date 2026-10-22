import { SslAuthHandler } from './OhosWebViewCallbackApiChannel';
import { InstanceManager } from './InstanceManager';
import { completeNativeCallback } from './NativeCallback';

export class SslAuthHandlerHostApiImpl {
  private readonly instanceManager: InstanceManager;

  constructor(_binaryMessenger: ESObject, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
  }

  cancel(instanceId: number): void {
    completeNativeCallback<SslAuthHandler>(this.instanceManager, instanceId, (handler: SslAuthHandler) => {
      handler.cancel();
    });
  }

  proceed(instanceId: number): void {
    completeNativeCallback<SslAuthHandler>(this.instanceManager, instanceId, (handler: SslAuthHandler) => {
      handler.proceed();
    });
  }
}
