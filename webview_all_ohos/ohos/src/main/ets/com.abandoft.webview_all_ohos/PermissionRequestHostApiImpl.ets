import { InstanceManager } from './InstanceManager';
import { completeNativeCallback } from './NativeCallback';

export class PermissionRequestHostApiImpl {
  private readonly instanceManager: InstanceManager;

  constructor(_binaryMessenger: ESObject, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
  }

  grant(instanceId: number, resources: string[]): void {
    completeNativeCallback<PermissionRequest>(this.instanceManager, instanceId, (request: PermissionRequest) => {
      request.grant(resources);
    });
  }

  deny(instanceId: number): void {
    completeNativeCallback<PermissionRequest>(this.instanceManager, instanceId, (request: PermissionRequest) => {
      request.deny();
    });
  }
}
