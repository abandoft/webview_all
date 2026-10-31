import common from '@ohos.app.ability.common';
import fileIo from '@ohos.file.fs';
import web_webview from '@ohos.web.webview';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodChannel, { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

class PendingDownload {
  id: string;
  item: web_webview.WebDownloadItem;
  directory: string;
  temporaryPath: string;
  target: string = '';
  useDefault: boolean = false;
  timer: number = -1;
  publishing: boolean = false;
  decisionReceived: boolean = false;

  constructor(id: string, item: web_webview.WebDownloadItem, directory: string) {
    this.id = id;
    this.item = item;
    this.directory = directory;
    this.temporaryPath = directory + '/payload';
  }
}

// A per-view bridge. The engine only receives private staging paths; publishing
// uses the file API's non-overwriting mode, including concurrent name conflicts.
export class WebDownloadCoordinator {
  private readonly channel: MethodChannel;
  private readonly controller: web_webview.WebviewController;
  private readonly context: common.Context;
  private readonly legacy: (item: web_webview.WebDownloadItem) => void;
  private readonly pending: Map<string, PendingDownload> = new Map();
  private enabled: boolean = false;
  private installed: boolean = false;
  private disposed: boolean = false;
  private nativeDelegate?: web_webview.WebDownloadDelegate;

  constructor(messenger: BinaryMessenger, identifier: number,
    controller: web_webview.WebviewController, context: common.Context,
    legacy: (item: web_webview.WebDownloadItem) => void) {
    this.channel = new MethodChannel(messenger, 'com.abandoft.webview_all_ohos/download/' + identifier);
    this.controller = controller;
    this.context = context;
    this.legacy = legacy;
  }

  setEnabled(enabled: boolean, attached: boolean): void {
    if (this.disposed) throw new Error('The WebView has been disposed.');
    const undecided = Array.from(this.pending.values()).filter((task: PendingDownload): boolean => !task.decisionReceived);
    undecided.forEach((task: PendingDownload): void => {
      task.decisionReceived = true;
      this.pending.delete(task.id);
      try { task.item.cancel(); } catch (_) {}
      this.finish(task, 'cancelled');
    });
    const previous = this.enabled;
    this.enabled = enabled;
    try {
      if (attached) this.onAttached();
    } catch (error) {
      this.enabled = previous;
      throw new Error(String(error));
    }
  }

  ownsNotifications(): boolean { return this.installed; }

  onAttached(): void {
    if (this.installed || !this.enabled || this.disposed) return;
    const delegate = new web_webview.WebDownloadDelegate();
    delegate.onBeforeDownload((item: web_webview.WebDownloadItem): void => this.begin(item));
    delegate.onDownloadUpdated((item: web_webview.WebDownloadItem): void => this.progress(item));
    delegate.onDownloadFinish((item: web_webview.WebDownloadItem): void => {
      this.publish(item).catch((error: Error): void => {
        const task = this.pending.get(item.getGuid());
        if (task) this.finish(task, 'failed', undefined, 'save_failed', String(error));
      });
    });
    delegate.onDownloadFailed((item: web_webview.WebDownloadItem): void => {
      const task = this.pending.get(item.getGuid());
      if (task) this.finish(task, 'failed', undefined, String(item.getLastErrorCode()), 'The native download failed.');
    });
    this.installed = true;
    this.nativeDelegate = delegate;
    try { this.controller.setDownloadDelegate(delegate); }
    catch (error) {
      this.installed = false;
      this.nativeDelegate = undefined;
      throw new Error(String(error));
    }
  }

  private begin(item: web_webview.WebDownloadItem): void {
    if (this.disposed) { item.cancel(); return; }
    if (!this.enabled) {
      // ArkWeb has no unsetDownloadDelegate API. After removing the new handler,
      // emulate the old notification-only path exactly once and stop this item.
      try { item.cancel(); } catch (_) {}
      this.legacy(item);
      return;
    }
    const id = item.getGuid();
    if (this.pending.has(id)) return;
    let task: PendingDownload;
    try {
      const directory = fileIo.mkdtempSync(this.context.cacheDir + '/webview-all-download-XXXXXX');
      task = new PendingDownload(id, item, directory);
      this.pending.set(id, task);
    } catch (error) {
      try { item.cancel(); } catch (_) {}
      this.emit('result', new Map<string, ESObject>().set('id', id).set('status', 'failed')
        .set('errorCode', 'temporary_file_failed').set('description', String(error)));
      return;
    }
    const total = item.getTotalBytes();
    const request: Map<string, ESObject> = new Map<string, ESObject>().set('id', id).set('url', item.getUrl())
      .set('suggestedFilename', item.getSuggestedFileName()).set('mimeType', item.getMimeType());
    if (total >= 0) request.set('totalBytes', total);
    task.timer = setTimeout((): void => {
      task.timer = -1;
      this.failDecision(task, 'Download decision timed out.');
    }, 35000);
    const reply: MethodResult = {
      success: (value: ESObject): void => {
        if (!this.pending.has(id) || this.disposed || task.decisionReceived) return;
        task.decisionReceived = true;
        if (task.timer >= 0) { clearTimeout(task.timer); task.timer = -1; }
        try { this.resolve(task, value as Map<string, ESObject>); }
        catch (error) { this.reject(task, String(error)); }
      },
      error: (_code: string, message: string, _details: ESObject): void => this.failDecision(task, message),
      notImplemented: (): void => this.failDecision(task, 'Download handler is unavailable.')
    };
    try { this.channel.invokeMethod('request', request, reply); }
    catch (error) { this.failDecision(task, String(error)); }
  }

  private resolve(task: PendingDownload, decision: Map<string, ESObject>): void {
    const error: ESObject = decision.get('error');
    if (error) { this.reject(task, String(error)); return; }
    const action = decision.get('action') as string;
    if (action === 'cancel' || action === 'handledExternally') {
      this.pending.delete(task.id);
      try { task.item.cancel(); }
      catch (error) {
        this.finish(task, 'failed', undefined, 'cancel_failed', String(error));
        return;
      }
      this.finish(task, action === 'cancel' ? 'cancelled' : 'handedOff');
      return;
    }
    if (action !== 'platformDefault' && action !== 'saveToFile') throw new Error('Unsupported download decision.');
    task.useDefault = action === 'platformDefault';
    if (!task.useDefault) {
      const path = decision.get('path') as string;
      if (typeof path !== 'string' || !path.startsWith('/') || path.indexOf('\u0000') >= 0) throw new Error('A download destination must be an absolute file path.');
      task.target = path;
    }
    task.item.start(task.temporaryPath);
  }

  private progress(item: web_webview.WebDownloadItem): void {
    const task = this.pending.get(item.getGuid());
    if (!task || this.disposed) return;
    const event: Map<string, ESObject> = new Map<string, ESObject>().set('id', task.id).set('bytesReceived', item.getReceivedBytes());
    const total = item.getTotalBytes();
    if (total >= 0) event.set('totalBytes', total);
    this.emit('progress', event);
  }

  private safeName(name: string): string {
    const parts = name.replace(/\\/g, '/').split('/');
    let result = parts[parts.length - 1].replace(/[\u0000-\u001f\u007f]/g, '_');
    if (result.length === 0 || result === '.' || result === '..') result = 'download';
    result = result.substring(0, 80);
    const last = result.charCodeAt(result.length - 1);
    if (last >= 0xd800 && last <= 0xdbff) result = result.substring(0, result.length - 1);
    return result;
  }

  private async publish(item: web_webview.WebDownloadItem): Promise<void> {
    const task = this.pending.get(item.getGuid());
    if (!task || task.publishing || this.disposed) return;
    task.publishing = true;
    if (task.useDefault) {
      const directory = this.context.filesDir + '/Downloads';
      try { fileIo.mkdirSync(directory); }
      catch (error) { if ((error as ESObject).code !== 13900015) throw new Error(String(error)); }
      const name = this.safeName(item.getSuggestedFileName());
      const dot = name.lastIndexOf('.');
      const split = dot > 0 ? dot : name.length;
      for (let index = 0; index < 10000; index++) {
        if (this.disposed || !this.pending.has(task.id)) return;
        const suffix = index === 0 ? '' : ' (' + index + ')';
        const target = directory + '/' + name.substring(0, split) + suffix + name.substring(split);
        try {
          await fileIo.moveFile(task.temporaryPath, target, 1);
          task.target = target;
          break;
        } catch (error) {
          if ((error as ESObject).code !== 13900015 || index === 9999) throw new Error(String(error));
        }
      }
    } else {
      await fileIo.moveFile(task.temporaryPath, task.target, 1);
    }
    if (!this.disposed && this.pending.has(task.id)) this.finish(task, 'completed', task.target);
  }

  private reject(task: PendingDownload, message: string): void {
    if (!this.pending.has(task.id)) return;
    this.pending.delete(task.id);
    try { task.item.cancel(); } catch (_) {}
    this.finish(task, 'failed', undefined, 'download_decision_failed', message);
  }

  private failDecision(task: PendingDownload, message: string): void {
    if (!this.pending.has(task.id) || task.decisionReceived) return;
    task.decisionReceived = true;
    this.reject(task, message);
  }

  private finish(task: PendingDownload, status: string, path?: string, code?: string, description?: string): void {
    this.pending.delete(task.id);
    if (task.timer >= 0) { clearTimeout(task.timer); task.timer = -1; }
    const event: Map<string, ESObject> = new Map<string, ESObject>().set('id', task.id).set('status', status);
    if (path) event.set('path', path);
    if (code) event.set('errorCode', code);
    if (description) event.set('description', description);
    this.emit('result', event);
    this.clean(task);
  }

  private clean(task: PendingDownload): void {
    try { fileIo.unlinkSync(task.temporaryPath); } catch (_) {}
    try { fileIo.rmdirSync(task.directory); } catch (_) {}
  }

  private emit(method: string, event: Map<string, ESObject>): void {
    try {
      this.channel.invokeMethod(method, event, { success: (): void => {}, error: (): void => {}, notImplemented: (): void => {} });
    } catch (_) {}
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    const tasks = Array.from(this.pending.values());
    this.pending.clear();
    tasks.forEach((task: PendingDownload): void => {
      try { task.item.cancel(); } catch (_) {}
      this.finish(task, 'cancelled');
    });
    if (this.installed) {
      // Do not leave engine callbacks retaining this disposed view/coordinator.
      const guard = new web_webview.WebDownloadDelegate();
      guard.onBeforeDownload((item: web_webview.WebDownloadItem): void => {
        try { item.cancel(); } catch (_) {}
      });
      try {
        this.controller.setDownloadDelegate(guard);
        this.nativeDelegate = guard;
      } catch (_) {
        this.nativeDelegate = undefined;
      }
    }
    this.emit('disposed', new Map<string, ESObject>());
  }
}
