export type FormalHostCallback =
  | 'runtime.ready'
  | 'runtime.fatal'
  | 'runtime.stopped'
  | 'workspace.changed';

export interface FormalRuntimeBootstrapInput {
  filesDirectory: string;
  cacheDirectory: string;
  temporaryDirectory: string;
  projectRoot: string;
  entryPath: string;
  credential: string;
  allowedOrigin: string;
  capabilityProfile: string;
  deviceForm?: string;
  generation: number;
  requestedPort: number;
}

export interface FormalRuntimeContract {
  version: number;
  capabilityProfile: string;
  entryExport: string;
  approvedHostCallbacks: FormalHostCallback[];
}

export interface FormalRuntimeStartResult {
  pid: number;
  generation: number;
  errorCode: number;
}

export interface FormalRuntimeStopResult {
  stopped: boolean;
  errorCode: number;
}

export interface FormalRuntimeState {
  activePid: number;
  activeGeneration: number;
  lastExitPid: number;
  lastExitSignal: number;
  lastExitGeneration: number;
  phase: number;
  errorCode: number;
}

declare const formalRuntime: {
  startFormalRuntime(input: FormalRuntimeBootstrapInput): FormalRuntimeStartResult;
  stopFormalRuntime(generation: number): FormalRuntimeStopResult;
  getFormalRuntimeState(generation: number): FormalRuntimeState;
  readFormalHostEvent(): string;
  getFormalRuntimeContract(): FormalRuntimeContract;
};

export default formalRuntime;
