@tool
extends RefCounted

## Unit test suite for MCPCommandRouter dual-track routing and alias deprecation metadata.

const Schemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")


static func run_all_tests() -> Dictionary:
	var results: Dictionary = {
		"passed": 0,
		"failed": 0,
		"errors": []
	}

	test_alias_deprecation_contract(results)
	test_source_enum_validation(results)
	test_stable_error_codes(results)

	return results


static func _assert(condition: bool, message: String, results: Dictionary) -> void:
	if condition:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(message)
		push_error("[RouterTest FAILED] " + message)


static func test_alias_deprecation_contract(results: Dictionary) -> void:
	var alias_map: Dictionary = Schemas.get_alias_map()
	
	# play_scene MUST be deprecated and point to run_scene
	_assert(alias_map.has("play_scene"), "play_scene alias must exist", results)
	_assert(alias_map["play_scene"]["deprecated"] == true, "play_scene must be deprecated", results)
	_assert(alias_map["play_scene"]["replacement"] == "run_scene", "play_scene replacement must be run_scene", results)

	# stop_scene MUST be deprecated and point to stop_project
	_assert(alias_map.has("stop_scene"), "stop_scene alias must exist", results)
	_assert(alias_map["stop_scene"]["deprecated"] == true, "stop_scene must be deprecated", results)
	_assert(alias_map["stop_scene"]["replacement"] == "stop_project", "stop_scene replacement must be stop_project", results)

	# is_simulation_running MUST point to get_execution_state
	_assert(alias_map.has("is_simulation_running"), "is_simulation_running alias must exist", results)
	_assert(alias_map["is_simulation_running"]["replacement"] == "get_execution_state", "is_simulation_running replacement must be get_execution_state", results)


static func test_source_enum_validation(results: Dictionary) -> void:
	for src in Schemas.VALID_SOURCES:
		_assert(src == "editor" or src == "preview" or src == "game", "Valid source must be editor, preview, or game", results)


static func test_stable_error_codes(results: Dictionary) -> void:
	_assert(Schemas.ERR_CODE_STATE_CONFLICT == -32602, "ERR_CODE_STATE_CONFLICT must be -32602", results)
	_assert(Schemas.ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE == -32603, "ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE must be -32603", results)
	_assert(Schemas.ERR_CODE_RUN_STATE_CONFLICT == -32603, "ERR_CODE_RUN_STATE_CONFLICT must be -32603", results)
