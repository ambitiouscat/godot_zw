@tool
extends RefCounted

## Contract validation for the authoritative single-GameAbility command surface.

const MCPCommandSchemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")


static func run_all_tests() -> Dictionary:
	var err_list: Array[String] = []
	var results: Dictionary = {
		"passed": 0,
		"failed": 0,
		"errors": err_list
	}

	test_play_aliases_target_real_run(results)
	test_stop_commands_real_run(results)
	test_screenshot_source_enums(results)
	test_deprecated_alias_metadata(results)
	test_canonical_commands_completeness(results)
	test_preview_commands_are_absent(results)

	return results


static func _assert(condition: bool, message: String, results: Dictionary) -> void:
	if condition:
		results["passed"] += 1
	else:
		results["failed"] += 1
		results["errors"].append(message)
		push_error("[ContractTest FAILED] " + message)


static func test_play_aliases_target_real_run(results: Dictionary) -> void:
	var alias_map: Dictionary = MCPCommandSchemas.get_alias_map()
	
	# CONTRACT: play_* aliases MUST target real run (run_*)
	var play_aliases: Array[String] = ["play_main_scene", "play_scene", "play_current_scene"]
	for alias: String in play_aliases:
		_assert(alias_map.has(alias), "Alias map must contain %s" % alias, results)
		var target: String = str(alias_map.get(alias, {}).get("target", ""))
		_assert(target.begins_with("run_"), "Alias '%s' must target a real run command ('run_*'), got '%s'" % [alias, target], results)


static func test_stop_commands_real_run(results: Dictionary) -> void:
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	
	# CONTRACT: stop_project is strictly real run track
	_assert(canonical.has("stop_project"), "Canonical commands must contain stop_project", results)
	_assert(canonical["stop_project"]["track"] == "real", "stop_project track must be 'real'", results)

	# CONTRACT: stop_scene is an alias for stop_project
	var alias_map: Dictionary = MCPCommandSchemas.get_alias_map()
	_assert(alias_map.has("stop_scene"), "Alias map must contain stop_scene", results)
	_assert(alias_map["stop_scene"]["target"] == "stop_project", "stop_scene must target stop_project", results)


static func test_screenshot_source_enums(results: Dictionary) -> void:
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	_assert(canonical.has("take_screenshot"), "Canonical commands must contain take_screenshot", results)
	
	var src_enum: Array = canonical["take_screenshot"]["params"]["source"]["enum"]
	_assert(src_enum.has("editor"), "take_screenshot source enum must contain 'editor'", results)
	_assert(src_enum.has("game"), "take_screenshot source enum must contain 'game'", results)
	_assert(src_enum.size() == 2, "take_screenshot must only allow exactly ['editor', 'game']", results)


static func test_deprecated_alias_metadata(results: Dictionary) -> void:
	var alias_map: Dictionary = MCPCommandSchemas.get_alias_map()
	for alias: String in alias_map:
		var entry: Dictionary = alias_map[alias]
		if entry.get("deprecated", false):
			_assert(entry.has("replacement"), "Deprecated alias '%s' must specify a canonical replacement" % alias, results)


static func test_canonical_commands_completeness(results: Dictionary) -> void:
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	var required_commands: Array[String] = [
		"run_project", "run_scene", "run_current_scene", "stop_project",
		"get_execution_state", "take_screenshot"
	]
	for cmd: String in required_commands:
		_assert(canonical.has(cmd), "Required canonical command '%s' must be present in schemas" % cmd, results)
	for command_name: String in canonical:
		_assert(not command_name.begins_with("simulate_"), "Simulation command '%s' must not be canonical" % command_name, results)
		_assert(command_name != "stop_simulation", "stop_simulation must not be canonical", results)


static func test_preview_commands_are_absent(results: Dictionary) -> void:
	var aliases: Dictionary = MCPCommandSchemas.get_alias_map()
	for alias: String in aliases:
		_assert(not alias.contains("simulation"), "Simulation alias '%s' must be removed" % alias, results)
	_assert(not MCPCommandSchemas.VALID_SOURCES.has("preview"), "preview must not be an allowed capture source", results)
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	for command_name: String in ["run_project", "run_scene", "run_current_scene"]:
		var params: Dictionary = canonical[command_name]["params"]
		_assert(not params.has("conflict_policy") and not params.has("preempt"), "%s must not expose cross-track preemption" % command_name, results)
