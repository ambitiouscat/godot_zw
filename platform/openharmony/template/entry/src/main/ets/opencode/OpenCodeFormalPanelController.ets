import {
  OpenCodePanelError
} from './OpenCodePanelContract';
import type {
  OpenCodePanelAsyncFailureProbeResult,
  OpenCodePanelNavigation,
  OpenCodePanelSnapshot,
  OpenCodePanelSnapshotListener,
  OpenCodePanelSessionController
} from './OpenCodePanelContract';
import {
  OpenCodeFormalRuntimeController,
  OpenCodeFormalRuntimeControllerError
} from './OpenCodeFormalRuntimeController';
import {
  OpenCodeFormalAssetInstaller,
  OpenCodeFormalAssetInstallerError
} from './OpenCodeFormalAssetInstaller';
import {
  OpenCodeSkillsInstaller,
  OpenCodeSkillsInstallerError
} from './OpenCodeSkillsInstaller';
import type {
  OpenCodeFormalHostEvent,
  OpenCodeFormalRuntimeConnection
} from './OpenCodeFormalRuntimeController';

const MAX_ERROR_CODE_LENGTH = 64;
const FORMAL_RUNTIME_INSTALL_ROOT = 'opencode-formal/install/v1';
const FORMAL_RUNTIME_ENTRY = 'runtime/opencode-harmony-runtime.mjs';

interface OpenCodeFormalRuntimeFatalDocument {
  generation?: number;
  code?: string;
  category?: string;
}

interface OpenCodeFormalRuntimeGenerationDocument {
  generation?: number;
}

/**
 * ArkWeb-facing lifecycle for the formal upstream client.
 *
 * The controller only starts/stops a formal runtime generation and returns an
 * authenticated loopback navigation. OpenCode routes and business semantics
 * remain inside the generated upstream runtime and client.
 */
export class OpenCodeFormalPanelController implements OpenCodePanelSessionController {
  private readonly runtimeController: OpenCodeFormalRuntimeController;
  private readonly assetInstaller: OpenCodeFormalAssetInstaller;
  private readonly skillsInstaller?: OpenCodeSkillsInstaller;
  private readonly runtimeEntryPath: string;
  private phase: string = 'idle';
  private visible: boolean = false;
  private foreground: boolean = false;
  private assetsPrepared: boolean = false;
  private connection?: OpenCodeFormalRuntimeConnection;
  private activation?: Promise<OpenCodePanelNavigation>;
  private activationVersion: number = 0;
  private destroyed: boolean = false;
  private errorCode: string = 'none';
  private errorSummary: string = '';
  private retryable: boolean = false;
  private readonly snapshotListeners: Set<OpenCodePanelSnapshotListener> =
    new Set();

  constructor(filesDirectory: string,
    runtimeController: OpenCodeFormalRuntimeController,
    assetInstaller: OpenCodeFormalAssetInstaller,
    skillsInstaller?: OpenCodeSkillsInstaller) {
    this.runtimeController = runtimeController;
    this.assetInstaller = assetInstaller;
    this.skillsInstaller = skillsInstaller;
    this.runtimeEntryPath =
      `${filesDirectory}/${FORMAL_RUNTIME_INSTALL_ROOT}/${FORMAL_RUNTIME_ENTRY}`;
    this.publishState('idle', 'none', '', false);
  }

  getSnapshot(): OpenCodePanelSnapshot {
    return {
      phase: this.phase,
      visible: this.visible,
      ready: this.connection !== undefined && this.phase === 'ready',
      assetsPrepared: this.assetsPrepared,
      generation: this.connection?.generation ?? 0,
      errorCode: this.errorCode,
      errorSummary: this.errorSummary,
      retryable: this.retryable
    };
  }

  subscribe(listener: OpenCodePanelSnapshotListener): () => void {
    this.snapshotListeners.add(listener);
    listener(this.getSnapshot());
    return (): void => {
      this.snapshotListeners.delete(listener);
    };
  }

  setProjectRoot(projectRoot: string): void {
    if (this.connection !== undefined || this.activation !== undefined) {
      throw new OpenCodePanelError(
        'FORMAL_PROJECT_CHANGE_WHILE_ACTIVE',
        this.phase,
        'Close the OpenCode runtime before changing the project root'
      );
    }
    this.runtimeController.updateAuthorizedProjectRoot(projectRoot);
  }

  setVisible(visible: boolean): void {
    if (this.visible === visible) return;
    this.visible = visible;
    AppStorage.setOrCreate('openCodePanelVisible', visible);
    this.publishSnapshot();
  }

  onForeground(): void {
    this.foreground = true;
  }

  onBackground(): void {
    this.foreground = false;
  }

