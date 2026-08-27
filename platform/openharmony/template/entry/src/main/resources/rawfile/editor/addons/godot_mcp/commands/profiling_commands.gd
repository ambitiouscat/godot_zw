@tool
extends "res://addons/godot_mcp/commands/base_command.gd"


func get_commands() -> Dictionary:
	return {
		"get_performance_monitors": _get_performance_monitors,
		"get_editor_performance": _get_editor_performance,
	}


func _get_performance_monitors(_params: Dictionary) -> Dictionary:
	var envelope := get_authoritative_game_envelope()
	if envelope.has("error"):
		return envelope
	return error_conflict("Game performance monitors are unavailable until a scoped GameAbility profiling agent is attached.", {
		"symbol": "CAPABILITY_UNAVAILABLE",
		"capability": "game_ability_profiling",
		"session_id": str(envelope.get("session_id", "")),
	})


func _get_editor_performance(_params: Dictionary) -> Dictionary:
	return success({
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_msec": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0),
	})
