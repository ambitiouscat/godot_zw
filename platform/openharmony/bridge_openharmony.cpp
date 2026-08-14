/**************************************************************************/
/*  bridge_openharmony.cpp                                                */
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
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "bridge_openharmony.h"
#include "dir_access_openharmony.h"
#include "file_access_openharmony.h"
#include "os_openharmony.h"
#include "core/os/time.h"

#include <atomic>
#include <condition_variable>
#include <cstdlib>
#include <functional>
#include <mutex>
#include <string>

#ifdef TOOLS_ENABLED
#include "editor/run/editor_run_bar.h"
#endif

#include "core/config/project_settings.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/variant/variant.h"
#include "display_server_openharmony.h"
#include "main/main.h"

#include <native_vsync/native_vsync.h>

#include <dlfcn.h>
#include <sys/stat.h>

OS_OpenHarmony *os_openharmony = nullptr;
OH_NativeVSync *native_vsync = nullptr;
uint32_t step = 0;

// Restart arguments passed from ArkTS (stored for godot_init to use)
static String restart_arguments;
// Project directory set from ArkTS (persistent directory for editor projects)
static String project_directory;
static CharString project_directory_utf8;

void godot_set_restart_arguments(const char *p_arguments) {
	if (p_arguments) {
		restart_arguments = String::utf8(p_arguments);
	} else {
		restart_arguments = "";
	}
}

void godot_set_project_dir(const char *p_path) {
	if (p_path && strlen(p_path) > 0) {
		project_directory = String::utf8(p_path);
		project_directory_utf8 = project_directory.utf8();
	} else {
		project_directory = "";
		project_directory_utf8 = CharString();
	}
}

const char *godot_get_project_dir() {
	if (project_directory.is_empty()) {
		return nullptr;
	}
	return project_directory_utf8.get_data();
}

// ============================================================
// File I/O Bridge — synchronous JSON request/response via NAPI
// ============================================================

static std::mutex fs_mutex;
static std::condition_variable fs_cv;
static std::atomic<uint32_t> fs_request_id{ 0 };
static uint32_t fs_pending_id = 0;
static String fs_result_json;
static GodotFsRequestCallback fs_request_callback = nullptr;

// Set to true during godot_init to prevent bridge deadlock.
// When the JS thread is blocked inside a NAPI call, TSF callbacks
// cannot be processed, so any godot_fs_sync would hang for 30s.
std::atomic<bool> g_godot_init_in_progress{ false };

void godot_set_fs_request_callback(GodotFsRequestCallback p_callback) {
	fs_request_callback = p_callback;
}

bool godot_fs_sync(const char *p_request_json, char *p_response_json, int p_response_size) {
	// Refuse to block if called from JS thread during godot_init.
	// The TSF callback needs the JS event loop, which is blocked.
	if (g_godot_init_in_progress) {
		return false;
	}
	if (!fs_request_callback || !p_request_json || !p_response_json || p_response_size <= 0) {
		return false;
	}

	bool timed_out = false;
	{
		std::unique_lock<std::mutex> lock(fs_mutex);
		uint32_t my_id = ++fs_request_id;
		fs_result_json = "";
		fs_pending_id = my_id;

		// Inject req_id into the JSON request so the response can be
		// matched to this specific request, preventing cross-talk from
		// stale TSF callbacks of timed-out requests.
		// p_request_json starts with '{', we inject after it:
		//   {"op":"stat",...}  →  {"req_id":5,"op":"stat",...}
		char req_with_id[8192];
		int written = snprintf(req_with_id, sizeof(req_with_id), "{\"req_id\":%u,%s", my_id, p_request_json + 1);
		if (written < 0 || written >= (int)sizeof(req_with_id)) {
			fs_pending_id = 0;
			return false;
		}

		if (!fs_request_callback(req_with_id)) {
			fs_pending_id = 0;
			return false;
		}

		if (!fs_cv.wait_for(lock, std::chrono::seconds(30), [&] { return fs_pending_id != my_id; })) {
			fs_pending_id = 0;
			timed_out = true;
		}

		if (!timed_out) {
			CharString utf8 = fs_result_json.utf8();
			strncpy(p_response_json, utf8.get_data(), p_response_size - 1);
			p_response_json[p_response_size - 1] = '\0';
		}
	}
	return !timed_out;
}

