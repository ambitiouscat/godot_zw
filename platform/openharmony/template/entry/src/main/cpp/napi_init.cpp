/**************************************************************************/
/*  napi_init.cpp                                                         */
/**************************************************************************/

#include "include/napi_bridge.h"
#include <hilog/log.h>
#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <rawfile/raw_file_manager.h>
#include <filemanagement/file_uri/oh_file_uri.h>
#include <cstdint>
#include <vector>
#include <cstring>
#include <string>
#include <atomic>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "LIB_ENTRY"

static NativeResourceManager *resourceManager = nullptr;
static OHNativeWindow *nativeWindow = nullptr;
static int32_t windowId = -1;
static uint32_t windowWidth = 0;
static uint32_t windowHeight = 0;
bool g_initialized = false;

static napi_value NAPI_Global_setResourceManager(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	resourceManager = OH_ResourceManager_InitNativeResourceManager(env, args[0]);
	return nullptr;
}

static napi_value NAPI_Global_setWindowId(napi_env env, napi_callback_info info) {
	if (windowId != -1) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	if (napi_ok != napi_get_value_int32(env, args[0], &windowId)) {
		return nullptr;
	}
	return nullptr;
}

static napi_value NAPI_Global_setSurfaceId(napi_env env, napi_callback_info info) {
	if (nativeWindow != nullptr) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	int64_t surfaceId = 0;
	bool lossless = true;
	if (napi_ok != napi_get_value_bigint_int64(env, args[0], &surfaceId, &lossless)) {
		return nullptr;
	}
	OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &nativeWindow);
	return nullptr;
}

static napi_value NAPI_Global_changeSurface(napi_env env, napi_callback_info info) {
	if (nativeWindow == nullptr) {
		return nullptr;
	}
	size_t argc = 3;
	napi_value args[3] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	int64_t surfaceId = 0;
	bool lossless = true;
	if (napi_ok != napi_get_value_bigint_int64(env, args[0], &surfaceId, &lossless)) {
		return nullptr;
	}
	if (napi_ok != napi_get_value_uint32(env, args[1], &windowWidth)) {
		return nullptr;
	}
	if (napi_ok != napi_get_value_uint32(env, args[2], &windowHeight)) {
		return nullptr;
	}
	if (g_initialized) {
		godot_resize(windowWidth, windowHeight);
	}
	return nullptr;
}

static napi_value NAPI_Global_destroySurface(napi_env env, napi_callback_info info) {
	if (nativeWindow == nullptr) {
		return nullptr;
	}
	OH_NativeWindow_DestroyNativeWindow(nativeWindow);
	nativeWindow = nullptr;
	return nullptr;
}

static napi_value NAPI_Global_setup(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	char allowed_permissions[2048];
	if (napi_ok != napi_get_value_string_utf8(env, args[0], &allowed_permissions[0], 2048, nullptr)) {
		return nullptr;
	}
	const int64_t init_result = godot_init(resourceManager, nativeWindow, windowId, windowWidth, windowHeight, &allowed_permissions[0]);
	if (init_result != 0) {
		OH_LOG_ERROR(LOG_APP, "godot_init failed: %{public}lld", static_cast<long long>(init_result));
		g_initialized = false;
		napi_value failed;
		napi_get_boolean(env, false, &failed);
		return failed;
	}
	g_initialized = true;
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_sendWindowEvent(napi_env env, napi_callback_info info) {
	if (!g_initialized) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	int32_t event = 0;
	if (napi_ok != napi_get_value_int32(env, args[0], &event)) {
		return nullptr;
	}
	godot_window_event(event);
	return nullptr;
}

extern void napi_input_register(napi_env env, napi_value exports);

// Forward declaration for file dialog callback - implemented in display_server_openharmony.cpp
extern void godot_emit_file_dialog_callback(const char *p_selected_path);

// ============================================================
// Shell Open - ThreadSafe Function
// ============================================================

static napi_threadsafe_function shell_open_tsf = nullptr;

struct ShellOpenData {
	char uri[512];
};

static void shell_open_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	ShellOpenData* shell_data = static_cast<ShellOpenData*>(data);

	if (!callback || !shell_data) {
		delete shell_data;
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value uri_str;
	napi_create_string_utf8(env, shell_data->uri, NAPI_AUTO_LENGTH, &uri_str);

	napi_value result;
	napi_call_function(env, undefined, callback, 1, &uri_str, &result);

	delete shell_data;
}

static bool napi_shell_open_callback(const char* p_uri) {
	if (!shell_open_tsf || !p_uri) {
		return false;
	}

	ShellOpenData* data = new ShellOpenData();
	strncpy(data->uri, p_uri, sizeof(data->uri) - 1);
	data->uri[sizeof(data->uri) - 1] = '\0';

	napi_call_threadsafe_function(shell_open_tsf, data, napi_tsfn_nonblocking);

	return true;
}

static napi_value NAPI_Global_setShellOpenCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "shell_open_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		shell_open_tsf_callback, &shell_open_tsf
	);

	godot_set_shell_open_callback(napi_shell_open_callback);

	return nullptr;
}

// ============================================================
// File Dialog - Using async callback pattern
// ============================================================

static napi_threadsafe_function file_dialog_tsf = nullptr;
static napi_env file_dialog_env = nullptr;

// File dialog result storage (accessed from both threads)
static std::vector<std::string> g_file_dialog_result;
static std::atomic<bool> g_file_dialog_ready{false};

