import { common, Want } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import plugin from 'libentry.so';
import { CursorManager } from './CursorManager';
import { FileManager } from './FileManager';
import { SensorManager } from './SensorManager';
import { getRestartArgs, setGameLaunched, isGameLaunched } from './AbilityState';
import { Logger } from './Logger';

const logger = new Logger('BridgeCallbacks')

export class BridgeCallbacks {
  /**
   * Callback for showing input dialog. Set by GameWindow which has the
   * CustomDialogController context. Call with (title, message, defaultText).
   */
  static showInputDialog: ((title: string, message: string, defaultText: string) => void) | null = null
  static mainWindow: window.Window | null = null

  /**
   * Register all NAPI callbacks and start the engine.
   * Must be called after permissions are granted.
   */
  static registerAll(
    uiContext: UIContext,
    allowedPermissions: string,
    cursorManager: CursorManager,
    fileManager: FileManager,
    sensorManager: SensorManager
  ): void {
    const context = uiContext.getHostContext() as common.UIAbilityContext
    plugin.setShellOpenCallback((uri: string): boolean => {
      try {
        context.openLink(uri)
        return true
      } catch (e) {
        logger.error('Failed to open link', e)
        return false
      }
    })

    plugin.setFileDialogCallback(async (mode: number, title: string, defaultPath: string, filters: string): Promise<string[]> => {
      const result = await fileManager.pickFile(mode, title, defaultPath, filters)
      plugin.fileDialogResult(result)
      return result
    })

    // Directory picker — triggered when Godot PM Browse button opens a folder dialog.
    // Opens native DocumentViewPicker (FOLDER mode), persists permission, converts URI
    // to physical path, and saves to recent directories.
    // NOTE: DocumentSelectMode.FOLDER requires FolderSelection capability (2in1 only).
    // On phones/tablets, immediately returns empty to fall back to the in-engine dialog.
    plugin.setDirectoryPickerCallback((title: string, defaultPath: string): void => {
      const deviceType: string = deviceInfo.deviceType
      if (deviceType !== '2in1') {
        logger.warn('Directory picker not available on ' + deviceType)
        plugin.directoryPickerResult('')
        return
      }
      fileManager.pickFolder().then((folderUri: string) => {
        if (folderUri) {
          fileManager.persistFolderPermission(folderUri).then(() => {
            const physicalPath = fileManager.toPhysicalPath(folderUri)
            fileManager.addRecentDirectory(folderUri, physicalPath)
            plugin.directoryPickerResult(physicalPath)
          }).catch((e: Error) => {
            logger.error('Failed to persist folder permission', e)
            plugin.directoryPickerResult('')
          })
        } else {
          // User cancelled
          plugin.directoryPickerResult('')
        }
      }).catch((e: Error) => {
        logger.error('Directory picker failed', e)
        plugin.directoryPickerResult('')
      })
    })

    plugin.setTerminateCallback((): void => {
      context.terminateSelf().catch((e: Error) => {
        logger.error('Failed to terminate self', e)
      })
    })

    // Restart callback — routes to the correct ability based on engine CLI args.
    // With process isolation (`:pm` / `:editor` / `:game`), each ability runs
    // in its own process. Editor→Game keeps Editor alive in background;
    // Game→Editor just terminates to reveal the background Editor.
    plugin.setRestartCallback((args: string): void => {
      logger.info('Restart requested with args', args)

      // Determine target ability from CLI args
      let targetAbility: string
      let godotMode: string

      // Parse args with exact match — '--editor' would match '--editor-pid' as substring!
      let argsArray: string[] = args.split('\n').filter(a => a.trim().length > 0)
      const hasEditor = argsArray.some(a => a.trim() === '--editor')
      const hasProjectManager = argsArray.some(a => a.trim() === '--project-manager')

      if (hasEditor) {
        targetAbility = 'EditorAbility'
        godotMode = 'editor'
      } else if (hasProjectManager) {
        targetAbility = 'ProjectManagerAbility'
        godotMode = 'pm'
      } else {
        // Has --path but no --editor or --project-manager → game mode
        targetAbility = 'GameAbility'
        godotMode = 'game'
      }
      logger.info(`Routing to ${targetAbility} (mode: ${godotMode})`)

      // Extract project path from --path <value>
      let projectPath: string | null = null
      const pathMatch = args.match(/--path\s+(\S+)/)
      if (pathMatch) {
        projectPath = pathMatch[1]
      }

      const params: Record<string, Object> = {
        'godotMode': godotMode,
        'restartArgs': argsArray
      }
      if (projectPath) {
        params['projectPath'] = projectPath
      }
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: targetAbility,
        parameters: params
      }

      const currentAbility = context.abilityInfo.name
      const keepSourceAlive = (currentAbility === 'EditorAbility' && targetAbility === 'GameAbility')
      const returnToBackground = (currentAbility === 'GameAbility' && targetAbility === 'EditorAbility')

      if (keepSourceAlive) {
        // Editor → Game: GameAbility runs in process:":game". Both Editor
        // and Game have independent task cards. Editor stays alive — no
        // need for terminateSelf.
        //
        // Use startAbilityForResult instead of startAbility — the returned
        // Promise resolves when GameAbility exits (normally or killed),
        // giving us reliable death detection without RUNNING_STATE_OBSERVER.
        setGameLaunched(true)
        context.startAbilityForResult(want).then((result) => {
          logger.info(`GameAbility exited, resultCode=${result.resultCode} — resetting editor run state`)
          setGameLaunched(false)
          // Defer C++ reset to next event loop tick — calling stop_playing()
          // synchronously from the startAbilityForResult callback conflicts
          // with Godot's editor state machine and causes PM window to open.
          setTimeout(() => {
            plugin.resetEditorRunState()
          }, 200)
        }).catch((e: Error) => {
          setGameLaunched(false)
          logger.error('startAbilityForResult failed (code=' + (e as BusinessError).code + ')')
        })

        // Safety timeout: if Game crashes without the system resolving
        // startAbilityForResult (edge case), force reset after 15s.
        setTimeout(() => {
          if (isGameLaunched()) {
            logger.warn('Game timeout — no exit signal received, force resetting run state')
            setGameLaunched(false)
            plugin.resetEditorRunState()
          }
        }, 15000)
      } else if (returnToBackground) {
        // Game → Editor: just terminate. EditorAbility is alive in background
        // within the same task card. System brings it to foreground automatically.
        logger.info('Returning to EditorAbility in background')
        context.terminateSelf().catch((e: Error) => {
          logger.error('terminateSelf failed', e)
        })
      } else {
        // All other transitions: startAbility first, then terminate current after target attaches window
        context.startAbility(want).then(() => {
          logger.info(`${targetAbility} started, scheduling delayed terminateSelf`)
          setTimeout(() => {
            context.terminateSelf().catch((err: BusinessError) => {
              logger.warn('Delayed terminateSelf caught error', err)
            })
          }, 800)
        }).catch((e: Error) => {
          logger.error('startAbility failed', e)
        })
      }
    })

