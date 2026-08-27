extends Node

## Run-scoped GameAbility root-viewport capture agent.
##
## The OpenHarmony bridge injects this script as an in-memory Autoload only for
## a correlated GameAbility launch. It is also kept on disk for one migration
## release so a legacy persisted Autoload can load without an error; without a
## valid process-local correlation envelope it remains completely disabled.

const Protocol = preload("res://addons/godot_mcp/lifecycle/runtime_capture_protocol.gd")
const SESSION_ENV := "GODOT_MCP_RUNTIME_SESSION_ID"
const OPERATION_ENV := "GODOT_MCP_RUNTIME_OPERATION_ID"
const NONCE_ENV := "GODOT_MCP_RUNTIME_BOOT_NONCE"
const RUNTIME_NODE_NAME := "__GodotMCPRuntimeCapture"

var _session_id := ""
var _operation_id := ""
var _boot_nonce := ""
var _capture_dir := ""
var _capture_in_progress := false


func _ready() -> void:
	# A legacy persisted Autoload may still instantiate this compatibility file
	# once before the editor migration removes it. Only the bridge-owned runtime
	# node may consume the process-local launch envelope.
	if Engine.is_editor_hint() or name != RUNTIME_NODE_NAME:
		process_mode = Node.PROCESS_MODE_DISABLED
		set_process(false)
		return
	_session_id = OS.get_environment(SESSION_ENV)
	_operation_id = OS.get_environment(OPERATION_ENV)
	_boot_nonce = OS.get_environment(NONCE_ENV)
	# The environment is only a bootstrap hand-off. Keep the copied values in
	# this node, then erase the process-visible originals immediately.
	OS.unset_environment(SESSION_ENV)
	OS.unset_environment(OPERATION_ENV)
	OS.unset_environment(NONCE_ENV)
	var correlated := (
		Protocol.is_valid_token(_session_id)
		and Protocol.is_valid_token(_operation_id)
		and Protocol.is_valid_token(_boot_nonce)
	)
	if not correlated:
		process_mode = Node.PROCESS_MODE_DISABLED
		set_process(false)
		return
	_capture_dir = Protocol.session_dir("user://", _session_id)
	var absolute_capture_dir := ProjectSettings.globalize_path(_capture_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_capture_dir)
	if mkdir_error != OK and not DirAccess.dir_exists_absolute(absolute_capture_dir):
		push_error("[MCP Capture] Failed to create session transport directory: %s" % error_string(mkdir_error))
		process_mode = Node.PROCESS_MODE_DISABLED
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	print("[MCP Capture] GameAbility root-viewport agent ready for session ", _session_id)


func _process(_delta: float) -> void:
	if _capture_in_progress:
		return
	var request_path := _find_request_path()
	if request_path.is_empty():
		return
	_capture_in_progress = true
	_handle_request(request_path)


func _exit_tree() -> void:
	# Normal GameAbility shutdown owns this exact session directory. Abrupt
	# process death may leave it behind, but a later session uses a different
	# directory and therefore cannot consume its artifacts.
	if _capture_dir.is_empty():
		return
	var directory := DirAccess.open(_capture_dir)
	if directory != null:
		directory.list_dir_begin()
		var filename := directory.get_next()
		while not filename.is_empty():
			if not directory.current_is_dir():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(_capture_dir + "/" + filename))
			filename = directory.get_next()
		directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_capture_dir))


func _find_request_path() -> String:
	var directory := DirAccess.open(_capture_dir)
	if directory == null:
		return ""
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var request_id := Protocol.request_id_from_filename(filename)
		if not directory.current_is_dir() and not request_id.is_empty():
			directory.list_dir_end()
			return Protocol.request_path(_capture_dir, request_id)
		filename = directory.get_next()
	directory.list_dir_end()
	return ""


