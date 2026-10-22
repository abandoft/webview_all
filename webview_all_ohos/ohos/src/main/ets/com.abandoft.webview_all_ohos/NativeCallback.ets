import { InstanceManager } from './InstanceManager';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { Reply } from './OhosWebViewCallbackApiChannel';

// Removing the registration is the terminal marker shared by a Dart response
// and an error fallback. A late second response cannot act on the native object.
export function completeNativeCallback<T>(
  instanceManager: InstanceManager,
  identifier: number,
  complete: (instance: T) => void
): void {
  const instance: ESObject | null = instanceManager.release(identifier);
  if (instance != null) {
    complete(instance as T);
  }
}

export class PendingNativeCallback<T> {
  private readonly instanceManager: InstanceManager;
  private readonly instance: T;
  private registered: boolean = false;
  private failed: boolean = false;

  constructor(instanceManager: InstanceManager, instance: T) {
    this.instanceManager = instanceManager;
    this.instance = instance;
  }

  markRegistered(): void {
    this.registered = true;
  }

  fail(error: Error, reject: (instance: T) => void, callback?: Reply<void>): void {
    if (this.failed) return;
    this.failed = true;
    try {
      const identifier = this.instanceManager.getIdentifier(this.instance);
      if (identifier >= 0) {
        completeNativeCallback<T>(this.instanceManager, identifier, reject);
      } else if (!this.registered) {
        // Registration can itself fail before Dart learns about the object.
        reject(this.instance);
      }
    } catch (cancelError) {
      Log.e('NativeCallback', 'Failed to cancel native callback: ' + String(cancelError));
    }
    try {
      callback?.error?.(error);
    } catch (callbackError) {
      Log.e('NativeCallback', 'Failure callback threw: ' + String(callbackError));
    }
  }
}
