import web_webview from '@ohos.web.webview';

export class WebStorageHostApiImpl {
  create(_instanceId: number): void {}

  deleteAllData(_instanceId: number, incognito: boolean = false): void {
    web_webview.WebviewController.initializeWebEngine();
    web_webview.WebStorage.deleteAllData(incognito);
  }
}
