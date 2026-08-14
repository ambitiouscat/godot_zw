import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileShare, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { Logger } from './Logger';

const logger = new Logger('GODOT_FS')
const PREF_NAME = 'godot_external_dirs'

interface RecentDirectoryEntry {
  uri: string
  path: string
  timestamp: string
}

export class FileManager {
  private context: common.UIAbilityContext
  private externalProjectDir: string = ''

  constructor(context: common.UIAbilityContext) {
    this.context = context
  }

  /**
   * Get the default project directory path based on device type.
   * - 2in1 (PC): return empty string — let C++ use OH_Environment path directly
   * - phone/tablet: return sandbox path (only native-accessible dir)
   */
  getDefaultProjectDir(): string {
    const deviceType: string = deviceInfo.deviceType
    if (deviceType === '2in1') {
      // PC mode - native code can access public directory directly
      return ''
    }
    // Mobile mode - use sandbox path for native code access
    const projectDir: string = this.context.getApplicationContext().filesDir + '/projects'
    logger.info('Mobile device, using sandbox project directory', projectDir)
    return projectDir
  }

  /**
   * Open folder picker for selecting an external project directory.
   * Uses DocumentViewPicker with selectMode:FOLDER to obtain write access
   * to directories outside the app sandbox.
   * Returns the selected directory path, or empty string if cancelled.
   */
  async pickFolder(): Promise<string> {
    try {
      let options = new picker.DocumentSelectOptions()
      options.selectMode = picker.DocumentSelectMode.FOLDER
      let pickerInstance = new picker.DocumentViewPicker(this.context)
      let uris = await pickerInstance.select(options)
      if (uris && uris.length > 0) {
        const folderUri: string = uris[0]
        logger.info('Folder selected', folderUri)
        this.externalProjectDir = folderUri
        return folderUri
      }
      return ''
    } catch (e) {
      logger.error('Folder picker error', e)
      return ''
    }
  }

