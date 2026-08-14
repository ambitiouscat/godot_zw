import { common } from '@kit.AbilityKit';
import plugin from 'libentry.so';
import {
  OPENCODE_EDITOR_CONTEXT_NATIVE_EVENT,
  OPENCODE_EDITOR_CONTEXT_TIMEOUT_MS,
  OpenCodeEditorContextContractError,
  parseOpenCodeEditorContextResponse,
  selectOpenCodeEditorContext
} from './OpenCodeEditorContext';
import type {
  OpenCodeEditorContextMethod,
  OpenCodeEditorContextSnapshot
} from './OpenCodeEditorContext';
import { OpenCodeBridgeProtocolError } from './OpenCodeBridgeProtocol';
import type { OpenCodeBridgeCancellation } from './OpenCodeBridgeProtocol';

interface PendingContextRequest {
  timer: number;
  resolve: (snapshot: OpenCodeEditorContextSnapshot) => void;
  reject: (error: OpenCodeBridgeProtocolError) => void;
}

export type OpenCodeProjectRootProvider = () => string;

export class OpenCodeContextCollector {
  private readonly eventHub: common.EventHub;
  private readonly projectRootProvider: OpenCodeProjectRootProvider;
  private readonly nativeResponseCallback: (rawResponse: string) => void;
  private readonly pending: Map<string, PendingContextRequest> = new Map();
  private sequence: number = 0;
  private disposed: boolean = false;

  constructor(eventHub: common.EventHub, projectRootProvider: OpenCodeProjectRootProvider) {
    this.eventHub = eventHub;
    this.projectRootProvider = projectRootProvider;
    this.nativeResponseCallback = (rawResponse: string): void => {
      this.handleNativeResponse(rawResponse);
    };
    this.eventHub.on(OPENCODE_EDITOR_CONTEXT_NATIVE_EVENT, this.nativeResponseCallback);
  }

  async collect(method: OpenCodeEditorContextMethod, payload: Object | undefined,
    cancellation: OpenCodeBridgeCancellation): Promise<Object | undefined> {
    if (payload !== undefined) {
      throw new OpenCodeBridgeProtocolError(
        'CONTEXT_PAYLOAD_REJECTED',
        'Editor context requests do not accept caller supplied paths or selectors'
      );
    }
    if (cancellation.isCancelled()) {
      throw new OpenCodeBridgeProtocolError(
        'CONTEXT_CANCELLED',
        'The editor context request was cancelled',
        true
      );
    }
    const snapshot = await this.requestSnapshot();
    if (cancellation.isCancelled()) {
      throw new OpenCodeBridgeProtocolError(
        'CONTEXT_CANCELLED',
        'The editor context request was cancelled',
        true
      );
    }
    return selectOpenCodeEditorContext(method, snapshot);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    try {
      this.eventHub.off(OPENCODE_EDITOR_CONTEXT_NATIVE_EVENT, this.nativeResponseCallback);
    } catch (_) {
      // Ability teardown can own and dispose the EventHub first.
    }
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new OpenCodeBridgeProtocolError(
        'CONTEXT_COLLECTOR_DISPOSED',
        'The editor context collector was disposed',
        true
      ));
    }
    this.pending.clear();
  }

  private requestSnapshot(): Promise<OpenCodeEditorContextSnapshot> {
    if (this.disposed) {
      return Promise.reject(new OpenCodeBridgeProtocolError(
        'CONTEXT_COLLECTOR_DISPOSED',
        'The editor context collector is unavailable',
        true
      ));
    }
    const requestId = `context:${Date.now().toString(36)}:${(++this.sequence).toString(36)}`;
    return new Promise<OpenCodeEditorContextSnapshot>((resolve, reject) => {
      const timer = setTimeout((): void => {
        if (!this.pending.delete(requestId)) return;
        reject(new OpenCodeBridgeProtocolError(
          'CONTEXT_TIMEOUT',
          'The editor did not return a context snapshot in time',
          true
        ));
      }, OPENCODE_EDITOR_CONTEXT_TIMEOUT_MS);
      const pending: PendingContextRequest = { timer: timer, resolve: resolve, reject: reject };
      this.pending.set(requestId, pending);
      try {
        if (!plugin.requestOpenCodeEditorContext(requestId)) {
          clearTimeout(timer);
          this.pending.delete(requestId);
          reject(new OpenCodeBridgeProtocolError(
            'CONTEXT_ENGINE_UNAVAILABLE',
            'The editor context bridge is not available yet',
            true
          ));
        }
      } catch (_) {
        clearTimeout(timer);
        this.pending.delete(requestId);
        reject(new OpenCodeBridgeProtocolError(
          'CONTEXT_ENGINE_UNAVAILABLE',
          'The editor context bridge could not be invoked',
          true
        ));
      }
    });
  }

  private handleNativeResponse(rawResponse: string): void {
    if (this.disposed || typeof rawResponse !== 'string' || rawResponse.length === 0) return;
    let requestId: string;
    try {
      const untrusted = JSON.parse(rawResponse) as NativeRequestIdentity;
      requestId = untrusted.requestId;
    } catch (_) {
      return;
    }
    if (typeof requestId !== 'string') return;
    const pending = this.pending.get(requestId);
    if (pending === undefined) return;
    clearTimeout(pending.timer);
    this.pending.delete(requestId);
    try {
      pending.resolve(parseOpenCodeEditorContextResponse(
        rawResponse,
        requestId,
        this.projectRootProvider()
      ));
    } catch (error) {
      if (error instanceof OpenCodeEditorContextContractError) {
        pending.reject(new OpenCodeBridgeProtocolError(
          error.code,
          error.message,
          error.retryable
        ));
        return;
      }
      pending.reject(new OpenCodeBridgeProtocolError(
        'CONTEXT_RESPONSE_INVALID',
        'The native editor context response could not be validated'
      ));
    }
  }
}

interface NativeRequestIdentity {
  requestId: string;
}
