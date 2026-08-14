export const OPENCODE_EDITOR_ACTION_VERSION = 1;
export const OPENCODE_EDITOR_ACTION_NATIVE_EVENT = 'opencode.editor-action.v1';
export const OPENCODE_EDITOR_ACTION_TIMEOUT_MS = 5000;

const MAX_ACTION_PATH_LENGTH = 512;
const MAX_PROJECT_ROOT_LENGTH = 2048;
const MAX_POSITION = 1000000;
const MAX_NATIVE_RESPONSE_LENGTH = 49152;

export type OpenCodeEditorActionMethod =
  'editor.open-file' |
  'editor.position-cursor' |
  'editor.refresh-resource' |
  'editor.select-scene-node';

interface OpenCodeEditorPathPayload {
  path?: string;
}

interface OpenCodeEditorPositionPayload {
  path?: string;
  line?: number;
  column?: number;
}

interface OpenCodeEditorNodePayload {
  nodePath?: string;
}

export interface OpenCodeEditorNativeAction {
  version: number;
  method: OpenCodeEditorActionMethod;
  authorizedRoot: string;
  path?: string;
  line?: number;
  column?: number;
  nodePath?: string;
}

export interface OpenCodeEditorActionResult {
  actionVersion: number;
  method: OpenCodeEditorActionMethod;
  completed: boolean;
  path?: string;
  line?: number;
  column?: number;
  nodePath?: string;
}

interface OpenCodeEditorNativeError {
  code?: string;
  summary?: string;
  retryable?: boolean;
}

interface OpenCodeEditorNativeResponse {
  version?: number;
  requestId?: string;
  ok?: boolean;
  result?: OpenCodeEditorActionResult;
  error?: OpenCodeEditorNativeError;
}

export class OpenCodeEditorActionContractError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, summary: string, retryable: boolean = false) {
    super(summary);
    this.code = code;
    this.retryable = retryable;
  }
}

export function prepareOpenCodeEditorAction(method: OpenCodeEditorActionMethod,
  payload: Object | undefined, authorizedRoot: string): OpenCodeEditorNativeAction {
  requireAuthorizedRoot(authorizedRoot);
  if (payload === undefined) {
    invalidPayload('The editor action payload is required');
  }

  if (method === 'editor.select-scene-node') {
    requireExactKeys(payload, ['nodePath']);
    const document = payload as OpenCodeEditorNodePayload;
    const nodePath = requireSceneNodePath(document.nodePath);
    return {
      version: OPENCODE_EDITOR_ACTION_VERSION,
      method: method,
      authorizedRoot: authorizedRoot,
      nodePath: nodePath
    };
  }

  if (method === 'editor.position-cursor') {
    requireExactKeys(payload, ['path', 'line', 'column']);
    const document = payload as OpenCodeEditorPositionPayload;
    return {
      version: OPENCODE_EDITOR_ACTION_VERSION,
      method: method,
      authorizedRoot: authorizedRoot,
      path: requireRelativeProjectPath(document.path),
      line: requirePosition(document.line),
      column: requirePosition(document.column)
    };
  }

  requireExactKeys(payload, ['path']);
  const document = payload as OpenCodeEditorPathPayload;
  return {
    version: OPENCODE_EDITOR_ACTION_VERSION,
    method: method,
    authorizedRoot: authorizedRoot,
    path: requireRelativeProjectPath(document.path)
  };
}

export function parseOpenCodeEditorActionResponse(rawResponse: string, expectedRequestId: string,
  expectedAction: OpenCodeEditorNativeAction): OpenCodeEditorActionResult {
  if (typeof rawResponse !== 'string' || rawResponse.length === 0 ||
    rawResponse.length > MAX_NATIVE_RESPONSE_LENGTH) {
    invalidResponse();
  }

  let response: OpenCodeEditorNativeResponse;
  try {
    response = JSON.parse(rawResponse) as OpenCodeEditorNativeResponse;
  } catch (_) {
    invalidResponse();
  }
  if (response.version !== OPENCODE_EDITOR_ACTION_VERSION ||
    response.requestId !== expectedRequestId || typeof response.ok !== 'boolean') {
    invalidResponse();
  }
  if (!response.ok) {
    const error = response.error;
    if (error === undefined || !isBoundedCode(error.code) ||
      !isBoundedText(error.summary, 160) || typeof error.retryable !== 'boolean') {
      invalidResponse();
    }
    throw new OpenCodeEditorActionContractError(
      error.code as string,
      error.summary as string,
      error.retryable as boolean
    );
  }

  const result = response.result;
  if (result === undefined || result.actionVersion !== OPENCODE_EDITOR_ACTION_VERSION ||
    result.method !== expectedAction.method || result.completed !== true) {
    invalidResponse();
  }
  validateExpectedResult(result, expectedAction);
  return result;
}

