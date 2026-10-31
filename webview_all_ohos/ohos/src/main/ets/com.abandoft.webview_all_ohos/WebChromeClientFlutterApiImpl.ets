import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { DVModel } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView';
import { CustomViewCallbackFlutterApiImpl } from './CustomViewCallbackFlutterApiImpl';
import { FileChooserParamsFlutterApiImpl } from './FileChooserParamsFlutterApiImpl';
import { GeolocationPermissionsCallbackFlutterApiImpl } from './GeolocationPermissionsCallbackFlutterApiImpl';
import { InstanceManager } from './InstanceManager';
import { PendingNativeCallback } from './NativeCallback';
import {
  ConsoleMessageLevel,
  CustomViewCallback,
  OhosWebViewCallbackApiChannel,
  Reply,
  emptyReply
} from './OhosWebViewCallbackApiChannel';
import { PermissionRequestFlutterApiImpl } from './PermissionRequestFlutterApiImpl';
import { ViewFlutterApiImpl } from './ViewFlutterApiImpl';
import { WebChromeClient } from './WebChromeClientHostApiImpl';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl';
import { WebViewPlatformView } from './WebViewPlatformView';

export class WebChromeClientFlutterApiImpl {
  private binaryMessenger: BinaryMessenger;
  private instanceManager: InstanceManager;
  private webViewFlutterApi: WebViewFlutterApiImpl;
  private callbackApi: OhosWebViewCallbackApiChannel;

  constructor(binaryMessenger: BinaryMessenger, instanceManager: InstanceManager) {
    this.binaryMessenger = binaryMessenger;
    this.instanceManager = instanceManager;
    this.webViewFlutterApi = new WebViewFlutterApiImpl(binaryMessenger, instanceManager);
    this.callbackApi = new OhosWebViewCallbackApiChannel(binaryMessenger);
  }

  onReceivedTitleImpl(client: WebChromeClient, view: WebViewPlatformView, title: string, callback?: Reply<void>): void {
    this.webViewFlutterApi.create(view, emptyReply<void>());
    this.callbackApi.invoke('WebChromeClient.onReceivedTitle', this.baseArgs(client)
      .set('webViewInstanceId', this.instanceManager.getIdentifier(view)).set('title', title), callback);
  }

