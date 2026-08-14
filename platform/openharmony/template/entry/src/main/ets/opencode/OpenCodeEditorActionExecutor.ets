import { common } from '@kit.AbilityKit';
import plugin from 'libentry.so';
import {
  OPENCODE_EDITOR_ACTION_NATIVE_EVENT,
  OPENCODE_EDITOR_ACTION_TIMEOUT_MS,
  OpenCodeEditorActionContractError,
  parseOpenCodeEditorActionResponse,
  prepareOpenCodeEditorAction
} from './OpenCodeEditorAction';
import type {
  OpenCodeEditorActionMethod,
  OpenCodeEditorActionResult,
  OpenCodeEditorNativeAction
} from './OpenCodeEditorAction';
import { OpenCodeBridgeProtocolError } from './OpenCodeBridgeProtocol';
import type { OpenCodeBridgeCancellation } from './OpenCodeBridgeProtocol';

interface PendingEditorAction {
  timer: number;
  action: OpenCodeEditorNativeAction;
  resolve: (result: OpenCodeEditorActionResult) => void;
  reject: (error: OpenCodeBridgeProtocolError) => void;
}

interface NativeActionIdentity {
  requestId: string;
}

export type OpenCodeActionProjectRootProvider = () => string;

let nextEditorActionExecutorId: number = 0;

export class OpenCodeEditorActionExecutor {
  private readonly eventHub: common.EventHub;
  private readonly projectRootProvider: OpenCodeActionProjectRootProvider;
  private readonly executorId: string;
  private readonly nativeResponseCallback: (rawResponse: string) => void;
  private readonly pending: Map<string, PendingEditorAction> = new Map();
  private sequence: number = 0;
  private disposed: boolean = false;

  constructor(eventHub: common.EventHub, projectRootProvider: OpenCodeActionProjectRootProvider) {
    this.eventHub = eventHub;
    this.projectRootProvider = projectRootProvider;
    this.executorId = (++nextEditorActionExecutorId).toString(36);
    this.nativeResponseCallback = (rawResponse: string): void => {
      this.handleNativeResponse(rawResponse);
    };
    this.eventHub.on(OPENCODE_EDITOR_ACTION_NATIVE_EVENT, this.nativeResponseCallback);
  }

  async execute(method: OpenCodeEditorActionMethod, payload: Object | undefined,
    cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> {
    if (cancellation.isCancelled()) {
      throw new OpenCodeBridgeProtocolError(
        'ACTION_CANCELLED',
        'The editor action was cancelled before execution',
        true
      );
    }

    let action: OpenCodeEditorNativeAction;
    try {
      action = prepareOpenCodeEditorAction(method, payload, this.projectRootProvider());
    } catch (error) {
      throw this.normalizeContractError(error);
    }
    const result = await this.requestAction(action);
    if (cancellation.isCancelled()) {
      throw new OpenCodeBridgeProtocolError(
        'ACTION_CANCELLED',
        'The editor action response was cancelled',
        true
      );
    }
    return result;
  }

  async refreshCommittedPath(path: string): Promise<void> {
    let action: OpenCodeEditorNativeAction;
    try {
      action = prepareOpenCodeEditorAction(
        'editor.refresh-resource',
        { path: path },
        this.projectRootProvider()
      );
    } catch (error) {
      throw this.normalizeContractError(error);
    }
    await this.requestAction(action);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    try {
      this.eventHub.off(OPENCODE_EDITOR_ACTION_NATIVE_EVENT, this.nativeResponseCallback);
    } catch (_) {
      // Ability teardown can own and dispose the EventHub first.
    }
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new OpenCodeBridgeProtocolError(
        'ACTION_EXECUTOR_DISPOSED',
        'The editor action executor was disposed',
        true
      ));
    }
    this.pending.clear();
  }

  private requestAction(action: OpenCodeEditorNativeAction): Promise<OpenCodeEditorActionResult> {
    if (this.disposed) {
      return Promise.reject(new OpenCodeBridgeProtocolError(
        'ACTION_EXECUTOR_DISPOSED',
        'The editor action executor is unavailable',
        true
      ));
    }
    const requestId =
      `action:${this.executorId}:${Date.now().toString(36)}:${(++this.sequence).toString(36)}`;
    return new Promise<OpenCodeEditorActionResult>((resolve, reject) => {
      const timer = setTimeout((): void => {
        if (!this.pending.delete(requestId)) return;
        reject(new OpenCodeBridgeProtocolError(
          'ACTION_TIMEOUT',
          'The editor did not complete the action in time',
          true
        ));
      }, OPENCODE_EDITOR_ACTION_TIMEOUT_MS);
      const pending: PendingEditorAction = {
        timer: timer,
        action: action,
        resolve: resolve,
        reject: reject
      };
      this.pending.set(requestId, pending);
      try {
        if (!plugin.requestOpenCodeEditorAction(requestId, JSON.stringify(action))) {
          clearTimeout(timer);
          this.pending.delete(requestId);
          reject(new OpenCodeBridgeProtocolError(
            'ACTION_ENGINE_UNAVAILABLE',
            'The editor action bridge is not available yet',
            true
          ));
        }
      } catch (_) {
        clearTimeout(timer);
        this.pending.delete(requestId);
        reject(new OpenCodeBridgeProtocolError(
          'ACTION_ENGINE_UNAVAILABLE',
          'The editor action bridge could not be invoked',
          true
        ));
      }
    });
  }

  private handleNativeResponse(rawResponse: string): void {
    if (this.disposed || typeof rawResponse !== 'string' || rawResponse.length === 0) return;
    let requestId: string;
    try {
      const identity = JSON.parse(rawResponse) as NativeActionIdentity;
      requestId = identity.requestId;
    } catch (_) {
      return;
    }
    if (typeof requestId !== 'string') return;
    const pending = this.pending.get(requestId);
    if (pending === undefined) return;
    clearTimeout(pending.timer);
    this.pending.delete(requestId);
    try {
      pending.resolve(parseOpenCodeEditorActionResponse(rawResponse, requestId, pending.action));
    } catch (error) {
      pending.reject(this.normalizeContractError(error));
    }
  }

  private normalizeContractError(error: Object): OpenCodeBridgeProtocolError {
    if (error instanceof OpenCodeEditorActionContractError) {
      return new OpenCodeBridgeProtocolError(error.code, error.message, error.retryable);
    }
    return new OpenCodeBridgeProtocolError(
      'ACTION_RESPONSE_INVALID',
      'The native editor action response could not be validated'
    );
  }
}