void godot_fs_deliver_result(const char *p_result_json) {
	if (!p_result_json) {
		return;
	}

	// Extract req_id from response JSON to reject stale responses.
	// A timed-out request's callback may still fire and call this function
	// after the next request has already started — without req_id checking,
	// the stale response would overwrite the new request's result.
	const char *id_tag = "\"req_id\":";
	const char *id_pos = strstr(p_result_json, id_tag);
	uint32_t resp_id = 0;
	if (id_pos) {
		resp_id = (uint32_t)strtoul(id_pos + strlen(id_tag), nullptr, 10);
	}

	std::lock_guard<std::mutex> lock(fs_mutex);
	if (fs_pending_id == 0 || resp_id != fs_pending_id) {
		return; // Stale or mismatched response, discard
	}
	fs_result_json = String::utf8(p_result_json);
	fs_pending_id = 0;
	fs_cv.notify_one();
}

Mutex godot_step_mutex;
uint32_t latest_window_width = 0;
uint32_t latest_window_height = 0;
static std::atomic<bool> pending_stop_playing{ false };
int32_t latest_window_event = 0;

enum GodotStartupStep {
	STEP_TERMINATED = -1,
	STEP_SETUP,
	STEP_SHOW_LOGO,
	STEP_STARTED
};

void godot_finalize() {
	if (step == STEP_TERMINATED) {
		return;
	}
	step = STEP_TERMINATED;

	if (os_openharmony) {
		os_openharmony->main_loop_end();
		Main::cleanup();
		memdelete(os_openharmony);
		os_openharmony = nullptr;
	}

	OH_NativeVSync_Destroy(native_vsync);
	native_vsync = nullptr;
}

void godot_step(long long timestamp, void *data) {
	// First VSync callback — bridge is now safe to use.
	// godot_iterate runs on the VSync thread (not JS thread),
	// so TSF callbacks can be processed normally.
	g_godot_init_in_progress = false;

	if (step == STEP_TERMINATED) {
		return;
	}

	switch (step) {
		case STEP_SETUP:
			// Since Godot is initialized on the UI thread, main_thread_id was set to that thread's id,
			// but for Godot purposes, the main thread is the one running the game loop
			Main::setup2(true); // The logo is shown in the next frame otherwise we run into rendering issues
			step++;
			break;
		case STEP_SHOW_LOGO:
			Main::setup_boot_logo();
			step++;

			break;
		case STEP_STARTED:
			if (Main::start() != EXIT_SUCCESS) {
				return;
			}
			os_openharmony->main_loop_begin();
			step++;
			break;
		default:

			godot_step_mutex.lock();
			uint32_t current_window_width = latest_window_width;
			uint32_t current_window_height = latest_window_height;
			int32_t current_window_event = latest_window_event;
			latest_window_width = 0;
			latest_window_height = 0;
			latest_window_event = 0;
			godot_step_mutex.unlock();

			if (current_window_width != 0 && current_window_height != 0) {
				DisplayServerOpenHarmony::get_singleton()->resize_window(current_window_width, current_window_height);
			}
			if (current_window_event != 0) {
				switch (current_window_event) {
					case 1: // SHOWN
					case 2: // ACTIVE
						OS_OpenHarmony::get_singleton()->on_focus_in();
						break;
					case 3: // INACTIVE
					case 4: // HIDDEN
						OS_OpenHarmony::get_singleton()->on_focus_out();
						break;
					case 5: // RESUMED
						OS_OpenHarmony::get_singleton()->on_exit_background();
						break;
					case 6: // PAUSED
						OS_OpenHarmony::get_singleton()->on_enter_background();
						break;
				}
			}

			// Handle deferred editor run state reset (triggered by
			// abilityLifecycle observer when GameAbility dies externally).
			// Must execute on Godot main thread — NAPI callback runs on JS thread.
			if (pending_stop_playing.load(std::memory_order_acquire)) {
#ifdef TOOLS_ENABLED
				EditorRunBar *run_bar = EditorRunBar::get_singleton();
				if (run_bar) {
					run_bar->notify_external_stop();
				}
#endif
				pending_stop_playing.store(false, std::memory_order_release);
			}

			if (os_openharmony->main_loop_iterate()) {
				// If the main loop iteration returns true, it means we should exit.
				// In this case, we do not request another frame.
				godot_finalize();
				return;
			}
			break;
	}

	// Request the next frame
	OH_NativeVSync_RequestFrame(native_vsync, godot_step, nullptr);
}