struct FileDialogData {
	int mode;
	char title[256];
	char default_path[512];
	char filters[1024];
};

static void file_dialog_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	FileDialogData* dialog_data = static_cast<FileDialogData*>(data);

	if (!callback || !dialog_data) {
		delete dialog_data;
		return;
	}

	file_dialog_env = env;

	// Call the JavaScript callback with parameters
	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value mode_val;
	napi_create_int32(env, dialog_data->mode, &mode_val);

	napi_value title_val;
	napi_create_string_utf8(env, dialog_data->title, NAPI_AUTO_LENGTH, &title_val);

	napi_value path_val;
	napi_create_string_utf8(env, dialog_data->default_path, NAPI_AUTO_LENGTH, &path_val);

	napi_value filters_val;
	napi_create_string_utf8(env, dialog_data->filters, NAPI_AUTO_LENGTH, &filters_val);

	napi_value js_args[4] = { mode_val, title_val, path_val, filters_val };

	// Call the JS callback - it returns a Promise
	napi_value result_array;
	napi_call_function(env, undefined, callback, 4, js_args, &result_array);

	// Note: We can't wait for the promise here in the TSF callback
	// The result will be sent back via a separate NAPI call

	delete dialog_data;
}

static bool napi_file_dialog_callback(int p_mode, const char *p_title, const char *p_default_path, const char *p_filters, char *p_result, int p_result_size) {
	if (!file_dialog_tsf) {
		return false;
	}

	// Reset result state
	g_file_dialog_result.clear();
	g_file_dialog_ready.store(false);

	FileDialogData* data = new FileDialogData();
	data->mode = p_mode;

	if (p_title) {
		strncpy(data->title, p_title, sizeof(data->title) - 1);
		data->title[sizeof(data->title) - 1] = '\0';
	} else {
		data->title[0] = '\0';
	}

	if (p_default_path) {
		strncpy(data->default_path, p_default_path, sizeof(data->default_path) - 1);
		data->default_path[sizeof(data->default_path) - 1] = '\0';
	} else {
		data->default_path[0] = '\0';
	}

	if (p_filters) {
		strncpy(data->filters, p_filters, sizeof(data->filters) - 1);
		data->filters[sizeof(data->filters) - 1] = '\0';
	} else {
		data->filters[0] = '\0';
	}

	// Queue the call to main thread - this shows the picker
	napi_call_threadsafe_function(file_dialog_tsf, data, napi_tsfn_nonblocking);

	// Return immediately - the actual result will come via fileDialogResult
	return false;
}

// ============================================================
// Directory Picker TSF (Thread-Safe Function) — triggered when
// Godot PM Browse button needs native folder selection.
// ============================================================

static napi_threadsafe_function directory_picker_tsf = nullptr;

struct DirectoryPickerData {
	char title[256];
	char default_path[512];
};

static void directory_picker_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	DirectoryPickerData* picker_data = static_cast<DirectoryPickerData*>(data);
	if (!callback || !picker_data) {
		delete picker_data;
		return;
	}
	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value title_val;
	napi_create_string_utf8(env, picker_data->title, NAPI_AUTO_LENGTH, &title_val);

	napi_value path_val;
	napi_create_string_utf8(env, picker_data->default_path, NAPI_AUTO_LENGTH, &path_val);

	napi_value js_args[2] = { title_val, path_val };
	napi_call_function(env, undefined, callback, 2, js_args, nullptr);

	delete picker_data;
}

static bool napi_directory_picker_callback(const char *p_title, const char *p_default_path, char *p_result, int p_result_size) {
	if (!directory_picker_tsf) {
		return false;
	}
	DirectoryPickerData* data = new DirectoryPickerData();
	if (p_title) {
		strncpy(data->title, p_title, sizeof(data->title) - 1);
		data->title[sizeof(data->title) - 1] = '\0';
	} else {
		data->title[0] = '\0';
	}
	if (p_default_path) {
		strncpy(data->default_path, p_default_path, sizeof(data->default_path) - 1);
		data->default_path[sizeof(data->default_path) - 1] = '\0';
	} else {
		data->default_path[0] = '\0';
	}
	napi_call_threadsafe_function(directory_picker_tsf, data, napi_tsfn_nonblocking);
	return false;
}

