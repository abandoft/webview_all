export interface FinalizationListener {
  onFinalize: (identifier: number) => void;
}

export class InstanceManager {
  private static readonly FIRST_HOST_IDENTIFIER: number = 65536;

  private readonly finalizationListener: FinalizationListener;
  private readonly instances: Map<number, ESObject> = new Map();
  private identifiers: WeakMap<ESObject, number> = new WeakMap();
  private nextHostIdentifier: number = InstanceManager.FIRST_HOST_IDENTIFIER;
  private stopped: boolean = false;

  constructor(finalizationListener: FinalizationListener) {
    this.finalizationListener = finalizationListener;
  }

  create(finalizationListener: FinalizationListener): InstanceManager {
    return new InstanceManager(finalizationListener);
  }

  stopFinalizationListener(): void {
    this.stopped = true;
    this.clear();
  }

  fHasFinalizationListenerStopped(): boolean {
    return this.stopped;
  }

  clear(): void {
    this.instances.clear();
    this.identifiers = new WeakMap();
  }

  getInstance<T>(identifier: number): T {
    const instance: ESObject = this.instances.get(identifier) as ESObject;
    if (instance == null) {
      throw new Error(`No native instance is registered for identifier ${identifier}.`);
    }
    return instance as T;
  }

  getIdentifier(instance: ESObject): number {
    const identifier = this.identifiers.get(instance);
    return identifier == null ? -1 : identifier;
  }

  containsInstance(instance: ESObject): boolean {
    return this.identifiers.has(instance);
  }

  addDartCreatedInstance(instance: ESObject, identifier: number): void {
    this.addInstance(instance, identifier);
  }

  addHostCreatedInstance(instance: ESObject): number {
    if (this.containsInstance(instance)) {
      return this.getIdentifier(instance);
    }
    const identifier = this.nextHostIdentifier++;
    this.addInstance(instance, identifier);
    return identifier;
  }

  remove(identifier: number): ESObject | null {
    const instance: ESObject = this.instances.get(identifier) as ESObject;
    if (instance == null) {
      return null;
    }
    this.instances.delete(identifier);
    this.identifiers.delete(instance);
    return instance;
  }

  release(identifier: number): ESObject | null {
    const instance: ESObject | null = this.remove(identifier);
    if (instance != null && !this.stopped) {
      this.finalizationListener.onFinalize(identifier);
    }
    return instance;
  }

  private addInstance(instance: ESObject, identifier: number): void {
    if (identifier < 0) {
      throw new Error(`Instance identifier must be non-negative: ${identifier}.`);
    }
    if (this.instances.has(identifier)) {
      throw new Error(`Instance identifier is already registered: ${identifier}.`);
    }
    if (this.identifiers.has(instance)) {
      throw new Error('Native instance is already registered.');
    }
    this.instances.set(identifier, instance);
    this.identifiers.set(instance, identifier);
  }
}
