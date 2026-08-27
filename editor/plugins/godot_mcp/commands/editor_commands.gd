@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

const CaptureProtocol = preload("res://addons/godot_mcp/lifecycle/runtime_capture_protocol.gd")


func get_commands() -> Dictionary:
	return {
		"get_editor_errors": _get_editor_errors,
		"get_output_log": _get_output_log,
		"get_editor_screenshot": _get_editor_screenshot,
		"get_game_screenshot": _get_game_screenshot,
		"execute_editor_script": _execute_editor_script,
		"clear_output": _clear_output,
		"reload_plugin": _reload_plugin,
		"reload_project": _reload_project,
		"get_signals": _get_signals,
		"compare_screenshots": _compare_screenshots,
		"set_auto_dismiss": _set_auto_dismiss,
		"get_editor_camera": _get_editor_camera,
		"set_editor_camera": _set_editor_camera,
	}


func _get_editor_errors(params: Dictionary) -> Dictionary:
	var errors: Array = []
	var max_lines: int = optional_int(params, "max_lines", 50)

	# 1. Read from log files without touching UI hierarchy
	var log_paths: Array[String] = ["user://logs/godot.log", "user://logs/editor.log", "user://godot.log"]
	for log_path in log_paths:
		if FileAccess.file_exists(log_path):
			var file := FileAccess.open(log_path, FileAccess.READ)
			if file != null:
				var content := file.get_as_text()
				file.close()
				var lines := content.split("\n")
				var start: int = maxi(0, lines.size() - max_lines)
				for i in range(start, lines.size()):
					var line: String = lines[i]
					if line.contains("ERROR") or line.contains("SCRIPT ERROR") or line.contains("Parse Error") or line.contains("WARNING"):
						errors.append(line.strip_edges())
				break

	# 2. Check the script editor for compile errors (red background lines)
	#    These don't appear in the Output panel
	var script_errors: Array = []
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor:
		var current_script: Script = script_editor.get_current_script()
		var ce: CodeEdit = _find_code_edit(script_editor)
		if ce and current_script:
			var script_path: String = current_script.resource_path
			for i in range(ce.get_line_count()):
				var bg: Color = ce.get_line_background_color(i)
				if bg.r > 0.8 and bg.a > 0:  # Red-ish background = error
					var line_text: String = ce.get_line(i).strip_edges()
					script_errors.append("COMPILE ERROR: %s:%d - %s" % [script_path, i + 1, line_text])

	# 3. Read from script editor error/warning panels (GDScript analyzer messages)
	#    Each open script editor has a VSplitContainer with two RichTextLabels:
	#    child[1] = warnings panel, child[2] = errors panel
	var analyzer_errors: Array = []
	if script_editor:
		var open_editors: Array = script_editor.get_open_script_editors()
		var open_scripts: Array = script_editor.get_open_scripts()
		for ei in range(open_editors.size()):
			var editor_node: Node = open_editors[ei]
			var script_path: String = ""
			if ei < open_scripts.size() and open_scripts[ei] != null:
				script_path = (open_scripts[ei] as Resource).resource_path
			var vsplit: VSplitContainer = null
			for c in editor_node.get_children():
				if c is VSplitContainer:
					vsplit = c as VSplitContainer
					break
			if vsplit == null:
				continue
			var children: Array = vsplit.get_children()
			# child[1] = warnings panel (RichTextLabel)
			if children.size() > 1 and children[1] is RichTextLabel:
				var text: String = (children[1] as RichTextLabel).get_parsed_text().strip_edges()
				if not text.is_empty():
					for line in text.split("\n"):
						var stripped: String = line.strip_edges()
						if stripped.is_empty() or stripped == "[Ignore]":
							continue
						# Remove leading "[Ignore]" prefix from warning lines
						stripped = stripped.trim_prefix("[Ignore]")
						var prefix: String = "WARNING: %s:" % script_path if not script_path.is_empty() else "WARNING: "
						analyzer_errors.append(prefix + stripped)
			# child[2] = errors panel (RichTextLabel)
			if children.size() > 2 and children[2] is RichTextLabel:
				var text: String = (children[2] as RichTextLabel).get_parsed_text().strip_edges()
				if not text.is_empty():
					for line in text.split("\n"):
						var stripped: String = line.strip_edges()
						if stripped.is_empty():
							continue
						var prefix: String = "SCRIPT ERROR: %s:" % script_path if not script_path.is_empty() else "SCRIPT ERROR: "
						analyzer_errors.append(prefix + stripped)

	# 4. Read from the debugger Errors tab (runtime errors/warnings)
	#    Path: ScriptEditorDebugger > TabContainer > "Errors" VBoxContainer > Tree
	var debugger_errors: Array = []
	var base2: Control = get_editor().get_base_control()
	if base2:
		var queue: Array[Node] = [base2]
		while not queue.is_empty():
			var node := queue.pop_front()
			if node.get_class() == "ScriptEditorDebugger":
				# Find TabContainer inside the debugger
				for child in node.get_children():
					if child is TabContainer:
						var tab_container := child as TabContainer
						for tab_idx in range(tab_container.get_tab_count()):
							var tab_control: Control = tab_container.get_tab_control(tab_idx)
							if tab_control is VBoxContainer and tab_control.name.begins_with("Errors"):
								# Find Tree inside the Errors tab
								for vchild in tab_control.get_children():
									if vchild is Tree:
										var tree := vchild as Tree
										var root_item: TreeItem = tree.get_root()
										if root_item:
											var item: TreeItem = root_item.get_first_child()
											while item:
												var col0: String = item.get_text(0).strip_edges()
												var col1: String = item.get_text(1).strip_edges()
												if not col0.is_empty() or not col1.is_empty():
													var msg: String = col0
													if not col1.is_empty():
														msg += " " + col1 if not msg.is_empty() else col1
													debugger_errors.append("DEBUGGER: " + msg)
												# Also check child items (expanded error details)
												var sub: TreeItem = item.get_first_child()
												while sub:
													var sub0: String = sub.get_text(0).strip_edges()
													var sub1: String = sub.get_text(1).strip_edges()
													if not sub0.is_empty() or not sub1.is_empty():
														var sub_msg: String = sub0
														if not sub1.is_empty():
															sub_msg += " " + sub1 if not sub_msg.is_empty() else sub1
														debugger_errors.append("DEBUGGER:   " + sub_msg)
													sub = sub.get_next()
												item = item.get_next()
								break  # Found Errors tab, stop searching tabs
						break  # Found TabContainer, stop searching debugger children
				break  # Found ScriptEditorDebugger, stop BFS
			for child in node.get_children():
				queue.append(child)

	# Fallback: read from log file if Output panel not accessible
	if errors.size() == 0 and script_errors.size() == 0 and analyzer_errors.size() == 0 and debugger_errors.size() == 0:
		var log_path := "user://logs/godot.log"
		if FileAccess.file_exists(log_path):
			var file := FileAccess.open(log_path, FileAccess.READ)
			if file:
				var content := file.get_as_text()
				file.close()
				var lines := content.split("\n")
				var start: int = maxi(0, lines.size() - max_lines)
				for i in range(start, lines.size()):
					var line: String = lines[i]
					if line.contains("ERROR") or line.contains("SCRIPT ERROR"):
						errors.append(line.strip_edges())

	errors.append_array(script_errors)
	errors.append_array(analyzer_errors)
	errors.append_array(debugger_errors)
	return success({"errors": errors, "count": errors.size()})


