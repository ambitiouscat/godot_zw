const CONTRACT_VERSION = 1;
const MAX_FILE_CHARS = 16 * 1024;
const MAX_DIFF_CHARS = 48 * 1024;
const ACCEPTANCE_MARKER = '# OPENCODE_HARMONY_ACCEPTANCE';
const PROPOSAL_ID_PATTERN = /^pat_[A-Za-z0-9_-]{24,96}$/;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;

interface AuthorizedFileDocument {
  path?: string;
  content?: string;
  sha256?: string;
}

interface AuthorizedProposalDocument {
  proposalID?: string;
  path?: string;
  diff?: string;
  beforeSha256?: string;
  afterSha256?: string;
}

interface AuthorizedAcceptanceDocument {
  proposalID?: string;
  path?: string;
  atomic?: boolean;
  beforeSha256?: string;
  afterSha256?: string;
}

interface AuthorizedRejectionDocument {
  proposalID?: string;
  path?: string;
  unchanged?: boolean;
  sha256?: string;
}

interface AuthorizedErrorDocument {
  error?: string;
}

export interface OpenCodeAuthorizedFileSnapshot {
  path: string;
  content: string;
  sha256: string;
}

export interface OpenCodeAuthorizedPatchPreparation {
  path: string;
  patchText: string;
}

export interface OpenCodeAuthorizedPatchProposal {
  version: number;
  proposalId: string;
  path: string;
  diff: string;
  beforeSha256: string;
  afterSha256: string;
}

export interface OpenCodeAuthorizedPatchAcceptance {
  version: number;
  proposalId: string;
  path: string;
  atomic: boolean;
  beforeSha256: string;
  afterSha256: string;
}

export interface OpenCodeAuthorizedPatchRejection {
  version: number;
  proposalId: string;
  path: string;
  unchanged: boolean;
  sha256: string;
}

export class OpenCodeAuthorizedPatchContractError extends Error {
  readonly code: string;

  constructor(code: string, summary: string) {
    super(summary);
    this.code = code;
  }
}

export function prepareOpenCodeAuthorizedPatch(path: string,
  content: string): OpenCodeAuthorizedPatchPreparation {
  requireRelativePath(path);
  if (content.length === 0 || content.length > MAX_FILE_CHARS || content.includes('\0')) {
    fail('HARMONY_AUTHORIZED_FILE_UNSUPPORTED',
      'The active script is outside the bounded acceptance size');
  }
  const eol = content.includes('\r\n') ? '\r\n' : '\n';
  const markerSuffix = `${ACCEPTANCE_MARKER}${eol}`;
  let nextContent: string;
  if (content.endsWith(markerSuffix)) {
    nextContent = content.substring(0, content.length - markerSuffix.length);
    if (nextContent.length === 0) {
      fail('HARMONY_AUTHORIZED_PATCH_EMPTY_OR_TOO_LARGE',
        'The acceptance patch cannot produce an empty script');
    }
  } else {
    const separator = content.endsWith('\n') ? '' : eol;
    nextContent = `${content}${separator}${markerSuffix}`;
  }
  if (nextContent.length > MAX_FILE_CHARS) {
    fail('HARMONY_AUTHORIZED_PATCH_EMPTY_OR_TOO_LARGE',
      'The acceptance patch exceeds the bounded script size');
  }
  const patchText = `*** Begin Patch\n*** Update File: ${path}\n@@\n` +
    `${prefixLines('-', content)}\n${prefixLines('+', nextContent)}\n*** End Patch\n`;
  if (patchText.length > MAX_DIFF_CHARS) {
    fail('HARMONY_AUTHORIZED_PATCH_TEXT_INVALID',
      'The acceptance patch exceeds the bounded bridge size');
  }
  return { path: path, patchText: patchText };
}

export function parseOpenCodeAuthorizedFile(raw: string,
  expectedPath: string): OpenCodeAuthorizedFileSnapshot {
  requireRelativePath(expectedPath);
  const document = parseDocument(raw) as AuthorizedFileDocument;
  if (document.path !== expectedPath || typeof document.content !== 'string' ||
    document.content.length === 0 || document.content.length > MAX_FILE_CHARS ||
    !isSha256(document.sha256)) {
    fail('HARMONY_AUTHORIZED_FILE_RESPONSE_INVALID',
      'OpenCode returned an invalid authorized file response');
  }
  return {
    path: document.path,
    content: document.content,
    sha256: document.sha256
  };
}

export function parseOpenCodeAuthorizedProposal(raw: string,
  expectedPath: string): OpenCodeAuthorizedPatchProposal {
  requireRelativePath(expectedPath);
  const document = parseDocument(raw) as AuthorizedProposalDocument;
  if (!isProposalId(document.proposalID) || document.path !== expectedPath ||
    typeof document.diff !== 'string' || document.diff.length === 0 ||
    document.diff.length > MAX_DIFF_CHARS || !isSha256(document.beforeSha256) ||
    !isSha256(document.afterSha256)) {
    fail('HARMONY_AUTHORIZED_PROPOSAL_RESPONSE_INVALID',
      'OpenCode returned an invalid bounded Diff proposal');
  }
  return {
    version: CONTRACT_VERSION,
    proposalId: document.proposalID,
    path: document.path,
    diff: document.diff,
    beforeSha256: document.beforeSha256,
    afterSha256: document.afterSha256
  };
}

