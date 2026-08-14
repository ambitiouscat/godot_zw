export const OPENCODE_EDITOR_CONTEXT_VERSION = 1;
export const OPENCODE_EDITOR_CONTEXT_NATIVE_EVENT = 'opencode.editor-context.v1';
export const OPENCODE_EDITOR_CONTEXT_TIMEOUT_MS = 3000;

const MAX_NATIVE_RESPONSE_LENGTH = 49152;
const MAX_PROJECT_ROOT_LENGTH = 4096;
const MAX_CONTEXT_PATH_LENGTH = 512;
const MAX_CONTEXT_NAME_LENGTH = 160;
const MAX_SELECTION_LENGTH = 4096;
const MAX_SCENE_NODES = 64;
const MAX_RESOURCE_REFERENCES = 32;

export type OpenCodeEditorContextMethod =
  'context.snapshot' |
  'context.active-project' |
  'context.active-script' |
  'context.selection' |
  'context.active-scene' |
  'context.scene-tree' |
  'context.selected-node' |
  'context.resource-references';

export interface OpenCodeEditorCursorContext {
  line: number;
  column: number;
}

export interface OpenCodeEditorSelectionContext {
  available: boolean;
  text?: string;
  truncated: boolean;
  fromLine?: number;
  fromColumn?: number;
  toLine?: number;
  toColumn?: number;
}

export interface OpenCodeEditorScriptContext {
  available: boolean;
  path?: string;
  cursor?: OpenCodeEditorCursorContext;
  selection?: OpenCodeEditorSelectionContext;
}

export interface OpenCodeEditorSceneNodeContext {
  name: string;
  type: string;
  path: string;
  depth: number;
  childCount: number;
}

export interface OpenCodeEditorSelectedNodeContext {
  available: boolean;
  name?: string;
  type?: string;
  path?: string;
  scriptPath?: string;
  resourceReferencesTruncated?: boolean;
}

export interface OpenCodeEditorResourceReferenceContext {
  property: string;
  type: string;
  path: string;
}

export interface OpenCodeEditorSceneContext {
  available: boolean;
  path?: string;
  nodes?: OpenCodeEditorSceneNodeContext[];
  treeTruncated?: boolean;
  selectedNode?: OpenCodeEditorSelectedNodeContext;
  resourceReferences?: OpenCodeEditorResourceReferenceContext[];
}

interface OpenCodeEditorNativeProjectContext {
  available: boolean;
  name?: string;
  resourcePath?: string;
}

export interface OpenCodeEditorContextNativeSnapshot {
  contextVersion: number;
  project: OpenCodeEditorNativeProjectContext;
  script: OpenCodeEditorScriptContext;
  scene: OpenCodeEditorSceneContext;
}

interface OpenCodeEditorNativeError {
  code: string;
  summary: string;
  retryable: boolean;
}

interface OpenCodeEditorNativeEnvelope {
  version: number;
  requestId: string;
  ok: boolean;
  result?: OpenCodeEditorContextNativeSnapshot;
  error?: OpenCodeEditorNativeError;
}

export interface OpenCodeEditorAuthorizedProjectContext {
  available: boolean;
  authorized: boolean;
  name: string;
  root: string;
}

export interface OpenCodeEditorContextSnapshot {
  contextVersion: number;
  capturedAtMs: number;
  project: OpenCodeEditorAuthorizedProjectContext;
  script: OpenCodeEditorScriptContext;
  scene: OpenCodeEditorSceneContext;
}

export interface OpenCodeEditorContextResult {
  contextVersion: number;
  capturedAtMs: number;
  kind: string;
  available: boolean;
  value: Object;
}

export class OpenCodeEditorContextContractError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, summary: string, retryable: boolean = false) {
    super(summary);
    this.code = code;
    this.retryable = retryable;
  }
}

