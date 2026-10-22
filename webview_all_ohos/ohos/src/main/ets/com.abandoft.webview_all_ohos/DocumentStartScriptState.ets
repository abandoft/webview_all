// This state machine has no ArkUI dependencies so lifecycle ordering can be
// verified independently of a device. The component acknowledges a revision
// only after its synchronous document-start modifier has been applied.
export class DocumentStartScriptSnapshot {
  readonly revision: number;
  readonly sources: Array<string>;

  constructor(revision: number, sources: Array<string>) {
    this.revision = revision;
    this.sources = sources.slice();
  }
}

class ScriptWaiter {
  readonly revision: number;
  readonly latest: boolean;
  readonly resolve: () => void;
  readonly reject: (error: Error) => void;

  constructor(revision: number, latest: boolean, resolve: () => void,
    reject: (error: Error) => void) {
    this.revision = revision;
    this.latest = latest;
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class DocumentStartScriptState {
  private current: DocumentStartScriptSnapshot = new DocumentStartScriptSnapshot(0, []);
  private appliedRevision: number = -1;
  private attached: boolean = false;
  private disposed: boolean = false;
  private attachmentError?: Error;
  private generation: number = 0;
  private listener?: (snapshot: DocumentStartScriptSnapshot) => void;
  private waiters: Array<ScriptWaiter> = [];

  getSnapshot(): DocumentStartScriptSnapshot {
    return this.current;
  }

  isDisposed(): boolean {
    return this.disposed;
  }

  isControllerAttached(): boolean {
    return this.attached;
  }

  getGeneration(): number {
    return this.generation;
  }

  subscribe(listener: (snapshot: DocumentStartScriptSnapshot) => void): void {
    this.ensureOpen();
    this.generation += 1;
    this.attachmentError = undefined;
    this.listener = listener;
    listener(this.current);
  }

  setScripts(sources: Array<string>): Promise<void> {
    this.ensureOpen();
    this.current = new DocumentStartScriptSnapshot(this.current.revision + 1, sources);
    if (this.listener) {
      this.listener(this.current);
    }
    // Registration before widget creation must complete without waiting for
    // attachment. Navigation still waits for this snapshot to be installed.
    if (!this.attached) {
      return Promise.resolve();
    }
    return this.wait(false);
  }

  markApplied(revision: number, generation: number): void {
    if (this.disposed || generation !== this.generation || !this.listener) {
      return;
    }
    this.appliedRevision = Math.max(this.appliedRevision, revision);
    this.completeReadyWaiters();
  }

  markControllerAttached(): void {
    if (this.disposed || !this.listener) {
      return;
    }
    this.attached = true;
    this.completeReadyWaiters();
  }

  waitUntilReady(): Promise<void> {
    this.ensureOpen();
    if (this.attachmentError) {
      return Promise.reject(this.attachmentError);
    }
    return this.wait(true);
  }

  failAttachment(error: Error): void {
    if (this.disposed) {
      return;
    }
    this.attached = false;
    this.attachmentError = error;
    this.rejectWaiters(error);
  }

  detach(): void {
    this.generation += 1;
    this.listener = undefined;
    this.attached = false;
    this.appliedRevision = -1;
    const pending = this.waiters;
    this.waiters = [];
    pending.forEach((waiter: ScriptWaiter) => {
      if (waiter.latest) {
        waiter.reject(new Error('The WebView component detached before it was ready.'));
      } else {
        // The snapshot remains registered for a future component, just as
        // registration before initial attachment completes immediately.
        waiter.resolve();
      }
    });
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.listener = undefined;
    this.attached = false;
    this.rejectWaiters(new Error('The WebView has been disposed.'));
  }

  private ensureOpen(): void {
    if (this.disposed) {
      throw new Error('The WebView has been disposed.');
    }
  }

  private wait(latest: boolean): Promise<void> {
    const revision = this.current.revision;
    if (this.attached && this.appliedRevision >= revision) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve, reject) => {
      this.waiters.push(new ScriptWaiter(revision, latest, resolve, reject));
    });
  }

  private completeReadyWaiters(): void {
    const pending = this.waiters;
    this.waiters = [];
    pending.forEach((waiter: ScriptWaiter) => {
      const requiredRevision = waiter.latest ? this.current.revision : waiter.revision;
      if (this.attached && this.appliedRevision >= requiredRevision) {
        waiter.resolve();
      } else {
        this.waiters.push(waiter);
      }
    });
  }

  private rejectWaiters(error: Error): void {
    const pending = this.waiters;
    this.waiters = [];
    pending.forEach((waiter: ScriptWaiter) => waiter.reject(error));
  }
}