  handleRuntimeHostEvent(event: OpenCodeFormalHostEvent): void {
    if (this.connection === undefined ||
      event.generation !== this.connection.generation) {
      return;
    }
    if (event.kind === 'runtime.fatal') {
      const code = this.parseRuntimeFatalCode(event.payload);
      this.connection = undefined;
      this.publishState('failed', code, this.summaryForCode(code), true);
      return;
    }
    if (event.kind === 'runtime.stopped') {
      if (!this.matchesRuntimeGeneration(event.payload, event.generation)) return;
      this.connection = undefined;
      this.publishState('idle', 'none', '', false);
    }
  }

  async activate(): Promise<OpenCodePanelNavigation> {
    if (this.destroyed) {
      throw new OpenCodePanelError(
        'PANEL_DESTROYED',
        'destroyed',
        'The OpenCode panel controller has already been destroyed',
        false
      );
    }
    this.setVisible(true);
    if (this.connection !== undefined && this.phase === 'ready') {
      return this.createNavigation(this.connection);
    }
    if (this.activation !== undefined) return this.activation;

    const activationVersion = ++this.activationVersion;
    const activation = this.start(activationVersion);
    this.activation = activation;
    try {
      return await activation;
    } finally {
      if (this.activation === activation) this.activation = undefined;
    }
  }

  async retry(): Promise<OpenCodePanelNavigation> {
    if (this.destroyed) {
      throw new OpenCodePanelError(
        'PANEL_DESTROYED',
        'destroyed',
        'The OpenCode panel controller has already been destroyed',
        false
      );
    }
    await this.stop();
    return this.activate();
  }

  async runAsyncFailureProbe():
    Promise<OpenCodePanelAsyncFailureProbeResult> {
    throw new OpenCodePanelError(
      'FORMAL_FAILURE_PROBE_UNAVAILABLE',
      this.phase,
      'The rollback-runtime failure probe is not available in formal mode',
      false
    );
  }

  async stop(): Promise<void> {
    ++this.activationVersion;
    this.activation = undefined;
    this.setVisible(false);
    this.publishState('stopping', 'none', '', false);
    try {
      await this.runtimeController.shutdownIfRunning();
      this.connection = undefined;
      this.publishState('idle', 'none', '', false);
    } catch (error) {
      const normalized = this.normalizeError(error);
      this.connection = undefined;
      this.publishState('failed', normalized.code,
        this.summaryForCode(normalized.code), normalized.retryable);
      throw normalized;
    }
  }

  async shutdown(): Promise<void> {
    if (this.destroyed) return;
    this.destroyed = true;
    try {
      await this.stop();
    } finally {
      this.snapshotListeners.clear();
      this.publishState('destroyed', 'none', '', false);
    }
  }

  private async start(activationVersion: number):
    Promise<OpenCodePanelNavigation> {
    this.publishState('preparing-assets', 'none', '', false);
    try {
      await this.assetInstaller.prepare();
      if (this.skillsInstaller) {
        await this.skillsInstaller.prepare();
      }
      this.requireCurrentActivation(activationVersion);
      this.assetsPrepared = true;
      this.publishState('starting', 'none', '', false);
      const connection = await this.runtimeController.start(
        this.runtimeEntryPath);
      this.requireCurrentActivation(activationVersion);
      this.connection = connection;
      this.publishState('ready', 'none', '', false);
      return this.createNavigation(connection);
    } catch (error) {
      const normalized = this.normalizeError(error);
      this.connection = undefined;
      if (activationVersion === this.activationVersion && !this.destroyed) {
        this.publishState('failed', normalized.code,
          this.summaryForCode(normalized.code), normalized.retryable);
      }
      throw normalized;
    }
  }

  private requireCurrentActivation(activationVersion: number): void {
    if (this.destroyed || activationVersion !== this.activationVersion) {
      throw new OpenCodePanelError(
        'PANEL_ACTIVATION_CANCELLED',
        this.phase,
        'The OpenCode panel activation was cancelled',
        false
      );
    }
  }

  private createNavigation(
    connection: OpenCodeFormalRuntimeConnection): OpenCodePanelNavigation {
    const prefix = 'Basic ';
    if (!connection.authorization.startsWith(prefix) ||
      connection.authorization.length <= prefix.length) {
      throw new OpenCodePanelError(
        'FORMAL_PANEL_AUTH_INVALID',
        this.phase,
        'The formal runtime did not provide a valid ArkWeb credential',
        false
      );
    }
    const authToken = connection.authorization.substring(prefix.length);
    return {
      url: `${connection.origin}/?auth_token=${encodeURIComponent(authToken)}` +
        `&harmony_panel=1&harmony_generation=${connection.generation}`,
      headers: [{
        headerKey: 'Authorization',
        headerValue: connection.authorization
      }],
      generation: connection.generation
    };
  }