int64_t godot_init(NativeResourceManager *p_resource_manager, void *p_native_window, int32_t window_id, int64_t window_width, int64_t window_height, const char *p_allowed_permissions) {
	OHNativeWindow *window = static_cast<OHNativeWindow *>(p_native_window);

	FileAccessOpenHarmony::setup(p_resource_manager);
	DirAccessOpenHarmony::setup(p_resource_manager);
	os_openharmony = memnew(OS_OpenHarmony);
	os_openharmony->set_window_id(window_id);
	os_openharmony->set_native_window(window);
	os_openharmony->set_display_size(Size2i(window_width, window_height));
	os_openharmony->set_allowed_permissions(p_allowed_permissions);

	Vector<String> args;
	String content;

	// Check if we have restart arguments from ArkTS (editor mode switch)
	if (!restart_arguments.is_empty()) {
		// Use restart arguments passed from ArkTS
		Vector<String> lines = restart_arguments.split("\n", false);
		for (const String &line : lines) {
			String arg = line.strip_edges();
			if (!arg.is_empty()) {
				args.push_back(arg);
			}
		}
		// Clear restart arguments after use
		restart_arguments = "";
	} else if (FileAccessOpenHarmony::get_rawfile_content("editor/_cl_", content) == OK && !content.is_empty()) {
		// Try editor mode CLI args first (editor/_cl_).
		// If found, run as editor. Otherwise fall back to game mode (_cl_).
		Vector<String> lines = content.split("\n", false);
		for (const String &line : lines) {
			String arg = line.strip_edges();
			if (!arg.is_empty()) {
				args.push_back(arg);
			}
		}
	} else {
		// Game mode: try _cl_ rawfile
		FileAccessOpenHarmony::get_rawfile_content("_cl_", content);
		if (!content.is_empty()) {
			Vector<String> lines = content.split("\n", false);
			for (const String &line : lines) {
				String arg = line.strip_edges();
				if (!arg.is_empty()) {
					args.push_back(arg);
				}
			}
		}
	}

	// Detect Vulkan availability: if no explicit --rendering-driver was specified,
	// try loading libvulkan.so and checking for the OHOS surface extension.
	{
		bool has_explicit_driver = false;
		for (const String &a : args) {
			if (a == "--rendering-driver" || a == "-rd") {
				has_explicit_driver = true;
				break;
			}
		}
		if (!has_explicit_driver) {
			void *vulkan_lib = dlopen("libvulkan.so", RTLD_LAZY | RTLD_LOCAL);
			if (vulkan_lib) {
				// The Vulkan loader exists, but the ICD driver may not be available
				// (e.g., on simulators). Try to create a minimal VkInstance to verify.
				typedef int (*PFN_vkCreateInstance)(const void *, const void *, void *);
				typedef void (*PFN_vkDestroyInstance)(void *, const void *);
				PFN_vkCreateInstance create_instance = (PFN_vkCreateInstance)dlsym(vulkan_lib, "vkCreateInstance");
				void *create_surface = dlsym(vulkan_lib, "vkCreateSurfaceOHOS");
				PFN_vkDestroyInstance destroy_instance = (PFN_vkDestroyInstance)dlsym(vulkan_lib, "vkDestroyInstance");
				if (create_instance && create_surface && destroy_instance) {
					// On 64-bit: VkApplicationInfo = {sType(4), padding(4), pNext(8), pAppName(8), appVer(4), engVer(4), apiVer(4)}
					// VkInstanceCreateInfo = {sType(4), padding(4), pNext(8), flags(4), padding(4), pAppInfo(8), layerCnt(4), padding(4), ppLayers(8), extCnt(4), padding(4), ppExts(8)}
					char app_info[40] = {};
					char inst_info[64] = {};
					void *test_instance = nullptr;
					*(int *)app_info = 0; // sType = VK_STRUCTURE_TYPE_APPLICATION_INFO (0)
					*(int *)inst_info = 1; // sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO (1)
					*(void **)(inst_info + 24) = app_info; // pApplicationInfo
					int err = create_instance(inst_info, nullptr, &test_instance);
					if (err == 0 && test_instance) {
						// Vulkan is available, but HarmonyOS GPU drivers (Bisheng compiler)
						// have known issues with compute pipelines. Default to GLES3 for stability.
						// Use --rendering-driver vulkan to override.
						args.push_back("--rendering-driver");
						args.push_back("opengl3");
						destroy_instance(test_instance, nullptr);
					}
				}
				dlclose(vulkan_lib);
			}
		}
	}

	const char **cmdline = nullptr;

	if (args.size() > 0) {
		cmdline = (const char **)memalloc(args.size() * sizeof(const char *));
		for (int i = 0; i < args.size(); i++) {
			CharString cs = args[i].utf8();
			char *flag = (char *)memalloc(cs.length() + 1);
			memcpy((void *)flag, cs.get_data(), cs.length() + 1);
			flag[cs.length()] = '\0';
			cmdline[i] = flag;
		}
	}


	// Prevent bridge deadlock during Main::setup on the JS thread.
	// Any file://docs/ URI that reaches godot_fs_sync will return false
	// instead of blocking the JS thread waiting for a TSF callback.
	g_godot_init_in_progress = true;

	Error err = Main::setup(OS_OpenHarmony::EXEC_PATH, args.size(), (char **)cmdline, false);

	if (cmdline) {
		for (int i = 0; i < args.size(); i++) {
			memfree((void *)cmdline[i]);
		}
		memfree(cmdline);
	}

	if (err != OK) {
		g_godot_init_in_progress = false;
		return err;
	}

	g_godot_init_in_progress = false;

	const char *connection_name = "godot";
	native_vsync = OH_NativeVSync_Create(connection_name, strlen(connection_name));
	return OH_NativeVSync_RequestFrame(native_vsync, godot_step, nullptr);
}

