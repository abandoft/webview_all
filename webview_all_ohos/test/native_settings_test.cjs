// Run with Node and the SDK's TypeScript compiler; no device is required:
// node test/native_settings_test.cjs <ets-loader/node_modules/typescript>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');

const sourceRoot = path.join(__dirname,
  '../ohos/src/main/ets/com.abandoft.webview_all_ohos');
const mixedMode = { None: 0, All: 1, Compatible: 2 };
const cookieCalls = [];
const storageCalls = [];
let hasCookies = false;
let clearCookieError;
const nativeCookies = {
  configCookieSync: (url, value, incognito) => cookieCalls.push(['set', url, value, incognito]),
  fetchCookieSync: () => 'name=value',
  existCookie: () => hasCookies,
  clearAllCookiesSync: () => {
    if (clearCookieError) throw clearCookieError;
    hasCookies = false;
  },
};
const nativeWeb = {
  WebCookieManager: nativeCookies,
  WebviewController: {
    initializeWebEngine: () => storageCalls.push('initialize'),
    getDefaultUserAgent: () => 'Default UA',
  },
  WebStorage: {
    deleteAllData: () => storageCalls.push('delete'),
  },
};
const modules = new Map();

function loadSource(name) {
  if (modules.has(name)) return modules.get(name).exports;
  const module = { exports: {} };
  modules.set(name, module);
  const source = fs.readFileSync(path.join(sourceRoot, name + '.ets'), 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: {
      target: ts.ScriptTarget.ES2020,
      module: ts.ModuleKind.CommonJS,
    },
  }).outputText;
  vm.runInNewContext(output, {
    module,
    exports: module.exports,
    MixedMode: mixedMode,
    require: (specifier) => {
      if (specifier === '@ohos.web.webview') return { default: nativeWeb };
      assert.ok(specifier.startsWith('./'), 'Unexpected import: ' + specifier);
      return loadSource(specifier.substring(2));
    },
  }, { filename: name + '.ets' });
  return module.exports;
}

