@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

## Runtime test orchestration depends on correlated inspection, input, and
## capture agents inside GameAbility. Those agents are not present in this
## build, so the former shared-file implementation is removed and every
## runtime test command fails closed instead of fabricating sent/pass results.


func get_commands() -> Dictionary:
	return {
		"run_test_scenario": _runtime_test_capability_unavailable,
		"assert_node_state": _runtime_test_capability_unavailable,
		"assert_screen_text": _runtime_test_capability_unavailable,
		"run_stress_test": _runtime_test_capability_unavailable,
		"get_test_report": _get_test_report,
	}


func _runtime_test_capability_unavailable(params: Dictionary) -> Dictionary:
	var envelope := get_authoritative_game_envelope()
	if envelope.has("error"):
		return envelope
	return error_conflict("Runtime test automation is unavailable until scoped GameAbility inspection, input, and capture agents are attached.", {
		"symbol": "CAPABILITY_UNAVAILABLE",
		"capability": "game_ability_test_automation",
		"session_id": str(envelope.get("session_id", "")),
		"requested_parameters": params.keys(),
	})


func _get_test_report(_params: Dictionary) -> Dictionary:
	return success({
		"total": 0,
		"passed": 0,
		"failed": 0,
		"pass_rate": "N/A",
		"all_passed": false,
		"no_results": true,
		"details": [],
		"capability_available": false,
	})
