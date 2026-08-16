/**************************************************************************/
/*  Index.d.ts                                                            */
/**************************************************************************/

import { resourceManager } from "@kit.LocalizationKit";

export class SimplifiedTouchEvent {
	public type: number;
	public id: number;
	public x: number;
	public y: number;
}

export class SimplifiedKeyEvent {
	public code: number;
	public unicode: number;
	public pressed: boolean;
	public alt: boolean;
	public ctrl: boolean;
	public shift: boolean;
	public meta: boolean;
}

export class SimplifiedMouseEvent {
	public type: number;
	public button: number;
	public mask: number;
	public x: number;
	public y: number;
}

export class SimplifiedSensorData {
	public type: number; // 0 = accelerometer, 1 = gyroscope
	public x: number;
	public y: number;
	public z: number;
}

export const setResourceManager: (resourceManager: resourceManager.ResourceManager) => boolean;

export const setWindowId: (id: number) => boolean;

export const setSurfaceId: (id: BigInt) => boolean;

export const changeSurface: (id: BigInt, w: number, h: number) => boolean;

export const destroySurface: (id: BigInt) => boolean;

export const sendWindowEvent: (id: number) => boolean;

export const setup: (allowed_permissions: string) => boolean;

export const inputTouch: (events: SimplifiedTouchEvent[]) => void;

export const inputKey: (events: SimplifiedKeyEvent) => void;

export const inputMouse: (events: SimplifiedMouseEvent) => void;

export const inputSensor: (data: SimplifiedSensorData) => void;

// Shell open - register callback for opening URLs
export const setShellOpenCallback: (callback: (uri: string) => boolean) => void;

// File dialog - register callback for file picker
// mode: 0 = open, 1 = save
// Returns: Promise<string[]> (array of file URIs)
export const setFileDialogCallback: (
	callback: (mode: number, title: string, defaultPath: string, filters: string) => Promise<string[]>,
) => void;

// Send file dialog result back to native code
export const fileDialogResult: (result: string[]) => boolean;

// Directory picker — native folder selection (DocumentViewPicker FOLDER mode)
// callback receives (title, defaultPath), should trigger pickFolder() + persistPermission
export const setDirectoryPickerCallback: (
	callback: (title: string, defaultPath: string) => void,
) => void;

// Send directory picker result (physical path) back to native code
export const directoryPickerResult: (physicalPath: string) => boolean;

// Terminate - register callback for app termination
export const setTerminateCallback: (callback: () => void) => void;

// Custom cursor - register callback for setting custom cursor
// callback receives: width, height, rgbaData (ArrayBuffer), hotspotX, hotspotY
export const setCustomCursorCallback: (
	callback: (width: number, height: number, rgbaData: ArrayBuffer, hotspotX: number, hotspotY: number) => void,
) => void;

// Vibrate - register callback for device vibration
// callback receives: durationMs (number)
export const setVibrateCallback: (callback: (durationMs: number) => void) => void;

// Cursor shape - register callback for cursor style change
// callback receives: shape (number, maps to pointer.PointerStyle)
export const setCursorShapeCallback: (callback: (shape: number) => void) => void;

// Alert - register callback for showing a simple alert dialog (OS::alert)
// callback receives: title (string), message (string)
export const setAlertCallback: (callback: (title: string, message: string) => void) => void;

// Dialog - register callback for showing a multi-button dialog (DisplayServer::dialog_show)
// callback receives: title (string), description (string), buttons (comma-separated string)
// If buttons starts with "INPUT:", it's an input dialog with partial text after the prefix
export const setDialogCallback: (callback: (title: string, description: string, buttons: string) => void) => void;

// Send dialog result back to native code (button index)
export const dialogResult: (buttonIndex: number) => boolean;

// Send input dialog result back to native code (button index + input text)
export const inputDialogResult: (text: string) => boolean;

// Set system locale (called from ArkTS before setup)
export const setLocale: (locale: string) => void;

// Restart - register callback for app restart (editor mode switch)
// callback receives: arguments (newline-separated string)
export const setRestartCallback: (callback: (args: string) => void) => void;

// Process kill - register callback for terminating GameAbility from Editor
export const setProcessKillCallback: (callback: () => void) => void;

// Set restart arguments before engine init (used when app is restarted)
export const setRestartArguments: (args: string) => void;

// Set project directory (persistent directory for editor projects)
export const setProjectDir: (path: string) => void;
export const resetEditorRunState: () => void;

// Window mode - register callback for window mode changes (maximize, fullscreen)
export const setWindowModeCallback: (callback: (mode: number) => void) => void;
export const setCcToggleCallback: (callback: () => void) => void;

// File I/O bridge — synchronous JSON file operations via ArkTS @ohos.file.fs
export const setFsRequestCallback: (callback: (requestJson: string) => void) => void;
export const fsResult: (resultJson: string) => boolean;

// Set environment variable (calls libc setenv)
export const setEnv: (name: string, value: string) => void;

// OpenCode Bridge — Editor context & Script application & Dock geometry synchronization
export const getEditorContext: () => string;
export const applyScriptChanges: (filePath: string, newContent: string) => boolean;
export const updateResourceFile: (filePath: string) => boolean;
export const setOpenCodeDockGeometryCallback: (callback: (x: number, y: number, width: number, height: number, isVisible: boolean) => void) => boolean;
export const requestOpenCodeEditorContext: (requestId: string) => boolean;
export const requestOpenCodeEditorAction: (requestId: string, actionJson: string) => boolean;

// File content read/write: implemented as pure ArkTS utilities in FileManager.ets
// (not as NAPI functions — file:// URI I/O requires ArkTS-side @ohos.file.fs)

// ── Rust Claude Code FFI — NAPI module: claude_code_rust ──────────────
export const ccInit:      () => number;
export const ccShutdown:  () => number;
export const ccHello:     () => string;
export const ccChat:         (promptJson: string) => string | null;
export const ccListTools:    () => string;
export const ccLastError:    () => string;
export const ccToolExecute:  (name: string, argsJson: string) => string | null;
export const ccSettingsLoad: () => string;
export const ccSettingsSave: (json: string) => number;
export const ccSetStreamCallback: (callback: (chunkJson: string, isFinal: boolean) => void) => number;
export const ccClearStreamCallback: () => number;
export const ccChatStream: (promptJson: string) => number;
