// Run with Node and the SDK compiler:
// node test/native_webview_test.cjs <ets-loader/node_modules/typescript>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const sourceRoot = path.join(__dirname, '../ohos/src/main/ets/com.abandoft.webview_all_ohos');
const actions = [];
let controller;
let cacheError;
class NativeController {
  constructor() { return controller; }
  static initializeWebEngine() { actions.push('initialize'); }
  static removeAllCache(disk) {
    if (cacheError) throw cacheError;
    actions.push(['clearCache', disk]);
  }
}
const nativeWeb = { WebviewController: NativeController, WebCookieManager: class {} };
const overrides = {
  '@ohos.multimedia.image': { default: {} },
  '@ohos.print': { default: {} },
  '@ohos.util': { default: { generateRandomUUID() { return 'navigation-test-' + Math.random(); } } },
  '@ohos.file.fs': { default: {} },
  '@ohos.web.webview': { default: nativeWeb },
  '@ohos.web.netErrorList': { WebNetErrorList: {} },
  '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView': { default: class {} },
  '@ohos/flutter_ohos/src/main/ets/util/Log': { default: { e() {}, d() {}, w() {} } },
  '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel': {
    default: class { setMethodCallHandler() {} },
  },
  '@ohos.app.ability.common': { default: {} },
  '@ohos.window': { default: {} },
  '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: 22 } },
  './OhosWebView': { WebBuilder() {} },
  './WebViewFlutterApiImpl': {
    WebViewFlutterApiImpl: class {
      onScrollChanged() { actions.push('scroll-event'); }
      onBrowserEvent(_, event) { actions.push(['browser-event', Object.fromEntries(event)]); }
    },
  },
};
const modules = new Map();
function loadSource(name) {
  if (modules.has(name)) return modules.get(name).exports;
  const module = { exports: {} };
  modules.set(name, module);
  const source = fs.readFileSync(path.join(sourceRoot, name + '.ets'), 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText;
  vm.runInNewContext(output, {
    module, exports: module.exports, Promise, Error, ArrayBuffer, Uint8Array, setTimeout, clearTimeout,
    MixedMode: { None: 0, All: 1, Compatible: 2 },
    RenderExitReason: { ProcessAbnormalTermination: 0, ProcessWasKilled: 1, ProcessCrashed: 2, ProcessOom: 3 },
    require(specifier) {
      if (overrides[specifier]) return overrides[specifier];
      assert.ok(specifier.startsWith('./'), 'Unexpected import: ' + specifier);
      return loadSource(specifier.substring(2));
    },
  }, { filename: name + '.ets' });
  return module.exports;
}
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

async function main() {
  const { WebViewHostApiImpl } = loadSource('WebViewHostApiImpl');
  let wait = deferred();
  let posted;
  let offsetError;
  let fallbackReads = 0;
  controller = {
    scrollTo: (x, y) => actions.push(['scrollTo', x, y]),
    scrollBy: (x, y) => actions.push(['scrollBy', x, y]),
    loadData: (...args) => actions.push(['loadData', ...args]),
    loadUrl: (...args) => actions.push(['loadUrl', ...args]),
    postUrl: (_, bytes) => { posted = bytes; },
    getUrl: () => 'https://example.test/',
    getTitle: () => 'A title',
    accessBackward: () => true,
    accessForward: () => false,
    backward: () => actions.push('backward'),
    forward: () => actions.push('forward'),
    stop: () => actions.push('stop'),
    backOrForward: (offset) => actions.push(['historyJump', offset]),
    getBackForwardEntries: () => ({
      size: 3, currentIndex: 1,
      getItemAtIndex: (index) => ({historyUrl: `https://example.test/${index}`,
        historyRawUrl: `https://example.test/original/${index}`, title: `Page ${index}`}),
    }),
    searchAllAsync: (text) => actions.push(['find', text]),
    searchNext: (forward) => actions.push(['findNext', forward]),
    clearMatches: () => actions.push('clearMatches'),
    refresh: () => assert.fail('Channel or UA configuration must not refresh'),
    runJavaScript: async (source) => { actions.push(['evaluate', source]); return '42'; },
    getPageOffset: () => {
      if (offsetError) throw offsetError;
      return { x: 12.75, y: 31.5 };
    },
    getScrollOffset: () => { fallbackReads++; return { x: 4, y: 9 }; },
    registerJavaScriptProxy: (_, name) => actions.push(['register', name]),
    deleteJavaScriptRegister: (name) => actions.push(['unregister', name]),
    setCustomUserAgent: (ua) => actions.push(['ua', ua]),
    pauseAllMedia: () => actions.push('pause-media'),
    setAudioMuted: (value) => actions.push(['audio-muted', value]),
    stopAllMedia: () => { throw new Error('Already detached'); },
  };
  const viewStub = {
    waitControllerAttached: () => wait.promise,
    ensureNotDisposed() {},
    isIncognito: () => false,
    getController: () => controller,
    setUrl() {},
    setScrollPosition: () => assert.fail('Do not report a requested scroll as an actual position'),
    getScrollX: () => assert.fail('Do not read predicted scroll coordinates'),
    getScrollY: () => assert.fail('Do not read predicted scroll coordinates'),
  };
  const instances = { getInstance: () => viewStub };
  let privateMode = false;
  viewStub.isIncognito = () => privateMode;
  const host = new WebViewHostApiImpl(instances, null, null, null);
  const scroll = host.scrollTo(1, 9999, 9999);
  const delta = host.scrollBy(1, 5, 7);
  const title = host.getTitle(1);
  const back = host.canGoBack(1);
  const forward = host.canGoForward(1);
  const load = host.loadData(1, '<body>page</body>', 'text/html', 'utf-8');
  const bytes = Uint8Array.from([99, 1, 2, 3, 88]).subarray(1, 4);
  const post = host.postUrl(1, 'https://example.test/', bytes);
  const result = deferred();
  host.evaluateJavascript(1, '21 * 2', { success: result.resolve, error: result.reject });
  await flush();
  assert.deepEqual(actions, [], 'Operations must wait until the component is ready');
  wait.resolve();
  await Promise.all([scroll, delta, load, post]);
  assert.equal(await title, 'A title');
  assert.equal(await back, true);
  assert.equal(await forward, false);
  assert.equal(await result.promise, '42');
  assert.deepEqual([...new Uint8Array(posted)], [1, 2, 3]);
  let pixelReleased = 0, packerReleased = 0, oversized = false;
  controller.getSurfaceId = () => 'web-view-surface';
  overrides['@ohos.multimedia.image'].default = {
    async createPixelMapFromSurface(id) {
      assert.equal(id, 'web-view-surface');
      return {async getImageInfo() {return {size: {width: oversized ? 20000 : 100, height: 1000}};},
        async release() {pixelReleased++;}};
    },
    createImagePacker() {return {async packing(_, options) {
      assert.equal(options.format, 'image/png'); return Uint8Array.from([137, 80, 78, 71]).buffer;
    }, async release() {packerReleased++;}};},
  };
  assert.deepEqual([...await host.takeScreenshot(1)], [137, 80, 78, 71]);
  assert.equal(pixelReleased, 1); assert.equal(packerReleased, 1);
  oversized = true;
  await assert.rejects(host.takeScreenshot(1), /16 megapixel/);
  assert.equal(pixelReleased, 2); assert.equal(packerReleased, 1);
  assert.equal(await host.mediaOperation(1, 'pauseMedia', false), true);
  assert.equal(actions.at(-1), 'pause-media');
  assert.equal(await host.mediaOperation(1, 'setAudioMuted', true), true);
  assert.deepEqual(actions.at(-1), ['audio-muted', true]);
  assert.equal(await host.mediaOperation(1, 'unknown', false), false);
  const snapshot = await host.getNavigationHistory(1);
  assert.equal(snapshot.get('currentIndex'), 1);
  assert.equal(snapshot.get('items')[2].get('url'), 'https://example.test/2');
  assert.equal(snapshot.get('items')[0].get('originalUrl'), 'https://example.test/original/0');
  assert.equal(await host.goToHistoryIndex(1, -1), false);
  assert.equal(await host.goToHistoryIndex(1, 3), false);
  assert.equal(await host.goToHistoryIndex(1, 2), true);
  assert.deepEqual(actions.at(-1), ['historyJump', 1]);
  await host.stopLoading(1);
  assert.equal(actions.at(-1), 'stop');
  const position = await host.getScrollPosition(1);
  assert.deepEqual([position.getX(), position.getY()], [12, 31]);
  offsetError = Object.assign(new Error('Unsupported capability'), { code: 801 });
  assert.equal(await host.getScrollY(1), 9);
  assert.equal(fallbackReads, 1);
  offsetError = Object.assign(new Error('Controller detached'), { code: 17100001 });
  await assert.rejects(host.getScrollX(1), /Controller detached/);
  assert.equal(fallbackReads, 1, 'Initialization failures must not be hidden by fallback');
  actions.length = 0;
  privateMode = true;
  host.clearCache(1, true);
  assert.deepEqual(actions, [], 'Private cache clearing must not delete normal cache');
  privateMode = false;
  instances.getInstance = () => assert.fail('Global cache clearing must not create or require a view');
  host.clearAllCache(true);
  assert.deepEqual(actions, ['initialize', ['clearCache', true]]);
  cacheError = new Error('Cache unavailable');
  assert.throws(() => host.clearAllCache(true), /Cache unavailable/);
  cacheError = undefined;

  const { WebViewPlatformView } = loadSource('WebViewPlatformView');
  const view = new WebViewPlatformView(null, null);
  view.setIncognito(true);
  assert.equal(view.isIncognito(), true);
  const titles = [];
  view.setWebChromeClient({ onReceivedTitle: (_, title) => titles.push(title) });
  view.onTitleReceive({ title: 'Changed' });
  view.onTitleReceive({ title: '' });
  assert.deepEqual(titles, ['Changed', '']);
  const state = view.getDocumentStartScriptState();
  const channel = { getJavaScriptChannelName: () => 'Bridge', createJavaScriptProxy: () => ({}) };
  actions.length = 0;
  view.addJavaScriptChannel(channel);
  assert.deepEqual(actions, [], 'Channel registration before mounting must complete without attachment');
  state.subscribe(() => {});
  state.markApplied(0, state.getGeneration());
  view.userAgentString = 'Configured UA';
  view.onControllerAttached();
  assert.deepEqual(actions, [['ua', 'Configured UA'], ['register', 'Bridge']]);
  const settings = view.getWebSettings();
  settings.onSettingsChanged(() => {});
  let ready = false;
  const pending = view.waitControllerAttached().then(() => { ready = true; });
  await flush();
  assert.equal(ready, false, 'Navigation must wait for settings modifiers, too');
  settings.markApplied(settings.getSnapshot().revision);
  await pending;
  settings.setAllowFileAccess(false);
  ready = false;
  const updated = view.waitControllerAttached().then(() => { ready = true; });
  await flush();
  assert.equal(ready, false);
  settings.markApplied(settings.getSnapshot().revision);
  await updated;
  actions.length = 0;
  const finding = view.findText('needle', true);
  assert.deepEqual(actions, [['find', 'needle']]);
  view.onSearchResultReceive({isDoneCounting: false, numberOfMatches: 1, activeMatchOrdinal: 0});
  view.onSearchResultReceive({isDoneCounting: true, numberOfMatches: 2, activeMatchOrdinal: 0});
  const found = await finding;
  assert.equal(found.get('matchFound'), true);
  assert.equal(found.get('matchCount'), 2);
  assert.equal(found.get('activeMatchIndex'), 0);
  const nextMatch = view.findText('needle', false);
  assert.deepEqual(actions.at(-1), ['findNext', false]);
  view.onSearchResultReceive({isDoneCounting: true, numberOfMatches: 2, activeMatchOrdinal: 1});
  assert.equal((await nextMatch).get('activeMatchIndex'), 1);
  const backwards = view.findText('different', false);
  view.onSearchResultReceive({isDoneCounting: true, numberOfMatches: 2, activeMatchOrdinal: 0});
  assert.deepEqual(actions.at(-1), ['findNext', false]);
  view.onSearchResultReceive({isDoneCounting: true, numberOfMatches: 2, activeMatchOrdinal: 1});
  assert.equal((await backwards).get('activeMatchIndex'), 1);
  const cancelledSearch = view.findText('cancelled', true);
  view.cancelFind();
  assert.equal(await cancelledSearch, null);
  view.onSearchResultReceive({isDoneCounting: true, numberOfMatches: 3, activeMatchOrdinal: 0});
  let rejectedPopup = false;
  view.denyPopups = true;
  view.onWindowNew({handler: {setWebController(value) {
    assert.equal(value, null); rejectedPopup = true;
  }}});
  assert.equal(rejectedPopup, true);
  const history = [];
  view.setWebViewClient({ doUpdateVisitedHistory: (_, url) => history.push(url) });
  view.onRefreshAccessedHistory({ url: 'https://frame.test/', isMainFrame: false });
  assert.deepEqual(history, []);
  view.onRefreshAccessedHistory({ url: 'https://example.test/updated', isMainFrame: true });
  assert.equal(view.getUrl(), 'https://example.test/updated');
  view.onRefreshAccessedHistory({ url: 'https://example.test/legacy' });
  assert.equal(history.length, 2);
  view.removeJavaScriptChannel('Bridge');
  let disposed = 0;
  view.setOnDisposeCallback(() => disposed++);
  view.dispose();
  view.dispose();
  assert.equal(disposed, 1, 'Media teardown failure must not skip UI disposal');
  assert.throws(() => view.addJavaScriptChannel(channel), /disposed/);
  await assert.rejects(view.waitControllerAttached(), /disposed/);
  actions.length = 0;
  view.onControllerAttached();
  view.onScroll({ xOffset: 3, yOffset: 5 });
  view.onRefreshAccessedHistory({ url: 'https://late.test/', isMainFrame: true });
  view.onInactive();
  view.onActive();
  view.onTitleReceive({ title: 'Late' });
  assert.deepEqual(titles, ['Changed', '']);
  assert.deepEqual(actions, [], 'Late callbacks must not revive or address a disposed view');
  assert.equal(history.length, 2);
  assert.equal(view.onJsAlert({}), false);
  assert.equal(view.onJsConfirm({}), false);
  assert.equal(view.onJsPrompt({}), false);

  const fullscreenView = new WebViewPlatformView(null, null);
  fullscreenView.fullscreenDelegateEnabled = true;
  let fullscreenExits = 0;
  actions.length = 0;
  fullscreenView.onFullScreenEnter({handler: {exitFullScreen() {fullscreenExits++;}}});
  assert.deepEqual(actions, [['browser-event', {type: 'fullscreenChanged', active: true}]],
    'Delegated fullscreen must not change system bars or orientation');
  assert.equal(fullscreenView.exitFullscreen(), true);
  assert.equal(fullscreenView.exitFullscreen(), false);
  assert.equal(fullscreenExits, 1);
  fullscreenView.onFullScreenExit();
  assert.deepEqual(actions.at(-1), ['browser-event', {type: 'fullscreenChanged', active: false}]);
  fullscreenView.onRenderExited({renderExitReason: 2});
  assert.deepEqual(actions.at(-1), ['browser-event', {type: 'processFailed', nativeCode: 2, didCrash: true}]);
  fullscreenView.dispose();
  const eventCount = actions.length;
  fullscreenView.onRenderExited({renderExitReason: 0});
  assert.equal(actions.length, eventCount, 'Disposed views must not deliver renderer events');

  const teardownView = new WebViewPlatformView(null, null);
  teardownView.addJavaScriptChannel(channel);
  teardownView.setWebViewClient({});
  teardownView.setWebChromeClient({});
  teardownView.setDownloadListener({});
  teardownView.setDialogController({ close() { throw new Error('Popup already detached'); } });
  let uiDisposals = 0;
  teardownView.setOnDisposeCallback(() => {
    uiDisposals++;
    throw new Error('Component already detached');
  });
  teardownView.dispose();
  teardownView.dispose();
  assert.equal(uiDisposals, 1, 'Popup or UI errors must not interrupt or repeat teardown');
  assert.equal(teardownView.dialogController, null);
  assert.equal(teardownView.javaScriptChannels.size, 0);
  assert.equal(teardownView.webViewClient, null);
  assert.equal(teardownView.webChromeClient, null);
  assert.equal(teardownView.downloadListener, null);

  const failedView = new WebViewPlatformView(null, null);
  failedView.addJavaScriptChannel(channel);
  const failedState = failedView.getDocumentStartScriptState();
  failedState.subscribe(() => {});
  const earlyWaiter = failedView.waitControllerAttached();
  controller.registerJavaScriptProxy = () => { throw new Error('Proxy registration failed'); };
  failedView.onControllerAttached();
  await assert.rejects(earlyWaiter, /Proxy registration failed/);
  await assert.rejects(failedView.waitControllerAttached(), /Proxy registration failed/);
  failedView.dispose();

  // Verify the actual method-channel dispatcher does not acknowledge async
  // operations before completion, including errors and point serialization.
  const { OhosWebViewHostApiChannel } = loadSource('OhosWebViewHostApiChannel');
  const operation = deferred();
  const channelHost = new OhosWebViewHostApiChannel(null, null, null, null,
    { scrollTo: () => operation.promise, getScrollPosition: async () => position },
    null, null, null, null, null, null, null, null, null, null, null, null);
  const replies = [];
  const reply = { success: (value) => replies.push(['success', value]),
    error: (code, message) => replies.push(['error', code, message]) };
  channelHost.onMethodCall({ method: 'WebView.scrollTo', argument: () => 1 }, reply);
  await flush();
  assert.deepEqual(replies, []);
  operation.reject(new Error('Scroll failed'));
  await flush();
  assert.equal(replies.length, 1);
  assert.equal(replies[0][0], 'error');
  replies.length = 0;
  channelHost.onMethodCall({ method: 'WebView.getScrollPosition', argument: () => 1 }, reply);
  await flush();
  assert.deepEqual(Array.from(replies[0][1]), [12, 31]);
  console.log('Native readiness, scroll, POST bytes, cache, history, search, popup policy, channels and disposal passed.');
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
