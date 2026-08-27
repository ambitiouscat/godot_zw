@tool
extends Node

var editor_plugin: EditorPlugin


## Override in subclasses: return {"method_name": Callable}
func get_commands() -> Dictionary:
	return {}


## Helper: return a success result
func success(data: Dictionary = {}) -> Dictionary:
	return {"result": data}


## Helper: return an error
func error(code: int, message: String, data: Dictionary = {}) -> Dictionary:
	var err := {"code": code, "message": message}
	if not data.is_empty():
		err["data"] = data
	return {"error": err}


## Error codes
func error_not_found(what: String, suggestion: String = "") -> Dictionary:
	var data := {}
	if suggestion:
		data["suggestion"] = suggestion
	return error(-32001, "%s not found" % what, data)


func error_invalid_params(message: String) -> Dictionary:
	return error(-32602, message)


func error_no_scene() -> Dictionary:
	return error(-32000, "No scene is currently open", {"suggestion": "Use open_scene to open a scene first"})


func error_internal(message: String, data: Dictionary = {}) -> Dictionary:
	return error(-32603, "Internal error: %s" % message, data)


func error_conflict(message: String, data: Dictionary = {}) -> Dictionary:
	return error(-32009, message, data)


## Get required string param
func require_string(params: Dictionary, key: String) -> Array:
	if not params.has(key) or not params[key] is String or (params[key] as String).is_empty():
		return [null, error_invalid_params("Missing required parameter: %s" % key)]
	return [params[key] as String, null]


## Get optional string param with default
func optional_string(params: Dictionary, key: String, default: String = "") -> String:
	if params.has(key) and params[key] is String:
		return params[key] as String
	return default


## Get optional bool param with default
func optional_bool(params: Dictionary, key: String, default: bool = false) -> bool:
	if params.has(key) and params[key] is bool:
		return params[key] as bool
	return default


## Get optional int param with default.
##
## Only converts from types that have a meaningful integer value. int() raises
## on null, arrays and dictionaries — and a raise inside a command handler
## aborts the coroutine, so the caller gets no response at all and waits out
## its full timeout for what is really one bad parameter.
func optional_int(params: Dictionary, key: String, default: int = 0) -> int:
	if not params.has(key):
		return default
	var value: Variant = params[key]
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return default


## Get optional float param with default. Same reasoning as optional_int:
## float() raises on null, arrays and dictionaries, and a raise inside a
## handler means the caller never gets a response.
func optional_float(params: Dictionary, key: String, default: float = 0.0) -> float:
	if not params.has(key):
		return default
	var value: Variant = params[key]
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is bool:
		return 1.0 if value else 0.0
	if value is String and (value as String).is_valid_float():
		return (value as String).to_float()
	return default


## Validates that every entry of `params[key]` is a Dictionary.
##
## `for entry: Dictionary in some_array` raises on the first non-Dictionary
## element, which aborts the handler before it can answer. Returns {} when the
## array is usable, or an error dictionary naming the offending index.
func require_dictionary_array(params: Dictionary, key: String) -> Dictionary:
	if not params.has(key) or not params[key] is Array:
		return error_invalid_params("'%s' array is required" % key)
	var items: Array = params[key]
	for i in items.size():
		if not items[i] is Dictionary:
			return error_invalid_params(
				"'%s'[%d] must be an object, got %s" % [key, i, type_string(typeof(items[i]))]
			)
	return {}


## Get the game process's user data directory.
## OS.get_user_data_dir() is cached at editor startup and won't reflect
## project name changes made to project.godot while the editor is running.
## The game process reads the name from disk, so we must do the same.
func get_game_user_dir() -> String:
	var cached_dir := OS.get_user_data_dir()
	if OS.has_feature("openharmony") or OS.has_feature("mobile") or OS.has_feature("android"):
		return cached_dir

	var cfg := ConfigFile.new()
	var err := cfg.load(ProjectSettings.globalize_path("res://project.godot"))
	if err != OK:
		return cached_dir
	# When use_custom_user_dir=true, editor and game share the same dir
	# (OS.get_user_data_dir() already resolves to the custom path).
	if cfg.get_value("application", "config/use_custom_user_dir", false):
		return cached_dir
	var disk_name = cfg.get_value("application", "config/name", "")
	if typeof(disk_name) != TYPE_STRING or (disk_name as String).is_empty():
		return cached_dir
	# Sanitize exactly like Godot does when computing the default user dir
	# (core/config/project_settings.cpp ProjectSettings::_init).
	var sanitized := (disk_name as String).xml_unescape().validate_filename().replace(".", "_")
	if sanitized.is_empty():
		return cached_dir
	var base_dir := cached_dir.get_base_dir()
	var game_dir := base_dir.path_join(sanitized)
	# Ensure the directory exists (game may not have created it yet)
	if not DirAccess.dir_exists_absolute(game_dir):
		DirAccess.make_dir_recursive_absolute(game_dir)
	return game_dir


