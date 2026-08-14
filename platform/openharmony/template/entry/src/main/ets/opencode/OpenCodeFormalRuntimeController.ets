import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import formalRuntime from 'libopencode_formal_runtime.so';
import type {
  FormalHostCallback,
  FormalRuntimeBootstrapInput,
  FormalRuntimeContract,
  FormalRuntimeStartResult,
  FormalRuntimeState,
  FormalRuntimeStopResult
} from 'libopencode_formal_runtime.so';

const FORMAL_RUNTIME_CONTRACT_VERSION = 1;
const FORMAL_RUNTIME_CAPABILITY_PROFILE = 'harmony-tier-a';
const FORMAL_RUNTIME_ENTRY_EXPORT = 'startHarmonyNativeChildRuntime';
const FORMAL_RUNTIME_ALLOWED_ORIGIN = 'http://127.0.0.1';
const FORMAL_RUNTIME_HOST_EVENT_NAME = 'opencode-formal-host-event.json';
const FORMAL_RUNTIME_MAX_PATH_BYTES = 4096;
const FORMAL_RUNTIME_MAX_HOST_EVENT_BYTES = 4096;
const FORMAL_RUNTIME_READY_TIMEOUT_MS = 15000;
const FORMAL_RUNTIME_STOP_TIMEOUT_MS = 5000;
const FORMAL_RUNTIME_POLL_INTERVAL_MS = 50;
const FORMAL_RUNTIME_INACTIVE = -7001;

const FORMAL_RUNTIME_APPROVED_CALLBACKS: ReadonlyArray<FormalHostCallback> = [
  'runtime.ready',
  'runtime.fatal',
  'runtime.stopped',
  'workspace.changed'
];

interface FormalHostEventDocument {
  version: number;
  generation: number;
  sequence: number;
  kind: string;
  payload: string;
}

interface FormalReadyPayload {
  generation: number;
  hostname: string;
  port: number;
}

interface FormalFatalPayload {
  generation: number;
  code: string;
  category: string;
}

export interface OpenCodeFormalHostEvent {
  version: 1;
  generation: number;
  sequence: number;
  kind: FormalHostCallback;
  payload: string;
}

export interface OpenCodeFormalRuntimeConnection {
  generation: number;
  hostname: '127.0.0.1';
  port: number;
  origin: string;
  authorization: string;
}

export interface OpenCodeFormalRuntimeSnapshot {
  contractVersion: 1;
  capabilityProfile: 'harmony-tier-a';
  phase: string;
  generation: number;
  port: number;
  projectAuthorized: boolean;
  errorCode: string;
}

export class OpenCodeFormalRuntimeControllerError extends Error {
  readonly code: string;
  readonly phase: string;

  constructor(code: string, phase: string, message: string) {
    super(message);
    this.code = code;
    this.phase = phase;
  }
}

/**
 * ArkTS-side owner for the formal libnode child lifetime.
 *
 * This controller intentionally contains no OpenCode routes, Provider/Session
 * behavior, tool dispatch, persistence projection, or client state. Those
 * semantics stay in the packaged upstream TypeScript runtime.
 */
export class OpenCodeFormalRuntimeController {
  private readonly filesDirectory: string;
  private readonly cacheDirectory: string;
  private readonly temporaryDirectory: string;
  private projectRoot: string;
  private phase: string = 'idle';
  private activeGeneration: number = 0;
  private activePort: number = 0;
  private activeCredential: string = '';
  private lastHostSequence: number = 0;
  private errorCode: string = 'none';

  constructor(filesDirectory: string, cacheDirectory: string,
    temporaryDirectory: string, projectRoot: string) {
    this.filesDirectory = this.requireAbsolutePath(
      filesDirectory, 'FORMAL_FILES_DIRECTORY_INVALID');
    this.cacheDirectory = this.requireAbsolutePath(
      cacheDirectory, 'FORMAL_CACHE_DIRECTORY_INVALID');
    this.temporaryDirectory = this.requireAbsolutePath(
      temporaryDirectory, 'FORMAL_TEMP_DIRECTORY_INVALID');
    this.projectRoot = '';
    if (projectRoot.length > 0) {
      this.projectRoot = this.requireAbsolutePath(
        projectRoot, 'FORMAL_PROJECT_ROOT_INVALID');
    }
    this.validateNativeContract(formalRuntime.getFormalRuntimeContract());
  }

