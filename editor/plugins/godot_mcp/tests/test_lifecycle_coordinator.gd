@tool
extends RefCounted

## Unit tests for the single authoritative GameAbility lifecycle.

const MCPLifecycleCoordinator = preload("res://addons/godot_mcp/lifecycle/lifecycle_coordinator.gd")
const Schemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")


class MockBackend extends Object:
	var launched_scenes: Array[String] = []
	var stopped_sessions: Array[String] = []
	var last_session: String = ""
	var last_operation: String = ""
	var last_nonce: String = ""

	func launch_game(path: String, session_id: String, operation_id: String, nonce: String) -> Error:
		launched_scenes.append(path)
		last_session = session_id
		last_operation = operation_id
		last_nonce = nonce
		return OK

	func stop_game(session_id: String, operation_id: String, nonce: String) -> void:
		stopped_sessions.append(session_id)
		last_operation = operation_id
		last_nonce = nonce


static func run_all_tests() -> Dictionary:
	var errors: Array[String] = []
	var results: Dictionary = {"passed": 0, "failed": 0, "errors": errors}
	test_real_run_lifecycle_and_capture_context(results)
	test_preview_mode_rejected(results)
	test_operation_id_idempotency_and_collision(results)
	test_uncorrelated_events_rejected(results)
	test_duplicate_reordered_repeated_and_long_running(results)
	test_timeout_enters_reconciling(results)
	return results


static func _assert(condition: bool, message: String, results: Dictionary) -> void:
	if condition:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(message)
		push_error("[LifecycleTest FAILED] " + message)


static func _new_coordinator() -> MCPLifecycleCoordinator:
	var coordinator := MCPLifecycleCoordinator.new()
	coordinator.real_backend = MockBackend.new()
	return coordinator


static func _start(coordinator: MCPLifecycleCoordinator, operation_id: String = "") -> Dictionary:
	return coordinator.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, operation_id)


static func _event(coordinator: MCPLifecycleCoordinator, event_type: String, session_id: String, nonce: String, event_id: String) -> Dictionary:
	return {
		"type": event_type,
		"session_id": session_id,
		"operation_id": coordinator.current_operation_id,
		"boot_nonce": nonce,
		"event_id": event_id,
		"timestamp_ms": maxi(Time.get_ticks_msec(), 1),
		"source": "game_ability",
	}


static func test_real_run_lifecycle_and_capture_context(results: Dictionary) -> void:
	var coordinator := _new_coordinator()
	var start := _start(coordinator, "op_real_1")
	_assert(start.get("accepted") == true, "Real run start must be accepted", results)
	_assert(coordinator.current_state == Schemas.STATE_REAL_STARTING, "Start must enter REAL_STARTING", results)
	_assert(coordinator.get_active_capture_context().is_empty(), "Capture context must remain unavailable before READY", results)
	_assert(coordinator.get_execution_state().get("capabilities", {}).get("game_capture_ready") == false, "Capture backend must not claim readiness before REAL_READY", results)

	var session_id := str(start.get("session_id", ""))
	var nonce := coordinator.current_boot_nonce
	var mock := coordinator.real_backend as MockBackend
	_assert(session_id.begins_with("real_"), "Session ID must use real_ prefix", results)
	_assert(not coordinator.current_operation_id.is_empty() and mock.last_operation == coordinator.current_operation_id and mock.last_nonce == nonce, "Launch backend must receive authoritative operation and nonce", results)
	_assert(coordinator.process_event(_event(coordinator, "REAL_READY", session_id, nonce, "ready-1")), "Correlated REAL_READY must be accepted", results)
	_assert(coordinator.current_state == Schemas.STATE_REAL_RUNNING, "READY must enter REAL_RUNNING", results)
	var capture_context := coordinator.get_active_capture_context()
	_assert(capture_context.get("session_id") == session_id and capture_context.get("operation_id") == coordinator.current_operation_id and capture_context.get("boot_nonce") == nonce, "Capture context must expose active session, operation, and nonce", results)
	var capabilities: Dictionary = coordinator.get_execution_state().get("capabilities", {})
	_assert(capabilities.get("game_capture_ready") == true and capabilities.get("game_capture_backend") == "game_ability_root_viewport", "Correlated REAL_READY must expose the GameAbility root-viewport capture backend", results)

	var stop := coordinator.request_stop(session_id, "op_stop_1")
	_assert(stop.get("accepted") == true and stop.get("stop_requested") == true, "Stop request must be accepted", results)
	_assert(coordinator.current_state == Schemas.STATE_REAL_STOPPING, "Stop must enter REAL_STOPPING", results)
	_assert(mock.last_operation == start.get("operation_id") and mock.last_nonce == nonce, "Stop backend must retain launch operation and nonce", results)
	_assert(coordinator.process_event(_event(coordinator, "REAL_STOP_ACK", session_id, nonce, "stop-ack-1")), "Correlated REAL_STOP_ACK must complete an explicit stop", results)
	_assert(coordinator.current_state == Schemas.STATE_IDLE, "STOP_ACK must enter IDLE", results)
	_assert(coordinator.get_active_boot_nonce().is_empty(), "Nonce must not remain readable after STOP_ACK", results)


