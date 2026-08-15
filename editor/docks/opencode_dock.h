/**************************************************************************/
/*  opencode_dock.h                                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/

#pragma once

#include "editor/docks/editor_dock.h"

class OpenCodeDock : public EditorDock {
	GDCLASS(OpenCodeDock, EditorDock);

private:
	bool was_visible = false;
	Rect2 last_global_rect;

	void _notify_geometry();

	static inline OpenCodeDock *singleton = nullptr;

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	static OpenCodeDock *get_singleton() { return singleton; }

	OpenCodeDock();
	~OpenCodeDock();
};
