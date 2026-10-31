// node test/native_download_test.cjs <SDK typescript directory>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const calls = [];
const files = new Map();
const timers = new Map();
let nextTimer = 1, nextDirectory = 1;
let native;
let fileMoves = 0;
const fileIo = {
  mkdtempSync: () => '/cache/download-' + nextDirectory++,
  mkdirSync() {},
  unlinkSync: (name) => files.delete(name),
  rmdirSync() {},
  async moveFile(source, target, mode) {
    assert.equal(mode, 1, 'Publication must never overwrite');
    fileMoves++;
    if (files.has(target)) throw Object.assign(new Error('File exists'), { code: 13900015 });
    assert.ok(files.has(source));
    files.set(target, files.get(source));
    files.delete(source);
  },
};
class NativeDelegate {
  onBeforeDownload(callback) { this.before = callback; }
  onDownloadUpdated(callback) { this.update = callback; }
  onDownloadFinish(callback) { this.finish = callback; }
  onDownloadFailed(callback) { this.fail = callback; }
}
class Channel {
  invokeMethod(method, args, reply) { calls.push({ method, args, reply }); }
}
const source = fs.readFileSync(path.join(__dirname, '../ohos/src/main/ets/com.abandoft.webview_all_ohos/WebDownloadCoordinator.ets'), 'utf8');
const output = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
}).outputText;
const moduleValue = { exports: {} };
vm.runInNewContext(output, {
  module: moduleValue, exports: moduleValue.exports,
  Map, Array, Error, String, Promise,
  setTimeout(fn) { const id = nextTimer++; timers.set(id, fn); return id; },
  clearTimeout(id) { timers.delete(id); },
  require(name) {
    if (name === '@ohos.file.fs') return { default: fileIo };
    if (name === '@ohos.web.webview') return { default: { WebDownloadDelegate: NativeDelegate } };
    if (name.endsWith('/MethodChannel')) return { default: Channel };
    throw new Error('Unexpected import ' + name);
  },
});
const { WebDownloadCoordinator } = moduleValue.exports;
const legacy = [];
const coordinator = new WebDownloadCoordinator(null, 7,
  { setDownloadDelegate(value) { native = value; } },
  { cacheDir: '/cache', filesDir: '/files' }, (item) => legacy.push(item));
let sequence = 0;
function item(name = 'report.txt') {
  const value = {
    id: 'task-' + ++sequence,
    started: [], cancelled: 0,
    getGuid() { return this.id; },
    getUrl() { return 'https://example.test/attachment'; },
    getSuggestedFileName() { return name; },
    getMimeType() { return 'text/plain'; },
    getTotalBytes() { return -1; },
    getReceivedBytes() { return 8; },
    getLastErrorCode() { return 17; },
    start(destination) { this.started.push(destination); files.set(destination, 'response'); },
    cancel() { this.cancelled++; native.fail(this); },
  };
  return value;
}
function take(method) {
  const index = calls.findIndex((value) => value.method === method);
  assert.notEqual(index, -1, 'Expected ' + method);
  return calls.splice(index, 1)[0];
}
function decision(request, action, destination) {
  request.reply.success(new Map([['action', action], ['path', destination]]));
}
async function flush() { for (let i = 0; i < 12; i++) await Promise.resolve(); }
async function main() {
  coordinator.setEnabled(true, false);
  assert.equal(native, undefined, 'Do not require an attached controller during configuration');
  coordinator.onAttached();
  assert.ok(native);
  assert.equal(coordinator.ownsNotifications(), true);

  const first = item();
  native.before(first);
  const request = take('request');
  assert.equal(request.args.get('url'), first.getUrl());
  assert.equal(request.args.has('totalBytes'), false);
  assert.equal(first.started.length, 0, 'Wait for the app decision');
  decision(request, 'saveToFile', '/files/chosen.txt');
  request.reply.error('late', 'Ignore a late error', null);
  request.reply.success(new Map([['action', 'cancel']]));
  assert.equal(first.started.length, 1, 'Resolve each request only once');
  assert.equal(first.cancelled, 0);
  native.update(first);
  const progress = take('progress').args;
  assert.equal(progress.get('bytesReceived'), 8);
  assert.equal(progress.has('totalBytes'), false);
  native.finish(first);
  await flush();
  assert.equal(take('result').args.get('status'), 'completed');
  assert.equal(files.get('/files/chosen.txt'), 'response');

  files.set('/files/existing.txt', 'user file');
  const conflict = item(); native.before(conflict);
  decision(take('request'), 'saveToFile', '/files/existing.txt');
  native.finish(conflict); await flush();
  assert.equal(take('result').args.get('status'), 'failed');
  assert.equal(files.get('/files/existing.txt'), 'user file');

  files.set('/files/Downloads/report.txt', 'first file');
  const defaultItem = item('../report.txt'); native.before(defaultItem);
  decision(take('request'), 'platformDefault'); native.finish(defaultItem); await flush();
  const saved = take('result').args;
  assert.equal(saved.get('path'), '/files/Downloads/report (1).txt');
  assert.equal(files.get('/files/Downloads/report.txt'), 'first file');

  const canceled = item(); native.before(canceled); decision(take('request'), 'cancel');
  assert.equal(canceled.started.length, 0); assert.equal(canceled.cancelled, 1);
  assert.equal(take('result').args.get('status'), 'cancelled');

  const external = item(); native.before(external); decision(take('request'), 'handledExternally');
  assert.equal(take('result').args.get('status'), 'handedOff');
  assert.equal(external.started.length, 0);

  const failure = item(); native.before(failure);
  take('request').reply.error('dart', 'Application failed', null);
  assert.equal(take('result').args.get('status'), 'failed');
  assert.equal(failure.started.length, 0);

  const timeout = item(); native.before(timeout); const late = take('request');
  assert.equal(timers.size, 1);
  const callback = [...timers.values()][0]; timers.clear(); callback();
  assert.equal(take('result').args.get('status'), 'failed');
  decision(late, 'platformDefault');
  assert.equal(timeout.started.length, 0);

  const running = item(); native.before(running);
  decision(take('request'), 'saveToFile', '/files/running.txt');
  const undecided = item(); native.before(undecided); const undecidedRequest = take('request');
  coordinator.setEnabled(true, true);
  assert.equal(take('result').args.get('status'), 'cancelled');
  assert.equal(undecided.cancelled, 1);
  decision(undecidedRequest, 'platformDefault');
  assert.equal(undecided.started.length, 0);
  assert.equal(running.cancelled, 0, 'Delegate replacement must not cancel an approved native task');
  native.finish(running); await flush();
  assert.equal(take('result').args.get('status'), 'completed');

  coordinator.setEnabled(false, true);
  const fallback = item(); native.before(fallback);
  assert.equal(legacy.length, 1); assert.equal(fallback.cancelled, 1);
  assert.equal(calls.some((value) => value.method === 'request'), false);

  coordinator.setEnabled(true, true);
  const pending = item(); native.before(pending); const pendingRequest = take('request');
  coordinator.dispose();
  assert.equal(take('result').args.get('status'), 'cancelled');
  take('disposed');
  decision(pendingRequest, 'platformDefault');
  assert.equal(pending.started.length, 0);
  assert.equal(timers.size, 0);
  assert.ok(fileMoves >= 5);
  assert.equal([...files.keys()].some((name) => name.startsWith('/cache/')), false);
  console.log('OHOS native download decisions, original tasks, safe targets, fallback and disposal passed.');
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