// NAPI function to receive the directory picker result from ArkTS
static napi_value NAPI_Global_directoryPickerResult(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	char buffer[2048];
	size_t copied = 0;
	napi_get_value_string_utf8(env, args[0], buffer, sizeof(buffer), &copied);
	if (copied > 0) {
		std::string path = buffer;
		char* result_path = nullptr;
		FileManagement_ErrCode err = OH_FileUri_GetPathFromUri(buffer, copied, &result_path);
		if (err == 0 && result_path != nullptr) {
			path = result_path;
			free(result_path);
		} else if (path.find("file://") == 0) {
			path = path.substr(7);
		}
		godot_emit_directory_picker_callback(path.c_str());
	} else {
		godot_emit_directory_picker_callback("");
	}
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_setDirectoryPickerCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}
	napi_value resource_name;
	napi_create_string_utf8(env, "directory_picker_tsf", NAPI_AUTO_LENGTH, &resource_name);
	napi_value async_resource;
	napi_create_object(env, &async_resource);
	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		directory_picker_tsf_callback, &directory_picker_tsf
	);
	godot_set_directory_picker_callback(napi_directory_picker_callback);
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// NAPI function to receive the file dialog result from ArkTS
static napi_value NAPI_Global_fileDialogResult(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	// Get the array of file URIs
	napi_value result_array = args[0];

	uint32_t length = 0;
	napi_get_array_length(env, result_array, &length);

	g_file_dialog_result.clear();

	// Process each URI and convert to real path
	if (length > 0) {
		for (uint32_t i = 0; i < length; i++) {
			napi_value item;
			napi_get_element(env, result_array, i, &item);

		char buffer[2048];
		size_t copied = 0;
		napi_get_value_string_utf8(env, item, buffer, sizeof(buffer), &copied);

		if (copied > 0) {
			std::string path = buffer;
			OH_LOG_INFO(LOG_APP, "Original URI: %s", buffer);

			// Try to convert URI to path using native API
			char* result_path = nullptr;
			FileManagement_ErrCode err = OH_FileUri_GetPathFromUri(buffer, copied, &result_path);

			if (err == 0 && result_path != nullptr) {
				path = result_path;
				free(result_path);
				OH_LOG_INFO(LOG_APP, "OH_FileUri_GetPathFromUri result: %s", path.c_str());
			} else {
				// Fallback: strip file:// prefix but need to handle docs/storage path
				// file://docs/storage/... -> /docs/storage/...
				if (path.find("file://") == 0) {
					path = path.substr(7);  // Remove file://
					// The result should be /docs/storage/...
				}
				OH_LOG_INFO(LOG_APP, "Fallback path: %s", path.c_str());
			}

			g_file_dialog_result.push_back(path);

			// Emit callback to Godot with processed path
			godot_emit_file_dialog_callback(path.c_str());
			}
		}
	} else {
		// No file selected
		godot_emit_file_dialog_callback("");
	}

	g_file_dialog_ready.store(true);

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_setFileDialogCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "file_dialog_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		file_dialog_tsf_callback, &file_dialog_tsf
	);

	godot_set_file_dialog_callback(napi_file_dialog_callback);

	OH_LOG_INFO(LOG_APP, "File dialog TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ============================================================
// Terminate callback - called when Godot wants to quit
// ============================================================

static void terminate_callback_fn(napi_env env, napi_value callback, void* context, void* data) {
	// Call the JavaScript callback which will terminate the ability
	napi_value undefined;
	napi_get_undefined(env, &undefined);
	napi_value result;
	napi_call_function(env, undefined, callback, 0, nullptr, &result);
}

static napi_threadsafe_function terminate_tsf = nullptr;

static void napi_terminate_callback() {
	if (!terminate_tsf) {
		return;
	}
	napi_call_threadsafe_function(terminate_tsf, nullptr, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setTerminateCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "terminate_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		terminate_callback_fn, &terminate_tsf
	);

	godot_set_terminate_callback(napi_terminate_callback);

	OH_LOG_INFO(LOG_APP, "Terminate callback TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ============================================================
// Custom cursor callback - called when Godot wants to set custom cursor
// ============================================================

struct CustomCursorData {
	int width;
	int height;
	int hotspot_x;
	int hotspot_y;
	std::vector<uint8_t> rgba_data;
};

static void custom_cursor_callback_fn(napi_env env, napi_value callback, void* context, void* data) {
	CustomCursorData* cursor_data = static_cast<CustomCursorData*>(data);
	if (!callback || !cursor_data) {
		delete cursor_data;
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	// Create ArrayBuffer from RGBA data
	void* buffer = nullptr;
	napi_value array_buffer;
	napi_create_arraybuffer(env, cursor_data->rgba_data.size(), &buffer, &array_buffer);
	memcpy(buffer, cursor_data->rgba_data.data(), cursor_data->rgba_data.size());

	// Create arguments: width, height, rgbaData, hotspotX, hotspotY
	napi_value args[5];
	napi_create_int32(env, cursor_data->width, &args[0]);
	napi_create_int32(env, cursor_data->height, &args[1]);
	args[2] = array_buffer;
	napi_create_int32(env, cursor_data->hotspot_x, &args[3]);
	napi_create_int32(env, cursor_data->hotspot_y, &args[4]);

	napi_value result;
	napi_call_function(env, undefined, callback, 5, args, &result);

	delete cursor_data;
}

static napi_threadsafe_function custom_cursor_tsf = nullptr;

static bool napi_custom_cursor_callback(int p_width, int p_height, const uint8_t *p_rgba_data, int p_data_size, int p_hotspot_x, int p_hotspot_y) {
	if (!custom_cursor_tsf) {
		return false;
	}

	CustomCursorData* data = new CustomCursorData();
	data->width = p_width;
	data->height = p_height;
	data->hotspot_x = p_hotspot_x;
	data->hotspot_y = p_hotspot_y;
	data->rgba_data.assign(p_rgba_data, p_rgba_data + p_data_size);

	napi_call_threadsafe_function(custom_cursor_tsf, data, napi_tsfn_nonblocking);
	return true;
}

static napi_value NAPI_Global_setCustomCursorCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "custom_cursor_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		custom_cursor_callback_fn, &custom_cursor_tsf
	);

	godot_set_custom_cursor_callback(napi_custom_cursor_callback);

	OH_LOG_INFO(LOG_APP, "Custom cursor TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ============================================================
// Vibration callback - called when Godot wants to vibrate
// ============================================================

static napi_threadsafe_function vibrate_tsf = nullptr;

struct VibrateData {
	int duration_ms;
};

static void vibrate_callback_fn(napi_env env, napi_value callback, void* context, void* data) {
	VibrateData* vib_data = static_cast<VibrateData*>(data);
	if (!callback || !vib_data) {
		delete vib_data;
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value duration_val;
	napi_create_int32(env, vib_data->duration_ms, &duration_val);

	napi_value js_args[1] = { duration_val };
	napi_value result;
	napi_call_function(env, undefined, callback, 1, js_args, &result);

	delete vib_data;
}

static void napi_vibrate_callback(int p_duration_ms) {
	if (!vibrate_tsf) {
		return;
	}
	VibrateData* data = new VibrateData{p_duration_ms};
	napi_call_threadsafe_function(vibrate_tsf, data, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setVibrateCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "vibrate_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		vibrate_callback_fn, &vibrate_tsf
	);

	godot_set_vibrate_callback(napi_vibrate_callback);

	OH_LOG_INFO(LOG_APP, "Vibrate callback TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ============================================================
// Cursor shape callback - called when Godot wants to change cursor style
// ============================================================

static napi_threadsafe_function cursor_shape_tsf = nullptr;

static void cursor_shape_callback_fn(napi_env env, napi_value callback, void* context, void* data) {
	int shape = (int)(intptr_t)data;
	if (!callback) {
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value shape_val;
	napi_create_int32(env, shape, &shape_val);

	napi_value js_args[1] = { shape_val };
	napi_value result;
	napi_call_function(env, undefined, callback, 1, js_args, &result);
}

static void napi_cursor_shape_callback(int p_shape) {
	if (!cursor_shape_tsf) {
		return;
	}
	napi_call_threadsafe_function(cursor_shape_tsf, (void*)(intptr_t)p_shape, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setCursorShapeCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "cursor_shape_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		cursor_shape_callback_fn, &cursor_shape_tsf
	);

	godot_set_cursor_shape_callback(napi_cursor_shape_callback);

	OH_LOG_INFO(LOG_APP, "Cursor shape TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ============================================================
// Alert Dialog - Fire-and-forget (OS::alert)
// ============================================================

// Process kill callback — sends kill signal to GameAbility from Editor
static napi_threadsafe_function process_kill_tsf = nullptr;

static void process_kill_tsf_callback(napi_env env, napi_value callback, void *, void *) {
	if (!callback) {
		return;
	}
	napi_value undefined;
	napi_get_undefined(env, &undefined);
	napi_value result;
	napi_call_function(env, undefined, callback, 0, nullptr, &result);
}

static void napi_process_kill_callback() {
	if (!process_kill_tsf) {
		return;
	}
	napi_call_threadsafe_function(process_kill_tsf, nullptr, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setProcessKillCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "process_kill_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		process_kill_tsf_callback, &process_kill_tsf
	);

	godot_set_process_kill_callback(napi_process_kill_callback);

	OH_LOG_INFO(LOG_APP, "Process kill callback TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// Runtime first-frame callback — forwarded from the engine thread to ArkTS.
// This is intentionally separate from window lifecycle callbacks: a WindowStage
// can exist before the Godot main loop has completed a frame.
static napi_threadsafe_function runtime_ready_tsf = nullptr;

static void runtime_ready_tsf_callback(napi_env env, napi_value callback, void *, void *) {
	if (!callback) {
		return;
	}
	napi_value undefined;
	napi_get_undefined(env, &undefined);
	napi_value result;
	napi_call_function(env, undefined, callback, 0, nullptr, &result);
}

static void napi_runtime_ready_callback() {
	if (runtime_ready_tsf) {
		napi_call_threadsafe_function(runtime_ready_tsf, nullptr, napi_tsfn_nonblocking);
	}
}

static napi_value NAPI_Global_setRuntimeReadyCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "runtime_ready_tsf", NAPI_AUTO_LENGTH, &resource_name);
	napi_value async_resource;
	napi_create_object(env, &async_resource);
	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		runtime_ready_tsf_callback, &runtime_ready_tsf
	);
	godot_set_runtime_ready_callback(napi_runtime_ready_callback);

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// --- alert callback ---
static napi_threadsafe_function alert_tsf = nullptr;

static void alert_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	char** alert_data = static_cast<char**>(data);
	if (!callback || !alert_data) {
		if (alert_data) {
			delete[] alert_data[0];
			delete[] alert_data[1];
			delete[] alert_data;
		}
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value title_val;
	napi_create_string_utf8(env, alert_data[0], NAPI_AUTO_LENGTH, &title_val);

	napi_value msg_val;
	napi_create_string_utf8(env, alert_data[1], NAPI_AUTO_LENGTH, &msg_val);

	napi_value js_args[2] = { title_val, msg_val };
	napi_value result;
	napi_call_function(env, undefined, callback, 2, js_args, &result);

	delete[] alert_data[0];
	delete[] alert_data[1];
	delete[] alert_data;
}

static void napi_alert_callback(const char *p_title, const char *p_message) {
	if (!alert_tsf) {
		return;
	}

	char** data = new char*[2];
	data[0] = new char[strlen(p_title) + 1];
	strcpy(data[0], p_title);
	data[1] = new char[strlen(p_message) + 1];
	strcpy(data[1], p_message);

	napi_call_threadsafe_function(alert_tsf, data, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setAlertCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "alert_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		alert_tsf_callback, &alert_tsf
	);

	godot_set_alert_callback(napi_alert_callback);

	OH_LOG_INFO(LOG_APP, "Alert TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ============================================================
// Dialog - Multi-button dialog (DisplayServer::dialog_show)
// ============================================================

struct DialogData {
	char title[256];
	char description[512];
	char buttons[2048];
};

static napi_threadsafe_function dialog_tsf = nullptr;

static void dialog_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	DialogData* dialog_data = static_cast<DialogData*>(data);
	if (!callback || !dialog_data) {
		delete dialog_data;
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value title_val;
	napi_create_string_utf8(env, dialog_data->title, NAPI_AUTO_LENGTH, &title_val);

	napi_value desc_val;
	napi_create_string_utf8(env, dialog_data->description, NAPI_AUTO_LENGTH, &desc_val);

	napi_value buttons_val;
	napi_create_string_utf8(env, dialog_data->buttons, NAPI_AUTO_LENGTH, &buttons_val);

	napi_value js_args[3] = { title_val, desc_val, buttons_val };
	napi_value result;
	napi_call_function(env, undefined, callback, 3, js_args, &result);

	delete dialog_data;
}

static bool napi_dialog_callback(const char *p_title, const char *p_description, const char *p_buttons, char *p_result, int p_result_size) {
	if (!dialog_tsf) {
		return false;
	}

	DialogData* data = new DialogData();

	if (p_title) {
		strncpy(data->title, p_title, sizeof(data->title) - 1);
		data->title[sizeof(data->title) - 1] = '\0';
	} else {
		data->title[0] = '\0';
	}

	if (p_description) {
		strncpy(data->description, p_description, sizeof(data->description) - 1);
		data->description[sizeof(data->description) - 1] = '\0';
	} else {
		data->description[0] = '\0';
	}

	if (p_buttons) {
		strncpy(data->buttons, p_buttons, sizeof(data->buttons) - 1);
		data->buttons[sizeof(data->buttons) - 1] = '\0';
	} else {
		data->buttons[0] = '\0';
	}

	napi_call_threadsafe_function(dialog_tsf, data, napi_tsfn_nonblocking);
	return true;
}

static napi_value NAPI_Global_setDialogCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "dialog_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		dialog_tsf_callback, &dialog_tsf
	);

	godot_set_dialog_callback(napi_dialog_callback);

	OH_LOG_INFO(LOG_APP, "Dialog TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_dialogResult(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	int32_t button_index = 0;
	napi_get_value_int32(env, args[0], &button_index);

	godot_emit_dialog_callback(button_index);

	napi_value result;
	napi_get_undefined(env, &result);
	return result;
}

static napi_value NAPI_Global_inputDialogResult(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	// Get string length first
	size_t str_len = 0;
	napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);

	std::string text(str_len, '\0');
	napi_get_value_string_utf8(env, args[0], &text[0], str_len + 1, &str_len);

	godot_emit_input_dialog_callback(text.c_str());

	napi_value result;
	napi_get_undefined(env, &result);
	return result;
}

static napi_value NAPI_Global_setLocale(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	size_t str_len = 0;
	napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);
	std::string locale(str_len, '\0');
	napi_get_value_string_utf8(env, args[0], &locale[0], str_len + 1, &str_len);

	godot_set_locale(locale.c_str());

	napi_value result;
	napi_get_undefined(env, &result);
	return result;
}

// ============================================================
// Restart callback - called when Godot wants to restart the app
// ============================================================

struct RestartData {
	char arguments[8192];
};

static napi_threadsafe_function restart_tsf = nullptr;

static void restart_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	RestartData* restart_data = static_cast<RestartData*>(data);
	if (!callback || !restart_data) {
		delete restart_data;
		return;
	}

	napi_value undefined;
	napi_get_undefined(env, &undefined);

	napi_value args_val;
	napi_create_string_utf8(env, restart_data->arguments, NAPI_AUTO_LENGTH, &args_val);

	napi_value js_args[1] = { args_val };
	napi_value result;
	napi_call_function(env, undefined, callback, 1, js_args, &result);

	delete restart_data;
}

static void napi_restart_callback(const char *p_arguments) {
	if (!restart_tsf || !p_arguments) {
		return;
	}

	RestartData* data = new RestartData();
	strncpy(data->arguments, p_arguments, sizeof(data->arguments) - 1);
	data->arguments[sizeof(data->arguments) - 1] = '\0';

	napi_call_threadsafe_function(restart_tsf, data, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setRestartCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value resource_name;
	napi_create_string_utf8(env, "restart_tsf", NAPI_AUTO_LENGTH, &resource_name);

	napi_value async_resource;
	napi_create_object(env, &async_resource);

	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		restart_tsf_callback, &restart_tsf
	);

	godot_set_restart_callback(napi_restart_callback);

	OH_LOG_INFO(LOG_APP, "Restart callback TSF created");

	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// NAPI function to set restart arguments from ArkTS (before engine init)
static napi_value NAPI_Global_setRestartArguments(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	// Get string length first
	size_t str_len = 0;
	napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);

	std::string args_str(str_len, '\0');
	napi_get_value_string_utf8(env, args[0], &args_str[0], str_len + 1, &str_len);

	godot_set_restart_arguments(args_str.c_str());

	OH_LOG_INFO(LOG_APP, "Restart arguments set: %s", args_str.c_str());

	napi_value result;
	napi_get_undefined(env, &result);
	return result;
}

// Supply the authoritative GameAbility capture context before godot_init.
// This is intentionally a dedicated API rather than the generic setEnv API:
// native code validates all three tokens before it can inject an Autoload.
static napi_value NAPI_Global_setRuntimeScreenshotContext(napi_env env, napi_callback_info info) {
	size_t argc = 3;
	napi_value args[3] = { nullptr, nullptr, nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) || argc != 3) {
		return nullptr;
	}

	std::string values[3];
	for (size_t index = 0; index < 3; index++) {
		size_t value_length = 0;
		if (napi_ok != napi_get_value_string_utf8(env, args[index], nullptr, 0, &value_length) || value_length == 0 || value_length > 160) {
			napi_value failed;
			napi_get_boolean(env, false, &failed);
			return failed;
		}
		values[index].resize(value_length + 1);
		if (napi_ok != napi_get_value_string_utf8(env, args[index], &values[index][0], values[index].size(), &value_length)) {
			napi_value failed;
			napi_get_boolean(env, false, &failed);
			return failed;
		}
		values[index].resize(value_length);
	}

	const bool accepted = godot_set_runtime_screenshot_context(values[0].c_str(), values[1].c_str(), values[2].c_str());
	napi_value result;
	napi_get_boolean(env, accepted, &result);
	return result;
}

// ============================================================
// Set project directory - user-chosen persistent directory for editor
// ============================================================

static napi_value NAPI_Global_setProjectDir(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	size_t str_len = 0;
	napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len);

	std::string path(str_len, '\0');
	napi_get_value_string_utf8(env, args[0], &path[0], str_len + 1, &str_len);

	godot_set_project_dir(path.c_str());

	OH_LOG_INFO(LOG_APP, "Project directory set: %s", path.c_str());

	napi_value result;
	napi_get_undefined(env, &result);
	return result;
}

	// ============================================================
	// File I/O Bridge — synchronous JSON request/response via TSF
	// ============================================================

	static napi_threadsafe_function fs_request_tsf = nullptr;

	struct FsRequestData {
		char request[4096];
	};

	static void fs_request_tsf_callback(napi_env env, napi_value callback, void *context, void *data) {
		FsRequestData *req = static_cast<FsRequestData *>(data);
		if (!callback || !req) {
			delete req;
			return;
		}
		napi_value undefined;
		napi_get_undefined(env, &undefined);
		napi_value request_str;
		napi_create_string_utf8(env, req->request, NAPI_AUTO_LENGTH, &request_str);
		napi_value result;
		napi_call_function(env, undefined, callback, 1, &request_str, &result);
		delete req;
	}

	static bool napi_fs_request_callback(const char *p_request_json) {
		if (!fs_request_tsf || !p_request_json) {
			return false;
		}
		FsRequestData *data = new FsRequestData();
		strncpy(data->request, p_request_json, sizeof(data->request) - 1);
		data->request[sizeof(data->request) - 1] = '\0';
		napi_status status = napi_call_threadsafe_function(fs_request_tsf, data, napi_tsfn_nonblocking);
		if (status != napi_ok) {
			delete data;
			return false;
		}
		return true;
	}

	static napi_value NAPI_Global_setFsRequestCallback(napi_env env, napi_callback_info info) {
		size_t argc = 1;
		napi_value args[1] = { nullptr };
		if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
			return nullptr;
		}

		napi_value resource_name;
		napi_create_string_utf8(env, "fs_request_tsf", NAPI_AUTO_LENGTH, &resource_name);
		napi_value async_resource;
		napi_create_object(env, &async_resource);

		napi_create_threadsafe_function(
			env, args[0], async_resource, resource_name,
			0, 1, nullptr, nullptr, nullptr,
			fs_request_tsf_callback, &fs_request_tsf);

		godot_set_fs_request_callback(napi_fs_request_callback);
		return nullptr;
	}

	static napi_value NAPI_Global_fsResult(napi_env env, napi_callback_info info) {
		size_t argc = 1;
		napi_value args[1] = { nullptr };
		if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
			return nullptr;
		}

		size_t str_len = 0;
		if (napi_ok != napi_get_value_string_utf8(env, args[0], nullptr, 0, &str_len)) {
			return nullptr;
		}
		std::string result(str_len, '\0');
		if (napi_ok != napi_get_value_string_utf8(env, args[0], &result[0], str_len + 1, &str_len)) {
			return nullptr;
		}

		godot_fs_deliver_result(result.c_str());
		return nullptr;
	}

	// Set environment variable (calls libc setenv)
	// ============================================================

	static napi_value NAPI_Global_setEnv(napi_env env, napi_callback_info info) {
		size_t argc = 2;
		napi_value args[2] = { nullptr };
		if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
			return nullptr;
		}

		char name_buf[256] = { 0 };
		char value_buf[512] = { 0 };
		size_t len = 0;

		if (argc > 0 && napi_ok == napi_get_value_string_utf8(env, args[0], name_buf, sizeof(name_buf), &len) && len > 0) {
			if (argc > 1 && napi_ok == napi_get_value_string_utf8(env, args[1], value_buf, sizeof(value_buf), &len)) {
				setenv(name_buf, value_buf, 1);
			}
		}

		napi_value result;
		napi_get_undefined(env, &result);
		return result;
	}

static napi_value NAPI_ResetEditorRunState(napi_env env, napi_callback_info info) {
	godot_ohos_reset_editor_run_state();
	return nullptr;
}

EXTERN_C_START
// ============================================================
// Window mode callback - Godot requests window maximize/fullscreen.
// ============================================================

static napi_threadsafe_function window_mode_tsf = nullptr;

static void window_mode_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	int mode = (int)(intptr_t)data;
	if (!callback) return;
	napi_value undefined, mode_val, js_args[1];
	napi_get_undefined(env, &undefined);
	napi_create_int32(env, mode, &mode_val);
	js_args[0] = mode_val;
	napi_value result;
	napi_call_function(env, undefined, callback, 1, js_args, &result);
}

static void napi_window_mode_callback(int p_mode) {
	if (!window_mode_tsf) return;
	napi_call_threadsafe_function(window_mode_tsf, (void*)(intptr_t)p_mode, napi_tsfn_nonblocking);
}

static napi_value NAPI_Global_setWindowModeCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
	napi_value resource_name;
	napi_create_string_utf8(env, "window_mode_tsf", NAPI_AUTO_LENGTH, &resource_name);
	napi_value async_resource;
	napi_create_object(env, &async_resource);
	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		window_mode_tsf_callback, &window_mode_tsf
	);
	godot_set_window_mode_callback(napi_window_mode_callback);
	OH_LOG_INFO(LOG_APP, "Window mode TSF created");
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

// ── Claude Code panel toggle TSF ──────────────────────────────────────

static napi_threadsafe_function cc_toggle_tsf = nullptr;

static void cc_toggle_tsf_callback(napi_env env, napi_value callback, void* context, void* data) {
	if (!callback) return;
	napi_value undefined;
	napi_get_undefined(env, &undefined);
	napi_value result;
	napi_call_function(env, undefined, callback, 0, nullptr, &result);
}

static void napi_cc_toggle_callback() {
	if (cc_toggle_tsf) {
		napi_call_threadsafe_function(cc_toggle_tsf, nullptr, napi_tsfn_nonblocking);
	}
}

static napi_value NAPI_Global_setCcToggleCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
	napi_value resource_name;
	napi_create_string_utf8(env, "cc_toggle_tsf", NAPI_AUTO_LENGTH, &resource_name);
	napi_value async_resource;
	napi_create_object(env, &async_resource);
	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		cc_toggle_tsf_callback, &cc_toggle_tsf
	);
	godot_set_cc_toggle_callback(napi_cc_toggle_callback);
	OH_LOG_INFO(LOG_APP, "CC toggle TSF created");
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_getEditorContext(napi_env env, napi_callback_info info) {
	const char *json_str = godot_get_editor_context_json();
	napi_value result;
	if (json_str) {
		napi_create_string_utf8(env, json_str, NAPI_AUTO_LENGTH, &result);
		free((void *)json_str);
	} else {
		napi_create_string_utf8(env, "{}", NAPI_AUTO_LENGTH, &result);
	}
	return result;
}

