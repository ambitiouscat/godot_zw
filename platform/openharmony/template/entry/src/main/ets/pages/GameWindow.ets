import { resourceManager, i18n } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
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
import { getProjectPath, getGodotMode } from '../core/AbilityState';
import { GodotMcpInstaller } from '../core/GodotMcpInstaller';
import { GodotMcpServerGateway } from '../core/GodotMcpServerGateway';
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

  // OpenCode Dock Alignment & Runtime state
  @State private dockVisible: boolean = false
  @State private dockX: number = 0
  @State private dockY: number = 0
  @State private dockWidth: number = 0
  @State private dockHeight: number = 0
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

    plugin.setOpenCodeDockGeometryCallback((x: number, y: number, width: number, height: number, isVisible: boolean) => {
      this.dockX = x
      this.dockY = y
      this.dockWidth = width
      this.dockHeight = height
      this.dockVisible = isVisible && width > 0 && height > 0
      if (this.dockVisible && !this.panelReady && !this.isStartingRuntime && getGodotMode() === 'editor') {
        this.startOpenCodePanel()
      }
    })

    if (getGodotMode() !== 'editor') {
      logger.info(`Skipping OpenCode and MCP initialization in non-editor mode: ${getGodotMode()}`)
      return
    }

    try {
      let initialProjectDir = getProjectPath()
      if (!initialProjectDir || initialProjectDir.length === 0) {
        initialProjectDir = this.fileManager.toPhysicalPath(this.fileManager.getExternalProjectDir())
      }
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

      // Auto-provision Godot MCP In-Engine Addon into the opened project
      void GodotMcpInstaller.ensureInstalled(this.context, initialProjectDir)
      void GodotMcpServerGateway.getInstance().start(6510)

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
    try {
      if (this.panelController) {
        void this.panelController.shutdown()
      }
    } catch (_) {}
  }

  private async startOpenCodePanel(retryCount: number = 0) {
    if (!this.panelController || this.panelReady || this.isStartingRuntime) {
      return
    }
    try {
      this.isStartingRuntime = true
      const target: OpenCodePanelNavigation = await this.panelController.activate()
      this.panelUrl = target.url
      this.panelReady = true
      logger.info(`OpenCode formal panel activated at: ${target.url}`)
    } catch (e) {
      logger.error(`Failed to activate OpenCode panel (attempt ${retryCount + 1})`, e)
      if (retryCount < 4) {
        const delayMs = (retryCount + 1) * 800
        logger.info(`Scheduling OpenCode panel retry ${retryCount + 1}/4 in ${delayMs}ms...`)
        setTimeout(() => {
          this.startOpenCodePanel(retryCount + 1)
        }, delayMs)
      }
    } finally {
      this.isStartingRuntime = false
    }
  }

  private async handleBridgeMessageFromWeb(msg: string, hostPort: webview.WebMessagePort): Promise<void> {
    try {
      const req: Record<string, Object> = JSON.parse(msg) as Record<string, Object>;
      if (!req || typeof req !== 'object') return;

      const requestId: string = (req['requestId'] as string) || 'req_0';
      const method: string = (req['method'] as string) || '';

      let resultJson: string = '{}';
      let ok: boolean = true;
      let errStr: string = '';

      if (method === 'context.snapshot' || method === 'context.active-script' || method === 'context.selection') {
        try {
          const rawCtx: string = plugin.getEditorContext();
          resultJson = (rawCtx && rawCtx.length > 0) ? rawCtx : '{"has_context":false}';
        } catch (e) {
          resultJson = '{"has_context":false}';
        }
      } else if (method === 'opencode.patch.propose' || method === 'opencode.patch.accept') {
        try {
          const payload = (req['payload'] as Record<string, string>) || {};
          const targetPath: string = payload['path'] || '';
          const targetContent: string = payload['diff'] || payload['content'] || '';
          const success: boolean = plugin.applyScriptChanges(targetPath, targetContent);
          resultJson = `{"applied":${success}}`;
        } catch (e) {
          ok = false;
          errStr = `,"error":{"code":"PATCH_FAILED","summary":${JSON.stringify(String(e))},"retryable":true}`;
        }
      } else if (method === 'mcp.execute_command' || method === 'mcp.call_tool') {
        try {
          const payload = (req['payload'] as Record<string, Object>) || {};
          const cmdName: string = (payload['name'] as string) || (payload['method'] as string) || '';
          const cmdArgs = (payload['arguments'] as Record<string, Object>) || (payload['params'] as Record<string, Object>) || {};
          const cmdRes = await GodotMcpServerGateway.getInstance().executeGodotCommand(cmdName, cmdArgs);
          resultJson = JSON.stringify(cmdRes);
        } catch (e) {
          ok = false;
          errStr = `,"error":{"code":"MCP_COMMAND_FAILED","summary":${JSON.stringify(String(e))},"retryable":false}`;
        }
      } else if (method === 'editor.refresh-resource' || method === 'editor.file-updated') {
        try {
          const payload = (req['payload'] as Record<string, string>) || {};
          const targetPath: string = payload['path'] || '';
          const success: boolean = plugin.updateResourceFile(targetPath);
          resultJson = `{"updated":${success}}`;
        } catch (e) {
          resultJson = '{"updated":false}';
        }
      } else if (method === 'runtime.status') {
        const isMcpConnected = GodotMcpServerGateway.getInstance().isGodotConnected();
        resultJson = `{"phase":"ready","visible":true,"ready":true,"generation":1,"errorCode":"","errorSummary":"","retryable":false,"mcp":{"available":true,"connected":${isMcpConnected},"ports":"6505-6514","toolCount":179}}`;
      } else {
        resultJson = '{"acknowledged":true}';
      }

      const respWire: string = `{"protocol":"opencode.i3d.editor-bridge","version":1,"panelInstanceId":"panel:main:01","kind":"response","requestId":"${requestId}","ok":${ok},"result":${resultJson}${errStr}}`;
      hostPort.postMessageEvent(respWire);
    } catch (e) {
      logger.error('Error handling bridge message from web', e);
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
    Stack() {
      // 1. Fullscreen Godot Engine
      XComponent({
        id: "window",
        type: XComponentType.SURFACE,
        controller: this.controller,
      })
        .id("godot_surface")
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

      // 2. OpenCode ArkWeb Dock (Overlay perfectly aligned to the Godot Editor Dock tab)
      if (this.dockVisible && this.panelReady && this.panelUrl.length > 0) {
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
          .onPageEnd((_event) => {
            logger.info('OpenCode webview onPageEnd: creating WebMessagePorts bootstrap');
            try {
              const ports = this.webController.createWebMessagePorts();
              if (ports && ports.length >= 2) {
                const hostPort = ports[0];
                const webPort = ports[1];

                hostPort.onMessageEvent((result: webview.WebMessage) => {
                  const msgStr = typeof result === 'string' ? result : new util.TextDecoder().decodeToString(new Uint8Array(result));
                  this.handleBridgeMessageFromWeb(msgStr, hostPort);
                });

                const bootstrapPayload = JSON.stringify({
                  name: '__init_opencode_editor_bridge_v1__',
                  protocol: 'opencode.i3d.editor-bridge',
                  version: 1,
                  scope: 'sdk-client',
                  panelInstanceId: 'panel:main:01'
                });
                this.webController.postMessage(bootstrapPayload, [webPort], '*');
                logger.info('OpenCode MessagePort bootstrap message posted successfully');
              }
            } catch (err) {
              logger.error('Failed to setup WebMessagePorts for OpenCode', err);
            }
          })
          .position({
            x: `${this.dockX}px`,
            y: `${this.dockY}px`
          })
          .width(`${this.dockWidth}px`)
          .height(`${this.dockHeight}px`)
          .backgroundColor('#252526')
          .border({ width: 0 })
      }
    }
    .width('100%')
    .height('100%')
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
