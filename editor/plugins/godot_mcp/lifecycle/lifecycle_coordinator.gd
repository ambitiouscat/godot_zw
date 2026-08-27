@tool
extends Node

## Event-driven lifecycle coordinator for the authoritative GameAbility runtime.
## EditorInterface can launch or stop a run, but only correlated GameAbility events
## are allowed to make the session RUNNING or IDLE.

const Schemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")

signal state_changed(old_state: String, new_state: String, session_id: String)
signal session_started(session_id: String, mode: String, scene_path: String)
signal session_stopped(session_id: String, mode: String, outcome: String)
signal error_raised(symbol: String, message: String, details: Dictionary)

var current_state: String = Schemas.STATE_IDLE
var current_mode: String = Schemas.MODE_NONE
var current_session_id: String = ""
var current_boot_nonce: String = ""
var current_target_scene: String = ""
var current_operation_id: String = ""
var transition_started_at_ms: int = 0
var last_session_info: Dictionary = {}
var unresolved_error: Variant = null
var _reconciliation_origin_state: String = ""

## Optional test/platform backend. It must expose launch_game(path, session,
## operation, nonce) and stop_game(session, operation, nonce).
var real_backend: Object = null

var start_handshake_timeout_ms: int = 15000
var stop_handshake_timeout_ms: int = 8000

var _operation_cache: Dictionary = {}
var _seen_events: Dictionary = {}
const MAX_CACHE_SIZE := 100


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	if transition_started_at_ms == 0:
		return
	var elapsed := Time.get_ticks_msec() - transition_started_at_ms
	if current_state == Schemas.STATE_REAL_STARTING and elapsed > start_handshake_timeout_ms:
		_enter_reconciling("START_TIMEOUT", "Timed out waiting for correlated REAL_READY")
	elif current_state == Schemas.STATE_REAL_STOPPING and elapsed > stop_handshake_timeout_ms:
		_enter_reconciling("STOP_TIMEOUT", "Timed out waiting for correlated REAL_STOP_ACK or REAL_EXIT")


## Start the sole supported runtime mode. No preview or cross-track preemption exists.
func request_start(mode: String, scene_path: String, save_policy: String = Schemas.SAVE_POLICY_REQUIRE_CLEAN, op_id: String = "") -> Dictionary:
	if mode != Schemas.MODE_REAL_RUN:
		return _make_error(Schemas.ERR_CODE_INVALID_ARGUMENT, "Only mode 'real_run' is supported", "INVALID_ARGUMENT")
	if not op_id.is_empty() and not _is_valid_correlation_token(op_id):
		return _make_error(Schemas.ERR_CODE_INVALID_OPERATION_ID, "operation_id contains unsupported characters or exceeds 160 characters", "INVALID_OPERATION_ID")

	var norm_args := {
		"mode": mode,
		"scene_path": scene_path,
		"save_policy": save_policy,
	}
	var args_hash := _hash_dictionary(norm_args)
	var cached_result := _get_cached_operation(op_id, args_hash)
	if not cached_result.is_empty():
		return cached_result
	if not op_id.is_empty() and _operation_cache.has(op_id):
		return _make_error(Schemas.ERR_CODE_INVALID_OPERATION_ID, "operation_id '%s' was previously used with different arguments" % op_id, "INVALID_OPERATION_ID")

	if current_state == Schemas.STATE_RECONCILING:
		return _make_error(Schemas.ERR_CODE_RECONCILIATION_REQUIRED, "Runtime state requires reconciliation before a new run can start", "RECONCILIATION_REQUIRED")
	if current_state != Schemas.STATE_IDLE:
		return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "GameAbility session '%s' is already active (%s)" % [current_session_id, current_state], "STATE_CONFLICT")

	var preflight_saved := false
	if save_policy == Schemas.SAVE_POLICY_REQUIRE_CLEAN:
		if _has_unsaved_scenes():
			return _make_error(Schemas.ERR_CODE_UNSAVED_CHANGES, "Active edited scene has unsaved changes and save_policy is 'require_clean'", "UNSAVED_CHANGES")
	elif save_policy == Schemas.SAVE_POLICY_SAVE:
		var save_err := _save_all_scenes()
		if save_err != OK:
			return _make_error(Schemas.ERR_CODE_INTERNAL, "Preflight save failed with error: %d" % save_err, "INTERNAL_ERROR")
		preflight_saved = true
	else:
		return _make_error(Schemas.ERR_CODE_INVALID_ARGUMENT, "Invalid save_policy '%s'" % save_policy, "INVALID_ARGUMENT")

	var next_session_id := _generate_session_id()
	var next_boot_nonce := _generate_nonce()
	var next_operation_id := op_id if not op_id.is_empty() else _generate_operation_id()
	if next_session_id.is_empty() or next_boot_nonce.is_empty() or next_operation_id.is_empty():
		return _make_error(Schemas.ERR_CODE_INTERNAL, "Failed to generate GameAbility correlation metadata", "INTERNAL_ERROR")
	current_session_id = next_session_id
	current_boot_nonce = next_boot_nonce
	current_target_scene = scene_path
	current_operation_id = next_operation_id
	current_mode = Schemas.MODE_REAL_RUN
	transition_started_at_ms = Time.get_ticks_msec()
	unresolved_error = null
	_set_state(Schemas.STATE_REAL_STARTING)

	var backend_err: Error = OK
	if real_backend != null and real_backend.has_method("launch_game"):
		backend_err = real_backend.launch_game(scene_path, current_session_id, current_operation_id, current_boot_nonce)
	else:
		backend_err = _default_real_launch(scene_path)
	if backend_err != OK:
		_record_and_reset("launch_failed")
		return _make_error(Schemas.ERR_CODE_INTERNAL, "Failed to launch GameAbility backend (error %d)" % backend_err, "INTERNAL_ERROR")

	var response := {
		"accepted": true,
		"session_id": current_session_id,
		"operation_id": current_operation_id,
		"state": current_state,
		"mode": Schemas.MODE_REAL_RUN,
		"target_scene": current_target_scene,
		"preflight_saved": preflight_saved,
	}
	_store_operation_cache(op_id, args_hash, response)
	return response


