export const OPENCODE_BRIDGE_PROTOCOL = 'opencode.i3d.editor-bridge';
export const OPENCODE_BRIDGE_VERSION = 1;
export const OPENCODE_BRIDGE_DEFAULT_TIMEOUT_MS = 5000;
export const OPENCODE_BRIDGE_MIN_TIMEOUT_MS = 100;
export const OPENCODE_BRIDGE_MAX_TIMEOUT_MS = 30000;

const MAX_WIRE_BYTES = 65536;
const MAX_IDENTIFIER_LENGTH = 96;
const MAX_METHOD_LENGTH = 96;
const MAX_ERROR_CODE_LENGTH = 64;
const MAX_ERROR_SUMMARY_LENGTH = 160;

const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,95}$/;
const METHOD_PATTERN = /^[A-Za-z][A-Za-z0-9]*(?:[._:/-][A-Za-z0-9]+)*$/;

export type OpenCodeBridgeMessageKind = 'request' | 'response' | 'cancel';

export interface OpenCodeBridgeErrorDocument {
  code: string;
  summary: string;
  retryable: boolean;
}

interface OpenCodeBridgeBaseEnvelope {
  protocol: string;
  version: number;
  panelInstanceId: string;
  kind: OpenCodeBridgeMessageKind;
  requestId: string;
}

export interface OpenCodeBridgeRequestEnvelope extends OpenCodeBridgeBaseEnvelope {
  kind: 'request';
  method: string;
  timeoutMs: number;
  payload?: Object;
}

export interface OpenCodeBridgeResponseEnvelope extends OpenCodeBridgeBaseEnvelope {
  kind: 'response';
  ok: boolean;
  result?: Object;
  error?: OpenCodeBridgeErrorDocument;
}

export interface OpenCodeBridgeCancelEnvelope extends OpenCodeBridgeBaseEnvelope {
  kind: 'cancel';
  reason?: string;
}

export type OpenCodeBridgeEnvelope =
  OpenCodeBridgeRequestEnvelope |
  OpenCodeBridgeResponseEnvelope |
  OpenCodeBridgeCancelEnvelope;

interface OpenCodeBridgeWireShape {
  protocol?: string;
  version?: number;
  panelInstanceId?: string;
  kind?: string;
  requestId?: string;
  method?: string;
  timeoutMs?: number;
  payload?: Object;
  ok?: boolean;
  result?: Object;
  error?: OpenCodeBridgeErrorDocument;
  reason?: string;
}

export class OpenCodeBridgeProtocolError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, summary: string, retryable: boolean = false) {
    super(boundedSummary(summary));
    this.code = boundedCode(code);
    this.retryable = retryable;
  }

  toDocument(): OpenCodeBridgeErrorDocument {
    return {
      code: this.code,
      summary: boundedSummary(this.message),
      retryable: this.retryable
    };
  }
}

export interface OpenCodeBridgeCancellation {
  isCancelled(): boolean;
  reason(): string;
}

export type OpenCodeBridgeSend = (wireMessage: string) => void;
export type OpenCodeBridgeHandler =
  (payload: Object | undefined, cancellation: OpenCodeBridgeCancellation) =>
    Promise<Object | undefined>;

interface PendingBridgeRequest {
  timer: number;
  resolve: (result: Object | undefined) => void;
  reject: (error: OpenCodeBridgeProtocolError) => void;
}

class OpenCodeBridgeCancellationState implements OpenCodeBridgeCancellation {
  private cancelled: boolean = false;
  private cancellationReason: string = '';

  isCancelled(): boolean {
    return this.cancelled;
  }

  reason(): string {
    return this.cancellationReason;
  }

  cancel(reason: string): void {
    this.cancelled = true;
    this.cancellationReason = boundedSummary(reason);
  }
}

interface ActiveBridgeDispatch {
  cancel: (reason: string) => void;
}

export function validateOpenCodeBridgeProtocolContract(): void {
  if (OPENCODE_BRIDGE_VERSION !== 1 ||
    OPENCODE_BRIDGE_MIN_TIMEOUT_MS < 1 ||
    OPENCODE_BRIDGE_DEFAULT_TIMEOUT_MS < OPENCODE_BRIDGE_MIN_TIMEOUT_MS ||
    OPENCODE_BRIDGE_DEFAULT_TIMEOUT_MS > OPENCODE_BRIDGE_MAX_TIMEOUT_MS) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_CONTRACT_INVALID',
      'The compiled OpenCode editor bridge constants are inconsistent'
    );
  }
}

