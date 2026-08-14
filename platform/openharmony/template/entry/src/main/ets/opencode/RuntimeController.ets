import { http } from '@kit.NetworkKit';
import nativeSpike, {
  NativeChildProcessState,
  NativeChildStartResult
} from 'libopencode_runtime.so';
import {
  OpenCodeAuthorizedPatchContractError,
  parseOpenCodeAuthorizedAcceptance,
  parseOpenCodeAuthorizedError,
  parseOpenCodeAuthorizedFile,
  parseOpenCodeAuthorizedProposal,
  parseOpenCodeAuthorizedRejection,
  prepareOpenCodeAuthorizedPatch,
  requireOpenCodeAuthorizedPath,
  requireOpenCodeAuthorizedProposalId
} from './OpenCodeAuthorizedPatch';
import type {
  OpenCodeAuthorizedPatchAcceptance,
  OpenCodeAuthorizedPatchProposal,
  OpenCodeAuthorizedPatchRejection
} from './OpenCodeAuthorizedPatch';
import { RuntimeLifecycleError } from './RuntimeLifecycleError';

export { RuntimeLifecycleError } from './RuntimeLifecycleError';

const RUNTIME_ASSET_CHUNK_BYTES = 1024 * 1024;

export interface RuntimeEnvironmentFingerprint {
  nodeVersion: string;
  platform: string;
  arch: string;
  compileSdkVersion: string;
  compileSdkApi: number;
  targetApi: number;
  deviceApi: number;
}

export interface StructuredDeviceTestResult {
  name: string;
  status: string;
  expected: string;
  actual: string;
  durationMs: number;
  timeoutMs: number;
  diagnostic: string;
  environment: RuntimeEnvironmentFingerprint;
}

export interface RuntimeResourceMetrics {
  rssStartBytes: number;
  heapUsedStartBytes: number;
  activePeakRssBytes: number;
  activePeakHeapUsedBytes: number;
  idleRssBytes: number;
  idleHeapUsedBytes: number;
}

export interface DeviceParityReport {
  schemaVersion: number;
  suite: string;
  caseCount: number;
  allIdle: boolean;
  reportSha256: string;
  runnerSha256: string;
  expectedReportSha256: string;
  matchesHostV2: boolean;
  failedCase?: string;
  failure?: string;
}

export interface DeviceParitySummary extends DeviceParityReport {
  generation: number;
  readyMs: number;
  environment: RuntimeEnvironmentFingerprint;
}

interface RuntimeStateDocument {
  protocolVersion: number;
  phase: string;
  version: string;
  platform: string;
  arch: string;
  sqlite: string;
  timer: string;
  http: string;
  port: number;
  credential?: string;
  healthChecks: number;
  readyMs?: number;
  durationMs?: number;
  reason?: string;
  error?: string;
  recoveryCommitted?: boolean;
  environment?: RuntimeEnvironmentFingerprint;
  tests?: StructuredDeviceTestResult[];
  processBoundary?: ProcessBoundaryDocument;
  resourceMetrics?: RuntimeResourceMetrics;
  parity?: DeviceParityReport;
  projectInterruptionPrepared?: boolean;
}

interface ProcessBoundaryDocument {
  method: string;
  outcome: string;
  durationMs: number;
}

export interface LifecycleCycleSummary {
  cycle: number;
  generation: number;
  readyMs: number;
  controllerReadyMs: number;
  durationMs: number;
  healthChecks: number;
  exitSignal: number;
  shutdownReason: string;
  postExitHealthRejected: boolean;
  environment: RuntimeEnvironmentFingerprint;
  tests: StructuredDeviceTestResult[];
  resourceMetrics: RuntimeResourceMetrics;
}

export interface LifecycleValidationSummary {
  protocolVersion: number;
  cycles: LifecycleCycleSummary[];
  restartPass: boolean;
  gracefulStopPass: boolean;
  structuredRunnerPass: boolean;
  credentialRotationPass: boolean;
  sqliteRecovery: SqliteRecoverySummary;
  processBoundary: ProcessBoundarySummary;
}

export interface SqliteRecoverySummary {
  commitObserved: boolean;
  forcedExitObserved: boolean;
  forcedExitSignal: number;
  recoveryPass: boolean;
  recoveryDurationMs: number;
}

export interface ProcessBoundaryResult {
  method: string;
  outcome: string;
  exitSignal: number;
  structuredOutcome: boolean;
}

export interface ProcessBoundarySummary {
  results: ProcessBoundaryResult[];
  allRecorded: boolean;
}

export interface AuthorizedProjectValidationSummary {
  protocolVersion: number;
  tests: StructuredDeviceTestResult[];
  allPassed: boolean;
  forcedExitObserved: boolean;
  forcedExitSignal: number;
  recoveryPass: boolean;
}

export interface InteractiveRuntimeSession {
  port: number;
  credential: string;
  generation: number;
}

export interface ProcessAuditCheckpoint {
  pass: boolean;
  openCodeAttempts: number;
  runtimeAttempts: number;
}

export class RuntimeController {
  private readonly filesDirectory: string;
  private readonly compileSdkVersion: string;
  private readonly deviceApiVersion: number;
  private readonly compileSdkApiVersion: number;
  private readonly targetApiVersion: number;
  private phase: string = 'idle';
  private currentStart?: NativeChildStartResult;
  private currentPort: number = 0;
  private currentCredential: string = '';
  private previousCredential: string = '';

  constructor(filesDirectory: string, compileSdkVersion: string, deviceApiVersion: number,
    compileSdkApiVersion: number, targetApiVersion: number) {
    this.filesDirectory = filesDirectory;
    this.compileSdkVersion = compileSdkVersion;
    this.deviceApiVersion = deviceApiVersion;
    this.compileSdkApiVersion = compileSdkApiVersion;
    this.targetApiVersion = targetApiVersion;
  }

  getPhase(): string {
    return this.phase;
  }

  preparePackagedAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/node-capability-fixture.mjs`;
    this.writePackagedAssetInChunks(destination, content, 'PACKAGED_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged ESM fixture');
  }

  prepareFetchCompatibilityAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/node-fetch-harmony.cjs`;
    this.writePackagedAssetInChunks(destination, content, 'FETCH_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged non-Wasm fetch bundle');
  }

  prepareArkWebAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/arkweb-loopback.html`;
    this.writePackagedAssetInChunks(destination, content, 'ARKWEB_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged ArkWeb loopback page');
  }

  prepareOpenCodeServerAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/opencode-harmony-server.mjs`;
    this.writePackagedAssetInChunks(destination, content, 'OPENCODE_SERVER_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode Harmony server');
  }

  prepareOpenCodeParityAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/opencode-harmony-v2-parity.mjs`;
    this.writePackagedAssetInChunks(destination, content, 'OPENCODE_PARITY_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode V2 parity runner');
  }

  prepareOpenCodeClientArchive(content: Uint8Array, selection: string = 'upstream'): void {
    const destination = this.openCodeClientArchiveDestination(selection);
    this.writePackagedAssetInChunks(destination, content, 'OPENCODE_CLIENT_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode client archive');
  }

  prepareOpenCodeMetadataAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/opencode-runtime-assets.json`;
    this.writePackagedAssetInChunks(destination, content, 'OPENCODE_METADATA_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode runtime metadata');
  }

  prepareOpenCodeCatalogAsset(content: Uint8Array): void {
    const destination = `${this.filesDirectory}/models-dev-api.json`;
    this.writePackagedAssetInChunks(destination, content, 'OPENCODE_CATALOG_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode model catalog');
  }

  async preparePackagedAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/node-capability-fixture.mjs`;
    await this.writePackagedAssetInChunksAsync(destination, content, 'PACKAGED_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged ESM fixture');
  }

  async prepareFetchCompatibilityAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/node-fetch-harmony.cjs`;
    await this.writePackagedAssetInChunksAsync(destination, content, 'FETCH_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged non-Wasm fetch bundle');
  }

  async prepareArkWebAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/arkweb-loopback.html`;
    await this.writePackagedAssetInChunksAsync(destination, content, 'ARKWEB_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged ArkWeb loopback page');
  }

  async prepareOpenCodeServerAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/opencode-harmony-server.mjs`;
    await this.writePackagedAssetInChunksAsync(destination, content,
      'OPENCODE_SERVER_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode Harmony server');
  }

  async prepareOpenCodeParityAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/opencode-harmony-v2-parity.mjs`;
    await this.writePackagedAssetInChunksAsync(destination, content,
      'OPENCODE_PARITY_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode V2 parity runner');
  }

  async prepareOpenCodeClientArchiveAsync(content: Uint8Array,
    selection: string = 'upstream'): Promise<void> {
    const destination = this.openCodeClientArchiveDestination(selection);
    await this.writePackagedAssetInChunksAsync(destination, content,
      'OPENCODE_CLIENT_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode client archive');
  }

  private openCodeClientArchiveDestination(selection: string): string {
    if (selection === 'upstream') {
      return `${this.filesDirectory}/opencode-harmony-client.tar`;
    }
    if (selection === 'sdk-composed') {
      return `${this.filesDirectory}/opencode-harmony-sdk-client.tar`;
    }
    throw new RuntimeLifecycleError('OPENCODE_CLIENT_SELECTION_INVALID', this.phase,
      'OpenCode client selection must be upstream or sdk-composed');
  }

  async prepareOpenCodeMetadataAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/opencode-runtime-assets.json`;
    await this.writePackagedAssetInChunksAsync(destination, content,
      'OPENCODE_METADATA_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode runtime metadata');
  }

  async prepareOpenCodeCatalogAssetAsync(content: Uint8Array): Promise<void> {
    const destination = `${this.filesDirectory}/models-dev-api.json`;
    await this.writePackagedAssetInChunksAsync(destination, content,
      'OPENCODE_CATALOG_ASSET_WRITE_FAILED',
      'Native bridge rejected the packaged OpenCode model catalog');
  }

  private writePackagedAssetInChunks(destination: string, content: Uint8Array,
    errorCode: string, diagnostic: string): void {
    if (content.byteLength === 0) {
      throw new RuntimeLifecycleError(errorCode, this.phase, `${diagnostic}: asset is empty`);
    }
    try {
      for (let offset = 0; offset < content.byteLength; offset += RUNTIME_ASSET_CHUNK_BYTES) {
        const chunk = content.subarray(offset,
          Math.min(offset + RUNTIME_ASSET_CHUNK_BYTES, content.byteLength));
        if (nativeSpike.writeRuntimeAsset(destination, chunk, offset > 0)) continue;
        throw new RuntimeLifecycleError(errorCode, this.phase,
          `${diagnostic}: native bridge returned false`);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) throw error;
      const errorType = error instanceof Error ? error.name : 'unknown';
      throw new RuntimeLifecycleError(errorCode, this.phase,
        `${diagnostic}: native bridge threw ${errorType}`);
    }
  }

  private async writePackagedAssetInChunksAsync(destination: string, content: Uint8Array,
    errorCode: string, diagnostic: string): Promise<void> {
    if (content.byteLength === 0) {
      throw new RuntimeLifecycleError(errorCode, this.phase, `${diagnostic}: asset is empty`);
    }
    try {
      for (let offset = 0; offset < content.byteLength; offset += RUNTIME_ASSET_CHUNK_BYTES) {
        const chunk = content.subarray(offset,
          Math.min(offset + RUNTIME_ASSET_CHUNK_BYTES, content.byteLength));
        if (!nativeSpike.writeRuntimeAsset(destination, chunk, offset > 0)) {
          throw new RuntimeLifecycleError(errorCode, this.phase,
            `${diagnostic}: native bridge returned false`);
        }
        await this.delay(0);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) throw error;
      const errorType = error instanceof Error ? error.name : 'unknown';
      throw new RuntimeLifecycleError(errorCode, this.phase,
        `${diagnostic}: native bridge threw ${errorType}`);
    }
  }

  async startInteractiveRuntime(projectRoot: string): Promise<InteractiveRuntimeSession> {
    if (this.phase !== 'idle') {
      throw new RuntimeLifecycleError('INVALID_STATE', this.phase,
        'Runtime must be idle before starting an interactive ArkWeb session');
    }
    this.phase = 'arkweb-starting';
    try {
      const start = this.startRuntime(projectRoot, 'interactive');
      this.currentStart = start;
      const ready = await this.waitForReady(start, 8000);
      if (ready.credential === undefined) {
        throw new RuntimeLifecycleError('ARKWEB_CREDENTIAL_MISSING', this.phase,
          'Interactive runtime did not publish its connection credential');
      }
      this.currentPort = ready.port;
      this.phase = 'arkweb-ready';
      await this.requestInteractiveMode(ready.port);
      return { port: ready.port, credential: ready.credential, generation: start.generation };
    } catch (error) {
      this.phase = 'error';
      await this.shutdownIfRunning();
      if (error instanceof Error) throw error;
      throw new RuntimeLifecycleError('ARKWEB_START_UNKNOWN', this.phase,
        'Interactive ArkWeb runtime failed with an unknown error');
    }
  }

  async stopInteractiveRuntime(): Promise<void> {
    if (this.currentStart === undefined || this.currentPort <= 0) {
      this.phase = 'idle';
      return;
    }
    const start = this.currentStart;
    const port = this.currentPort;
    this.phase = 'arkweb-stopping';
    await this.requestStop(port);
    await this.waitForExit(start, 5000);
    if (!(await this.expectHealthFailure(port))) {
      throw new RuntimeLifecycleError('ARKWEB_STALE_LISTENER', 'exited',
        'ArkWeb runtime listener remained reachable after stop');
    }
    this.currentPort = 0;
    this.currentCredential = '';
    this.currentStart = undefined;
    this.phase = 'idle';
  }

  async probeHealthStatus(port: number, credential: string): Promise<number> {
    const request = http.createHttp();
    try {
      const response = await request.request(`http://127.0.0.1:${port}/health`, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': `Bearer ${credential}`,
          'Origin': `http://127.0.0.1:${port}`
        },
        connectTimeout: 1500,
        readTimeout: 1500,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      });
      return response.responseCode;
    } catch (_) {
      return 0;
    } finally {
      request.destroy();
    }
  }

  async probeProcessAudit(port: number, credential: string): Promise<ProcessAuditCheckpoint> {
    const request = http.createHttp();
    try {
      const response = await request.request(`http://127.0.0.1:${port}/audit/process`, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': `Bearer ${credential}`,
          'Origin': `http://127.0.0.1:${port}`
        },
        connectTimeout: 1500,
        readTimeout: 1500,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== 200) {
        throw new RuntimeLifecycleError('PROCESS_AUDIT_REJECTED', this.phase,
          `Process audit returned HTTP ${response.responseCode}`);
      }
      const result = JSON.parse(String(response.result)) as ProcessAuditCheckpoint;
      if (typeof result.pass !== 'boolean' ||
        !Number.isInteger(result.openCodeAttempts) || result.openCodeAttempts < 0 ||
        !Number.isInteger(result.runtimeAttempts) || result.runtimeAttempts < 0) {
        throw new RuntimeLifecycleError('PROCESS_AUDIT_INVALID', this.phase,
          'Process audit returned an invalid bounded result');
      }
      return result;
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) throw error;
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('PROCESS_AUDIT_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('PROCESS_AUDIT_REQUEST_FAILED', this.phase,
        'Process audit request failed with an unknown error');
    } finally {
      request.destroy();
    }
  }

  async proposeOpenCodeAuthorizedPatch(path: string): Promise<OpenCodeAuthorizedPatchProposal> {
    const relativePath = requireOpenCodeAuthorizedPath(path);
    const port = this.requireInteractivePort();
    try {
      const fileRaw = await this.requestOpenCodeAuthorizedEndpoint(
        port,
        `/project/file?path=${encodeURIComponent(relativePath)}`,
        http.RequestMethod.GET
      );
      const snapshot = parseOpenCodeAuthorizedFile(fileRaw, relativePath);
      const preparation = prepareOpenCodeAuthorizedPatch(snapshot.path, snapshot.content);
      const proposalRaw = await this.requestOpenCodeAuthorizedEndpoint(
        port,
        '/project/patch/propose',
        http.RequestMethod.POST,
        JSON.stringify({ patchText: preparation.patchText })
      );
      return parseOpenCodeAuthorizedProposal(proposalRaw, relativePath);
    } catch (error) {
      throw this.normalizeAuthorizedPatchError(error);
    }
  }

  async acceptOpenCodeAuthorizedPatch(proposalId: string,
    path: string): Promise<OpenCodeAuthorizedPatchAcceptance> {
    const normalizedProposalId = requireOpenCodeAuthorizedProposalId(proposalId);
    const relativePath = requireOpenCodeAuthorizedPath(path);
    const port = this.requireInteractivePort();
    try {
      const raw = await this.requestOpenCodeAuthorizedEndpoint(
        port,
        `/project/patch/${encodeURIComponent(normalizedProposalId)}/accept`,
        http.RequestMethod.POST
      );
      return parseOpenCodeAuthorizedAcceptance(raw, normalizedProposalId, relativePath);
    } catch (error) {
      throw this.normalizeAuthorizedPatchError(error);
    }
  }

  async rejectOpenCodeAuthorizedPatch(proposalId: string,
    path: string): Promise<OpenCodeAuthorizedPatchRejection> {
    const normalizedProposalId = requireOpenCodeAuthorizedProposalId(proposalId);
    const relativePath = requireOpenCodeAuthorizedPath(path);
    const port = this.requireInteractivePort();
    try {
      const raw = await this.requestOpenCodeAuthorizedEndpoint(
        port,
        `/project/patch/${encodeURIComponent(normalizedProposalId)}/reject`,
        http.RequestMethod.POST
      );
      return parseOpenCodeAuthorizedRejection(raw, normalizedProposalId, relativePath);
    } catch (error) {
      throw this.normalizeAuthorizedPatchError(error);
    }
  }

  async runDeviceParityValidation(): Promise<DeviceParitySummary> {
    if (this.phase !== 'idle') {
      throw new RuntimeLifecycleError('PARITY_INVALID_STATE', this.phase,
        'Runtime must be idle before the device parity gate starts');
    }
    try {
      this.phase = 'parity-starting';
      const start = this.startRuntime('', 'parity');
      this.currentStart = start;
      const ready = await this.waitForReady(start, 300000);
      this.currentPort = ready.port;
      this.phase = 'parity-ready';
      const report = this.requireDeviceParityReport(ready);

      this.phase = 'parity-stopping';
      await this.requestStop(ready.port);
      const exited = await this.waitForExit(start, 15000);
      const finalReport = this.requireDeviceParityReport(exited);
      if (JSON.stringify(report) !== JSON.stringify(finalReport)) {
        throw new RuntimeLifecycleError('PARITY_RESULT_CHANGED', this.phase,
          'Device parity result changed between ready and graceful exit');
      }
      if (!(await this.expectHealthFailure(ready.port))) {
        throw new RuntimeLifecycleError('PARITY_STALE_LISTENER', 'exited',
          'Device parity listener remained reachable after the child exited');
      }
      const environment = exited.environment === undefined ? ready.environment : exited.environment;
      if (environment === undefined) {
        throw new RuntimeLifecycleError('PARITY_ENVIRONMENT_MISSING', 'exited',
          'Device parity result omitted its runtime environment fingerprint');
      }
      this.currentPort = 0;
      this.currentStart = undefined;
      this.currentCredential = '';
      this.phase = 'idle';
      return {
        schemaVersion: finalReport.schemaVersion,
        suite: finalReport.suite,
        caseCount: finalReport.caseCount,
        allIdle: finalReport.allIdle,
        reportSha256: finalReport.reportSha256,
        runnerSha256: finalReport.runnerSha256,
        expectedReportSha256: finalReport.expectedReportSha256,
        matchesHostV2: finalReport.matchesHostV2,
        generation: start.generation,
        readyMs: ready.readyMs === undefined ? 0 : ready.readyMs,
        environment: environment
      };
    } catch (error) {
      this.phase = 'error';
      await this.shutdownIfRunning();
      if (error instanceof Error) throw error;
      throw new RuntimeLifecycleError('PARITY_UNKNOWN_FAILURE', this.phase,
        'Device parity validation failed with an unknown error');
    }
  }

  private requireDeviceParityReport(document: RuntimeStateDocument): DeviceParityReport {
    const report = document.parity;
    if (report === undefined || report.schemaVersion !== 1 ||
      report.suite !== 'opencode-session-lifecycle' || report.caseCount !== 9 ||
      report.allIdle !== true || report.matchesHostV2 !== true ||
      report.reportSha256 !== report.expectedReportSha256 ||
      !/^[a-f0-9]{64}$/.test(report.reportSha256) ||
      !/^[a-f0-9]{64}$/.test(report.runnerSha256)) {
      const diagnostic = report === undefined ? 'report=missing' :
        `cases=${report.caseCount},allIdle=${String(report.allIdle)},matchesHostV2=${String(report.matchesHostV2)},` +
        `actual=${report.reportSha256},expected=${report.expectedReportSha256},` +
        `failedCase=${report.failedCase === undefined ? 'none' : report.failedCase},` +
        `failure=${report.failure === undefined ? 'none' : report.failure}`;
      throw new RuntimeLifecycleError('PARITY_RESULT_INVALID', this.phase,
        `Device parity result is invalid: ${diagnostic}`);
    }
    return report;
  }

  async runLifecycleValidation(cycleCount: number = 2): Promise<LifecycleValidationSummary> {
    if (this.phase !== 'idle') {
      throw new RuntimeLifecycleError('INVALID_STATE', this.phase,
        'Runtime lifecycle validation is already active');
    }
    if (cycleCount < 2 || cycleCount > 4) {
      throw new RuntimeLifecycleError('INVALID_CYCLE_COUNT', this.phase,
        'Lifecycle validation requires between two and four cycles');
    }

    const cycles: LifecycleCycleSummary[] = [];
    try {
      for (let cycle = 1; cycle <= cycleCount; cycle += 1) {
        cycles.push(await this.runCycle(cycle));
      }
      const sqliteRecovery = await this.runSqliteRecoveryValidation();
      const processBoundary = await this.runProcessBoundaryValidation();
      this.phase = 'idle';
      return {
        protocolVersion: 1,
        cycles: cycles,
        restartPass: cycles.length === cycleCount,
        gracefulStopPass: cycles.every((item: LifecycleCycleSummary) =>
          item.shutdownReason === 'requested' && item.postExitHealthRejected),
        structuredRunnerPass: cycles.every((item: LifecycleCycleSummary) =>
          item.tests.length >= 4 && item.tests.every((test: StructuredDeviceTestResult) =>
            test.status !== 'fail')),
        credentialRotationPass: true,
        sqliteRecovery: sqliteRecovery,
        processBoundary: processBoundary
      };
    } catch (error) {
      this.phase = 'error';
      if (error instanceof Error) {
        throw error;
      }
      throw new RuntimeLifecycleError('UNKNOWN_LIFECYCLE_ERROR', this.phase,
        'Runtime lifecycle validation failed with an unknown error');
    }
  }

  async shutdownIfRunning(): Promise<void> {
    if (this.currentStart === undefined) {
      this.currentPort = 0;
      this.currentCredential = '';
      this.phase = 'idle';
      return;
    }
    if (this.currentPort <= 0) {
      const nativeState = nativeSpike.getNativeChildProcessState();
      if (nativeState.activePid === this.currentStart.pid) return;
      this.currentStart = undefined;
      this.currentCredential = '';
      this.phase = 'idle';
      return;
    }
    try {
      await this.requestStop(this.currentPort);
      await this.waitForExit(this.currentStart, 5000);
    } catch (_) {
      // The child has a 20 second watchdog; teardown remains bounded even if this best-effort call fails.
    } finally {
      this.currentPort = 0;
      this.currentStart = undefined;
      this.currentCredential = '';
      this.phase = 'idle';
    }
  }

  async runAuthorizedProjectValidation(projectRoot: string): Promise<AuthorizedProjectValidationSummary> {
    if (this.phase !== 'idle') {
      throw new RuntimeLifecycleError('INVALID_STATE', this.phase,
        'Runtime must be idle before authorized project validation');
    }
    if (!projectRoot.startsWith('/') || projectRoot.length > 4096 ||
      projectRoot.includes('\0') || projectRoot.includes('\r') || projectRoot.includes('\n')) {
      throw new RuntimeLifecycleError('INVALID_PROJECT_ROOT', this.phase,
        'Authorized project root is not a supported local path');
    }

    const requiredFirstCycle: string[] = [
      'node.project.root-normalization',
      'node.project.recursive-read',
      'node.project.large-file-stream',
      'node.project.permitted-write',
      'node.project.atomic-replacement',
      'node.project.rejected-edit-unchanged',
      'node.project.traversal-denial',
      'node.project.uri-denial',
      'node.project.link-indirection-denial'
    ];
    try {
      this.phase = 'project-starting';
      const firstStart = this.startRuntime(projectRoot);
      this.currentStart = firstStart;
      const firstReady = await this.waitForReady(firstStart, 8000);
      this.phase = 'project-ready';
      this.currentPort = firstReady.port;
      const firstTests = this.requirePassingProjectTests(firstReady, requiredFirstCycle);
      if (!(await this.requestHealth(firstReady.port))) {
        throw new RuntimeLifecycleError('PROJECT_HEALTH_FAILED', this.phase,
          'Authorized-project runtime did not return HTTP 200');
      }

      await this.requestProjectInterruptedEdit(firstReady.port);
      this.phase = 'project-forced-exit';
      const forcedExitSignal = await this.waitForForcedExit(firstStart, 5000);
      const interruptedState = this.readDocument(firstStart.statePath);
      if (interruptedState === undefined || interruptedState.projectInterruptionPrepared !== true) {
        throw new RuntimeLifecycleError('PROJECT_INTERRUPTION_NOT_PREPARED', this.phase,
          'Forced-exit state did not record the uncommitted temporary edit');
      }
      this.currentPort = 0;
      this.currentStart = undefined;

      this.phase = 'project-recovery-starting';
      const recoveryStart = this.startRuntime(projectRoot);
      this.currentStart = recoveryStart;
      const recoveryReady = await this.waitForReady(recoveryStart, 8000);
      this.phase = 'project-recovery-ready';
      this.currentPort = recoveryReady.port;
      const recoveryTests = this.requirePassingProjectTests(recoveryReady,
        ['node.project.interruption-recovery']);
      if (!(await this.requestHealth(recoveryReady.port))) {
        throw new RuntimeLifecycleError('PROJECT_RECOVERY_HEALTH_FAILED', this.phase,
          'Recovered authorized-project runtime did not return HTTP 200');
      }

      this.phase = 'project-stopping';
      await this.requestStop(recoveryReady.port);
      await this.waitForExit(recoveryStart, 5000);
      if (!(await this.expectHealthFailure(recoveryReady.port))) {
        throw new RuntimeLifecycleError('PROJECT_RECOVERY_STALE_LISTENER', 'exited',
          'Recovered authorized-project listener remained reachable after stop');
      }
      this.currentPort = 0;
      this.currentStart = undefined;
      this.phase = 'idle';
      const tests = firstTests.concat(recoveryTests);
      return {
        protocolVersion: 1,
        tests: tests,
        allPassed: tests.every((test: StructuredDeviceTestResult) => test.status === 'pass'),
        forcedExitObserved: true,
        forcedExitSignal: forcedExitSignal,
        recoveryPass: recoveryTests.length === 1 && recoveryTests[0].status === 'pass'
      };
    } catch (error) {
      this.phase = 'error';
      await this.shutdownIfRunning();
      if (error instanceof Error) throw error;
      throw new RuntimeLifecycleError('UNKNOWN_PROJECT_VALIDATION_ERROR', this.phase,
        'Authorized project validation failed with an unknown error');
    }
  }

  private async runCycle(cycle: number): Promise<LifecycleCycleSummary> {
    const cycleStartedAt = Date.now();
    this.phase = 'starting';
    const start = this.startRuntime();
    this.currentStart = start;

    const ready = await this.waitForReady(start, 5000);
    const controllerReadyMs = Date.now() - cycleStartedAt;
    this.phase = 'ready';
    this.currentPort = ready.port;

    for (let check = 0; check < 3; check += 1) {
      const healthy = await this.requestHealth(ready.port);
      if (!healthy) {
        throw new RuntimeLifecycleError('HEALTH_FAILED', this.phase,
          `Health request ${check + 1} did not return HTTP 200`);
      }
      await this.delay(200);
    }

    this.phase = 'stopping';
    await this.requestStop(ready.port);
    const exited = await this.waitForExit(start, 5000);
    const postExitHealthRejected = await this.expectHealthFailure(ready.port);
    if (!postExitHealthRejected) {
      throw new RuntimeLifecycleError('STALE_LISTENER', 'exited',
        'Health endpoint remained reachable after the child exit callback');
    }
    if (exited.environment === undefined || exited.tests === undefined ||
      exited.resourceMetrics === undefined) {
      throw new RuntimeLifecycleError('MISSING_STRUCTURED_RESULTS', 'exited',
        'Runtime result did not include the environment fingerprint and bounded test records');
    }

    this.currentPort = 0;
    this.currentStart = undefined;
    this.phase = 'idle';
    return {
      cycle: cycle,
      generation: start.generation,
      readyMs: ready.readyMs === undefined ? 0 : ready.readyMs,
      controllerReadyMs: controllerReadyMs,
      durationMs: exited.durationMs === undefined ? Date.now() - cycleStartedAt : exited.durationMs,
      healthChecks: exited.healthChecks,
      exitSignal: nativeSpike.getNativeChildProcessState().lastExitSignal,
      shutdownReason: exited.reason === undefined ? 'unknown' : exited.reason,
      postExitHealthRejected: postExitHealthRejected,
      environment: exited.environment,
      tests: exited.tests,
      resourceMetrics: exited.resourceMetrics
    };
  }

  private startRuntime(projectRoot: string = '',
    runtimeMode: 'validation' | 'interactive' | 'parity' = 'validation'): NativeChildStartResult {
    this.currentCredential = '';
    const start = nativeSpike.startNativeChildProcess(this.filesDirectory, this.compileSdkVersion,
      this.deviceApiVersion, this.compileSdkApiVersion, this.targetApiVersion, projectRoot,
      runtimeMode);
    if (start.callbackCode !== 0) {
      throw new RuntimeLifecycleError('EXIT_CALLBACK_REGISTRATION_FAILED', this.phase,
        `Native exit callback registration failed with code ${start.callbackCode}`);
    }
    if (start.code !== 0 || start.pid < 0) {
      throw new RuntimeLifecycleError('START_FAILED', this.phase,
        `Native child process start failed with code ${start.code}`);
    }
    return start;
  }

  private requirePassingProjectTests(document: RuntimeStateDocument,
    requiredNames: string[]): StructuredDeviceTestResult[] {
    if (document.tests === undefined) {
      throw new RuntimeLifecycleError('PROJECT_RESULTS_MISSING', this.phase,
        'Runtime state did not contain structured project tests');
    }
    const selected: StructuredDeviceTestResult[] = [];
    for (const name of requiredNames) {
      let match: StructuredDeviceTestResult | undefined = undefined;
      for (const test of document.tests) {
        if (test.name === name) {
          match = test;
          break;
        }
      }
      if (match === undefined) {
        throw new RuntimeLifecycleError('PROJECT_TEST_MISSING', this.phase,
          `Required project test was not recorded: ${name}`);
      }
      if (match.status !== 'pass') {
        throw new RuntimeLifecycleError('PROJECT_TEST_FAILED', this.phase,
          `Required project test failed: ${name} (${match.actual})`);
      }
      selected.push(match);
    }
    return selected;
  }

  private async runSqliteRecoveryValidation(): Promise<SqliteRecoverySummary> {
    if (!nativeSpike.resetSqliteRecoveryState(this.filesDirectory)) {
      throw new RuntimeLifecycleError('SQLITE_RECOVERY_RESET_FAILED', this.phase,
        'Failed to reset the disposable SQLite recovery database');
    }

    this.phase = 'starting';
    const crashStart = this.startRuntime();
    this.currentStart = crashStart;
    const crashReady = await this.waitForReady(crashStart, 5000);
    this.phase = 'ready';
    this.currentPort = crashReady.port;
    await this.requestCrashAfterCommit(crashReady.port);
    this.phase = 'forced-exit';
    const forcedExitSignal = await this.waitForForcedExit(crashStart, 5000);
    const committedState = this.readDocument(crashStart.statePath);
    if (committedState === undefined || committedState.recoveryCommitted !== true) {
      throw new RuntimeLifecycleError('SQLITE_COMMIT_NOT_OBSERVED', this.phase,
        'Forced-exit state did not prove a committed SQLite transaction');
    }
    this.currentPort = 0;
    this.currentStart = undefined;

    this.phase = 'starting';
    const recoveryStart = this.startRuntime();
    this.currentStart = recoveryStart;
    const recoveryReady = await this.waitForReady(recoveryStart, 5000);
    this.phase = 'ready';
    this.currentPort = recoveryReady.port;

    let recoveryTest: StructuredDeviceTestResult | undefined = undefined;
    if (recoveryReady.tests !== undefined) {
      for (const test of recoveryReady.tests) {
        if (test.name === 'node.sqlite.forced-recovery') {
          recoveryTest = test;
          break;
        }
      }
    }
    if (recoveryTest === undefined || recoveryTest.status !== 'pass') {
      throw new RuntimeLifecycleError('SQLITE_RECOVERY_FAILED', this.phase,
        'Restarted runtime did not recover the committed SQLite record');
    }
    if (!(await this.requestHealth(recoveryReady.port))) {
      throw new RuntimeLifecycleError('RECOVERY_HEALTH_FAILED', this.phase,
        'Recovered runtime did not return HTTP 200');
    }

    this.phase = 'stopping';
    await this.requestStop(recoveryReady.port);
    await this.waitForExit(recoveryStart, 5000);
    if (!(await this.expectHealthFailure(recoveryReady.port))) {
      throw new RuntimeLifecycleError('RECOVERY_STALE_LISTENER', 'exited',
        'Recovered runtime listener remained reachable after stop');
    }
    this.currentPort = 0;
    this.currentStart = undefined;
    this.phase = 'idle';
    return {
      commitObserved: true,
      forcedExitObserved: true,
      forcedExitSignal: forcedExitSignal,
      recoveryPass: true,
      recoveryDurationMs: recoveryTest.durationMs
    };
  }

  private async runProcessBoundaryValidation(): Promise<ProcessBoundarySummary> {
    const methods: string[] = ['spawn', 'exec', 'execFile', 'fork'];
    const results: ProcessBoundaryResult[] = [];
    for (const method of methods) {
      this.phase = `process-test-${method}`;
      const start = this.startRuntime();
      this.currentStart = start;
      const ready = await this.waitForReady(start, 5000);
      this.currentPort = ready.port;
      await this.requestProcessBoundaryTest(ready.port, method);
      results.push(await this.waitForProcessBoundaryResult(start, method, 7000));
      this.currentPort = 0;
      this.currentStart = undefined;
    }
    this.phase = 'idle';
    return {
      results: results,
      allRecorded: results.length === methods.length
    };
  }

  private async waitForReady(start: NativeChildStartResult, timeoutMs: number): Promise<RuntimeStateDocument> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const document = this.readDocument(start.statePath);
      if (document !== undefined) {
        if (document.phase === 'ready' && document.port > 0) {
          if (document.credential === undefined || document.credential.length < 43) {
            throw new RuntimeLifecycleError('READY_CREDENTIAL_MISSING', document.phase,
              'Runtime ready state did not include a bounded high-entropy credential');
          }
          if (this.previousCredential.length > 0 &&
            this.previousCredential === document.credential) {
            throw new RuntimeLifecycleError('CREDENTIAL_REUSE', document.phase,
              'Runtime reused the previous child credential');
          }
          this.previousCredential = document.credential;
          this.currentCredential = document.credential;
          return document;
        }
        if (document.phase === 'exited') {
          throw new RuntimeLifecycleError('EXITED_BEFORE_READY', document.phase,
            document.error === undefined ? 'Runtime exited before ready' : document.error);
        }
      }
      const nativeState = nativeSpike.getNativeChildProcessState();
      if (nativeState.exitObserved && nativeState.lastExitPid === start.pid) {
        throw new RuntimeLifecycleError('EXITED_BEFORE_READY', 'starting',
          `Runtime exited before ready with signal ${nativeState.lastExitSignal}`);
      }
      await this.delay(100);
    }
    throw new RuntimeLifecycleError('READY_TIMEOUT', 'starting',
      `Runtime did not report ready within ${timeoutMs}ms`);
  }

  private async waitForExit(start: NativeChildStartResult, timeoutMs: number): Promise<RuntimeStateDocument> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const nativeState: NativeChildProcessState = nativeSpike.getNativeChildProcessState();
      const document = this.readDocument(start.resultPath);
      if (nativeState.exitObserved && nativeState.lastExitPid === start.pid &&
        nativeState.activePid < 0 && document !== undefined && document.phase === 'exited') {
        return document;
      }
      await this.delay(100);
    }
    throw new RuntimeLifecycleError('EXIT_TIMEOUT', 'stopping',
      `Runtime did not report exit within ${timeoutMs}ms`);
  }

  private async waitForForcedExit(start: NativeChildStartResult, timeoutMs: number): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const nativeState: NativeChildProcessState = nativeSpike.getNativeChildProcessState();
      if (nativeState.exitObserved && nativeState.lastExitPid === start.pid && nativeState.activePid < 0) {
        return nativeState.lastExitSignal;
      }
      await this.delay(100);
    }
    throw new RuntimeLifecycleError('FORCED_EXIT_TIMEOUT', 'forced-exit',
      `Runtime did not report forced exit within ${timeoutMs}ms`);
  }

  private async waitForProcessBoundaryResult(start: NativeChildStartResult, method: string,
    timeoutMs: number): Promise<ProcessBoundaryResult> {
    const deadline = Date.now() + timeoutMs;
    let observed: ProcessBoundaryDocument | undefined = undefined;
    while (Date.now() < deadline) {
      const document = this.readDocument(start.statePath);
      if (document !== undefined && document.processBoundary !== undefined &&
        document.processBoundary.method === method) {
        observed = document.processBoundary;
      }
      const nativeState: NativeChildProcessState = nativeSpike.getNativeChildProcessState();
      if (nativeState.exitObserved && nativeState.lastExitPid === start.pid && nativeState.activePid < 0) {
        const hasStructuredOutcome = observed !== undefined && observed.outcome !== 'invoking';
        return {
          method: method,
          outcome: hasStructuredOutcome && observed !== undefined ? observed.outcome :
            `terminated-by-signal-${nativeState.lastExitSignal}`,
          exitSignal: nativeState.lastExitSignal,
          structuredOutcome: hasStructuredOutcome
        };
      }
      await this.delay(100);
    }
    throw new RuntimeLifecycleError('PROCESS_BOUNDARY_TIMEOUT', this.phase,
      `${method} process-boundary test did not exit within ${timeoutMs}ms`);
  }

  private readDocument(path: string): RuntimeStateDocument | undefined {
    const payload = nativeSpike.readRuntimeResult(path);
    if (payload.length === 0) return undefined;
    try {
      return JSON.parse(payload) as RuntimeStateDocument;
    } catch (_) {
      throw new RuntimeLifecycleError('INVALID_STATE_DOCUMENT', this.phase,
        'Runtime state document is not valid JSON');
    }
  }

  private async requestHealth(port: number): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(`http://127.0.0.1:${port}/health`, {
        method: http.RequestMethod.GET,
        header: this.authenticatedHeaders(port),
        connectTimeout: 1500,
        readTimeout: 1500,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      });
      return response.responseCode === 200;
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) {
        throw error;
      }
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('HEALTH_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('HEALTH_REQUEST_FAILED', this.phase,
        'Health request failed with an unknown error');
    } finally {
      request.destroy();
    }
  }

  private async requestStop(port: number): Promise<void> {
    const request = http.createHttp();
    try {
      const response = await request.request(`http://127.0.0.1:${port}/stop`, {
        method: http.RequestMethod.POST,
        header: this.authenticatedHeaders(port),
        connectTimeout: 1500,
        readTimeout: 1500,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== 202) {
        throw new RuntimeLifecycleError('STOP_REJECTED', this.phase,
          `Stop request returned HTTP ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) {
        throw error;
      }
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('STOP_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('STOP_REQUEST_FAILED', this.phase,
        'Stop request failed with an unknown error');
    } finally {
      request.destroy();
    }
  }

  private async requestInteractiveMode(port: number): Promise<void> {
    const request = http.createHttp();
    try {
      const response = await request.request(`http://127.0.0.1:${port}/interactive-mode`, {
        method: http.RequestMethod.POST,
        header: this.authenticatedHeaders(port),
        connectTimeout: 1500,
        readTimeout: 1500,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== 204) {
        throw new RuntimeLifecycleError('INTERACTIVE_MODE_REJECTED', this.phase,
          `Interactive-mode request returned HTTP ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) throw error;
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('INTERACTIVE_MODE_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('INTERACTIVE_MODE_REQUEST_FAILED', this.phase,
        'Interactive-mode request failed with an unknown error');
    } finally {
      request.destroy();
    }
  }

  private async requestCrashAfterCommit(port: number): Promise<void> {
    const request = http.createHttp();
    try {
      const response = await request.request(
        `http://127.0.0.1:${port}/sqlite/commit-and-crash`, {
          method: http.RequestMethod.POST,
          header: this.authenticatedHeaders(port),
          connectTimeout: 1500,
          readTimeout: 1500,
          usingProxy: false,
          expectDataType: http.HttpDataType.STRING
        });
      if (response.responseCode !== 202) {
        throw new RuntimeLifecycleError('SQLITE_CRASH_REQUEST_REJECTED', this.phase,
          `SQLite crash request returned HTTP ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) {
        throw error;
      }
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('SQLITE_CRASH_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('SQLITE_CRASH_REQUEST_FAILED', this.phase,
        'SQLite crash request failed with an unknown error');
    } finally {
      request.destroy();
    }
  }

  private async requestProjectInterruptedEdit(port: number): Promise<void> {
    const request = http.createHttp();
    try {
      const response = await request.request(
        `http://127.0.0.1:${port}/project/prepare-interrupted-edit`, {
          method: http.RequestMethod.POST,
          header: this.authenticatedHeaders(port),
          connectTimeout: 1500,
          readTimeout: 1500,
          usingProxy: false,
          expectDataType: http.HttpDataType.STRING
        });
      if (response.responseCode !== 202) {
        throw new RuntimeLifecycleError('PROJECT_INTERRUPT_REQUEST_REJECTED', this.phase,
          `Project interruption request returned HTTP ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) throw error;
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('PROJECT_INTERRUPT_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('PROJECT_INTERRUPT_REQUEST_FAILED', this.phase,
        'Project interruption request failed with an unknown error');
    } finally {
      request.destroy();
    }
  }

  private async requestProcessBoundaryTest(port: number, method: string): Promise<void> {
    const request = http.createHttp();
    try {
      const response = await request.request(
        `http://127.0.0.1:${port}/process-test/${method}`, {
          method: http.RequestMethod.POST,
          header: this.authenticatedHeaders(port),
          connectTimeout: 1500,
          readTimeout: 1500,
          usingProxy: false,
          expectDataType: http.HttpDataType.STRING
        });
      if (response.responseCode !== 202) {
        throw new RuntimeLifecycleError('PROCESS_TEST_REJECTED', this.phase,
          `${method} process test returned HTTP ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) {
        throw error;
      }
      if (error instanceof Error) {
        throw new RuntimeLifecycleError('PROCESS_TEST_REQUEST_FAILED', this.phase, error.message);
      }
      throw new RuntimeLifecycleError('PROCESS_TEST_REQUEST_FAILED', this.phase,
        `${method} process test request failed with an unknown error`);
    } finally {
      request.destroy();
    }
  }

  private requireInteractivePort(): number {
    if (this.phase !== 'arkweb-ready' || this.currentPort <= 0 ||
      this.currentCredential.length === 0) {
      throw new RuntimeLifecycleError('HARMONY_AUTHORIZED_RUNTIME_NOT_READY', this.phase,
        'The interactive OpenCode runtime is not ready for an authorized patch request');
    }
    return this.currentPort;
  }

  private async requestOpenCodeAuthorizedEndpoint(port: number, path: string,
    method: http.RequestMethod, body: string = ''): Promise<string> {
    const request = http.createHttp();
    try {
      const headers = this.authenticatedHeaders(port);
      if (body.length > 0) headers['Content-Type'] = 'application/json';
      const response = await request.request(`http://127.0.0.1:${port}${path}`, {
        method: method,
        header: headers,
        extraData: body.length > 0 ? body : undefined,
        connectTimeout: 2000,
        readTimeout: 5000,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      });
      const raw = String(response.result);
      if (response.responseCode !== 200) {
        throw new RuntimeLifecycleError(parseOpenCodeAuthorizedError(raw), this.phase,
          'The OpenCode authorized patch request was rejected');
      }
      return raw;
    } catch (error) {
      if (error instanceof RuntimeLifecycleError) throw error;
      throw new RuntimeLifecycleError('HARMONY_AUTHORIZED_REQUEST_FAILED', this.phase,
        'The OpenCode authorized patch request failed');
    } finally {
      request.destroy();
    }
  }

  private normalizeAuthorizedPatchError(error: Object): RuntimeLifecycleError {
    if (error instanceof RuntimeLifecycleError) return error;
    if (error instanceof OpenCodeAuthorizedPatchContractError) {
      return new RuntimeLifecycleError(error.code, this.phase, error.message);
    }
    return new RuntimeLifecycleError('HARMONY_AUTHORIZED_REQUEST_FAILED', this.phase,
      'The OpenCode authorized patch request failed');
  }

  private async expectHealthFailure(port: number): Promise<boolean> {
    try {
      return !(await this.requestHealth(port));
    } catch (_) {
      return true;
    }
  }

  private authenticatedHeaders(port: number): Record<string, string> {
    if (this.currentCredential.length === 0) {
      throw new RuntimeLifecycleError('CREDENTIAL_NOT_READY', this.phase,
        'Authenticated loopback request attempted before credential readiness');
    }
    return {
      'Authorization': `Bearer ${this.currentCredential}`,
      'Origin': `http://127.0.0.1:${port}`
    };
  }

  private delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }
}