## Stop the active GameAbility session. Repeated stop requests are idempotent.
func request_stop(target_session_id: String = "", op_id: String = "") -> Dictionary:
	if not op_id.is_empty() and not _is_valid_correlation_token(op_id):
		return _make_error(Schemas.ERR_CODE_INVALID_OPERATION_ID, "operation_id contains unsupported characters or exceeds 160 characters", "INVALID_OPERATION_ID")
	var norm_args := {"target_session_id": target_session_id}
	var args_hash := _hash_dictionary(norm_args)
	var cached_result := _get_cached_operation(op_id, args_hash)
	if not cached_result.is_empty():
		return cached_result
	if not op_id.is_empty() and _operation_cache.has(op_id):
		return _make_error(Schemas.ERR_CODE_INVALID_OPERATION_ID, "operation_id '%s' was previously used with different arguments" % op_id, "INVALID_OPERATION_ID")

	if current_state == Schemas.STATE_IDLE:
		var idle_response := {
			"accepted": true,
			"session_id": target_session_id,
			"operation_id": op_id,
			"state": Schemas.STATE_IDLE,
			"mode": Schemas.MODE_NONE,
			"stop_requested": false,
			"already_stopped": true,
		}
		_store_operation_cache(op_id, args_hash, idle_response)
		return idle_response
	if not target_session_id.is_empty() and target_session_id != current_session_id:
		return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "Target session_id '%s' does not match active session '%s'" % [target_session_id, current_session_id], "STATE_CONFLICT")

	if current_state == Schemas.STATE_REAL_STOPPING:
		var stopping_response := _stop_response(op_id, false)
		_store_operation_cache(op_id, args_hash, stopping_response)
		return stopping_response

	transition_started_at_ms = Time.get_ticks_msec()
	_set_state(Schemas.STATE_REAL_STOPPING)
	if real_backend != null and real_backend.has_method("stop_game"):
		real_backend.stop_game(current_session_id, current_operation_id, current_boot_nonce)
	else:
		_default_real_stop()
	var response := _stop_response(op_id, true)
	_store_operation_cache(op_id, args_hash, response)
	return response


## Read-only nonce accessor for the screenshot bridge. It is empty until READY.
func get_active_boot_nonce() -> String:
	if current_state != Schemas.STATE_REAL_RUNNING:
		return ""
	return current_boot_nonce


## Read-only, authoritative screenshot correlation context. No fallback context exists.
func get_active_capture_context() -> Dictionary:
	if current_state != Schemas.STATE_REAL_RUNNING:
		return {}
	return {
		"mode": Schemas.MODE_REAL_RUN,
		"session_id": current_session_id,
		"operation_id": current_operation_id,
		"boot_nonce": current_boot_nonce,
		"target_scene": current_target_scene,
		"state": current_state,
	}


