import { InstanceManager } from './InstanceManager';

export class OhosObjectHostApiImpl {
  private readonly instanceManager: InstanceManager;

  constructor(instanceManager: InstanceManager) {
    this.instanceManager = instanceManager;
  }

  dispose(identifier: number): void {
    this.instanceManager.release(identifier);
  }
}