export function serializeOpenCodeBridgeEnvelope(envelope: OpenCodeBridgeEnvelope): string {
  validateOpenCodeBridgeEnvelope(envelope);
  const serialized = JSON.stringify(envelope);
  if (serialized.length > MAX_WIRE_BYTES) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_MESSAGE_TOO_LARGE',
      'The OpenCode editor bridge message exceeds the bounded wire size'
    );
  }
  return serialized;
}

export function parseOpenCodeBridgeEnvelope(rawMessage: string,
  expectedPanelInstanceId?: string): OpenCodeBridgeEnvelope {
  if (rawMessage.length === 0 || rawMessage.length > MAX_WIRE_BYTES) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_INVALID_JSON',
      'The OpenCode editor bridge message is empty or too large'
    );
  }

  let parsed: OpenCodeBridgeWireShape;
  try {
    parsed = JSON.parse(rawMessage) as OpenCodeBridgeWireShape;
  } catch (_) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_INVALID_JSON',
      'The OpenCode editor bridge message is not valid JSON'
    );
  }

  const envelope = validateOpenCodeBridgeEnvelope(parsed);
  if (expectedPanelInstanceId !== undefined &&
    envelope.panelInstanceId !== expectedPanelInstanceId) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_PANEL_STALE',
      'The OpenCode editor bridge message belongs to another panel instance'
    );
  }
  return envelope;
}

export function createOpenCodeBridgeErrorResponse(
  request: OpenCodeBridgeRequestEnvelope,
  error: OpenCodeBridgeProtocolError
): OpenCodeBridgeResponseEnvelope {
  return {
    protocol: OPENCODE_BRIDGE_PROTOCOL,
    version: OPENCODE_BRIDGE_VERSION,
    panelInstanceId: request.panelInstanceId,
    kind: 'response',
    requestId: request.requestId,
    ok: false,
    error: error.toDocument()
  };
}

export class OpenCodeBridgeRequestTracker {
  private readonly panelInstanceId: string;
  private readonly send: OpenCodeBridgeSend;
  private readonly pending: Map<string, PendingBridgeRequest> = new Map();
  private sequence: number = 0;
  private disposed: boolean = false;

  constructor(panelInstanceId: string, send: OpenCodeBridgeSend) {
    requireIdentifier(panelInstanceId, 'panel instance identifier');
    this.panelInstanceId = panelInstanceId;
    this.send = send;
  }

  getPanelInstanceId(): string {
    return this.panelInstanceId;
  }

  getPendingCount(): number {
    return this.pending.size;
  }