export function parseOpenCodeAuthorizedAcceptance(raw: string, proposalId: string,
  expectedPath: string): OpenCodeAuthorizedPatchAcceptance {
  requireProposalId(proposalId);
  requireRelativePath(expectedPath);
  const document = parseDocument(raw) as AuthorizedAcceptanceDocument;
  if (document.proposalID !== proposalId || document.path !== expectedPath ||
    document.atomic !== true || !isSha256(document.beforeSha256) ||
    !isSha256(document.afterSha256)) {
    fail('HARMONY_AUTHORIZED_ACCEPT_RESPONSE_INVALID',
      'OpenCode returned an invalid atomic acceptance response');
  }
  return {
    version: CONTRACT_VERSION,
    proposalId: document.proposalID,
    path: document.path,
    atomic: true,
    beforeSha256: document.beforeSha256,
    afterSha256: document.afterSha256
  };
}

export function parseOpenCodeAuthorizedRejection(raw: string, proposalId: string,
  expectedPath: string): OpenCodeAuthorizedPatchRejection {
  requireProposalId(proposalId);
  requireRelativePath(expectedPath);
  const document = parseDocument(raw) as AuthorizedRejectionDocument;
  if (document.proposalID !== proposalId || document.path !== expectedPath ||
    document.unchanged !== true || !isSha256(document.sha256)) {
    fail('HARMONY_AUTHORIZED_REJECT_RESPONSE_INVALID',
      'OpenCode returned an invalid patch rejection response');
  }
  return {
    version: CONTRACT_VERSION,
    proposalId: document.proposalID,
    path: document.path,
    unchanged: true,
    sha256: document.sha256
  };
}

export function parseOpenCodeAuthorizedError(raw: string): string {
  try {
    const document = JSON.parse(raw) as AuthorizedErrorDocument;
    if (typeof document.error === 'string' &&
      /^HARMONY_AUTHORIZED_[A-Z0-9_]{1,48}$/.test(document.error)) {
      return document.error;
    }
  } catch (_) {
    // Return the fixed bounded fallback below.
  }
  return 'HARMONY_AUTHORIZED_REQUEST_FAILED';
}

export function requireOpenCodeAuthorizedProposalId(value: string): string {
  requireProposalId(value);
  return value;
}

export function requireOpenCodeAuthorizedPath(value: string): string {
  requireRelativePath(value);
  return value;
}

function prefixLines(prefix: string, content: string): string {
  const withoutTerminalNewline = content.endsWith('\n') ?
    content.substring(0, content.length - 1) : content;
  return withoutTerminalNewline.split('\n').map((line: string): string => {
    return `${prefix}${line}`;
  }).join('\n');
}

function parseDocument(raw: string): Object {
  if (raw.length === 0 || raw.length > 64 * 1024) {
    fail('HARMONY_AUTHORIZED_RESPONSE_INVALID',
      'OpenCode returned an invalid authorized patch response');
  }
  try {
    const document = JSON.parse(raw) as Object;
    if (document === null || Array.isArray(document)) {
      fail('HARMONY_AUTHORIZED_RESPONSE_INVALID',
        'OpenCode returned an invalid authorized patch response');
    }
    return document;
  } catch (error) {
    if (error instanceof OpenCodeAuthorizedPatchContractError) throw error;
    fail('HARMONY_AUTHORIZED_RESPONSE_INVALID',
      'OpenCode returned an invalid authorized patch response');
  }
}

function requireRelativePath(value: string): void {
  if (typeof value !== 'string' || value.length === 0 || value.length > 512 ||
    value.startsWith('/') || value.includes('\\') || value.includes('\0') ||
    value.includes(':') || value.split('/').some((part: string): boolean => {
      return part.length === 0 || part === '.' || part === '..';
    })) {
    fail('HARMONY_AUTHORIZED_PATH_INVALID', 'The authorized script path is invalid');
  }
}

function requireProposalId(value: string): void {
  if (!isProposalId(value)) {
    fail('HARMONY_AUTHORIZED_PATCH_ID_INVALID', 'The authorized patch identifier is invalid');
  }
}

function isProposalId(value: string | undefined): value is string {
  return typeof value === 'string' && PROPOSAL_ID_PATTERN.test(value);
}

function isSha256(value: string | undefined): value is string {
  return typeof value === 'string' && SHA256_PATTERN.test(value);
}

function fail(code: string, summary: string): never {
  throw new OpenCodeAuthorizedPatchContractError(code, summary);
}
