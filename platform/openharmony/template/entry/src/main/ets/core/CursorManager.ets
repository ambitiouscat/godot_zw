import ApplicationStateChangeCallback from '@ohos.app.ability.ApplicationStateChangeCallback';
import { pointer } from '@kit.InputKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { Logger } from './Logger';

const logger = new Logger('CursorManager')

interface CursorController {
  setCursor(style: pointer.PointerStyle): void
}

// Cursor mode tracking
const CURSOR_MODE_NONE = 0
const CURSOR_MODE_SHAPE = 1
const CURSOR_MODE_CUSTOM = 2

class CursorData {
  width: number = 0
  height: number = 0
  rgbaData: ArrayBuffer = new ArrayBuffer(0)
  hotspotX: number = 0
  hotspotY: number = 0
}

class ForegroundCallback extends ApplicationStateChangeCallback {
  private lastCursorData: CursorData | null = null
  private lastShape: pointer.PointerStyle = pointer.PointerStyle.DEFAULT
  private cursorMode: number = CURSOR_MODE_NONE
  private applyShapeFn: ((style: pointer.PointerStyle) => void) | null = null
  private applyCustomFn: (() => void) | null = null
  private restoreFn: (() => void) | null = null

  constructor(
    applyShape: (style: pointer.PointerStyle) => void,
    applyCustom: () => void,
    restore: () => void
  ) {
    super()
    this.applyShapeFn = applyShape
    this.applyCustomFn = applyCustom
    this.restoreFn = restore
  }

  onApplicationForeground(): void {
    if (this.cursorMode === CURSOR_MODE_CUSTOM && this.lastCursorData !== null) {
      this.applyCustomFn?.()
    } else if (this.cursorMode === CURSOR_MODE_SHAPE) {
      this.applyShapeFn?.(this.lastShape)
    }
  }

  onApplicationBackground(): void {
    this.restoreFn?.()
  }

  saveCursorData(data: CursorData): void {
    this.lastCursorData = data
    this.cursorMode = CURSOR_MODE_CUSTOM
  }

  saveShape(style: pointer.PointerStyle): void {
    this.lastShape = style
    this.cursorMode = CURSOR_MODE_SHAPE
  }

  clearCursorData(): void {
    this.lastCursorData = null
    this.cursorMode = CURSOR_MODE_NONE
  }

  getCursorData(): CursorData {
    return this.lastCursorData!
  }

  reapply(): void {
    if (this.cursorMode === CURSOR_MODE_CUSTOM && this.lastCursorData !== null) {
      this.applyCustomFn?.()
    } else if (this.cursorMode === CURSOR_MODE_SHAPE) {
      this.applyShapeFn?.(this.lastShape)
    }
  }
}

/**
 * Map Godot CursorShape enum to OpenHarmony PointerStyle enum.
 * Godot CursorShape: ARROW=0, IBEAM=1, POINTING_HAND=2, CROSS=3, WAIT=4, BUSY=5,
 *   DRAG=6, CAN_DROP=7, FORBIDDEN=8, VSIZE=9, HSIZE=10, BDIAGSIZE=11, FDIAGSIZE=12,
 *   MOVE=13, VSPLIT=14, HSPLIT=15, HELP=16
 */
function mapCursorShape(godotShape: number): pointer.PointerStyle {
  switch (godotShape) {
    case 1:  return pointer.PointerStyle.TEXT_CURSOR       // IBEAM
    case 2:  return pointer.PointerStyle.HAND_POINTING     // POINTING_HAND
    case 3:  return pointer.PointerStyle.CROSS
    case 4:  return pointer.PointerStyle.LOADING           // WAIT
    case 5:  return pointer.PointerStyle.LOADING           // BUSY
    case 6:  return pointer.PointerStyle.HAND_GRABBING     // DRAG
    case 7:  return pointer.PointerStyle.HAND_OPEN         // CAN_DROP
    case 8:  return pointer.PointerStyle.CURSOR_FORBID
    case 9:  return pointer.PointerStyle.RESIZE_UP_DOWN    // VSIZE
    case 10: return pointer.PointerStyle.RESIZE_LEFT_RIGHT // HSIZE
    case 11: return pointer.PointerStyle.SOUTH_EAST        // BDIAGSIZE
    case 12: return pointer.PointerStyle.NORTH_EAST        // FDIAGSIZE
    case 13: return pointer.PointerStyle.MOVE
    case 14: return pointer.PointerStyle.RESIZE_LEFT_RIGHT // VSPLIT
    case 15: return pointer.PointerStyle.RESIZE_UP_DOWN    // HSPLIT
    case 16: return pointer.PointerStyle.HELP
    default: return pointer.PointerStyle.DEFAULT            // ARROW
  }
}