  request(method: string, payload?: Object,
    timeoutMs: number = OPENCODE_BRIDGE_DEFAULT_TIMEOUT_MS): Promise<Object | undefined> {
    if (this.disposed) {
      return Promise.reject(new OpenCodeBridgeProtocolError(
        'BRIDGE_DISPOSED',
        'The OpenCode editor bridge request tracker is disposed'
      ));
    }
    requireMethod(method);
    requireTimeout(timeoutMs);

    const requestId = this.nextRequestId();
    const envelope: OpenCodeBridgeRequestEnvelope = {
      protocol: OPENCODE_BRIDGE_PROTOCOL,
      version: OPENCODE_BRIDGE_VERSION,
      panelInstanceId: this.panelInstanceId,
      kind: 'request',
      requestId,
      method,
      timeoutMs,
      payload
    };

    return new Promise<Object | undefined>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (!this.pending.delete(requestId)) return;
        this.sendCancellation(requestId, 'timeout');
        reject(new OpenCodeBridgeProtocolError(
          'BRIDGE_TIMEOUT',
          `The OpenCode editor bridge request timed out: ${method}`,
          true
        ));
      }, timeoutMs);
      this.pending.set(requestId, { timer, resolve, reject });

      try {
        this.send(serializeOpenCodeBridgeEnvelope(envelope));
      } catch (_) {
        clearTimeout(timer);
        this.pending.delete(requestId);
        reject(new OpenCodeBridgeProtocolError(
          'BRIDGE_SEND_FAILED',
          'The OpenCode editor bridge request could not be sent',
          true
        ));
      }
    });
  }

  handleIncoming(rawMessage: string): boolean {
    let envelope: OpenCodeBridgeEnvelope;
    try {
      envelope = parseOpenCodeBridgeEnvelope(rawMessage, this.panelInstanceId);
    } catch (_) {
      return false;
    }
    if (envelope.kind !== 'response') return false;

    const pending = this.pending.get(envelope.requestId);
    if (pending === undefined) return false;
    clearTimeout(pending.timer);
    this.pending.delete(envelope.requestId);

    if (envelope.ok) {
      pending.resolve(envelope.result);
      return true;
    }
    const error = envelope.error as OpenCodeBridgeErrorDocument;
    pending.reject(new OpenCodeBridgeProtocolError(
      error.code,
      error.summary,
      error.retryable
    ));
    return true;
  }

  cancel(requestId: string, reason: string = 'cancelled'): boolean {
    const pending = this.pending.get(requestId);
    if (pending === undefined) return false;
    clearTimeout(pending.timer);
    this.pending.delete(requestId);
    pending.reject(new OpenCodeBridgeProtocolError(
      'BRIDGE_CANCELLED',
      'The OpenCode editor bridge request was cancelled'
    ));
    this.sendCancellation(requestId, reason);
    return true;
  }

  cancelAll(reason: string = 'panel-disposed'): void {
    const requestIds: string[] = [];
    this.pending.forEach((_pending, requestId) => {
      requestIds.push(requestId);
    });
    requestIds.forEach((requestId) => {
      this.cancel(requestId, reason);
    });
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.cancelAll('panel-disposed');
  }

  private nextRequestId(): string {
    this.sequence += 1;
    return `r:${Date.now().toString(36)}:${this.sequence.toString(36)}`;
  }

  private sendCancellation(requestId: string, reason: string): void {
    const envelope: OpenCodeBridgeCancelEnvelope = {
      protocol: OPENCODE_BRIDGE_PROTOCOL,
      version: OPENCODE_BRIDGE_VERSION,
      panelInstanceId: this.panelInstanceId,
      kind: 'cancel',
      requestId,
      reason: boundedSummary(reason)
    };
    try {
      this.send(serializeOpenCodeBridgeEnvelope(envelope));
    } catch (_) {
      // The local request is already settled. A transport failure must not
      // resurrect it or leak an unhandled exception.
    }
  }
}

export class OpenCodeBridgeDispatcher {
  private readonly panelInstanceId: string;
  private readonly handlers: Map<string, OpenCodeBridgeHandler> = new Map();
  private readonly active: Map<string, ActiveBridgeDispatch> = new Map();
  private disposed: boolean = false;

  constructor(panelInstanceId: string) {
    requireIdentifier(panelInstanceId, 'panel instance identifier');
    this.panelInstanceId = panelInstanceId;
  }

  register(method: string, handler: OpenCodeBridgeHandler): void {
    if (this.disposed) {
      throw new OpenCodeBridgeProtocolError(
        'BRIDGE_DISPOSED',
        'The OpenCode editor bridge dispatcher is disposed'
      );
    }
    requireMethod(method);
    if (this.handlers.has(method)) {
      throw new OpenCodeBridgeProtocolError(
        'BRIDGE_DUPLICATE_HANDLER',
        `The OpenCode editor bridge handler is already registered: ${method}`
      );
    }
    this.handlers.set(method, handler);
  }

  unregister(method: string): void {
    this.handlers.delete(method);
  }

  getActiveCount(): number {
    return this.active.size;
  }

