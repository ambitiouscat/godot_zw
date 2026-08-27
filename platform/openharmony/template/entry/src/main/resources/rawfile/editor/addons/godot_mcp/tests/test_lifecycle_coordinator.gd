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
	var results: Dictionary = {
		"passed": 0,
		"failed": 0,
		"errors": []
	}

	test_real_run_lifecycle(results)
	test_preview_lifecycle(results)
	test_conflict_rejection(results)
	test_preemption_flow(results)
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

	_assert(coord.current_state == Schemas.STATE_IDLE, "Initial state must be IDLE", results)

	# 1. Start real run
	var res := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "op_start_1")
	_assert(res.get("accepted") == true, "Start request must be accepted", results)
	_assert(coord.current_state == Schemas.STATE_REAL_STARTING, "State must be REAL_STARTING", results)
	_assert(res.get("mode") == Schemas.MODE_REAL_RUN, "Mode must be real_run", results)
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


static func test_preview_lifecycle(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.preview_backend = mock

	var res := coord.request_start(Schemas.MODE_PREVIEW, "res://preview.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT, "op_prev_1")
	_assert(res.get("accepted") == true, "Preview start must be accepted", results)
	_assert(coord.current_state == Schemas.STATE_PREVIEW_STARTING, "State must be PREVIEW_STARTING", results)
	var sess_id: String = res.get("session_id", "")
	_assert(sess_id.begins_with("sim_"), "Session ID must start with sim_", results)

	coord.process_event({"type": "PREVIEW_READY", "session_id": sess_id})
	_assert(coord.current_state == Schemas.STATE_PREVIEW_RUNNING, "State must be PREVIEW_RUNNING", results)

	var stop_res := coord.request_stop("preview", sess_id, "op_prev_stop_1")
	_assert(stop_res.get("accepted") == true, "Preview stop must be accepted", results)
	_assert(coord.current_state == Schemas.STATE_PREVIEW_STOPPING, "State must be PREVIEW_STOPPING", results)

	coord.process_event({"type": "PREVIEW_STOP_ACK", "session_id": sess_id})
	_assert(coord.current_state == Schemas.STATE_IDLE, "State must return to IDLE", results)


static func test_conflict_rejection(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock
	coord.preview_backend = mock

	# Start real run
	var start_res := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn")
	var sess_id: String = start_res.get("session_id")
	coord.process_event({"type": "REAL_READY", "session_id": sess_id})

	# Attempt to start preview without preemption -> must fail
	var conf_res := coord.request_start(Schemas.MODE_PREVIEW, "res://other.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_REJECT)
	_assert(conf_res.has("error"), "Starting preview without preemption must return an error", results)
	_assert(conf_res.get("error", {}).get("symbol") == "STATE_CONFLICT", "Error symbol must be STATE_CONFLICT", results)
	_assert(coord.current_state == Schemas.STATE_REAL_RUNNING, "Real run must remain unaffected", results)


static func test_preemption_flow(results: Dictionary) -> void:
	var coord := MCPLifecycleCoordinator.new()
	var mock := MockBackend.new()
	coord.real_backend = mock
	coord.preview_backend = mock

	# Start real run
	var start_res := coord.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn")
	var real_sess: String = start_res.get("session_id")
	coord.process_event({"type": "REAL_READY", "session_id": real_sess})

	# Request preview with preempt
	var preempt_res := coord.request_start(Schemas.MODE_PREVIEW, "res://level.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, Schemas.CONFLICT_POLICY_PREEMPT, "op_preempt_1")
	_assert(preempt_res.get("accepted") == true, "Preemption request must be accepted", results)
	_assert(preempt_res.get("status") == "preempting", "Status must be preempting", results)
	_assert(coord.is_preempting == true, "Coordinator must be marked is_preempting", results)
	_assert(coord.current_state == Schemas.STATE_REAL_STOPPING, "Real session must transition to REAL_STOPPING", results)

	# Simulate REAL_EXIT from GameAbility
	coord.process_event({"type": "REAL_EXIT", "session_id": real_sess})
	# Upon REAL_EXIT, the coordinator must automatically start the target preview
	_assert(coord.current_state == Schemas.STATE_PREVIEW_STARTING, "Coordinator must advance to PREVIEW_STARTING after real exit", results)
	_assert(coord.current_session_id.begins_with("sim_"), "New session must be a preview session", results)


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