func _get_output_log(params: Dictionary) -> Dictionary:
	var max_lines: int = optional_int(params, "max_lines", 100)
	var filter: String = optional_string(params, "filter", "")

	# Read safely from log file without touching live UI scene tree
	var log_paths: Array[String] = [
		get_game_user_dir() + "/logs/godot.log",
		get_game_user_dir() + "/godot.log",
		"user://logs/godot.log",
		"user://logs/editor.log",
		"user://godot.log"
	]
	if FileAccess.file_exists("res://screenshots/qa_runtime_log.txt"):
		log_paths.push_front("res://screenshots/qa_runtime_log.txt")

	for log_path in log_paths:
		if FileAccess.file_exists(log_path):
			var file := FileAccess.open(log_path, FileAccess.READ)
			if file != null:
				var content := file.get_as_text()
				file.close()
				var lines := content.split("\n")
				var start: int = maxi(0, lines.size() - max_lines)
				var output_lines: Array = []
				for i in range(start, lines.size()):
					var line: String = lines[i]
					if filter.is_empty() or line.contains(filter):
						output_lines.append(line)
				if not output_lines.is_empty():
					var src_tag := "game_log" if log_path.contains("qa_runtime_log") or log_path.begins_with(get_game_user_dir()) else "log_file"
					return success({"lines": output_lines, "count": output_lines.size(), "source": src_tag})

	return success({"lines": [], "count": 0, "source": "none"})


