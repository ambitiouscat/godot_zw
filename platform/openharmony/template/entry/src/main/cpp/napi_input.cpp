/**************************************************************************/
/*  napi_input.cpp                                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/

#include "include/napi_bridge.h"
#include <hilog/log.h>
#include <napi/native_api.h>
#include <vector>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "LIB_ENTRY"

extern bool g_initialized;

static napi_value NAPI_Input_touch(napi_env env, napi_callback_info info) {
	if (!g_initialized) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		OH_LOG_ERROR(LOG_APP, "GetContext napi_get_cb_info failed");
		return nullptr;
	}
	uint32_t array_length = 0;
	if (napi_ok != napi_get_array_length(env, args[0], &array_length)) {
		OH_LOG_ERROR(LOG_APP, "Get array length failed");
		return nullptr;
	}

	std::vector<GodotTouchEvent> events;

	for (uint32_t i = 0; i < array_length; i++) {
		napi_value element;
		if (napi_ok != napi_get_element(env, args[0], i, &element)) {
			OH_LOG_ERROR(LOG_APP, "Get array element failed");
			return nullptr;
		}

		napi_value event_type;
		if (napi_ok != napi_get_named_property(env, element, "type", &event_type)) {
			OH_LOG_ERROR(LOG_APP, "Get event type failed");
			return nullptr;
		}

		int32_t event_type_int;
		if (napi_ok != napi_get_value_int32(env, event_type, &event_type_int)) {
			OH_LOG_ERROR(LOG_APP, "Get event type int failed");
			return nullptr;
		}

		napi_value event_id;
		if (napi_ok != napi_get_named_property(env, element, "id", &event_id)) {
			OH_LOG_ERROR(LOG_APP, "Get event id failed");
			return nullptr;
		}

		int32_t event_id_int;
		if (napi_ok != napi_get_value_int32(env, event_id, &event_id_int)) {
			OH_LOG_ERROR(LOG_APP, "Get event id int failed");
			return nullptr;
		}

		napi_value event_x;
		if (napi_ok != napi_get_named_property(env, element, "x", &event_x)) {
			OH_LOG_ERROR(LOG_APP, "Get event x failed");
			return nullptr;
		}

		double event_x_double;
		if (napi_ok != napi_get_value_double(env, event_x, &event_x_double)) {
			OH_LOG_ERROR(LOG_APP, "Get event x double failed");
			return nullptr;
		}

		napi_value event_y;
		if (napi_ok != napi_get_named_property(env, element, "y", &event_y)) {
			OH_LOG_ERROR(LOG_APP, "Get event y failed");
			return nullptr;
		}

		double event_y_double;
		if (napi_ok != napi_get_value_double(env, event_y, &event_y_double)) {
			OH_LOG_ERROR(LOG_APP, "Get event y double failed");
			return nullptr;
		}

		GodotTouchEvent event;
		event.type = event_type_int;
		event.id = event_id_int;
		event.x = event_x_double;
		event.y = event_y_double;
		events.push_back(event);
	}
	godot_touch(&events[0], events.size());
	return nullptr;
}

static napi_value NAPI_Input_key(napi_env env, napi_callback_info info) {
	if (!g_initialized) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		OH_LOG_ERROR(LOG_APP, "GetContext napi_get_cb_info failed");
		return nullptr;
	}

	napi_value element = args[0];

	napi_value code;
	if (napi_ok != napi_get_named_property(env, element, "code", &code)) {
		OH_LOG_ERROR(LOG_APP, "Get code failed");
		return nullptr;
	}

	uint32_t code_uint;
	if (napi_ok != napi_get_value_uint32(env, code, &code_uint)) {
		OH_LOG_ERROR(LOG_APP, "Get code int failed");
		return nullptr;
	}

	napi_value unicode;
	if (napi_ok != napi_get_named_property(env, element, "unicode", &unicode)) {
		OH_LOG_ERROR(LOG_APP, "Get unicode failed");
		return nullptr;
	}

	uint32_t unicode_uint;
	if (napi_ok != napi_get_value_uint32(env, unicode, &unicode_uint)) {
		OH_LOG_ERROR(LOG_APP, "Get unicode int failed");
		return nullptr;
	}

	napi_value pressed;
	if (napi_ok != napi_get_named_property(env, element, "pressed", &pressed)) {
		OH_LOG_ERROR(LOG_APP, "Get pressed failed");
		return nullptr;
	}

	bool pressed_bool;
	if (napi_ok != napi_get_value_bool(env, pressed, &pressed_bool)) {
		OH_LOG_ERROR(LOG_APP, "Get pressed bool failed");
		return nullptr;
	}

	napi_value alt;
	if (napi_ok != napi_get_named_property(env, element, "alt", &alt)) {
		OH_LOG_ERROR(LOG_APP, "Get alt failed");
		return nullptr;
	}

	bool alt_bool;
	if (napi_ok != napi_get_value_bool(env, alt, &alt_bool)) {
		OH_LOG_ERROR(LOG_APP, "Get alt bool failed");
		return nullptr;
	}

	napi_value ctrl;
	if (napi_ok != napi_get_named_property(env, element, "ctrl", &ctrl)) {
		OH_LOG_ERROR(LOG_APP, "Get ctrl failed");
		return nullptr;
	}

	bool ctrl_bool;
	if (napi_ok != napi_get_value_bool(env, ctrl, &ctrl_bool)) {
		OH_LOG_ERROR(LOG_APP, "Get ctrl bool failed");
		return nullptr;
	}

	napi_value shift;
	if (napi_ok != napi_get_named_property(env, element, "shift", &shift)) {
		OH_LOG_ERROR(LOG_APP, "Get shift failed");
		return nullptr;
	}

	bool shift_bool;
	if (napi_ok != napi_get_value_bool(env, shift, &shift_bool)) {
		OH_LOG_ERROR(LOG_APP, "Get shift bool failed");
		return nullptr;
	}

	napi_value meta;
	if (napi_ok != napi_get_named_property(env, element, "meta", &meta)) {
		OH_LOG_ERROR(LOG_APP, "Get meta failed");
		return nullptr;
	}

	bool meta_bool;
	if (napi_ok != napi_get_value_bool(env, meta, &meta_bool)) {
		OH_LOG_ERROR(LOG_APP, "Get meta bool failed");
		return nullptr;
	}

	GodotKeyEvent event;
	event.code = code_uint;
	event.unicode = unicode_uint;
	event.pressed = pressed_bool;
	event.alt = alt_bool;
	event.ctrl = ctrl_bool;
	event.shift = shift_bool;
	event.meta = meta_bool;
	godot_key(&event);
	return nullptr;
}

static napi_value NAPI_Input_sensor(napi_env env, napi_callback_info info) {
	if (!g_initialized) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		return nullptr;
	}

	napi_value element = args[0];

	napi_value type;
	if (napi_ok != napi_get_named_property(env, element, "type", &type)) {
		return nullptr;
	}
	uint32_t type_uint;
	if (napi_ok != napi_get_value_uint32(env, type, &type_uint)) {
		return nullptr;
	}

	napi_value x;
	if (napi_ok != napi_get_named_property(env, element, "x", &x)) {
		return nullptr;
	}
	double x_double;
	if (napi_ok != napi_get_value_double(env, x, &x_double)) {
		return nullptr;
	}

	napi_value y;
	if (napi_ok != napi_get_named_property(env, element, "y", &y)) {
		return nullptr;
	}
	double y_double;
	if (napi_ok != napi_get_value_double(env, y, &y_double)) {
		return nullptr;
	}

	napi_value z;
	if (napi_ok != napi_get_named_property(env, element, "z", &z)) {
		return nullptr;
	}
	double z_double;
	if (napi_ok != napi_get_value_double(env, z, &z_double)) {
		return nullptr;
	}

	GodotSensorData data;
	data.type = type_uint;
	data.x = (float)x_double;
	data.y = (float)y_double;
	data.z = (float)z_double;
	godot_sensor(&data);
	return nullptr;
}

static napi_value NAPI_Input_mouse(napi_env env, napi_callback_info info) {
	if (!g_initialized) {
		return nullptr;
	}
	size_t argc = 1;
	napi_value args[1] = { nullptr };
	if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {
		OH_LOG_ERROR(LOG_APP, "GetContext napi_get_cb_info failed");
		return nullptr;
	}

	napi_value element = args[0];

	napi_value type;
	if (napi_ok != napi_get_named_property(env, element, "type", &type)) {
		OH_LOG_ERROR(LOG_APP, "Get type failed");
		return nullptr;
	}

	uint32_t type_uint;
	if (napi_ok != napi_get_value_uint32(env, type, &type_uint)) {
		OH_LOG_ERROR(LOG_APP, "Get type int failed");
		return nullptr;
	}

	napi_value button;
	if (napi_ok != napi_get_named_property(env, element, "button", &button)) {
		OH_LOG_ERROR(LOG_APP, "Get button failed");
		return nullptr;
	}

	uint32_t button_uint;
	if (napi_ok != napi_get_value_uint32(env, button, &button_uint)) {
		OH_LOG_ERROR(LOG_APP, "Get button int failed");
		return nullptr;
	}

	napi_value mask;
	if (napi_ok != napi_get_named_property(env, element, "mask", &mask)) {
		OH_LOG_ERROR(LOG_APP, "Get mask failed");
		return nullptr;
	}

	uint32_t mask_uint;
	if (napi_ok != napi_get_value_uint32(env, mask, &mask_uint)) {
		OH_LOG_ERROR(LOG_APP, "Get mask int failed");
		return nullptr;
	}

	napi_value x;
	if (napi_ok != napi_get_named_property(env, element, "x", &x)) {
		OH_LOG_ERROR(LOG_APP, "Get x failed");
		return nullptr;
	}

	double x_double;
	if (napi_ok != napi_get_value_double(env, x, &x_double)) {
		OH_LOG_ERROR(LOG_APP, "Get x double failed");
		return nullptr;
	}

	napi_value y;
	if (napi_ok != napi_get_named_property(env, element, "y", &y)) {
		OH_LOG_ERROR(LOG_APP, "Get y failed");
		return nullptr;
	}

	double y_double;
	if (napi_ok != napi_get_value_double(env, y, &y_double)) {
		OH_LOG_ERROR(LOG_APP, "Get y double failed");
		return nullptr;
	}

	GodotMouseEvent event;
	event.type = type_uint;
	event.button = button_uint;
	event.mask = mask_uint;
	event.x = x_double;
	event.y = y_double;
	godot_mouse(&event);
	return nullptr;
}

void napi_input_register(napi_env env, napi_value exports) {
	napi_property_descriptor desc[] = {
		{ "inputTouch", nullptr, NAPI_Input_touch, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "inputKey", nullptr, NAPI_Input_key, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "inputMouse", nullptr, NAPI_Input_mouse, nullptr, nullptr, nullptr, napi_default, nullptr },
		{ "inputSensor", nullptr, NAPI_Input_sensor, nullptr, nullptr, nullptr, napi_default, nullptr }
	};
	napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