  async handleIncoming(rawMessage: string): Promise<string | undefined> {
    let envelope: OpenCodeBridgeEnvelope;
    try {
      envelope = parseOpenCodeBridgeEnvelope(rawMessage, this.panelInstanceId);
    } catch (_) {
      return undefined;
    }

    if (envelope.kind === 'cancel') {
      const active = this.active.get(envelope.requestId);
      if (active === undefined) return undefined;
      active.cancel(envelope.reason === undefined ? 'cancelled' : envelope.reason);
      return undefined;
    }
    if (envelope.kind !== 'request') return undefined;

    if (this.disposed) {
      return serializeOpenCodeBridgeEnvelope(createOpenCodeBridgeErrorResponse(
        envelope,
        new OpenCodeBridgeProtocolError(
          'BRIDGE_DISPOSED',
          'The OpenCode editor bridge dispatcher is disposed'
        )
      ));
    }
    if (this.active.has(envelope.requestId)) {
      return serializeOpenCodeBridgeEnvelope(createOpenCodeBridgeErrorResponse(
        envelope,
        new OpenCodeBridgeProtocolError(
          'BRIDGE_DUPLICATE_REQUEST',
          'The OpenCode editor bridge request identifier is already active'
        )
      ));
    }

    const handler = this.handlers.get(envelope.method);
    if (handler === undefined) {
      return serializeOpenCodeBridgeEnvelope(createOpenCodeBridgeErrorResponse(
        envelope,
        new OpenCodeBridgeProtocolError(
          'BRIDGE_UNSUPPORTED',
          `The OpenCode editor bridge method is unsupported: ${envelope.method}`
        )
      ));
    }
    return this.dispatch(envelope, handler);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    const activeRequests: ActiveBridgeDispatch[] = [];
    this.active.forEach((active) => {
      activeRequests.push(active);
    });
    activeRequests.forEach((active) => {
      active.cancel('dispatcher-disposed');
    });
    this.handlers.clear();
  }

  private dispatch(request: OpenCodeBridgeRequestEnvelope,
    handler: OpenCodeBridgeHandler): Promise<string | undefined> {
    const cancellation = new OpenCodeBridgeCancellationState();
    return new Promise<string | undefined>((resolve) => {
      let settled = false;
      const settle = (wireMessage: string | undefined): void => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        this.active.delete(request.requestId);
        resolve(wireMessage);
      };
      const timer = setTimeout(() => {
        cancellation.cancel('timeout');
        settle(serializeOpenCodeBridgeEnvelope(createOpenCodeBridgeErrorResponse(
          request,
          new OpenCodeBridgeProtocolError(
            'BRIDGE_TIMEOUT',
            `The OpenCode editor bridge handler timed out: ${request.method}`,
            true
          )
        )));
      }, request.timeoutMs);

      this.active.set(request.requestId, {
        cancel: (reason: string): void => {
          cancellation.cancel(reason);
          settle(undefined);
        }
      });

      let handlerPromise: Promise<Object | undefined>;
      try {
        handlerPromise = handler(request.payload, cancellation);
      } catch (_) {
        settle(serializeOpenCodeBridgeEnvelope(
          createOpenCodeBridgeErrorResponse(
            request,
            new OpenCodeBridgeProtocolError(
              'BRIDGE_HANDLER_FAILED',
              'The OpenCode editor bridge handler failed',
              true
            )
          )
        ));
        return;
      }

      handlerPromise.then((result) => {
        if (settled || cancellation.isCancelled()) return;
        const response: OpenCodeBridgeResponseEnvelope = {
          protocol: OPENCODE_BRIDGE_PROTOCOL,
          version: OPENCODE_BRIDGE_VERSION,
          panelInstanceId: request.panelInstanceId,
          kind: 'response',
          requestId: request.requestId,
          ok: true,
          result
        };
        settle(serializeOpenCodeBridgeEnvelope(response));
      }).catch((error) => {
        if (settled || cancellation.isCancelled()) return;
        const protocolError = error instanceof OpenCodeBridgeProtocolError ?
          error :
          new OpenCodeBridgeProtocolError(
            'BRIDGE_HANDLER_FAILED',
            'The OpenCode editor bridge handler failed',
            true
          );
        settle(serializeOpenCodeBridgeEnvelope(
          createOpenCodeBridgeErrorResponse(request, protocolError)
        ));
      });
    });
  }
}