void godot_set_locale(const char *p_locale) {
	if (p_locale && os_openharmony) {
		// Format: "zh_CN" or "en_US" (already in Godot format from ArkTS).
		os_openharmony->set_locale(String::utf8(p_locale));
	}
}

void godot_touch(GodotTouchEvent *p_event, int count) {
	if (step <= STEP_SETUP) {
		return;
	}
	static Vector<GodotTouchEvent> last_touch_events;
	for (int i = 0; i < count; i++) {
		GodotTouchEvent &event = p_event[i];
		if (event.id >= last_touch_events.size()) {
			last_touch_events.resize(event.id + 1);
		}
		switch (event.type) {
			case 0: { // Touch begin
				Ref<InputEventScreenTouch> ev;
				ev.instantiate();
				ev->set_index(event.id);
				ev->set_pressed(true);
				ev->set_position(Vector2(event.x, event.y + 1));
				Input::get_singleton()->parse_input_event(ev);
			} break;
			case 1: { // Touch up
				Ref<InputEventScreenTouch> ev;
				ev.instantiate();
				ev->set_index(event.id);
				ev->set_pressed(false);
				ev->set_position(Vector2(event.x, event.y));
				Input::get_singleton()->parse_input_event(ev);
			} break;
			case 2: { // Touch move
				Ref<InputEventScreenDrag> ev;
				ev.instantiate();
				ev->set_index(event.id);
				ev->set_position(Vector2(event.x, event.y));
				ev->set_relative(Vector2(event.x - last_touch_events[event.id].x, event.y - last_touch_events[event.id].y));
				ev->set_relative_screen_position(ev->get_relative());
				Input::get_singleton()->parse_input_event(ev);
			} break;
			case 3: { // Touch cancel
				Ref<InputEventScreenTouch> ev;
				ev.instantiate();
				ev->set_index(event.id);
				ev->set_canceled(true);
				ev->set_position(Vector2(event.x, event.y));
				Input::get_singleton()->parse_input_event(ev);
			} break;
		}
		last_touch_events.set(event.id, event);
	}
}