static func test_preview_mode_rejected(results: Dictionary) -> void:
	var coordinator := _new_coordinator()
	var result := coordinator.request_start("preview", "res://preview.tscn")
	_assert(result.get("error", {}).get("symbol") == "INVALID_ARGUMENT", "Preview mode must be rejected", results)
	_assert(coordinator.current_state == Schemas.STATE_IDLE, "Rejected preview must not change lifecycle state", results)


static func test_operation_id_idempotency_and_collision(results: Dictionary) -> void:
	var coordinator := _new_coordinator()
	var invalid := _start(coordinator, "invalid operation id")
	_assert(invalid.get("error", {}).get("symbol") == "INVALID_OPERATION_ID", "Operation IDs with unsupported characters must fail before launch", results)
	var first := _start(coordinator, "retry-key")
	var retry := _start(coordinator, "retry-key")
	_assert(retry.get("session_id") == first.get("session_id"), "Same operation ID and arguments must be idempotent", results)
	var collision := coordinator.request_start(Schemas.MODE_REAL_RUN, "res://other.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, "retry-key")
	_assert(collision.get("error", {}).get("symbol") == "INVALID_OPERATION_ID", "Operation ID reuse with different arguments must fail", results)


static func test_uncorrelated_events_rejected(results: Dictionary) -> void:
	var coordinator := _new_coordinator()
	_assert(not coordinator.process_event({}), "An empty lifecycle event must be rejected", results)
	var start := _start(coordinator)
	var session_id := str(start.get("session_id", ""))
	var nonce := coordinator.current_boot_nonce
	_assert(not str(start.get("operation_id", "")).is_empty() and start.get("operation_id") == coordinator.current_operation_id, "A missing client operation ID must be replaced with and return an authoritative operation ID", results)
	var missing_nonce := _event(coordinator, "REAL_READY", session_id, nonce, "missing-nonce")
	missing_nonce.erase("boot_nonce")
	_assert(not coordinator.process_event(missing_nonce), "READY without nonce must be rejected", results)
	var missing_session := _event(coordinator, "REAL_READY", session_id, nonce, "missing-session")
	missing_session.erase("session_id")
	_assert(not coordinator.process_event(missing_session), "READY without session must be rejected", results)
	var wrong_session := _event(coordinator, "REAL_READY", "real-stale", nonce, "wrong-session")
	_assert(not coordinator.process_event(wrong_session), "READY with wrong session must be rejected", results)
	var wrong_operation := _event(coordinator, "REAL_READY", session_id, nonce, "wrong-operation")
	wrong_operation["operation_id"] = "op-stale"
	_assert(not coordinator.process_event(wrong_operation), "READY with wrong operation must be rejected", results)
	var wrong_nonce := _event(coordinator, "REAL_READY", session_id, "wrong", "wrong-nonce")
	_assert(not coordinator.process_event(wrong_nonce), "READY with wrong nonce must be rejected", results)
	_assert(coordinator.current_state == Schemas.STATE_REAL_STARTING, "Rejected events must not transition state", results)
	_assert(coordinator.process_event(_event(coordinator, "REAL_READY", session_id, nonce, "ready-2")), "Matching READY must be accepted", results)
	var exit_missing_nonce := _event(coordinator, "REAL_EXIT", session_id, nonce, "exit-missing-nonce")
	exit_missing_nonce.erase("boot_nonce")
	_assert(not coordinator.process_event(exit_missing_nonce), "EXIT without nonce must be rejected", results)
	_assert(coordinator.current_state == Schemas.STATE_REAL_RUNNING, "Rejected EXIT must not stop active run", results)


static func test_duplicate_reordered_repeated_and_long_running(results: Dictionary) -> void:
	var coordinator := _new_coordinator()
	var start := _start(coordinator, "op_ordering")
	var session_id := str(start.get("session_id", ""))
	var nonce := coordinator.current_boot_nonce
	var repeated_start := coordinator.request_start(Schemas.MODE_REAL_RUN, "res://main.tscn", Schemas.SAVE_POLICY_REQUIRE_CLEAN, "op_second_start")
	_assert(repeated_start.get("error", {}).get("symbol") == "STATE_CONFLICT", "A distinct repeated start must fail while a run is starting", results)

	var early_stop_ack := _event(coordinator, "REAL_STOP_ACK", session_id, nonce, "early-stop-ack")
	_assert(not coordinator.process_event(early_stop_ack), "STOP_ACK before a stop request must be rejected", results)
	var ready := _event(coordinator, "REAL_READY", session_id, nonce, "ready-dedup")
	_assert(coordinator.process_event(ready), "First correlated READY must be accepted", results)
	_assert(not coordinator.process_event(ready), "Duplicate event_id must be rejected", results)

	# A confirmed running session has no duration timer. Advancing process time must
	# never clear or terminate it.
	coordinator.transition_started_at_ms = 0
	coordinator._process(3600.0)
	_assert(coordinator.current_state == Schemas.STATE_REAL_RUNNING, "Confirmed REAL_RUNNING must not have a duration limit", results)

	var first_stop := coordinator.request_stop(session_id, "op_stop_once")
	var repeated_stop := coordinator.request_stop(session_id, "op_stop_again")
	_assert(first_stop.get("stop_requested") == true, "First stop must invoke the backend", results)
	_assert(repeated_stop.get("accepted") == true and repeated_stop.get("stop_requested") == false, "Repeated stop must be idempotent and must not invoke the backend again", results)
	_assert((coordinator.real_backend as MockBackend).stopped_sessions.size() == 1, "Repeated stop must call the backend exactly once", results)

	var stop_ack := _event(coordinator, "REAL_STOP_ACK", session_id, nonce, "stop-ack")
	_assert(coordinator.process_event(stop_ack), "Correlated STOP_ACK must be accepted while stopping", results)
	_assert(coordinator.current_state == Schemas.STATE_IDLE, "Correlated STOP_ACK must complete the explicit stop", results)
	_assert(not coordinator.process_event(stop_ack), "Duplicate STOP_ACK must be rejected", results)


static func test_timeout_enters_reconciling(results: Dictionary) -> void:
	var coordinator := _new_coordinator()
	var start := _start(coordinator)
	var session_id := str(start.get("session_id", ""))
	var nonce := coordinator.current_boot_nonce
	coordinator.start_handshake_timeout_ms = 1
	coordinator.transition_started_at_ms = Time.get_ticks_msec() - 2
	coordinator._process(0.0)
	_assert(coordinator.current_state == Schemas.STATE_RECONCILING, "Start timeout must enter RECONCILING rather than IDLE", results)
	_assert(coordinator.get_execution_state().get("unresolved_error", {}).get("reason") == "START_TIMEOUT", "Reconciliation must retain timeout reason", results)
	_assert(coordinator.process_event(_event(coordinator, "REAL_READY", session_id, nonce, "ready-after-timeout")), "Correlated READY must resolve reconciliation", results)
	_assert(coordinator.current_state == Schemas.STATE_REAL_RUNNING, "READY must restore REAL_RUNNING from reconciliation", results)
	coordinator.request_stop(session_id, "op_timeout_stop")
	coordinator.stop_handshake_timeout_ms = 1
	coordinator.transition_started_at_ms = Time.get_ticks_msec() - 2
	coordinator._process(0.0)
	_assert(coordinator.current_state == Schemas.STATE_RECONCILING, "Stop timeout must enter RECONCILING rather than IDLE", results)
	_assert(coordinator.get_execution_state().get("unresolved_error", {}).get("reason") == "STOP_TIMEOUT", "Stop reconciliation must retain timeout reason", results)
	_assert(coordinator.process_event(_event(coordinator, "REAL_STOP_ACK", session_id, nonce, "stop-ack-after-timeout")), "Correlated STOP_ACK must resolve stop reconciliation", results)
	_assert(coordinator.current_state == Schemas.STATE_IDLE, "STOP_ACK must restore IDLE from stop reconciliation", results)