func _find_code_edit(node: Node, depth: int = 0) -> CodeEdit:
	if depth > 8:
		return null
	if node is CodeEdit:
		return node as CodeEdit
	for child in node.get_children():
		var found: CodeEdit = _find_code_edit(child, depth + 1)
		if found:
			return found
	return null


func _find_rtl(node: Node, depth: int = 0) -> RichTextLabel:
	if depth > 6:
		return null
	if node is RichTextLabel:
		return node as RichTextLabel
	for child in node.get_children():
		var found: RichTextLabel = _find_rtl(child, depth + 1)
		if found:
			return found
	return null


func _get_editor_screenshot(params: Dictionary) -> Dictionary:
	var base_control: Control = get_editor().get_base_control()
	if base_control == null:
		return error_internal("Could not access editor base control")

	var viewport: Viewport = base_control.get_viewport()
	if viewport == null:
		return error_internal("Could not access editor viewport")

	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return error_internal("Could not get viewport texture")

	var image: Image = texture.get_image()
	if image == null:
		return error_internal("Could not get image from viewport")

	var png_buffer: PackedByteArray = image.save_png_to_buffer()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(png_buffer)
	var sha: String = ctx.finish().hex_encode()
	var now: int = Time.get_ticks_msec()

	var save_path: String = params.get("save_path", params.get("path", ""))
	if save_path != "":
		var abs_path := _resolve_save_path(save_path)
		var err := image.save_png(abs_path)
		if err != OK:
			return error_internal("Failed to save screenshot: %s" % error_string(err))
		return success({
			"requested_source": "editor",
			"actual_source": "editor_viewport",
			"backend": "editor_viewport",
			"path": save_path,
			"saved_path": save_path,
			"global_path": abs_path,
			"width": image.get_width(),
			"height": image.get_height(),
			"format": "png",
			"sha256": sha,
			"capture_timestamp_ms": now,
			"source": "editor"
		})

	var base64 := Marshalls.raw_to_base64(png_buffer)
	return success({
		"requested_source": "editor",
		"actual_source": "editor_viewport",
		"backend": "editor_viewport",
		"image_base64": base64,
		"width": image.get_width(),
		"height": image.get_height(),
		"format": "png",
		"sha256": sha,
		"capture_timestamp_ms": now,
		"source": "editor"
	})





