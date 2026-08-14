/**************************************************************************/
/*  opencode_dock.h                                                       */
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

#pragma once

#include "editor/docks/editor_dock.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"
#include "scene/gui/label.h"
#include "scene/gui/option_button.h"
#include "scene/gui/rich_text_label.h"
#include "scene/gui/text_edit.h"
#include "scene/main/http_request.h"

class OpenCodeDock : public EditorDock {
	GDCLASS(OpenCodeDock, EditorDock);

	static inline OpenCodeDock *singleton = nullptr;

	OptionButton *model_selector = nullptr;
	Button *new_session_btn = nullptr;
	Button *clear_chat_btn = nullptr;
	Label *status_label = nullptr;

	RichTextLabel *chat_log = nullptr;

	Button *attach_script_btn = nullptr;
	Button *attach_node_btn = nullptr;

	TextEdit *prompt_input = nullptr;
	Button *send_btn = nullptr;

	HTTPRequest *http_request = nullptr;
	bool is_requesting = false;
	String current_model = "deepseek-v3";
	int backend_port = 4096;

	void _send_prompt();
	void _on_send_pressed();
	void _on_input_gui_input(const Ref<InputEvent> &p_event);
	void _on_http_completed(int p_status, int p_code, const PackedStringArray &p_headers, const PackedByteArray &p_data);
	void _attach_current_script();
	void _attach_selected_node();
	void _new_session();
	void _clear_chat();
	void _on_model_selected(int p_index);
	void _append_chat_message(const String &p_sender, const String &p_message, const Color &p_color);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	static OpenCodeDock *get_singleton() { return singleton; }

	void set_backend_port(int p_port) { backend_port = p_port; }
	int get_backend_port() const { return backend_port; }

	OpenCodeDock();
	~OpenCodeDock();
};
