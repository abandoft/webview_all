import { HttpAuthHandler } from './OhosWebViewCallbackApiChannel';
import { InstanceManager } from './InstanceManager';
import { completeNativeCallback } from './NativeCallback';

export class HttpAuthHandlerHostApiImpl {
  private readonly instanceManager: InstanceManager;

  constructor(_binaryMessenger: ESObject, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
  }

  useHttpAuthUsernamePassword(instanceId: number): boolean {
    return this.handler(instanceId).useHttpAuthUsernamePassword();
  }

  cancel(instanceId: number): void {
    completeNativeCallback<HttpAuthHandler>(this.instanceManager, instanceId, (handler: HttpAuthHandler) => {
      handler.cancel();
    });
  }

  proceed(instanceId: number, username: string, password: string): void {
    completeNativeCallback<HttpAuthHandler>(this.instanceManager, instanceId, (handler: HttpAuthHandler) => {
      handler.proceed(username, password);
    });
  }

  private handler(instanceId: number): HttpAuthHandler {
    return this.instanceManager.getInstance<HttpAuthHandler>(instanceId);
  }
}
