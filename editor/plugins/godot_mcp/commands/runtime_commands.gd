@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

## Editor-side commands for runtime game inspection.
## Communicates with MCPGameInspector autoload via file-based IPC.


func get_commands() -> Dictionary:
	return {
		"get_game_scene_tree": _get_game_scene_tree,
		"get_game_node_properties": _get_game_node_properties,
		"set_game_node_property": _set_game_node_property,
		"capture_frames": _capture_frames,
		"monitor_properties": _monitor_properties,
		"execute_game_script": _execute_game_script,
		"start_recording": _start_recording,
		"stop_recording": _stop_recording,
		"replay_recording": _replay_recording,
		"find_nodes_by_script": _find_nodes_by_script,
		"get_autoload": _get_autoload,
		"batch_get_properties": _batch_get_properties,
		"find_ui_elements": _find_ui_elements,
		"click_button_by_text": _click_button_by_text,
		"wait_for_node": _wait_for_node,
		"find_nearby_nodes": _find_nearby_nodes,
		"navigate_to": _navigate_to,
		"move_to": _move_to,
		"watch_signals": _watch_signals,
	}


func _get_active_simulated_root() -> Node:
	var runner = get_tree().root.find_child("InEditorGameRunner", true, false)
	if runner and runner.has_method("get_simulated_root"):
		return runner.get_simulated_root()
	return null


func _serialize_simulated_node(node: Node, max_depth: int, current_depth: int) -> Dictionary:
	var data := {
		"name": node.name,
		"class": node.get_class(),
		"path": str(node.get_path()),
		"child_count": node.get_child_count(),
		"process_mode": node.process_mode
	}
	if node.get_script():
		data["script"] = node.get_script().resource_path
	if max_depth < 0 or current_depth < max_depth:
		var children: Array = []
		for child in node.get_children():
			children.append(_serialize_simulated_node(child, max_depth, current_depth + 1))
		data["children"] = children
	return data


func _find_simulated_node(root: Node, path_str: String) -> Node:
	if path_str.is_empty() or path_str == "." or path_str == root.name or path_str == "/root":
		return root
	var clean_path := path_str.trim_prefix(".").trim_prefix("/")
	if root.has_node(clean_path):
		return root.get_node(clean_path)
	return root.find_child(clean_path.get_file(), true, false)


func _get_game_scene_tree(params: Dictionary) -> Dictionary:
	var sim_root := _get_active_simulated_root()
	var max_depth: int = optional_int(params, "max_depth", -1)
	if sim_root and is_instance_valid(sim_root):
		var tree_data := _serialize_simulated_node(sim_root, max_depth, 0)
		return success({"tree": tree_data, "mode": "in_editor_viewport", "root_name": sim_root.name})

	var cmd_params := {"max_depth": max_depth}
	var script_filter: String = optional_string(params, "script_filter")
	if not script_filter.is_empty():
		cmd_params["script_filter"] = script_filter
	var type_filter: String = optional_string(params, "type_filter")
	if not type_filter.is_empty():
		cmd_params["type_filter"] = type_filter
	var named_only: bool = optional_bool(params, "named_only", false)
	if named_only:
		cmd_params["named_only"] = true

	return await _send_game_command("get_scene_tree", cmd_params)


