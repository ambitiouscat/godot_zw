@tool
extends Node

var editor_plugin: EditorPlugin

var _command_handlers: Dictionary = {}  # method_name -> Callable
var _disabled_tools: Dictionary = {}  # method_name -> true

const TOOL_CONFIG_PATH := "user://mcp_tool_config.cfg"


func _ready() -> void:
	_load_tool_config()
	_register_commands()


func _register_commands() -> void:
	var command_classes := [
		preload("res://addons/godot_mcp/commands/project_commands.gd"),
		preload("res://addons/godot_mcp/commands/scene_commands.gd"),
		preload("res://addons/godot_mcp/commands/node_commands.gd"),
		preload("res://addons/godot_mcp/commands/script_commands.gd"),
		preload("res://addons/godot_mcp/commands/editor_commands.gd"),
		preload("res://addons/godot_mcp/commands/input_commands.gd"),
		preload("res://addons/godot_mcp/commands/runtime_commands.gd"),
		preload("res://addons/godot_mcp/commands/animation_commands.gd"),
		preload("res://addons/godot_mcp/commands/tilemap_commands.gd"),
		preload("res://addons/godot_mcp/commands/theme_commands.gd"),
		preload("res://addons/godot_mcp/commands/profiling_commands.gd"),
		preload("res://addons/godot_mcp/commands/batch_commands.gd"),
		preload("res://addons/godot_mcp/commands/shader_commands.gd"),
		preload("res://addons/godot_mcp/commands/export_commands.gd"),
		preload("res://addons/godot_mcp/commands/resource_commands.gd"),
		preload("res://addons/godot_mcp/commands/input_map_commands.gd"),
		preload("res://addons/godot_mcp/commands/scene_3d_commands.gd"),
		preload("res://addons/godot_mcp/commands/physics_commands.gd"),
		preload("res://addons/godot_mcp/commands/analysis_commands.gd"),
		preload("res://addons/godot_mcp/commands/animation_tree_commands.gd"),
		preload("res://addons/godot_mcp/commands/audio_commands.gd"),
		preload("res://addons/godot_mcp/commands/navigation_commands.gd"),
		preload("res://addons/godot_mcp/commands/particle_commands.gd"),
		preload("res://addons/godot_mcp/commands/test_commands.gd"),
		preload("res://addons/godot_mcp/commands/android_commands.gd"),
		preload("res://addons/godot_mcp/commands/headless_commands.gd"),
	]

	process_mode = Node.PROCESS_MODE_ALWAYS

	for cmd_class in command_classes:
		var cmd: Node = cmd_class.new()
		cmd.process_mode = Node.PROCESS_MODE_ALWAYS
		cmd.editor_plugin = editor_plugin
		add_child(cmd)
		var methods: Dictionary = cmd.get_commands()
		for method_name: String in methods:
			_command_handlers[method_name] = methods[method_name]

	# Compatibility aliases
	if _command_handlers.has("add_node"):
		_command_handlers["create_node"] = _command_handlers["add_node"]
	if _command_handlers.has("update_property"):
		_command_handlers["set_node_property"] = _command_handlers["update_property"]
		_command_handlers["set_property"] = _command_handlers["update_property"]
	if _command_handlers.has("get_filesystem_tree"):
		_command_handlers["get_project_structure"] = _command_handlers["get_filesystem_tree"]
	if _command_handlers.has("edit_resource"):
		_command_handlers["update_resource"] = _command_handlers["edit_resource"]
		_command_handlers["set_resource_property"] = func(p: Dictionary):
			var path: String = p.get("path", "")
			var prop: String = p.get("property", p.get("name", ""))
			var val: Variant = p.get("value", null)
			return _command_handlers["edit_resource"].call({"path": path, "properties": {prop: val}})
	if _command_handlers.has("create_resource"):
		_command_handlers["create_material"] = func(p: Dictionary):
			var path: String = p.get("path", "res://material.tres")
			var type: String = p.get("type", p.get("resource_type", "StandardMaterial3D"))
			var props: Dictionary = p.get("properties", {})
			if p.has("albedo_color"): props["albedo_color"] = p["albedo_color"]
			return _command_handlers["create_resource"].call({"path": path, "type": type, "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_box_mesh"] = func(p: Dictionary):
			var path: String = p.get("path", "res://box_mesh.tres")
			var type: String = p.get("type", p.get("resource_type", "BoxMesh"))
			var props: Dictionary = p.get("properties", {})
			if p.has("size"): props["size"] = p["size"]
			return _command_handlers["create_resource"].call({"path": path, "type": type, "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_mesh"] = _command_handlers["create_box_mesh"]
	if _command_handlers.has("set_project_setting"):
		_command_handlers["set_setting"] = _command_handlers["set_project_setting"]
		_command_handlers["set_main_scene"] = func(p: Dictionary):
			var scene: String = p.get("scene", p.get("path", p.get("main_scene", "")))
			return _command_handlers["set_project_setting"].call({"key": "application/run/main_scene", "value": scene})
	if _command_handlers.has("run_project"):
		_command_handlers["play_main_scene"] = _command_handlers["run_project"]
		_command_handlers["play_scene"] = _command_handlers["run_scene"]
		_command_handlers["play_current_scene"] = _command_handlers["run_current_scene"]

	print("[MCP] Registered %d commands" % _command_handlers.size())


func execute(method: String, params: Dictionary) -> Dictionary:
	if not _command_handlers.has(method):
		return {
			"error": {
				"code": -32601,
				"message": "Method not found: %s" % method,
				"data": {"available_methods": _command_handlers.keys()}
			}
		}

	if _disabled_tools.has(method):
		return {
			"error": {
				"code": -32603,
				"message": "Tool '%s' is disabled in MCP Server settings" % method
			}
		}

	var handler: Callable = _command_handlers[method]
	if not handler.is_valid():
		return {
			"error": {
				"code": -32603,
				"message": "Handler for '%s' is not valid" % method
			}
		}

	var result: Variant = await handler.call(params)
	if result == null:
		return {
			"error": {
				"code": -32603,
				"message": "Handler for '%s' returned null" % method
			}
		}
	if not result is Dictionary:
		return {
			"error": {
				"code": -32603,
				"message": "Handler for '%s' returned %s instead of a result dictionary" % [
					method, type_string(typeof(result))
				],
			}
		}
	return result


func get_available_methods() -> Array:
	return _command_handlers.keys()


func is_tool_disabled(method: String) -> bool:
	return _disabled_tools.has(method)


func set_tool_disabled(method: String, disabled: bool) -> void:
	if disabled:
		_disabled_tools[method] = true
	else:
		_disabled_tools.erase(method)
	_save_tool_config()


func set_all_tools_disabled(disabled: bool) -> void:
	if disabled:
		for method: String in _command_handlers:
			_disabled_tools[method] = true
	else:
		_disabled_tools.clear()
	_save_tool_config()


func _load_tool_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(TOOL_CONFIG_PATH) != OK:
		return
	if not cfg.has_section("disabled_tools"):
		return
	for method: String in cfg.get_section_keys("disabled_tools"):
		if cfg.get_value("disabled_tools", method, false):
			_disabled_tools[method] = true


func _save_tool_config() -> void:
	var cfg := ConfigFile.new()
	for method: String in _disabled_tools:
		cfg.set_value("disabled_tools", method, true)
	cfg.save(TOOL_CONFIG_PATH)