void godot_mouse(GodotMouseEvent *p_event) {
	if (step <= STEP_SETUP) {
		return;
	}
	static GodotMouseEvent last_mouse_event;
	GodotMouseEvent &event = *p_event;
	switch (event.type) {
		case 0: { // Mouse down
			Ref<InputEventMouseButton> ev;
			ev.instantiate();
			ev->set_pressed(true);
			ev->set_position(Vector2(event.x, event.y));
			ev->set_global_position(ev->get_position());
			ev->set_button_index(MouseButton(event.button));
			ev->set_button_mask(BitField<MouseButtonMask>(event.mask));
			// Double-click detection: Godot relies on OS-level double-click
			// events (e.g. WM_LBUTTONDBLCLK on Windows). OpenHarmony has no
			// equivalent, so emulate it by tracking last press time/pos/button.
			{
				static uint64_t last_press_time = 0;
				static Vector2 last_press_pos;
				static MouseButton last_button = MouseButton::NONE;
				uint64_t now = Time::get_singleton()->get_ticks_msec();
				MouseButton btn = MouseButton(event.button);
				if (last_button != MouseButton::NONE && last_button == btn &&
						last_press_pos.distance_to(Vector2(event.x, event.y)) < 8.0f &&
						(now - last_press_time) < 400) {
					ev->set_double_click(true);
					last_press_time = 0; // Reset to prevent triple-click
					last_button = MouseButton::NONE;
				} else {
					last_press_time = now;
					last_press_pos = Vector2(event.x, event.y);
					last_button = btn;
				}
			}
			Input::get_singleton()->parse_input_event(ev);
		} break;
		case 1: { // Mouse up
			Ref<InputEventMouseButton> ev;
			ev.instantiate();
			ev->set_pressed(false);
			ev->set_position(Vector2(event.x, event.y));
			ev->set_global_position(ev->get_position());
			ev->set_button_index(MouseButton(event.button));
			ev->set_button_mask(BitField<MouseButtonMask>(event.mask));
			Input::get_singleton()->parse_input_event(ev);
		} break;
		case 2: { // Mouse move
			Ref<InputEventMouseMotion> ev;
			ev.instantiate();
			ev->set_device(InputEvent::DEVICE_ID_EMULATION);
			ev->set_button_mask(BitField<MouseButtonMask>(event.mask));
			ev->set_position(Vector2(event.x, event.y));
			ev->set_global_position(ev->get_position());
			ev->set_relative(Vector2(event.x - last_mouse_event.x, event.y - last_mouse_event.y));
			ev->set_relative_screen_position(ev->get_relative());
			Input::get_singleton()->parse_input_event(ev);
		} break;
	}
	last_mouse_event = event;
}

void godot_key(GodotKeyEvent *p_event) {
	if (step <= STEP_SETUP) {
		return;
	}
	GodotKeyEvent &event = *p_event;
	Ref<InputEventKey> ev;
	ev.instantiate();
	ev->set_pressed(event.pressed);
	ev->set_echo(false);
	ev->set_keycode(Key(event.code));
	ev->set_physical_keycode(Key(event.code));
	ev->set_key_label(Key(event.code));
	ev->set_unicode(event.unicode);
	ev->set_location(KeyLocation::UNSPECIFIED);
	ev->set_alt_pressed(event.alt);
	ev->set_ctrl_pressed(event.ctrl);
	ev->set_shift_pressed(event.shift);
	ev->set_meta_pressed(event.meta);
	Input::get_singleton()->parse_input_event(ev);
}

void godot_resize(uint32_t width, uint32_t height) {
	godot_step_mutex.lock();
	latest_window_width = width;
	latest_window_height = height;
	godot_step_mutex.unlock();
}

void godot_window_event(int32_t event) {
	godot_step_mutex.lock();
	latest_window_event = event;
	godot_step_mutex.unlock();
}

void godot_sensor(GodotSensorData *p_data) {
	if (step <= STEP_STARTED) {
		return;
	}
	GodotSensorData &data = *p_data;
	Vector3 val(data.x, data.y, data.z);
	if (data.type == 0) {
		Input::get_singleton()->set_accelerometer(val);
	} else if (data.type == 1) {
		Input::get_singleton()->set_gyroscope(val);
	}
}

// ============================================================
// Shell Open - Open URL functionality
// ============================================================

// Global callback set by napi layer when ArkTS is ready
static GodotShellOpenCallback shell_open_callback = nullptr;
static String pending_shell_open_uri;

void godot_set_shell_open_callback(GodotShellOpenCallback p_callback) {
	shell_open_callback = p_callback;
	
	// If there was a pending request, process it now
	if (!pending_shell_open_uri.is_empty() && shell_open_callback) {
		shell_open_callback(pending_shell_open_uri.utf8().get_data());
		pending_shell_open_uri = "";
	}
}

void godot_request_shell_open(const char *p_uri) {
	// Store the URI for later if callback not ready
	if (!shell_open_callback) {
		pending_shell_open_uri = p_uri;
		return;
	}
	
	shell_open_callback(p_uri);
}

// ============================================================
// File Dialog - File selection/save functionality
// ============================================================

// Global callback set by napi layer when ArkTS is ready
static GodotFileDialogCallback file_dialog_callback = nullptr;
static int pending_file_dialog_mode = 0;
static String pending_file_dialog_title;
static String pending_file_dialog_default_path;
static String pending_file_dialog_filters;