func _get_game_screenshot(params: Dictionary) -> Dictionary:
	var envelope := get_authoritative_game_envelope()
	if envelope.has("error"):
		return envelope

	var session_id := str(envelope.get("session_id", ""))
	var operation_id := str(envelope.get("operation_id", ""))
	var boot_nonce := str(envelope.get("boot_nonce", ""))
	var requested_operation_id := optional_string(params, "operation_id", "")
	if not requested_operation_id.is_empty() and requested_operation_id != operation_id:
		return error_conflict("Screenshot operation_id does not match the active GameAbility session.", {
			"symbol": "INVALID_OPERATION_ID",
			"session_id": session_id,
			"operation_id": operation_id,
		})

	var request_id := _generate_capture_request_id()
	if request_id.is_empty():
		return error_internal("Failed to generate a secure screenshot request ID")
	var game_user_dir := get_game_user_dir()
	var capture_dir := CaptureProtocol.session_dir(game_user_dir, session_id)
	if capture_dir.is_empty():
		return error_internal("Active GameAbility session ID cannot be used for the capture transport")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(capture_dir)
	if mkdir_error != OK and not DirAccess.dir_exists_absolute(capture_dir):
		return error_internal("Could not create the GameAbility capture session directory: %s" % error_string(mkdir_error))
	var request_path := CaptureProtocol.request_path(capture_dir, request_id)
	var request_tmp_path := request_path + CaptureProtocol.TEMP_SUFFIX
	var response_path := CaptureProtocol.response_path(capture_dir, request_id)
	var image_path := CaptureProtocol.image_path(capture_dir, request_id)
	var artifacts: Array[String] = [request_tmp_path, request_path, response_path, image_path]
	_cleanup_capture_artifacts(artifacts)

	var request := {
		"request_id": request_id,
		"session_id": session_id,
		"operation_id": operation_id,
		"boot_nonce": boot_nonce,
		"requested_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}
	var request_file := FileAccess.open(request_tmp_path, FileAccess.WRITE)
	if request_file == null:
		return error_internal("Could not create the GameAbility screenshot request in %s" % game_user_dir)
	request_file.store_string(JSON.stringify(request))
	request_file.close()
	var publish_error := DirAccess.rename_absolute(request_tmp_path, request_path)
	if publish_error != OK:
		_cleanup_capture_artifacts(artifacts)
		return error_internal("Could not publish the GameAbility screenshot request: %s" % error_string(publish_error))

	var deadline_ms := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms and not FileAccess.file_exists(response_path):
		await get_tree().create_timer(0.05).timeout
		var current := get_authoritative_game_envelope()
		if current.has("error") or str(current.get("session_id", "")) != session_id or str(current.get("operation_id", "")) != operation_id or str(current.get("boot_nonce", "")) != boot_nonce:
			_cleanup_capture_artifacts(artifacts)
			return error_conflict("GameAbility session ended or changed while capturing the screenshot.", {
				"symbol": "SESSION_ENDED",
				"session_id": session_id,
				"request_id": request_id,
			})

	if not FileAccess.file_exists(response_path):
		_cleanup_capture_artifacts(artifacts)
		return error_conflict("GameAbility screenshot capture timed out without a correlated response.", {
			"symbol": "CAPTURE_BACKEND_UNAVAILABLE",
			"session_id": session_id,
			"request_id": request_id,
			"backend": CaptureProtocol.BACKEND,
		})

	var response := _read_capture_response(response_path)
	if response.is_empty():
		_cleanup_capture_artifacts(artifacts)
		return error_internal("GameAbility returned an unreadable screenshot response", {
			"symbol": "STALE_CAPTURE_RESPONSE",
			"session_id": session_id,
			"request_id": request_id,
		})
	if str(response.get("status", "")) != "ok":
		var runtime_error := str(response.get("error", "GameAbility screenshot capture failed"))
		_cleanup_capture_artifacts(artifacts)
		return error_conflict(runtime_error, {
			"symbol": "CAPTURE_BACKEND_UNAVAILABLE",
			"session_id": session_id,
			"request_id": request_id,
			"backend": CaptureProtocol.BACKEND,
		})

	var validation_error := CaptureProtocol.validate_success_response(response, session_id, operation_id, boot_nonce, request_id)
	if not validation_error.is_empty():
		_cleanup_capture_artifacts(artifacts)
		return error_conflict(validation_error, {
			"symbol": "STALE_CAPTURE_RESPONSE",
			"session_id": session_id,
			"request_id": request_id,
		})
	if not FileAccess.file_exists(image_path):
		_cleanup_capture_artifacts(artifacts)
		return error_internal("Correlated GameAbility response did not publish its PNG artifact", {
			"symbol": "STALE_CAPTURE_RESPONSE",
			"session_id": session_id,
			"request_id": request_id,
		})

	var image_file := FileAccess.open(image_path, FileAccess.READ)
	if image_file == null:
		_cleanup_capture_artifacts(artifacts)
		return error_internal("Could not read the GameAbility screenshot artifact")
	var png_buffer := image_file.get_buffer(image_file.get_length())
	image_file.close()
	var computed_sha := _sha256_bytes(png_buffer)
	var reported_sha := str(response.get("sha256", ""))
	if computed_sha.is_empty() or computed_sha != reported_sha:
		_cleanup_capture_artifacts(artifacts)
		return error_internal("GameAbility screenshot SHA-256 integrity check failed", {
			"symbol": "STALE_CAPTURE_RESPONSE",
			"session_id": session_id,
			"request_id": request_id,
			"reported_sha256": reported_sha,
			"computed_sha256": computed_sha,
		})
	if png_buffer.size() != int(response.get("byte_count", 0)):
		_cleanup_capture_artifacts(artifacts)
		return error_internal("GameAbility screenshot byte count does not match the correlated response", {
			"symbol": "STALE_CAPTURE_RESPONSE",
			"session_id": session_id,
			"request_id": request_id,
		})

	var image := Image.new()
	var image_error := image.load_png_from_buffer(png_buffer)
	if image_error != OK:
		_cleanup_capture_artifacts(artifacts)
		return error_internal("Failed to decode the correlated GameAbility PNG: %s" % error_string(image_error))
	if image.get_width() != int(response.get("width", 0)) or image.get_height() != int(response.get("height", 0)):
		_cleanup_capture_artifacts(artifacts)
		return error_internal("GameAbility screenshot dimensions do not match the correlated response", {
			"symbol": "STALE_CAPTURE_RESPONSE",
			"session_id": session_id,
			"request_id": request_id,
		})

	_cleanup_capture_artifacts(artifacts)
	var result := {
		"requested_source": "game",
		"actual_source": "game_ability",
		"backend": CaptureProtocol.BACKEND,
		"session_id": session_id,
		"request_id": request_id,
		"width": image.get_width(),
		"height": image.get_height(),
		"format": "png",
		"byte_count": png_buffer.size(),
		"sha256": computed_sha,
		"capture_timestamp_ms": int(response.get("capture_timestamp_ms", 0)),
		"source": "game",
		"provenance": {
			"source": "game_ability",
			"backend": CaptureProtocol.BACKEND,
			"session_id": session_id,
			"operation_id": operation_id,
			"request_id": request_id,
		},
	}
	var save_path := optional_string(params, "save_path", optional_string(params, "path", ""))
	if save_path.is_empty():
		result["image_base64"] = Marshalls.raw_to_base64(png_buffer)
		return success(result)

	var absolute_save_path := _resolve_save_path(save_path)
	var parent_dir := absolute_save_path.get_base_dir()
	if not parent_dir.is_empty():
		var output_mkdir_error := DirAccess.make_dir_recursive_absolute(parent_dir)
		if output_mkdir_error != OK and not DirAccess.dir_exists_absolute(parent_dir):
			return error_internal("Failed to create screenshot output directory %s: %s" % [parent_dir, error_string(output_mkdir_error)])
	var output_file := FileAccess.open(absolute_save_path, FileAccess.WRITE)
	if output_file == null:
		return error_internal("Failed to open screenshot output path %s" % absolute_save_path)
	output_file.store_buffer(png_buffer)
	output_file.close()
	result["path"] = save_path
	result["saved_path"] = save_path
	result["global_path"] = absolute_save_path
	return success(result)


func _generate_capture_request_id() -> String:
	var crypto := Crypto.new()
	var random_bytes := crypto.generate_random_bytes(16)
	if random_bytes.size() != 16:
		return ""
	return "req_" + random_bytes.hex_encode()


func _read_capture_response(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _cleanup_capture_artifacts(paths: Array[String]) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _resolve_save_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _execute_editor_script(params: Dictionary) -> Dictionary:
	var result := require_string(params, "code")
	if result[1] != null:
		return result[1]
	var code: String = result[0]
	var allow_unsafe_editor_io: bool = optional_bool(params, "allow_unsafe_editor_io", false)
	var unsafe_guard := _guard_editor_script_file_io(code, allow_unsafe_editor_io)
	if not unsafe_guard.is_empty():
		return unsafe_guard

	# Wrap user code in a @tool script.
	# The wrapper returns a sentinel rather than _mcp_output, so a caller that
	# never returns anything of its own does not get the printed output echoed
	# back a second time as an escaped string in return_value.
	var wrapped_code := """@tool
extends Node

var _mcp_output: Array = []
# Read back through `self` below, so a same-named local in the caller's code
# cannot shadow it.
var _mcp_sentinel := RefCounted.new()

func _mcp_print(value: Variant) -> void:
	_mcp_output.append(str(value))

func run() -> Variant:
	# User code begins
%s
	# User code ends
	return self._mcp_sentinel
""" % _indent_code(code)

	# Create a temporary script
	var script := GDScript.new()
	script.source_code = wrapped_code
	var err := script.reload()

	if err != OK:
		return error(-32002, "Script compilation failed", {
			"error": error_string(err),
			"code": wrapped_code,
		})

	# Create temp node and execute
	var temp_node := Node.new()
	temp_node.set_script(script)
	add_child(temp_node)

	var output: Variant = null

	# Execute with error handling
	if temp_node.has_method("run"):
		output = temp_node.run()

	var mcp_output: Array = []
	var raw_output: Variant = temp_node.get("_mcp_output")
	if raw_output is Array:
		mcp_output = raw_output

	# Read the sentinel before freeing the node that owns it.
	var sentinel: Variant = temp_node.get("_mcp_sentinel")

	# Cleanup
	temp_node.queue_free()

	# Suppress only the sentinel. An explicit `return null` from the caller's
	# code is a real return value and stays distinguishable from no return.
	# The sentinel is an object identity rather than a magic string, because
	# any string a caller might return is a legitimate result.
	var payload := {"output": mcp_output}
	if not (output is RefCounted and output == sentinel):
		payload["return_value"] = str(output) if output != null else null
	return success(payload)


func _guard_editor_script_file_io(code: String, allow_unsafe_editor_io: bool) -> Dictionary:
	if allow_unsafe_editor_io:
		return {}
	var compact := code.replace(" ", "").replace("\t", "").replace("\n", "")
	var unsafe_patterns: Array[String] = []
	if compact.contains("ResourceSaver.save("):
		unsafe_patterns.append("ResourceSaver.save")
	if compact.contains("ProjectSettings.save("):
		unsafe_patterns.append("ProjectSettings.save")
	if compact.contains("ConfigFile.save("):
		unsafe_patterns.append("ConfigFile.save")
	if compact.contains("FileAccess.open(") and _contains_any(compact, ["FileAccess.WRITE", "FileAccess.READ_WRITE", "FileAccess.WRITE_READ"]):
		unsafe_patterns.append("FileAccess.open WRITE")
	if _contains_any(compact, ["DirAccess.remove_absolute(", "DirAccess.rename_absolute(", "DirAccess.copy_absolute(", "DirAccess.make_dir_absolute(", "DirAccess.make_dir_recursive_absolute("]):
		unsafe_patterns.append("DirAccess filesystem mutation")
	if unsafe_patterns.is_empty():
		return {}
	return error_conflict(
		"Refusing to execute editor script with direct file/resource write APIs",
		{
			"unsafe_patterns": unsafe_patterns,
			"open_scenes": get_open_scene_paths(),
			"suggestion": "Use dedicated MCP commands and save_scene for editor-owned resources, or pass allow_unsafe_editor_io=true only when no open editor resource can be overwritten.",
			"note": "This is a text match on the submitted source, meant to catch accidents. It is not a security boundary: a dynamically built call, or a destructive API not on the list, is not caught.",
		}
	)


func _contains_any(value: String, needles: Array[String]) -> bool:
	for needle: String in needles:
		if value.contains(needle):
			return true
	return false


func _indent_code(code: String) -> String:
	var lines := code.split("\n")
	var indented: PackedStringArray = []
	for line in lines:
		indented.append("\t" + line)
	return "\n".join(indented)


func _clear_output(params: Dictionary) -> Dictionary:
	print("\n".repeat(50))
	return success({"cleared": true})


func _reload_plugin(params: Dictionary) -> Dictionary:
	# Disable and re-enable this plugin to reload all scripts
	var plugin_name := "godot_mcp"
	var ei := get_editor()

	# Send success BEFORE reloading (connection will briefly drop)
	# Use call_deferred so the response is sent first
	_deferred_reload_plugin.call_deferred(ei, plugin_name)
	return success({"reloading": true, "message": "Plugin will reload momentarily. Connection will briefly drop and auto-reconnect."})


func _deferred_reload_plugin(ei: EditorInterface, plugin_name: String) -> void:
	ei.set_plugin_enabled(plugin_name, false)
	ei.set_plugin_enabled(plugin_name, true)
	print("[MCP] Plugin reloaded")


func _reload_project(params: Dictionary) -> Dictionary:
	# Rescan filesystem and reload changed scripts
	var ei := get_editor()
	ei.get_resource_filesystem().scan()

	return success({"reloaded": true, "message": "Filesystem rescanned."})


func _get_signals(params: Dictionary) -> Dictionary:
	var result := require_string(params, "node_path")
	if result[1] != null:
		return result[1]
	var node_path: String = result[0]

	var root := get_edited_root()
	if root == null:
		return error_no_scene()

	var node := find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	var signals: Array = []
	for sig in node.get_signal_list():
		var sig_info: Dictionary = {
			"name": sig["name"],
			"args": [],
		}
		for arg in sig["args"]:
			sig_info["args"].append({"name": arg["name"], "type": arg["type"]})

		# Get connections for this signal
		var connections: Array = []
		for conn in node.get_signal_connection_list(sig["name"]):
			connections.append({
				"target": str(root.get_path_to(conn["callable"].get_object())),
				"method": conn["callable"].get_method(),
			})
		sig_info["connections"] = connections
		signals.append(sig_info)

	return success({
		"node_path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"signals": signals,
		"count": signals.size(),
	})


func _load_image_from_param(value: String, label: String) -> Array:
	## Returns [Image, null] on success or [null, error_dict] on failure.
	## Accepts a file path (res://, user://) or raw base64 PNG data.
	var img := Image.new()
	if value.begins_with("res://") or value.begins_with("user://"):
		var err := img.load(value)
		if err != OK:
			return [null, error_invalid_params("Failed to load %s from path '%s': %s" % [label, value, error_string(err)])]
		return [img, null]
	# Treat as base64 PNG
	var buf := Marshalls.base64_to_raw(value)
	var err := img.load_png_from_buffer(buf)
	if err != OK:
		return [null, error_invalid_params("Failed to decode %s from base64: %s" % [label, error_string(err)])]
	return [img, null]


func _compare_screenshots(params: Dictionary) -> Dictionary:
	var result := require_string(params, "image_a")
	if result[1] != null:
		return result[1]
	var image_a_value: String = result[0]

	var result2 := require_string(params, "image_b")
	if result2[1] != null:
		return result2[1]
	var image_b_value: String = result2[0]

	var threshold: int = optional_int(params, "threshold", 10)

	# Load images (from path or base64)
	var load_a := _load_image_from_param(image_a_value, "image_a")
	if load_a[1] != null:
		return load_a[1]
	var img_a: Image = load_a[0]

	var load_b := _load_image_from_param(image_b_value, "image_b")
	if load_b[1] != null:
		return load_b[1]
	var img_b: Image = load_b[0]

	if img_a.get_size() != img_b.get_size():
		return error_invalid_params("Image sizes differ: %s vs %s" % [str(img_a.get_size()), str(img_b.get_size())])

	var width := img_a.get_width()
	var height := img_a.get_height()
	var diff_image := Image.create(width, height, false, Image.FORMAT_RGBA8)

	var changed_pixels: int = 0
	var total_pixels: int = width * height

	for y in height:
		for x in width:
			var ca: Color = img_a.get_pixel(x, y)
			var cb: Color = img_b.get_pixel(x, y)
			var dr := absi(int(ca.r8) - int(cb.r8))
			var dg := absi(int(ca.g8) - int(cb.g8))
			var db := absi(int(ca.b8) - int(cb.b8))
			var max_diff := maxi(dr, maxi(dg, db))
			if max_diff > threshold:
				changed_pixels += 1
				# Red highlight for changed pixels
				diff_image.set_pixel(x, y, Color(1, 0, 0, clampf(float(max_diff) / 255.0, 0.3, 1.0)))
			else:
				# Dim version of original
				diff_image.set_pixel(x, y, Color(ca.r * 0.3, ca.g * 0.3, ca.b * 0.3, 1.0))

	var diff_percentage: float = (float(changed_pixels) / float(total_pixels)) * 100.0
	var identical: bool = changed_pixels == 0

	# Encode diff image
	var diff_png := diff_image.save_png_to_buffer()
	var diff_base64 := Marshalls.raw_to_base64(diff_png)

	return success({
		"identical": identical,
		"changed_pixels": changed_pixels,
		"total_pixels": total_pixels,
		"diff_percentage": snappedf(diff_percentage, 0.01),
		"threshold": threshold,
		"width": width,
		"height": height,
		"diff_image_base64": diff_base64,
	})


func _get_editor_camera(_params: Dictionary) -> Dictionary:
	var vp3d := EditorInterface.get_editor_viewport_3d()
	var cam := vp3d.get_camera_3d() if vp3d else null
	if not cam:
		return error(-32000, "No 3D editor camera found", {
			"suggestion": "Make sure a 3D scene is open in the editor",
		})
	var pos := cam.global_position
	var rot := cam.rotation_degrees
	return success({
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"rotation_degrees": {"x": rot.x, "y": rot.y, "z": rot.z},
		"fov": cam.fov,
		"near": cam.near,
		"far": cam.far,
	})


func _set_editor_camera(params: Dictionary) -> Dictionary:
	var vp3d := EditorInterface.get_editor_viewport_3d()
	var cam := vp3d.get_camera_3d() if vp3d else null
	if not cam:
		return error(-32000, "No 3D editor camera found", {
			"suggestion": "Make sure a 3D scene is open in the editor",
		})

	# Set position
	if params.has("position"):
		var p: Dictionary = params["position"]
		cam.global_position = Vector3(
			float(p.get("x", cam.global_position.x)),
			float(p.get("y", cam.global_position.y)),
			float(p.get("z", cam.global_position.z)),
		)

	# Set rotation
	if params.has("rotation_degrees"):
		var r: Dictionary = params["rotation_degrees"]
		cam.rotation_degrees = Vector3(
			float(r.get("x", cam.rotation_degrees.x)),
			float(r.get("y", cam.rotation_degrees.y)),
			float(r.get("z", cam.rotation_degrees.z)),
		)

	# Look at target (overrides rotation if set)
	if params.has("look_at"):
		var t: Dictionary = params["look_at"]
		cam.look_at(Vector3(float(t.get("x", 0)), float(t.get("y", 0)), float(t.get("z", 0))))

	# Set FOV
	if params.has("fov"):
		cam.fov = optional_float(params, "fov")

	var pos := cam.global_position
	var rot := cam.rotation_degrees
	return success({
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"rotation_degrees": {"x": rot.x, "y": rot.y, "z": rot.z},
		"fov": cam.fov,
	})


func _set_auto_dismiss(params: Dictionary) -> Dictionary:
	var enabled: bool = params.get("enabled", true)
	editor_plugin.auto_dismiss_dialogs = enabled
	return success({
		"auto_dismiss": enabled,
		"message": "Auto-dismiss dialogs %s" % ("enabled" if enabled else "disabled"),
	})
