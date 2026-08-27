@tool
extends Node

## Centralized, single-authority asynchronous lifecycle coordinator for Dual-Track Godot MCP.
## Manages state transitions, session correlation, mutual exclusion, preemption, and idempotency.

const Schemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")

signal state_changed(old_state: String, new_state: String, session_id: String)
signal session_started(session_id: String, mode: String, scene_path: String)
signal session_stopped(session_id: String, mode: String, outcome: String)
signal error_raised(symbol: String, message: String, details: Dictionary)

# -----------------------------------------------------------------------------
# Internal State
# -----------------------------------------------------------------------------
var current_state: String = Schemas.STATE_IDLE
var current_mode: String = Schemas.MODE_NONE
var desired_mode: String = Schemas.MODE_NONE

var current_session_id: String = ""
var pending_session_id: String = ""
var current_boot_nonce: String = ""
var current_target_scene: String = ""
var current_operation_id: String = ""

var is_preempting: bool = false
var transition_started_at_ms: int = 0
var last_session_info: Dictionary = {}
var unresolved_error: Variant = null

# Pluggable backend for real execution (allows unit test mocking)
var real_backend: Object = null

# Configuration
var start_handshake_timeout_ms: int = 15000
var stop_handshake_timeout_ms: int = 8000

# Bounded LRU-style caches for idempotency and deduplication
var _operation_cache: Dictionary = {} # op_id -> { "args_hash": String, "result": Dictionary, "time": int }
var _seen_events: Dictionary = {}     # event_id -> time_ms
const MAX_CACHE_SIZE := 100


func _init() -> void:
	current_state = Schemas.STATE_IDLE
	current_mode = Schemas.MODE_NONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()

	# Real Run state tracking via EditorInterface
	if current_mode == Schemas.MODE_REAL_RUN:
		var is_playing: bool = EditorInterface.is_playing_scene()
		if current_state == Schemas.STATE_REAL_STARTING and is_playing:
			_set_state(Schemas.STATE_REAL_RUNNING)
			transition_started_at_ms = 0
			session_started.emit(current_session_id, Schemas.MODE_REAL_RUN, current_target_scene)
		elif current_state == Schemas.STATE_REAL_RUNNING and not is_playing:
			_complete_session_termination("game_stopped")
		elif current_state == Schemas.STATE_REAL_STOPPING and not is_playing:
			transition_started_at_ms = 0
			_complete_session_termination("stop_requested")

	# Timeout reconciliation fallback
	if transition_started_at_ms > 0:
		var elapsed := now - transition_started_at_ms
		if current_state == Schemas.STATE_REAL_STARTING:
			if elapsed > start_handshake_timeout_ms:
				print("[LifecycleCoordinator] Start handshake timed out after %dms, auto-reconciling to IDLE" % elapsed)
				transition_started_at_ms = 0
				_complete_session_termination("START_TIMEOUT")
		elif current_state == Schemas.STATE_REAL_STOPPING:
			if elapsed > stop_handshake_timeout_ms:
				print("[LifecycleCoordinator] Stop handshake timed out after %dms, auto-reconciling to IDLE" % elapsed)
				transition_started_at_ms = 0
				_complete_session_termination("STOP_TIMEOUT")


# -----------------------------------------------------------------------------
# Public Lifecycle Command Endpoints
# -----------------------------------------------------------------------------