void godot_set_file_dialog_callback(GodotFileDialogCallback p_callback) {
	file_dialog_callback = p_callback;
}

void godot_request_file_dialog(int p_mode, const char *p_title, const char *p_default_path, const char *p_filters) {
	if (!file_dialog_callback) {
		pending_file_dialog_mode = p_mode;
		pending_file_dialog_title = p_title ? p_title : "";
		pending_file_dialog_default_path = p_default_path ? p_default_path : "";
		pending_file_dialog_filters = p_filters ? p_filters : "";
		return;
	}
	
	file_dialog_callback(p_mode, p_title, p_default_path, p_filters, nullptr, 0);
}

// Directory picker callback
static GodotDirectoryPickerCallback directory_picker_callback = nullptr;
static String pending_directory_picker_title;
static String pending_directory_picker_default_path;

void godot_set_directory_picker_callback(GodotDirectoryPickerCallback p_callback) {
	directory_picker_callback = p_callback;
	// Flush any pending request that arrived before registration.
	if (!pending_directory_picker_title.is_empty()) {
		directory_picker_callback(pending_directory_picker_title.utf8().get_data(),
				pending_directory_picker_default_path.utf8().get_data(),
				nullptr, 0);
		pending_directory_picker_title.clear();
		pending_directory_picker_default_path.clear();
	}
}

void godot_request_directory_picker(const char *p_title, const char *p_default_path) {
	if (!directory_picker_callback) {
		pending_directory_picker_title = p_title ? p_title : "";
		pending_directory_picker_default_path = p_default_path ? p_default_path : "";
		return;
	}
	directory_picker_callback(p_title, p_default_path, nullptr, 0);
}

// Terminate callback
static GodotTerminateCallback terminate_callback = nullptr;

void godot_set_terminate_callback(GodotTerminateCallback p_callback) {
	terminate_callback = p_callback;
}

void godot_request_terminate() {
	if (terminate_callback) {
		terminate_callback();
	}
}

// Window mode callback
static GodotWindowModeCallback window_mode_callback = nullptr;

void godot_set_window_mode_callback(GodotWindowModeCallback p_callback) {
	window_mode_callback = p_callback;
}

void godot_request_window_mode(int p_mode) {
	if (window_mode_callback) {
		window_mode_callback(p_mode);
	}
}

// Custom cursor callback
static GodotCustomCursorCallback custom_cursor_callback = nullptr;

void godot_set_custom_cursor_callback(GodotCustomCursorCallback p_callback) {
	custom_cursor_callback = p_callback;
}

bool godot_request_custom_cursor(int p_width, int p_height, const uint8_t *p_rgba_data, int p_data_size, int p_hotspot_x, int p_hotspot_y) {
	if (custom_cursor_callback) {
		return custom_cursor_callback(p_width, p_height, p_rgba_data, p_data_size, p_hotspot_x, p_hotspot_y);
	}
	return false;
}

// Vibration callback
static GodotVibrateCallback vibrate_callback = nullptr;

void godot_set_vibrate_callback(GodotVibrateCallback p_callback) {
	vibrate_callback = p_callback;
}

void godot_request_vibrate(int p_duration_ms) {
	if (vibrate_callback) {
		vibrate_callback(p_duration_ms);
	}
}

// Cursor shape callback
static GodotCursorShapeCallback cursor_shape_callback = nullptr;

void godot_set_cursor_shape_callback(GodotCursorShapeCallback p_callback) {
	cursor_shape_callback = p_callback;
}

void godot_request_cursor_shape(int p_shape) {
	if (cursor_shape_callback) {
		cursor_shape_callback(p_shape);
	}
}

// ============================================================
// Restart - restart app with new arguments (for editor mode switch)
// ============================================================

static GodotRestartCallback restart_callback = nullptr;

void godot_set_restart_callback(GodotRestartCallback p_callback) {
	restart_callback = p_callback;
}

void godot_request_restart(const char *p_arguments) {
	if (restart_callback) {
		restart_callback(p_arguments);
	}
}

// ============================================================
// Process kill
// ============================================================

static GodotProcessKillCallback process_kill_callback = nullptr;

void godot_set_process_kill_callback(GodotProcessKillCallback p_callback) {
	process_kill_callback = p_callback;
}

