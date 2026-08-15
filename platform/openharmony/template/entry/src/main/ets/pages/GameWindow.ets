import { resourceManager, i18n } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import webview from '@ohos.web.webview';
import fs from '@ohos.file.fs';
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
import { HarmonyOpenCodeBridgeProxy } from '../opencode/OpenCodePanelBridgeHost';
import { OpenCodeFormalPanelController } from '../opencode/OpenCodeFormalPanelController';
import { OpenCodeFormalRuntimeController } from '../opencode/OpenCodeFormalRuntimeController';
import { OpenCodeFormalAssetInstaller } from '../opencode/OpenCodeFormalAssetInstaller';
import type { OpenCodePanelNavigation } from '../opencode/OpenCodePanelContract';

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

  // OpenCode AI Assistant Panel state
  @State private isAiPanelOpen: boolean = true
  @State private aiPanelWidth: number = 420
  @State private panelUrl: string = ''
  @State private panelReady: boolean = false
  @State private isStartingRuntime: boolean = false
  private webController: webview.WebviewController = new webview.WebviewController()
  private bridgeProxy: HarmonyOpenCodeBridgeProxy = new HarmonyOpenCodeBridgeProxy()
  private panelController?: OpenCodeFormalPanelController

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

    try {
      let initialProjectDir = this.fileManager.toPhysicalPath(this.fileManager.getExternalProjectDir())
      if (!initialProjectDir || initialProjectDir.length === 0) {
        initialProjectDir = this.fileManager.getDefaultProjectDir()
      }
      if (!initialProjectDir || initialProjectDir.length === 0) {
        initialProjectDir = `${this.context.filesDir}/projects`
      }
      try {
        if (!fs.accessSync(initialProjectDir)) {
          fs.mkdirSync(initialProjectDir, true)
        }
      } catch (_) {}
      const runtimeController = new OpenCodeFormalRuntimeController(
        this.context.filesDir,
        this.context.cacheDir,
        this.context.tempDir,
        initialProjectDir
      )
      const assetInstaller = new OpenCodeFormalAssetInstaller(this.context)
      this.panelController = new OpenCodeFormalPanelController(this.context.filesDir, runtimeController, assetInstaller)
      this.startOpenCodePanel()
    } catch (e) {
      logger.error('Failed to initialize OpenCode formal panel controller', e)
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

  private async startOpenCodePanel() {
    if (this.isStartingRuntime || this.panelReady || !this.panelController) {
      return
    }
    this.isStartingRuntime = true
    try {
      const nav: OpenCodePanelNavigation = await this.panelController.activate()
      this.panelUrl = nav.url
      this.panelReady = true
      logger.info('OpenCode formal panel activated at: ' + nav.url)
    } catch (e) {
      logger.error('Failed to activate OpenCode panel', e)
    } finally {
      this.isStartingRuntime = false
    }
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
    Row() {
      // 1. Left: Godot Editor / Game Viewport (fills remaining width)
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
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            let ctx = this.getUIContext()
            this.controller.setXComponentSurfaceRect({
              offsetX: 0,
              offsetY: 0,
              surfaceWidth: ctx.vp2px(Number(newArea.width)),
              surfaceHeight: ctx.vp2px(Number(newArea.height))
            });
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

        // Toggle button when OpenCode panel is closed
        if (!this.isAiPanelOpen) {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row() {
              Text('✨ OpenCode AI')
                .fontSize(13)
                .fontColor('#ffffff')
                .fontWeight(FontWeight.Medium)
            }
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          }
          .backgroundColor('rgba(30, 100, 210, 0.85)')
          .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.4)' })
          .position({ x: '100%', y: 16 })
          .markAnchor({ x: '100%', y: 0 })
          .margin({ right: 16 })
          .onClick(() => {
            this.isAiPanelOpen = true
            this.startOpenCodePanel()
          })
        }
      }
      .layoutWeight(1)
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM])
      .onKeyEvent((event) => {
        this.inputManager.handleKeyEvent(event)
      })

      // 2. Right: OpenCode Web SPA Sidebar
      if (this.isAiPanelOpen) {
        Column() {
          // Top Control Header
          Row() {
            Text('OpenCode AI 助手')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#e6e6e6')
            Blank()
            Button('✕', { type: ButtonType.Normal })
              .fontSize(14)
              .fontColor('#aaaaaa')
              .backgroundColor(Color.Transparent)
              .width(28)
              .height(28)
              .borderRadius(4)
              .onClick(() => {
                this.isAiPanelOpen = false
              })
          }
          .width('100%')
          .height(38)
          .padding({ left: 12, right: 8 })
          .backgroundColor('#1e1e1e')
          .border({ width: { bottom: 1 }, color: '#333333' })

          // Webview Content
          if (this.panelReady && this.panelUrl.length > 0) {
            Web({ src: this.panelUrl, controller: this.webController })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .fileAccess(true)
              .imageAccess(true)
              .mixedMode(MixedMode.All)
              .javaScriptProxy({
                object: this.bridgeProxy,
                name: 'harmonyBridge',
                methodList: ['getEditorContext', 'applyScriptChanges'],
                controller: this.webController
              })
              .width('100%')
              .layoutWeight(1)
          } else {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color('#007DFF')
              Text(this.isStartingRuntime ? '正在启动 OpenCode 独立运行时...' : '正在准备 OpenCode 资产...')
                .fontSize(12)
                .fontColor('#888888')
                .margin({ top: 10 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width(this.aiPanelWidth)
        .height('100%')
        .backgroundColor('#252526')
        .border({ width: { left: 1 }, color: '#333333' })
      }
    }
    .width('100%')
    .height('100%')
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