static napi_value NAPI_Global_applyScriptChanges(napi_env env, napi_callback_info info) {
	size_t argc = 2;
	napi_value args[2] = { nullptr, nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) || argc < 2) {
		napi_value false_val;
		napi_get_boolean(env, false, &false_val);
		return false_val;
	}
	size_t path_len = 0;
	napi_get_value_string_utf8(env, args[0], nullptr, 0, &path_len);
	std::string path(path_len, '\0');
	napi_get_value_string_utf8(env, args[0], &path[0], path_len + 1, &path_len);

	size_t content_len = 0;
	napi_get_value_string_utf8(env, args[1], nullptr, 0, &content_len);
	std::string content(content_len, '\0');
	napi_get_value_string_utf8(env, args[1], &content[0], content_len + 1, &content_len);

	bool ok = godot_apply_script_changes(path.c_str(), content.c_str());
	napi_value result;
	napi_get_boolean(env, ok, &result);
	return result;
}

static napi_value NAPI_Global_updateResourceFile(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) || argc < 1) {
		napi_value false_val;
		napi_get_boolean(env, false, &false_val);
		return false_val;
	}
	size_t path_len = 0;
	napi_get_value_string_utf8(env, args[0], nullptr, 0, &path_len);
	std::string path(path_len, '\0');
	napi_get_value_string_utf8(env, args[0], &path[0], path_len + 1, &path_len);

	bool ok = godot_update_resource_file(path.c_str());
	napi_value result;
	napi_get_boolean(env, ok, &result);
	return result;
}