void godot_request_process_kill() {
	if (process_kill_callback) {
		process_kill_callback();
	}
}

// ============================================================
// Reset editor run state �� called from ArkTS via NAPI when
// GameAbility dies externally (X button, crash, system kill).
// ============================================================

void godot_ohos_reset_editor_run_state() {
#ifdef TOOLS_ENABLED
	pending_stop_playing.store(true, std::memory_order_release);
#else
	// Non-tools build: no-op
#endif
}

// ============================================================
// Alert dialog - simple OK dialog (OS::alert)
// ============================================================

static GodotAlertCallback alert_callback = nullptr;

void godot_set_alert_callback(GodotAlertCallback p_callback) {
	alert_callback = p_callback;
}

void godot_request_alert(const char *p_title, const char *p_message) {
	if (alert_callback) {
		alert_callback(p_title, p_message);
	}
}

// ============================================================
// Button dialog - multi-button dialog (DisplayServer::dialog_show)
// ============================================================

static GodotDialogCallback dialog_callback = nullptr;

void godot_set_dialog_callback(GodotDialogCallback p_callback) {
	dialog_callback = p_callback;
}

void godot_request_dialog(const char *p_title, const char *p_description, const char *p_buttons) {
	if (!dialog_callback) {
		return;
	}
	dialog_callback(p_title, p_description, p_buttons, nullptr, 0);
}

// Claude Code panel toggle callback
static GodotCcToggleCallback cc_toggle_callback = nullptr;

void godot_set_cc_toggle_callback(GodotCcToggleCallback p_callback) {
	cc_toggle_callback = p_callback;
}

void godot_request_toggle_cc_panel() {
	if (cc_toggle_callback) {
		cc_toggle_callback();
	}
}

// Engine command — Rust/NAPI → Godot bidirectional
// Deferred to Godot main thread via mutex/cv to avoid data races.
// Ownership protocol: all return paths use strdup(); Rust side copies then calls free().
// godot_process_engine_commands() frees the handler's strdup result after copying.

static GodotEngineCommandHandler engine_command_handler = nullptr;
static std::mutex engine_cmd_mutex;
static std::condition_variable engine_cmd_cv;
static std::string engine_cmd_request;
static std::string engine_cmd_result;
static std::atomic<bool> engine_cmd_pending{false};
static bool engine_cmd_done = false;

void godot_set_engine_command_handler(GodotEngineCommandHandler p_handler) {
	engine_command_handler = p_handler;
}

const char* godot_engine_command(const char *p_command_json) {
	if (!engine_command_handler) {
		return strdup("{\"error\":\"no handler registered\"}");
	}

	std::string local_result;

	// Store request and signal main thread
	{
		std::unique_lock<std::mutex> lock(engine_cmd_mutex);
		// Wait until the channel is free (no other thread is pending)
		engine_cmd_cv.wait(lock, [] { return !engine_cmd_pending; });

		engine_cmd_request = p_command_json ? p_command_json : "";
		engine_cmd_done = false;
		engine_cmd_pending = true;

		// Block until main thread processes the command
		engine_cmd_cv.wait(lock, [] { return engine_cmd_done; });

		// Safely copy result under lock
		local_result = engine_cmd_result;
		
		// Free the channel and wake up any other waiting request threads
		engine_cmd_pending = false;
		engine_cmd_cv.notify_all();
	}

	// strdup the result — Rust side will free() after copying
	return strdup(local_result.c_str());
}

// Called from OS_OpenHarmony::main_loop_iterate() on the Godot main thread.
// Processes one pending engine command per frame.
void godot_process_engine_commands() {
	if (!engine_cmd_pending.load(std::memory_order_acquire)) {
		return;
	}

	std::unique_lock<std::mutex> lock(engine_cmd_mutex);
	if (!engine_cmd_pending || engine_cmd_done) {
		return; // Double-checked under lock, avoid double execution if already done
	}

	std::string request = engine_cmd_request;
	lock.unlock();

	// Execute handler on MAIN THREAD (safe for Godot API access)
	const char *raw_result = engine_command_handler(request.c_str());
	
	lock.lock();
	if (raw_result) {
		engine_cmd_result = raw_result;
		// Handler returns strdup'd strings — free after copying
		free((void *)raw_result);
	} else {
		engine_cmd_result = "{\"error\":\"null result\"}";
	}

	engine_cmd_done = true;
	lock.unlock();
	engine_cmd_cv.notify_all();
}