  getPhase(): string {
    return this.phase;
  }

  getSnapshot(): OpenCodeFormalRuntimeSnapshot {
    return {
      contractVersion: 1,
      capabilityProfile: 'harmony-tier-a',
      phase: this.phase,
      generation: this.activeGeneration,
      port: this.activePort,
      projectAuthorized: this.projectRoot.length > 0,
      errorCode: this.errorCode
    };
  }

  updateAuthorizedProjectRoot(projectRoot: string): void {
    if (this.activeGeneration !== 0 ||
      this.phase === 'starting' ||
      this.phase === 'ready' ||
      this.phase === 'stopping') {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_PROJECT_CHANGE_WHILE_ACTIVE',
        this.phase,
        'The authorized project cannot change while the formal runtime is active'
      );
    }
    this.projectRoot = projectRoot.length === 0 ? '' :
      this.requireAbsolutePath(projectRoot, 'FORMAL_PROJECT_ROOT_INVALID');
  }

  async start(entryPath: string, requestedPort: number = 0):
    Promise<OpenCodeFormalRuntimeConnection> {
    if (this.phase === 'starting' ||
      this.phase === 'ready' ||
      this.phase === 'stopping' ||
      this.activeGeneration !== 0) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_RUNTIME_ALREADY_ACTIVE',
        this.phase,
        'A formal runtime generation is already active'
      );
    }
    if (this.projectRoot.length === 0) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_PROJECT_ROOT_REQUIRED',
        this.phase,
        'An authorized project root is required before starting the formal runtime'
      );
    }
    if (!Number.isInteger(requestedPort) || requestedPort < 0 || requestedPort > 65535) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_RUNTIME_PORT_INVALID',
        this.phase,
        'The requested formal runtime port is invalid'
      );
    }

    const acceptedEntryPath = this.requireAbsolutePath(
      entryPath, 'FORMAL_RUNTIME_ENTRY_INVALID');
    if (!this.isPathInside(this.filesDirectory, acceptedEntryPath)) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_RUNTIME_ENTRY_OUTSIDE_FILES',
        this.phase,
        'The formal runtime entry must be inside the application files directory'
      );
    }

    const credential = this.createCredential();
    const bootstrap: FormalRuntimeBootstrapInput = {
      filesDirectory: this.filesDirectory,
      cacheDirectory: this.cacheDirectory,
      temporaryDirectory: this.temporaryDirectory,
      projectRoot: this.projectRoot,
      entryPath: acceptedEntryPath,
      credential,
      allowedOrigin: FORMAL_RUNTIME_ALLOWED_ORIGIN,
      capabilityProfile: 'harmony-tier-a',
      deviceForm: deviceInfo.deviceType ?? '',
      requestedPort
    };

    this.phase = 'starting';
    this.errorCode = 'none';
    this.lastHostSequence = 0;
    try {
      const started = formalRuntime.startFormalRuntime(bootstrap);
      if (started.code === 0 && started.generation > 0) {
        this.activeGeneration = started.generation;
        this.activeCredential = credential;
      }
      this.validateStartResult(started);
      const ready = await this.waitForReady(started.generation);
      this.activePort = ready.port;
      this.phase = 'ready';
      return this.requireConnection();
    } catch (error) {
      const normalized = this.normalizeError(
        error, 'FORMAL_RUNTIME_START_FAILED', 'starting',
        'The formal upstream runtime could not be started');
      await this.stopFailedStart();
      this.phase = 'failed';
      this.errorCode = normalized.code;
      throw normalized;
    }
  }

  requireConnection(): OpenCodeFormalRuntimeConnection {
    if (this.phase !== 'ready' ||
      this.activeGeneration <= 0 ||
      this.activePort <= 0 ||
      this.activeCredential.length === 0) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_RUNTIME_NOT_READY',
        this.phase,
        'The formal runtime connection is not ready'
      );
    }
    return {
      generation: this.activeGeneration,
      hostname: '127.0.0.1',
      port: this.activePort,
      origin: `http://127.0.0.1:${this.activePort}`,
      authorization: this.createBasicAuthorization(this.activeCredential)
    };
  }

  readHostEvent(): OpenCodeFormalHostEvent | undefined {
    const rawEvent = formalRuntime.readFormalHostEvent();
    if (rawEvent.length === 0) return undefined;
    if (rawEvent.length > FORMAL_RUNTIME_MAX_HOST_EVENT_BYTES) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_HOST_EVENT_TOO_LARGE',
        this.phase,
        'The formal runtime host event exceeds the contract limit'
      );
    }

    let parsed: FormalHostEventDocument;
    try {
      parsed = JSON.parse(rawEvent) as FormalHostEventDocument;
    } catch (_) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_HOST_EVENT_INVALID',
        this.phase,
        'The formal runtime host event is not valid JSON'
      );
    }
    if (parsed.version !== FORMAL_RUNTIME_CONTRACT_VERSION ||
      !Number.isInteger(parsed.generation) ||
      parsed.generation <= 0 ||
      !Number.isInteger(parsed.sequence) ||
      parsed.sequence <= 0 ||
      typeof parsed.kind !== 'string' ||
      typeof parsed.payload !== 'string' ||
      parsed.payload.length > FORMAL_RUNTIME_MAX_HOST_EVENT_BYTES) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_HOST_EVENT_INVALID',
        this.phase,
        'The formal runtime host event does not match the versioned contract'
      );
    }
    const callback = this.requireApprovedCallback(parsed.kind);
    if (parsed.generation !== this.activeGeneration ||
      parsed.sequence <= this.lastHostSequence) {
      return undefined;
    }
    this.lastHostSequence = parsed.sequence;
    return {
      version: 1,
      generation: parsed.generation,
      sequence: parsed.sequence,
      kind: callback,
      payload: parsed.payload
    };
  }

  async shutdownIfRunning(): Promise<void> {
    const generation = this.activeGeneration;
    if (generation <= 0) {
      this.clearConnection();
      if (this.phase !== 'failed') this.phase = 'stopped';
      return;
    }

    const state = formalRuntime.getFormalRuntimeState();
    if (state.activeGeneration === generation && state.activePid >= 0) {
      this.phase = 'stopping';
      const stopped = formalRuntime.stopFormalRuntime(generation);
      this.validateStopResult(stopped);
    } else if (state.activeGeneration !== 0 &&
      state.activeGeneration !== generation) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_RUNTIME_GENERATION_STALE',
        this.phase,
        'The active formal runtime generation no longer matches the controller'
      );
    }

    await this.waitForStopped(generation);
    this.clearConnection();
    this.phase = 'stopped';
    this.errorCode = 'none';
  }

  private validateNativeContract(contract: FormalRuntimeContract): void {
    if (contract.version !== FORMAL_RUNTIME_CONTRACT_VERSION ||
      contract.capabilityProfile !== FORMAL_RUNTIME_CAPABILITY_PROFILE ||
      contract.entryExport !== FORMAL_RUNTIME_ENTRY_EXPORT ||
      contract.approvedHostCallbacks.length !==
        FORMAL_RUNTIME_APPROVED_CALLBACKS.length) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_NATIVE_CONTRACT_INVALID',
        'initializing',
        'The formal native runtime contract is incompatible'
      );
    }
    for (let index = 0; index < FORMAL_RUNTIME_APPROVED_CALLBACKS.length; index++) {
      if (contract.approvedHostCallbacks[index] !==
        FORMAL_RUNTIME_APPROVED_CALLBACKS[index]) {
        throw new OpenCodeFormalRuntimeControllerError(
          'FORMAL_NATIVE_CONTRACT_INVALID',
          'initializing',
          'The formal native runtime callback contract is incompatible'
        );
      }
    }
  }

  private validateStartResult(result: FormalRuntimeStartResult): void {
    const expectedEventPath =
      `${this.filesDirectory}/${FORMAL_RUNTIME_HOST_EVENT_NAME}`;
    if (result.code !== 0 ||
      result.callbackCode !== 0 ||
      result.pid <= 0 ||
      result.generation <= 0 ||
      result.phase !== 'starting' ||
      result.hostEventPath !== expectedEventPath) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_NATIVE_START_REJECTED',
        'starting',
        'The native formal runtime launcher rejected the start request'
      );
    }
  }

  private validateStopResult(result: FormalRuntimeStopResult): void {
    if (!result.accepted ||
      result.code !== 0 ||
      result.generation !== this.activeGeneration ||
      result.phase !== 'stopping') {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_NATIVE_STOP_REJECTED',
        'stopping',
        'The native formal runtime launcher rejected the stop request'
      );
    }
  }

  private async waitForReady(generation: number): Promise<FormalReadyPayload> {
    const deadline = Date.now() + FORMAL_RUNTIME_READY_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const event = this.readHostEvent();
      if (event !== undefined) {
        if (event.kind === 'runtime.ready') {
          const ready = this.parseReadyPayload(event.payload);
          if (ready.generation !== generation ||
            ready.hostname !== '127.0.0.1' ||
            !Number.isInteger(ready.port) ||
            ready.port <= 0 ||
            ready.port > 65535) {
            throw new OpenCodeFormalRuntimeControllerError(
              'FORMAL_RUNTIME_READY_INVALID',
              'starting',
              'The formal runtime readiness event is invalid'
            );
          }
          return ready;
        }
        if (event.kind === 'runtime.fatal') {
          const fatal = this.parseFatalPayload(event.payload);
          throw new OpenCodeFormalRuntimeControllerError(
            this.boundedCode(fatal.code),
            'starting',
            `The formal runtime failed during startup (${this.boundedCode(fatal.category)})`
          );
        }
      }
      const state = formalRuntime.getFormalRuntimeState();
      if (state.activeGeneration !== generation ||
        state.phase === 'failed' ||
        (state.exitObserved && state.lastExitGeneration === generation)) {
        throw new OpenCodeFormalRuntimeControllerError(
          'FORMAL_RUNTIME_EXITED_BEFORE_READY',
          'starting',
          'The formal runtime exited before reporting readiness'
        );
      }
      await this.delay(FORMAL_RUNTIME_POLL_INTERVAL_MS);
    }
    throw new OpenCodeFormalRuntimeControllerError(
      'FORMAL_RUNTIME_READY_TIMEOUT',
      'starting',
      'The formal runtime did not report readiness within the bounded timeout'
    );
  }

  private async waitForStopped(generation: number): Promise<void> {
    const deadline = Date.now() + FORMAL_RUNTIME_STOP_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const state: FormalRuntimeState = formalRuntime.getFormalRuntimeState();
      if (state.activeGeneration === 0 &&
        (state.lastExitGeneration === generation || state.lastExitGeneration === 0)) {
        return;
      }
      await this.delay(FORMAL_RUNTIME_POLL_INTERVAL_MS);
    }
    throw new OpenCodeFormalRuntimeControllerError(
      'FORMAL_RUNTIME_STOP_TIMEOUT',
      'stopping',
      'The formal runtime did not stop within the bounded timeout'
    );
  }

  private async stopFailedStart(): Promise<void> {
    const generation = this.activeGeneration;
    if (generation > 0) {
      try {
        const state = formalRuntime.getFormalRuntimeState();
        if (state.activeGeneration === generation && state.activePid >= 0) {
          const stopped = formalRuntime.stopFormalRuntime(generation);
          if (stopped.accepted && stopped.code === 0) {
            await this.waitForStopped(generation);
          } else if (stopped.code !== FORMAL_RUNTIME_INACTIVE) {
            this.errorCode = 'FORMAL_RUNTIME_FAILED_START_CLEANUP';
          }
        }
      } catch (_) {
        this.errorCode = 'FORMAL_RUNTIME_FAILED_START_CLEANUP';
      }
    }
    this.clearConnection();
  }

  private parseReadyPayload(payload: string): FormalReadyPayload {
    try {
      return JSON.parse(payload) as FormalReadyPayload;
    } catch (_) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_RUNTIME_READY_INVALID',
        'starting',
        'The formal runtime readiness payload is not valid JSON'
      );
    }
  }

  private parseFatalPayload(payload: string): FormalFatalPayload {
    try {
      const fatal = JSON.parse(payload) as FormalFatalPayload;
      if (!Number.isInteger(fatal.generation) ||
        typeof fatal.code !== 'string' ||
        typeof fatal.category !== 'string') {
        throw new Error('invalid');
      }
      return fatal;
    } catch (_) {
      return {
        generation: this.activeGeneration,
        code: 'FORMAL_RUNTIME_START_FAILED',
        category: 'UnknownError'
      };
    }
  }

  private requireApprovedCallback(kind: string): FormalHostCallback {
    switch (kind) {
      case 'runtime.ready':
        return 'runtime.ready';
      case 'runtime.fatal':
        return 'runtime.fatal';
      case 'runtime.stopped':
        return 'runtime.stopped';
      case 'workspace.changed':
        return 'workspace.changed';
      default:
        throw new OpenCodeFormalRuntimeControllerError(
          'FORMAL_HOST_CALLBACK_REJECTED',
          this.phase,
          'The formal runtime emitted an unapproved host callback'
        );
    }
  }

  private requireAbsolutePath(value: string, code: string): string {
    if (value.length === 0 ||
      value.length > FORMAL_RUNTIME_MAX_PATH_BYTES ||
      !value.startsWith('/') ||
      value.includes('\n') ||
      value.includes('\r') ||
      value.includes('/../') ||
      value.includes('/./') ||
      value.endsWith('/..') ||
      value.endsWith('/.')) {
      throw new OpenCodeFormalRuntimeControllerError(
        code,
        this.phase,
        'A formal runtime path is invalid'
      );
    }
    return value;
  }

  private isPathInside(root: string, candidate: string): boolean {
    return candidate === root ||
      candidate.startsWith(root.endsWith('/') ? root : `${root}/`);
  }

  private createCredential(): string {
    const random = cryptoFramework.createRandom().generateRandomSync(32);
    const base64 = new util.Base64Helper().encodeToStringSync(random.data);
    const credential = base64
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '');
    if (credential.length < 43 || credential.length > 128) {
      throw new OpenCodeFormalRuntimeControllerError(
        'FORMAL_CREDENTIAL_GENERATION_FAILED',
        this.phase,
        'The formal runtime credential could not be generated'
      );
    }
    return credential;
  }

  private createBasicAuthorization(credential: string): string {
    const bytes = new util.TextEncoder().encodeInto(`opencode:${credential}`);
    const encoded = new util.Base64Helper().encodeToStringSync(bytes);
    return `Basic ${encoded}`;
  }

  private boundedCode(value: string): string {
    if (value.length === 0 || value.length > 64 ||
      !/^[A-Za-z0-9._-]+$/.test(value)) {
      return 'UnknownError';
    }
    return value;
  }

  private normalizeError(error: Object, fallbackCode: string,
    fallbackPhase: string, fallbackMessage: string):
    OpenCodeFormalRuntimeControllerError {
    if (error instanceof OpenCodeFormalRuntimeControllerError) return error;
    return new OpenCodeFormalRuntimeControllerError(
      fallbackCode, fallbackPhase, fallbackMessage);
  }

  private clearConnection(): void {
    this.activeGeneration = 0;
    this.activePort = 0;
    this.activeCredential = '';
    this.lastHostSequence = 0;
  }

  private delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }
}
