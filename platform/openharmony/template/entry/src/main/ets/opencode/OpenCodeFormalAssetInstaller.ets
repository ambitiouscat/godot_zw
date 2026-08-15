import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { OPENCODE_HARMONY_CLIENT_SELECTION } from './OpenCodeSpikeBuildConfig';

const FORMAL_RAWFILE_ROOT = 'opencode_formal';
const FORMAL_PACKAGE_MANIFEST =
  `${FORMAL_RAWFILE_ROOT}/package-manifest.json`;
const FORMAL_PACKAGE_ID = 'opencode-formal-harmony-tier-a-v1';
const FORMAL_PACKAGE_INSTALL_ROOT = 'opencode-formal/install/v1';
const FORMAL_PACKAGE_FILES_PREFIX = 'install/v1/';
const FORMAL_PACKAGE_STATE_FILE = '.opencode-formal-package-state.json';
const FORMAL_PACKAGE_MAX_FILES = 4096;
const FORMAL_PACKAGE_MAX_BYTES = 128 * 1024 * 1024;
const FORMAL_ASSET_WRITE_CHUNK_BYTES = 1024 * 1024;

interface FormalPackageFile {
  path: string;
  bytes: number;
  sha256: string;
}

interface FormalPackageSelections {
  runtime: string;
  client: string;
  capabilityProfile: string;
}

interface FormalPackageManifest {
  schemaVersion: number;
  packageID: string;
  installRoot: string;
  rawfileRoot: string;
  outputSha256: string;
  bytes: number;
  selections: FormalPackageSelections;
  files: Array<FormalPackageFile>;
}

interface FormalPackageState {
  schemaVersion: number;
  packageID: string;
  outputSha256: string;
  files: number;
  bytes: number;
}

interface PlatformFileError {
  code?: number;
}

export interface OpenCodeFormalAssetInstallResult {
  installRoot: string;
  packageID: string;
  outputSha256: string;
  files: number;
  bytes: number;
  reused: boolean;
}

export class OpenCodeFormalAssetInstallerError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * Copies the deterministic formal rawfile package into application-private
 * storage. The completion marker is written last inside a staging directory,
 * so an interrupted install is never accepted as runnable state.
 */
export class OpenCodeFormalAssetInstaller {
  private readonly context: common.UIAbilityContext;
  private preparation?: Promise<OpenCodeFormalAssetInstallResult>;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  prepare(): Promise<OpenCodeFormalAssetInstallResult> {
    if (this.preparation !== undefined) return this.preparation;
    const preparation = this.install();
    this.preparation = preparation;
    preparation.catch((): void => {
      if (this.preparation === preparation) this.preparation = undefined;
    });
    return preparation;
  }

