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
  requestedPort: number;
}

export interface FormalRuntimeContract {
  version: number;
  capabilityProfile: string;
  entryExport: string;
  approvedHostCallbacks: FormalHostCallback[];
}

export interface FormalRuntimeStartResult {
  code: number;
  pid: number;
  callbackCode: number;
  generation: number;
  phase: string;
  hostEventPath: string;
}

export interface FormalRuntimeStopResult {
  code: number;
  pid: number;
  generation: number;
  accepted: boolean;
  phase: string;
}

export interface FormalRuntimeState {
  contractVersion: number;
  activePid: number;
  activeGeneration: number;
  highestGeneration: number;
  lastExitPid: number;
  lastExitSignal: number;
  lastExitGeneration: number;
  exitObserved: boolean;
  phase: string;
}

declare const formalRuntime: {
  startFormalRuntime(input: FormalRuntimeBootstrapInput): FormalRuntimeStartResult;
  stopFormalRuntime(generation: number): FormalRuntimeStopResult;
  getFormalRuntimeState(): FormalRuntimeState;
  readFormalHostEvent(): string;
  getFormalRuntimeContract(): FormalRuntimeContract;
};

export default formalRuntime;
