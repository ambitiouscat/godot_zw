import { resourceManager, i18n } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import plugin, { SimplifiedTouchEvent } from 'libentry.so';
import { InputManager } from '../core/InputManager';
import { PermissionManager } from '../core/PermissionManager';
import { SensorManager } from '../core/SensorManager';
import { CursorManager } from '../core/CursorManager';
import { FileManager } from '../core/FileManager';
import { BridgeCallbacks } from '../core/BridgeCallbacks';
import { InputDialogContent } from '../core/InputDialog';
import { Logger } from '../core/Logger';
import { injectStandardDirs } from '../core/StandardDirProvider';

const logger = new Logger('GameWindow')

class PluginXComponentController extends XComponentController {
  ctx: common.UIAbilityContext
  resMgr: resourceManager.ResourceManager
  windowId: number

  constructor(context: common.UIAbilityContext, resourceManager: resourceManager.ResourceManager) {
    super()
    this.ctx = context
    this.resMgr = resourceManager
    try {
      this.windowId = this.ctx.windowStage.getMainWindowSync()
        .getWindowProperties()
        .id
    } catch (e) {
      logger.error('Failed to get window ID in PluginXComponentController', e)
      this.windowId = 0
    }
  }

  onSurfaceCreated(surfaceId: string): void {
    plugin.setResourceManager(this.resMgr)
    plugin.setWindowId(this.windowId)
    plugin.setSurfaceId(BigInt(surfaceId))
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    plugin.changeSurface(BigInt(surfaceId), rect.surfaceWidth, rect.surfaceHeight)
  }

  onSurfaceDestroyed(surfaceId: string): void {
    plugin.destroySurface(BigInt(surfaceId))
  }
}

@Entry
@Component
struct GameWindow {
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  resMgr = this.context.resourceManager
  controller: XComponentController = new PluginXComponentController(this.context, this.resMgr)
  inputManager: InputManager = new InputManager()
  private mainWindow: window.Window | null = null
  private permissionManager: PermissionManager = new PermissionManager(this.context)
  private cursorManager: CursorManager = new CursorManager(this.getUIContext())
  private fileManager: FileManager = new FileManager(this.context)
  private sensorManager: SensorManager = new SensorManager()
  @State private inputDialogTitle: string = ''
  @State private inputDialogMessage: string = ''
  @State private inputDialogText: string = ''
  private inputDialogController: CustomDialogController | null = null

  aboutToAppear() {
    try {
      const win = this.context.windowStage.getMainWindowSync()
      this.mainWindow = win
      win.on('windowSizeChange', (size: Size) => {
        this.setXComponentSurfaceRect(size)
      })
    } catch (e) {
      logger.error('Failed to initialize main window', e)
    }
  }

  aboutToDisappear() {
    try {
      this.mainWindow?.off('windowSizeChange')
    } catch (e) {
      logger.error('Failed to unregister window listener', e)
    }
    BridgeCallbacks.showInputDialog = null
    this.inputDialogController = null
  }

  setXComponentSurfaceRect(size: Size) {
    this.controller.setXComponentSurfaceRect({
      offsetX: 0,
      offsetY: 0,
      surfaceWidth: size.width,
      surfaceHeight: size.height
    });
  }

  build() {
    Stack() {
      XComponent({
        id: "window",
        type: XComponentType.SURFACE,
        controller: this.controller,
      })
        .onLoad(() => {
          try {
            const win = this.mainWindow
            if (win === null) {
              logger.error('Main window not initialized')
              this.initEngine()
              return
            }
            const rect = win.getWindowProperties().windowRect
            this.setXComponentSurfaceRect(rect)
          } catch (e) {
            logger.error('Failed to set XComponent surface rect', e)
          }
          this.initEngine()
        })
        .onTouch((event) => {
          if (event.source === SourceType.TouchScreen) {
            let ctx = this.getUIContext()
            let events: SimplifiedTouchEvent[] = []
            for (let index = 0; index < event.touches.length; index++) {
              const touch = event.touches[index];
              events.push({
                type: touch.type,
                id: touch.id,
                x: ctx.vp2px(touch.x),
                y: ctx.vp2px(touch.y),
              })
            }
            this.inputManager.handleTouch(events);
          }
        })
        .onMouse((event) => {
          this.inputManager.handleMouse(event, this.getUIContext())
        })
        .onHover((isHover: boolean, event: HoverEvent) => {
          if (isHover) {
            this.cursorManager.reapplyCursor()
            this.inputManager.handleHover(event, this.getUIContext())
          }
        })
        .onAxisEvent((event) => {
          this.inputManager.handleAxisEvent(event, this.getUIContext())
        })
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM])
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM])
    .onKeyEvent((event) => {
      this.inputManager.handleKeyEvent(event)
    })
  }

  private async initEngine() {
    let allowedPermissions = await this.permissionManager.requestPermissions()

    injectStandardDirs()

    // Restore persisted folder permissions from prior sessions.
    // Must be awaited before checking externalProjectDir.
    await this.fileManager.restorePersistedPermissions()

    // Set project directory:
    // 1. Restored external dir from persisted DocumentViewPicker permission (2in1 only).
    //    Convert file://docs/ URI → physical path (POSIX-accessible after persistPermission).
    // 2. Default sandbox dir (phone/tablet)
    // Directory selection via native picker is now triggered from PM's Browse UI,
    // not from this startup flow.
    let projectDir: string = this.fileManager.toPhysicalPath(this.fileManager.getExternalProjectDir())
    if (!projectDir) {
      projectDir = this.fileManager.getDefaultProjectDir()
    }
    if (projectDir.length > 0) {
      plugin.setProjectDir(projectDir)
    }

    BridgeCallbacks.registerAll(
      this.getUIContext(),
      allowedPermissions,
      this.cursorManager,
      this.fileManager,
      this.sensorManager
    )

    // Register input dialog provider (uses this component's CustomDialogController)
    BridgeCallbacks.showInputDialog = (title: string, message: string, defaultText: string): void => {
      this.inputDialogTitle = title
      this.inputDialogMessage = message
      this.inputDialogText = defaultText

      // Close previous dialog if open, then create a new one with current values
      this.inputDialogController?.close()
      this.inputDialogController = new CustomDialogController({
        builder: InputDialogContent({
          title: this.inputDialogTitle,
          message: this.inputDialogMessage,
          defaultText: this.inputDialogText
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center
      })
      this.inputDialogController.open()
    }

    // Set system locale
    try {
      let lang: string = i18n.System.getSystemLanguage().replace('-', '_')
      plugin.setLocale(lang)
    } catch (e) {
      logger.error('Failed to set locale', e)
    }
  }
}
