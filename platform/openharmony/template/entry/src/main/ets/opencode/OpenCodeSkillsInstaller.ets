import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';

const SKILLS_RAWFILE_ROOT = 'opencode_skills';
const SKILLS_MANIFEST = `${SKILLS_RAWFILE_ROOT}/skills-manifest.json`;
const SKILLS_PACKAGE_ID = 'harmony-i3dact-skills-v1';
const SKILLS_INSTALL_ROOT = 'opencode-formal/v1/home/.agents/skills';
const SKILLS_STATE_FILE = '.opencode-skills-state.json';
const SKILLS_MAX_FILES = 4096;
const SKILLS_MAX_BYTES = 32 * 1024 * 1024;
const SKILLS_WRITE_CHUNK_BYTES = 1024 * 1024;
const HILOG_DOMAIN = 0xA0FF;
const HILOG_TAG = 'OpenCodeSkills';

interface SkillsPackageFile {
  path: string;
  bytes: number;
  sha256: string;
}

interface SkillsPackageManifest {
  schemaVersion: number;
  packageID: string;
  rawfileRoot: string;
  skillsSubdir: string;
  installRoot: string;
  outputSha256: string;
  bytes: number;
  files: Array<SkillsPackageFile>;
}

interface SkillsPackageState {
  schemaVersion: number;
  packageID: string;
  outputSha256: string;
  files: number;
  bytes: number;
}

export interface OpenCodeSkillsInstallResult {
  installRoot: string;
  outputSha256: string;
  files: number;
  bytes: number;
  reused: boolean;
}

export class OpenCodeSkillsInstallerError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * Installs the prepackaged HarmonyOS Tier-A skill set into the formal
 * runtime's global home (.agents/skills) so every authorized project
 * discovers the same preinstalled skills at startup. Mirrors the formal
 * asset installer's staging + completion-marker contract: an interrupted
 * install is never accepted as current state. Install failures are
 * reported to the caller; they never block the runtime itself.
 */
export class OpenCodeSkillsInstaller {
  private readonly context: common.UIAbilityContext;
  private preparation?: Promise<OpenCodeSkillsInstallResult>;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  prepare(): Promise<OpenCodeSkillsInstallResult> {
    if (this.preparation !== undefined) return this.preparation;
    const preparation = this.install();
    this.preparation = preparation;
    preparation.catch((): void => {
      if (this.preparation === preparation) this.preparation = undefined;
    });
    return preparation;
  }

