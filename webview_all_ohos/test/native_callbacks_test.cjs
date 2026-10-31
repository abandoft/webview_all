// node test/native_callbacks_test.cjs <ets-loader/node_modules/typescript>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const sourceRoot = path.join(__dirname, '../ohos/src/main/ets/com.abandoft.webview_all_ohos');
const calls = [];
const logs = [];
let sendError;
class MethodChannel {
  invokeMethod(method, args, result) {
    if (sendError) throw sendError;
    calls.push({ method, args, result });
  }
}
const modules = new Map();
function loadSource(name) {
  if (modules.has(name)) return modules.get(name).exports;
  const module = { exports: {} };
  modules.set(name, module);
  let source = fs.readFileSync(path.join(sourceRoot, name + '.ets'), 'utf8');
  // This test exercises callback logic; the ArkUI popup builder is compiled by
  // the native application build and has no role in callback completion.
  source = source.replace(/@CustomDialog\nstruct PopupWebView[\s\S]*?(?=class OhosWebChromeClient)/, '');
  const output = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText;
  vm.runInNewContext(output, {
    module,
    exports: module.exports,
    Map, WeakMap, Error,
    FileSelectorMode: { FileOpenMode: 0, FileOpenMultipleMode: 1, FileSaveMode: 2 },
    require: (specifier) => {
      if (specifier.endsWith('/MethodChannel')) return { default: MethodChannel };
      if (specifier.endsWith('/Log')) return { default: { e: (...args) => logs.push(args) } };
      if (specifier === '@ohos.web.webview') return { default: {} };
      if (specifier === '@ohos.file.fs') return { default: {} };
      assert.ok(specifier.startsWith('./'), 'Unexpected import: ' + specifier);
      return loadSource(specifier.substring(2));
    },
  }, { filename: name + '.ets' });
  return module.exports;
}
function take(method) {
  const index = calls.findIndex((call) => call.method === method);
  assert.notEqual(index, -1, 'Missing native-to-Dart call: ' + method);
  return calls.splice(index, 1)[0];
}
function reject(call) { call.result.error('DartError', 'Handler failed', null); }

const { InstanceManager } = loadSource('InstanceManager');
const { OhosWebViewCallbackApiChannel } = loadSource('OhosWebViewCallbackApiChannel');
const { WebChromeClientFlutterApiImpl } = loadSource('WebChromeClientFlutterApiImpl');
const { WebViewClientFlutterApiImpl } = loadSource('WebViewClientFlutterApiImpl');
const { WebChromeClientCreator } = loadSource('WebChromeClientHostApiImpl');
const { HttpAuthHandlerHostApiImpl } = loadSource('HttpAuthHandlerHostApiImpl');
const { SslAuthHandlerHostApiImpl } = loadSource('SslAuthHandlerHostApiImpl');
const { PermissionRequestHostApiImpl } = loadSource('PermissionRequestHostApiImpl');
const { GeolocationPermissionsCallbackHostApiImpl } = loadSource('GeolocationPermissionsCallbackHostApiImpl');

const channel = new OhosWebViewCallbackApiChannel(null);
let successes = 0, failures = 0;
channel.invoke('once', null, { reply: () => successes++, error: () => failures++ });
const once = take('once');
once.result.success(1);
reject(once);
once.result.notImplemented();
assert.equal(successes, 1);
assert.equal(failures, 0);
channel.invoke('unimplemented', null, { reply: () => assert.fail(), error: () => failures++ });
const missing = take('unimplemented');
assert.doesNotThrow(() => missing.result.notImplemented());
reject(missing);
assert.equal(failures, 1);
channel.invoke('throwingFallback', null, { reply: () => {}, error: () => { throw new Error('fallback'); } });
assert.doesNotThrow(() => reject(take('throwingFallback')));
sendError = new Error('Messenger detached');
channel.invoke('sendFailure', null, { reply: () => assert.fail(), error: () => failures++ });
sendError = undefined;
assert.equal(failures, 2);
channel.invoke('replyThrows', null, { reply: () => { throw new Error('invalid response'); }, error: () => failures++ });
assert.doesNotThrow(() => take('replyThrows').result.success(null));
assert.equal(failures, 3);

const released = [];
const manager = new InstanceManager({ onFinalize: (identifier) => released.push(identifier) });
const webView = {};
const viewClient = {};
manager.addDartCreatedInstance(webView, 1);
manager.addDartCreatedInstance(viewClient, 2);
const viewApi = new WebViewClientFlutterApiImpl(null, manager);
let canceled = 0, proceeded = 0;
const auth = { cancel: () => canceled++, proceed: () => proceeded++, useHttpAuthUsernamePassword: () => false };
viewApi.onReceivedHttpAuthRequestImpl(viewClient, webView, auth, 'example.test', 'realm');
reject(take('HttpAuthHandler.create'));
assert.equal(canceled, 1);
assert.equal(manager.containsInstance(auth), false);
assert.equal(calls.some((call) => call.method === 'WebViewClient.onReceivedHttpAuthRequest'), false);
viewApi.onReceivedHttpAuthRequestImpl(viewClient, webView, auth, 'example.test', 'realm');
take('HttpAuthHandler.create').result.success(null);
const authEvent = take('WebViewClient.onReceivedHttpAuthRequest');
const authId = authEvent.args.get('httpAuthHandlerInstanceId');
const authHost = new HttpAuthHandlerHostApiImpl(null, manager);
authHost.proceed(authId, 'username', 'password');
reject(authEvent);
authHost.cancel(authId);
assert.equal(proceeded, 1);
assert.equal(canceled, 1, 'A failed Dart reply after proceed must not cancel again');

