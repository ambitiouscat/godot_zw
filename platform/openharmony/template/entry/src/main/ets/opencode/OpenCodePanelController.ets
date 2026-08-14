import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type {
  DeviceParitySummary,
  InteractiveRuntimeSession,
  RuntimeController
} from './RuntimeController';
import { RuntimeLifecycleError } from './RuntimeLifecycleError';
import {
  OpenCodePanelError
} from './OpenCodePanelContract';
import type {
  OpenCodePanelAsyncFailureProbeResult,
  OpenCodePanelNavigation,
  OpenCodePanelSnapshot,
  OpenCodePanelSnapshotListener
} from './OpenCodePanelContract';
import {
  OPENCODE_HARMONY_CLIENT_SELECTION,
  OPENCODE_HARMONY_PARITY_ENABLED
} from './OpenCodeSpikeBuildConfig';

const DOMAIN = 0x0000;
const MAX_ERROR_CODE_LENGTH = 64;
const MAX_ERROR_SUMMARY_LENGTH = 160;
const HEALTH_POLL_INTERVAL_MS = 2000;
const HEALTH_FAILURE_LIMIT = 3;
const FAILURE_PROBE_TIMEOUT_MS = 14000;
const FAILURE_PROBE_HEARTBEAT_INTERVAL_MS = 16;
const FAILURE_PROBE_MAX_HEARTBEAT_GAP_MS = 1000;
const FAILURE_PROBE_MIN_HEARTBEAT_TICKS = 2;

const PACKAGED_ESM_ASSET = 'opencode_spike/node-capability-fixture.mjs';
const PACKAGED_FETCH_ASSET = 'opencode_spike/node-fetch-harmony.cjs';
const PACKAGED_ARKWEB_ASSET = 'opencode_spike/arkweb-loopback.html';
const PACKAGED_OPENCODE_SERVER_ASSET =
  'opencode_spike/opencode/opencode-harmony-server.mjs';
const PACKAGED_OPENCODE_PARITY_ASSET =
  'opencode_spike/opencode/opencode-harmony-v2-parity.mjs';
const PACKAGED_OPENCODE_CLIENT_ASSET =
  'opencode_spike/opencode/opencode-harmony-client.tar';
const PACKAGED_OPENCODE_SDK_CLIENT_ASSET =
  'opencode_spike/opencode/opencode-harmony-sdk-client.tar';
const PACKAGED_OPENCODE_METADATA_ASSET =
  'opencode_spike/opencode/runtime-assets.json';
const PACKAGED_OPENCODE_CATALOG_ASSET =
  'opencode_spike/opencode/models-dev-api.json';

/**
 * Owns the readiness-gated OpenCode panel session without owning its visual
 * placement. The engine-ui tab can call activate(), then attach the returned
 * authenticated navigation to its final ArkWeb host after the Vue source is
 * available.
 */
export class OpenCodePanelController {
  private readonly context: common.UIAbilityContext;
  private readonly runtimeController: RuntimeController;
  private projectRoot: string;
  private phase: string = 'idle';
  private visible: boolean = false;
  private foreground: boolean = false;
  private assetsPrepared: boolean = false;
  private parityValidated: boolean = false;
  private session?: InteractiveRuntimeSession;
  private activation?: Promise<OpenCodePanelNavigation>;
  private activationVersion: number = 0;
  private destroyed: boolean = false;
  private healthTimer: number = -1;
  private healthProbeActive: boolean = false;
  private consecutiveHealthFailures: number = 0;
  private errorCode: string = 'none';
  private errorSummary: string = '';
  private retryable: boolean = false;
  private failureProbeActive: boolean = false;
  private readonly snapshotListeners: Set<OpenCodePanelSnapshotListener> = new Set();

  constructor(context: common.UIAbilityContext, runtimeController: RuntimeController,
    projectRoot: string) {
    this.context = context;
    this.runtimeController = runtimeController;
    this.projectRoot = projectRoot;
    this.publishState('idle', 'none', '', false);
  }

