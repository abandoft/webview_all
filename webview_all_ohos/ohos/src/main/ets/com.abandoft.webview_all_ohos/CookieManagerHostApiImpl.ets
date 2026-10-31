import web_webview from '@ohos.web.webview';
import { Result } from './OhosWebViewTypes';

export class CookieManagerHostApiImpl {
  constructor(_binaryMessenger: ESObject, _instanceManager: ESObject) {}

  attachInstance(_instanceIdentifier: number): void {}

  setCookie(_identifier: number, url: string, value: string, incognito: boolean = false): void {
    this.assertUrl(url);
    web_webview.WebCookieManager.configCookieSync(url, value, incognito);
  }

  getCookies(_identifier: number, url: string, result: Result<string>, incognito: boolean = false): void {
    this.assertUrl(url);
    result.success(web_webview.WebCookieManager.fetchCookieSync(url, incognito));
  }

  setAcceptThirdPartyCookies(_identifier: number, accept: boolean): void {
    web_webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(accept);
  }

  removeAllCookies(_identifier: number, result: Result<boolean>, incognito: boolean = false): void {
    const hadCookies = web_webview.WebCookieManager.existCookie(incognito);
    web_webview.WebCookieManager.clearAllCookiesSync(incognito);
    result.success(hadCookies);
  }

  private assertUrl(url: string): void {
    if (url == null || url.length == 0) {
      throw new Error('Cookie URL must not be empty.');
    }
  }
}
