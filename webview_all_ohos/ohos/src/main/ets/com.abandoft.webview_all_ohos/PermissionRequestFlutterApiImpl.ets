import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { InstanceManager } from './InstanceManager';
import { OhosWebViewCallbackApiChannel, Reply } from './OhosWebViewCallbackApiChannel';

export class PermissionRequestFlutterApiImpl {
  private instanceManager: InstanceManager;
  private callbackApi: OhosWebViewCallbackApiChannel;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
    this.callbackApi = new OhosWebViewCallbackApiChannel(binaryMessenger);
  }

  create(instance: PermissionRequest, resources: string[], callback?: Reply<void>): void {
    if (this.instanceManager.containsInstance(instance)) {
      callback?.reply();
    } else {
      this.callbackApi.createPermissionRequest(
        this.instanceManager.addHostCreatedInstance(instance),
        resources,
        callback
      );
    }
  }
}
