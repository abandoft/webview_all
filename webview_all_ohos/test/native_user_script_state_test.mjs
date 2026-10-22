// Run with Node >=22.13: node --test test/native_user_script_state_test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const source = readFileSync(new URL('../ohos/src/main/ets/com.abandoft.webview_all_ohos/DocumentStartScriptState.ets', import.meta.url), 'utf8');
const javascript = stripTypeScriptTypes(source);
const { DocumentStartScriptState } = await import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
const tick = () => Promise.resolve();
const mount = state => state.subscribe(() => {});
const apply = state => state.markApplied(state.getSnapshot().revision, state.getGeneration());

test('registration before mount completes, while navigation waits for attach and latest application', async () => {
  const state = new DocumentStartScriptState();
  const sources = ['first'];
  await state.setScripts(sources);
  sources.push('external mutation');
  assert.deepEqual(state.getSnapshot().sources, ['first']);
  let ready = false;
  const navigation = state.waitUntilReady().then(() => { ready = true; });
  mount(state);
  apply(state);
  await state.setScripts(['first', 'second']);
  state.markControllerAttached();
  await tick();
  assert.equal(ready, false);
  apply(state);
  await navigation;
  assert.equal(ready, true);
});

test('attached updates and removals wait for their applied revision', async () => {
  const state = new DocumentStartScriptState();
  mount(state);
  apply(state);
  state.markControllerAttached();
  let completed = false;
  const update = state.setScripts(['a', 'b']).then(() => { completed = true; });
  state.markApplied(0, state.getGeneration());
  await tick();
  assert.equal(completed, false);
  apply(state);
  await update;
  const clear = state.setScripts([]);
  assert.deepEqual(state.getSnapshot().sources, []);
  apply(state);
  await clear;
});

test('a detached component cannot acknowledge a later mount', async () => {
  const state = new DocumentStartScriptState();
  mount(state);
  const oldGeneration = state.getGeneration();
  state.detach();
  mount(state);
  state.markControllerAttached();
  let ready = false;
  const navigation = state.waitUntilReady().then(() => { ready = true; });
  state.markApplied(0, oldGeneration);
  await tick();
  assert.equal(ready, false);
  apply(state);
  await navigation;
});

test('detach keeps registration for the next document and rejects pending navigation', async () => {
  const state = new DocumentStartScriptState();
  mount(state);
  apply(state);
  state.markControllerAttached();
  const update = state.setScripts(['retained']);
  const navigation = state.waitUntilReady();
  const rejected = assert.rejects(navigation, /detached/);
  state.detach();
  await Promise.all([update, rejected]);
  assert.deepEqual(state.getSnapshot().sources, ['retained']);
  state.markControllerAttached();
  assert.equal(state.isControllerAttached(), false);
});

test('dispose before attachment rejects waiters and cannot be undone by late callbacks', async () => {
  const state = new DocumentStartScriptState();
  const rejected = assert.rejects(state.waitUntilReady(), /disposed/);
  state.dispose();
  state.markControllerAttached();
  state.markApplied(999, state.getGeneration());
  state.dispose();
  await rejected;
  assert.equal(state.isControllerAttached(), false);
  assert.throws(() => state.waitUntilReady(), /disposed/);
  assert.throws(() => state.setScripts(['late']), /disposed/);
  assert.throws(() => mount(state), /disposed/);
});

test('dispose rejects all pending mounted updates and navigation', async () => {
  const state = new DocumentStartScriptState();
  mount(state);
  apply(state);
  state.markControllerAttached();
  const first = assert.rejects(state.setScripts(['a']), /disposed/);
  const second = assert.rejects(state.setScripts(['b']), /disposed/);
  const navigation = assert.rejects(state.waitUntilReady(), /disposed/);
  state.dispose();
  await Promise.all([first, second, navigation]);
});