export function parseOpenCodeEditorContextResponse(rawResponse: string,
  expectedRequestId: string, authorizedProjectRoot: string): OpenCodeEditorContextSnapshot {
  if (rawResponse.length === 0 || rawResponse.length > MAX_NATIVE_RESPONSE_LENGTH) {
    throw new OpenCodeEditorContextContractError(
      'CONTEXT_RESPONSE_INVALID',
      'The native editor context response is empty or too large'
    );
  }
  requireAuthorizedRoot(authorizedProjectRoot);

  let document: OpenCodeEditorNativeEnvelope;
  try {
    document = JSON.parse(rawResponse) as OpenCodeEditorNativeEnvelope;
  } catch (_) {
    throw new OpenCodeEditorContextContractError(
      'CONTEXT_RESPONSE_INVALID',
      'The native editor context response is not valid JSON'
    );
  }
  if (document.version !== OPENCODE_EDITOR_CONTEXT_VERSION ||
    document.requestId !== expectedRequestId || typeof document.ok !== 'boolean') {
    throw new OpenCodeEditorContextContractError(
      'CONTEXT_RESPONSE_INVALID',
      'The native editor context response does not match the request'
    );
  }
  if (!document.ok) {
    const error = document.error;
    if (error === undefined || !isBoundedToken(error.code, 64) ||
      !isBoundedText(error.summary, 160) || typeof error.retryable !== 'boolean') {
      throw new OpenCodeEditorContextContractError(
        'CONTEXT_RESPONSE_INVALID',
        'The native editor context error is invalid'
      );
    }
    throw new OpenCodeEditorContextContractError(error.code, error.summary, error.retryable);
  }

  const nativeSnapshot = document.result;
  if (nativeSnapshot === undefined ||
    nativeSnapshot.contextVersion !== OPENCODE_EDITOR_CONTEXT_VERSION) {
    throw new OpenCodeEditorContextContractError(
      'CONTEXT_RESPONSE_INVALID',
      'The native editor context snapshot is unavailable'
    );
  }
  validateProject(nativeSnapshot.project);
  validateScript(nativeSnapshot.script);
  validateScene(nativeSnapshot.scene);

  const project: OpenCodeEditorAuthorizedProjectContext = {
    available: nativeSnapshot.project.available,
    authorized: true,
    name: nativeSnapshot.project.name === undefined ? '' : nativeSnapshot.project.name,
    root: authorizedProjectRoot
  };
  const snapshot: OpenCodeEditorContextSnapshot = {
    contextVersion: OPENCODE_EDITOR_CONTEXT_VERSION,
    capturedAtMs: Date.now(),
    project: project,
    script: nativeSnapshot.script,
    scene: nativeSnapshot.scene
  };
  return snapshot;
}

export function selectOpenCodeEditorContext(method: OpenCodeEditorContextMethod,
  snapshot: OpenCodeEditorContextSnapshot): Object {
  if (method === 'context.snapshot') return snapshot;

  let available: boolean = false;
  let value: Object;
  let kind: string;
  if (method === 'context.active-project') {
    kind = 'active-project';
    available = snapshot.project.available;
    value = snapshot.project;
  } else if (method === 'context.active-script') {
    kind = 'active-script';
    available = snapshot.script.available;
    value = snapshot.script;
  } else if (method === 'context.selection') {
    kind = 'selection';
    const selection = snapshot.script.selection;
    available = selection !== undefined && selection.available;
    value = selection === undefined ? unavailableValue() : selection;
  } else if (method === 'context.active-scene') {
    kind = 'active-scene';
    available = snapshot.scene.available;
    const sceneValue: OpenCodeEditorSceneContext = {
      available: snapshot.scene.available,
      path: snapshot.scene.path
    };
    value = sceneValue;
  } else if (method === 'context.scene-tree') {
    kind = 'scene-tree';
    available = snapshot.scene.available;
    const treeValue: OpenCodeEditorSceneContext = {
      available: snapshot.scene.available,
      path: snapshot.scene.path,
      nodes: snapshot.scene.nodes,
      treeTruncated: snapshot.scene.treeTruncated
    };
    value = treeValue;
  } else if (method === 'context.selected-node') {
    kind = 'selected-node';
    const selectedNode = snapshot.scene.selectedNode;
    available = selectedNode !== undefined && selectedNode.available;
    value = selectedNode === undefined ? unavailableValue() : selectedNode;
  } else {
    kind = 'resource-references';
    const references = snapshot.scene.resourceReferences;
    available = snapshot.scene.available;
    const resourceValue: OpenCodeEditorResourceListContext = {
      available: snapshot.scene.available,
      truncated: snapshot.scene.selectedNode?.resourceReferencesTruncated === true,
      references: references === undefined ? [] : references
    };
    value = resourceValue;
  }

  const result: OpenCodeEditorContextResult = {
    contextVersion: snapshot.contextVersion,
    capturedAtMs: snapshot.capturedAtMs,
    kind: kind,
    available: available,
    value: value
  };
  return result;
}

interface OpenCodeEditorResourceListContext {
  available: boolean;
  truncated: boolean;
  references: OpenCodeEditorResourceReferenceContext[];
}

interface OpenCodeEditorUnavailableValue {
  available: boolean;
}

function unavailableValue(): OpenCodeEditorUnavailableValue {
  const value: OpenCodeEditorUnavailableValue = { available: false };
  return value;
}

function validateProject(project: OpenCodeEditorNativeProjectContext): void {
  if (project === undefined || typeof project.available !== 'boolean' ||
    (project.name !== undefined && !isBoundedText(project.name, MAX_CONTEXT_NAME_LENGTH)) ||
    (project.resourcePath !== undefined && !isBoundedText(project.resourcePath, MAX_CONTEXT_PATH_LENGTH))) {
    invalidSnapshot();
  }
}

