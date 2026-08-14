/**************************************************************************/
/*  display_server_openharmony.cpp                                        */
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

#include "display_server_openharmony.h"
#include "bridge_openharmony.h"
#include "os_openharmony.h"

#include "core/input/input.h"
#include "rendering_context_driver_vulkan_openharmony.h"
#include "wrapper_openharmony.h"

#include "scene/resources/texture.h"

#include "servers/rendering/renderer_rd/renderer_compositor_rd.h"
#include "servers/rendering/rendering_device.h"

#ifdef GLES3_ENABLED
#include "drivers/gles3/rasterizer_gles3.h"
#endif

#include <database/pasteboard/oh_pasteboard.h>
#include <database/udmf/udmf.h>
#include <database/udmf/uds.h>

void DisplayServerOpenHarmony::_dispatch_input_events(const Ref<InputEvent> &p_event) {
	get_singleton()->send_input_event(p_event);
}

DisplayServerOpenHarmony *DisplayServerOpenHarmony::get_singleton() {
	return static_cast<DisplayServerOpenHarmony *>(DisplayServer::get_singleton());
}

Vector<String> DisplayServerOpenHarmony::get_rendering_drivers_func() {
	Vector<String> drivers;
#ifdef GLES3_ENABLED
	drivers.push_back("opengl3");
#endif
#ifdef VULKAN_ENABLED
	drivers.push_back("vulkan");
#endif
	return drivers;
}

DisplayServer *DisplayServerOpenHarmony::create_func(const String &p_rendering_driver, DisplayServerEnums::WindowMode p_mode, DisplayServerEnums::VSyncMode p_vsync_mode, uint32_t p_flags, const Vector2i *p_position, const Vector2i &p_resolution, int p_screen, DisplayServerEnums::Context p_context, int64_t p_parent_window, Error &r_error) {
	DisplayServer *ds = memnew(DisplayServerOpenHarmony(p_rendering_driver, p_mode, p_vsync_mode, p_flags, p_position, p_resolution, p_screen, p_context, p_parent_window, r_error));
	if (r_error != OK) {
		if (p_rendering_driver == "vulkan") {
			OS::get_singleton()->alert(
					"Your device seems not to support the required Vulkan version.\n\n"
					"Please try exporting your game using the 'gl_compatibility' renderer.",
					"Unable to initialize Vulkan video driver");
		} else {
			OS::get_singleton()->alert(
					"Your device seems not to support the required OpenGL ES 3.0 version.",
					"Unable to initialize OpenGL video driver");
		}
	}
	return ds;
}

void DisplayServerOpenHarmony::register_openharmony_driver() {
	register_create_function("openharmony", create_func, get_rendering_drivers_func);
}

