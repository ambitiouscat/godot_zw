/**************************************************************************/
/*  opencode_dock.cpp                                                     */
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

#include "opencode_dock.h"

#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/object/callable_mp.h"
#include "editor/editor_data.h"
#include "editor/editor_interface.h"
#include "editor/editor_node.h"
#include "editor/script/script_editor_plugin.h"
#include "editor/settings/editor_command_palette.h"
#include "editor/themes/editor_scale.h"
#include "scene/gui/separator.h"

void OpenCodeDock::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_THEME_CHANGED: {
			if (attach_script_btn) {
				attach_script_btn->set_button_icon(get_editor_theme_icon(SNAME("Script")));
			}
			if (attach_node_btn) {
				attach_node_btn->set_button_icon(get_editor_theme_icon(SNAME("Node")));
			}
			if (new_session_btn) {
				new_session_btn->set_button_icon(get_editor_theme_icon(SNAME("Add")));
			}
			if (clear_chat_btn) {
				clear_chat_btn->set_button_icon(get_editor_theme_icon(SNAME("Clear")));
			}
			if (send_btn) {
				send_btn->set_button_icon(get_editor_theme_icon(SNAME("Play")));
			}
		} break;
	}
}

void OpenCodeDock::_on_model_selected(int p_index) {
	current_model = model_selector->get_item_text(p_index).to_lower();
}

void OpenCodeDock::_attach_current_script() {
	ScriptEditor *se = ScriptEditor::get_singleton();
	if (!se) {
		return;
	}
	ScriptEditorBase *seb = se->get_current_editor();
	if (seb) {
		Ref<Resource> res = seb->get_edited_resource();
		Ref<Script> script = res;
		if (script.is_valid()) {
			String path = script->get_path();
			String code = script->get_source_code();
			String snippet = vformat("\n[File: %s]\n```gdscript\n%s\n```\n", path, code);
			prompt_input->insert_text_at_caret(snippet);
		}
	}
}

void OpenCodeDock::_attach_selected_node() {
	EditorSelection *sel = EditorInterface::get_singleton()->get_selection();
	if (!sel) {
		return;
	}
	List<Node *> nodes = sel->get_top_selected_node_list();
	if (nodes.is_empty()) {
		return;
	}
	String info = "\n[Selected Nodes]:\n";
	for (Node *n : nodes) {
		info += vformat("- %s (%s) @ %s\n", n->get_name(), n->get_class(), n->get_path());
	}
	prompt_input->insert_text_at_caret(info);
}

void OpenCodeDock::_new_session() {
	chat_log->clear();
	_append_chat_message("System", "新的 OpenCode 对话已开启，可以向 AI 提问或要求编写代码。", Color(0.6f, 0.6f, 0.6f));
}

void OpenCodeDock::_clear_chat() {
	chat_log->clear();
}

void OpenCodeDock::_append_chat_message(const String &p_sender, const String &p_message, const Color &p_color) {
	String color_hex = p_color.to_html(false);
	chat_log->push_color(p_color);
	chat_log->push_bold();
	chat_log->add_text(vformat("[%s]:\n", p_sender));
	chat_log->pop();
	chat_log->pop();
	chat_log->add_text(p_message + "\n\n");
}

void OpenCodeDock::_on_send_pressed() {
	_send_prompt();
}

void OpenCodeDock::_on_input_gui_input(const Ref<InputEvent> &p_event) {
	Ref<InputEventKey> k = p_event;
	if (k.is_valid() && k->is_pressed() && !k->is_echo()) {
		if (k->get_keycode() == Key::ENTER && (k->is_ctrl_pressed() || k->is_command_or_control_autoremap())) {
			_send_prompt();
			prompt_input->accept_event();
		}
	}
}