    // Process kill callback — Editor sends kill signal to running GameAbility
    plugin.setProcessKillCallback((): void => {
      logger.info('Process kill — terminating GameAbility')
      const killWant: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'GameAbility',
        parameters: { key: 'kill' }
      }
      context.startAbility(killWant).catch((e: Error) => {
        logger.error('Failed to send kill signal to GameAbility', (e as BusinessError).code)
      })
    })

    plugin.setCustomCursorCallback((width: number, height: number, rgbaData: ArrayBuffer, hotspotX: number, hotspotY: number): void => {
      cursorManager.setCustomCursor(width, height, rgbaData, hotspotX, hotspotY)
    })

    plugin.setCursorShapeCallback((shape: number): void => {
      cursorManager.setCursorShape(shape)
    })

    plugin.setVibrateCallback((durationMs: number): void => {
      try {
        vibrator.startVibration({
          type: 'time',
          duration: durationMs
        }, {
          usage: 'unknown'
        }, (error) => {
          if (error) {
            logger.error('Failed to vibrate', error)
          }
        })
      } catch (e) {
        logger.error('Failed to start vibration', e)
      }
    })

    // Window mode callback — Godot requests maximize, fullscreen, or windowed.
    plugin.setWindowModeCallback((mode: number): void => {
      try {
        const win: window.Window | null = BridgeCallbacks.mainWindow
        if (!win) {
          logger.warn('Window mode: no main window')
          return
        }
        // 0=WINDOWED, 2=MAXIMIZED, 3=FULLSCREEN, 4=EXCLUSIVE_FULLSCREEN
        // On 2in1 in free multi-window mode, setWindowLayoutFullScreen is
        // disabled by the system. Use maximize(presentation) instead.
        const is2in1: boolean = (deviceInfo.deviceType === '2in1')
        if (mode === 2 || mode === 0) {
          if (is2in1) {
            win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).catch((err: Error) => {
              logger.error('Failed to exit immersive', err)
            })
          } else {
            win.maximize().catch((err: Error) => {
              logger.error('Failed to maximize window', err)
            })
          }
        } else if (mode === 3 || mode === 4) {
          if (is2in1) {
            win.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch((err: Error) => {
              logger.error('Failed to enter immersive', err)
            })
          } else {
            win.setWindowLayoutFullScreen(true).catch((err: Error) => {
              logger.error('Failed to set fullscreen', err)
            })
          }
        }
      } catch (err) {
        logger.error('Failed to set window mode', err)
      }
    })

    // Alert dialog (OS::alert) - simple OK dialog
    plugin.setAlertCallback((title: string, message: string): void => {
      try {
        let alertParam: AlertDialogParam = { title: title, message: message }
        uiContext.showAlertDialog(alertParam)
      } catch (e) {
        logger.error('Failed to show alert dialog', e)
      }
    })

    // Multi-button dialog (DisplayServer::dialog_show / dialog_input_text)
    plugin.setDialogCallback((title: string, description: string, buttons: string): void => {
      try {
        // Input dialog (buttons string starts with "INPUT:")
        const inputPrefix: string = 'INPUT:'
        if (buttons.startsWith(inputPrefix)) {
          const defaultText: string = buttons.substring(inputPrefix.length)
          if (BridgeCallbacks.showInputDialog) {
            BridgeCallbacks.showInputDialog(title, description, defaultText)
          }
          return
        }

        // Regular multi-button dialog
        const buttonLabels: string[] = buttons.split(',')
        const alertButtons: AlertDialogButtonOptions[] = []

        for (let i = 0; i < buttonLabels.length; i++) {
          const index: number = i
          alertButtons.push({
            value: buttonLabels[i],
            action: (): void => {
              plugin.dialogResult(index)
            }
          })
        }

        uiContext.showAlertDialog({
          title: title,
          message: description,
          buttons: alertButtons,
          buttonDirection: DialogButtonDirection.AUTO
        })
      } catch (e) {
        logger.error('Failed to show dialog', e)
      }
    })

    // Pass restart arguments to native layer before engine init
    // Read restart arguments from Want parameters (cross-process safe)
    let restartArgsStr = ''
    const restartArgs = getRestartArgs();
    if (restartArgs && restartArgs.length > 0) {
      restartArgsStr = restartArgs.join('\n');
    }
    if (restartArgsStr) {
      plugin.setRestartArguments(restartArgsStr);
    }

    // File I/O bridge — routes C++ file operations to ArkTS @ohos.file.fs
    plugin.setFsRequestCallback((requestJson: string): void => {
      let response: FsBaseResult = { ok: false, error: '' }
      let reqId: number = 0
      try {
        const req = JSON.parse(requestJson) as Record<string, Object>
        reqId = (req['req_id'] as number) || 0
        const op: string = req['op'] as string
        const path: string = (req['path'] as string) || ''
        switch (op) {
          case 'stat':
            response = handleFsStat(path) as FsBaseResult
            break
          case 'read_file':
            response = handleFsReadFile(path) as FsBaseResult
            break
          case 'write_file':
            response = handleFsWriteFile(path, req['text'] as string, req['data'] as string) as FsBaseResult
            break
          case 'list_dir':
            response = handleFsListDir(path) as FsBaseResult
            break
          case 'mkdir':
            response = handleFsMkdir(path) as FsBaseResult
            break
          case 'remove':
            response = handleFsRemove(path) as FsBaseResult
            break
          case 'rename':
            response = handleFsRename(path, (req['new_path'] as string) || '') as FsBaseResult
            break
          default:
            response = { ok: false, error: 'Unknown operation: ' + op } as FsBaseResult
        }
      } catch (e) {
        response = { ok: false, error: String(e) } as FsBaseResult
      }
      // Echo req_id back so C++ can reject stale responses from timed-out requests.
      // Inject req_id before the first field: {"ok":true,...} → {"req_id":5,"ok":true,...}
      // Safe: response always has at least {ok:...}, so respStr never equals "{}".
      const respStr = JSON.stringify(response)
      const withId = '{"req_id":' + reqId + ',' + respStr.substring(1)
      plugin.fsResult(withId)
    })

    plugin.setup(allowedPermissions)

    sensorManager.startSensors(allowedPermissions)
  }
}