## Request starting a real run or preview session
func request_start(mode: String, scene_path: String, save_policy: String = Schemas.SAVE_POLICY_REQUIRE_CLEAN, conflict_policy: String = Schemas.CONFLICT_POLICY_REJECT, op_id: String = "") -> Dictionary:
	var now := Time.get_ticks_msec()
	
	# 1. Normalize parameters
	if mode != Schemas.MODE_REAL_RUN and mode != Schemas.MODE_PREVIEW:
		return _make_error(Schemas.ERR_CODE_INVALID_ARGUMENT, "Invalid mode: %s" % mode, "INVALID_ARGUMENT")
	
	if conflict_policy != Schemas.CONFLICT_POLICY_REJECT and conflict_policy != Schemas.CONFLICT_POLICY_PREEMPT:
		conflict_policy = Schemas.CONFLICT_POLICY_REJECT

	var norm_args := {
		"mode": mode,
		"scene_path": scene_path,
		"save_policy": save_policy,
		"conflict_policy": conflict_policy
	}
	var args_hash := _hash_dictionary(norm_args)

	# 2. Idempotency / Retry check
	if not op_id.is_empty() and _operation_cache.has(op_id):
		var cached: Dictionary = _operation_cache[op_id]
		if cached.get("args_hash") == args_hash:
			return cached.get("result", {})
		else:
			return _make_error(Schemas.ERR_CODE_INVALID_OPERATION_ID, "operation_id '%s' was previously used with different arguments" % op_id, "INVALID_OPERATION_ID")

	# 3. Check for RECONCILING state
	if current_state == Schemas.STATE_RECONCILING:
		return _make_error(Schemas.ERR_CODE_RECONCILIATION_REQUIRED, "System is currently reconciling runtime state; new starts are rejected", "RECONCILIATION_REQUIRED")

	# 4. Handle active or transitional state conflicts
	if current_state != Schemas.STATE_IDLE:
		var active_mode := current_mode
		
		# If same mode is already running or starting
		if active_mode == mode:
			if current_state == Schemas.STATE_REAL_RUNNING or current_state == Schemas.STATE_PREVIEW_RUNNING:
				if conflict_policy != Schemas.CONFLICT_POLICY_PREEMPT:
					return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "Session '%s' is already running in mode '%s'" % [current_session_id, mode], "STATE_CONFLICT")
			elif current_state == Schemas.STATE_REAL_STARTING or current_state == Schemas.STATE_PREVIEW_STARTING:
				return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "A session is already starting in mode '%s'" % mode, "STATE_CONFLICT")
			elif current_state == Schemas.STATE_REAL_STOPPING or current_state == Schemas.STATE_PREVIEW_STOPPING:
				return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "Current session is stopping; please wait for IDLE before starting", "STATE_CONFLICT")

		# If different mode is active (Cross-track conflict)
		if active_mode != mode and active_mode != Schemas.MODE_NONE:
			if conflict_policy == Schemas.CONFLICT_POLICY_REJECT:
				return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "Active session '%s' is running in '%s'. Explicit conflict_policy='preempt' is required to switch modes." % [current_session_id, active_mode], "STATE_CONFLICT")
			
			# Preemption authorized: initiate stop on source session before target start
			is_preempting = true
			desired_mode = mode
			pending_session_id = _generate_session_id(mode)
			
			var stop_res := _initiate_stop(active_mode, current_session_id, op_id)
			if stop_res.has("error"):
				is_preempting = false
				pending_session_id = ""
				return stop_res
			
			var preemption_result := {
				"accepted": true,
				"session_id": pending_session_id,
				"preempting_session_id": current_session_id,
				"operation_id": op_id,
				"state": current_state,
				"mode": mode,
				"target_scene": scene_path,
				"preflight_saved": false,
				"status": "preempting"
			}
			_store_operation_cache(op_id, args_hash, preemption_result)
			return preemption_result

	# 5. Handle preflight save policy
	var preflight_saved := false
	if save_policy == Schemas.SAVE_POLICY_REQUIRE_CLEAN:
		if _has_unsaved_scenes():
			return _make_error(Schemas.ERR_CODE_UNSAVED_CHANGES, "Active edited scene has unsaved changes and save_policy is 'require_clean'", "UNSAVED_CHANGES")
	elif save_policy == Schemas.SAVE_POLICY_SAVE:
		var save_err := _save_all_scenes()
		if save_err != OK:
			return _make_error(Schemas.ERR_CODE_INTERNAL, "Preflight save failed with error: %d" % save_err, "INTERNAL_ERROR")
		preflight_saved = true

	# 6. Generate Session ID and Transition to STARTING
	current_session_id = _generate_session_id(mode)
	current_boot_nonce = _generate_nonce()
	current_target_scene = scene_path
	current_operation_id = op_id
	current_mode = mode
	desired_mode = mode
	transition_started_at_ms = now
	unresolved_error = null

	_set_state(Schemas.STATE_REAL_STARTING)

	# 7. Dispatch to real GameAbility backend
	var warnings: Array[String] = []
	var backend_err: Error = OK
	if real_backend and real_backend.has_method("launch_game"):
		backend_err = real_backend.launch_game(scene_path, current_session_id, current_boot_nonce)
	else:
		backend_err = _default_real_launch(scene_path)

	if backend_err != OK:
		_set_state(Schemas.STATE_IDLE)
		current_mode = Schemas.MODE_NONE
		return _make_error(Schemas.ERR_CODE_INTERNAL, "Failed to launch GameAbility backend (error %d)" % backend_err, "INTERNAL_ERROR")

	var response := {
		"accepted": true,
		"session_id": current_session_id,
		"operation_id": op_id,
		"state": current_state,
		"mode": mode,
		"target_scene": current_target_scene,
		"preflight_saved": preflight_saved
	}
	if not warnings.is_empty():
		response["warnings"] = warnings

	_store_operation_cache(op_id, args_hash, response)
	return response


