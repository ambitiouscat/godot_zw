@tool
extends RefCounted

## Contract tests for the run-scoped GameAbility capture agent and the
## one-time cleanup of legacy project.godot Autoload entries.

const CaptureProtocol = preload("res://addons/godot_mcp/lifecycle/runtime_capture_protocol.gd")
const LegacyAutoloadMigration = preload("res://addons/godot_mcp/lifecycle/legacy_autoload_migration.gd")


static func run_all_tests() -> Dictionary:
	var errors: Array[String] = []
	var results: Dictionary = {"passed": 0, "failed": 0, "errors": errors}
	test_token_validation(results)
	test_response_correlation(results)
	test_legacy_autoload_ownership(results)
	return results


static func _assert(condition: bool, message: String, results: Dictionary) -> void:
	if condition:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(message)
		push_error("[RuntimeCaptureTest FAILED] " + message)


static func test_token_validation(results: Dictionary) -> void:
	_assert(CaptureProtocol.is_valid_token("real_0123456789abcdef"), "Runtime capture tokens must accept the lifecycle token alphabet", results)
	_assert(not CaptureProtocol.is_valid_token(""), "Runtime capture tokens must reject empty values", results)
	_assert(not CaptureProtocol.is_valid_token("bad/token"), "Runtime capture tokens must reject path separators", results)
	_assert(not CaptureProtocol.is_valid_token("bad token"), "Runtime capture tokens must reject whitespace", results)
	_assert(not CaptureProtocol.is_valid_token("."), "Runtime capture tokens must reject the current-directory segment", results)
	_assert(not CaptureProtocol.is_valid_token(".."), "Runtime capture tokens must reject the parent-directory segment", results)
	_assert(not CaptureProtocol.is_valid_token("x".repeat(161)), "Runtime capture tokens must enforce the 160-character limit", results)
	_assert(CaptureProtocol.session_dir("user://", "real_session") == "user://mcp_capture_sessions/real_session", "Capture artifacts must be isolated under the active session directory", results)
	_assert(CaptureProtocol.session_dir("user://", "../escape").is_empty(), "Invalid session IDs must not produce transport paths", results)
	_assert(CaptureProtocol.request_id_from_filename("mcp_capture_request_req_1234.json") == "req_1234", "Request filenames must round-trip a valid request ID", results)


static func test_response_correlation(results: Dictionary) -> void:
	var response := {
		"status": "ok",
		"request_id": "req_0123456789abcdef",
		"session_id": "real_session",
		"operation_id": "op_capture",
		"boot_nonce": "nonce_1234",
		"backend": CaptureProtocol.BACKEND,
		"requested_source": "game",
		"actual_source": "game_ability",
		# Exercise Godot's JSON-decoded numeric representation.
		"width": 1280.0,
		"height": 720.0,
		"format": "png",
		"byte_count": 1024.0,
		"sha256": "a".repeat(64),
		"capture_timestamp_ms": 1.0,
	}
	_assert(CaptureProtocol.validate_success_response(response, "real_session", "op_capture", "nonce_1234", "req_0123456789abcdef").is_empty(), "A fully correlated capture response must be accepted", results)
	var stale := response.duplicate()
	stale["boot_nonce"] = "nonce_stale"
	_assert(not CaptureProtocol.validate_success_response(stale, "real_session", "op_capture", "nonce_1234", "req_0123456789abcdef").is_empty(), "A response with a stale boot nonce must be rejected", results)
	var wrong_backend := response.duplicate()
	wrong_backend["backend"] = "editor_viewport"
	_assert(not CaptureProtocol.validate_success_response(wrong_backend, "real_session", "op_capture", "nonce_1234", "req_0123456789abcdef").is_empty(), "A cross-source capture backend must be rejected", results)


static func test_legacy_autoload_ownership(results: Dictionary) -> void:
	_assert(LegacyAutoloadMigration.is_owned_legacy_setting("autoload/MCPScreenshot", "*res://addons/godot_mcp/mcp_screenshot_service.gd"), "The exact legacy screenshot Autoload must be recognized", results)
	_assert(LegacyAutoloadMigration.is_owned_legacy_setting("autoload/MCPInputService", "res://addons/godot_mcp/mcp_input_service.gd"), "The exact legacy input Autoload must be recognized", results)
	_assert(not LegacyAutoloadMigration.is_owned_legacy_setting("autoload/MCPScreenshot", "res://scripts/my_screenshot.gd"), "A user-owned Autoload with the same name must not be removed", results)
	_assert(not LegacyAutoloadMigration.is_owned_legacy_setting("autoload/UserService", "res://addons/godot_mcp/mcp_screenshot_service.gd"), "An unrelated Autoload key must not be removed", results)
