export const OPENCODE_FORMAL_CHANGED_PATH_VERSION = 1;
export const OPENCODE_FORMAL_CHANGED_PATH_MAX_LENGTH = 512;

export type OpenCodeFormalChangedPathOperation = 'create' | 'write' | 'remove';

export interface OpenCodeFormalChangedPath {
  version: 1;
  operation: OpenCodeFormalChangedPathOperation;
  path: string;
}

export interface OpenCodeFormalChangedPathEvent {
  generation: number;
  sequence: number;
  kind: string;
  payload: string;
}

interface OpenCodeFormalChangedPathDocument {
  version?: number;
  operation?: string;
  path?: string;
}

export class OpenCodeFormalChangedPathError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(`${code}: ${message}`);
    this.code = code;
  }
}

/**
 * A per-generation gate for the fixed workspace.changed callback.
 *
 * The payload can select only a committed relative path. It cannot select a
 * Godot method or carry an arbitrary host command.
 */
export class OpenCodeFormalChangedPathGate {
  private generation: number = 0;
  private lastSequence: number = 0;

  start(generation: number): void {
    if (!Number.isInteger(generation) || generation <= 0) {
      throw new OpenCodeFormalChangedPathError(
        'FORMAL_CHANGED_PATH_GENERATION_INVALID',
        'The changed-path generation is invalid'
      );
    }
    if (generation === this.generation) return;
    this.generation = generation;
    this.lastSequence = 0;
  }

  stop(): void {
    this.generation = 0;
    this.lastSequence = 0;
  }

  accept(event: OpenCodeFormalChangedPathEvent): OpenCodeFormalChangedPath | undefined {
    if (event.kind !== 'workspace.changed' ||
      event.generation !== this.generation ||
      !Number.isInteger(event.sequence) ||
      event.sequence <= this.lastSequence) {
      return undefined;
    }
    const change = parseOpenCodeFormalChangedPath(event.payload);
    this.lastSequence = event.sequence;
    return change;
  }
}

export function parseOpenCodeFormalChangedPath(payload: string): OpenCodeFormalChangedPath {
  if (typeof payload !== 'string' || payload.length === 0 ||
    payload.length > OPENCODE_FORMAL_CHANGED_PATH_MAX_LENGTH * 4) {
    invalidChangedPath();
  }
  let document: OpenCodeFormalChangedPathDocument;
  try {
    document = JSON.parse(payload) as OpenCodeFormalChangedPathDocument;
  } catch (_) {
    invalidChangedPath();
  }
  if (document === null || typeof document !== 'object' || Array.isArray(document)) {
    invalidChangedPath();
  }
  const keys = Object.keys(document).sort();
  if (keys.length !== 3 ||
    keys[0] !== 'operation' ||
    keys[1] !== 'path' ||
    keys[2] !== 'version' ||
    document.version !== OPENCODE_FORMAL_CHANGED_PATH_VERSION ||
    !isOperation(document.operation) ||
    !isRelativeProjectPath(document.path)) {
    invalidChangedPath();
  }
  return {
    version: 1,
    operation: document.operation as OpenCodeFormalChangedPathOperation,
    path: document.path as string
  };
}

function isOperation(value: string | undefined): boolean {
  return value === 'create' || value === 'write' || value === 'remove';
}

function isRelativeProjectPath(value: string | undefined): boolean {
  if (typeof value !== 'string' || value.length === 0 ||
    value.length > OPENCODE_FORMAL_CHANGED_PATH_MAX_LENGTH ||
    value.startsWith('/') || value.endsWith('/') ||
    value.includes('\\') || value.includes(':') ||
    value.includes('\0') || value.includes('\r') ||
    value.includes('\n') || value.includes('\t')) {
    return false;
  }
  const segments = value.split('/');
  for (const segment of segments) {
    if (segment.length === 0 || segment === '.' || segment === '..') return false;
  }
  return true;
}

function invalidChangedPath(): never {
  throw new OpenCodeFormalChangedPathError(
    'FORMAL_CHANGED_PATH_INVALID',
    'The formal runtime changed-path payload is invalid'
  );
}
