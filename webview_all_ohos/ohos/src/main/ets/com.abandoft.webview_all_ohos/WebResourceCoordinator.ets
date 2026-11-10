import web_webview from '@ohos.web.webview';
import { WebNetErrorList } from '@ohos.web.netErrorList';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodChannel, { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { ContentRuleState } from './ContentRuleState';

class ResourceTask {
  id: string;
  request: web_webview.WebSchemeHandlerRequest;
  handler: web_webview.WebResourceHandler;
  channel: MethodChannel;
  timer: number = -1;
  done: boolean = false;

  constructor(id: string, request: web_webview.WebSchemeHandlerRequest,
    handler: web_webview.WebResourceHandler, channel: MethodChannel) {
    this.id = id;
    this.request = request;
    this.handler = handler;
    this.channel = channel;
  }
}

// Only controller-issued virtual HTTPS resources are claimed synchronously.
// All other HTTPS traffic stays in ArkWeb's normal network stack.
export class WebResourceCoordinator {
  private contentRules: ContentRuleState = new ContentRuleState();
  private readonly messenger: BinaryMessenger;
  private readonly controller: web_webview.WebviewController;
  private readonly scheme: web_webview.WebSchemeHandler = new web_webview.WebSchemeHandler();
  private channel?: MethodChannel;
  private host: string = '';
  private enabled: boolean = false;
  private installed: boolean = false;
  private installedCustomSchemes: Set<string> = new Set<string>();
  private customSchemes: Array<string> = [];
  private customChannel?: MethodChannel;
  private customChannelName: string = '';
  private customEnabled: boolean = false;
  private disposed: boolean = false;
  private nextId: number = 0;
  private pending: Map<web_webview.WebSchemeHandlerRequest, ResourceTask> = new Map();

  constructor(messenger: BinaryMessenger, controller: web_webview.WebviewController) {
    this.messenger = messenger;
    this.controller = controller;
    this.scheme.onRequestStart((request: web_webview.WebSchemeHandlerRequest,
      handler: web_webview.WebResourceHandler): boolean => {
      if (!this.disposed && this.contentRules.blocks(request.getRequestUrl())) {
        handler.didFail(WebNetErrorList.ERR_BLOCKED_BY_CLIENT, true); return true;
      }
      const url = request.getRequestUrl();
      const custom = this.customSchemes.includes(url.substring(0, url.indexOf(':')));
      if (this.disposed || (!custom && !url.startsWith('https://' + this.host + '/'))) return false;
      const channel = custom ? this.customChannel : this.channel;
      const enabled = custom ? this.customEnabled : this.enabled;
      if (!enabled || !channel) {
        handler.didFail(WebNetErrorList.ERR_ABORTED, true);
        return true;
      }
      const task = new ResourceTask(String(++this.nextId), request, handler, channel);
      this.pending.set(request, task);
      this.begin(task);
      return true;
    });
    this.scheme.onRequestStop((request: web_webview.WebSchemeHandlerRequest): void => {
      const task = this.pending.get(request);
      if (task) this.remove(task);
    });
  }

  configureRules(rules: Array<Map<string, ESObject>>, attached: boolean): void {
    if (this.disposed) throw new Error('The resource coordinator was disposed.');
    this.contentRules.configure(rules);
    if (attached) this.onAttached();
  }
  configureSchemes(name: string, schemes: Array<string>, enabled: boolean, attached: boolean): void {
    if (this.disposed) throw new Error('The resource coordinator was disposed.');
    if (!enabled && name !== this.customChannelName) return;
    const previous = this.customChannel;
    Array.from(this.pending.values()).forEach((task: ResourceTask) => { if (task.channel === previous) this.fail(task); });
    this.customSchemes = schemes.slice(); this.customEnabled = enabled;
    this.customChannelName = name; this.customChannel = new MethodChannel(this.messenger, name);
    if (attached) this.onAttached();
  }

  configure(name: string, host: string, enabled: boolean, attached: boolean): void {
    if (this.disposed) throw new Error('The resource coordinator was disposed.');
    const previous = this.channel;
    Array.from(this.pending.values()).forEach((task: ResourceTask) => { if (task.channel === previous) this.fail(task); });
    this.channel = new MethodChannel(this.messenger, name);
    this.host = host;
    this.enabled = enabled;
    if (attached) this.onAttached();
  }

  onAttached(): void {
    if (this.disposed) return;
    if (!this.installed) {
      this.controller.setWebSchemeHandler('https', this.scheme);
      this.controller.setWebSchemeHandler('http', this.scheme);
      this.installed = true;
    }
    this.customSchemes.forEach((name: string) => {
      if (!this.installedCustomSchemes.has(name)) {
        this.controller.setWebSchemeHandler(name, this.scheme); this.installedCustomSchemes.add(name);
      }
    });
  }

  private arm(task: ResourceTask): void {
    if (task.timer >= 0) clearTimeout(task.timer);
    task.timer = setTimeout((): void => this.fail(task), 30000);
  }

  private async begin(task: ResourceTask): Promise<void> {
    this.arm(task);
    let bytes: Uint8Array | undefined = undefined;
    try {
      const body = task.request.getHttpBodyStream();
      if (body === null) bytes = new Uint8Array(0);
      else {
        await body.initialize();
        if (!body.isChunked() && body.getSize() <= 4 * 1024 * 1024) {
          const chunks: Array<Uint8Array> = []; let size = 0;
          while (!body.isEof() && !task.done) {
            const chunk = new Uint8Array(await body.read(65536));
            if (chunk.byteLength === 0 || size + chunk.byteLength > 4 * 1024 * 1024) break;
            chunks.push(chunk); size += chunk.byteLength;
          }
          if (body.isEof()) {
            const output = new Uint8Array(size); let offset = 0;
            chunks.forEach((chunk: Uint8Array) => { output.set(chunk, offset); offset += chunk.byteLength; });
            bytes = output;
          }
        }
      }
    } catch (_) { /* The callback explicitly receives bodyAvailable=false. */ }
    if (task.done) return;
    const headers = new Map<string, string>();
    task.request.getHeader().forEach((header: web_webview.WebHeader): void => {
      headers.set(header.headerKey, header.headerValue);
    });
    const requestArguments: Map<string, ESObject> = new Map<string, ESObject>()
      .set('id', task.id).set('uri', task.request.getRequestUrl())
      .set('method', task.request.getRequestMethod()).set('headers', headers);
    requestArguments.set('isForMainFrame', task.request.isMainFrame());
    requestArguments.set('bodyAvailable', bytes !== undefined);
    if (bytes !== undefined) requestArguments.set('body', bytes);
    this.arm(task);
    const reply: MethodResult = {
      success: (value: ESObject): void => {
        if (task.done) return;
        try {
          const metadata: Map<string, ESObject> = value as Map<string, ESObject>;
          const response = new web_webview.WebSchemeHandlerResponse();
          response.setStatus(metadata.get('statusCode') as number);
          response.setStatusText('Resource');
          response.setMimeType(metadata.get('mimeType') as string);
          const responseHeaders = metadata.get('headers') as Map<string, string>;
          responseHeaders.forEach((text: string, name: string): void => response.setHeaderByName(name, text, false));
          task.handler.didReceiveResponse(response);
          if (task.request.getRequestMethod() === 'HEAD' || metadata.get('contentLength') === 0) {
            task.handler.didFinish();
            this.remove(task);
          } else {
            this.read(task);
          }
        } catch (_) { this.fail(task); }
      },
      error: (): void => this.fail(task),
      notImplemented: (): void => this.fail(task)
    };
    try { task.channel.invokeMethod('open', requestArguments, reply); }
    catch (_) { this.fail(task); }
  }

  private read(task: ResourceTask): void {
    if (task.done) return;
    this.arm(task);
    const reply: MethodResult = {
      success: (value: ESObject): void => {
        if (task.done) return;
        try {
          if (value == null) {
            task.handler.didFinish();
            this.remove(task);
            return;
          }
          const bytes = value as Uint8Array;
          if (bytes.byteLength === 0 || bytes.byteLength > 65536) { this.fail(task); return; }
          // Codec values can be views of a larger message buffer.
          const buffer = new ArrayBuffer(bytes.byteLength);
          new Uint8Array(buffer).set(bytes);
          task.handler.didReceiveResponseBody(buffer);
          setTimeout((): void => this.read(task), 0);
        } catch (_) { this.fail(task); }
      },
      error: (): void => this.fail(task),
      notImplemented: (): void => this.fail(task)
    };
    try {
      task.channel.invokeMethod('read', new Map<string, ESObject>().set('id', task.id).set('length', 65536), reply);
    } catch (_) { this.fail(task); }
  }

  private remove(task: ResourceTask): void {
    if (task.done) return;
    task.done = true;
    if (task.timer >= 0) clearTimeout(task.timer);
    this.pending.delete(task.request);
    try {
      task.channel.invokeMethod('cancel', new Map<string, ESObject>().set('id', task.id),
        { success: (): void => {}, error: (): void => {}, notImplemented: (): void => {} });
    } catch (_) {}
  }

  private fail(task: ResourceTask): void {
    if (task.done) return;
    try { task.handler.didFail(WebNetErrorList.ERR_ABORTED, true); } catch (_) {}
    this.remove(task);
  }

  private cancelAll(): void {
    Array.from(this.pending.values()).forEach((task: ResourceTask): void => this.fail(task));
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.cancelAll();
    try {
      this.channel?.invokeMethod('closed', null,
        { success: (): void => {}, error: (): void => {}, notImplemented: (): void => {} });
      this.customChannel?.invokeMethod('closed', null,
        { success: (): void => {}, error: (): void => {}, notImplemented: (): void => {} });
    } catch (_) {}
    // The view owns this HTTPS handler; ordinary requests still return false
    // until the native Web component itself is released.
  }
}