## Request stopping an active session
func request_stop(track: String, target_session_id: String = "", op_id: String = "") -> Dictionary:
	var now := Time.get_ticks_msec()
	var norm_args := {
		"track": track,
		"target_session_id": target_session_id
	}
	var args_hash := _hash_dictionary(norm_args)

	if not op_id.is_empty() and _operation_cache.has(op_id):
		var cached: Dictionary = _operation_cache[op_id]
		if cached.get("args_hash") == args_hash:
			return cached.get("result", {})
		else:
			return _make_error(Schemas.ERR_CODE_INVALID_OPERATION_ID, "operation_id '%s' was previously used with different arguments" % op_id, "INVALID_OPERATION_ID")

	# If already IDLE
	if current_state == Schemas.STATE_IDLE:
		var idle_resp := {
			"accepted": true,
			"session_id": target_session_id,
			"operation_id": op_id,
			"state": Schemas.STATE_IDLE,
			"mode": Schemas.MODE_NONE,
			"stop_requested": false,
			"already_stopped": true
		}
		_store_operation_cache(op_id, args_hash, idle_resp)
		return idle_resp

	# Validate track match
	var expected_mode := Schemas.MODE_REAL_RUN if track == "real" else Schemas.MODE_PREVIEW
	if current_mode != expected_mode:
		return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "Cannot stop track '%s': active session '%s' is in mode '%s'" % [track, current_session_id, current_mode], "STATE_CONFLICT")

	# Validate specific session_id if provided
	if not target_session_id.is_empty() and target_session_id != current_session_id:
		return _make_error(Schemas.ERR_CODE_STATE_CONFLICT, "Target session_id '%s' does not match active session '%s'" % [target_session_id, current_session_id], "STATE_CONFLICT")

	var stop_res := _initiate_stop(current_mode, current_session_id, op_id)
	_store_operation_cache(op_id, args_hash, stop_res)
	return stop_res


## Retrieve authoritative execution state, active sessions, target scene, and capabilities.
func get_execution_state() -> Dictionary:
	var phase := "idle"
	match current_state:
		Schemas.STATE_IDLE:
			phase = "idle"
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
		"desired_mode": desired_mode,
		"session_id": current_session_id,
		"pending_session_id": pending_session_id,
		"operation_id": current_operation_id,
		"target_scene": current_target_scene,
		"is_preempting": is_preempting,
		"transition_started_at_ms": transition_started_at_ms,
		"capabilities": {
			"real_run_supported": true,
			"preview_supported": false,
			"screenshot_backends": ["game_ability", "editor_viewport"],
			"supports_preemption": false
		},
		"last_session": last_session_info,
		"unresolved_error": unresolved_error
	}


# -----------------------------------------------------------------------------
# Event Ingestion (From OpenHarmony Bridge or In-Editor Runner)
# -----------------------------------------------------------------------------

func process_event(event: Dictionary) -> void:
	var event_id: String = str(event.get("event_id", ""))
	var event_type: String = str(event.get("type", ""))
	var sess_id: String = str(event.get("session_id", ""))
	var nonce: String = str(event.get("boot_nonce", ""))

	# Deduplicate events by event_id
	if not event_id.is_empty():
		if _seen_events.has(event_id):
			return
		_seen_events[event_id] = Time.get_ticks_msec()
		if _seen_events.size() > MAX_CACHE_SIZE:
			_prune_seen_events()

	# Validate session correlation: ignore events for stale sessions unless reconciling
	if current_state != Schemas.STATE_RECONCILING and not sess_id.is_empty() and sess_id != current_session_id:
		print("[LifecycleCoordinator] Stale event '%s' ignored for session '%s' (current is '%s')" % [event_type, sess_id, current_session_id])
		return

	match event_type:
		"REAL_READY":
			if current_state == Schemas.STATE_REAL_STARTING:
				_set_state(Schemas.STATE_REAL_RUNNING)
				session_started.emit(current_session_id, Schemas.MODE_REAL_RUN, current_target_scene)

		"REAL_STOP_ACK":
			# Real stop ACK received; remains in REAL_STOPPING until REAL_EXIT
			print("[LifecycleCoordinator] Received REAL_STOP_ACK for session %s" % sess_id)

		"REAL_EXIT":
			if current_state == Schemas.STATE_REAL_STOPPING or current_state == Schemas.STATE_REAL_RUNNING:
				_complete_session_termination("exit_ok")

		"CRASH", "ABRUPT_EXIT":
			unresolved_error = event.get("details", {"message": "Process terminated abruptly"})
			_complete_session_termination("crashed")


