import web_webview from '@ohos.web.webview';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

export class WebSchemeRegistry {
  private static registered: Set<string> = new Set<string>();
  static register(names: Array<string>): Array<string> {
    if (names.length === 0) return [];
    const blocked = ['http', 'https', 'file', 'about', 'data', 'javascript', 'blob', 'ws', 'wss',
      'ftp', 'content', 'resource', 'intent', 'webview-all-resource'];
    if (names.some((name: string) => !/^[a-z][a-z0-9+.-]{0,31}$/.test(name) || blocked.includes(name))) {
      Log.w('webview_all', 'Invalid or engine-owned custom URL scheme; custom handling is unavailable.'); return [];
    }
    const all = new Set<string>(WebSchemeRegistry.registered);
    names.forEach((name: string) => all.add(name));
    if (all.size > 10) {
      Log.w('webview_all', 'ArkWeb supports at most 10 registered custom schemes; existing registrations were retained.'); return [];
    }
    if (all.size !== WebSchemeRegistry.registered.size) {
      try {
        const schemes: Array<web_webview.WebCustomScheme> = Array.from(all).map((name: string): web_webview.WebCustomScheme => {
          return {schemeName: name, isSupportCORS: true, isSupportFetch: true,
            isStandard: true, isLocal: false, isSecure: false, isCspBypassing: false};
        });
        web_webview.WebviewController.customizeSchemes(schemes, true);
        WebSchemeRegistry.registered = all;
      } catch (error) {
        Log.w('webview_all', 'ArkWeb custom schemes must be registered before WebEngine initialization: ' + error); return [];
      }
    }
    return names.slice();
  }
}