  getSnapshot(): OpenCodePanelSnapshot {
    return {
      phase: this.phase,
      visible: this.visible,
      ready: this.session !== undefined && this.phase === 'ready',
      assetsPrepared: this.assetsPrepared,
      generation: this.session === undefined ? 0 : this.session.generation,
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
    if (this.session !== undefined || this.activation !== undefined) {
      throw new OpenCodePanelError('PROJECT_CHANGE_WHILE_ACTIVE', this.phase,
        'Close the OpenCode runtime before changing the project root');
    }
    this.projectRoot = projectRoot;
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

  async activate(): Promise<OpenCodePanelNavigation> {
    if (this.destroyed) {
      throw new OpenCodePanelError('PANEL_DESTROYED', 'destroyed',
        'The OpenCode panel controller has already been destroyed', false);
    }
    this.setVisible(true);
    if (this.session !== undefined && this.phase === 'ready') {
      return this.createNavigation(this.session);
    }
    if (this.activation !== undefined) return this.activation;

    const activationVersion = ++this.activationVersion;
    const activation = this.activateInternal(activationVersion);
    this.activation = activation;
    try {
      return await activation;
    } finally {
      if (this.activation === activation) this.activation = undefined;
    }
  }

  async retry(): Promise<OpenCodePanelNavigation> {
    await this.stop();
    return this.activate();
  }

  async runAsyncFailureProbe(): Promise<OpenCodePanelAsyncFailureProbeResult> {
    if (this.failureProbeActive) {
      throw new OpenCodePanelError('PANEL_FAILURE_PROBE_ACTIVE', this.phase,
        'The asynchronous failure probe is already running', false);
    }
    if (this.session === undefined || this.phase !== 'ready') {
      throw new OpenCodePanelError('PANEL_FAILURE_PROBE_NOT_READY', this.phase,
        'The local OpenCode runtime must be ready before the failure probe starts', true);
    }

    this.failureProbeActive = true;
    const startedAt = Date.now();
    let previousTick = startedAt;
    let uiTicks = 0;
    let uiMaxGapMs = 0;
    const heartbeatTimer = setInterval((): void => {
      const current = Date.now();
      uiMaxGapMs = Math.max(uiMaxGapMs, current - previousTick);
      previousTick = current;
      uiTicks += 1;
    }, FAILURE_PROBE_HEARTBEAT_INTERVAL_MS);
    hilog.info(DOMAIN, 'OpenCodePanel',
      'PANEL_ASYNC_FAILURE_PROBE_STARTED version=1');

    try {
      // Stop only the child runtime while retaining the panel session. The
      // normal asynchronous health monitor must observe the unreachable
      // listener and publish the same structured failure used for a real exit.
      await this.runtimeController.shutdownIfRunning();
      await this.waitForFailureProbeResult(startedAt);
      const finishedAt = Date.now();
      uiMaxGapMs = Math.max(uiMaxGapMs, finishedAt - previousTick);
      const durationMs = finishedAt - startedAt;
      if (uiTicks < FAILURE_PROBE_MIN_HEARTBEAT_TICKS ||
        uiMaxGapMs > FAILURE_PROBE_MAX_HEARTBEAT_GAP_MS) {
        throw new OpenCodePanelError('PANEL_UI_HEARTBEAT_STALLED', this.phase,
          'The editor UI heartbeat stalled during the asynchronous runtime failure', true);
      }
      hilog.info(DOMAIN, 'OpenCodePanel',
        'PANEL_ASYNC_FAILURE_PROBE_COMPLETE version=1 code=%{public}s ticks=%{public}d maxGap=%{public}d duration=%{public}d',
        this.errorCode, uiTicks, uiMaxGapMs, durationMs);
      return {
        phase: this.phase,
        errorCode: this.errorCode,
        durationMs,
        uiTicks,
        uiMaxGapMs
      };
    } finally {
      clearInterval(heartbeatTimer);
      this.failureProbeActive = false;
    }
  }

  async stop(): Promise<void> {
    this.stopHealthMonitor();
    this.activationVersion += 1;
    const pendingActivation = this.activation;
    if (pendingActivation !== undefined) {
      try {
        await pendingActivation;
      } catch (_) {
        // The activation path owns its structured failure and runtime cleanup.
      }
    }
    if (this.session === undefined && this.runtimeController.getPhase() === 'idle') {
      this.publishState('idle', 'none', '', false);
      return;
    }
    this.publishState('stopping', 'none', '', false);
    try {
      await this.runtimeController.shutdownIfRunning();
    } finally {
      this.session = undefined;
      this.publishState('idle', 'none', '', false);
    }
  }

  async shutdown(): Promise<void> {
    this.destroyed = true;
    this.setVisible(false);
    await this.stop();
    this.publishState('destroyed', 'none', '', false);
  }

  private async activateInternal(activationVersion: number): Promise<OpenCodePanelNavigation> {
    try {
      const projectRoot = this.requireProjectRoot();
      this.publishState(this.assetsPrepared ? 'starting' : 'preparing-assets',
        'none', '', false);
      if (!this.assetsPrepared) {
        await this.prepareAssets(activationVersion);
        this.assetsPrepared = true;
      }
      this.requireCurrentActivation(activationVersion);

      if (OPENCODE_HARMONY_PARITY_ENABLED && !this.parityValidated) {
        this.publishState('validating-parity', 'none', '', false);
        const parity: DeviceParitySummary =
          await this.runtimeController.runDeviceParityValidation();
        this.requireCurrentActivation(activationVersion);
        this.parityValidated = true;
        hilog.info(DOMAIN, 'OpenCodeParity',
          'DEVICE_V2_PARITY_RESULT pass=%{public}s cases=%{public}d sha256=%{public}s',
          String(parity.allIdle && parity.matchesHostV2), parity.caseCount, parity.reportSha256);
      }

      this.publishState('starting', 'none', '', false);
      const session = await this.runtimeController.startInteractiveRuntime(projectRoot);
      this.requireCurrentActivation(activationVersion);
      const healthStatus =
        await this.runtimeController.probeHealthStatus(session.port, session.credential);
      if (healthStatus !== 200) {
        throw new OpenCodePanelError('READY_HEALTH_REJECTED', 'starting',
          `OpenCode readiness health returned HTTP ${healthStatus}`);
      }
      this.requireCurrentActivation(activationVersion);
      this.session = session;
      this.publishState('ready', 'none', '', false);
      this.startHealthMonitor();
      hilog.info(DOMAIN, 'OpenCodePanel',
        'PANEL_READY generation=%{public}d foreground=%{public}s',
        session.generation, String(this.foreground));
      return this.createNavigation(session);
    } catch (error) {
      this.stopHealthMonitor();
      this.session = undefined;
      await this.runtimeController.shutdownIfRunning();
      const panelError = this.normalizeError(error);
      this.publishState('failed', panelError.code,
        this.boundedSummary(panelError.message), panelError.retryable);
      hilog.error(DOMAIN, 'OpenCodePanel',
        'PANEL_START_FAILED code=%{public}s phase=%{public}s retryable=%{public}s summary=%{public}s',
        panelError.code, panelError.phase, String(panelError.retryable),
        this.boundedSummary(panelError.message));
      throw panelError;
    }
  }

  private async prepareAssets(activationVersion: number): Promise<void> {
    try {
      const resourceManager = this.context.resourceManager;
      await this.runtimeController.preparePackagedAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_ESM_ASSET));
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareFetchCompatibilityAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_FETCH_ASSET));
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareArkWebAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_ARKWEB_ASSET));
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareOpenCodeServerAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_OPENCODE_SERVER_ASSET));
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareOpenCodeParityAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_OPENCODE_PARITY_ASSET));
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareOpenCodeClientArchiveAsync(
        await resourceManager.getRawFileContent(PACKAGED_OPENCODE_CLIENT_ASSET), 'upstream');
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareOpenCodeClientArchiveAsync(
        await resourceManager.getRawFileContent(PACKAGED_OPENCODE_SDK_CLIENT_ASSET), 'sdk-composed');
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareOpenCodeMetadataAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_OPENCODE_METADATA_ASSET));
      this.requireCurrentActivation(activationVersion);
      await this.runtimeController.prepareOpenCodeCatalogAssetAsync(
        await resourceManager.getRawFileContent(PACKAGED_OPENCODE_CATALOG_ASSET));
      this.requireCurrentActivation(activationVersion);
    } catch (error) {
      if (error instanceof OpenCodePanelError) throw error;
      if (error instanceof RuntimeLifecycleError) throw error;
      throw new OpenCodePanelError('PANEL_ASSETS_UNAVAILABLE', 'preparing-assets',
        'The OpenCode spike resources are missing or unreadable');
    }
  }

  private requireProjectRoot(): string {
    if (!this.projectRoot.startsWith('/') || this.projectRoot.length > 4096 ||
      this.projectRoot.includes('\0') || this.projectRoot.includes('\r') ||
      this.projectRoot.includes('\n')) {
      throw new OpenCodePanelError('PROJECT_ROOT_UNAVAILABLE', 'idle',
        'The editor did not provide a supported local project root', false);
    }
    return this.projectRoot;
  }

  private requireCurrentActivation(activationVersion: number): void {
    if (this.destroyed || activationVersion !== this.activationVersion) {
      throw new OpenCodePanelError('PANEL_ACTIVATION_CANCELLED', this.phase,
        'The OpenCode panel activation was cancelled', false);
    }
  }

  private createNavigation(session: InteractiveRuntimeSession): OpenCodePanelNavigation {
    const clientRoot = OPENCODE_HARMONY_CLIENT_SELECTION === 'sdk-composed' ?
      'sdk-client' : 'client';
    return {
      url: `http://127.0.0.1:${session.port}/${clientRoot}/?harmony_mode=interactive`,
      headers: [{
        headerKey: 'Authorization',
        headerValue: `Bearer ${session.credential}`
      }],
      generation: session.generation
    };
  }

  private startHealthMonitor(): void {
    this.stopHealthMonitor();
    this.consecutiveHealthFailures = 0;
    this.healthTimer = setInterval(() => {
      this.probeReadySession();
    }, HEALTH_POLL_INTERVAL_MS);
  }

  private stopHealthMonitor(): void {
    if (this.healthTimer >= 0) {
      clearInterval(this.healthTimer);
      this.healthTimer = -1;
    }
    this.healthProbeActive = false;
    this.consecutiveHealthFailures = 0;
  }

  private async probeReadySession(): Promise<void> {
    if (this.healthProbeActive || this.session === undefined || this.phase !== 'ready') return;
    this.healthProbeActive = true;
    try {
      let healthy = false;
      try {
        const status = await this.runtimeController.probeHealthStatus(
          this.session.port, this.session.credential);
        healthy = status === 200;
      } catch (_) {
        // A refused or closed loopback listener is a health failure, not an
        // unhandled Promise rejection on the editor UI event loop.
        healthy = false;
      }
      if (healthy) {
        this.consecutiveHealthFailures = 0;
        return;
      }
      this.consecutiveHealthFailures += 1;
      if (this.consecutiveHealthFailures < HEALTH_FAILURE_LIMIT) return;

      this.stopHealthMonitor();
      this.session = undefined;
      try {
        await this.runtimeController.shutdownIfRunning();
      } catch (_) {
        // Failure publication must remain bounded even if cleanup also fails.
      }
      this.publishState('failed', 'RUNTIME_HEALTH_LOST',
        'The local OpenCode runtime is no longer available', true);
      hilog.error(DOMAIN, 'OpenCodePanel',
        'PANEL_RUNTIME_LOST code=%{public}s', 'RUNTIME_HEALTH_LOST');
    } finally {
      this.healthProbeActive = false;
    }
  }

  private waitForFailureProbeResult(startedAt: number): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const check = (): void => {
        if (this.phase === 'failed' && this.errorCode === 'RUNTIME_HEALTH_LOST') {
          resolve();
          return;
        }
        if (Date.now() - startedAt >= FAILURE_PROBE_TIMEOUT_MS) {
          reject(new OpenCodePanelError('PANEL_FAILURE_PROBE_TIMEOUT', this.phase,
            'The asynchronous runtime failure was not detected in time', true));
          return;
        }
        setTimeout(check, 50);
      };
      check();
    });
  }

  private normalizeError(error: Object): OpenCodePanelError {
    if (error instanceof OpenCodePanelError) return error;
    if (error instanceof RuntimeLifecycleError) {
      return new OpenCodePanelError(
        this.boundedCode(error.code),
        error.phase,
        this.summaryForRuntimeCode(error.code)
      );
    }
    if (error instanceof Error) {
      return new OpenCodePanelError('PANEL_START_FAILED', this.phase,
        'The local OpenCode runtime could not be started');
    }
    return new OpenCodePanelError('PANEL_START_UNKNOWN', this.phase,
      'The local OpenCode runtime failed with an unknown error');
  }

  private summaryForRuntimeCode(code: string): string {
    if (code.includes('ASSET')) return 'A packaged OpenCode runtime asset could not be prepared';
    if (code.includes('CREDENTIAL')) return 'The runtime did not publish a valid session credential';
    if (code.includes('READY') || code.includes('HEALTH')) {
      return 'The local OpenCode runtime did not become ready in time';
    }
    if (code.includes('START') || code.includes('CALLBACK')) {
      return 'HarmonyOS could not start the local OpenCode child runtime';
    }
    return 'The local OpenCode runtime could not be started';
  }

  private boundedCode(code: string): string {
    const normalized = code.toUpperCase().replace(/[^A-Z0-9_]/g, '_');
    if (normalized.length === 0) return 'PANEL_START_FAILED';
    return normalized.substring(0, MAX_ERROR_CODE_LENGTH);
  }

  private boundedSummary(summary: string): string {
    const singleLine = summary.replace(/[\r\n\t]/g, ' ').trim();
    return singleLine.substring(0, MAX_ERROR_SUMMARY_LENGTH);
  }

  private publishState(phase: string, errorCode: string, errorSummary: string,
    retryable: boolean): void {
    this.phase = phase;
    this.errorCode = this.boundedCode(errorCode === 'none' ? 'none' : errorCode);
    if (errorCode === 'none') this.errorCode = 'none';
    this.errorSummary = this.boundedSummary(errorSummary);
    this.retryable = retryable;
    AppStorage.setOrCreate('openCodePanelPhase', phase);
    AppStorage.setOrCreate('openCodePanelVisible', this.visible);
    AppStorage.setOrCreate('openCodePanelReady',
      this.session !== undefined && phase === 'ready');
    AppStorage.setOrCreate('openCodePanelErrorCode', this.errorCode);
    AppStorage.setOrCreate('openCodePanelErrorSummary', this.errorSummary);
    AppStorage.setOrCreate('openCodePanelRetryable', retryable);
    this.publishSnapshot();
  }

  private publishSnapshot(): void {
    const snapshot = this.getSnapshot();
    this.snapshotListeners.forEach((listener: OpenCodePanelSnapshotListener): void => {
      try {
        listener(snapshot);
      } catch (_) {
        // A status observer cannot interrupt panel lifecycle publication.
      }
    });
  }
}