function validateScript(script: OpenCodeEditorScriptContext): void {
  if (script === undefined || typeof script.available !== 'boolean' ||
    (script.path !== undefined && !isBoundedText(script.path, MAX_CONTEXT_PATH_LENGTH))) {
    invalidSnapshot();
  }
  if (script.cursor !== undefined &&
    (!isNonNegativeInteger(script.cursor.line) || !isNonNegativeInteger(script.cursor.column))) {
    invalidSnapshot();
  }
  const selection = script.selection;
  if (selection === undefined) return;
  if (typeof selection.available !== 'boolean' || typeof selection.truncated !== 'boolean' ||
    (selection.text !== undefined && !isBoundedText(selection.text, MAX_SELECTION_LENGTH)) ||
    !isOptionalNonNegativeInteger(selection.fromLine) ||
    !isOptionalNonNegativeInteger(selection.fromColumn) ||
    !isOptionalNonNegativeInteger(selection.toLine) ||
    !isOptionalNonNegativeInteger(selection.toColumn)) {
    invalidSnapshot();
  }
}

function validateScene(scene: OpenCodeEditorSceneContext): void {
  if (scene === undefined || typeof scene.available !== 'boolean' ||
    (scene.path !== undefined && !isBoundedText(scene.path, MAX_CONTEXT_PATH_LENGTH)) ||
    (scene.treeTruncated !== undefined && typeof scene.treeTruncated !== 'boolean')) {
    invalidSnapshot();
  }
  const nodes = scene.nodes;
  if (nodes !== undefined) {
    if (!Array.isArray(nodes) || nodes.length > MAX_SCENE_NODES) invalidSnapshot();
    for (const node of nodes) {
      if (!isBoundedText(node.name, MAX_CONTEXT_NAME_LENGTH) ||
        !isBoundedText(node.type, MAX_CONTEXT_NAME_LENGTH) ||
        !isBoundedText(node.path, MAX_CONTEXT_PATH_LENGTH) ||
        !node.path.startsWith('/') || !isNonNegativeInteger(node.depth) ||
        !isNonNegativeInteger(node.childCount)) {
        invalidSnapshot();
      }
    }
  }
  const selected = scene.selectedNode;
  if (selected !== undefined &&
    (typeof selected.available !== 'boolean' ||
      (selected.name !== undefined && !isBoundedText(selected.name, MAX_CONTEXT_NAME_LENGTH)) ||
      (selected.type !== undefined && !isBoundedText(selected.type, MAX_CONTEXT_NAME_LENGTH)) ||
      (selected.path !== undefined &&
        (!isBoundedText(selected.path, MAX_CONTEXT_PATH_LENGTH) || !selected.path.startsWith('/'))) ||
      (selected.scriptPath !== undefined && !isBoundedText(selected.scriptPath, MAX_CONTEXT_PATH_LENGTH)) ||
      (selected.resourceReferencesTruncated !== undefined &&
        typeof selected.resourceReferencesTruncated !== 'boolean'))) {
    invalidSnapshot();
  }
  const references = scene.resourceReferences;
  if (references === undefined) return;
  if (!Array.isArray(references) || references.length > MAX_RESOURCE_REFERENCES) invalidSnapshot();
  for (const reference of references) {
    if (!isBoundedText(reference.property, MAX_CONTEXT_NAME_LENGTH) ||
      !isBoundedText(reference.type, MAX_CONTEXT_NAME_LENGTH) ||
      !isBoundedText(reference.path, MAX_CONTEXT_PATH_LENGTH)) {
      invalidSnapshot();
    }
  }
}

function requireAuthorizedRoot(root: string): void {
  if (!root.startsWith('/') || root.length > MAX_PROJECT_ROOT_LENGTH ||
    root.includes('\0') || root.includes('\r') || root.includes('\n')) {
    throw new OpenCodeEditorContextContractError(
      'CONTEXT_PROJECT_UNAUTHORIZED',
      'The authorized project root is unavailable'
    );
  }
}

function invalidSnapshot(): never {
  throw new OpenCodeEditorContextContractError(
    'CONTEXT_RESPONSE_INVALID',
    'The native editor context snapshot contains invalid fields'
  );
}

function isBoundedToken(value: string, limit: number): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= limit &&
    /^[A-Z0-9_]+$/.test(value);
}

function isBoundedText(value: string, limit: number): boolean {
  return typeof value === 'string' && value.length <= limit && !value.includes('\0');
}

function isNonNegativeInteger(value: number): boolean {
  return Number.isInteger(value) && value >= 0;
}

function isOptionalNonNegativeInteger(value: number | undefined): boolean {
  return value === undefined || isNonNegativeInteger(value);
}
