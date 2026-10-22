import web_webview from '@ohos.web.webview';
import { DVModel } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView';
import { InstanceManager } from './InstanceManager';
import {
  CustomViewCallback,
  Reply,
  emptyReply
} from './OhosWebViewCallbackApiChannel';
import { WebChromeClientFlutterApiImpl } from './WebChromeClientFlutterApiImpl';
import { WebViewPlatformView } from './WebViewPlatformView';

export interface WebChromeClient {
  onProgressChanged(view: WebViewPlatformView, progress: number): void;
  onShowCustomView(view: DVModel, callback: CustomViewCallback): void;
  onHideCustomView(): void;
  onGeolocationPermissionsShowPrompt(origin: string, callback: JsGeolocation): void;
  onGeolocationPermissionsHidePrompt(): void;
  onShowFileChooser(
    webView: WebViewPlatformView,
    filePathCallback: FileSelectorResult,
    fileChooserParams: FileSelectorParam
  ): boolean;
  onPermissionRequest(request: PermissionRequest): void;
  onConsoleMessage(message: ConsoleMessage): void;
  onCreateWindow(
    webView: WebViewPlatformView,
    isDialog: boolean,
    isUserGesture: boolean,
    handler: ControllerHandler
  ): void;
  onJsAlert(webView: WebViewPlatformView, url: string, message: string, result: JsResult): boolean;
  onJsConfirm(webView: WebViewPlatformView, url: string, message: string, result: JsResult): boolean;
  onJsPrompt(
    webView: WebViewPlatformView,
    url: string,
    message: string,
    defaultValue: string,
    result: JsResult
  ): boolean;
}

export class WebChromeClientCreator {
  createWebChromeClient(flutterApi: WebChromeClientFlutterApiImpl): WebChromeClient {
    return new OhosWebChromeClient(flutterApi);
  }
}

export class WebChromeClientHostApiImpl {
  private readonly instanceManager: InstanceManager;
  private readonly creator: WebChromeClientCreator;
  private readonly flutterApi: WebChromeClientFlutterApiImpl;

  constructor(
    instanceManager: InstanceManager,
    creator: WebChromeClientCreator,
    flutterApi: WebChromeClientFlutterApiImpl
  ) {
    this.instanceManager = instanceManager;
    this.creator = creator;
    this.flutterApi = flutterApi;
  }

  create(instanceId: number): void {
    this.instanceManager.addDartCreatedInstance(this.creator.createWebChromeClient(this.flutterApi), instanceId);
  }

  setSynchronousReturnValueForOnShowFileChooser(instanceId: number, value: boolean): void {
    this.client(instanceId).setReturnValueForOnShowFileChooser(value);
  }

  setSynchronousReturnValueForOnConsoleMessage(instanceId: number, value: boolean): void {
    this.client(instanceId).setReturnValueForOnConsoleMessage(value);
  }

  setSynchronousReturnValueForOnJsAlert(instanceId: number, value: boolean): void {
    this.client(instanceId).setReturnValueForOnJsAlert(value);
  }

  setSynchronousReturnValueForOnJsConfirm(instanceId: number, value: boolean): void {
    this.client(instanceId).setReturnValueForOnJsConfirm(value);
  }

  setSynchronousReturnValueForOnJsPrompt(instanceId: number, value: boolean): void {
    this.client(instanceId).setReturnValueForOnJsPrompt(value);
  }

  private client(instanceId: number): OhosWebChromeClient {
    return this.instanceManager.getInstance<OhosWebChromeClient>(instanceId);
  }
}

@CustomDialog
struct PopupWebView {
  controller?: CustomDialogController;
  webViewController: web_webview.WebviewController = new web_webview.WebviewController();

  build() {
    Web({ src: '', controller: this.webViewController })
      .javaScriptAccess(true)
      .multiWindowAccess(false)
      .onWindowExit(() => {
        if (this.controller) {
          this.controller.close();
        }
      })
  }
}

class OhosWebChromeClient implements WebChromeClient {
  private readonly flutterApi: WebChromeClientFlutterApiImpl;
  private readonly emptyReply: Reply<void> = emptyReply<void>();
  private returnValueForOnShowFileChooser: boolean = false;
  private returnValueForOnConsoleMessage: boolean = false;
  private returnValueForOnJsAlert: boolean = false;
  private returnValueForOnJsConfirm: boolean = false;
  private returnValueForOnJsPrompt: boolean = false;

  constructor(flutterApi: WebChromeClientFlutterApiImpl) {
    this.flutterApi = flutterApi;
  }

  onProgressChanged(view: WebViewPlatformView, progress: number): void {
    this.flutterApi.onProgressChangedImpl(this, view, progress, this.emptyReply);
  }