  /**
   * Persist write permission for a folder URI across app restarts.
   * Also saves the URI to local Preferences for restoration on next launch.
   */
  async persistFolderPermission(uri: string): Promise<void> {
    try {
      let policyInfo: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
      }
      await fileShare.persistPermission([policyInfo])
      logger.info('Folder permission persisted', uri)
      await this.saveExternalDirUri(uri)
    } catch (e) {
      let bizErr = e as BusinessError
      logger.error('Failed to persist folder permission, code=' + bizErr.code, e)
    }
  }

  /**
   * Activate previously persisted permissions and restore saved URIs at startup.
   */
  async restorePersistedPermissions(): Promise<void> {
    try {
      // Restore saved URIs from Preferences
      let savedUris = await this.loadExternalDirUris()
      if (savedUris.length === 0) {
        logger.info('No persisted external directories found')
        return
      }
      // Build PolicyInfo array for activation
      let policies: fileShare.PolicyInfo[] = []
      for (const uri of savedUris) {
        policies.push({
          uri: uri,
          operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE,
        })
      }
      // Activate persisted permissions
      await fileShare.activatePermission(policies)
      logger.info('Persisted permissions activated', JSON.stringify(savedUris))
      // Use the first saved URI as project dir
      this.externalProjectDir = savedUris[0]
    } catch (e) {
      let bizErr = e as BusinessError
      logger.error('Failed to restore persisted permissions, code=' + bizErr.code, e)
    }
  }

  /**
   * Save an external directory URI to local Preferences.
   */
  private async saveExternalDirUri(uri: string): Promise<void> {
    try {
      let prefs = await preferences.getPreferences(this.context, PREF_NAME)
      let saved = await prefs.get('uris', '[]') as string
      let uris: string[] = JSON.parse(saved) as string[]
      if (uris.indexOf(uri) < 0) {
        uris.push(uri)
      }
      await prefs.put('uris', JSON.stringify(uris))
      await prefs.flush()
    } catch (e) {
      logger.error('Failed to save external dir URI', e)
    }
  }

  /**
   * Load saved external directory URIs from local Preferences.
   */
  private async loadExternalDirUris(): Promise<string[]> {
    try {
      let prefs = await preferences.getPreferences(this.context, PREF_NAME)
      let saved = await prefs.get('uris', '[]') as string
      return JSON.parse(saved) as string[]
    } catch (e) {
      logger.error('Failed to load external dir URIs', e)
      return []
    }
  }

  /**
   * Get the user-selected external project directory.
   */
  getExternalProjectDir(): string {
    return this.externalProjectDir
  }

  /**
   * Convert a file://docs/ or file://media/ URI to its POSIX-accessible physical path.
   * After persistPermission, the physical path is directly accessible via POSIX I/O,
   * completely bypassing the NAPI bridge for file operations.
   *
   * file://docs/storage/Users/currentUser/Desktop -> /storage/Users/currentUser/Desktop
   * file://media/... -> /media/...
   */
  toPhysicalPath(uri: string): string {
    if (uri.startsWith('file://docs/')) {
      return uri.substring(11) // strip 'file://docs' → '/storage/...'
    }
    if (uri.startsWith('file://media/')) {
      return uri.substring(12) // strip 'file://media' → '/media/...'
    }
    return uri // already a physical path or unknown format
  }

  /**
   * Unified file picker entry point.
   * mode: 0 = open, 1 = save
   */
  async pickFile(mode: number, title: string, defaultPath: string, filters: string): Promise<string[]> {
    try {
      if (mode === 1) {
        return await this.saveFile(title, defaultPath, filters);
      } else {
        return await this.openFile(title, filters);
      }
    } catch (e) {
      logger.error('File picker error', e)
      return []
    }
  }

  private async openFile(_title: string, filters: string): Promise<string[]> {
    let selectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = 1;

    if (filters) {
      const suffixFilters = this.parseFilters(filters);
      if (suffixFilters.length > 0) {
        selectOptions.fileSuffixFilters = suffixFilters;
      }
    }

    let pickerInstance = new picker.DocumentViewPicker(this.context);
    let uris = await pickerInstance.select(selectOptions);
    return uris || [];
  }

  private async saveFile(_title: string, defaultName: string, filters: string): Promise<string[]> {
    let saveOptions = new picker.DocumentSaveOptions();

    if (defaultName) {
      saveOptions.newFileNames = [defaultName];
    }

    if (filters) {
      const suffixFilters = this.parseFilters(filters);
      if (suffixFilters.length > 0) {
        saveOptions.fileSuffixChoices = suffixFilters;
      }
    }

    let pickerInstance = new picker.DocumentViewPicker(this.context);
    let uris = await pickerInstance.save(saveOptions);
    return uris || [];
  }

  private parseFilters(filters: string): string[] {
    if (!filters) {
      return [];
    }

    const filterList = filters.split(',');
    const suffixes: string[] = [];

    for (const f of filterList) {
      const match = f.match(/\.(\w+)/);
      if (match && match[1]) {
        suffixes.push(match[1]);
      }
    }

    return suffixes;
  }

  /**
   * Add a directory to the recent directories list (max 10, deduped, newest first).
   * Stored in @ohos.data.preferences under key 'recent_directories'.
   */
  async addRecentDirectory(uri: string, physicalPath: string): Promise<void> {
    try {
      let prefs = await preferences.getPreferences(this.context, PREF_NAME)
      let saved = await prefs.get('recent_directories', '[]') as string
      let dirs: RecentDirectoryEntry[] = JSON.parse(saved) as RecentDirectoryEntry[]
      // Remove duplicate by physical path
      dirs = dirs.filter(d => d.path !== physicalPath)
      // Add to front
      let entry: RecentDirectoryEntry = { uri: uri, path: physicalPath, timestamp: new Date().toISOString() }
      dirs.unshift(entry)
      // Trim to max 10
      if (dirs.length > 10) {
        dirs = dirs.slice(0, 10)
      }
      await prefs.put('recent_directories', JSON.stringify(dirs))
      await prefs.flush()
    } catch (e) {
      logger.error('Failed to save recent directory', e)
    }
  }
}
