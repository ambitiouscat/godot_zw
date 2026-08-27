@tool
extends Node

const Schemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")
const MCPLifecycleCoordinator = preload("res://addons/godot_mcp/lifecycle/lifecycle_coordinator.gd")

var editor_plugin: EditorPlugin
var coordinator: MCPLifecycleCoordinator = null
var game_runner: Node = null

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

	for cmd_class: GDScript in command_classes:
		var cmd: Node = cmd_class.new()
		cmd.process_mode = Node.PROCESS_MODE_ALWAYS
		cmd.editor_plugin = editor_plugin
		add_child(cmd)
		var methods: Dictionary = cmd.get_commands()
		for method_name: String in methods:
			_command_handlers[method_name] = methods[method_name]

	# Central Lifecycle Coordinator
	coordinator = MCPLifecycleCoordinator.new()
	coordinator.name = "LifecycleCoordinator"
	add_child(coordinator)

	# =========================================================================
	# GameAbility Canonical Execution Commands
	# =========================================================================

	_command_handlers["run_project"] = func(p: Dictionary) -> Dictionary:
		var scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
		var sp: String = p.get("save_policy", Schemas.SAVE_POLICY_REQUIRE_CLEAN)
		var cp: String = p.get("conflict_policy", Schemas.CONFLICT_POLICY_REJECT)
		if p.has("preempt") and p["preempt"] == true: cp = Schemas.CONFLICT_POLICY_PREEMPT
		var op_id: String = p.get("operation_id", "")
		var res: Dictionary = coordinator.request_start(Schemas.MODE_REAL_RUN, scene, sp, cp, op_id)
		if res.has("error"): return res
		return {"result": res}

	_command_handlers["run_scene"] = func(p: Dictionary) -> Dictionary:
		var path: String = p.get("path", p.get("scene_path", p.get("scene", "")))
		var sp: String = p.get("save_policy", Schemas.SAVE_POLICY_REQUIRE_CLEAN)
		var cp: String = p.get("conflict_policy", Schemas.CONFLICT_POLICY_REJECT)
		if p.has("preempt") and p["preempt"] == true: cp = Schemas.CONFLICT_POLICY_PREEMPT
		var op_id: String = p.get("operation_id", "")
		var res: Dictionary = coordinator.request_start(Schemas.MODE_REAL_RUN, path, sp, cp, op_id)
		if res.has("error"): return res
		return {"result": res}

	_command_handlers["run_current_scene"] = func(p: Dictionary) -> Dictionary:
		var cur: String = ""
		if editor_plugin and EditorInterface.get_edited_scene_root():
			cur = EditorInterface.get_edited_scene_root().scene_file_path
		var sp: String = p.get("save_policy", Schemas.SAVE_POLICY_REQUIRE_CLEAN)
		var cp: String = p.get("conflict_policy", Schemas.CONFLICT_POLICY_REJECT)
		if p.has("preempt") and p["preempt"] == true: cp = Schemas.CONFLICT_POLICY_PREEMPT
		var op_id: String = p.get("operation_id", "")
		var res: Dictionary = coordinator.request_start(Schemas.MODE_REAL_RUN, cur, sp, cp, op_id)
		if res.has("error"): return res
		return {"result": res}

	_command_handlers["stop_project"] = func(p: Dictionary) -> Dictionary:
		var sess_id: String = p.get("session_id", "")
		var op_id: String = p.get("operation_id", "")
		var res: Dictionary = coordinator.request_stop("real", sess_id, op_id)
		if res.has("error"): return res
		return {"result": res}

	# Lifecycle State Introspection
	_command_handlers["get_execution_state"] = func(_p: Dictionary) -> Dictionary:
		return {"result": coordinator.get_execution_state()}

	# 4. Compatibility Aliases (Real Run)
	_command_handlers["run_main_scene"] = _command_handlers["run_project"]
	_command_handlers["stop_playing_scene"] = _command_handlers["stop_project"]

	_command_handlers["play_main_scene"] = func(p: Dictionary) -> Dictionary:
		var res: Dictionary = _command_handlers["run_project"].call(p)
		if res.has("result"):
			res["result"]["deprecated_alias"] = true
			res["result"]["replacement"] = "run_project"
		return res

	_command_handlers["play_scene"] = func(p: Dictionary) -> Dictionary:
		var res: Dictionary = _command_handlers["run_scene"].call(p)
		if res.has("result"):
			res["result"]["deprecated_alias"] = true
			res["result"]["replacement"] = "run_scene"
		return res

	_command_handlers["play_current_scene"] = func(p: Dictionary) -> Dictionary:
		var res: Dictionary = _command_handlers["run_current_scene"].call(p)
		if res.has("result"):
			res["result"]["deprecated_alias"] = true
			res["result"]["replacement"] = "run_current_scene"
		return res

	_command_handlers["stop_scene"] = func(p: Dictionary) -> Dictionary:
		var res: Dictionary = _command_handlers["stop_project"].call(p)
		if res.has("result"):
			res["result"]["deprecated_alias"] = true
			res["result"]["replacement"] = "stop_project"
		return res

	_command_handlers["is_simulation_running"] = func(_p: Dictionary) -> Dictionary:
		var st: Dictionary = coordinator.get_execution_state()
		return {
			"result": {
				"deprecated_alias": true,
				"replacement": "get_execution_state",
				"is_running": false,
				"scene": str(st.get("target_scene", "")),
				"session_id": str(st.get("session_id", ""))
			}
		}

	# 5. Strict Screenshot Router with Zero Cross-Source Fallback
	var base_editor_shot: Callable = _command_handlers.get("get_editor_screenshot", Callable())
	var base_preview_shot: Callable = _command_handlers.get("get_preview_screenshot", Callable())
	var base_game_shot: Callable = _command_handlers.get("get_game_screenshot", Callable())

	_command_handlers["take_screenshot"] = func(p: Dictionary) -> Dictionary:
		var src: String = p.get("source", p.get("viewport", Schemas.SOURCE_EDITOR))
		if src == Schemas.SOURCE_GAME:
			if base_game_shot.is_valid():
				return await base_game_shot.call(p)
			return {"error": {"code": Schemas.ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE, "message": "GameAbility screenshot backend not initialized", "symbol": "CAPTURE_BACKEND_UNAVAILABLE"}}
		elif src == Schemas.SOURCE_EDITOR:
			if base_editor_shot.is_valid():
				return await base_editor_shot.call(p)
			return {"error": {"code": Schemas.ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE, "message": "Editor screenshot backend not initialized", "symbol": "CAPTURE_BACKEND_UNAVAILABLE"}}
		elif src == Schemas.SOURCE_PREVIEW:
			return {"error": {"code": Schemas.ERR_CODE_INVALID_ARGUMENT, "message": "source 'preview' has been removed; use 'game' for authoritative runtime capture or 'editor' for editor inspection.", "symbol": "INVALID_ARGUMENT"}}
		return {"error": {"code": Schemas.ERR_CODE_INVALID_ARGUMENT, "message": "Invalid screenshot source '%s'. Must be 'editor' or 'game'." % src, "symbol": "INVALID_ARGUMENT"}}

	_command_handlers["capture_screenshot"] = func(p: Dictionary) -> Dictionary:
		var res: Dictionary = await _command_handlers["take_screenshot"].call(p)
		if res.has("result"):
			res["result"]["deprecated_alias"] = true
			res["result"]["replacement"] = "take_screenshot(source=\"editor\")"
		return res
	_command_handlers["get_screenshot"] = _command_handlers["capture_screenshot"]

	_command_handlers["capture_game_screenshot"] = func(p: Dictionary) -> Dictionary:
		var cp := p.duplicate()
		cp["source"] = Schemas.SOURCE_GAME
		var res: Dictionary = await _command_handlers["take_screenshot"].call(cp)
		if res.has("result"):
			res["result"]["deprecated_alias"] = true
			res["result"]["replacement"] = "take_screenshot(source=\"game\")"
		return res

	# Resource and Scene creation aliases
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
		_command_handlers["create_standard_material_3d"] = _command_handlers["create_material"]
		_command_handlers["create_box_mesh"] = func(p: Dictionary):
			var path: String = p.get("path", "res://box_mesh.tres")
			var type: String = p.get("type", p.get("resource_type", "BoxMesh"))
			var props: Dictionary = p.get("properties", {})
			if p.has("size"): props["size"] = p["size"]
			return _command_handlers["create_resource"].call({"path": path, "type": type, "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_mesh"] = _command_handlers["create_box_mesh"]
		_command_handlers["create_cylinder_mesh"] = func(p: Dictionary):
			var path: String = p.get("path", "res://cylinder_mesh.tres")
			var props: Dictionary = p.get("properties", {})
			if p.has("top_radius"): props["top_radius"] = p["top_radius"]
			if p.has("bottom_radius"): props["bottom_radius"] = p["bottom_radius"]
			if p.has("height"): props["height"] = p["height"]
			return _command_handlers["create_resource"].call({"path": path, "type": "CylinderMesh", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_sphere_mesh"] = func(p: Dictionary):
			var path: String = p.get("path", "res://sphere_mesh.tres")
			var props: Dictionary = p.get("properties", {})
			if p.has("radius"): props["radius"] = p["radius"]
			if p.has("height"): props["height"] = p["height"]
			return _command_handlers["create_resource"].call({"path": path, "type": "SphereMesh", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_capsule_mesh"] = func(p: Dictionary):
			var path: String = p.get("path", "res://capsule_mesh.tres")
			var props: Dictionary = p.get("properties", {})
			if p.has("radius"): props["radius"] = p["radius"]
			if p.has("height"): props["height"] = p["height"]
			return _command_handlers["create_resource"].call({"path": path, "type": "CapsuleMesh", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_plane_mesh"] = func(p: Dictionary):
			var path: String = p.get("path", "res://plane_mesh.tres")
			var props: Dictionary = p.get("properties", {})
			if p.has("size"): props["size"] = p["size"]
			return _command_handlers["create_resource"].call({"path": path, "type": "PlaneMesh", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_box_shape_3d"] = func(p: Dictionary):
			var path: String = p.get("path", "res://box_shape_3d.tres")
			var props: Dictionary = {}
			if p.has("size"): props["size"] = p["size"]
			return _command_handlers["create_resource"].call({"path": path, "type": "BoxShape3D", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_box_shape"] = _command_handlers["create_box_shape_3d"]
		_command_handlers["create_cylinder_shape_3d"] = func(p: Dictionary):
			var path: String = p.get("path", "res://cylinder_shape_3d.tres")
			var props: Dictionary = {}
			if p.has("radius"): props["radius"] = p["radius"]
			if p.has("height"): props["height"] = p["height"]
			return _command_handlers["create_resource"].call({"path": path, "type": "CylinderShape3D", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_cylinder_shape"] = _command_handlers["create_cylinder_shape_3d"]
		_command_handlers["create_sphere_shape_3d"] = func(p: Dictionary):
			var path: String = p.get("path", "res://sphere_shape_3d.tres")
			var props: Dictionary = {}
			if p.has("radius"): props["radius"] = p["radius"]
			return _command_handlers["create_resource"].call({"path": path, "type": "SphereShape3D", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_sphere_shape"] = _command_handlers["create_sphere_shape_3d"]
		_command_handlers["create_capsule_shape_3d"] = func(p: Dictionary):
			var path: String = p.get("path", "res://capsule_shape_3d.tres")
			var props: Dictionary = {}
			if p.has("radius"): props["radius"] = p["radius"]
			if p.has("height"): props["height"] = p["height"]
			return _command_handlers["create_resource"].call({"path": path, "type": "CapsuleShape3D", "properties": props, "overwrite": p.get("overwrite", true)})
		_command_handlers["create_capsule_shape"] = _command_handlers["create_capsule_shape_3d"]

	if _command_handlers.has("set_project_setting"):
		_command_handlers["set_setting"] = _command_handlers["set_project_setting"]
		_command_handlers["set_main_scene"] = func(p: Dictionary):
			var scene: String = p.get("scene", p.get("path", p.get("main_scene", "")))
			return _command_handlers["set_project_setting"].call({"key": "application/run/main_scene", "value": scene})

	_command_handlers["get_editor_state"] = func(p: Dictionary):
		var tree := get_tree()
		var current_scene: Node = tree.edited_scene_root if tree else null
		var selected_paths: Array = []
		if EditorInterface.get_selection():
			for n in EditorInterface.get_selection().get_selected_nodes():
				if current_scene:
					selected_paths.append(str(current_scene.get_path_to(n)))
				else:
					selected_paths.append(n.name)
		return {
			"result": {
				"active_scene": current_scene.scene_file_path if current_scene else "",
				"active_root_name": current_scene.name if current_scene else "",
				"open_scenes": EditorInterface.get_open_scenes(),
				"selected_nodes": selected_paths,
				"is_playing": EditorInterface.is_playing_scene(),
				"execution_state": coordinator.get_execution_state()
			}
		}

	if _command_handlers.has("add_node"):
		_command_handlers["create_camera_3d"] = func(p: Dictionary):
			var cp := p.duplicate()
			cp["type"] = "Camera3D"
			if not cp.has("name"): cp["name"] = "Camera3D"
			return _command_handlers["add_node"].call(cp)
		_command_handlers["create_light_3d"] = func(p: Dictionary):
			var cp := p.duplicate()
			var light_type: String = cp.get("light_type", cp.get("type", "DirectionalLight3D"))
			if not light_type.ends_with("Light3D"):
				light_type = "DirectionalLight3D"
			cp["type"] = light_type
			if not cp.has("name"): cp["name"] = light_type
			return _command_handlers["add_node"].call(cp)
		_command_handlers["create_mesh_instance_3d"] = func(p: Dictionary):
			var cp := p.duplicate()
			cp["type"] = "MeshInstance3D"
			if not cp.has("name"): cp["name"] = "MeshInstance3D"
			return _command_handlers["add_node"].call(cp)
		_command_handlers["create_collision_shape_3d"] = func(p: Dictionary):
			var cp := p.duplicate()
			cp["type"] = "CollisionShape3D"
			if not cp.has("name"): cp["name"] = "CollisionShape3D"
			return _command_handlers["add_node"].call(cp)

	if _command_handlers.has("move_node"):
		_command_handlers["reparent_node"] = func(p: Dictionary):
			var cp := p.duplicate()
			if not cp.has("new_parent_path"):
				if cp.has("new_parent"): cp["new_parent_path"] = cp["new_parent"]
				elif cp.has("parent_path"): cp["new_parent_path"] = cp["parent_path"]
				elif cp.has("parent"): cp["new_parent_path"] = cp["parent"]
				elif cp.has("target_path"): cp["new_parent_path"] = cp["target_path"]
				elif cp.has("target"): cp["new_parent_path"] = cp["target"]
			if not cp.has("node_path"):
				if cp.has("path"): cp["node_path"] = cp["path"]
				elif cp.has("node"): cp["node_path"] = cp["node"]
				elif cp.has("source_path"): cp["node_path"] = cp["source_path"]
				elif cp.has("source"): cp["node_path"] = cp["source"]
			return _command_handlers["move_node"].call(cp)

	_command_handlers["save_project_settings"] = func(p: Dictionary):
		var err := ProjectSettings.save()
		if err == OK:
			return {"result": {"saved": true}}
		return {"error": {"code": -32603, "message": "Failed to save project settings: %d" % err}}

	_command_handlers["refresh_filesystem"] = func(p: Dictionary):
		EditorInterface.get_resource_filesystem().scan()
		return {"result": {"rescanned": true}}
	_command_handlers["rescan_filesystem"] = _command_handlers["refresh_filesystem"]

	if _command_handlers.has("set_input_action"):
		_command_handlers["add_input_action"] = func(p: Dictionary):
			var cp := p.duplicate()
			if not cp.has("action") and cp.has("action_name"):
				cp["action"] = cp["action_name"]
			if not cp.has("events") or not (cp["events"] is Array):
				var ev_list: Array = []
				if cp.has("key") or cp.has("keycode"):
					var k_str: String = str(cp.get("key", cp.get("keycode", "Space")))
					if k_str.begins_with("Key_"):
						k_str = k_str.substr(4)
					var k_code: int = OS.find_keycode_from_string(k_str)
					if k_code == 0:
						k_code = KEY_SPACE
					ev_list.append({"type": "key", "keycode": k_code})
				else:
					ev_list.append({"type": "key", "keycode": KEY_SPACE})
				cp["events"] = ev_list
			return await _command_handlers["set_input_action"].call(cp)

	_command_handlers["list_methods"] = func(_p: Dictionary):
		var keys: Array = _command_handlers.keys()
		keys.sort()
		return {
			"result": {
				"methods": keys,
				"count": keys.size(),
				"canonical_commands": Schemas.get_canonical_commands().keys(),
				"alias_map": Schemas.get_alias_map()
			}
		}

	_command_handlers["get_documentation"] = func(p: Dictionary):
		var method: String = p.get("method", p.get("name", p.get("tool", "")))
		if _command_handlers.has(method):
			var canonical_map := Schemas.get_canonical_commands()
			var alias_map := Schemas.get_alias_map()
			var doc := {
				"method": method,
				"available": true,
				"is_disabled": _disabled_tools.get(method, false)
			}
			if canonical_map.has(method):
				doc["schema"] = canonical_map[method]
			elif alias_map.has(method):
				doc["alias_info"] = alias_map[method]
			return {"result": doc}
		return {"error": {"code": -32601, "message": "Method '%s' not found" % method}}

	if _command_handlers.has("read_resource"):
		_command_handlers["load_resource"] = _command_handlers["read_resource"]

	print("[MCP] Registered %d commands with Dual-Track LifecycleCoordinator" % _command_handlers.size())


func execute(method: String, params: Dictionary) -> Dictionary:
	if not _command_handlers.has(method):
		return {
			"error": {
				"code": -32601,
				"message": "Method '%s' not found. Check tool name or use get_editor_state/list_methods." % method
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
