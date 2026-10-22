import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { CustomViewCallbackHostApiImpl } from './CustomViewCallbackHostApiImpl';
import { DownloadListenerHostApiImpl } from './DownloadListenerHostApiImpl';
import { FlutterAssetManagerHostApiImpl } from './FlutterAssetManagerHostApiImpl';
import { GeolocationPermissionsCallbackHostApiImpl } from './GeolocationPermissionsCallbackHostApiImpl';
import { HttpAuthHandlerHostApiImpl } from './HttpAuthHandlerHostApiImpl';
import { InstanceManager } from './InstanceManager';
import { JavaScriptChannelHostApiImpl } from './JavaScriptChannelHostApiImpl';
import { OhosObjectHostApiImpl } from './OhosObjectHostApiImpl';
import { CookieManagerHostApiImpl } from './CookieManagerHostApiImpl';
import { PermissionRequestHostApiImpl } from './PermissionRequestHostApiImpl';
import { Result, WebViewPoint } from './OhosWebViewTypes';
import { SslAuthHandlerHostApiImpl } from './SslAuthHandlerHostApiImpl';
import { WebChromeClientHostApiImpl } from './WebChromeClientHostApiImpl';
import { WebSettingsHostApiImpl } from './WebSettingsHostApiImpl';
import { WebStorageHostApiImpl } from './WebStorageHostApiImpl';
import { WebViewClientHostApiImpl } from './WebViewClientHostApiImpl';
import { WebViewHostApiImpl } from './WebViewHostApiImpl';

const CHANNEL_NAME = 'com.abandoft.webview_all_ohos/host_api';

class MethodResultAdapter<T> implements Result<T> {
  private result: MethodResult;

  constructor(result: MethodResult) {
    this.result = result;
  }

  success(value: T): void {
    this.result.success(value);
  }

  error(error: Error): void {
    this.result.error(error.name, error.message, error.stack);
  }
}

export class OhosWebViewHostApiChannel implements MethodCallHandler {
  private channel: MethodChannel;
  private instanceManager: InstanceManager;
  private objectApi: OhosObjectHostApiImpl;
  private cookieManagerApi: CookieManagerHostApiImpl;
  private webViewApi: WebViewHostApiImpl;
  private javaScriptChannelApi: JavaScriptChannelHostApiImpl;
  private webViewClientApi: WebViewClientHostApiImpl;
  private webChromeClientApi: WebChromeClientHostApiImpl;
  private downloadListenerApi: DownloadListenerHostApiImpl;
  private webSettingsApi: WebSettingsHostApiImpl;
  private flutterAssetManagerApi: FlutterAssetManagerHostApiImpl;
  private webStorageApi: WebStorageHostApiImpl;
  private permissionRequestApi: PermissionRequestHostApiImpl;
  private geolocationPermissionsCallbackApi: GeolocationPermissionsCallbackHostApiImpl;
  private customViewCallbackApi: CustomViewCallbackHostApiImpl;
  private httpAuthHandlerApi: HttpAuthHandlerHostApiImpl;
  private sslAuthHandlerApi: SslAuthHandlerHostApiImpl;