func _handle_request(request_path: String) -> void:
	var request_id := Protocol.request_id_from_filename(request_path.get_file())
	var request := _read_json(request_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
	if request_id.is_empty() or request.is_empty():
		_capture_in_progress = false
		return

	var correlation_error := _validate_request(request, request_id)
	if not correlation_error.is_empty():
		_write_response(request_id, {
			"status": "error",
			"error": correlation_error,
			"request_id": request_id,
			"session_id": _session_id,
			"operation_id": _operation_id,
			"boot_nonce": _boot_nonce,
			"backend": Protocol.BACKEND,
		})
		_capture_in_progress = false
		return

	# Capture only after a completed render frame. No DisplayServer or editor
	# screenshot fallback is allowed for source="game".
	await RenderingServer.frame_post_draw
	var viewport := get_viewport()
	var texture: ViewportTexture = viewport.get_texture() if viewport != null else null
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		_write_response(request_id, {
			"status": "error",
			"error": "GameAbility root viewport did not produce an image",
			"request_id": request_id,
			"session_id": _session_id,
			"operation_id": _operation_id,
			"boot_nonce": _boot_nonce,
			"backend": Protocol.BACKEND,
		})
		_capture_in_progress = false
		return

	var png_buffer := image.save_png_to_buffer()
	if png_buffer.is_empty():
		_write_response(request_id, {
			"status": "error",
			"error": "Failed to encode GameAbility root viewport as PNG",
			"request_id": request_id,
			"session_id": _session_id,
			"operation_id": _operation_id,
			"boot_nonce": _boot_nonce,
			"backend": Protocol.BACKEND,
		})
		_capture_in_progress = false
		return

	var image_path := Protocol.image_path(_capture_dir, request_id)
	var image_tmp_path := image_path + Protocol.TEMP_SUFFIX
	_remove_if_present(image_tmp_path)
	_remove_if_present(image_path)
	var image_file := FileAccess.open(image_tmp_path, FileAccess.WRITE)
	if image_file == null:
		_write_response(request_id, {
			"status": "error",
			"error": "Failed to create the GameAbility capture artifact",
			"request_id": request_id,
			"session_id": _session_id,
			"operation_id": _operation_id,
			"boot_nonce": _boot_nonce,
			"backend": Protocol.BACKEND,
		})
		_capture_in_progress = false
		return
	image_file.store_buffer(png_buffer)
	image_file.close()
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(image_tmp_path), ProjectSettings.globalize_path(image_path))
	if rename_error != OK:
		_remove_if_present(image_tmp_path)
		_write_response(request_id, {
			"status": "error",
			"error": "Failed to publish the GameAbility capture artifact",
			"request_id": request_id,
			"session_id": _session_id,
			"operation_id": _operation_id,
			"boot_nonce": _boot_nonce,
			"backend": Protocol.BACKEND,
		})
		_capture_in_progress = false
		return

	_write_response(request_id, {
		"status": "ok",
		"request_id": request_id,
		"session_id": _session_id,
		"operation_id": _operation_id,
		"boot_nonce": _boot_nonce,
		"backend": Protocol.BACKEND,
		"requested_source": "game",
		"actual_source": "game_ability",
		"width": image.get_width(),
		"height": image.get_height(),
		"format": "png",
		"byte_count": png_buffer.size(),
		"sha256": _sha256(png_buffer),
		"capture_timestamp_ms": int(Time.get_unix_time_from_system() * 1000.0),
	})
	_capture_in_progress = false


func _validate_request(request: Dictionary, request_id: String) -> String:
	var expected := {
		"request_id": request_id,
		"session_id": _session_id,
		"operation_id": _operation_id,
		"boot_nonce": _boot_nonce,
	}
	for key: String in expected:
		if str(request.get(key, "")) != str(expected[key]):
			return "Capture request %s does not match this GameAbility session" % key
	return ""


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _write_response(request_id: String, response: Dictionary) -> void:
	var response_path := Protocol.response_path(_capture_dir, request_id)
	var response_tmp_path := response_path + Protocol.TEMP_SUFFIX
	_remove_if_present(response_tmp_path)
	_remove_if_present(response_path)
	var file := FileAccess.open(response_tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[MCP Capture] Failed to write response for request %s" % request_id)
		return
	file.store_string(JSON.stringify(response))
	file.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(response_tmp_path), ProjectSettings.globalize_path(response_path))
	if err != OK:
		_remove_if_present(response_tmp_path)
		push_error("[MCP Capture] Failed to publish response for request %s: %s" % [request_id, error_string(err)])


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _remove_if_present(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)