// ============================================================
// File I/O Bridge — type declarations for JSON responses
// ============================================================

interface FsStatResult {
  ok: boolean
  exists?: boolean
  is_dir?: boolean
  is_file?: boolean
  size?: number
  mtime?: number
  error?: string
}

interface FsReadResult {
  ok: boolean
  size?: number
  text?: string
  data?: string
  error?: string
}

interface FsDirEntry {
  name: string
  is_dir: boolean
  is_file: boolean
}

interface FsListResult {
  ok: boolean
  entries?: FsDirEntry[]
  error?: string
}

interface FsSimpleResult {
  ok: boolean
  error?: string
}

interface FsWriteResult {
  ok: boolean
  error?: string
}

interface FsBaseResult {
  ok: boolean
  error?: string
}

// ============================================================
// File I/O Bridge Handlers — @ohos.file.fs operations
// ============================================================

function handleFsStat(path: string): FsStatResult {
  try {
    const stat = fs.statSync(path)
    return { ok: true, exists: true, is_dir: stat.isDirectory(), is_file: stat.isFile(), size: stat.size, mtime: stat.mtime }
  } catch (e) {
    const bizErr = e as BusinessError
    if (bizErr.code === 13900002) {
      return { ok: true, exists: false }
    }
    return { ok: false, error: 'stat failed: code=' + bizErr.code + ' msg=' + bizErr.message }
  }
}


