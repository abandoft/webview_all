import { InstanceManager } from './InstanceManager';
import { completeNativeCallback } from './NativeCallback';

export class GeolocationPermissionsCallbackHostApiImpl {
  private readonly instanceManager: InstanceManager;

  constructor(_binaryMessenger: ESObject, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
  }

  invoke(instanceId: number, origin: string, allow: boolean, retain: boolean): void {
    completeNativeCallback<JsGeolocation>(this.instanceManager, instanceId, (callback: JsGeolocation) => {
      callback.invoke(origin, allow, retain);
    });
  }
}