function validateExpectedResult(result: OpenCodeEditorActionResult,
  expectedAction: OpenCodeEditorNativeAction): void {
  if (expectedAction.path !== undefined && result.path !== expectedAction.path) invalidResponse();
  if (expectedAction.nodePath !== undefined && result.nodePath !== expectedAction.nodePath) invalidResponse();
  if (expectedAction.line !== undefined && result.line !== expectedAction.line) invalidResponse();
  if (expectedAction.column !== undefined && result.column !== expectedAction.column) invalidResponse();
}

function requireExactKeys(payload: Object, allowedKeys: string[]): void {
  const keys = Object.keys(payload);
  if (keys.length !== allowedKeys.length) invalidPayload('The editor action payload is invalid');
  for (const key of keys) {
    if (!allowedKeys.includes(key)) invalidPayload('The editor action payload contains unsupported fields');
  }
}

function requireRelativeProjectPath(value: string | undefined): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > MAX_ACTION_PATH_LENGTH ||
    value.startsWith('/') || value.endsWith('/') || value.includes('\\') || value.includes(':') ||
    hasControlCharacter(value)) {
    throw new OpenCodeEditorActionContractError(
      'ACTION_PATH_UNAUTHORIZED',
      'The editor action path must be relative to the authorized project root'
    );
  }
  const segments = value.split('/');
  for (const segment of segments) {
    if (segment.length === 0 || segment === '.' || segment === '..') {
      throw new OpenCodeEditorActionContractError(
        'ACTION_PATH_UNAUTHORIZED',
        'The editor action path escapes the authorized project root'
      );
    }
  }
  return value;
}

function requireSceneNodePath(value: string | undefined): string {
  if (typeof value !== 'string' || value.length < 2 || value.length > MAX_ACTION_PATH_LENGTH ||
    !value.startsWith('/') || value.endsWith('/') || hasControlCharacter(value)) {
    invalidPayload('The scene node path is invalid');
  }
  const segments = value.slice(1).split('/');
  for (const segment of segments) {
    if (segment.length === 0 || segment === '.' || segment === '..') {
      invalidPayload('The scene node path is invalid');
    }
  }
  return value;
}

function requirePosition(value: number | undefined): number {
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > MAX_POSITION) {
    invalidPayload('Editor line and column positions must be positive one-based integers');
  }
  return value as number;
}

function requireAuthorizedRoot(root: string): void {
  if (typeof root !== 'string' || !root.startsWith('/') || root.length > MAX_PROJECT_ROOT_LENGTH ||
    hasControlCharacter(root)) {
    throw new OpenCodeEditorActionContractError(
      'ACTION_PROJECT_UNAUTHORIZED',
      'The authorized project root is unavailable'
    );
  }
}

function invalidPayload(summary: string): never {
  throw new OpenCodeEditorActionContractError('ACTION_PAYLOAD_INVALID', summary);
}

function invalidResponse(): never {
  throw new OpenCodeEditorActionContractError(
    'ACTION_RESPONSE_INVALID',
    'The native editor action response contains invalid fields'
  );
}

function hasControlCharacter(value: string): boolean {
  return value.includes('\0') || value.includes('\r') || value.includes('\n') || value.includes('\t');
}

function isBoundedCode(value: string | undefined): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 64 &&
    /^[A-Z0-9_]+$/.test(value);
}

function isBoundedText(value: string | undefined, limit: number): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= limit &&
    !hasControlCharacter(value);
}
