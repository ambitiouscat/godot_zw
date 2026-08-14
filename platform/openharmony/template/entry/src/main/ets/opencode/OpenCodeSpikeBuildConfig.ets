import BuildProfile from 'hap_editor/BuildProfile';

/**
 * This module is the only default-build contact point for the OpenCode spike.
 *
 * It deliberately imports no OpenCode runtime implementation. Runtime,
 * NativeChildProcess and asset modules must only be reached after checking
 * OPENCODE_HARMONY_ENABLED.
 */
export const OPENCODE_HARMONY_ENABLED: boolean = BuildProfile.OPENCODE_HARMONY_ENABLED;
export const OPENCODE_HARMONY_BUILD_MODE: string = BuildProfile.BUILD_MODE_NAME;
export const OPENCODE_HARMONY_RUNTIME_SELECTION: string = BuildProfile.OPENCODE_HARMONY_RUNTIME;
export const OPENCODE_HARMONY_CLIENT_SELECTION: string = BuildProfile.OPENCODE_HARMONY_CLIENT;
export const OPENCODE_HARMONY_PARITY_ENABLED: boolean = BuildProfile.OPENCODE_HARMONY_PARITY;

export const OPENCODE_HARMONY_MINIMAL_RUNTIME: string = 'minimal-compatibility';
export const OPENCODE_HARMONY_FORMAL_RUNTIME: string = 'formal-upstream';
export const OPENCODE_HARMONY_FORMAL_RUNTIME_SELECTED: boolean =
  OPENCODE_HARMONY_RUNTIME_SELECTION === OPENCODE_HARMONY_FORMAL_RUNTIME;
