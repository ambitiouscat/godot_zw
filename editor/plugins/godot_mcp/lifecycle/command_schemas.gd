@tool
class_name MCPCommandSchemas
extends RefCounted

## Machine-readable schemas for the authoritative, single GameAbility runtime.

const STATE_IDLE := "IDLE"
const STATE_REAL_STARTING := "REAL_STARTING"
const STATE_REAL_RUNNING := "REAL_RUNNING"
const STATE_REAL_STOPPING := "REAL_STOPPING"
const STATE_RECONCILING := "RECONCILING"

const STABLE_STATES: Array[String] = [STATE_IDLE, STATE_REAL_RUNNING]
const TRANSITIONAL_STATES: Array[String] = [STATE_REAL_STARTING, STATE_REAL_STOPPING, STATE_RECONCILING]

const MODE_NONE := "none"
const MODE_REAL_RUN := "real_run"

const SAVE_POLICY_REQUIRE_CLEAN := "require_clean"
const SAVE_POLICY_SAVE := "save"

const SOURCE_EDITOR := "editor"
const SOURCE_GAME := "game"
const VALID_SOURCES: Array[String] = [SOURCE_EDITOR, SOURCE_GAME]

const ERR_CODE_STATE_CONFLICT := -32602
const ERR_CODE_UNSAVED_CHANGES := -32602
const ERR_CODE_INVALID_OPERATION_ID := -32602
const ERR_CODE_INVALID_ARGUMENT := -32602
const ERR_CODE_CAPABILITY_UNAVAILABLE := -32009
const ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE := -32603
const ERR_CODE_RUN_STATE_CONFLICT := -32603
const ERR_CODE_SESSION_ENDED := -32603
const ERR_CODE_STALE_CAPTURE_RESPONSE := -32603
const ERR_CODE_RECONCILIATION_REQUIRED := -32603
const ERR_CODE_INTERNAL := -32603

const ERROR_SYMBOLS: Dictionary = {
	"STATE_CONFLICT": ERR_CODE_STATE_CONFLICT,
	"UNSAVED_CHANGES": ERR_CODE_UNSAVED_CHANGES,
	"INVALID_OPERATION_ID": ERR_CODE_INVALID_OPERATION_ID,
	"INVALID_ARGUMENT": ERR_CODE_INVALID_ARGUMENT,
	"CAPABILITY_UNAVAILABLE": ERR_CODE_CAPABILITY_UNAVAILABLE,
	"CAPTURE_BACKEND_UNAVAILABLE": ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE,
	"RUN_STATE_CONFLICT": ERR_CODE_RUN_STATE_CONFLICT,
	"SESSION_ENDED": ERR_CODE_SESSION_ENDED,
	"STALE_CAPTURE_RESPONSE": ERR_CODE_STALE_CAPTURE_RESPONSE,
	"RECONCILIATION_REQUIRED": ERR_CODE_RECONCILIATION_REQUIRED,
	"INTERNAL_ERROR": ERR_CODE_INTERNAL,
}


static func get_canonical_commands() -> Dictionary:
	return {
		"run_project": _run_command("Start the configured main scene in standalone GameAbility."),
		"run_scene": _run_scene_command(),
		"run_current_scene": _run_command("Start the currently opened editor scene in standalone GameAbility."),
		"stop_project": {
			"track": "real",
			"description": "Stop the active standalone GameAbility session.",
			"params": {"session_id": {"type": "string", "default": ""}, "operation_id": {"type": "string", "default": ""}},
			"returns": {"accepted": "bool", "session_id": "string", "operation_id": "string", "state": "string", "mode": "string", "stop_requested": "bool", "already_stopped": "bool"},
		},
		"get_execution_state": {
			"track": "read-only",
			"description": "Retrieve authoritative GameAbility execution state and session context.",
			"params": {},
			"returns": {"state": "string", "phase": "string", "mode": "string", "session_id": "string", "operation_id": "string", "target_scene": "string", "transition_started_at_ms": "int", "capabilities": "dictionary", "last_session": "dictionary", "unresolved_error": "variant"},
		},
		"take_screenshot": {
			"track": "capture",
			"description": "Capture strictly from 'editor' or the authoritative 'game' source; no fallback.",
			"params": {
				"source": {"type": "string", "enum": [SOURCE_EDITOR, SOURCE_GAME], "default": SOURCE_EDITOR},
				"viewport": {"type": "string", "deprecated": true, "replacement": "source"},
				"save_path": {"type": "string", "default": ""},
				"path": {"type": "string", "deprecated": true, "replacement": "save_path"},
				"operation_id": {"type": "string", "default": ""},
			},
			"returns": {"requested_source": "string", "actual_source": "string", "backend": "string", "session_id": "string", "request_id": "string", "path": "string", "global_path": "string", "width": "int", "height": "int", "byte_count": "int", "format": "string", "sha256": "string", "capture_timestamp_ms": "int", "provenance": "dictionary"},
		},
	}


static func get_alias_map() -> Dictionary:
	return {
		"run_main_scene": {"target": "run_project", "deprecated": false},
		"stop_playing_scene": {"target": "stop_project", "deprecated": false},
		"play_main_scene": {"target": "run_project", "deprecated": true, "replacement": "run_project"},
		"play_scene": {"target": "run_scene", "deprecated": true, "replacement": "run_scene"},
		"play_current_scene": {"target": "run_current_scene", "deprecated": true, "replacement": "run_current_scene"},
		"stop_scene": {"target": "stop_project", "deprecated": true, "replacement": "stop_project"},
		"get_game_screenshot": {"target": "take_screenshot", "default_params": {"source": SOURCE_GAME}, "deprecated": true, "replacement": "take_screenshot(source=\"game\")"},
		"capture_game_screenshot": {"target": "take_screenshot", "default_params": {"source": SOURCE_GAME}, "deprecated": true, "replacement": "take_screenshot(source=\"game\")"},
		"get_editor_screenshot": {"target": "take_screenshot", "default_params": {"source": SOURCE_EDITOR}, "deprecated": true, "replacement": "take_screenshot(source=\"editor\")"},
		"capture_screenshot": {"target": "take_screenshot", "default_params": {"source": SOURCE_EDITOR}, "deprecated": true, "replacement": "take_screenshot(source=\"editor\")"},
		"get_screenshot": {"target": "take_screenshot", "default_params": {"source": SOURCE_EDITOR}, "deprecated": true, "replacement": "take_screenshot(source=\"editor\")"},
	}


static func _run_command(description: String) -> Dictionary:
	return {
		"track": "real",
		"description": description,
		"params": {"save_policy": {"type": "string", "enum": [SAVE_POLICY_REQUIRE_CLEAN, SAVE_POLICY_SAVE], "default": SAVE_POLICY_REQUIRE_CLEAN}, "operation_id": {"type": "string", "default": ""}},
		"returns": {"accepted": "bool", "session_id": "string", "operation_id": "string", "state": "string", "mode": "string", "target_scene": "string", "preflight_saved": "bool"},
	}


static func _run_scene_command() -> Dictionary:
	var command := _run_command("Start a specific scene in standalone GameAbility.")
	command["params"]["path"] = {"type": "string", "required": false}
	command["params"]["scene_path"] = {"type": "string", "deprecated": true, "replacement": "path"}
	command["params"]["scene"] = {"type": "string", "deprecated": true, "replacement": "path"}
	return command
