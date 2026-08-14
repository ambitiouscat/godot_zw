/**************************************************************************/
/*  bridge_openharmony.h                                                  */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.       */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include <rawfile/raw_file_manager.h>
#include <atomic>
#include <cstdint>

// ============================================================
// GODOT_FS: unified debug tag for all file I/O bridge logs.
// Filter in IDE/hilog: "GODOT_FS"
// Set to 0 to compile out all bridge debug output.
// ============================================================
#define FS_BRIDGE_DEBUG 1
#define FS_BRIDGE_TAG "GODOT_FS"

// Set true during godot_init to prevent bridge deadlock.
// godot_fs_sync returns false immediately when this flag is set.
extern std::atomic<bool> g_godot_init_in_progress;

extern "C" {
typedef struct GodotTouchEvent {
	uint32_t type;
	uint32_t id;
	float x;
	float y;
} GodotTouchEvent;

typedef struct GodotKeyEvent {
	uint32_t code;
	char32_t unicode;
	bool pressed;
	bool alt;
	bool ctrl;
	bool shift;
	bool meta;
} GodotKeyEvent;

typedef struct GodotMouseEvent {
	uint32_t type;
	uint32_t button;
	uint32_t mask;
	float x;
	float y;
} GodotMouseEvent;

typedef struct GodotSensorData {
	uint32_t type; // 0 = accelerometer, 1 = gyroscope
	float x;
	float y;
	float z;
} GodotSensorData;

// Callback for shell_open (called from ArkTS layer)
typedef bool (*GodotShellOpenCallback)(const char *p_uri);

// Callback for file dialog (called from ArkTS layer)
// Returns: true if file selected, false otherwise
// The selected URI is stored in the callback implementation
typedef bool (*GodotFileDialogCallback)(int p_mode, const char *p_title, const char *p_default_path, const char *p_filters, char *p_result, int p_result_size);

int64_t godot_init(NativeResourceManager *p_resource_manager, void *p_native_window, int32_t window_id, int64_t window_width, int64_t window_height, const char *p_allowed_permissions);
void godot_touch(GodotTouchEvent *p_event, int count);
void godot_mouse(GodotMouseEvent *p_event);
void godot_key(GodotKeyEvent *p_event);
void godot_resize(uint32_t width, uint32_t height);
void godot_window_event(int32_t event);
void godot_sensor(GodotSensorData *p_data);

// Shell open - request ArkTS to open a URL
void godot_request_shell_open(const char *p_uri);

// Set callback for shell_open result (called from ArkTS)
void godot_set_shell_open_callback(GodotShellOpenCallback p_callback);

// File dialog - request ArkTS to show file picker
void godot_request_file_dialog(int p_mode, const char *p_title, const char *p_default_path, const char *p_filters);

// Called when file dialog result is ready - declared in display_server_openharmony.cpp
extern void godot_emit_file_dialog_callback(const char *p_selected_path);

// Set callback for file dialog result (called from ArkTS)
void godot_set_file_dialog_callback(GodotFileDialogCallback p_callback);

// Directory picker — request ArkTS to show native folder picker (DocumentViewPicker FOLDER mode)
// Separate from file dialog to avoid mode confusion (FILE_MODE_OPEN_DIR maps to same mode=0 as files).
typedef bool (*GodotDirectoryPickerCallback)(const char *p_title, const char *p_default_path, char *p_result, int p_result_size);
void godot_request_directory_picker(const char *p_title, const char *p_default_path);
void godot_set_directory_picker_callback(GodotDirectoryPickerCallback p_callback);
extern void godot_emit_directory_picker_callback(const char *p_selected_path);

// Claude Code panel toggle — engine requests ArkTS to show/hide the CC chat panel
typedef void (*GodotCcToggleCallback)(void);
void godot_request_toggle_cc_panel();
void godot_set_cc_toggle_callback(GodotCcToggleCallback p_callback);

// Engine command channel — Rust/NAPI sends command to Godot, gets JSON result.
// Commands are deferred to the Godot main thread (called from godot_process_engine_commands)
// to avoid data races on EditorNode / SceneTree / EditorSelection.
typedef const char* (*GodotEngineCommandHandler)(const char *p_command_json);
void godot_set_engine_command_handler(GodotEngineCommandHandler p_handler);
const char* godot_engine_command(const char *p_command_json);
void godot_process_engine_commands();

// Window mode — request ArkTS to set maximize, fullscreen, or windowed.
// 0=WINDOWED, 2=MAXIMIZED, 3=FULLSCREEN, 4=EXCLUSIVE_FULLSCREEN
typedef void (*GodotWindowModeCallback)(int p_mode);
void godot_request_window_mode(int p_mode);
void godot_set_window_mode_callback(GodotWindowModeCallback p_callback);

// Request app termination - calls the registered callback to terminate the ability
void godot_request_terminate();

// Set callback for terminate (called from ArkTS)
typedef void (*GodotTerminateCallback)();
void godot_set_terminate_callback(GodotTerminateCallback p_callback);

// Custom cursor - request ArkTS to set custom cursor image
// Returns: true if successful, false otherwise
typedef bool (*GodotCustomCursorCallback)(int p_width, int p_height, const uint8_t *p_rgba_data, int p_data_size, int p_hotspot_x, int p_hotspot_y);
void godot_set_custom_cursor_callback(GodotCustomCursorCallback p_callback);

// Vibration - request ArkTS to vibrate the device
typedef void (*GodotVibrateCallback)(int p_duration_ms);
void godot_set_vibrate_callback(GodotVibrateCallback p_callback);
void godot_request_vibrate(int p_duration_ms);

// Cursor shape - request ArkTS to change the system cursor style
typedef void (*GodotCursorShapeCallback)(int p_shape);
void godot_set_cursor_shape_callback(GodotCursorShapeCallback p_callback);
void godot_request_cursor_shape(int p_shape);

// Alert dialog - show a simple OK dialog (called from OS::alert)
typedef void (*GodotAlertCallback)(const char *p_title, const char *p_message);
void godot_set_alert_callback(GodotAlertCallback p_callback);
void godot_request_alert(const char *p_title, const char *p_message);

// Button dialog - show dialog with multiple buttons (called from DisplayServer::dialog_show)
// Returns: true if dialog was shown, false otherwise
// The selected button index is sent back via godot_emit_dialog_callback
typedef bool (*GodotDialogCallback)(const char *p_title, const char *p_description, const char *p_buttons, char *p_result, int p_result_size);
void godot_set_dialog_callback(GodotDialogCallback p_callback);
void godot_request_dialog(const char *p_title, const char *p_description, const char *p_buttons);

// Called when dialog result is ready - declared in display_server_openharmony.cpp
extern void godot_emit_dialog_callback(int p_button_index);
extern void godot_emit_input_dialog_callback(const char *p_text);

// Restart callback - request ArkTS to restart the app with new arguments
// Arguments are newline-separated (e.g., "--editor\n--path\n/data/...")
typedef void (*GodotRestartCallback)(const char *p_arguments);
void godot_set_restart_callback(GodotRestartCallback p_callback);
void godot_request_restart(const char *p_arguments);

// Process kill — sends kill signal to running GameAbility from Editor
typedef void (*GodotProcessKillCallback)();
void godot_set_process_kill_callback(GodotProcessKillCallback p_callback);
void godot_request_process_kill();

// Reset editor run state — called from ArkTS via NAPI when GameAbility dies
// externally (X button, crash, system kill). Resets EditorRun::status to STOP.
void godot_ohos_reset_editor_run_state();

// Set restart arguments passed from ArkTS (used when app is restarted)
void godot_set_restart_arguments(const char *p_arguments);

// Set project directory (persistent directory for editor projects, from ArkTS)
void godot_set_project_dir(const char *p_path);

// Get project directory (for editor to use as default project path)
const char *godot_get_project_dir();

// File I/O bridge — synchronous JSON request/response via NAPI
// Allows C++ to perform file operations on paths outside the app sandbox
// by delegating to ArkTS @ohos.file.fs through a thread-safe function.
typedef bool (*GodotFsRequestCallback)(const char *p_request_json);
bool godot_fs_sync(const char *p_request_json, char *p_response_json, int p_response_size);
void godot_fs_deliver_result(const char *p_result_json);
void godot_set_fs_request_callback(GodotFsRequestCallback p_callback);

// Set system locale from ArkTS (e.g., "zh-Hans-CN")
// Must be called before godot_init, or at least before the editor/project manager starts
void godot_set_locale(const char *p_locale);
}