function handleFsReadFile(path: string): FsReadResult {
  try {
    const stat = fs.statSync(path)
    // Try text mode first — readTextSync handles UTF-8 correctly.
    // Fall back to binary (base64) if it fails on non-text content.
    try {
      const text = fs.readTextSync(path, { encoding: 'utf-8' })
      return { ok: true, size: stat.size, text: text }
    } catch (_textErr) {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
      try {
        const buf = new ArrayBuffer(stat.size)
        fs.readSync(file.fd, buf, { offset: 0, length: stat.size })
        return { ok: true, size: stat.size, data: base64Encode(new Uint8Array(buf)) }
      } finally {
        fs.closeSync(file)
      }
    }
  } catch (e) {
    return { ok: false, error: String(e) }
  }
}

function handleFsWriteFile(path: string, text?: string, data?: string): FsWriteResult {
  try {
    if (text !== undefined && text !== null) {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      try {
        fs.writeSync(file.fd, text)
        return { ok: true }
      } finally {
        fs.closeSync(file)
      }
    } else if (data !== undefined && data !== null) {
      // Decode base64 to ArrayBuffer for binary-safe write.
      // Writing via string would corrupt bytes > 127 (UTF-8 encoding).
      const buf = base64DecodeToArrayBuffer(data)
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      try {
        fs.writeSync(file.fd, buf)
        return { ok: true }
      } finally {
        fs.closeSync(file)
      }
    } else {
      return { ok: false, error: 'write_file: no text or data provided' }
    }
  } catch (e) {
    return { ok: false, error: String(e) }
  }
}

function handleFsListDir(path: string): FsListResult {
  try {
    const names: string[] = fs.listFileSync(path)
    const entries: FsDirEntry[] = []
    for (const name of names) {
      const childPath: string = path.endsWith('/') ? path + name : path + '/' + name
      try {
        const s = fs.statSync(childPath)
        entries.push({ name: name, is_dir: s.isDirectory(), is_file: s.isFile() })
      } catch (_e) {
        entries.push({ name: name, is_dir: false, is_file: false })
      }
    }
    return { ok: true, entries: entries }
  } catch (e) {
    const bizErr = e as BusinessError
    if (bizErr.code === 13900001) {
      return { ok: false, error: 'permission_denied', entries: [] }
    }
    return { ok: false, error: String(e) }
  }
}

function handleFsMkdir(path: string): FsSimpleResult {
  try {
    fs.mkdirSync(path, true)
    return { ok: true }
  } catch (e) {
    const bizErr = e as BusinessError
    if (bizErr.code === 13900001) {
      return { ok: false, error: 'permission_denied' }
    }
    return { ok: false, error: String(e) }
  }
}

function handleFsRemove(path: string): FsSimpleResult {
  try {
    fs.rmdirSync(path)
    return { ok: true }
  } catch (_e1) {
    try {
      fs.unlinkSync(path)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: String(e) }
    }
  }
}

function handleFsRename(oldPath: string, newPath: string): FsSimpleResult {
  try {
    fs.renameSync(oldPath, newPath)
    return { ok: true }
  } catch (e) {
    return { ok: false, error: String(e) }
  }
}

function base64Encode(input: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  let result = ''
  for (let i = 0; i < input.length; i += 3) {
    const b1 = input[i]
    const b2 = i + 1 < input.length ? input[i + 1] : 0
    const b3 = i + 2 < input.length ? input[i + 2] : 0
    result += chars.charAt((b1 >> 2) & 0x3f)
    result += chars.charAt(((b1 << 4) | (b2 >> 4)) & 0x3f)
    result += i + 1 < input.length ? chars.charAt(((b2 << 2) | (b3 >> 6)) & 0x3f) : '='
    result += i + 2 < input.length ? chars.charAt(b3 & 0x3f) : '='
  }
  return result
}