## Get EditorInterface
func get_editor() -> EditorInterface:
	return editor_plugin.get_editor_interface()


## Return the correlation envelope for the one authoritative game process.
##
## EditorInterface.is_playing_scene() is deliberately not used here. It only
## says that Godot's editor believes something is playing; it cannot identify
## a GameAbility instance or distinguish a stale process from the session that
## initiated the request. Runtime-facing commands must therefore gate on the
## lifecycle coordinator's REAL_RUNNING state and use its session nonce.
func get_authoritative_game_envelope() -> Dictionary:
	var coordinator: Node = get_tree().root.find_child("LifecycleCoordinator", true, false)
	if coordinator == null or not coordinator.has_method("get_execution_state") or not coordinator.has_method("get_active_capture_context"):
		return error_conflict("Authoritative GameAbility lifecycle service is unavailable.", {
			"symbol": "CAPABILITY_UNAVAILABLE",
			"capability": "authoritative_game_runtime",
		})

	var execution_state: Variant = coordinator.call("get_execution_state")
	if not execution_state is Dictionary:
		return error_internal("Lifecycle coordinator returned an invalid execution state.")
	var state: Dictionary = execution_state
	var lifecycle_state: String = str(state.get("state", ""))
	var mode: String = str(state.get("mode", ""))
	if lifecycle_state != "REAL_RUNNING" or mode != "real_run":
		return error_conflict("GameAbility is not in the authoritative REAL_RUNNING state.", {
			"symbol": "RUN_STATE_CONFLICT",
			"state": lifecycle_state,
			"mode": mode,
		})

	var capture_context: Variant = coordinator.call("get_active_capture_context")
	if not capture_context is Dictionary:
		return error_internal("Lifecycle coordinator returned an invalid capture context.")
	var context: Dictionary = capture_context
	var session_id: String = str(context.get("session_id", ""))
	var operation_id: String = str(context.get("operation_id", ""))
	var boot_nonce: String = str(context.get("boot_nonce", ""))
	if session_id.is_empty() or operation_id.is_empty() or boot_nonce.is_empty():
		return error_conflict("GameAbility session correlation data is incomplete.", {
			"symbol": "RUN_STATE_CONFLICT",
			"state": lifecycle_state,
			"session_id_present": not session_id.is_empty(),
			"operation_id_present": not operation_id.is_empty(),
			"boot_nonce_present": not boot_nonce.is_empty(),
		})

	return {
		"session_id": session_id,
		"operation_id": operation_id,
		"boot_nonce": boot_nonce,
		"state": lifecycle_state,
		"mode": mode,
	}


## Get the edited scene root
func get_edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


## Get UndoRedo
func get_undo_redo() -> EditorUndoRedoManager:
	return editor_plugin.get_undo_redo()


func normalize_project_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return path.simplify_path()
	return ProjectSettings.localize_path(path).simplify_path()


## Compares two project paths for the purpose of a protective guard.
##
## Windows and macOS have case-insensitive filesystems, so "res://Player.gd"
## and "res://player.gd" are the same file while comparing unequal. An exact
## match would let a differently-cased alias slip past the open-resource
## guards and overwrite the file the user has open. These guards are meant to
## refuse when in doubt, so the comparison is case-insensitive: at worst a
## write is refused that would have been safe, which the caller can override.
func paths_match(a: String, b: String) -> bool:
	return a.nocasecmp_to(b) == 0


