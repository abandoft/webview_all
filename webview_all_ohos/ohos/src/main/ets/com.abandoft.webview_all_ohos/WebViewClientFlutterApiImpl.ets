import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { HttpAuthHandlerFlutterApiImpl } from './HttpAuthHandlerFlutterApiImpl';
import { InstanceManager } from './InstanceManager';
import { PendingNativeCallback } from './NativeCallback';
import { HttpAuthHandler, OhosWebViewCallbackApiChannel, Reply, SslAuthHandler, emptyReply } from './OhosWebViewCallbackApiChannel';
import { SslAuthHandlerFlutterApiImpl } from './SslAuthHandlerFlutterApiImpl';
import { WebViewClient } from './WebViewClientHostApiImpl';
import { WebViewFlutterApiImpl } from './WebViewFlutterApiImpl';
import { WebViewPlatformView } from './WebViewPlatformView';

export class WebViewClientFlutterApiImpl {
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

  onPageStartedImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    url: string,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebViewClient.onPageStarted', this.baseArgs(webViewClient, webView)
      .set('url', url), callback);
  }

  onPageFinishedImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    url: string,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebViewClient.onPageFinished', this.baseArgs(webViewClient, webView)
      .set('url', url), callback);
  }

  onReceivedRequestErrorImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    request: WebResourceRequest,
    error: WebResourceError,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebViewClient.onReceivedRequestError', this.baseArgs(webViewClient, webView)
      .set('request', WebViewClientFlutterApiImpl.createWebResourceRequestData(request))
      .set('error', WebViewClientFlutterApiImpl.createWebResourceErrorData(error)), callback);
  }

  onReceivedHttpErrorImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    request: WebResourceRequest,
    response: WebResourceResponse,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebViewClient.onReceivedHttpError', this.baseArgs(webViewClient, webView)
      .set('request', WebViewClientFlutterApiImpl.createWebResourceRequestData(request))
      .set('response', WebViewClientFlutterApiImpl.createWebResourceResponseData(response)), callback);
  }

  requestLoadingImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    request: WebResourceRequest,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebViewClient.requestLoading', this.baseArgs(webViewClient, webView)
      .set('request', WebViewClientFlutterApiImpl.createWebResourceRequestData(request)), callback);
  }

  doUpdateVisitedHistoryImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    url: string,
    isReload: boolean,
    callback?: Reply<void>
  ): void {
    this.webViewFlutterApi.create(webView, emptyReply<void>());
    this.callbackApi.invoke('WebViewClient.doUpdateVisitedHistory', this.baseArgs(webViewClient, webView)
      .set('url', url)
      .set('isReload', isReload), callback);
  }

  onReceivedHttpAuthRequestImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    httpAuthHandler: HttpAuthHandler,
    host: string,
    realm: string,
    callback?: Reply<void>
  ): void {
    const pending = new PendingNativeCallback<HttpAuthHandler>(this.instanceManager, httpAuthHandler);
    const fail = (error: Error): void => {
      pending.fail(error, (handler: HttpAuthHandler) => handler.cancel(), callback);
    };
    try {
      new HttpAuthHandlerFlutterApiImpl(this.binaryMessenger, this.instanceManager)
        .create(httpAuthHandler, {
          reply: (): void => {
            pending.markRegistered();
            this.callbackApi.invoke<void>('WebViewClient.onReceivedHttpAuthRequest', this.baseArgs(webViewClient, webView)
              .set('httpAuthHandlerInstanceId', this.instanceManager.getIdentifier(httpAuthHandler))
              .set('host', host)
              .set('realm', realm), { reply: (): void => callback?.reply(), error: fail });
          },
          error: fail
        });
    } catch (error) {
      fail(new Error(String(error)));
    }
  }

  onReceivedSslAuthErrorImpl(
    webViewClient: WebViewClient,
    webView: WebViewPlatformView,
    sslAuthHandler: SslAuthHandler,
    url: string,
    errorCode: number,
    description: string,
    callback?: Reply<void>
  ): void {
    const pending = new PendingNativeCallback<SslAuthHandler>(this.instanceManager, sslAuthHandler);
    const fail = (error: Error): void => {
      pending.fail(error, (handler: SslAuthHandler) => handler.cancel(), callback);
    };
    try {
      new SslAuthHandlerFlutterApiImpl(this.binaryMessenger, this.instanceManager)
        .create(sslAuthHandler, {
          reply: (): void => {
            pending.markRegistered();
            this.callbackApi.invoke<void>('WebViewClient.onReceivedSslAuthError', this.baseArgs(webViewClient, webView)
              .set('sslAuthHandlerInstanceId', this.instanceManager.getIdentifier(sslAuthHandler))
              .set('url', url)
              .set('errorCode', errorCode)
              .set('description', description), { reply: (): void => callback?.reply(), error: fail });
          },
          error: fail
        });
    } catch (error) {
      fail(new Error(String(error)));
    }
  }

  private baseArgs(webViewClient: WebViewClient, webView: WebViewPlatformView): Map<string, ESObject> {
    return new Map<string, ESObject>()
      .set('instanceId', this.getIdentifierForClient(webViewClient))
      .set('webViewInstanceId', this.instanceManager.getIdentifier(webView));
  }

  private getIdentifierForClient(webViewClient: WebViewClient): number {
    const identifier: number = this.instanceManager.getIdentifier(webViewClient);
    if (identifier == null) {
      throw new Error('Could not find identifier for WebViewClient.');
    }
    return identifier;
  }

  static createWebResourceErrorData(error: WebResourceError): Map<string, ESObject> {
    return new Map<string, ESObject>()
      .set('errorCode', error.getErrorCode())
      .set('description', error.getErrorInfo());
  }

  static createWebResourceResponseData(response: WebResourceResponse): Map<string, ESObject> {
    return new Map<string, ESObject>()
      .set('statusCode', response.getResponseCode())
      .set('responseHeaders', WebViewClientFlutterApiImpl.toWebHeadersMap(response.getResponseHeader()))
      .set('reasonPhrase', response.getReasonMessage())
      .set('mimeType', response.getResponseMimeType());
  }

  static createWebResourceRequestData(request: WebResourceRequest): Map<string, ESObject> {
    return new Map<string, ESObject>()
      .set('url', request.getRequestUrl())
      .set('isForMainFrame', request.isMainFrame())
      .set('isRedirect', request.isRedirect())
      .set('hasGesture', request.isRequestGesture())
      .set('method', request.getRequestMethod())
      .set('requestHeaders', WebViewClientFlutterApiImpl.toWebHeadersMap(request.getRequestHeader()));
  }

  static toWebHeadersMap(headers: Array<Header>): Map<string, string> {
    const headersMap: Map<string, string> = new Map();
    if (headers == null || headers.length === 0) {
      return headersMap;
    }
    for (const header of headers) {
      headersMap.set(header.headerKey, header.headerValue);
    }
    return headersMap;
  }
}