func get_execution_state() -> Dictionary:
	var phase := "idle"
	var capture_ready := current_state == Schemas.STATE_REAL_RUNNING
	match current_state:
		Schemas.STATE_REAL_STARTING:
			phase = "starting"
		Schemas.STATE_REAL_RUNNING:
			phase = "running"
		Schemas.STATE_REAL_STOPPING:
			phase = "stopping"
		Schemas.STATE_RECONCILING:
			phase = "reconciling"
	return {
		"state": current_state,
		"phase": phase,
		"mode": current_mode,
		"session_id": current_session_id,
		"operation_id": current_operation_id,
		"target_scene": current_target_scene,
		"transition_started_at_ms": transition_started_at_ms,
		"capabilities": {
			"real_run_supported": true,
			"preview_supported": false,
			"allowed_screenshot_sources": [Schemas.SOURCE_EDITOR, Schemas.SOURCE_GAME],
			"game_capture_ready": capture_ready,
			"game_capture_backend": "game_ability_root_viewport" if capture_ready else "unavailable",
			"supports_preemption": false,
		},
		"last_session": last_session_info,
		"unresolved_error": unresolved_error,
	}


## Ingest a GameAbility bridge event. A missing or mismatched session/nonce is rejected.
func process_event(event: Dictionary) -> bool:
	var event_type := str(event.get("type", ""))
	var session_id := str(event.get("session_id", ""))
	var operation_id := str(event.get("operation_id", ""))
	var boot_nonce := str(event.get("boot_nonce", ""))
	var event_id := str(event.get("event_id", ""))
	var timestamp_ms := int(event.get("timestamp_ms", 0))
	var source := str(event.get("source", ""))
	if event_type.is_empty() or session_id.is_empty() or operation_id.is_empty() or boot_nonce.is_empty() or event_id.is_empty() or timestamp_ms <= 0 or source != "game_ability":
		return false
	if session_id != current_session_id or operation_id != current_operation_id or boot_nonce != current_boot_nonce:
		return false

	if _seen_events.has(event_id):
		return false
	_seen_events[event_id] = Time.get_ticks_msec()
	if _seen_events.size() > MAX_CACHE_SIZE:
		_prune_seen_events()

	match event_type:
		"REAL_READY":
			if current_state != Schemas.STATE_REAL_STARTING and not (current_state == Schemas.STATE_RECONCILING and _reconciliation_origin_state == Schemas.STATE_REAL_STARTING):
				return false
			transition_started_at_ms = 0
			unresolved_error = null
			_set_state(Schemas.STATE_REAL_RUNNING)
			session_started.emit(current_session_id, Schemas.MODE_REAL_RUN, current_target_scene)
			return true
		"REAL_STOP_ACK":
			if current_state != Schemas.STATE_REAL_STOPPING and not (current_state == Schemas.STATE_RECONCILING and _reconciliation_origin_state == Schemas.STATE_REAL_STOPPING):
				return false
			# On OpenHarmony this correlated event is emitted only after the
			# GameAbility accepted the stop request and immediately before the OS
			# termination call. It is the authoritative explicit-stop terminal
			# signal; startAbilityForResult is retained only as an abrupt-exit
			# fallback because it does not reliably resolve across isolated
			# Ability processes on all device classes.
			_record_and_reset("stop_requested")
			return true
		"REAL_EXIT":
			if current_state == Schemas.STATE_IDLE:
				return false
			var outcome := "stop_requested" if current_state == Schemas.STATE_REAL_STOPPING else "exit_ok"
			_record_and_reset(outcome)
			return true
		"CRASH", "ABRUPT_EXIT":
			unresolved_error = event.get("details", {"message": "GameAbility terminated abruptly"})
			_record_and_reset("crashed")
			return true
	return false


func _enter_reconciling(reason: String, message: String) -> void:
	_reconciliation_origin_state = current_state
	transition_started_at_ms = 0
	unresolved_error = {"reason": reason, "message": message, "session_id": current_session_id}
	_set_state(Schemas.STATE_RECONCILING)


func _stop_response(op_id: String, stop_requested: bool) -> Dictionary:
	return {
		"accepted": true,
		"session_id": current_session_id,
		"operation_id": op_id,
		"state": current_state,
		"mode": Schemas.MODE_REAL_RUN,
		"stop_requested": stop_requested,
		"already_stopped": false,
	}


