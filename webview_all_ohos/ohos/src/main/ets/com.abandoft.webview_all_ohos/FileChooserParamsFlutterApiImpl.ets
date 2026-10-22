import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { InstanceManager } from './InstanceManager';
import { FileChooserMode, OhosWebViewCallbackApiChannel, Reply } from './OhosWebViewCallbackApiChannel';

export class FileChooserParamsFlutterApiImpl {
  private instanceManager: InstanceManager;
  private callbackApi: OhosWebViewCallbackApiChannel;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
    this.callbackApi = new OhosWebViewCallbackApiChannel(binaryMessenger);
  }

  private toFileChooserMode(mode: number): FileChooserMode {
    switch (mode) {
      case FileSelectorMode.FileOpenMode:
        return FileChooserMode.OPEN;
      case FileSelectorMode.FileOpenMultipleMode:
        return FileChooserMode.OPEN_MULTIPLE;
      case FileSelectorMode.FileSaveMode:
        return FileChooserMode.SAVE;
      default:
        throw new Error(`Unsupported FileChooserMode: ${mode}`);
    }
  }

  create(instance: FileSelectorParam, callback?: Reply<void>): void {
    if (this.instanceManager.containsInstance(instance)) {
      callback?.reply();
    } else {
      this.callbackApi.createFileChooserParams(
        this.instanceManager.addHostCreatedInstance(instance),
        instance.isCapture(),
        instance.getAcceptType(),
        this.toFileChooserMode(instance.getMode()),
        instance.getTitle(),
        callback
      );
    }
  }
}