  constructor(
    messenger: BinaryMessenger,
    instanceManager: InstanceManager,
    objectApi: OhosObjectHostApiImpl,
    cookieManagerApi: CookieManagerHostApiImpl,
    webViewApi: WebViewHostApiImpl,
    javaScriptChannelApi: JavaScriptChannelHostApiImpl,
    webViewClientApi: WebViewClientHostApiImpl,
    webChromeClientApi: WebChromeClientHostApiImpl,
    downloadListenerApi: DownloadListenerHostApiImpl,
    webSettingsApi: WebSettingsHostApiImpl,
    flutterAssetManagerApi: FlutterAssetManagerHostApiImpl,
    webStorageApi: WebStorageHostApiImpl,
    permissionRequestApi: PermissionRequestHostApiImpl,
    geolocationPermissionsCallbackApi: GeolocationPermissionsCallbackHostApiImpl,
    customViewCallbackApi: CustomViewCallbackHostApiImpl,
    httpAuthHandlerApi: HttpAuthHandlerHostApiImpl,
    sslAuthHandlerApi: SslAuthHandlerHostApiImpl
  ) {
    this.channel = new MethodChannel(messenger, CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    this.instanceManager = instanceManager;
    this.objectApi = objectApi;
    this.cookieManagerApi = cookieManagerApi;
    this.webViewApi = webViewApi;
    this.javaScriptChannelApi = javaScriptChannelApi;
    this.webViewClientApi = webViewClientApi;
    this.webChromeClientApi = webChromeClientApi;
    this.downloadListenerApi = downloadListenerApi;
    this.webSettingsApi = webSettingsApi;
    this.flutterAssetManagerApi = flutterAssetManagerApi;
    this.webStorageApi = webStorageApi;
    this.permissionRequestApi = permissionRequestApi;
    this.geolocationPermissionsCallbackApi = geolocationPermissionsCallbackApi;
    this.customViewCallbackApi = customViewCallbackApi;
    this.httpAuthHandlerApi = httpAuthHandlerApi;
    this.sslAuthHandlerApi = sslAuthHandlerApi;
  }

  dispose(): void {
    this.channel.setMethodCallHandler(null);
  }

  onMethodCall(call: ESObject, result: MethodResult): void {
    try {
      switch (call.method as string) {
        case 'InstanceManager.clear':
          this.instanceManager.clear();
          result.success(null);
          return;
        case 'OhosObject.dispose':
          this.objectApi.dispose(call.argument('identifier'));
          result.success(null);
          return;
        case 'CookieManager.attachInstance':
          this.cookieManagerApi.attachInstance(call.argument('instanceIdentifier'));
          result.success(null);
          return;
        case 'CookieManager.setCookie':
          this.cookieManagerApi.setCookie(call.argument('identifier'), call.argument('url'), call.argument('value'));
          result.success(null);
          return;
        case 'CookieManager.getCookies':
          this.cookieManagerApi.getCookies(
            call.argument('identifier'),
            call.argument('url'),
            new MethodResultAdapter<string>(result)
          );
          return;
        case 'CookieManager.removeAllCookies':
          this.cookieManagerApi.removeAllCookies(
            call.argument('identifier'),
            new MethodResultAdapter<boolean>(result)
          );
          return;
        case 'CookieManager.setAcceptThirdPartyCookies':
          this.cookieManagerApi.setAcceptThirdPartyCookies(
            call.argument('identifier'),
            call.argument('accept')
          );
          result.success(null);
          return;
        case 'WebView.create':
          this.webViewApi.create(call.argument('instanceId'));
          result.success(null);
          return;
        case 'WebView.loadData':
          this.finishPromise(result, this.webViewApi.loadData(
            call.argument('instanceId'),
            call.argument('data'),
            call.argument('mimeType'),
            call.argument('encoding')
          ));
          return;
        case 'WebView.loadDataWithBaseUrl':
          this.finishPromise(result, this.webViewApi.loadDataWithBaseUrl(
            call.argument('instanceId'),
            call.argument('baseUrl'),
            call.argument('data'),
            call.argument('mimeType'),
            call.argument('encoding'),
            call.argument('historyUrl')
          ));
          return;
        case 'WebView.loadUrl':
          this.finishPromise(result, this.webViewApi.loadUrl(
            call.argument('instanceId'),
            call.argument('url'),
            call.argument('headers')
          ));
          return;
        case 'WebView.postUrl':
          this.finishPromise(result, this.webViewApi.postUrl(
            call.argument('instanceId'),
            call.argument('url'),
            call.argument('data')
          ));
          return;
        case 'WebView.getUrl':
          this.finishPromise(result, this.webViewApi.getUrl(call.argument('instanceId')));
          return;
        case 'WebView.canGoBack':
          this.finishPromise(result, this.webViewApi.canGoBack(call.argument('instanceId')));
          return;
        case 'WebView.canGoForward':
          this.finishPromise(result, this.webViewApi.canGoForward(call.argument('instanceId')));
          return;
        case 'WebView.goBack':
          this.finishPromise(result, this.webViewApi.goBack(call.argument('instanceId')));
          return;
        case 'WebView.goForward':
          this.finishPromise(result, this.webViewApi.goForward(call.argument('instanceId')));
          return;
        case 'WebView.reload':
          this.finishPromise(result, this.webViewApi.reload(call.argument('instanceId')));
          return;
        case 'WebView.setDocumentStartScripts':
          this.finishPromise(result, this.webViewApi.setDocumentStartScripts(
            call.argument('instanceId'), call.argument('scripts')
          ));
          return;
        case 'WebView.clearAllCache':
          this.webViewApi.clearAllCache(call.argument('includeDiskFiles'));
          result.success(null);
          return;
        case 'WebView.clearCache':
          this.webViewApi.clearCache(call.argument('instanceId'), call.argument('includeDiskFiles'));
          result.success(null);
          return;
        case 'WebView.evaluateJavascript':
          this.webViewApi.evaluateJavascript(
            call.argument('instanceId'),
            call.argument('javascriptString'),
            new MethodResultAdapter<string>(result)
          );
          return;
        case 'WebView.getTitle':
          this.finishPromise(result, this.webViewApi.getTitle(call.argument('instanceId')));
          return;
        case 'WebView.scrollTo':
          this.finishPromise(result, this.webViewApi.scrollTo(call.argument('instanceId'), call.argument('x'), call.argument('y')));
          return;
        case 'WebView.scrollBy':
          this.finishPromise(result, this.webViewApi.scrollBy(call.argument('instanceId'), call.argument('x'), call.argument('y')));
          return;
        case 'WebView.getScrollX':
          this.finishPromise(result, this.webViewApi.getScrollX(call.argument('instanceId')));
          return;
        case 'WebView.getScrollY':
          this.finishPromise(result, this.webViewApi.getScrollY(call.argument('instanceId')));
          return;
        case 'WebView.getScrollPosition': {
          this.finishPromise(result, this.webViewApi.getScrollPosition(call.argument('instanceId'))
            .then((point: WebViewPoint) => point.toArray()));
          return;
        }
        case 'WebView.setWebContentsDebuggingEnabled':
          this.webViewApi.setWebContentsDebuggingEnabled(call.argument('enabled'));
          result.success(null);
          return;
        case 'WebView.setWebViewClient':
          this.webViewApi.setWebViewClient(call.argument('instanceId'), call.argument('webViewClientInstanceId'));
          result.success(null);
          return;
        case 'WebView.addJavaScriptChannel':
          this.webViewApi.addJavaScriptChannel(
            call.argument('instanceId'),
            call.argument('javaScriptChannelInstanceId')
          );
          result.success(null);
          return;
        case 'WebView.removeJavaScriptChannel':
          this.webViewApi.removeJavaScriptChannel(
            call.argument('instanceId'),
            call.argument('javaScriptChannelInstanceId')
          );
          result.success(null);
          return;
        case 'WebView.setDownloadListener':
          this.webViewApi.setDownloadListener(call.argument('instanceId'), call.argument('listenerInstanceId'));
          result.success(null);
          return;
        case 'WebView.setWebChromeClient':
          this.webViewApi.setWebChromeClient(call.argument('instanceId'), call.argument('clientInstanceId'));
          result.success(null);
          return;
        case 'JavaScriptChannel.create':
          this.javaScriptChannelApi.create(call.argument('instanceId'), call.argument('channelName'));
          result.success(null);
          return;
        case 'WebViewClient.create':
          this.webViewClientApi.create(call.argument('instanceId'));
          result.success(null);
          return;
        case 'WebViewClient.setSynchronousReturnValueForShouldOverrideUrlLoading':
          this.webViewClientApi.setSynchronousReturnValueForShouldOverrideUrlLoading(
            call.argument('instanceId'),
            call.argument('value')
          );
          result.success(null);
          return;
        case 'DownloadListener.create':
          this.downloadListenerApi.create(call.argument('instanceId'));
          result.success(null);
          return;
        case 'WebChromeClient.create':
          this.webChromeClientApi.create(call.argument('instanceId'));
          result.success(null);
          return;
        case 'FlutterAssetManager.list':
          this.finishPromise(result, this.flutterAssetManagerApi.list(call.argument('path')));
          return;
        case 'FlutterAssetManager.getAssetFilePathByName':
          result.success(this.flutterAssetManagerApi.getAssetFilePathByName(call.argument('name')));
          return;
        case 'WebStorage.create':
          this.webStorageApi.create(call.argument('instanceId'));
          result.success(null);
          return;
        case 'WebStorage.deleteAllData':
          this.webStorageApi.deleteAllData(call.argument('instanceId'));
          result.success(null);
          return;
        case 'PermissionRequest.grant':
          this.permissionRequestApi.grant(call.argument('instanceId'), call.argument('resources'));
          result.success(null);
          return;
        case 'PermissionRequest.deny':
          this.permissionRequestApi.deny(call.argument('instanceId'));
          result.success(null);
          return;
        case 'CustomViewCallback.onCustomViewHidden':
          this.customViewCallbackApi.onCustomViewHidden(call.argument('identifier'));
          result.success(null);
          return;
        case 'GeolocationPermissionsCallback.invoke':
          this.geolocationPermissionsCallbackApi.invoke(
            call.argument('instanceId'),
            call.argument('origin'),
            call.argument('allow'),
            call.argument('retain')
          );
          result.success(null);
          return;
        case 'HttpAuthHandler.useHttpAuthUsernamePassword':
          result.success(this.httpAuthHandlerApi.useHttpAuthUsernamePassword(call.argument('instanceId')));
          return;
        case 'HttpAuthHandler.cancel':
          this.httpAuthHandlerApi.cancel(call.argument('instanceId'));
          result.success(null);
          return;
        case 'HttpAuthHandler.proceed':
          this.httpAuthHandlerApi.proceed(
            call.argument('instanceId'),
            call.argument('username'),
            call.argument('password')
          );
          result.success(null);
          return;
        case 'SslAuthHandler.cancel':
          this.sslAuthHandlerApi.cancel(call.argument('instanceId'));
          result.success(null);
          return;
        case 'SslAuthHandler.proceed':
          this.sslAuthHandlerApi.proceed(call.argument('instanceId'));
          result.success(null);
          return;
        default:
          this.handleWebSettingsAndChrome(call, result);
          return;
      }
    } catch (err) {
      this.fail(result, err);
    }
  }

  private handleWebSettingsAndChrome(call: ESObject, result: MethodResult): void {
    const method: string = call.method as string;
    const instanceId: number = call.argument('instanceId');
    const value: ESObject = call.argument('value');

    switch (method) {
      case 'WebSettings.create':
        this.webSettingsApi.create(instanceId, call.argument('webViewInstanceId'));
        result.success(null);
        return;
      case 'WebSettings.setDomStorageEnabled':
        this.webSettingsApi.setDomStorageEnabled(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setJavaScriptCanOpenWindowsAutomatically':
        this.webSettingsApi.setJavaScriptCanOpenWindowsAutomatically(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setSupportMultipleWindows':
        this.webSettingsApi.setSupportMultipleWindows(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setBackgroundColor':
        this.webSettingsApi.setBackgroundColor(instanceId, value as number);
        result.success(null);
        return;
      case 'WebSettings.setJavaScriptEnabled':
        this.webSettingsApi.setJavaScriptEnabled(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setUserAgentString':
        this.finishPromise(result, this.webSettingsApi.setUserAgentString(instanceId, value as string | null));
        return;
      case 'WebSettings.setMediaPlaybackRequiresUserGesture':
        this.webSettingsApi.setMediaPlaybackRequiresUserGesture(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setSupportZoom':
        this.webSettingsApi.setSupportZoom(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setLoadWithOverviewMode':
        this.webSettingsApi.setLoadWithOverviewMode(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setUseWideViewPort':
        this.webSettingsApi.setUseWideViewPort(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setDisplayZoomControls':
        this.webSettingsApi.setDisplayZoomControls(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setBuiltInZoomControls':
        this.webSettingsApi.setBuiltInZoomControls(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setAllowFileAccess':
        this.webSettingsApi.setAllowFileAccess(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebSettings.setTextZoom':
        this.webSettingsApi.setTextZoom(instanceId, value as number);
        result.success(null);
        return;
      case 'WebSettings.setMixedContentMode':
        this.webSettingsApi.setMixedContentMode(instanceId, value as string);
        result.success(null);
        return;
      case 'WebSettings.getUserAgentString':
        this.finishPromise(result, this.webSettingsApi.getUserAgentString(instanceId));
        return;
      case 'WebSettings.setAllowFullScreenRotate':
        this.webSettingsApi.setAllowFullScreenRotate(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebChromeClient.setSynchronousReturnValueForOnShowFileChooser':
        this.webChromeClientApi.setSynchronousReturnValueForOnShowFileChooser(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebChromeClient.setSynchronousReturnValueForOnConsoleMessage':
        this.webChromeClientApi.setSynchronousReturnValueForOnConsoleMessage(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebChromeClient.setSynchronousReturnValueForOnJsAlert':
        this.webChromeClientApi.setSynchronousReturnValueForOnJsAlert(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebChromeClient.setSynchronousReturnValueForOnJsConfirm':
        this.webChromeClientApi.setSynchronousReturnValueForOnJsConfirm(instanceId, value as boolean);
        result.success(null);
        return;
      case 'WebChromeClient.setSynchronousReturnValueForOnJsPrompt':
        this.webChromeClientApi.setSynchronousReturnValueForOnJsPrompt(instanceId, value as boolean);
        result.success(null);
        return;
      default:
        result.notImplemented();
    }
  }

  private finishPromise<T>(result: MethodResult, promise: Promise<T>): void {
    promise.then((value: T) => {
      result.success(value);
    }).catch((err: Error) => {
      this.fail(result, err);
    });
  }

  private fail(result: MethodResult, err: ESObject): void {
    if (err instanceof Error) {
      result.error(err.name, err.message, err.stack);
      return;
    }
    result.error('WebViewAllOhosError', String(err), null);
  }
}