func _record_and_reset(outcome: String) -> void:
	last_session_info = {
		"session_id": current_session_id,
		"mode": current_mode,
		"target_scene": current_target_scene,
		"outcome": outcome,
		"terminated_at_ms": Time.get_ticks_msec(),
	}
	if not current_session_id.is_empty():
		session_stopped.emit(current_session_id, current_mode, outcome)
	_set_state(Schemas.STATE_IDLE)
	current_mode = Schemas.MODE_NONE
	current_session_id = ""
	current_boot_nonce = ""
	current_target_scene = ""
	current_operation_id = ""
	transition_started_at_ms = 0
	_reconciliation_origin_state = ""


func _set_state(new_state: String) -> void:
	if current_state == new_state:
		return
	var old_state := current_state
	current_state = new_state
	state_changed.emit(old_state, new_state, current_session_id)


func _default_real_launch(scene_path: String) -> Error:
	OS.set_environment("GODOT_MCP_REAL_SESSION_ID", current_session_id)
	OS.set_environment("GODOT_MCP_REAL_OPERATION_ID", current_operation_id)
	OS.set_environment("GODOT_MCP_REAL_BOOT_NONCE", current_boot_nonce)
	# Starting an OpenHarmony Ability can background the editor immediately.
	# Defer it by one idle turn so the MCP server can publish the accepted
	# JSON-RPC response before the platform performs the window/process switch.
	_deferred_real_launch.call_deferred(scene_path)
	return OK


func _deferred_real_launch(scene_path: String) -> void:
	if scene_path.is_empty():
		EditorInterface.play_main_scene()
	else:
		EditorInterface.play_custom_scene(scene_path)


func _default_real_stop() -> void:
	EditorInterface.stop_playing_scene()


func _has_unsaved_scenes() -> bool:
	# Undo history remains available after a save, so UndoRedo.has_undo() is not
	# an unsaved-state test. EditorInterface already exposes the editor's exact
	# per-scene dirty tracking used by the scene tabs and run preflight.
	return not EditorInterface.get_unsaved_scenes().is_empty()


func _save_all_scenes() -> Error:
	if EditorInterface.get_edited_scene_root() != null:
		return EditorInterface.save_scene()
	return OK


func _generate_session_id() -> String:
	return "real_%s" % _generate_secure_token()


func _generate_nonce() -> String:
	return _generate_secure_token()


func _generate_operation_id() -> String:
	return "op_%s" % _generate_secure_token()


func _generate_secure_token() -> String:
	# Session correlation is a trust boundary: values exposed in the start
	# response must not make the following boot nonce predictable.
	var crypto: Crypto = Crypto.new()
	var random_bytes: PackedByteArray = crypto.generate_random_bytes(16)
	if random_bytes.size() != 16:
		push_error("Failed to generate a 128-bit GameAbility correlation token")
		return ""
	return random_bytes.hex_encode()


func _is_valid_correlation_token(value: String) -> bool:
	if value.is_empty() or value.length() > 160:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_ascii_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and code != 46 and code != 95 and code != 58 and code != 45:
			return false
	return true


func _hash_dictionary(values: Dictionary) -> String:
	var keys := values.keys()
	keys.sort()
	var raw := ""
	for key: Variant in keys:
		raw += "%s:%s;" % [str(key), str(values[key])]
	return raw.sha256_text()


func _get_cached_operation(op_id: String, args_hash: String) -> Dictionary:
	if op_id.is_empty() or not _operation_cache.has(op_id):
		return {}
	var cached: Dictionary = _operation_cache[op_id]
	if cached.get("args_hash", "") == args_hash:
		return cached.get("result", {})
	return {}


func _store_operation_cache(op_id: String, args_hash: String, result: Dictionary) -> void:
	if op_id.is_empty():
		return
	_operation_cache[op_id] = {"args_hash": args_hash, "result": result, "time": Time.get_ticks_msec()}
	if _operation_cache.size() > MAX_CACHE_SIZE:
		_prune_oldest_operations()


func _prune_seen_events() -> void:
	var keys := _seen_events.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(_seen_events[a]) < int(_seen_events[b]))
	for index in range(MAX_CACHE_SIZE / 2):
		_seen_events.erase(keys[index])


func _prune_oldest_operations() -> void:
	var keys := _operation_cache.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(_operation_cache[a].get("time", 0)) < int(_operation_cache[b].get("time", 0)))
	for index in range(MAX_CACHE_SIZE / 2):
		_operation_cache.erase(keys[index])


func _make_error(code: int, message: String, symbol: String) -> Dictionary:
	error_raised.emit(symbol, message, {"code": code})
	return {"error": {"code": code, "message": message, "symbol": symbol}}