  onProgressChangedImpl(
    webChromeClient: WebChromeClient,
    webView: WebViewPlatformView,
    progress: number,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebChromeClient.onProgressChanged', this.baseArgs(webChromeClient)
      .set('webViewInstanceId', this.instanceManager.getIdentifier(webView))
      .set('progress', progress), callback);
  }

  onShowFileChooserImpl(
    webChromeClient: WebChromeClient,
    webView: WebViewPlatformView,
    fileChooserParams: FileSelectorParam,
    callback: Reply<Array<string> | null>
  ): void {
    const release = (): void => {
      this.instanceManager.release(this.instanceManager.getIdentifier(fileChooserParams));
    };
    const fail = (error: Error): void => {
      release();
      try {
        callback.error?.(error);
      } catch (cancelError) {
        Log.e('WebChromeClientFlutterApiImpl', 'File selection cancellation failed: ' + String(cancelError));
      }
    };
    try {
      this.webViewFlutterApi.create(webView, emptyReply<void>());
      new FileChooserParamsFlutterApiImpl(this.binaryMessenger, this.instanceManager)
        .create(fileChooserParams, {
          reply: (): void => {
            this.callbackApi.invoke('WebChromeClient.onShowFileChooser', this.baseArgs(webChromeClient)
              .set('webViewInstanceId', this.instanceManager.getIdentifier(webView))
              .set('paramsInstanceId', this.instanceManager.getIdentifier(fileChooserParams)), {
                reply: (paths: Array<string> | null): void => {
                  release();
                  callback.reply(paths);
                },
                error: fail
              });
          },
          error: fail
        });
    } catch (error) {
      fail(new Error(String(error)));
    }
  }

  onGeolocationPermissionsShowPromptImpl(
    webChromeClient: WebChromeClient,
    origin: string,
    callback: JsGeolocation,
    replyCallback?: Reply<void>
  ): void {
    const pending = new PendingNativeCallback<JsGeolocation>(this.instanceManager, callback);
    const fail = (error: Error): void => {
      pending.fail(error, (value: JsGeolocation) => value.invoke(origin, false, false), replyCallback);
    };
    try {
      new GeolocationPermissionsCallbackFlutterApiImpl(this.binaryMessenger, this.instanceManager)
        .create(callback, {
          reply: (): void => {
            pending.markRegistered();
            this.callbackApi.invoke<void>('WebChromeClient.onGeolocationPermissionsShowPrompt', this.baseArgs(webChromeClient)
              .set('paramsInstanceId', this.instanceManager.getIdentifier(callback))
              .set('origin', origin), { reply: (): void => replyCallback?.reply(), error: fail });
          },
          error: fail
        });
    } catch (error) {
      fail(new Error(String(error)));
    }
  }

  onGeolocationPermissionsHidePromptImpl(instance: WebChromeClient, callback?: Reply<void>): void {
    this.callbackApi.invoke('WebChromeClient.onGeolocationPermissionsHidePrompt',
      new Map<string, ESObject>().set('identifier', this.instanceManager.getIdentifier(instance)), callback);
  }

  onPermissionRequestImpl(
    instance: WebChromeClient,
    request: PermissionRequest,
    callback?: Reply<void>
  ): void {
    const pending = new PendingNativeCallback<PermissionRequest>(this.instanceManager, request);
    const fail = (error: Error): void => {
      pending.fail(error, (value: PermissionRequest) => value.deny(), callback);
    };
    try {
      new PermissionRequestFlutterApiImpl(this.binaryMessenger, this.instanceManager)
        .create(request, request.getAccessibleResource(), {
          reply: (): void => {
            pending.markRegistered();
            this.callbackApi.invoke<void>('WebChromeClient.onPermissionRequest', this.baseArgs(instance)
              .set('requestInstanceId', this.instanceManager.getIdentifier(request)), {
                reply: (): void => callback?.reply(), error: fail
              });
          },
          error: fail
        });
    } catch (error) {
      fail(new Error(String(error)));
    }
  }

  onShowCustomViewImpl(
    instance: WebChromeClient,
    view: DVModel,
    customViewCallback: CustomViewCallback,
    callback?: Reply<void>
  ): void {
    const pending = new PendingNativeCallback<CustomViewCallback>(this.instanceManager, customViewCallback);
    const fail = (error: Error): void => {
      pending.fail(error, (value: CustomViewCallback) => value.onCustomViewHidden(), callback);
      this.instanceManager.release(this.instanceManager.getIdentifier(view));
    };
    try {
      new ViewFlutterApiImpl(this.binaryMessenger, this.instanceManager).create(view, {
        reply: (): void => {
          new CustomViewCallbackFlutterApiImpl(this.binaryMessenger, this.instanceManager)
            .create(customViewCallback, {
              reply: (): void => {
                pending.markRegistered();
                this.callbackApi.invoke<void>('WebChromeClient.onShowCustomView', this.baseArgs(instance)
                  .set('viewIdentifier', this.instanceManager.getIdentifier(view))
                  .set('callbackIdentifier', this.instanceManager.getIdentifier(customViewCallback)), {
                    reply: (): void => callback?.reply(), error: fail
                  });
              },
              error: fail
            });
        },
        error: fail
      });
    } catch (error) {
      fail(new Error(String(error)));
    }
  }

  onHideCustomViewImpl(instance: WebChromeClient, callback?: Reply<void>): void {
    this.callbackApi.invoke('WebChromeClient.onHideCustomView', this.baseArgs(instance), callback);
  }

  onConsoleMessageImpl(
    instance: WebChromeClient,
    message: ConsoleMessage,
    callback?: Reply<void>
  ): void {
    this.callbackApi.invoke('WebChromeClient.onConsoleMessage', this.baseArgs(instance)
      .set('message', new Map<string, ESObject>()
        .set('lineNumber', message.getLineNumber())
        .set('message', message.getMessage())
        .set('level', this.toConsoleMessageLevel(message.getMessageLevel()))
        .set('sourceId', message.getSourceId())), callback);
  }

  onJsAlertImpl(
    instance: WebChromeClient,
    url: string,
    message: string,
    callback?: Reply<void>
  ): void {
    this.callbackApi.invoke('WebChromeClient.onJsAlert', this.baseArgs(instance)
      .set('url', url)
      .set('message', message), callback);
  }

  onJsConfirmImpl(
    instance: WebChromeClient,
    url: string,
    message: string,
    callback: Reply<boolean | null>
  ): void {
    this.callbackApi.invoke('WebChromeClient.onJsConfirm', this.baseArgs(instance)
      .set('url', url)
      .set('message', message), callback);
  }

  onJsPromptImpl(
    instance: WebChromeClient,
    url: string,
    message: string,
    defaultValue: string,
    callback: Reply<string | null>
  ): void {
    this.callbackApi.invoke('WebChromeClient.onJsPrompt', this.baseArgs(instance)
      .set('url', url)
      .set('message', message)
      .set('defaultValue', defaultValue), callback);
  }

  private baseArgs(webChromeClient: WebChromeClient): Map<string, ESObject> {
    return new Map<string, ESObject>().set('instanceId', this.getIdentifierForClient(webChromeClient));
  }

  private getIdentifierForClient(webChromeClient: WebChromeClient): number {
    const identifier: number = this.instanceManager.getIdentifier(webChromeClient);
    if (identifier == null) {
      throw new Error('Could not find identifier for WebChromeClient.');
    }
    return identifier;
  }

  private toConsoleMessageLevel(level: MessageLevel): ConsoleMessageLevel {
    switch (level) {
      case MessageLevel.Info:
        return ConsoleMessageLevel.TIP;
      case MessageLevel.Log:
        return ConsoleMessageLevel.LOG;
      case MessageLevel.Warn:
        return ConsoleMessageLevel.WARNING;
      case MessageLevel.Error:
        return ConsoleMessageLevel.ERROR;
      case MessageLevel.Debug:
        return ConsoleMessageLevel.DEBUG;
      default:
        return ConsoleMessageLevel.UNKNOWN;
    }
  }
}