  private async install(): Promise<OpenCodeSkillsInstallResult> {
    const manifest = await this.readManifest();
    const installRoot = `${this.context.filesDir}/${SKILLS_INSTALL_ROOT}`;
    if (this.isCurrentInstall(installRoot, manifest)) {
      return this.result(installRoot, manifest, true);
    }

    const stagingRoot = `${installRoot}.staging`;
    try {
      this.removeTreeIfPresent(stagingRoot);
      try {
        fs.mkdirSync(stagingRoot, true);
      } catch (_) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_STAGING_CREATE_FAILED',
          'The skills staging directory could not be created'
        );
      }
      const preparedDirectories: Set<string> = new Set();
      preparedDirectories.add(stagingRoot);
      for (const file of manifest.files) {
        await this.copyPackagedFile(manifest, file, stagingRoot, preparedDirectories);
      }
      this.writePackageState(stagingRoot, manifest);
      this.removeTreeIfPresent(installRoot);
      try {
        fs.renameSync(stagingRoot, installRoot);
      } catch (_) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_PROMOTE_FAILED',
          'The staged skills package could not be promoted'
        );
      }
      if (!this.isCurrentInstall(installRoot, manifest)) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_INSTALL_VERIFY_FAILED',
          'The installed skills package could not be verified'
        );
      }
      hilog.info(HILOG_DOMAIN, HILOG_TAG,
        'SKILLS_INSTALL_OK files=%{public}d bytes=%{public}d',
        manifest.files.length, manifest.bytes);
      return this.result(installRoot, manifest, false);
    } catch (error) {
      try {
        this.removeTreeIfPresent(stagingRoot);
      } catch (_) {
        // Preserve the authoritative installation error.
      }
      if (error instanceof OpenCodeSkillsInstallerError) throw error;
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_INSTALL_FAILED',
        'The packaged Harmony skills could not be installed'
      );
    }
  }

  private async readManifest(): Promise<SkillsPackageManifest> {
    let document: SkillsPackageManifest;
    try {
      const bytes = await this.context.resourceManager.getRawFileContent(
        SKILLS_MANIFEST);
      const source = util.TextDecoder.create('utf-8', {
        fatal: true,
        ignoreBOM: false
      }).decodeToString(bytes);
      document = JSON.parse(source) as SkillsPackageManifest;
    } catch (_) {
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_MANIFEST_UNAVAILABLE',
        'The packaged skills manifest is missing or invalid'
      );
    }
    this.validateManifest(document);
    return document;
  }

  private validateManifest(manifest: SkillsPackageManifest): void {
    if (manifest.schemaVersion !== 1 ||
      manifest.packageID !== SKILLS_PACKAGE_ID ||
      manifest.rawfileRoot !== SKILLS_RAWFILE_ROOT ||
      manifest.skillsSubdir !== 'harmony' ||
      manifest.installRoot !== SKILLS_INSTALL_ROOT ||
      !this.isSha256(manifest.outputSha256) ||
      !Number.isSafeInteger(manifest.bytes) ||
      manifest.bytes <= 0 ||
      manifest.bytes > SKILLS_MAX_BYTES ||
      !Array.isArray(manifest.files) ||
      manifest.files.length <= 0 ||
      manifest.files.length > SKILLS_MAX_FILES) {
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_MANIFEST_REJECTED',
        'The packaged skills manifest violates the install contract'
      );
    }
    let totalBytes = 0;
    const paths: Set<string> = new Set();
    const skillRoots: Set<string> = new Set();
    for (const file of manifest.files) {
      if (!this.isAcceptedPackagePath(file.path) ||
        !Number.isSafeInteger(file.bytes) ||
        file.bytes < 0 ||
        !this.isSha256(file.sha256) ||
        paths.has(file.path)) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_MANIFEST_REJECTED',
          'A packaged skills file entry is invalid'
        );
      }
      paths.add(file.path);
      totalBytes += file.bytes;
      const top = file.path.split('/')[0];
      if (top !== undefined) skillRoots.add(top);
    }
    if (totalBytes !== manifest.bytes) {
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_MANIFEST_REJECTED',
        'The packaged skills byte total does not match the manifest'
      );
    }
    for (const root of skillRoots) {
      if (!paths.has(`${root}/SKILL.md`) && root !== 'ADAPTATION-NOTES.md') {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_MANIFEST_REJECTED',
          'A packaged skill directory is missing its SKILL.md'
        );
      }
    }
  }

  private async copyPackagedFile(manifest: SkillsPackageManifest,
    file: SkillsPackageFile, stagingRoot: string,
    preparedDirectories: Set<string>): Promise<void> {
    const rawfilePath =
      `${SKILLS_RAWFILE_ROOT}/${manifest.skillsSubdir}/${file.path}`;
    let content: Uint8Array;
    try {
      content = await this.context.resourceManager.getRawFileContent(
        rawfilePath);
    } catch (_) {
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_RESOURCE_MISSING',
        'A declared skills resource is unavailable'
      );
    }
    if (content.byteLength !== file.bytes) {
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_RESOURCE_SIZE_MISMATCH',
        'A declared skills resource has an unexpected size'
      );
    }
    const destination = `${stagingRoot}/${file.path}`;
    const directory = destination.substring(0, destination.lastIndexOf('/'));
    if (!preparedDirectories.has(directory)) {
      try {
        fs.mkdirSync(directory, true);
        preparedDirectories.add(directory);
      } catch (error) {
        if (this.isExistingDirectory(directory)) {
          preparedDirectories.add(directory);
        } else {
          throw new OpenCodeSkillsInstallerError(
            'SKILLS_DIR_CREATE_FAILED',
            'A skills resource directory could not be created'
          );
        }
      }
    }
    let opened: fs.File;
    try {
      opened = fs.openSync(destination,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    } catch (_) {
      throw new OpenCodeSkillsInstallerError(
        'SKILLS_RESOURCE_OPEN_FAILED',
        'A skills resource could not be opened for writing'
      );
    }
    let writeFailure: OpenCodeSkillsInstallerError | undefined;
    try {
      this.writePackagedContent(opened.fd, content);
    } catch (error) {
      writeFailure = error instanceof OpenCodeSkillsInstallerError ?
        error :
        new OpenCodeSkillsInstallerError(
          'SKILLS_RESOURCE_WRITE_FAILED',
          'A skills resource could not be written'
        );
    }
    try {
      fs.closeSync(opened);
    } catch (_) {
      if (writeFailure === undefined) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_RESOURCE_CLOSE_FAILED',
          'A skills resource could not be closed'
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

  private writePackagedContent(fd: number, content: Uint8Array): void {
    let offset = 0;
    while (offset < content.byteLength) {
      const end = Math.min(
        offset + SKILLS_WRITE_CHUNK_BYTES, content.byteLength);
      const chunk = content.slice(offset, end);
      let written: number;
      try {
        written = fs.writeSync(fd, chunk.buffer, {
          offset: offset,
          length: chunk.byteLength
        });
      } catch (_) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_RESOURCE_WRITE_FAILED',
          'A skills resource could not be written'
        );
      }
      if (!Number.isSafeInteger(written) ||
        written <= 0 ||
        written > chunk.byteLength) {
        throw new OpenCodeSkillsInstallerError(
          'SKILLS_RESOURCE_WRITE_INCOMPLETE',
          'A skills resource was not written completely'
        );
      }
      offset += written;
    }
  }

  private writePackageState(stagingRoot: string,
    manifest: SkillsPackageManifest): void {
    const state: SkillsPackageState = {
      schemaVersion: 1,
      packageID: manifest.packageID,
      outputSha256: manifest.outputSha256,
      files: manifest.files.length,
      bytes: manifest.bytes
    };
    const filename = `${stagingRoot}/${SKILLS_STATE_FILE}`;
    const opened = fs.openSync(filename,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(opened.fd, JSON.stringify(state));
    } finally {
      fs.closeSync(opened);
    }
  }

  private isCurrentInstall(installRoot: string,
    manifest: SkillsPackageManifest): boolean {
    try {
      const source = fs.readTextSync(`${installRoot}/${SKILLS_STATE_FILE}`);
      const state = JSON.parse(source) as SkillsPackageState;
      if (state.schemaVersion !== 1 ||
        state.packageID !== manifest.packageID ||
        state.outputSha256 !== manifest.outputSha256 ||
        state.files !== manifest.files.length ||
        state.bytes !== manifest.bytes) {
        return false;
      }
      fs.accessSync(`${installRoot}/i3dact-api/SKILL.md`);
      fs.accessSync(`${installRoot}/i3dact-gen/SKILL.md`);
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
    if (value.length === 0 ||
      value.startsWith('/') ||
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

  private result(installRoot: string, manifest: SkillsPackageManifest,
    reused: boolean): OpenCodeSkillsInstallResult {
    return {
      installRoot,
      outputSha256: manifest.outputSha256,
      files: manifest.files.length,
      bytes: manifest.bytes,
      reused
    };
  }
}
