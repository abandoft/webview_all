import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodChannel, { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const CHANNEL_NAME = 'com.abandoft.webview_all_ohos/callback_api';
const TAG = 'OhosWebViewCallbackApiChannel';

export interface Reply<T> {
  reply: (value: T) => void;
  error?: (error: Error) => void;
}

export enum FileChooserMode {
  OPEN,
  OPEN_MULTIPLE,
  SAVE
}

export enum ConsoleMessageLevel {
  DEBUG,
  ERROR,
  LOG,
  TIP,
  WARNING,
  UNKNOWN
}

export interface CustomViewCallback {
  onCustomViewHidden(): void;
}

export interface HttpAuthHandler {
  cancel(): void;
  proceed(username: string, password: string): void;
  useHttpAuthUsernamePassword(): boolean;
}

export interface SslAuthHandler {
  cancel(): void;
  proceed(): void;
}

export class OhosWebViewCallbackApiChannel {
  private channel: MethodChannel;

  constructor(binaryMessenger: BinaryMessenger) {
    this.channel = new MethodChannel(binaryMessenger, CHANNEL_NAME);
  }

  invoke<T>(method: string, args: ESObject, callback?: Reply<T>): void {
    const result = this.resultFor(method, callback);
    try {
      this.channel.invokeMethod(method, args, result);
    } catch (error) {
      result.error('CallbackSendFailed', String(error), null);
    }
  }

  createWebView(identifier: number, callback?: Reply<void>): void {
    this.invoke('WebView.create', new Map<string, ESObject>().set('identifier', identifier), callback);
  }

  onWebViewScrollChanged(
    webViewInstanceId: number,
    left: number,
    top: number,
    oldLeft: number,
    oldTop: number,
    callback?: Reply<void>
  ): void {
    this.invoke('WebView.onScrollChanged', new Map<string, ESObject>()
      .set('webViewInstanceId', webViewInstanceId)
      .set('left', left)
      .set('top', top)
      .set('oldLeft', oldLeft)
      .set('oldTop', oldTop), callback);
  }

  createFileChooserParams(
    instanceId: number,
    isCaptureEnabled: boolean,
    acceptTypes: string[],
    mode: FileChooserMode,
    filenameHint: string,
    callback?: Reply<void>
  ): void {
    this.invoke('FileChooserParams.create', new Map<string, ESObject>()
      .set('instanceId', instanceId)
      .set('isCaptureEnabled', isCaptureEnabled)
      .set('acceptTypes', acceptTypes)
      .set('mode', mode)
      .set('filenameHint', filenameHint), callback);
  }

  createPermissionRequest(identifier: number, resources: string[], callback?: Reply<void>): void {
    this.invoke('PermissionRequest.create', new Map<string, ESObject>()
      .set('identifier', identifier)
      .set('resources', resources), callback);
  }

  createCustomViewCallback(identifier: number, callback?: Reply<void>): void {
    this.invoke('CustomViewCallback.create', new Map<string, ESObject>().set('identifier', identifier), callback);
  }

  createView(identifier: number, callback?: Reply<void>): void {
    this.invoke('View.create', new Map<string, ESObject>().set('identifier', identifier), callback);
  }

  createGeolocationPermissionsCallback(instanceId: number, callback?: Reply<void>): void {
    this.invoke('GeolocationPermissionsCallback.create',
      new Map<string, ESObject>().set('instanceId', instanceId), callback);
  }

  createHttpAuthHandler(instanceId: number, callback?: Reply<void>): void {
    this.invoke('HttpAuthHandler.create', new Map<string, ESObject>().set('instanceId', instanceId), callback);
  }

  createSslAuthHandler(instanceId: number, callback?: Reply<void>): void {
    this.invoke('SslAuthHandler.create', new Map<string, ESObject>().set('instanceId', instanceId), callback);
  }

  private resultFor<T>(method: string, callback?: Reply<T>): MethodResult {
    let completed = false;
    const fail = (error: Error): void => {
      // Do not log callback arguments or error details, which can contain page
      // data. Native event handlers must never throw a Dart-channel error.
      Log.e(TAG, method + ' failed: ' + error.message);
      try {
        callback?.error?.(error);
      } catch (fallbackError) {
        Log.e(TAG, method + ' cancellation failed: ' + String(fallbackError));
      }
    };
    return {
      success: (result: ESObject): void => {
        if (completed) return;
        completed = true;
        try {
          callback?.reply(result as T);
        } catch (error) {
          fail(new Error(String(error)));
        }
      },
      error: (errorCode: string, errorMessage: string, _errorDetails: ESObject): void => {
        if (completed) return;
        completed = true;
        fail(new Error(errorCode + ': ' + errorMessage));
      },
      notImplemented: (): void => {
        if (completed) return;
        completed = true;
        fail(new Error('Dart callback method is not implemented.'));
      }
    };
  }
}

export function emptyReply<T>(): Reply<T> {
  return {
    reply: (_value: T): void => {
    }
  };
}
