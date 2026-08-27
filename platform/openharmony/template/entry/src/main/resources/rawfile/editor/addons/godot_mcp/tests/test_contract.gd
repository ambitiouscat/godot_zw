@tool
extends RefCounted

## Contract validation test suite for Dual-Track MCP command definitions.
## Validates routing, alias contracts, track separation, and source integrity.

const MCPCommandSchemas = preload("res://addons/godot_mcp/lifecycle/command_schemas.gd")


static func run_all_tests() -> Dictionary:
	var results: Dictionary = {
		"passed": 0,
		"failed": 0,
		"errors": []
	}

	test_play_aliases_target_real_run(results)
	test_stop_commands_track_separation(results)
	test_screenshot_source_enums(results)
	test_deprecated_alias_metadata(results)
	test_canonical_commands_completeness(results)

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
	
	# CONTRACT: play_* aliases MUST target real run (run_*), NEVER preview (simulate_*)
	var play_aliases := ["play_main_scene", "play_scene", "play_current_scene"]
	for alias in play_aliases:
		_assert(alias_map.has(alias), "Alias map must contain %s" % alias, results)
		var target: String = str(alias_map.get(alias, {}).get("target", ""))
		_assert(target.begins_with("run_"), "Alias '%s' must target a real run command ('run_*'), got '%s'" % [alias, target], results)
		_assert(not target.begins_with("simulate_"), "Alias '%s' must NEVER target a simulation/preview command" % alias, results)


static func test_stop_commands_track_separation(results: Dictionary) -> void:
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	
	# CONTRACT: stop_project is strictly real run track
	_assert(canonical.has("stop_project"), "Canonical commands must contain stop_project", results)
	_assert(canonical["stop_project"]["track"] == "real", "stop_project track must be 'real'", results)

	# CONTRACT: stop_simulation is strictly preview track
	_assert(canonical.has("stop_simulation"), "Canonical commands must contain stop_simulation", results)
	_assert(canonical["stop_simulation"]["track"] == "preview", "stop_simulation track must be 'preview'", results)

	# CONTRACT: stop_scene is an alias for stop_project, NOT stop_simulation
	var alias_map: Dictionary = MCPCommandSchemas.get_alias_map()
	_assert(alias_map.has("stop_scene"), "Alias map must contain stop_scene", results)
	_assert(alias_map["stop_scene"]["target"] == "stop_project", "stop_scene must target stop_project", results)


static func test_screenshot_source_enums(results: Dictionary) -> void:
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	_assert(canonical.has("take_screenshot"), "Canonical commands must contain take_screenshot", results)
	
	var src_enum: Array = canonical["take_screenshot"]["params"]["source"]["enum"]
	_assert(src_enum.has("editor"), "take_screenshot source enum must contain 'editor'", results)
	_assert(src_enum.has("preview"), "take_screenshot source enum must contain 'preview'", results)
	_assert(src_enum.has("game"), "take_screenshot source enum must contain 'game'", results)
	_assert(src_enum.size() == 3, "take_screenshot must only allow exactly ['editor', 'preview', 'game']", results)


static func test_deprecated_alias_metadata(results: Dictionary) -> void:
	var alias_map: Dictionary = MCPCommandSchemas.get_alias_map()
	for alias in alias_map:
		var entry: Dictionary = alias_map[alias]
		if entry.get("deprecated", false):
			_assert(entry.has("replacement"), "Deprecated alias '%s' must specify a canonical replacement" % alias, results)


static func test_canonical_commands_completeness(results: Dictionary) -> void:
	var canonical: Dictionary = MCPCommandSchemas.get_canonical_commands()
	var required_commands := [
		"run_project", "run_scene", "run_current_scene", "stop_project",
		"simulate_project", "simulate_scene", "simulate_current_scene", "stop_simulation",
		"get_execution_state", "take_screenshot"
	]
	for cmd in required_commands:
		_assert(canonical.has(cmd), "Required canonical command '%s' must be present in schemas" % cmd, results)