DisplayServerOpenHarmony::DisplayServerOpenHarmony(const String &p_rendering_driver, DisplayServerEnums::WindowMode p_mode, DisplayServerEnums::VSyncMode p_vsync_mode, uint32_t p_flags, const Vector2i *p_position, const Vector2i &p_resolution, int p_screen, DisplayServerEnums::Context p_context, int64_t p_parent_window, Error &r_error) {
	native_menu = memnew(NativeMenu);
	rendering_driver = p_rendering_driver;

	rendering_context = nullptr;
	rendering_device = nullptr;

	OHNativeWindow *native_window = OS_OpenHarmony::get_singleton()->get_native_window();
	ERR_FAIL_NULL(native_window);

#if defined(GLES3_ENABLED)
	if (rendering_driver == "opengl3") {
		// Load EGL library dynamically via GLAD.
		if (!gladLoaderLoadEGL(EGL_NO_DISPLAY)) {
			ERR_PRINT("Failed to load EGL library.");
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Get the default EGL display.
		egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
		if (egl_display == EGL_NO_DISPLAY) {
			ERR_PRINT("Failed to get EGL display.");
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Initialize EGL.
		EGLint egl_major, egl_minor;
		if (!eglInitialize(egl_display, &egl_major, &egl_minor)) {
			ERR_PRINT("Failed to initialize EGL.");
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Reload GLAD with a real display to get full EGL extensions.
		if (!gladLoaderLoadEGL(egl_display)) {
			ERR_PRINT("Failed to reload EGL library with display.");
			eglTerminate(egl_display);
			egl_display = EGL_NO_DISPLAY;
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Bind OpenGL ES API.
		eglBindAPI(EGL_OPENGL_ES_API);

		// Choose an EGL config matching OpenGL ES 3.0.
		EGLint egl_attrib_list[] = {
			EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
			EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
			EGL_RED_SIZE, 8,
			EGL_GREEN_SIZE, 8,
			EGL_BLUE_SIZE, 8,
			EGL_ALPHA_SIZE, 8,
			EGL_DEPTH_SIZE, 24,
			EGL_STENCIL_SIZE, 8,
			EGL_NONE
		};
		EGLint config_count;
		EGLConfig egl_config;
		if (!eglChooseConfig(egl_display, egl_attrib_list, &egl_config, 1, &config_count) || config_count == 0) {
			ERR_PRINT("Failed to choose EGL config.");
			eglTerminate(egl_display);
			egl_display = EGL_NO_DISPLAY;
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Create an EGL window surface from the native window handle.
		egl_surface = eglCreateWindowSurface(egl_display, egl_config, (EGLNativeWindowType)native_window, nullptr);
		if (egl_surface == EGL_NO_SURFACE) {
			ERR_PRINT(vformat("Failed to create EGL window surface, error: 0x%x", eglGetError()));
			eglTerminate(egl_display);
			egl_display = EGL_NO_DISPLAY;
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Create an OpenGL ES 3.0 context.
		EGLint context_attribs[] = {
			EGL_CONTEXT_CLIENT_VERSION, 3,
			EGL_NONE
		};
		egl_context = eglCreateContext(egl_display, egl_config, EGL_NO_CONTEXT, context_attribs);
		if (egl_context == EGL_NO_CONTEXT) {
			ERR_PRINT("Failed to create EGL context.");
			eglDestroySurface(egl_display, egl_surface);
			egl_surface = EGL_NO_SURFACE;
			eglTerminate(egl_display);
			egl_display = EGL_NO_DISPLAY;
			r_error = ERR_UNAVAILABLE;
			return;
		}

		// Bind the EGL context and surface.
		if (!eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context)) {
			ERR_PRINT("Failed to make EGL context current.");
			eglDestroyContext(egl_display, egl_context);
			egl_context = EGL_NO_CONTEXT;
			eglDestroySurface(egl_display, egl_surface);
			egl_surface = EGL_NO_SURFACE;
			eglTerminate(egl_display);
			egl_display = EGL_NO_DISPLAY;
			r_error = ERR_UNAVAILABLE;
			return;
		}

		RasterizerGLES3::make_current(false);

		Input::get_singleton()->set_event_dispatch_function(_dispatch_input_events);
		Input::get_singleton()->set_emulate_mouse_from_touch(true);
		r_error = OK;
		return;
	}
#endif

#if defined(VULKAN_ENABLED)
	if (rendering_driver == "vulkan") {
		rendering_context = memnew(RenderingContextDriverVulkanOpenHarmony);

		if (rendering_context->initialize() != OK) {
			memdelete(rendering_context);
			rendering_context = nullptr;
			ERR_PRINT("Failed to initialize Vulkan context.");
			r_error = ERR_UNAVAILABLE;
			return;
		}
		RenderingContextDriverVulkanOpenHarmony::WindowPlatformData vulkan;
		vulkan.window = native_window;

		if (rendering_context->window_create(DisplayServerEnums::MAIN_WINDOW_ID, &vulkan) != OK) {
			ERR_PRINT("Failed to create Vulkan window.");
			memdelete(rendering_context);
			rendering_context = nullptr;
			r_error = ERR_UNAVAILABLE;
			return;
		}

		Size2i display_size = OS_OpenHarmony::get_singleton()->get_display_size();
		rendering_context->window_set_size(DisplayServerEnums::MAIN_WINDOW_ID, display_size.width, display_size.height);
		rendering_context->window_set_vsync_mode(DisplayServerEnums::MAIN_WINDOW_ID, p_vsync_mode);

		rendering_device = memnew(RenderingDevice);
		if (rendering_device->initialize(rendering_context, DisplayServerEnums::MAIN_WINDOW_ID) != OK) {
			rendering_device = nullptr;
			memdelete(rendering_context);
			rendering_context = nullptr;
			r_error = ERR_UNAVAILABLE;
			return;
		}
		rendering_device->screen_create(DisplayServerEnums::MAIN_WINDOW_ID);

		RendererCompositorRD::make_current();

		Input::get_singleton()->set_event_dispatch_function(_dispatch_input_events);
		Input::get_singleton()->set_emulate_mouse_from_touch(true);
		r_error = OK;
		return;
	}
#endif

	ERR_PRINT(vformat("Unsupported rendering driver: %s", rendering_driver));
	r_error = ERR_UNAVAILABLE;
}

DisplayServerOpenHarmony::~DisplayServerOpenHarmony() {
#ifdef GLES3_ENABLED
	if (egl_display != EGL_NO_DISPLAY) {
		if (egl_context != EGL_NO_CONTEXT) {
			eglDestroyContext(egl_display, egl_context);
		}
		if (egl_surface != EGL_NO_SURFACE) {
			eglDestroySurface(egl_display, egl_surface);
		}
		eglTerminate(egl_display);
	}
#endif
	if (rendering_device) {
		memdelete(rendering_device);
		rendering_device = nullptr;
	}
	if (rendering_context) {
		memdelete(rendering_context);
		rendering_context = nullptr;
	}
}
void DisplayServerOpenHarmony::_window_callback(const Callable &p_callable, const Variant &p_arg, bool p_deferred) const {
	if (p_callable.is_valid()) {
		if (p_deferred) {
			p_callable.call_deferred(p_arg);
		} else {
			p_callable.call(p_arg);
		}
	}
}

void DisplayServerOpenHarmony::send_input_event(const Ref<InputEvent> &p_event) const {
	_window_callback(input_event_callback, p_event);
}

void DisplayServerOpenHarmony::resize_window(uint32_t width, uint32_t height) {
	Size2i size = Size2i(width, height);

#if defined(RD_ENABLED)
	if (rendering_context) {
		rendering_context->window_set_size(DisplayServerEnums::MAIN_WINDOW_ID, size.x, size.y);
	}
#endif

	Variant resize_rect = Rect2i(Point2i(), size);
	_window_callback(window_resize_callback, resize_rect);
}

void DisplayServerOpenHarmony::send_window_event(DisplayServerEnums::WindowEvent p_event) const {
	_window_callback(window_event_callback, int(p_event));
}

bool DisplayServerOpenHarmony::has_feature(DisplayServerEnums::Feature p_feature) const {
	switch (p_feature) {
		case DisplayServerEnums::FEATURE_TOUCHSCREEN:
		case DisplayServerEnums::FEATURE_CLIPBOARD:
		case DisplayServerEnums::FEATURE_VIRTUAL_KEYBOARD:
		case DisplayServerEnums::FEATURE_IME:
		case DisplayServerEnums::FEATURE_KEEP_SCREEN_ON:
		case DisplayServerEnums::FEATURE_CURSOR_SHAPE:
		case DisplayServerEnums::FEATURE_CUSTOM_CURSOR_SHAPE:
		case DisplayServerEnums::FEATURE_MOUSE:
		case DisplayServerEnums::FEATURE_MOUSE_WARP:
			return true;
		default:
			return false;
	}
}

String DisplayServerOpenHarmony::get_name() const {
	return "OpenHarmony";
}

Point2i DisplayServerOpenHarmony::mouse_get_position() const {
	return Input::get_singleton()->get_mouse_position();
}

void DisplayServerOpenHarmony::mouse_set_mode(DisplayServerEnums::MouseMode p_mode) {
	mouse_mode = p_mode;
}

DisplayServerEnums::MouseMode DisplayServerOpenHarmony::mouse_get_mode() const {
	return mouse_mode;
}

void DisplayServerOpenHarmony::mouse_set_mode_override(DisplayServerEnums::MouseMode p_mode) {
	mouse_mode_override = p_mode;
}

DisplayServerEnums::MouseMode DisplayServerOpenHarmony::mouse_get_mode_override() const {
	return mouse_mode_override;
}

void DisplayServerOpenHarmony::mouse_set_mode_override_enabled(bool p_override_enabled) {
	mouse_mode_override_enabled = p_override_enabled;
}

bool DisplayServerOpenHarmony::mouse_is_mode_override_enabled() const {
	return mouse_mode_override_enabled;
}

void DisplayServerOpenHarmony::warp_mouse(const Point2i &p_position) {
	// HarmonyOS does not support programmatic mouse cursor warping.
	// Do NOT call Input::get_singleton()->warp_mouse() here — that would
	// create infinite recursion since Input::warp_mouse() dispatches through
	// DisplayServer::_input_warp() back to this function.
	//
	// The crash manifests as SIGSEGV(SEGV_ACCERR) from stack-buffer-overflow
	// on the VSync thread (OS_VSyncThread) after ~180+ recursive frames.
	WARN_PRINT_ONCE("warp_mouse is not supported on HarmonyOS — cursor warp requests will be ignored.");
}

BitField<MouseButtonMask> DisplayServerOpenHarmony::mouse_get_button_state() const {
	return Input::get_singleton()->get_mouse_button_mask();
}

int DisplayServerOpenHarmony::get_screen_count() const {
	return 1;
}

int DisplayServerOpenHarmony::get_primary_screen() const {
	return 0;
}

Point2i DisplayServerOpenHarmony::screen_get_position(int p_screen) const {
	return Point2i(0, 0);
}

Size2i DisplayServerOpenHarmony::screen_get_size(int p_screen) const {
	return OS_OpenHarmony::get_singleton()->get_display_size();
}

Rect2i DisplayServerOpenHarmony::screen_get_usable_rect(int p_screen) const {
	Size2i display_size = OS_OpenHarmony::get_singleton()->get_display_size();
	return Rect2i(0, 0, display_size.width, display_size.height);
}

int DisplayServerOpenHarmony::screen_get_dpi(int p_screen) const {
	return ohos_wrapper_get_display_dpi();
}

float DisplayServerOpenHarmony::screen_get_scale(int p_screen) const {
	return ohos_wrapper_get_display_scaled_density();
}

float DisplayServerOpenHarmony::screen_get_refresh_rate(int p_screen) const {
	return ohos_wrapper_get_display_refresh_rate();
}

bool DisplayServerOpenHarmony::is_touchscreen_available() const {
	return true;
}

void DisplayServerOpenHarmony::screen_set_orientation(DisplayServerEnums::ScreenOrientation p_orientation, int p_screen) {
	// Not supported on OpenHarmony.
}

DisplayServerEnums::ScreenOrientation DisplayServerOpenHarmony::screen_get_orientation(int p_screen) const {
	switch (ohos_wrapper_get_display_orientation()) {
		case WrapperScreenOrientation::WRAPPER_SCREEN_LANDSCAPE:
			return DisplayServerEnums::SCREEN_LANDSCAPE;
		case WrapperScreenOrientation::WRAPPER_SCREEN_PORTRAIT:
			return DisplayServerEnums::SCREEN_PORTRAIT;
		case WrapperScreenOrientation::WRAPPER_SCREEN_REVERSE_LANDSCAPE:
			return DisplayServerEnums::SCREEN_REVERSE_LANDSCAPE;
		case WrapperScreenOrientation::WRAPPER_SCREEN_REVERSE_PORTRAIT:
			return DisplayServerEnums::SCREEN_REVERSE_PORTRAIT;
		default:
			return DisplayServerEnums::SCREEN_PORTRAIT;
	}
}

void DisplayServerOpenHarmony::clipboard_set(const String &p_text) {
	OH_Pasteboard *pasteboard = OH_Pasteboard_Create();
	OH_UdsPlainText *plainText = OH_UdsPlainText_Create();
	OH_UdsPlainText_SetContent(plainText, p_text.utf8().get_data());
	OH_UdmfRecord *record = OH_UdmfRecord_Create();
	OH_UdmfRecord_AddPlainText(record, plainText);
	OH_UdmfData *data = OH_UdmfData_Create();
	OH_UdmfData_AddRecord(data, record);
	int status = OH_Pasteboard_SetData(pasteboard, data);
	if (status != 0) {
		ERR_PRINT("Failed to set clipboard data with PASTEBOARD_ErrCode: " + itos(status));
	}
	OH_UdsPlainText_Destroy(plainText);
	OH_UdmfRecord_Destroy(record);
	OH_UdmfData_Destroy(data);
	OH_Pasteboard_Destroy(pasteboard);
}

String DisplayServerOpenHarmony::clipboard_get() const {
	String content = "";
	OH_Pasteboard *pasteboard = OH_Pasteboard_Create();
	bool hasPlainTextData = OH_Pasteboard_HasType(pasteboard, "text/plain");
	if (hasPlainTextData) {
		int status = 0;
		OH_UdmfData *udmfData = OH_Pasteboard_GetData(pasteboard, &status);
		if (status == 0) {
			OH_UdmfRecord *record = OH_UdmfData_GetRecord(udmfData, 0);
			OH_UdsPlainText *plainText = OH_UdsPlainText_Create();
			OH_UdmfRecord_GetPlainText(record, plainText);
			content = String::utf8(OH_UdsPlainText_GetContent(plainText));
			OH_UdsPlainText_Destroy(plainText);
		} else {
			ERR_PRINT("Failed to get clipboard data with PASTEBOARD_ErrCode: " + itos(status));
		}
		OH_UdmfData_Destroy(udmfData);
	}
	OH_Pasteboard_Destroy(pasteboard);
	return content;
}

void DisplayServerOpenHarmony::screen_set_keep_on(bool p_enable) {
	ohos_wrapper_screen_set_keep_on(OS_OpenHarmony::get_singleton()->get_window_id(), p_enable);
}

bool DisplayServerOpenHarmony::screen_is_kept_on() const {
	return ohos_wrapper_screen_is_kept_on(OS_OpenHarmony::get_singleton()->get_window_id());
}

void DisplayServerOpenHarmony::_get_text_config(InputMethod_TextEditorProxy *text_editor_proxy, InputMethod_TextConfig *text_config) {
	InputMethod_TextInputType input_type = IME_TEXT_INPUT_TYPE_TEXT;
	InputMethod_EnterKeyType enter_key_type = IME_ENTER_KEY_DONE;
	switch (get_singleton()->keyboard_type) {
		case DisplayServerEnums::KEYBOARD_TYPE_DEFAULT:
			input_type = IME_TEXT_INPUT_TYPE_TEXT;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_MULTILINE:
			input_type = IME_TEXT_INPUT_TYPE_MULTILINE;
			enter_key_type = IME_ENTER_KEY_NEWLINE;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_NUMBER:
			input_type = IME_TEXT_INPUT_TYPE_NUMBER;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_NUMBER_DECIMAL:
			input_type = IME_TEXT_INPUT_TYPE_NUMBER_DECIMAL;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_PHONE:
			input_type = IME_TEXT_INPUT_TYPE_PHONE;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_EMAIL_ADDRESS:
			input_type = IME_TEXT_INPUT_TYPE_EMAIL_ADDRESS;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_PASSWORD:
			input_type = IME_TEXT_INPUT_TYPE_VISIBLE_PASSWORD;
			break;
		case DisplayServerEnums::KEYBOARD_TYPE_URL:
			input_type = IME_TEXT_INPUT_TYPE_URL;
			break;
		default:
			break;
	}
	OH_TextConfig_SetInputType(text_config, input_type);
	OH_TextConfig_SetPreviewTextSupport(text_config, false);
	OH_TextConfig_SetEnterKeyType(text_config, enter_key_type);
}

void DisplayServerOpenHarmony::_insert_text(InputMethod_TextEditorProxy *text_editor_proxy, const char16_t *text, size_t length) {
	String characters;
	characters = String::utf16(text, length);

	for (int i = 0; i < characters.size(); i++) {
		int character = characters[i];
		Key key = Key::NONE;

		if (character == '\t') { // 0x09
			key = Key::TAB;
		} else if (character == '\n') { // 0x0A
			key = Key::ENTER;
		} else if (character == 0x2006) {
			key = Key::SPACE;
		}

		_input_text_key(key, character, key, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
		_input_text_key(key, character, key, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
	}
}

void DisplayServerOpenHarmony::_delete_forward(InputMethod_TextEditorProxy *text_editor_proxy, int32_t length) {
	for (int i = 0; i < length; i++) {
		_input_text_key(Key::KEY_DELETE, 0, Key::KEY_DELETE, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
		_input_text_key(Key::KEY_DELETE, 0, Key::KEY_DELETE, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
	}
}

void DisplayServerOpenHarmony::_delete_backward(InputMethod_TextEditorProxy *text_editor_proxy, int32_t length) {
	for (int i = 0; i < length; i++) {
		_input_text_key(Key::BACKSPACE, 0, Key::BACKSPACE, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
		_input_text_key(Key::BACKSPACE, 0, Key::BACKSPACE, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
	}
}

void DisplayServerOpenHarmony::_send_keyboard_status(InputMethod_TextEditorProxy *text_editor_proxy, InputMethod_KeyboardStatus status) {
	get_singleton()->keyboard_status = status;
}

void DisplayServerOpenHarmony::_send_enter_key(InputMethod_TextEditorProxy *text_editor_proxy, InputMethod_EnterKeyType enter_key_type) {
	_input_text_key(Key::ENTER, 0, Key::ENTER, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
	_input_text_key(Key::ENTER, 0, Key::ENTER, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
}

void DisplayServerOpenHarmony::_move_cursor(InputMethod_TextEditorProxy *text_editor_proxy, InputMethod_Direction direction) {
	switch (direction) {
		case IME_DIRECTION_LEFT:
			_input_text_key(Key::LEFT, 0, Key::LEFT, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
			_input_text_key(Key::LEFT, 0, Key::LEFT, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
			break;
		case IME_DIRECTION_RIGHT:
			_input_text_key(Key::RIGHT, 0, Key::RIGHT, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
			_input_text_key(Key::RIGHT, 0, Key::RIGHT, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
			break;
		case IME_DIRECTION_UP:
			_input_text_key(Key::UP, 0, Key::UP, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
			_input_text_key(Key::UP, 0, Key::UP, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
			break;
		case IME_DIRECTION_DOWN:
			_input_text_key(Key::DOWN, 0, Key::DOWN, Key::NONE, 0, true, KeyLocation::UNSPECIFIED);
			_input_text_key(Key::DOWN, 0, Key::DOWN, Key::NONE, 0, false, KeyLocation::UNSPECIFIED);
			break;
		default:
			break;
	}
}

void DisplayServerOpenHarmony::_handle_set_selection(InputMethod_TextEditorProxy *text_editor_proxy, int32_t start, int32_t end) {
	// Not supported by Godot.
}

void DisplayServerOpenHarmony::_handle_extend_action(InputMethod_TextEditorProxy *text_editor_proxy, InputMethod_ExtendAction action) {
	// Not supported by Godot.
}

void DisplayServerOpenHarmony::_get_left_text_of_cursor(InputMethod_TextEditorProxy *text_editor_proxy, int32_t number, char16_t *text, size_t *length) {
	// Not supported by Godot.
}

void DisplayServerOpenHarmony::_get_right_text_of_cursor(InputMethod_TextEditorProxy *text_editor_proxy, int32_t number, char16_t *text, size_t *length) {
	// Not supported by Godot.
}

int32_t DisplayServerOpenHarmony::_get_text_index_at_cursor(InputMethod_TextEditorProxy *text_editor_proxy) {
	// Not supported by Godot.
	return 0;
}

int32_t DisplayServerOpenHarmony::_receive_private_command(InputMethod_TextEditorProxy *text_editor_proxy, InputMethod_PrivateCommand *command[], size_t length) {
	// Not supported by Godot.
	return 0;
}

int32_t DisplayServerOpenHarmony::_set_preview_text(InputMethod_TextEditorProxy *text_editor_proxy, const char16_t *text, size_t length, int32_t start, int32_t end) {
	// Not supported by Godot.
	return 0;
}

void DisplayServerOpenHarmony::_finish_text_preview(InputMethod_TextEditorProxy *text_editor_proxy) {
	// Not supported by Godot.
}

void DisplayServerOpenHarmony::_input_text_key(Key p_key, char32_t p_char, Key p_unshifted, Key p_physical, int p_modifier, bool p_pressed, KeyLocation p_location) {
	Ref<InputEventKey> ev;
	ev.instantiate();
	ev->set_echo(false);
	ev->set_pressed(p_pressed);
	ev->set_keycode(fix_keycode(p_char, p_key));
	ev->set_key_label(p_unshifted);
	ev->set_physical_keycode(p_physical);
	ev->set_unicode(fix_unicode(p_char));
	ev->set_location(p_location);
	Input::get_singleton()->parse_input_event(ev);
}

void DisplayServerOpenHarmony::virtual_keyboard_show(const String &p_existing_text, const Rect2 &p_screen_rect, DisplayServerEnums::VirtualKeyboardType p_type, int p_max_length, int p_cursor_start, int p_cursor_end) {
	if (keyboard_status == IME_KEYBOARD_STATUS_SHOW && keyboard_type == p_type) {
		return;
	}
	if (keyboard_status != IME_KEYBOARD_STATUS_NONE) {
		virtual_keyboard_hide();
	}

	keyboard_type = p_type;
	text_editor_proxy = OH_TextEditorProxy_Create();
	attach_options = OH_AttachOptions_Create(true);

	OH_TextEditorProxy_SetGetTextConfigFunc(text_editor_proxy, _get_text_config);
	OH_TextEditorProxy_SetInsertTextFunc(text_editor_proxy, _insert_text);
	OH_TextEditorProxy_SetDeleteForwardFunc(text_editor_proxy, _delete_forward);
	OH_TextEditorProxy_SetDeleteBackwardFunc(text_editor_proxy, _delete_backward);
	OH_TextEditorProxy_SetSendKeyboardStatusFunc(text_editor_proxy, _send_keyboard_status);
	OH_TextEditorProxy_SetSendEnterKeyFunc(text_editor_proxy, _send_enter_key);
	OH_TextEditorProxy_SetMoveCursorFunc(text_editor_proxy, _move_cursor);
	OH_TextEditorProxy_SetHandleSetSelectionFunc(text_editor_proxy, _handle_set_selection);
	OH_TextEditorProxy_SetHandleExtendActionFunc(text_editor_proxy, _handle_extend_action);
	OH_TextEditorProxy_SetGetLeftTextOfCursorFunc(text_editor_proxy, _get_left_text_of_cursor);
	OH_TextEditorProxy_SetGetRightTextOfCursorFunc(text_editor_proxy, _get_right_text_of_cursor);
	OH_TextEditorProxy_SetGetTextIndexAtCursorFunc(text_editor_proxy, _get_text_index_at_cursor);
	OH_TextEditorProxy_SetReceivePrivateCommandFunc(text_editor_proxy, _receive_private_command);
	OH_TextEditorProxy_SetSetPreviewTextFunc(text_editor_proxy, _set_preview_text);
	OH_TextEditorProxy_SetFinishTextPreviewFunc(text_editor_proxy, _finish_text_preview);

	auto retult = OH_InputMethodController_Attach(text_editor_proxy, attach_options, &input_method_proxy);
	if (retult != IME_ERR_OK) {
		ERR_PRINT(vformat("Failed to attach input method controller: %d", retult));
		return;
	}
}

void DisplayServerOpenHarmony::virtual_keyboard_hide() {
	if (keyboard_status == IME_KEYBOARD_STATUS_SHOW) {
		if (OH_InputMethodProxy_HideKeyboard(input_method_proxy) != IME_ERR_OK) {
			ERR_PRINT("Failed to hide keyboard");
		}
	}
	if (input_method_proxy) {
		if (OH_InputMethodController_Detach(input_method_proxy) != IME_ERR_OK) {
			ERR_PRINT("Failed to detach input method controller");
		}
		input_method_proxy = nullptr;
	}
	if (attach_options) {
		OH_AttachOptions_Destroy(attach_options);
		attach_options = nullptr;
	}
	if (text_editor_proxy) {
		OH_TextEditorProxy_Destroy(text_editor_proxy);
		text_editor_proxy = nullptr;
	}
	keyboard_status = IME_KEYBOARD_STATUS_NONE;
}

int DisplayServerOpenHarmony::virtual_keyboard_get_height() const {
	if (keyboard_status == IME_KEYBOARD_STATUS_SHOW) {
		int height = ohos_wrapper_get_keyboard_avoid_area(OS_OpenHarmony::get_singleton()->get_window_id());
		return height;
	}
	return 0;
}

void DisplayServerOpenHarmony::window_set_ime_active(const bool p_active, DisplayServerEnums::WindowID p_window) {
	ime_active = p_active;
}

void DisplayServerOpenHarmony::window_set_ime_position(const Point2i &p_pos, DisplayServerEnums::WindowID p_window) {
	if (ime_active) {
		InputMethod_CursorInfo *info = OH_CursorInfo_Create(p_pos.x, p_pos.y, 0, 30);
		OH_InputMethodProxy_NotifyCursorUpdate(input_method_proxy, info);
	}
}

Vector<DisplayServerEnums::WindowID> DisplayServerOpenHarmony::get_window_list() const {
	Vector<DisplayServerEnums::WindowID> ret;
	ret.push_back(DisplayServerEnums::MAIN_WINDOW_ID);
	return ret;
}

DisplayServerEnums::WindowID DisplayServerOpenHarmony::get_window_at_screen_position(const Point2i &p_position) const {
	return DisplayServerEnums::MAIN_WINDOW_ID;
}

void DisplayServerOpenHarmony::window_attach_instance_id(ObjectID p_instance, DisplayServerEnums::WindowID p_window) {
	window_attached_instance_id = p_instance;
}

ObjectID DisplayServerOpenHarmony::window_get_attached_instance_id(DisplayServerEnums::WindowID p_window) const {
	return window_attached_instance_id;
}

void DisplayServerOpenHarmony::window_set_window_event_callback(const Callable &p_callable, DisplayServerEnums::WindowID p_window) {
	window_event_callback = p_callable;
}

void DisplayServerOpenHarmony::window_set_input_event_callback(const Callable &p_callable, DisplayServerEnums::WindowID p_window) {
	input_event_callback = p_callable;
}

void DisplayServerOpenHarmony::window_set_input_text_callback(const Callable &p_callable, DisplayServerEnums::WindowID p_window) {
	input_text_callback = p_callable;
}

void DisplayServerOpenHarmony::window_set_rect_changed_callback(const Callable &p_callable, DisplayServerEnums::WindowID p_window) {
	window_resize_callback = p_callable;
}

void DisplayServerOpenHarmony::window_set_drop_files_callback(const Callable &p_callable, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

void DisplayServerOpenHarmony::window_set_title(const String &p_title, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

int DisplayServerOpenHarmony::window_get_current_screen(DisplayServerEnums::WindowID p_window) const {
	return DisplayServerEnums::SCREEN_OF_MAIN_WINDOW;
}

void DisplayServerOpenHarmony::window_set_current_screen(int p_screen, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

Point2i DisplayServerOpenHarmony::window_get_position(DisplayServerEnums::WindowID p_window) const {
	return Point2i();
}

Point2i DisplayServerOpenHarmony::window_get_position_with_decorations(DisplayServerEnums::WindowID p_window) const {
	return Point2i();
}

void DisplayServerOpenHarmony::window_set_position(const Point2i &p_position, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

void DisplayServerOpenHarmony::window_set_transient(DisplayServerEnums::WindowID p_window, DisplayServerEnums::WindowID p_parent) {
	// Not supported on OpenHarmony.
}

void DisplayServerOpenHarmony::window_set_max_size(const Size2i p_size, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

Size2i DisplayServerOpenHarmony::window_get_max_size(DisplayServerEnums::WindowID p_window) const {
	return Size2i();
}

void DisplayServerOpenHarmony::window_set_min_size(const Size2i p_size, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

Size2i DisplayServerOpenHarmony::window_get_min_size(DisplayServerEnums::WindowID p_window) const {
	return Size2i();
}

void DisplayServerOpenHarmony::window_set_size(const Size2i p_size, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

Size2i DisplayServerOpenHarmony::window_get_size(DisplayServerEnums::WindowID p_window) const {
	return OS_OpenHarmony::get_singleton()->get_display_size();
}

Size2i DisplayServerOpenHarmony::window_get_size_with_decorations(DisplayServerEnums::WindowID p_window) const {
	return OS_OpenHarmony::get_singleton()->get_display_size();
}

static DisplayServerEnums::WindowMode tracked_window_mode = DisplayServerEnums::WINDOW_MODE_MAXIMIZED;

void DisplayServerOpenHarmony::window_set_mode(DisplayServerEnums::WindowMode p_mode, DisplayServerEnums::WindowID p_window) {
	tracked_window_mode = p_mode;
	extern void godot_request_window_mode(int p_mode);
	godot_request_window_mode((int)p_mode);
}

DisplayServerEnums::WindowMode DisplayServerOpenHarmony::window_get_mode(DisplayServerEnums::WindowID p_window) const {
	return tracked_window_mode;
}

void DisplayServerOpenHarmony::swap_buffers() {
#ifdef GLES3_ENABLED
	if (egl_display != EGL_NO_DISPLAY && egl_surface != EGL_NO_SURFACE) {
		eglSwapBuffers(egl_display, egl_surface);
	}
#endif
}

void DisplayServerOpenHarmony::gl_window_make_current(DisplayServerEnums::WindowID p_window_id) {
#ifdef GLES3_ENABLED
	if (egl_display != EGL_NO_DISPLAY && egl_surface != EGL_NO_SURFACE && egl_context != EGL_NO_CONTEXT) {
		eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context);
	}
#endif
}

void DisplayServerOpenHarmony::window_set_vsync_mode(DisplayServerEnums::VSyncMode p_vsync_mode, DisplayServerEnums::WindowID p_window) {
#ifdef GLES3_ENABLED
	if (rendering_driver == "opengl3" && egl_display != EGL_NO_DISPLAY) {
		eglSwapInterval(egl_display, p_vsync_mode != DisplayServerEnums::VSYNC_DISABLED ? 1 : 0);
	}
#endif
}

DisplayServerEnums::VSyncMode DisplayServerOpenHarmony::window_get_vsync_mode(DisplayServerEnums::WindowID p_window) const {
	return DisplayServerEnums::VSyncMode::VSYNC_ADAPTIVE;
}

bool DisplayServerOpenHarmony::window_is_maximize_allowed(DisplayServerEnums::WindowID p_window) const {
	return true;
}

void DisplayServerOpenHarmony::window_set_flag(DisplayServerEnums::WindowFlags p_flag, bool p_enabled, DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

bool DisplayServerOpenHarmony::window_get_flag(DisplayServerEnums::WindowFlags p_flag, DisplayServerEnums::WindowID p_window) const {
	return false;
}

void DisplayServerOpenHarmony::window_request_attention(DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

void DisplayServerOpenHarmony::window_move_to_foreground(DisplayServerEnums::WindowID p_window) {
	// Not supported on OpenHarmony.
}

bool DisplayServerOpenHarmony::window_is_focused(DisplayServerEnums::WindowID p_window) const {
	return true;
}

bool DisplayServerOpenHarmony::window_can_draw(DisplayServerEnums::WindowID p_window) const {
	return true;
}

bool DisplayServerOpenHarmony::can_any_window_draw() const {
	return true;
}

void DisplayServerOpenHarmony::process_events() {
	Input::get_singleton()->flush_buffered_events();
}

// ============================================================
// File Dialog - Implemented via ArkTS picker
// ============================================================

// Saved callback for file dialog - used to emit result back to Godot
static Callable saved_file_dialog_callback;
static Callable saved_directory_picker_callback;

// Map Godot's FileDialogMode to our internal mode
// 0 = open file, 1 = save file
static int convert_file_dialog_mode(DisplayServerEnums::FileDialogMode p_mode) {
	switch (p_mode) {
		case DisplayServerEnums::FILE_DIALOG_MODE_SAVE_FILE:
			return 1;  // Save mode
		default:
			return 0;  // Open mode (including OPEN_FILE, OPEN_FILES, OPEN_DIR, OPEN_ANY)
	}
}

Error DisplayServerOpenHarmony::file_dialog_show(const String &p_title, const String &p_current_directory, const String &p_filename, bool p_show_hidden, DisplayServerEnums::FileDialogMode p_mode, const Vector<String> &p_filters, const Callable &p_callback, DisplayServerEnums::WindowID p_window_id) {
	// Save callback for later use when result comes back
	saved_file_dialog_callback = p_callback;
	
	// Convert filters to comma-separated string
	String filters_str;
	for (int i = 0; i < p_filters.size(); i++) {
		if (i > 0) {
			filters_str += ",";
		}
		filters_str += p_filters[i];
	}
	
	// Convert Godot mode to our internal mode (0 = open, 1 = save)
	int mode = convert_file_dialog_mode(p_mode);

	// Request file dialog via bridge (which will call ArkTS)
	godot_request_file_dialog(
		mode,
		p_title.utf8().get_data(),
		p_current_directory.utf8().get_data(),
		filters_str.utf8().get_data()
	);
	
	// Note: The actual result will be returned via callback
	// This is async - we return OK immediately and callback will be called later
	return OK;
}

// Called from NAPI when file dialog result is ready
void godot_emit_file_dialog_callback(const char *p_selected_path) {
	if (saved_file_dialog_callback.is_valid()) {
		Vector<String> selected_paths;
		if (p_selected_path && strlen(p_selected_path) > 0) {
			selected_paths.push_back(String(p_selected_path));
		}
		// Call Godot callback: (bool success, Array paths, int id)
		saved_file_dialog_callback.call_deferred(selected_paths.is_empty() ? false : true, selected_paths, 0);
	}
}

// Called from NAPI when directory picker result is ready.
// Dedicated callback (from directory_picker_show) takes priority;
// falls back to file dialog callback (from file_dialog_show with OPEN_DIR).
void godot_emit_directory_picker_callback(const char *p_selected_path) {
	if (saved_directory_picker_callback.is_valid()) {
		Vector<String> selected_paths;
		if (p_selected_path && strlen(p_selected_path) > 0) {
			selected_paths.push_back(String(p_selected_path));
		}
		saved_directory_picker_callback.call_deferred(selected_paths.is_empty() ? false : true, selected_paths, 0);
		saved_directory_picker_callback = Callable();
		return;
	}
	if (saved_file_dialog_callback.is_valid()) {
		Vector<String> selected_paths;
		if (p_selected_path && strlen(p_selected_path) > 0) {
			selected_paths.push_back(String(p_selected_path));
		}
		saved_file_dialog_callback.call_deferred(selected_paths.is_empty() ? false : true, selected_paths, 0);
	}
}

Error DisplayServerOpenHarmony::file_dialog_with_options_show(const String &p_title, const String &p_current_directory, const String &p_root, const String &p_filename, bool p_show_hidden, DisplayServerEnums::FileDialogMode p_mode, const Vector<String> &p_filters, const TypedArray<Dictionary> &p_options, const Callable &p_callback, DisplayServerEnums::WindowID p_window_id) {
	// Options are not supported on OpenHarmony, just forward.
	return file_dialog_show(p_title, p_current_directory, p_filename, p_show_hidden, p_mode, p_filters, p_callback, p_window_id);
}

Error DisplayServerOpenHarmony::directory_picker_show(const String &p_title, const String &p_default_path, const Callable &p_callback) {
	saved_directory_picker_callback = p_callback;
	godot_request_directory_picker(p_title.utf8().get_data(), p_default_path.utf8().get_data());
	return OK;
}

// ============================================================
// Dialog - Implemented via ArkTS AlertDialog / CustomDialog
// ============================================================

// Saved callbacks for dialog results
static Callable saved_dialog_callback;

Error DisplayServerOpenHarmony::dialog_show(String p_title, String p_description, Vector<String> p_buttons, const Callable &p_callback) {
	if (p_buttons.is_empty()) {
		return ERR_INVALID_PARAMETER;
	}

	saved_dialog_callback = p_callback;

	// Serialize buttons as comma-separated string
	String buttons_str;
	for (int i = 0; i < p_buttons.size(); i++) {
		if (i > 0) {
			buttons_str += ",";
		}
		buttons_str += p_buttons[i];
	}

	godot_request_dialog(
			p_title.utf8().get_data(),
			p_description.utf8().get_data(),
			buttons_str.utf8().get_data());

	return OK;
}

Error DisplayServerOpenHarmony::dialog_input_text(String p_title, String p_description, String p_partial, const Callable &p_callback) {
	saved_dialog_callback = p_callback;

	// Encode as "INPUT:" prefix so BridgeCallbacks.ets can detect it
	String encoded = "INPUT:" + p_partial;

	godot_request_dialog(
			p_title.utf8().get_data(),
			p_description.utf8().get_data(),
			encoded.utf8().get_data());

	return OK;
}

// Called from NAPI when dialog result is ready
void godot_emit_dialog_callback(int p_button_index) {
	if (saved_dialog_callback.is_valid()) {
		saved_dialog_callback.call_deferred(p_button_index);
	}
}

void godot_emit_input_dialog_callback(const char *p_text) {
	if (saved_dialog_callback.is_valid()) {
		// Standard convention (Windows, Android): pass only the text string.
		saved_dialog_callback.call_deferred(String::utf8(p_text));
	}
}

void DisplayServerOpenHarmony::cursor_set_shape(DisplayServerEnums::CursorShape p_shape) {
	if (p_shape == current_cursor_shape) {
		return;
	}
	current_cursor_shape = p_shape;
	extern void godot_request_cursor_shape(int p_shape);
	godot_request_cursor_shape((int)p_shape);
}

DisplayServerEnums::CursorShape DisplayServerOpenHarmony::cursor_get_shape() const {
	return current_cursor_shape;
}

void DisplayServerOpenHarmony::cursor_set_custom_image(const Ref<Resource> &p_cursor, DisplayServerEnums::CursorShape p_shape, const Vector2 &p_hotspot) {
	ERR_FAIL_COND(!p_cursor.is_valid());
	
	Ref<Image> image = p_cursor;
	if (image.is_null()) {
		// Try to cast from ImageTexture
		Ref<Texture2D> texture = p_cursor;
		if (texture.is_valid()) {
			image = texture->get_image();
		}
	}
	ERR_FAIL_COND(image.is_null());
	
	// Convert image to RGBA8 format
	image = image->duplicate();
	if (image->is_compressed()) {
		image->decompress();
	}
	if (image->get_format() != Image::FORMAT_RGBA8) {
		image->convert(Image::FORMAT_RGBA8);
	}
	
	// Get image data and compute hash
	Vector<uint8_t> data = image->get_data();
	int width = image->get_width();
	int height = image->get_height();
	
	// Quick hash: combine size + hotspot + first/last 64 bytes of data
	uint64_t new_hash = (uint64_t(width) << 48) | (uint64_t(height) << 32) |
		(uint64_t(p_hotspot.x) << 16) | (uint64_t(p_hotspot.y));
	int data_size = data.size();
	if (data_size >= 64) {
		for (int i = 0; i < 8; i++) {
			new_hash ^= (uint64_t(data[i]) | (uint64_t(data[i + 32]) << 8) |
				(uint64_t(data[data_size - 1 - i]) << 16) | (uint64_t(data[data_size - 33 - i]) << 24)) << (i * 8);
		}
	} else {
		for (int i = 0; i < data_size; i++) {
			new_hash ^= (uint64_t(data[i]) << ((i % 8) * 8));
		}
	}

	// Skip if cursor hasn't changed
	if (new_hash == cursor_data_hash && p_hotspot == cursor_hotspot) {
		return;
	}
	cursor_data_hash = new_hash;
	cursor_hotspot = p_hotspot;
	
	// Request ArkTS to set custom cursor via bridge
	extern bool godot_request_custom_cursor(int p_width, int p_height, const uint8_t *p_rgba_data, int p_data_size, int p_hotspot_x, int p_hotspot_y);
	godot_request_custom_cursor(width, height, data.ptr(), data.size(), (int)p_hotspot.x, (int)p_hotspot.y);
}