func _get_game_node_properties(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	var sim_root := _get_active_simulated_root()
	if sim_root and is_instance_valid(sim_root):
		var target := _find_simulated_node(sim_root, result[0])
		if target == null:
			return error_not_found("Node '%s' not found in active simulation" % result[0])
		var props: Dictionary = {}
		var requested_props: Array = params.get("properties", [])
		if requested_props.is_empty():
			for p in target.get_property_list():
				var pname: String = p["name"]
				if not pname.begins_with("_"):
					props[pname] = target.get(pname)
		else:
			for pname in requested_props:
				props[str(pname)] = target.get(str(pname))
		return success({"node_path": str(target.get_path()), "properties": props, "mode": "in_editor_viewport"})

	var cmd_params := {"node_path": result[0]}
	if params.has("properties") and params["properties"] is Array:
		cmd_params["properties"] = params["properties"]

	return await _send_game_command("get_node_properties", cmd_params)


func _set_game_node_property(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	var prop_result := require_string(params, "property")
	if prop_result[1] != null:
		return prop_result[1]

	if not params.has("value"):
		return error_invalid_params("Missing required parameter: value")

	var sim_root := _get_active_simulated_root()
	if sim_root and is_instance_valid(sim_root):
		var target := _find_simulated_node(sim_root, result[0])
		if target == null:
			return error_not_found("Node '%s' not found in active simulation" % result[0])
		target.set(prop_result[0], params["value"])
		return success({
			"node_path": str(target.get_path()),
			"property": prop_result[0],
			"value": target.get(prop_result[0]),
			"mode": "in_editor_viewport"
		})

	return await _send_game_command("set_node_property", {
		"node_path": result[0],
		"property": prop_result[0],
		"value": params["value"],
	})


func _execute_game_script(params: Dictionary) -> Dictionary:
	var result := require_string(params, "code")
	if result[1] != null:
		return result[1]

	var sim_root := _get_active_simulated_root()
	if sim_root and is_instance_valid(sim_root):
		var expr := Expression.new()
		var err := expr.parse(result[0])
		if err == OK:
			var res = expr.execute([], sim_root)
			if not expr.has_execute_failed():
				return success({"result": res, "mode": "in_editor_viewport"})
			return error_internal("Expression execution error: %s" % expr.get_error_text())
		return error_internal("Expression parse error: %d" % err)

	return await _send_game_command("execute_script", {
		"code": result[0],
	}, 10.0)


func _capture_frames(params: Dictionary) -> Dictionary:
	var count: int = optional_int(params, "count", 5)
	var frame_interval: int = optional_int(params, "frame_interval", 10)
	var half_resolution: bool = optional_bool(params, "half_resolution", true)

	var runner = get_tree().root.find_child("InEditorGameRunner", true, false)
	if runner and runner.has_method("capture_frame_image") and runner.is_running:
		var frames: Array = []
		var dir_path := ProjectSettings.globalize_path("res://screenshots")
		DirAccess.make_dir_recursive_absolute(dir_path)
		for i in range(count):
			var img: Image = runner.capture_frame_image()
			if img:
				var path := "res://screenshots/frame_%d_%d.png" % [Time.get_ticks_msec(), i]
				img.save_png(ProjectSettings.globalize_path(path))
				frames.append({"index": i, "path": path, "width": img.get_width(), "height": img.get_height()})
			await get_tree().process_frame
		return success({"frames": frames, "count": frames.size(), "mode": "in_editor_viewport"})

	var estimated_seconds: float = (count * frame_interval) / 60.0 + 2.0
	var timeout := minf(estimated_seconds, 25.0)

	return await _send_game_command("capture_frames", {
		"count": count,
		"frame_interval": frame_interval,
		"half_resolution": half_resolution,
	}, timeout)


func _monitor_properties(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	if not params.has("properties") or not params["properties"] is Array:
		return error_invalid_params("'properties' array is required")

	var frame_count: int = optional_int(params, "frame_count", 60)
	var frame_interval: int = optional_int(params, "frame_interval", 1)

	# Dynamic timeout
	var estimated_seconds: float = (frame_count * frame_interval) / 60.0 + 2.0
	var timeout := minf(estimated_seconds, 25.0)

	return await _send_game_command("monitor_properties", {
		"node_path": result[0],
		"properties": params["properties"],
		"frame_count": frame_count,
		"frame_interval": frame_interval,
	}, timeout)


func _start_recording(params: Dictionary) -> Dictionary:
	return await _send_game_command("start_recording", {})


func _stop_recording(params: Dictionary) -> Dictionary:
	return await _send_game_command("stop_recording", {}, 5.0)


func _replay_recording(params: Dictionary) -> Dictionary:
	# `for e: Dictionary in ...` raises on the first non-Dictionary entry,
	# aborting the handler before it can answer.
	var events_guard := require_dictionary_array(params, "events")
	if not events_guard.is_empty():
		return events_guard
	var speed: float = optional_float(params, "speed", 1.0)

	# Calculate timeout based on event duration
	var max_time_ms: int = 0
	for event_data: Dictionary in params["events"]:
		# time_ms comes straight from JSON; int() raises on an array or object.
		var raw_t: Variant = event_data.get("time_ms", 0)
		var t: int = int(raw_t) if (raw_t is int or raw_t is float or raw_t is bool) else 0
		if t > max_time_ms:
			max_time_ms = t
	var timeout := (max_time_ms / 1000.0 / speed) + 5.0

	return await _send_game_command("replay_recording", {
		"events": params["events"],
		"speed": speed,
	}, minf(timeout, 120.0))


func _find_nodes_by_script(params: Dictionary) -> Dictionary:
	var result := require_string(params, "script")
	if result[1] != null:
		return result[1]

	var cmd_params := {"script": result[0]}
	if params.has("properties") and params["properties"] is Array:
		cmd_params["properties"] = params["properties"]

	return await _send_game_command("find_nodes_by_script", cmd_params)


func _get_autoload(params: Dictionary) -> Dictionary:
	var result := require_string(params, "name")
	if result[1] != null:
		return result[1]

	var cmd_params := {"name": result[0]}
	if params.has("properties") and params["properties"] is Array:
		cmd_params["properties"] = params["properties"]

	return await _send_game_command("get_autoload", cmd_params)


func _batch_get_properties(params: Dictionary) -> Dictionary:
	if not params.has("nodes") or not params["nodes"] is Array:
		return error_invalid_params("'nodes' array is required")

	return await _send_game_command("batch_get_properties", {
		"nodes": params["nodes"],
	})


func _find_ui_elements(params: Dictionary) -> Dictionary:
	var cmd_params := {}
	var type_filter: String = optional_string(params, "type_filter")
	if not type_filter.is_empty():
		cmd_params["type_filter"] = type_filter
	return await _send_game_command("find_ui_elements", cmd_params)


func _click_button_by_text(params: Dictionary) -> Dictionary:
	var result := require_string(params, "text")
	if result[1] != null:
		return result[1]

	var cmd_params := {"text": result[0]}
	var partial: bool = optional_bool(params, "partial", true)
	cmd_params["partial"] = partial

	return await _send_game_command("click_button_by_text", cmd_params)


func _wait_for_node(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]

	var timeout: float = optional_float(params, "timeout", 5.0)
	var poll_frames: int = optional_int(params, "poll_frames", 5)

	return await _send_game_command("wait_for_node", {
		"node_path": result[0],
		"timeout": timeout,
		"poll_frames": poll_frames,
	}, timeout + 2.0)


func _find_nearby_nodes(params: Dictionary) -> Dictionary:
	if not params.has("position"):
		return error_invalid_params("Missing required parameter: position")

	var cmd_params: Dictionary = {"position": params["position"]}
	if params.has("radius"):
		cmd_params["radius"] = optional_float(params, "radius")
	var type_filter: String = optional_string(params, "type_filter")
	if not type_filter.is_empty():
		cmd_params["type_filter"] = type_filter
	var group_filter: String = optional_string(params, "group_filter")
	if not group_filter.is_empty():
		cmd_params["group_filter"] = group_filter
	if params.has("max_results"):
		cmd_params["max_results"] = optional_int(params, "max_results")

	return await _send_game_command("find_nearby_nodes", cmd_params)


func _navigate_to(params: Dictionary) -> Dictionary:
	if not params.has("target"):
		return error_invalid_params("Missing required parameter: target")

	var cmd_params: Dictionary = {"target": params["target"]}
	var player_path: String = optional_string(params, "player_path")
	if not player_path.is_empty():
		cmd_params["player_path"] = player_path
	var camera_path: String = optional_string(params, "camera_path")
	if not camera_path.is_empty():
		cmd_params["camera_path"] = camera_path
	if params.has("move_speed"):
		cmd_params["move_speed"] = optional_float(params, "move_speed")

	return await _send_game_command("navigate_to", cmd_params)


func _move_to(params: Dictionary) -> Dictionary:
	if not params.has("target"):
		return error_invalid_params("Missing required parameter: target")

	var cmd_params: Dictionary = {"target": params["target"]}
	var player_path: String = optional_string(params, "player_path")
	if not player_path.is_empty():
		cmd_params["player_path"] = player_path
	var camera_path: String = optional_string(params, "camera_path")
	if not camera_path.is_empty():
		cmd_params["camera_path"] = camera_path
	if params.has("arrival_radius"):
		cmd_params["arrival_radius"] = optional_float(params, "arrival_radius")
	if params.has("timeout"):
		cmd_params["timeout"] = optional_float(params, "timeout")
	if params.has("run"):
		cmd_params["run"] = optional_bool(params, "run")
	if params.has("look_at_target"):
		cmd_params["look_at_target"] = optional_bool(params, "look_at_target")

	# Dynamic timeout: game-side timeout + overhead for IPC polling
	var game_timeout: float = optional_float(params, "timeout", 15.0)
	var ipc_timeout: float = game_timeout + 5.0

	return await _send_game_command("move_to", cmd_params, ipc_timeout)


func _watch_signals(params: Dictionary) -> Dictionary:
	if not params.has("node_paths") or not params["node_paths"] is Array:
		return error_invalid_params("Missing required parameter: node_paths (Array)")

	var cmd_params: Dictionary = {"node_paths": params["node_paths"]}
	if params.has("signal_filter") and params["signal_filter"] is Array:
		cmd_params["signal_filter"] = params["signal_filter"]
	var duration_ms: int = optional_int(params, "duration_ms", 5000)
	cmd_params["duration_ms"] = duration_ms

	# Dynamic timeout: duration + overhead
	var timeout_sec: float = (duration_ms / 1000.0) + 5.0

	return await _send_game_command("watch_signals", cmd_params, timeout_sec)


# ── IPC Helper ────────────────────────────────────────────────────────────────

func _send_game_command(command: String, params: Dictionary, timeout_sec: float = 5.0) -> Dictionary:
	var ei := get_editor()
	if not ei.is_playing_scene():
		return error(-32000, "No scene is currently playing", {"suggestion": "Use play_scene first"})

	var user_dir := get_game_user_dir()
	var request_path := user_dir + "/mcp_game_request"
	var response_path := user_dir + "/mcp_game_response"

	# Clean stale response
	if FileAccess.file_exists(response_path):
		DirAccess.remove_absolute(response_path)

	# Write request
	var request_data := JSON.stringify({"command": command, "params": params})
	var req := FileAccess.open(request_path, FileAccess.WRITE)
	if req == null:
		return error_internal("Could not create game request file")
	req.store_string(request_data)
	req.close()

	# Poll for response
	var attempts := int(timeout_sec / 0.1)
	while attempts > 0:
		await get_tree().create_timer(0.1).timeout
		if FileAccess.file_exists(response_path):
			break
		# Check if game is still running
		if not ei.is_playing_scene():
			if FileAccess.file_exists(request_path):
				DirAccess.remove_absolute(request_path)
			return error(-32000, "Game stopped during command execution")
		attempts -= 1

	if not FileAccess.file_exists(response_path):
		# Try to auto-resume the debugger (runtime error may have paused the game)
		if ei.is_playing_scene():
			try_debugger_continue()
			# Give the game a chance to recover and write a response
			for _retry in 20:
				await get_tree().create_timer(0.1).timeout
				if FileAccess.file_exists(response_path):
					break

	if not FileAccess.file_exists(response_path):
		if FileAccess.file_exists(request_path):
			DirAccess.remove_absolute(request_path)
		return build_timeout_error(timeout_sec)

	# Read response
	var file := FileAccess.open(response_path, FileAccess.READ)
	if file == null:
		return error_internal("Could not read game response file")
	var text := file.get_as_text()
	file.close()
	DirAccess.remove_absolute(response_path)

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return error_internal("Invalid response JSON from game")

	if parsed.has("error"):
		return error(-32000, str(parsed["error"]))

	return success(parsed)