  private normalizeError(error: Object): OpenCodePanelError {
    if (error instanceof OpenCodePanelError) return error;
    if (error instanceof OpenCodeFormalAssetInstallerError) {
      const code = this.boundedCode(error.code);
      return new OpenCodePanelError(code, this.phase,
        this.summaryForCode(code), this.isRetryable(code));
    }
    if (error instanceof OpenCodeSkillsInstallerError) {
      const code = this.boundedCode(error.code);
      return new OpenCodePanelError(code, this.phase,
        this.summaryForCode(code), this.isRetryable(code));
    }
    if (error instanceof OpenCodeFormalRuntimeControllerError) {
      const code = this.boundedCode(error.code);
      return new OpenCodePanelError(code, error.phase,
        this.summaryForCode(code), this.isRetryable(code));
    }
    return new OpenCodePanelError(
      'FORMAL_PANEL_START_FAILED',
      this.phase,
      'The formal upstream OpenCode runtime could not be started',
      true
    );
  }

  private parseRuntimeFatalCode(payload: string): string {
    try {
      const document = JSON.parse(payload) as OpenCodeFormalRuntimeFatalDocument;
      if (document.generation !== this.connection?.generation ||
        typeof document.code !== 'string' ||
        typeof document.category !== 'string') {
        return 'FORMAL_RUNTIME_FATAL_INVALID';
      }
      return this.boundedCode(document.code);
    } catch (_) {
      return 'FORMAL_RUNTIME_FATAL_INVALID';
    }
  }

  private matchesRuntimeGeneration(payload: string, generation: number): boolean {
    try {
      const document =
        JSON.parse(payload) as OpenCodeFormalRuntimeGenerationDocument;
      return document.generation === generation;
    } catch (_) {
      return false;
    }
  }

  private isRetryable(code: string): boolean {
    return code !== 'FORMAL_PROJECT_ROOT_REQUIRED' &&
      code !== 'FORMAL_RUNTIME_ENTRY_OUTSIDE_FILES' &&
      code !== 'FORMAL_RUNTIME_ENTRY_INVALID' &&
      code !== 'FORMAL_NATIVE_CONTRACT_INVALID' &&
      code !== 'FORMAL_PANEL_AUTH_INVALID' &&
      code !== 'PANEL_ACTIVATION_CANCELLED';
  }

  private summaryForCode(code: string): string {
    if (code.includes('PROJECT_ROOT')) {
      return 'The editor did not provide an authorized project root';
    }
    if (code.includes('ENTRY')) {
      return 'The packaged formal runtime entry is unavailable';
    }
    if (code.includes('ASSET')) {
      return 'The packaged formal OpenCode resources are unavailable';
    }
    if (code.includes('CONTRACT')) {
      return 'The packaged formal runtime contract is incompatible';
    }
    if (code.includes('READY') || code.includes('TIMEOUT')) {
      return 'The formal upstream runtime did not become ready in time';
    }
    if (code.includes('AUTH')) {
      return 'The formal runtime did not provide valid ArkWeb authentication';
    }
    if (code.includes('STOP')) {
      return 'The formal upstream runtime could not be stopped cleanly';
    }
    return 'The formal upstream OpenCode runtime could not be started';
  }

  private boundedCode(code: string): string {
    const normalized = code.toUpperCase().replace(/[^A-Z0-9_]/g, '_');
    if (normalized.length === 0) return 'FORMAL_PANEL_START_FAILED';
    return normalized.substring(0, MAX_ERROR_CODE_LENGTH);
  }

  private publishState(phase: string, errorCode: string,
    errorSummary: string, retryable: boolean): void {
    this.phase = phase;
    this.errorCode = errorCode === 'none' ? 'none' :
      this.boundedCode(errorCode);
    this.errorSummary = errorSummary;
    this.retryable = retryable;
    AppStorage.setOrCreate('openCodePanelPhase', phase);
    AppStorage.setOrCreate('openCodePanelVisible', this.visible);
    AppStorage.setOrCreate('openCodePanelReady',
      this.connection !== undefined && phase === 'ready');
    AppStorage.setOrCreate('openCodePanelErrorCode', this.errorCode);
    AppStorage.setOrCreate('openCodePanelErrorSummary', this.errorSummary);
    AppStorage.setOrCreate('openCodePanelRetryable', retryable);
    this.publishSnapshot();
  }

  private publishSnapshot(): void {
    const snapshot = this.getSnapshot();
    this.snapshotListeners.forEach(
      (listener: OpenCodePanelSnapshotListener): void => {
        try {
          listener(snapshot);
        } catch (_) {
          // A status observer cannot interrupt panel lifecycle publication.
        }
      });
  }
}