  private async install(): Promise<OpenCodeFormalAssetInstallResult> {
    const manifest = await this.readManifest();
    const installRoot =
      `${this.context.filesDir}/${FORMAL_PACKAGE_INSTALL_ROOT}`;
    if (this.isCurrentInstall(installRoot, manifest)) {
      return this.result(installRoot, manifest, true);
    }

    const stagingRoot = `${installRoot}.staging`;
    try {
      this.removeTreeIfPresent(stagingRoot);
      try {
        fs.mkdirSync(stagingRoot, true);
      } catch (_) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_STAGING_CREATE_FAILED',
          'The formal OpenCode staging directory could not be created'
        );
      }
      const preparedDirectories: Set<string> = new Set();
      preparedDirectories.add(stagingRoot);
      for (const file of manifest.files) {
        await this.copyPackagedFile(
          file, stagingRoot, preparedDirectories);
      }
      this.writePackageState(stagingRoot, manifest);
      this.removeTreeIfPresent(installRoot);
      try {
        fs.renameSync(stagingRoot, installRoot);
      } catch (_) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_PROMOTE_FAILED',
          'The staged formal OpenCode package could not be promoted'
        );
      }
      if (!this.isCurrentInstall(installRoot, manifest)) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_INSTALL_VERIFY_FAILED',
          'The installed formal OpenCode package could not be verified'
        );
      }
      return this.result(installRoot, manifest, false);
    } catch (error) {
      try {
        this.removeTreeIfPresent(stagingRoot);
      } catch (_) {
        // Preserve the authoritative installation error.
      }
      if (error instanceof OpenCodeFormalAssetInstallerError) throw error;
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_INSTALL_FAILED',
        'The packaged formal OpenCode resources could not be installed'
      );
    }
  }

  private async readManifest(): Promise<FormalPackageManifest> {
    let document: FormalPackageManifest;
    try {
      const bytes = await this.context.resourceManager.getRawFileContent(
        FORMAL_PACKAGE_MANIFEST);
      const source = util.TextDecoder.create('utf-8', {
        fatal: true,
        ignoreBOM: false
      }).decodeToString(bytes);
      document = JSON.parse(source) as FormalPackageManifest;
    } catch (_) {
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_MANIFEST_UNAVAILABLE',
        'The packaged formal OpenCode manifest is missing or invalid'
      );
    }
    this.validateManifest(document);
    return document;
  }

  private validateManifest(manifest: FormalPackageManifest): void {
    if (manifest.schemaVersion !== 1 ||
      manifest.packageID !== FORMAL_PACKAGE_ID ||
      manifest.installRoot !== FORMAL_PACKAGE_INSTALL_ROOT ||
      manifest.rawfileRoot !== FORMAL_RAWFILE_ROOT ||
      manifest.selections?.runtime !== 'formal-upstream' ||
      manifest.selections?.client !== OPENCODE_HARMONY_CLIENT_SELECTION ||
      (manifest.selections.client !== 'sdk-composed' &&
        manifest.selections.client !== 'upstream-solidjs') ||
      manifest.selections?.capabilityProfile !== 'harmony-tier-a' ||
      !this.isSha256(manifest.outputSha256) ||
      !Number.isSafeInteger(manifest.bytes) ||
      manifest.bytes <= 0 ||
      manifest.bytes > FORMAL_PACKAGE_MAX_BYTES ||
      !Array.isArray(manifest.files) ||
      manifest.files.length <= 0 ||
      manifest.files.length > FORMAL_PACKAGE_MAX_FILES) {
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_MANIFEST_REJECTED',
        'The packaged formal OpenCode manifest violates the install contract'
      );
    }
    let totalBytes = 0;
    const paths: Set<string> = new Set();
    for (const file of manifest.files) {
      if (!this.isAcceptedPackagePath(file.path) ||
        !Number.isSafeInteger(file.bytes) ||
        file.bytes < 0 ||
        !this.isSha256(file.sha256) ||
        paths.has(file.path)) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_MANIFEST_REJECTED',
          'A packaged formal OpenCode file entry is invalid'
        );
      }
      paths.add(file.path);
      totalBytes += file.bytes;
      if (totalBytes > FORMAL_PACKAGE_MAX_BYTES) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_MANIFEST_REJECTED',
          'The packaged formal OpenCode resources exceed the size limit'
        );
      }
    }
    if (totalBytes !== manifest.bytes ||
      !paths.has('install/v1/runtime/opencode-harmony-runtime.mjs') ||
      !paths.has('install/v1/client/index.html') ||
      !paths.has('install/v1/config/AGENTS.md')) {
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_MANIFEST_REJECTED',
        'The packaged formal OpenCode resources are incomplete'
      );
    }
  }

  private async copyPackagedFile(file: FormalPackageFile,
    stagingRoot: string, preparedDirectories: Set<string>): Promise<void> {
    const relative = file.path.substring(FORMAL_PACKAGE_FILES_PREFIX.length);
    const rawfilePath = `${FORMAL_RAWFILE_ROOT}/${file.path}`;
    let content: Uint8Array;
    try {
      content = await this.context.resourceManager.getRawFileContent(
        rawfilePath);
    } catch (_) {
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_RESOURCE_MISSING',
        'A declared formal OpenCode resource is unavailable'
      );
    }
    if (content.byteLength !== file.bytes) {
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_RESOURCE_SIZE_MISMATCH',
        'A declared formal OpenCode resource has an unexpected size'
      );
    }
    const destination = `${stagingRoot}/${relative}`;
    const directory = destination.substring(0, destination.lastIndexOf('/'));
    if (!preparedDirectories.has(directory)) {
      try {
        fs.mkdirSync(directory, true);
        preparedDirectories.add(directory);
      } catch (error) {
        if (this.isExistingDirectory(directory)) {
          preparedDirectories.add(directory);
        } else {
          throw new OpenCodeFormalAssetInstallerError(
            this.directoryFailureCode(relative, error),
            'A formal OpenCode resource directory could not be created'
          );
        }
      }
    }
    let opened: fs.File;
    try {
      opened = fs.openSync(destination,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    } catch (_) {
      throw new OpenCodeFormalAssetInstallerError(
        'FORMAL_ASSET_RESOURCE_OPEN_FAILED',
        'A formal OpenCode resource could not be opened for writing'
      );
    }
    let writeFailure: OpenCodeFormalAssetInstallerError | undefined;
    try {
      this.writePackagedContent(opened.fd, content);
    } catch (error) {
      writeFailure = error instanceof OpenCodeFormalAssetInstallerError ?
        error :
        new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_RESOURCE_WRITE_FAILED',
          'A formal OpenCode resource could not be written'
        );
    }
    try {
      fs.closeSync(opened);
    } catch (_) {
      if (writeFailure === undefined) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_RESOURCE_CLOSE_FAILED',
          'A formal OpenCode resource could not be closed'
        );
      }
    }
    if (writeFailure !== undefined) throw writeFailure;
  }

  private isExistingDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (_) {
      return false;
    }
  }

  private directoryFailureCode(relative: string, error: Object): string {
    let prefix = 'FORMAL_ASSET_DIR_OTHER_E';
    if (relative.startsWith('client/assets/')) {
      prefix = 'FORMAL_ASSET_DIR_CLIENT_ASSETS_E';
    } else if (relative.startsWith('client/')) {
      prefix = 'FORMAL_ASSET_DIR_CLIENT_E';
    } else if (relative.startsWith('config/')) {
      prefix = 'FORMAL_ASSET_DIR_CONFIG_E';
    } else if (relative.startsWith('manifests/')) {
      prefix = 'FORMAL_ASSET_DIR_MANIFESTS_E';
    } else if (relative.startsWith('runtime/assets/')) {
      prefix = 'FORMAL_ASSET_DIR_RUNTIME_ASSETS_E';
    } else if (relative.startsWith('runtime/')) {
      prefix = 'FORMAL_ASSET_DIR_RUNTIME_E';
    }
    return `${prefix}${this.platformErrorCode(error)}`;
  }

  private platformErrorCode(error: Object): string {
    const candidate = error as PlatformFileError;
    const code = candidate.code;
    if (code !== undefined &&
      Number.isSafeInteger(code) &&
      code >= 0 &&
      code <= 99999999) {
      return String(code);
    }
    return 'UNKNOWN';
  }

  private writePackagedContent(fd: number, content: Uint8Array): void {
    let offset = 0;
    while (offset < content.byteLength) {
      const end = Math.min(
        offset + FORMAL_ASSET_WRITE_CHUNK_BYTES, content.byteLength);
      const chunk = content.slice(offset, end);
      let written: number;
      try {
        written = fs.writeSync(fd, chunk.buffer, {
          offset: offset,
          length: chunk.byteLength
        });
      } catch (_) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_RESOURCE_WRITE_FAILED',
          'A formal OpenCode resource could not be written'
        );
      }
      if (!Number.isSafeInteger(written) ||
        written <= 0 ||
        written > chunk.byteLength) {
        throw new OpenCodeFormalAssetInstallerError(
          'FORMAL_ASSET_RESOURCE_WRITE_INCOMPLETE',
          'A formal OpenCode resource was not written completely'
        );
      }
      offset += written;
    }
  }

  private writePackageState(stagingRoot: string,
    manifest: FormalPackageManifest): void {
    const state: FormalPackageState = {
      schemaVersion: 1,
      packageID: manifest.packageID,
      outputSha256: manifest.outputSha256,
      files: manifest.files.length,
      bytes: manifest.bytes
    };
    const filename = `${stagingRoot}/${FORMAL_PACKAGE_STATE_FILE}`;
    const opened = fs.openSync(filename,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(opened.fd, JSON.stringify(state));
    } finally {
      fs.closeSync(opened);
    }
  }

  private isCurrentInstall(installRoot: string,
    manifest: FormalPackageManifest): boolean {
    try {
      const source = fs.readTextSync(
        `${installRoot}/${FORMAL_PACKAGE_STATE_FILE}`);
      const state = JSON.parse(source) as FormalPackageState;
      if (state.schemaVersion !== 1 ||
        state.packageID !== manifest.packageID ||
        state.outputSha256 !== manifest.outputSha256 ||
        state.files !== manifest.files.length ||
        state.bytes !== manifest.bytes) {
        return false;
      }
      fs.accessSync(
        `${installRoot}/runtime/opencode-harmony-runtime.mjs`);
      fs.accessSync(`${installRoot}/client/index.html`);
      fs.accessSync(`${installRoot}/config/AGENTS.md`);
      return true;
    } catch (_) {
      return false;
    }
  }

  private removeTreeIfPresent(target: string): void {
    let stat: fs.Stat;
    try {
      stat = fs.statSync(target);
    } catch (_) {
      return;
    }
    if (!stat.isDirectory()) {
      fs.unlinkSync(target);
      return;
    }
    for (const child of fs.listFileSync(target)) {
      this.removeTreeIfPresent(`${target}/${child}`);
    }
    fs.rmdirSync(target);
  }

  private isAcceptedPackagePath(value: string): boolean {
    if (!value.startsWith(FORMAL_PACKAGE_FILES_PREFIX) ||
      value.length <= FORMAL_PACKAGE_FILES_PREFIX.length ||
      value.includes('\\') ||
      value.includes('\0') ||
      value.endsWith('.map')) {
      return false;
    }
    const parts = value.split('/');
    return parts.every((part: string): boolean =>
      part.length > 0 && part !== '.' && part !== '..');
  }

  private isSha256(value: string): boolean {
    return /^[a-f0-9]{64}$/.test(value);
  }

  private result(installRoot: string, manifest: FormalPackageManifest,
    reused: boolean): OpenCodeFormalAssetInstallResult {
    return {
      installRoot,
      packageID: manifest.packageID,
      outputSha256: manifest.outputSha256,
      files: manifest.files.length,
      bytes: manifest.bytes,
      reused
    };
  }
}
