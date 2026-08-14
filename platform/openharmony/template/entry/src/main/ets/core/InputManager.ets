/**************************************************************************/
/*  InputManager.ets                                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/

import plugin, { SimplifiedKeyEvent, SimplifiedMouseEvent, SimplifiedTouchEvent } from 'libentry.so';
import { KeyCode } from '@kit.InputKit';

export class InputManager {
  // Long-press → right-click detection
  private longPressTimer: number | null = null
  private longPressStartX: number = 0
  private longPressStartY: number = 0
  private longPressActive: boolean = false
  private readonly LONG_PRESS_MS: number = 500
  private readonly LONG_PRESS_MOVE_THRESHOLD: number = 30 // px

  // Track mouse button state for reliable mask during drag.
  // HarmonyOS may not populate event.pressedButtons on Move events
  // for external mice, causing mask=0 → gizmo ignores the drag.
  private currentMouseMask: number = 0

  convertMouseButton(button: MouseButton): number {
    switch (button) {
      case MouseButton.Left:
        return 1;
      case MouseButton.Right:
        return 2;
      case MouseButton.Middle:
        return 3;
      case MouseButton.Forward:
        return 8;
      case MouseButton.Back:
        return 9;
    }
    return 0;
  }

  convertMouseAction(action: MouseAction): number {
    switch (action) {
      case MouseAction.Press:
        return 0;
      case MouseAction.Release:
        return 1;
    }
    return 2;
  }

  handleTouch(events: SimplifiedTouchEvent[]): void {
    let touchEvents: SimplifiedTouchEvent[] = [];
    for (let index = 0; index < events.length; index++) {
      const touch = events[index];
      touchEvents.push({
        type: touch.type,
        id: touch.id,
        x: touch.x,
        y: touch.y,
      });
      // Track touch for long-press detection (first finger in array)
      if (index === 0) {
        this.trackLongPress(touch);
      }
    }
    plugin.inputTouch(touchEvents);
  }

  private trackLongPress(touch: SimplifiedTouchEvent): void {
    switch (touch.type) {
      case TouchType.Down: // Touch begin
        this.cancelLongPress();
        this.longPressStartX = touch.x;
        this.longPressStartY = touch.y;
        this.longPressActive = true;
        // Start timer for long press
        this.longPressTimer = setTimeout(() => {
          if (this.longPressActive) {
            // Send right-click press
            let rightClick: SimplifiedMouseEvent = {
              type: 0, // Press
              button: 2, // Right button
              mask: 2, // Right button mask (1 << (2-1))
              x: touch.x,
              y: touch.y,
            };
            plugin.inputMouse(rightClick);
            // Send right-click release
            rightClick.type = 1; // Release
            rightClick.mask = 0;
            plugin.inputMouse(rightClick);
          }
          this.longPressTimer = null;
        }, this.LONG_PRESS_MS);
        break;
      case TouchType.Up: // Touch end / cancel
        this.cancelLongPress();
        break;
      case TouchType.Move: // Touch move
        // Cancel if moved too far from start position
        if (this.longPressActive) {
          let dx = touch.x - this.longPressStartX;
          let dy = touch.y - this.longPressStartY;
          if (Math.sqrt(dx * dx + dy * dy) > this.LONG_PRESS_MOVE_THRESHOLD) {
            this.cancelLongPress();
          }
        }
        break;
      case TouchType.Cancel: // Touch cancel
        this.cancelLongPress();
        break;
    }
  }

  private cancelLongPress(): void {
    this.longPressActive = false;
    if (this.longPressTimer !== null) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = null;
    }
  }

  handleMouse(event: MouseEvent, ctx: UIContext): void {
    let button = this.convertMouseButton(event.button)
    let type = this.convertMouseAction(event.action)

    // Track button state ourselves — HarmonyOS may not reliably
    // report pressedButtons during Move events for external mice.
    // Godot MouseButtonMask: LEFT=(1<<0)=1, RIGHT=(1<<1)=2, MIDDLE=(1<<2)=4.
    // convertMouseButton returns Godot enum (1=LEFT, 2=RIGHT, ...),
    // so shift by (button-1) to get the correct mask bit.
    if (type === 0 && button !== 0) {
      this.currentMouseMask |= (1 << (button - 1))
    } else if (type === 1 && button !== 0) {
      this.currentMouseMask &= ~(1 << (button - 1))
    }

    if (button == 0 && type != 2) {
      return;
    }
    let mask = this.currentMouseMask
    // Merge system reported pressedButtons if available (defense in depth)
    if (event.pressedButtons) {
      for (let index = 0; index < event.pressedButtons.length; index++) {
        mask |= 1 << (this.convertMouseButton(event.pressedButtons[index]) - 1)
      }
    }
    let mouseEvent: SimplifiedMouseEvent = {
      type: type,
      button: button,
      mask: mask,
      x: ctx.vp2px(event.x),
      y: ctx.vp2px(event.y),
    };
    plugin.inputMouse(mouseEvent);
  }

  // HarmonyOS XComponent SURFACE does not dispatch Mouse Move events
  // through .onMouse. Use .onHover to detect drag motion when a button
  // is held (tracked via currentMouseMask).
  handleHover(event: HoverEvent, ctx: UIContext): void {
    if (this.currentMouseMask !== 0) {
      let mouseEvent: SimplifiedMouseEvent = {
        type: 2, // Move
        button: 0,
        mask: this.currentMouseMask,
        x: ctx.vp2px(event.x),
        y: ctx.vp2px(event.y),
      };
      plugin.inputMouse(mouseEvent);
    }
  }

  handleAxisEvent(event: AxisEvent, ctx: UIContext): void {
    if (!event.scrollStep) {
      return;
    }
    let value = event.getVerticalAxisValue()
    if (value != 0) {
      let mouseEvent: SimplifiedMouseEvent = {
        type: this.convertMouseAction(MouseAction.Press),
        button: value > 0 ? 5 : 4,
        mask: 0,
        x: ctx.vp2px(event.x),
        y: ctx.vp2px(event.y),
      };
      plugin.inputMouse(mouseEvent);
      mouseEvent.type = this.convertMouseAction(MouseAction.Release);
      plugin.inputMouse(mouseEvent);
    }
    value = event.getHorizontalAxisValue()
    if (value != 0) {
      let mouseEvent: SimplifiedMouseEvent = {
        type: this.convertMouseAction(MouseAction.Press),
        button: value > 0 ? 7 : 6,
        mask: 0,
        x: ctx.vp2px(event.x),
        y: ctx.vp2px(event.y),
      };
      plugin.inputMouse(mouseEvent);
      mouseEvent.type = this.convertMouseAction(MouseAction.Release);
      plugin.inputMouse(mouseEvent);
    }
  }

  handleKeyEvent(event: KeyEvent): void {
    let code = mapKeyCode(event.keyCode);
    if (code == 0) {
      return;
    }
    let keyEvent: SimplifiedKeyEvent = {
      code: code,
      unicode: event.unicode ? event.unicode! : 0,
      pressed: event.type == KeyType.Down,
      alt: getModifierKeyStateSafe(event, ['alt']),
      ctrl: getModifierKeyStateSafe(event, ['ctrl']),
      shift: getModifierKeyStateSafe(event, ['shift']),
      meta: event.metaKey != 0,
    };
    plugin.inputKey(keyEvent);
  }
}

function getModifierKeyStateSafe(event: KeyEvent, keys: string[]): boolean {
  try {
    return event.getModifierKeyState ? event.getModifierKeyState(keys) : false
  } catch (e) {
    return false
  }
}

function mapKeyCode(keyCode: KeyCode): number {
  const SPECIAL = (1 << 22);

  switch (keyCode) {
    case KeyCode.KEYCODE_ESCAPE:
      return SPECIAL | 0x01;
    case KeyCode.KEYCODE_TAB:
      return SPECIAL | 0x02;
    case KeyCode.KEYCODE_DEL:
      return SPECIAL | 0x04;
    case KeyCode.KEYCODE_ENTER:
      return SPECIAL | 0x05;
    case KeyCode.KEYCODE_NUMPAD_ENTER:
      return SPECIAL | 0x06;
    case KeyCode.KEYCODE_INSERT:
      return SPECIAL | 0x07;
    case KeyCode.KEYCODE_FORWARD_DEL:
      return SPECIAL | 0x08;
    case KeyCode.KEYCODE_BREAK:
      return SPECIAL | 0x09;
    case KeyCode.KEYCODE_DPAD_LEFT:
      return SPECIAL | 0x0F;
    case KeyCode.KEYCODE_DPAD_UP:
      return SPECIAL | 0x10;
    case KeyCode.KEYCODE_DPAD_RIGHT:
      return SPECIAL | 0x11;
    case KeyCode.KEYCODE_DPAD_DOWN:
      return SPECIAL | 0x12;
    case KeyCode.KEYCODE_SHIFT_LEFT:
    case KeyCode.KEYCODE_SHIFT_RIGHT:
      return SPECIAL | 0x15;
    case KeyCode.KEYCODE_CTRL_LEFT:
    case KeyCode.KEYCODE_CTRL_RIGHT:
      return SPECIAL | 0x16;
    case KeyCode.KEYCODE_META_LEFT:
    case KeyCode.KEYCODE_META_RIGHT:
      return SPECIAL | 0x17;
    case KeyCode.KEYCODE_ALT_LEFT:
    case KeyCode.KEYCODE_ALT_RIGHT:
      return SPECIAL | 0x18;
    // Number keys 0-9 (top row)
    case KeyCode.KEYCODE_0:
      return 0x0030;
    case KeyCode.KEYCODE_1:
      return 0x0031;
    case KeyCode.KEYCODE_2:
      return 0x0032;
    case KeyCode.KEYCODE_3:
      return 0x0033;
    case KeyCode.KEYCODE_4:
      return 0x0034;
    case KeyCode.KEYCODE_5:
      return 0x0035;
    case KeyCode.KEYCODE_6:
      return 0x0036;
    case KeyCode.KEYCODE_7:
      return 0x0037;
    case KeyCode.KEYCODE_8:
      return 0x0038;
    case KeyCode.KEYCODE_9:
      return 0x0039;
    // Numpad 0-9
    case KeyCode.KEYCODE_NUMPAD_0:
      return SPECIAL | 0x20;
    case KeyCode.KEYCODE_NUMPAD_1:
      return SPECIAL | 0x21;
    case KeyCode.KEYCODE_NUMPAD_2:
      return SPECIAL | 0x22;
    case KeyCode.KEYCODE_NUMPAD_3:
      return SPECIAL | 0x23;
    case KeyCode.KEYCODE_NUMPAD_4:
      return SPECIAL | 0x24;
    case KeyCode.KEYCODE_NUMPAD_5:
      return SPECIAL | 0x25;
    case KeyCode.KEYCODE_NUMPAD_6:
      return SPECIAL | 0x26;
    case KeyCode.KEYCODE_NUMPAD_7:
      return SPECIAL | 0x27;
    case KeyCode.KEYCODE_NUMPAD_8:
      return SPECIAL | 0x28;
    case KeyCode.KEYCODE_NUMPAD_9:
      return SPECIAL | 0x29;
    // Numpad operators
    case KeyCode.KEYCODE_NUMPAD_ADD:
      return SPECIAL | 0x2A;
    case KeyCode.KEYCODE_NUMPAD_SUBTRACT:
      return SPECIAL | 0x2B;
    case KeyCode.KEYCODE_NUMPAD_MULTIPLY:
      return SPECIAL | 0x2C;
    case KeyCode.KEYCODE_NUMPAD_DIVIDE:
      return SPECIAL | 0x2D;
    case KeyCode.KEYCODE_NUMPAD_DOT:
      return SPECIAL | 0x2E;
    // Punctuation and symbols
    case KeyCode.KEYCODE_STAR:
      return 0x002A; // *
    case KeyCode.KEYCODE_POUND:
      return 0x0023; // #
    case KeyCode.KEYCODE_COMMA:
      return 0x002C; // ,
    case KeyCode.KEYCODE_PERIOD:
      return 0x002E; // .
    case KeyCode.KEYCODE_SLASH:
      return 0x002F; // /
    case KeyCode.KEYCODE_BACKSLASH:
      return 0x005C; // backslash
    case KeyCode.KEYCODE_SEMICOLON:
      return 0x003B; // ;
    case KeyCode.KEYCODE_APOSTROPHE:
      return 0x0027; // '
    case KeyCode.KEYCODE_GRAVE:
      return 0x0060; // `
    case KeyCode.KEYCODE_LEFT_BRACKET:
      return 0x005B; // [
    case KeyCode.KEYCODE_RIGHT_BRACKET:
      return 0x005D; // ]
    case KeyCode.KEYCODE_MINUS:
      return 0x002D; // -
    case KeyCode.KEYCODE_EQUALS:
      return 0x003D; // =
    // Letters A-Z
    case KeyCode.KEYCODE_A:
      return 0x0041;
    case KeyCode.KEYCODE_B:
      return 0x0042;
    case KeyCode.KEYCODE_C:
      return 0x0043;
    case KeyCode.KEYCODE_D:
      return 0x0044;
    case KeyCode.KEYCODE_E:
      return 0x0045;
    case KeyCode.KEYCODE_F:
      return 0x0046;
    case KeyCode.KEYCODE_G:
      return 0x0047;
    case KeyCode.KEYCODE_H:
      return 0x0048;
    case KeyCode.KEYCODE_I:
      return 0x0049;
    case KeyCode.KEYCODE_J:
      return 0x004A;
    case KeyCode.KEYCODE_K:
      return 0x004B;
    case KeyCode.KEYCODE_L:
      return 0x004C;
    case KeyCode.KEYCODE_M:
      return 0x004D;
    case KeyCode.KEYCODE_N:
      return 0x004E;
    case KeyCode.KEYCODE_O:
      return 0x004F;
    case KeyCode.KEYCODE_P:
      return 0x0050;
    case KeyCode.KEYCODE_Q:
      return 0x0051;
    case KeyCode.KEYCODE_R:
      return 0x0052;
    case KeyCode.KEYCODE_S:
      return 0x0053;
    case KeyCode.KEYCODE_T:
      return 0x0054;
    case KeyCode.KEYCODE_U:
      return 0x0055;
    case KeyCode.KEYCODE_V:
      return 0x0056;
    case KeyCode.KEYCODE_W:
      return 0x0057;
    case KeyCode.KEYCODE_X:
      return 0x0058;
    case KeyCode.KEYCODE_Y:
      return 0x0059;
    case KeyCode.KEYCODE_Z:
      return 0x005A;
    case KeyCode.KEYCODE_SPACE:
      return 0x0020;
    default:
      return 0;
  }
}