void OpenCodeDock::_send_prompt() {
	String text = prompt_input->get_text().strip_edges();
	if (text.is_empty() || is_requesting) {
		return;
	}

	_append_chat_message("User", text, Color(0.4f, 0.7f, 1.0f));
	prompt_input->clear();

	is_requesting = true;
	send_btn->set_disabled(true);
	status_label->set_text(TTR("🟡 正在生成..."));

	Dictionary payload;
	payload["prompt"] = text;
	payload["model"] = current_model;
	String json_str = JSON::stringify(payload);

	Vector<String> headers;
	headers.push_back("Content-Type: application/json");

	String url = vformat("http://127.0.0.1:%d/api/prompt", backend_port);
	Error err = http_request->request(url, headers, HTTPClient::METHOD_POST, json_str);
	if (err != OK) {
		is_requesting = false;
		send_btn->set_disabled(false);
		status_label->set_text(TTR("🔴 请求失败"));
		_append_chat_message("System", vformat("无法连接至 OpenCode 本地服务 (端口 %d): %d", backend_port, (int)err), Color(1.0f, 0.4f, 0.4f));
	}
}

void OpenCodeDock::_on_http_completed(int p_status, int p_code, const PackedStringArray &p_headers, const PackedByteArray &p_data) {
	is_requesting = false;
	send_btn->set_disabled(false);

	if (p_status != HTTPRequest::RESULT_SUCCESS) {
		status_label->set_text(TTR("🔴 错误"));
		_append_chat_message("System", vformat("HTTP 请求异常: %d", p_status), Color(1.0f, 0.4f, 0.4f));
		return;
	}

	status_label->set_text(TTR("🟢 就绪"));

	String response_str = String::utf8((const char *)p_data.ptr(), p_data.size());

	Ref<JSON> json;
	json.instantiate();
	Error err = json->parse(response_str);
	if (err == OK) {
		Dictionary dict = json->get_data();
		if (dict.has("response")) {
			String answer = dict["response"];
			_append_chat_message("OpenCode", answer, Color(0.5f, 0.9f, 0.5f));
			return;
		}
	}

	_append_chat_message("OpenCode", response_str, Color(0.5f, 0.9f, 0.5f));
}

void OpenCodeDock::_bind_methods() {
	ClassDB::bind_method(D_METHOD("_on_send_pressed"), &OpenCodeDock::_on_send_pressed);
	ClassDB::bind_method(D_METHOD("_on_input_gui_input", "event"), &OpenCodeDock::_on_input_gui_input);
	ClassDB::bind_method(D_METHOD("_on_http_completed", "status", "code", "headers", "data"), &OpenCodeDock::_on_http_completed);
	ClassDB::bind_method(D_METHOD("_attach_current_script"), &OpenCodeDock::_attach_current_script);
	ClassDB::bind_method(D_METHOD("_attach_selected_node"), &OpenCodeDock::_attach_selected_node);
	ClassDB::bind_method(D_METHOD("_new_session"), &OpenCodeDock::_new_session);
	ClassDB::bind_method(D_METHOD("_clear_chat"), &OpenCodeDock::_clear_chat);
	ClassDB::bind_method(D_METHOD("_on_model_selected", "index"), &OpenCodeDock::_on_model_selected);
}