function base64Decode(input: string): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  let result = ''
  let i = 0
  while (i < input.length) {
    const ch1 = input.charAt(i++)
    const c1 = chars.indexOf(ch1)
    if (c1 < 0 && ch1 !== '=') {
      throw new Error('Invalid base64 character "' + ch1 + '" at position ' + (i - 1))
    }
    const ch2 = input.charAt(i++)
    const c2 = chars.indexOf(ch2)
    if (c2 < 0 && ch2 !== '=') {
      throw new Error('Invalid base64 character "' + ch2 + '" at position ' + (i - 1))
    }
    const ch3 = i < input.length ? input.charAt(i) : ''
    const c3 = i < input.length && ch3 !== '=' ? chars.indexOf(ch3) : -1
    if (c3 < 0 && ch3 !== '' && ch3 !== '=') {
      throw new Error('Invalid base64 character "' + ch3 + '" at position ' + i)
    }
    if (c3 >= 0) {
      i++
    }
    const ch4 = i < input.length ? input.charAt(i) : ''
    const c4 = i < input.length && ch4 !== '=' ? chars.indexOf(ch4) : -1
    if (c4 < 0 && ch4 !== '' && ch4 !== '=') {
      throw new Error('Invalid base64 character "' + ch4 + '" at position ' + i)
    }
    if (c4 >= 0) {
      i++
    }
    if (c1 >= 0 && c2 >= 0) {
      result += String.fromCharCode(((c1 << 2) | (c2 >> 4)) & 0xff)
    }
    if (c3 >= 0) {
      result += String.fromCharCode(((c2 << 4) | (c3 >> 2)) & 0xff)
    }
    if (c4 >= 0) {
      result += String.fromCharCode(((c3 << 6) | c4) & 0xff)
    }
  }
  return result
}

// Decode base64 to ArrayBuffer for binary-safe file write.
// Unlike base64Decode which returns a string (corrupted by UTF-8 encoding
// on write), this produces raw bytes that writeSync(ArrayBuffer) preserves.
function base64DecodeToArrayBuffer(input: string): ArrayBuffer {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  // Compute output length: each 4 base64 chars → 3 bytes, minus padding
  let padding = 0
  if (input.length > 0 && input.charAt(input.length - 1) === '=') {
    padding++
  }
  if (input.length > 1 && input.charAt(input.length - 2) === '=') {
    padding++
  }
  const outLen = (input.length / 4) * 3 - padding
  const buf = new ArrayBuffer(outLen)
  const view = new Uint8Array(buf)
  let i = 0
  let j = 0
  while (i < input.length) {
    const ch1 = input.charAt(i++)
    const c1 = chars.indexOf(ch1)
    if (c1 < 0 && ch1 !== '=') {
      throw new Error('Invalid base64 character "' + ch1 + '" at position ' + (i - 1))
    }
    const ch2 = input.charAt(i++)
    const c2 = chars.indexOf(ch2)
    if (c2 < 0 && ch2 !== '=') {
      throw new Error('Invalid base64 character "' + ch2 + '" at position ' + (i - 1))
    }
    const ch3 = i < input.length ? input.charAt(i) : ''
    const c3 = i < input.length && ch3 !== '=' ? chars.indexOf(ch3) : -1
    if (c3 < 0 && ch3 !== '' && ch3 !== '=') {
      throw new Error('Invalid base64 character "' + ch3 + '" at position ' + i)
    }
    if (c3 >= 0) {
      i++
    }
    const ch4 = i < input.length ? input.charAt(i) : ''
    const c4 = i < input.length && ch4 !== '=' ? chars.indexOf(ch4) : -1
    if (c4 < 0 && ch4 !== '' && ch4 !== '=') {
      throw new Error('Invalid base64 character "' + ch4 + '" at position ' + i)
    }
    if (c4 >= 0) {
      i++
    }
    if (c1 >= 0 && c2 >= 0) {
      view[j++] = ((c1 << 2) | (c2 >> 4)) & 0xff
    }
    if (c3 >= 0 && j < outLen) {
      view[j++] = ((c2 << 4) | (c3 >> 2)) & 0xff
    }
    if (c4 >= 0 && j < outLen) {
      view[j++] = ((c3 << 6) | c4) & 0xff
    }
  }
  return buf
}