struct OpenCodeDockGeometryData {
	float x;
	float y;
	float width;
	float height;
	bool is_visible;
};

static napi_threadsafe_function g_opencode_dock_tsf = nullptr;

static void opencode_dock_tsf_callback(napi_env env, napi_value js_callback, void *context, void *data) {
	if (env == nullptr || js_callback == nullptr) {
		if (data) {
			delete static_cast<OpenCodeDockGeometryData *>(data);
		}
		return;
	}
	OpenCodeDockGeometryData *geom = static_cast<OpenCodeDockGeometryData *>(data);
	if (!geom) {
		return;
	}

	napi_value argv[5];
	napi_create_double(env, geom->x, &argv[0]);
	napi_create_double(env, geom->y, &argv[1]);
	napi_create_double(env, geom->width, &argv[2]);
	napi_create_double(env, geom->height, &argv[3]);
	napi_get_boolean(env, geom->is_visible, &argv[4]);

	napi_value undefined, result;
	napi_get_undefined(env, &undefined);
	napi_call_function(env, undefined, js_callback, 5, argv, &result);
	delete geom;
}

static void napi_opencode_dock_geometry_callback(float p_x, float p_y, float p_width, float p_height, bool p_is_visible) {
	if (g_opencode_dock_tsf) {
		OpenCodeDockGeometryData *data = new OpenCodeDockGeometryData{ p_x, p_y, p_width, p_height, p_is_visible };
		napi_call_threadsafe_function(g_opencode_dock_tsf, data, napi_tsfn_nonblocking);
	}
}