OpenCodeDock::OpenCodeDock() {
	singleton = this;
	set_name(TTRC("OpenCode"));
	set_icon_name("ScriptCreate");
	set_dock_shortcut(ED_SHORTCUT_AND_COMMAND("docks/open_opencode", TTRC("Open OpenCode AI Dock")));
	set_default_slot(EditorDock::DOCK_SLOT_RIGHT_UL);

	VBoxContainer *main_vb = memnew(VBoxContainer);
	main_vb->set_v_size_flags(SIZE_EXPAND_FILL);
	main_vb->set_h_size_flags(SIZE_EXPAND_FILL);
	add_child(main_vb);

	// 1. Top Toolbar
	HBoxContainer *toolbar = memnew(HBoxContainer);
	main_vb->add_child(toolbar);

	model_selector = memnew(OptionButton);
	model_selector->add_item("DeepSeek-V3");
	model_selector->add_item("Claude-3.5-Sonnet");
	model_selector->add_item("GPT-4o");
	model_selector->add_item("Qwen-2.5-Coder");
	model_selector->connect("item_selected", callable_mp(this, &OpenCodeDock::_on_model_selected));
	model_selector->set_h_size_flags(SIZE_EXPAND_FILL);
	toolbar->add_child(model_selector);

	status_label = memnew(Label);
	status_label->set_text(TTR("🟢 就绪"));
	toolbar->add_child(status_label);

	new_session_btn = memnew(Button);
	new_session_btn->set_tooltip_text(TTR("新建对话"));
	new_session_btn->connect("pressed", callable_mp(this, &OpenCodeDock::_new_session));
	toolbar->add_child(new_session_btn);

	clear_chat_btn = memnew(Button);
	clear_chat_btn->set_tooltip_text(TTR("清空历史"));
	clear_chat_btn->connect("pressed", callable_mp(this, &OpenCodeDock::_clear_chat));
	toolbar->add_child(clear_chat_btn);

	// 2. Chat Log View
	chat_log = memnew(RichTextLabel);
	chat_log->set_use_bbcode(true);
	chat_log->set_scroll_follow(true);
	chat_log->set_selection_enabled(true);
	chat_log->set_v_size_flags(SIZE_EXPAND_FILL);
	chat_log->set_h_size_flags(SIZE_EXPAND_FILL);
	chat_log->set_custom_minimum_size(Size2(200 * EDSCALE, 150 * EDSCALE));
	main_vb->add_child(chat_log);

	_append_chat_message("System", "欢迎使用 OpenCode AI 助手！\n支持附加当前脚本与选中节点信息，Ctrl+Enter 快捷发送。", Color(0.6f, 0.6f, 0.6f));

	// 3. Context Attachment Bar
	HBoxContainer *context_bar = memnew(HBoxContainer);
	main_vb->add_child(context_bar);

	attach_script_btn = memnew(Button);
	attach_script_btn->set_text(TTR("附加当前脚本"));
	attach_script_btn->connect("pressed", callable_mp(this, &OpenCodeDock::_attach_current_script));
	context_bar->add_child(attach_script_btn);

	attach_node_btn = memnew(Button);
	attach_node_btn->set_text(TTR("附加选中节点"));
	attach_node_btn->connect("pressed", callable_mp(this, &OpenCodeDock::_attach_selected_node));
	context_bar->add_child(attach_node_btn);

	// 4. Input Area
	HBoxContainer *input_hb = memnew(HBoxContainer);
	main_vb->add_child(input_hb);

	prompt_input = memnew(TextEdit);
	prompt_input->set_placeholder(TTR("输入提示词 (Ctrl+Enter 发送)..."));
	prompt_input->set_custom_minimum_size(Size2(0, 60 * EDSCALE));
	prompt_input->set_v_size_flags(SIZE_SHRINK_END);
	prompt_input->set_h_size_flags(SIZE_EXPAND_FILL);
	prompt_input->connect("gui_input", callable_mp(this, &OpenCodeDock::_on_input_gui_input));
	input_hb->add_child(prompt_input);

	send_btn = memnew(Button);
	send_btn->set_text(TTR("发送"));
	send_btn->set_custom_minimum_size(Size2(60 * EDSCALE, 60 * EDSCALE));
	send_btn->connect("pressed", callable_mp(this, &OpenCodeDock::_on_send_pressed));
	input_hb->add_child(send_btn);

	// 5. HTTP Client for OpenCode Local Loopback
	http_request = memnew(HTTPRequest);
	http_request->connect("request_completed", callable_mp(this, &OpenCodeDock::_on_http_completed));
	add_child(http_request);
}

OpenCodeDock::~OpenCodeDock() {
	singleton = nullptr;
}