## Refuses a write whose path does not carry one of the expected extensions.
##
## Without this, create_shader / create_theme / create_resource and friends
## will happily ResourceSaver.save over whatever the path points at — a
## mistyped destination silently destroys a script or an image, with no undo.
## `what` names the tool's own file kind for the message.
func guard_expected_extension(path: String, allowed: Array, what: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext in allowed:
		return {}
	var pretty: Array = []
	for e: String in allowed:
		pretty.append("." + e)
	return error_invalid_params(
		"'%s' does not look like %s (expected %s). Refusing to write, since this would overwrite whatever is at that path." % [
			path, what, ", ".join(pretty)
		]
	)


func is_scene_resource_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "tscn" or ext == "scn"


func get_open_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()
	for scene_path: String in open_scenes:
		var normalized := normalize_project_path(scene_path)
		if not normalized.is_empty() and normalized not in paths:
			paths.append(normalized)

	var root := get_edited_root()
	if root != null and not root.scene_file_path.is_empty():
		var active_path := normalize_project_path(root.scene_file_path)
		if active_path not in paths:
			paths.append(active_path)
	return paths


func is_scene_path_open(path: String) -> bool:
	var normalized := normalize_project_path(path)
	if normalized.is_empty():
		return false
	for open_path: String in get_open_scene_paths():
		if paths_match(open_path, normalized):
			return true
	return false


func is_active_scene_path(path: String) -> bool:
	var root := get_edited_root()
	if root == null:
		return false
	return paths_match(normalize_project_path(root.scene_file_path), normalize_project_path(path))


func guard_offline_scene_save(path: String) -> Dictionary:
	if is_scene_resource_path(path) and is_scene_path_open(path):
		return error_conflict(
			"Refusing to save open scene '%s' outside the Godot editor state" % normalize_project_path(path),
			{
				"path": normalize_project_path(path),
				"open_scenes": get_open_scene_paths(),
				"suggestion": "Use live editor changes plus save_scene, or close the scene before offline edits.",
			}
		)
	return {}


## Helper: create the parent directory of a res:// path if missing.
## Returns {} on success, an error dictionary on failure.
func ensure_parent_dir(path: String) -> Dictionary:
	var dir := path.get_base_dir()
	if dir.is_empty() or DirAccess.dir_exists_absolute(dir):
		return {}
	var derr := DirAccess.make_dir_recursive_absolute(dir)
	if derr != OK:
		return error_internal("Cannot create directory '%s': %s" % [dir, error_string(derr)])
	return {}


func is_shader_resource_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "gdshader" or ext == "gdshaderinc" or ext == "shader"


func is_text_resource_open_in_script_editor(path: String) -> bool:
	var target := normalize_project_path(path)
	if target.is_empty():
		return false
	if is_shader_resource_path(target) and ResourceLoader.has_cached(target):
		return true
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return false
	for open_resource in script_editor.get_open_scripts():
		if open_resource is Resource:
			var resource_path := normalize_project_path((open_resource as Resource).resource_path)
			if paths_match(resource_path, target):
				return true
	return false


func guard_text_resource_write(path: String, force: bool) -> Dictionary:
	if not force and is_text_resource_open_in_script_editor(path):
		return error_conflict(
			"Refusing to write open text resource '%s' outside the script editor state" % normalize_project_path(path),
			{
				"path": normalize_project_path(path),
				"suggestion": "Close the file in Godot's script editor or pass force=true to overwrite it deliberately.",
			}
		)
	return {}


func mark_current_scene_unsaved() -> void:
	if EditorInterface.has_method("mark_scene_as_unsaved"):
		EditorInterface.mark_scene_as_unsaved()


func add_child_with_undo(parent: Node, child: Node, root: Node, action_name: String) -> void:
	var undo_redo := get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(parent, "add_child", child)
	undo_redo.add_do_method(child, "set_owner", root)
	undo_redo.add_do_reference(child)
	undo_redo.add_undo_method(parent, "remove_child", child)
	undo_redo.commit_action()


func set_property_with_undo(target: Object, property: String, new_value: Variant, action_name: String) -> void:
	var old_value: Variant = target.get(property)
	var undo_redo := get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_property(target, property, new_value)
	if new_value is Resource:
		undo_redo.add_do_reference(new_value)
	undo_redo.add_undo_property(target, property, old_value)
	if old_value is Resource:
		undo_redo.add_undo_reference(old_value)
	undo_redo.commit_action()


## Find node by path in edited scene
func find_node_by_path(node_path: String) -> Node:
	var root := get_edited_root()
	if root == null:
		return null
	if node_path == "." or node_path == root.name:
		return root
	# Try relative from root
	if root.has_node(node_path):
		return root.get_node(node_path)
	# Try with root name prefix stripped
	if node_path.begins_with(root.name + "/"):
		var rel := node_path.substr(root.name.length() + 1)
		if root.has_node(rel):
			return root.get_node(rel)
	return null