function validateOpenCodeBridgeEnvelope(
  value: OpenCodeBridgeWireShape | OpenCodeBridgeEnvelope
): OpenCodeBridgeEnvelope {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_INVALID_ENVELOPE',
      'The OpenCode editor bridge message must be an object'
    );
  }
  if (value.protocol !== OPENCODE_BRIDGE_PROTOCOL) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_PROTOCOL_UNSUPPORTED',
      'The OpenCode editor bridge protocol identifier is unsupported'
    );
  }
  if (!Number.isInteger(value.version) || value.version !== OPENCODE_BRIDGE_VERSION) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_VERSION_UNSUPPORTED',
      'The OpenCode editor bridge protocol version is unsupported'
    );
  }
  requireIdentifier(value.panelInstanceId, 'panel instance identifier');
  requireIdentifier(value.requestId, 'request identifier');

  if (value.kind === 'request') {
    requireMethod(value.method);
    requireTimeout(value.timeoutMs);
    return {
      protocol: value.protocol,
      version: value.version,
      panelInstanceId: value.panelInstanceId,
      kind: 'request',
      requestId: value.requestId,
      method: value.method,
      timeoutMs: value.timeoutMs,
      payload: value.payload
    };
  }
  if (value.kind === 'response') {
    if (typeof value.ok !== 'boolean') {
      throw new OpenCodeBridgeProtocolError(
        'BRIDGE_INVALID_ENVELOPE',
        'The OpenCode editor bridge response is missing its status'
      );
    }
    if (!value.ok) validateErrorDocument(value.error);
    if (value.ok && value.error !== undefined) {
      throw new OpenCodeBridgeProtocolError(
        'BRIDGE_INVALID_ENVELOPE',
        'A successful OpenCode editor bridge response cannot include an error'
      );
    }
    return {
      protocol: value.protocol,
      version: value.version,
      panelInstanceId: value.panelInstanceId,
      kind: 'response',
      requestId: value.requestId,
      ok: value.ok,
      result: value.result,
      error: value.error
    };
  }
  if (value.kind === 'cancel') {
    if (value.reason !== undefined && typeof value.reason !== 'string') {
      throw new OpenCodeBridgeProtocolError(
        'BRIDGE_INVALID_ENVELOPE',
        'The OpenCode editor bridge cancellation reason must be text'
      );
    }
    return {
      protocol: value.protocol,
      version: value.version,
      panelInstanceId: value.panelInstanceId,
      kind: 'cancel',
      requestId: value.requestId,
      reason: value.reason === undefined ? undefined : boundedSummary(value.reason)
    };
  }
  throw new OpenCodeBridgeProtocolError(
    'BRIDGE_INVALID_ENVELOPE',
    'The OpenCode editor bridge message kind is unsupported'
  );
}

function validateErrorDocument(error?: OpenCodeBridgeErrorDocument): void {
  if (error === undefined || error === null || typeof error !== 'object') {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_INVALID_ENVELOPE',
      'The failed OpenCode editor bridge response is missing its error'
    );
  }
  if (typeof error.code !== 'string' ||
    typeof error.summary !== 'string' ||
    typeof error.retryable !== 'boolean' ||
    boundedCode(error.code) !== error.code ||
    boundedSummary(error.summary) !== error.summary) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_INVALID_ENVELOPE',
      'The OpenCode editor bridge error document is invalid'
    );
  }
}

function requireIdentifier(value: string | undefined, label: string): void {
  if (typeof value !== 'string' ||
    value.length === 0 ||
    value.length > MAX_IDENTIFIER_LENGTH ||
    !IDENTIFIER_PATTERN.test(value)) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_IDENTIFIER_INVALID',
      `The OpenCode editor bridge ${label} is invalid`
    );
  }
}

function requireMethod(method: string | undefined): void {
  if (typeof method !== 'string' ||
    method.length === 0 ||
    method.length > MAX_METHOD_LENGTH ||
    !METHOD_PATTERN.test(method)) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_METHOD_INVALID',
      'The OpenCode editor bridge method is invalid'
    );
  }
}

function requireTimeout(timeoutMs: number | undefined): void {
  if (!Number.isInteger(timeoutMs) ||
    (timeoutMs as number) < OPENCODE_BRIDGE_MIN_TIMEOUT_MS ||
    (timeoutMs as number) > OPENCODE_BRIDGE_MAX_TIMEOUT_MS) {
    throw new OpenCodeBridgeProtocolError(
      'BRIDGE_TIMEOUT_INVALID',
      'The OpenCode editor bridge timeout is outside the supported range'
    );
  }
}

function boundedCode(code: string): string {
  const normalized = code.toUpperCase().replace(/[^A-Z0-9_]/g, '_');
  if (normalized.length === 0) return 'BRIDGE_ERROR';
  return normalized.substring(0, MAX_ERROR_CODE_LENGTH);
}

function boundedSummary(summary: string): string {
  return summary.replace(/[\r\n\t]/g, ' ').trim().substring(0, MAX_ERROR_SUMMARY_LENGTH);
}