function applyCustomCursor(windowId: number, data: CursorData): void {
  try {
    let options: image.InitializationOptions = {
      size: { width: data.width, height: data.height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    }

    image.createPixelMap(data.rgbaData, options).then((pixelMap: image.PixelMap) => {
      let cursor: pointer.CustomCursor = {
        pixelMap: pixelMap,
        focusX: data.hotspotX,
        focusY: data.hotspotY
      }
      let config: pointer.CursorConfig = { followSystem: false }
      pointer.setCustomCursor(windowId, cursor, config).then(() => {
        logger.info('Custom cursor set successfully')
      }).catch((e: Object) => {
        logger.error('Failed to set custom cursor', e)
      })
    }).catch((e: Error) => {
      logger.error('Failed to create pixel map for cursor', e)
    })
  } catch (e) {
    logger.error('Failed to set custom cursor', e)
  }
}

export class CursorManager {
  private windowId: number
  private cursorController: CursorController
  foregroundCallback: ForegroundCallback

  constructor(uiContext: UIContext) {
    this.windowId = 0
    this.cursorController = uiContext.getCursorController() as CursorController

    // Get windowId from the host context
    try {
      let abilityContext = uiContext.getHostContext() as common.UIAbilityContext
      this.windowId = abilityContext.windowStage.getMainWindowSync().getWindowProperties().id
    } catch (e) {
      logger.error('Failed to get window ID in CursorManager', e)
    }

    // Build callback functions that reference the latest state
    this.foregroundCallback = new ForegroundCallback(
      (style: pointer.PointerStyle): void => {
        this.applyCursorShape(style)
      },
      (): void => {
        if (this.windowId > 0) {
          applyCustomCursor(this.windowId, this.foregroundCallback.getCursorData())
        }
      },
      (): void => {
        this.restoreDefaultCursor()
      }
    )

    // Register foreground/background listener for cursor restoration
    let abilityContext = uiContext.getHostContext() as common.UIAbilityContext
    abilityContext.getApplicationContext().on('applicationStateChange', this.foregroundCallback)
  }

  private applyCursorShape(style: pointer.PointerStyle): void {
    try {
      this.cursorController.setCursor(style)
    } catch (e) {
      logger.error('Failed to set cursor shape', e)
    }
  }

  private restoreDefaultCursor(): void {
    try {
      this.cursorController.setCursor(pointer.PointerStyle.DEFAULT)
    } catch (e) {
      logger.error('Failed to restore default cursor', e)
    }
  }

  /**
   * Set custom cursor from RGBA pixel data.
   * Saves cursor state so it can be restored on foreground and cursor re-entry.
   */
  setCustomCursor(width: number, height: number, rgbaData: ArrayBuffer, hotspotX: number, hotspotY: number): void {
    let data = new CursorData()
    data.width = width
    data.height = height
    data.rgbaData = rgbaData
    data.hotspotX = hotspotX
    data.hotspotY = hotspotY
    this.foregroundCallback.saveCursorData(data)

    if (this.windowId > 0) {
      applyCustomCursor(this.windowId, data)
    }
  }

  /**
   * Set cursor shape by mapping Godot's CursorShape to OpenHarmony's PointerStyle.
   * Saves shape state so it can be restored on foreground and cursor re-entry.
   */
  setCursorShape(godotShape: number): void {
    let style = mapCursorShape(godotShape)
    this.foregroundCallback.saveShape(style)
    this.applyCursorShape(style)
  }

  /**
   * Re-apply last cursor state after system-triggered reset.
   * Call this on mouse re-entry or window focus change.
   */
  reapplyCursor(): void {
    this.foregroundCallback.reapply()
  }
}
