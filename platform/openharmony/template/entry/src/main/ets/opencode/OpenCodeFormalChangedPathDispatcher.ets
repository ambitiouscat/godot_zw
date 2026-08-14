import { common } from '@kit.AbilityKit';
import {
  OpenCodeFormalChangedPathError,
  OpenCodeFormalChangedPathGate
} from './OpenCodeFormalChangedPath';
import { OpenCodeEditorActionExecutor } from './OpenCodeEditorActionExecutor';
import type {
  OpenCodeFormalHostEvent,
  OpenCodeFormalRuntimeController
} from './OpenCodeFormalRuntimeController';

const FORMAL_CHANGED_PATH_POLL_INTERVAL_MS = 50;
const MAX_ERROR_CODE_LENGTH = 64;

export type OpenCodeFormalRuntimeHostEventObserver =
  (event: OpenCodeFormalHostEvent) => void;

interface OpenCodeFormalChangedPathStructuredError {
  code?: string;
}

/**
 * Continuously drains the formal NativeChildProcess host-event queue.
 *
 * A workspace event can invoke only the fixed refresh-resource action. The
 * event payload never selects an action method and failed refreshes are not
 * automatically replayed because the native action may already have run.
 */
export class OpenCodeFormalChangedPathDispatcher {
  private readonly runtimeController: OpenCodeFormalRuntimeController;
  private readonly actionExecutor: OpenCodeEditorActionExecutor;
  private readonly runtimeEventObserver: OpenCodeFormalRuntimeHostEventObserver;
  private readonly gate: OpenCodeFormalChangedPathGate =
    new OpenCodeFormalChangedPathGate();
  private activeGeneration: number = 0;
  private pollVersion: number = 0;
  private pollTimer?: number;
  private pollActive: boolean = false;
  private disposed: boolean = false;

  constructor(eventHub: common.EventHub,
    runtimeController: OpenCodeFormalRuntimeController,
    projectRootProvider: () => string,
    runtimeEventObserver: OpenCodeFormalRuntimeHostEventObserver) {
    this.runtimeController = runtimeController;
    this.actionExecutor =
      new OpenCodeEditorActionExecutor(eventHub, projectRootProvider);
    this.runtimeEventObserver = runtimeEventObserver;
    this.publishState('idle', 'none');
  }

  start(generation: number): void {
    if (this.disposed) return;
    if (this.activeGeneration === generation) return;
    this.stop();
    this.gate.start(generation);
    this.activeGeneration = generation;
    this.publishState('ready', 'none');
    this.schedule(this.pollVersion);
  }

  stop(): void {
    ++this.pollVersion;
    if (this.pollTimer !== undefined) {
      clearTimeout(this.pollTimer);
      this.pollTimer = undefined;
    }
    this.activeGeneration = 0;
    this.gate.stop();
    if (!this.disposed) this.publishState('idle', 'none');
  }

  dispose(): void {
    if (this.disposed) return;
    this.stop();
    this.disposed = true;
    this.actionExecutor.dispose();
    this.publishState('disposed', 'none');
  }

  private schedule(version: number): void {
    if (this.disposed || this.activeGeneration <= 0 ||
      version !== this.pollVersion || this.pollTimer !== undefined) {
      return;
    }
    this.pollTimer = setTimeout((): void => {
      this.pollTimer = undefined;
      this.poll(version).catch(() => {
        // poll() records only a bounded error code and always schedules the
        // next drain while the same generation remains active.
      });
    }, FORMAL_CHANGED_PATH_POLL_INTERVAL_MS);
  }

  private async poll(version: number): Promise<void> {
    if (this.pollActive || this.disposed || this.activeGeneration <= 0 ||
      version !== this.pollVersion) {
      this.schedule(version);
      return;
    }
    this.pollActive = true;
    try {
      const event = this.runtimeController.readHostEvent();
      if (event !== undefined) {
        if (event.kind === 'workspace.changed') {
          const change = this.gate.accept(event);
          if (change !== undefined) {
            await this.actionExecutor.refreshCommittedPath(change.path);
            this.publishState('ready', 'none');
          }
        } else {
          this.runtimeEventObserver(event);
        }
      }
    } catch (error) {
      this.publishState('failed', this.errorCode(error));
    } finally {
      this.pollActive = false;
      this.schedule(version);
    }
  }

  private errorCode(error: Object): string {
    if (error instanceof OpenCodeFormalChangedPathError) {
      return this.boundedCode(error.code);
    }
    const candidate = error as OpenCodeFormalChangedPathStructuredError;
    if (typeof candidate.code === 'string') {
      return this.boundedCode(candidate.code);
    }
    return 'FORMAL_CHANGED_PATH_DISPATCH_FAILED';
  }

  private boundedCode(value: string): string {
    const normalized = value.toUpperCase().replace(/[^A-Z0-9_]/g, '_');
    return (normalized.length === 0 ?
      'FORMAL_CHANGED_PATH_DISPATCH_FAILED' : normalized)
      .substring(0, MAX_ERROR_CODE_LENGTH);
  }

  private publishState(phase: string, errorCode: string): void {
    AppStorage.setOrCreate('openCodeChangedPathBridgePhase', phase);
    AppStorage.setOrCreate('openCodeChangedPathBridgeErrorCode', errorCode);
  }
}