# -----------------------------------------------------------------------------
# Internal Lifecycle Actions
# -----------------------------------------------------------------------------

func _initiate_stop(mode: String, sess_id: String, op_id: String) -> Dictionary:
	current_operation_id = op_id
	transition_started_at_ms = Time.get_ticks_msec()

	_set_state(Schemas.STATE_REAL_STOPPING)
	if real_backend and real_backend.has_method("stop_game"):
		real_backend.stop_game(sess_id)
	else:
		_default_real_stop()

	return {
		"accepted": true,
		"session_id": sess_id,
		"operation_id": op_id,
		"state": current_state,
		"mode": mode,
		"stop_requested": true,
		"already_stopped": false
	}


func _complete_session_termination(outcome: String) -> void:
	last_session_info = {
		"session_id": current_session_id,
		"mode": current_mode,
		"target_scene": current_target_scene,
		"outcome": outcome,
		"terminated_at_ms": Time.get_ticks_msec()
	}
	session_stopped.emit(current_session_id, current_mode, outcome)

	var was_preempting := is_preempting
	var next_mode := desired_mode
	var next_session := pending_session_id

	# Reset state to IDLE
	_set_state(Schemas.STATE_IDLE)
	current_mode = Schemas.MODE_NONE
	current_session_id = ""
	current_boot_nonce = ""
	current_target_scene = ""
	is_preempting = false
	pending_session_id = ""

	# If preemption was pending, launch the target session now
	if was_preempting and next_mode != Schemas.MODE_NONE:
		print("[LifecycleCoordinator] Preemption complete: starting target mode '%s' (session '%s')" % [next_mode, next_session])
		request_start(next_mode, current_target_scene, Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, current_operation_id)


func _set_state(new_state: String) -> void:
	if current_state != new_state:
		var old_state := current_state
		current_state = new_state
		state_changed.emit(old_state, new_state, current_session_id)
		print("[LifecycleCoordinator] State transition: %s -> %s (session: %s)" % [old_state, new_state, current_session_id])


# -----------------------------------------------------------------------------
# Default Engine Fallbacks
# -----------------------------------------------------------------------------

func _default_real_launch(scene_path: String) -> Error:
	if scene_path.is_empty():
		EditorInterface.play_main_scene()
	else:
		EditorInterface.play_custom_scene(scene_path)
	return OK


func _default_real_stop() -> void:
	EditorInterface.stop_playing_scene()


func _has_unsaved_scenes() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return false
	var mgr := EditorInterface.get_editor_undo_redo()
	if mgr != null:
		var ur = mgr.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
		if ur != null and ur.has_undo():
			return true
	return false


func _save_all_scenes() -> Error:
	if EditorInterface.get_edited_scene_root() != null:
		return EditorInterface.save_scene()
	return OK


# -----------------------------------------------------------------------------
# Utilities: IDs, Nonces & Hashes
# -----------------------------------------------------------------------------

func _generate_session_id(mode: String) -> String:
	var prefix := "real" if mode == Schemas.MODE_REAL_RUN else "sim"
	var uuid_part := "%08x-%04x-%04x-%04x-%012x" % [
		randi(), randi() & 0xffff, (randi() & 0x0fff) | 0x4000,
		(randi() & 0x3fff) | 0x8000, randi() | (randi() << 32)
	]
	return "%s_%s" % [prefix, uuid_part]


func _generate_nonce() -> String:
	return "%08x%08x" % [randi(), randi()]


func _hash_dictionary(dict: Dictionary) -> String:
	var keys := dict.keys()
	keys.sort()
	var raw := ""
	for k in keys:
		raw += "%s:%s;" % [str(k), str(dict[k])]
	return raw.sha256_text()


func _store_operation_cache(op_id: String, args_hash: String, result: Dictionary) -> void:
	if op_id.is_empty():
		return
	_operation_cache[op_id] = {
		"args_hash": args_hash,
		"result": result,
		"time": Time.get_ticks_msec()
	}
	if _operation_cache.size() > MAX_CACHE_SIZE:
		_prune_operation_cache()


func _prune_operation_cache() -> void:
	var sorted_keys := _operation_cache.keys()
	for i in range(MAX_CACHE_SIZE / 2):
		_operation_cache.erase(sorted_keys[i])


func _prune_seen_events() -> void:
	var sorted_keys := _seen_events.keys()
	for i in range(MAX_CACHE_SIZE / 2):
		_seen_events.erase(sorted_keys[i])


func _make_error(code: int, message: String, symbol: String) -> Dictionary:
	error_raised.emit(symbol, message, {"code": code})
	return {
		"error": {
			"code": code,
			"message": message,
			"symbol": symbol
		}
	}