async function main() {
  const { WebViewSettings } = loadSource('WebViewSettings');
  const { WebSettingsHostApiImpl, WebSettingsCreator } = loadSource('WebSettingsHostApiImpl');
  const { CookieManagerHostApiImpl } = loadSource('CookieManagerHostApiImpl');
  const { WebStorageHostApiImpl } = loadSource('WebStorageHostApiImpl');
  let waitCount = 0;
  let releaseAttachment;
  const attachment = new Promise((resolve) => { releaseAttachment = resolve; });
  let nativeUserAgent = '';
  const webView = {
    ensureNotDisposed() {},
    isWebviewBinding: false,
    userAgentString: '',
    waitControllerAttached: () => { waitCount++; return attachment; },
    setCustomUserAgent: (value) => {
      nativeUserAgent = value;
      webView.userAgentString = value;
    },
    getController: () => ({
      getCustomUserAgent: () => nativeUserAgent,
      loadUrl: () => assert.fail('Setting UA must not navigate'),
      refresh: () => assert.fail('Setting UA must not refresh'),
    }),
    getUrl: () => assert.fail('Setting UA must not read a cached navigation URL'),
  };
  const settings = new WebViewSettings(webView);
  const initial = settings.getSnapshot();
  assert.equal(initial.textZoom, 100);
  await settings.waitUntilApplied();
  const snapshots = [];
  settings.onSettingsChanged((snapshot) => snapshots.push(snapshot));
  const changes = [
    ['setDomStorageEnabled', true, 'domStorageEnabled', true],
    ['setJavaScriptCanOpenWindowsAutomatically', true, 'javaScriptCanOpenWindowsAutomatically', true],
    ['setSupportMultipleWindows', true, 'supportMultipleWindows', true],
    ['setBackgroundColor', 0x12345678, 'backgroundColor', '#12345678'],
    ['setJavaScriptEnabled', true, 'javaScriptEnabled', true],
    ['setMediaPlaybackRequiresUserGesture', true, 'mediaPlaybackRequiresUserGesture', true],
    ['setSupportZoom', false, 'supportZoom', false],
    ['setLoadWithOverviewMode', true, 'loadWithOverviewMode', true],
    ['setUseWideViewPort', true, 'useWideViewPort', true],
    ['setAllowFileAccess', false, 'allowFileAccess', false],
    ['setMixedContentMode', 'alwaysAllow', 'mixedContentMode', mixedMode.All],
    ['setTextZoom', 175, 'textZoom', 175],
  ];
  for (const [setter, value, field, expected] of changes) {
    const previousCount = snapshots.length;
    settings[setter](value);
    assert.equal(snapshots.length, previousCount + 1, setter + ' must notify');
    assert.equal(snapshots.at(-1)[field], expected, setter + ' snapshot');
    assert.notEqual(snapshots.at(-1), initial);
    assert.equal(snapshots.at(-1).revision, snapshots.length);
  }
  assert.equal(initial.supportZoom, true, 'Published snapshots must remain independent');
  assert.equal(initial.textZoom, 100);
  const latest = snapshots.at(-1);
  latest.supportZoom = true;
  assert.equal(settings.getSnapshot().supportZoom, false);
  settings.onSettingsChanged(undefined);
  settings.setSupportZoom(true);
  assert.equal(snapshots.length, changes.length, 'Removed listeners must not receive changes');
  assert.throws(() => settings.setMixedContentMode('invalid'));

  settings.onSettingsChanged(() => {});
  const firstRevision = settings.getSnapshot().revision;
  let firstApplied = false;
  const firstWait = settings.waitUntilApplied().then(() => { firstApplied = true; });
  settings.setAllowFileAccess(true);
  const latestRevision = settings.getSnapshot().revision;
  let latestApplied = false;
  const latestWait = settings.waitUntilApplied().then(() => { latestApplied = true; });
  settings.markApplied(firstRevision);
  await firstWait;
  assert.equal(firstApplied, true);
  assert.equal(latestApplied, false, 'An old build must not acknowledge newer settings');
  settings.markApplied(latestRevision);
  await latestWait;
  settings.setAllowFileAccess(false);
  const detachedWait = assert.rejects(settings.waitUntilApplied(), /detached/);
  settings.onSettingsChanged(undefined);
  await detachedWait;
  await settings.waitUntilApplied();
  settings.onSettingsChanged(() => {});
  let remountedApplied = false;
  const remountedWait = settings.waitUntilApplied().then(() => { remountedApplied = true; });
  await Promise.resolve();
  assert.equal(remountedApplied, false, 'A remounted view needs its own build acknowledgement');
  settings.markApplied(settings.getSnapshot().revision);
  await remountedWait;
  settings.onSettingsChanged(undefined);

  await settings.setUserAgentString('Configured before mounting');
  assert.equal(waitCount, 0, 'Pre-mount UA configuration must complete without attachment');
  assert.equal(webView.userAgentString, 'Configured before mounting');
  assert.equal(await settings.getUserAgentString(), 'Configured before mounting');
  webView.isWebviewBinding = true;
  const host = new WebSettingsHostApiImpl({ getInstance: () => settings }, new WebSettingsCreator());
  let completed = false;
  const pending = host.setUserAgentString(1, 'Mounted UA').then(() => { completed = true; });
  await Promise.resolve();
  assert.equal(completed, false, 'Host API must await the native setter');
  releaseAttachment();
  await pending;
  assert.equal(nativeUserAgent, 'Mounted UA');
  await settings.setUserAgentString(null);
  assert.equal(nativeUserAgent, '', 'Null must reset the custom UA');
  assert.equal(await settings.getUserAgentString(), 'Default UA');
  webView.waitControllerAttached = () => Promise.reject(new Error('View disposed'));
  await assert.rejects(host.setUserAgentString(1, 'Late UA'), /View disposed/);

  const cookies = new CookieManagerHostApiImpl(null, null);
  cookies.setCookie(1, 'https://example.test', 'name=value');
  assert.deepEqual(cookieCalls, [['set', 'https://example.test', 'name=value', false]]);
  assert.throws(() => cookies.setCookie(1, '', 'name=value'));
  cookies.setCookie(1, 'https://private.test', 'private=value', true);
  assert.deepEqual(cookieCalls.at(-1), ['set', 'https://private.test', 'private=value', true]);
  let cleared;
  const result = { success: (value) => { cleared = value; } };
  cookies.removeAllCookies(1, result);
  assert.equal(cleared, false, 'An empty cookie store must return false');
  hasCookies = true;
  cookies.removeAllCookies(1, result);
  assert.equal(cleared, true, 'Removing existing cookies must return true');
  cleared = undefined;
  clearCookieError = new Error('Cookie store unavailable');
  assert.throws(() => cookies.removeAllCookies(1, result), /Cookie store unavailable/);
  assert.equal(cleared, undefined, 'A failed clear must not report success');
  storageCalls.length = 0;
  new WebStorageHostApiImpl().deleteAllData(1);
  assert.deepEqual(storageCalls, ['initialize', 'delete'], 'Storage clear must initialize ArkWeb before deleting');
  console.log('Native settings snapshots, UA lifecycle, and cookie results passed.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
