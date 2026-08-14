export interface OpenCodePanelHeader {
  headerKey: string;
  headerValue: string;
}

/**
 * Returned only to the ArkTS Web owner. Authentication material must never be
 * published through AppStorage, EventHub, logs, or panel snapshots.
 */
export interface OpenCodePanelNavigation {
  url: string;
  headers: OpenCodePanelHeader[];
  generation: number;
}

export interface OpenCodePanelSnapshot {
  phase: string;
  visible: boolean;
  ready: boolean;
  assetsPrepared: boolean;
  generation: number;
  errorCode: string;
  errorSummary: string;
  retryable: boolean;
}

export interface OpenCodePanelAsyncFailureProbeResult {
  phase: string;
  errorCode: string;
  durationMs: number;
  uiTicks: number;
  uiMaxGapMs: number;
}

export type OpenCodePanelSnapshotListener =
  (snapshot: OpenCodePanelSnapshot) => void;

export class OpenCodePanelError extends Error {
  readonly code: string;
  readonly phase: string;
  readonly retryable: boolean;

  constructor(code: string, phase: string, message: string,
    retryable: boolean = true) {
    super(message);
    this.code = code;
    this.phase = phase;
    this.retryable = retryable;
  }
}

/**
 * Shared lifecycle surface for the rollback runtime and the formal upstream
 * runtime. It deliberately excludes Provider, Session, tools, persistence,
 * routing, and protocol semantics.
 */
export interface OpenCodePanelSessionController {
  getSnapshot(): OpenCodePanelSnapshot;
  subscribe(listener: OpenCodePanelSnapshotListener): () => void;
  setProjectRoot(projectRoot: string): void;
  setVisible(visible: boolean): void;
  onForeground(): void;
  onBackground(): void;
  activate(): Promise<OpenCodePanelNavigation>;
  retry(): Promise<OpenCodePanelNavigation>;
  runAsyncFailureProbe(): Promise<OpenCodePanelAsyncFailureProbeResult>;
  stop(): Promise<void>;
  shutdown(): Promise<void>;
}