static napi_value NAPI_Global_setOpenCodeDockGeometryCallback(napi_env env, napi_callback_info info) {
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
	napi_value resource_name;
	napi_create_string_utf8(env, "opencode_dock_tsf", NAPI_AUTO_LENGTH, &resource_name);
	napi_value async_resource;
	napi_create_object(env, &async_resource);
	napi_create_threadsafe_function(
		env, args[0], async_resource, resource_name,
		0, 1, nullptr, nullptr, nullptr,
		opencode_dock_tsf_callback, &g_opencode_dock_tsf
	);
	godot_set_opencode_dock_geometry_callback(napi_opencode_dock_geometry_callback);
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_requestOpenCodeEditorContext(napi_env env, napi_callback_info info) {
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value NAPI_Global_requestOpenCodeEditorAction(napi_env env, napi_callback_info info) {
	napi_value result;
	napi_get_boolean(env, true, &result);
	return result;
}

static napi_value Init(napi_env env, napi_value exports) {
	napi_property_descriptor desc[] = {
		{ "setResourceManager", nullptr, NAPI_Global_setResourceManager, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setSurfaceId", nullptr, NAPI_Global_setSurfaceId, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "changeSurface", nullptr, NAPI_Global_changeSurface, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "destroySurface", nullptr, NAPI_Global_destroySurface, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setup", nullptr, NAPI_Global_setup, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setWindowId", nullptr, NAPI_Global_setWindowId, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "sendWindowEvent", nullptr, NAPI_Global_sendWindowEvent, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setShellOpenCallback", nullptr, NAPI_Global_setShellOpenCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setFileDialogCallback", nullptr, NAPI_Global_setFileDialogCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "fileDialogResult", nullptr, NAPI_Global_fileDialogResult, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setDirectoryPickerCallback", nullptr, NAPI_Global_setDirectoryPickerCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "directoryPickerResult", nullptr, NAPI_Global_directoryPickerResult, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setTerminateCallback", nullptr, NAPI_Global_setTerminateCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setCustomCursorCallback", nullptr, NAPI_Global_setCustomCursorCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setVibrateCallback", nullptr, NAPI_Global_setVibrateCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setCursorShapeCallback", nullptr, NAPI_Global_setCursorShapeCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setAlertCallback", nullptr, NAPI_Global_setAlertCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setDialogCallback", nullptr, NAPI_Global_setDialogCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "dialogResult", nullptr, NAPI_Global_dialogResult, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "inputDialogResult", nullptr, NAPI_Global_inputDialogResult, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setLocale", nullptr, NAPI_Global_setLocale, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setProcessKillCallback", nullptr, NAPI_Global_setProcessKillCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setRuntimeReadyCallback", nullptr, NAPI_Global_setRuntimeReadyCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
	{ "setRestartCallback", nullptr, NAPI_Global_setRestartCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setRestartArguments", nullptr, NAPI_Global_setRestartArguments, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setRuntimeScreenshotContext", nullptr, NAPI_Global_setRuntimeScreenshotContext, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setProjectDir", nullptr, NAPI_Global_setProjectDir, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setFsRequestCallback", nullptr, NAPI_Global_setFsRequestCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "fsResult", nullptr, NAPI_Global_fsResult, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setEnv", nullptr, NAPI_Global_setEnv, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "resetEditorRunState", nullptr, NAPI_ResetEditorRunState, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setWindowModeCallback", nullptr, NAPI_Global_setWindowModeCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setCcToggleCallback", nullptr, NAPI_Global_setCcToggleCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "getEditorContext", nullptr, NAPI_Global_getEditorContext, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "applyScriptChanges", nullptr, NAPI_Global_applyScriptChanges, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "updateResourceFile", nullptr, NAPI_Global_updateResourceFile, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "setOpenCodeDockGeometryCallback", nullptr, NAPI_Global_setOpenCodeDockGeometryCallback, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "requestOpenCodeEditorContext", nullptr, NAPI_Global_requestOpenCodeEditorContext, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "requestOpenCodeEditorAction", nullptr, NAPI_Global_requestOpenCodeEditorAction, nullptr, nullptr, nullptr, napi_default, nullptr }
	};
	napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

	napi_input_register(env, exports);

	return exports;
}
EXTERN_C_END

static napi_module demoModule = {
	.nm_version = 1,
	.nm_flags = 0,
	.nm_filename = nullptr,
	.nm_register_func = Init,
	.nm_modname = "entry",
	.nm_priv = ((void *)0),
	.reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
	napi_module_register(&demoModule);
}
