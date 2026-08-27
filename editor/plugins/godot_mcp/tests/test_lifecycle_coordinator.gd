@tool
extends RefCounted

## Unit test suite for MCPLifecycleCoordinator state machine.

const MCPLifecycleCoordinator = preload("res://addons/godot_mcp/lifecycle/lifecycle_coordinator.gd")
const Schemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")

class MockBackend extends Object:
	var launched_scenes: Array[String] = []
	var stopped_sessions: Array[String] = []
	var last_session: String = ""
	var last_nonce: String = ""

	func launch_game(path: String, session_id: String, nonce: String) -> Error:
		launched_scenes.append(path)
		last_session = session_id
		last_nonce = nonce
		return OK

	func stop_game(session_id: String) -> void:
		stopped_sessions.append(session_id)

	func start_preview(path: String, session_id: String) -> Dictionary:
		launched_scenes.append(path)
		last_session = session_id
		return {"warnings": []}

	func stop_preview(session_id: String) -> void:
		stopped_sessions.append(session_id)


static func run_all_tests() -> Dictionary:
	var err_list: Array[String] = []
	var results: Dictionary = {
		"passed": 0,
		"failed": 0,
		"errors": err_list
	}

	test_real_run_lifecycle(results)
	test_preview_mode_rejected(results)
	test_operation_id_idempotency_and_collision(results)
	test_wrong_track_stop(results)
	test_stale_event_ignored(results)

	return results


static func _assert(condition: bool, message: String, results: Dictionary) -> void:
	if condition:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(message)
		push_error("[LifecycleTest FAILED] " + message)


static func test_real_run_lifecycle(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock

	# 1. Start real run
	var res := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "op_real_1")
	_assert(res.get("accepted") == true, "Real run start must be accepted", results)
	_assert(coord.current_state == Schemas.STATE_REAL_STARTING, "State must be REAL_STARTING", results)
	var sess_id: String = res.get("session_id", "")
	_assert(sess_id.begins_with("real_"), "Session ID must start with real_", results)

	# 2. Ingest REAL_READY
	coord.process_event({"type": "REAL_READY", "session_id": sess_id, "boot_nonce": coord.current_boot_nonce})
	_assert(coord.current_state == Schemas.STATE_REAL_RUNNING, "State must be REAL_RUNNING after REAL_READY", results)

	# 3. Stop real run
	var stop_res := coord.request_stop("real", sess_id, "op_stop_1")
	_assert(stop_res.get("accepted") == true, "Stop request must be accepted", results)
	_assert(coord.current_state == Schemas.STATE_REAL_STOPPING, "State must be REAL_STOPPING", results)

	# 4. Ingest REAL_EXIT
	coord.process_event({"type": "REAL_EXIT", "session_id": sess_id})
	_assert(coord.current_state == Schemas.STATE_IDLE, "State must be IDLE after REAL_EXIT", results)


static func test_preview_mode_rejected(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock

	# Requesting preview must fail because standalone GameAbility is the sole runtime
	var res := coord.request_start("preview", "res://preview.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "op_prev_1")
	_assert(res.has("error"), "Starting preview mode must be rejected", results)


static func test_operation_id_idempotency_and_collision(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock

	# First call
	var res1 := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "retry_key_123")
	_assert(res1.get("accepted") == true, "First call must succeed", results)

	# Exact retry with same operation_id and arguments
	var res2 := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "retry_key_123")
	_assert(res2.get("session_id") == res1.get("session_id"), "Retry with same op_id must return identical session_id", results)

	# Collision: same operation_id with different arguments
	var res3 := coord.request_start(Schemas.MODE_PREVIEW, "res://other.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "retry_key_123")
	_assert(res3.has("error"), "Reusing operation_id with different args must fail", results)
	_assert(res3.get("error", {}).get("symbol") == "INVALID_OPERATION_ID", "Error symbol must be INVALID_OPERATION_ID", results)


static func test_wrong_track_stop(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock

	var start_res := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn")
	var sess_id: String = start_res.get("session_id")
	coord.process_event({"type": "REAL_READY", "session_id": sess_id})

	# Call stop_simulation (track="preview") while real run is active
	var stop_res := coord.request_stop("preview")
	_assert(stop_res.has("error"), "Wrong track stop must return an error", results)
	_assert(stop_res.get("error", {}).get("symbol") == "STATE_CONFLICT", "Error symbol must be STATE_CONFLICT", results)
	_assert(coord.current_state == Schemas.STATE_REAL_RUNNING, "Real session must remain RUNNING", results)


static func test_stale_event_ignored(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock

	var start_res := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn")
	var real_sess: String = start_res.get("session_id")
	coord.process_event({"type": "REAL_READY", "session_id": real_sess})

	# Stale event with old session ID
	coord.process_event({"type": "REAL_EXIT", "session_id": "real_old_stale_12345"})
	_assert(coord.current_state == Schemas.STATE_REAL_RUNNING, "Current session must not be affected by stale exit event", results)
