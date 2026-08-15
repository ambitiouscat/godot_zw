/**************************************************************************/
/*  opencode_dock.cpp                                                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/

#include "opencode_dock.h"

#ifdef OPENHARMONY_ENABLED
#include "platform/openharmony/bridge_openharmony.h"
#endif

void OpenCodeDock::_notify_geometry() {
#ifdef OPENHARMONY_ENABLED
	bool current_visible = is_visible_in_tree();
	Rect2 current_rect = get_global_rect();

	if (current_visible != was_visible || (current_visible && current_rect != last_global_rect)) {
		was_visible = current_visible;
		last_global_rect = current_rect;
		if (current_visible && current_rect.size.x > 0 && current_rect.size.y > 0) {
			godot_notify_opencode_dock_geometry(current_rect.position.x, current_rect.position.y, current_rect.size.x, current_rect.size.y, true);
		} else {
			godot_notify_opencode_dock_geometry(0, 0, 0, 0, false);
		}
	}
#endif
}

void OpenCodeDock::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE:
		case NOTIFICATION_VISIBILITY_CHANGED:
		case NOTIFICATION_RESIZED:
		case NOTIFICATION_TRANSFORM_CHANGED:
		case NOTIFICATION_DRAW: {
			_notify_geometry();
		} break;
		case NOTIFICATION_EXIT_TREE: {
#ifdef OPENHARMONY_ENABLED
			if (was_visible) {
				was_visible = false;
				godot_notify_opencode_dock_geometry(0, 0, 0, 0, false);
			}
#endif
		} break;
	}
}

void OpenCodeDock::_bind_methods() {
}

OpenCodeDock::OpenCodeDock() {
	singleton = this;
	set_name(TTRC("OpenCode"));
	set_icon_name("Script");
	set_default_slot(EditorDock::DOCK_SLOT_RIGHT_UL);
}

OpenCodeDock::~OpenCodeDock() {
#ifdef OPENHARMONY_ENABLED
	if (was_visible) {
		was_visible = false;
		godot_notify_opencode_dock_geometry(0, 0, 0, 0, false);
	}
#endif
	singleton = nullptr;
}