const ssl = { cancel: () => canceled++, proceed: () => proceeded++ };
viewApi.onReceivedSslAuthErrorImpl(viewClient, webView, ssl, 'https://example.test', 1, 'error');
take('SslAuthHandler.create').result.success(null);
const sslEvent = take('WebViewClient.onReceivedSslAuthError');
sslEvent.result.notImplemented();
new SslAuthHandlerHostApiImpl(null, manager).proceed(sslEvent.args.get('sslAuthHandlerInstanceId'));
assert.equal(canceled, 2);
assert.equal(proceeded, 1, 'A late SSL decision must not act after cancellation');

const chromeApi = new WebChromeClientFlutterApiImpl(null, manager);
const chrome = new WebChromeClientCreator().createWebChromeClient(chromeApi);
manager.addDartCreatedInstance(chrome, 3);
let denied = 0, granted = 0;
const permission = { getAccessibleResource: () => ['camera'], deny: () => denied++, grant: () => granted++ };
chrome.onPermissionRequest(permission);
reject(take('PermissionRequest.create'));
assert.equal(denied, 1);
assert.equal(manager.containsInstance(permission), false);
chrome.onPermissionRequest(permission);
take('PermissionRequest.create').result.success(null);
const permissionEvent = take('WebChromeClient.onPermissionRequest');
new PermissionRequestHostApiImpl(null, manager).grant(permissionEvent.args.get('requestInstanceId'), ['camera']);
reject(permissionEvent);
assert.equal(granted, 1);
assert.equal(denied, 1);
chrome.onPermissionRequest(permission);
take('PermissionRequest.create').result.success(null);
reject(take('WebChromeClient.onPermissionRequest'));
assert.equal(denied, 2);

const locationDecisions = [];
const geolocation = { invoke: (...args) => locationDecisions.push(args) };
chrome.onGeolocationPermissionsShowPrompt('https://example.test', geolocation);
take('GeolocationPermissionsCallback.create').result.success(null);
reject(take('WebChromeClient.onGeolocationPermissionsShowPrompt'));
assert.deepEqual(locationDecisions, [['https://example.test', false, false]]);
chrome.onGeolocationPermissionsShowPrompt('https://example.test', geolocation);
take('GeolocationPermissionsCallback.create').result.success(null);
const geoEvent = take('WebChromeClient.onGeolocationPermissionsShowPrompt');
new GeolocationPermissionsCallbackHostApiImpl(null, manager).invoke(geoEvent.args.get('paramsInstanceId'), 'https://example.test', true, false);
reject(geoEvent);
assert.equal(locationDecisions.length, 2);
assert.equal(locationDecisions[1][1], true);

const params = { isCapture: () => false, getAcceptType: () => [], getMode: () => 0, getTitle: () => '' };
const selected = [];
const selector = { handleFileList: (paths) => selected.push(Array.from(paths)) };
const callCount = calls.length;
assert.equal(chrome.onShowFileChooser(webView, selector, params), false);
assert.equal(calls.length, callCount, 'No Dart chooser means the native picker keeps ownership');
assert.equal(selected.length, 0);
chrome.setReturnValueForOnShowFileChooser(true);
assert.equal(chrome.onShowFileChooser(webView, selector, params), true);
take('FileChooserParams.create').result.success(null);
const chooser = take('WebChromeClient.onShowFileChooser');
chooser.result.success(null);
reject(chooser);
assert.deepEqual(selected, [[]]);
assert.equal(manager.containsInstance(params), false);
chrome.onShowFileChooser(webView, selector, params);
take('FileChooserParams.create').result.success(null);
reject(take('WebChromeClient.onShowFileChooser'));
assert.deepEqual(selected, [[], []]);
chrome.onShowFileChooser(webView, selector, params);
reject(take('FileChooserParams.create'));
assert.deepEqual(selected, [[], [], []]);

let dialogConfirm = 0, dialogCancel = 0;
const dialog = { handleConfirm: () => dialogConfirm++, handleCancel: () => dialogCancel++, handlePromptConfirm: () => dialogConfirm++ };
chrome.setReturnValueForOnJsAlert(true);
chrome.onJsAlert(webView, '', '', dialog);
reject(take('WebChromeClient.onJsAlert'));
assert.equal(dialogCancel, 1);
chrome.onJsAlert(webView, '', '', dialog);
take('WebChromeClient.onJsAlert').result.success(null);
assert.equal(dialogConfirm, 1);
chrome.setReturnValueForOnJsConfirm(true);
chrome.onJsConfirm(webView, '', '', dialog);
const confirm = take('WebChromeClient.onJsConfirm');
confirm.result.success(false);
confirm.result.success(true);
assert.equal(dialogCancel, 2);
assert.equal(dialogConfirm, 1);
chrome.setReturnValueForOnJsPrompt(true);
chrome.onJsPrompt(webView, '', '', '', dialog);
take('WebChromeClient.onJsPrompt').result.success('');
assert.equal(dialogConfirm, 2, 'An empty prompt result is a valid confirmation');
chrome.onJsPrompt(webView, '', '', '', dialog);
reject(take('WebChromeClient.onJsPrompt'));
assert.equal(dialogCancel, 3);
let hidden = 0;
chrome.onShowCustomView({}, { onCustomViewHidden: () => hidden++ });
reject(take('View.create'));
assert.equal(hidden, 1);
assert.ok(logs.length >= 5, 'Dart callback failures must be recorded');
console.log('Native callback failure, cancellation, and single-completion tests passed.');
