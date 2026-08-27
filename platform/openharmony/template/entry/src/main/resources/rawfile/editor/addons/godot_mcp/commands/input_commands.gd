@tool
extends "res://addons/godot_mcp/commands/base_command.gd"

## Runtime input injection must be implemented by a session-scoped
## GameAbility agent. The former shared, unacknowledged mailbox could report
## success even when no game service consumed the event. Keep the public
## methods discoverable but fail honestly.


func get_commands() -> Dictionary:
	return {
		"simulate_key": _input_capability_unavailable,
		"simulate_mouse_click": _input_capability_unavailable,
		"simulate_mouse_move": _input_capability_unavailable,
		"simulate_action": _input_capability_unavailable,
		"simulate_sequence": _input_capability_unavailable,
	}


func _input_capability_unavailable(params: Dictionary) -> Dictionary:
	var envelope := get_authoritative_game_envelope()
	if envelope.has("error"):
		return envelope
	return error_conflict("Runtime input injection is unavailable: no scoped GameAbility input agent is attached to this run.", {
		"symbol": "CAPABILITY_UNAVAILABLE",
		"capability": "game_ability_input",
		"session_id": str(envelope.get("session_id", "")),
		"requested_parameters": params.keys(),
	})