  onShowCustomView(view: DVModel, callback: CustomViewCallback): void {
    this.flutterApi.onShowCustomViewImpl(this, view, callback, this.emptyReply);
  }

  onHideCustomView(): void {
    this.flutterApi.onHideCustomViewImpl(this, this.emptyReply);
  }

  onGeolocationPermissionsShowPrompt(origin: string, callback: JsGeolocation): void {
    this.flutterApi.onGeolocationPermissionsShowPromptImpl(this, origin, callback, this.emptyReply);
  }

  onGeolocationPermissionsHidePrompt(): void {
    this.flutterApi.onGeolocationPermissionsHidePromptImpl(this, this.emptyReply);
  }

  onShowFileChooser(
    webView: WebViewPlatformView,
    filePathCallback: FileSelectorResult,
    fileChooserParams: FileSelectorParam
  ): boolean {
    if (!this.returnValueForOnShowFileChooser) {
      return false;
    }
    let completed = false;
    const complete = (paths: Array<string> | null): void => {
      if (completed) return;
      completed = true;
      filePathCallback.handleFileList(paths ?? []);
    };
    this.flutterApi.onShowFileChooserImpl(this, webView, fileChooserParams, {
      reply: (paths: Array<string> | null): void => complete(paths),
      error: (_error: Error): void => complete(null)
    });
    return true;
  }

  onPermissionRequest(request: PermissionRequest): void {
    this.flutterApi.onPermissionRequestImpl(this, request, this.emptyReply);
  }

  onConsoleMessage(message: ConsoleMessage): void {
    this.flutterApi.onConsoleMessageImpl(this, message, this.emptyReply);
  }

  onCreateWindow(
    webView: WebViewPlatformView,
    _isDialog: boolean,
    _isUserGesture: boolean,
    handler: ControllerHandler
  ): void {
    const existingDialog = webView.getDialogController();
    if (existingDialog != null) {
      existingDialog.close();
    }
    const webViewController = new web_webview.WebviewController();
    const dialogController = new CustomDialogController({
      builder: PopupWebView({ webViewController: webViewController })
    });
    webView.setDialogController(dialogController);
    dialogController.open();
    handler.setWebController(webViewController);
  }

  onJsAlert(_webView: WebViewPlatformView, url: string, message: string, result: JsResult): boolean {
    if (!this.returnValueForOnJsAlert) {
      return false;
    }
    let completed = false;
    const complete = (confirm: boolean): void => {
      if (completed) return;
      completed = true;
      if (confirm) result.handleConfirm();
      else result.handleCancel();
    };
    this.flutterApi.onJsAlertImpl(this, url, message, {
      reply: (): void => {
        complete(true);
      },
      error: (_error: Error): void => complete(false)
    });
    return true;
  }

  onJsConfirm(_webView: WebViewPlatformView, url: string, message: string, result: JsResult): boolean {
    if (!this.returnValueForOnJsConfirm) {
      return false;
    }
    let completed = false;
    const complete = (confirm: boolean): void => {
      if (completed) return;
      completed = true;
      if (confirm) result.handleConfirm();
      else result.handleCancel();
    };
    this.flutterApi.onJsConfirmImpl(this, url, message, {
      reply: (confirmed: boolean | null): void => {
        complete(confirmed === true);
      },
      error: (_error: Error): void => complete(false)
    });
    return true;
  }

  onJsPrompt(
    _webView: WebViewPlatformView,
    url: string,
    message: string,
    defaultValue: string,
    result: JsResult
  ): boolean {
    if (!this.returnValueForOnJsPrompt) {
      return false;
    }
    let completed = false;
    const complete = (value: string | null): void => {
      if (completed) return;
      completed = true;
      if (typeof value === 'string') result.handlePromptConfirm(value);
      else result.handleCancel();
    };
    this.flutterApi.onJsPromptImpl(this, url, message, defaultValue, {
      reply: (value: string | null): void => {
        complete(value);
      },
      error: (_error: Error): void => complete(null)
    });
    return true;
  }

  setReturnValueForOnShowFileChooser(value: boolean): void {
    this.returnValueForOnShowFileChooser = value;
  }

  setReturnValueForOnConsoleMessage(value: boolean): void {
    this.returnValueForOnConsoleMessage = value;
  }

  setReturnValueForOnJsAlert(value: boolean): void {
    this.returnValueForOnJsAlert = value;
  }

  setReturnValueForOnJsConfirm(value: boolean): void {
    this.returnValueForOnJsConfirm = value;
  }

  setReturnValueForOnJsPrompt(value: boolean): void {
    this.returnValueForOnJsPrompt = value;
  }
}
