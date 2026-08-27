@tool
class_name MCPCommandSchemas
extends RefCounted

## Machine-readable schemas, aliases, lifecycle statuses, and error definitions for Dual-Track Architecture.

# -----------------------------------------------------------------------------
# Lifecycle States & Phases
# -----------------------------------------------------------------------------
const STATE_IDLE := "IDLE"
const STATE_PREVIEW_STARTING := "PREVIEW_STARTING"
const STATE_PREVIEW_RUNNING := "PREVIEW_RUNNING"
const STATE_PREVIEW_STOPPING := "PREVIEW_STOPPING"
const STATE_REAL_STARTING := "REAL_STARTING"
const STATE_REAL_RUNNING := "REAL_RUNNING"
const STATE_REAL_STOPPING := "REAL_STOPPING"
const STATE_RECONCILING := "RECONCILING"

const STABLE_STATES: Array[String] = [
	STATE_IDLE,
	STATE_PREVIEW_RUNNING,
	STATE_REAL_RUNNING,
]

const TRANSITIONAL_STATES: Array[String] = [
	STATE_PREVIEW_STARTING,
	STATE_PREVIEW_STOPPING,
	STATE_REAL_STARTING,
	STATE_REAL_STOPPING,
	STATE_RECONCILING,
]

const MODE_NONE := "none"
const MODE_REAL_RUN := "real_run"
const MODE_PREVIEW := "preview"

const CONFLICT_POLICY_REJECT := "reject"
const CONFLICT_POLICY_PREEMPT := "preempt"

const SAVE_POLICY_REQUIRE_CLEAN := "require_clean"
const SAVE_POLICY_SAVE := "save"

const SOURCE_EDITOR := "editor"
const SOURCE_PREVIEW := "preview"
const SOURCE_GAME := "game"

const VALID_SOURCES: Array[String] = [
	SOURCE_EDITOR,
	SOURCE_GAME,
]

# -----------------------------------------------------------------------------
# Stable Error Codes & Symbolic Names
# -----------------------------------------------------------------------------
const ERR_CODE_STATE_CONFLICT := -32602
const ERR_CODE_UNSAVED_CHANGES := -32602
const ERR_CODE_INVALID_OPERATION_ID := -32602
const ERR_CODE_INVALID_ARGUMENT := -32602
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
	"CAPTURE_BACKEND_UNAVAILABLE": ERR_CODE_CAPTURE_BACKEND_UNAVAILABLE,
	"RUN_STATE_CONFLICT": ERR_CODE_RUN_STATE_CONFLICT,
	"SESSION_ENDED": ERR_CODE_SESSION_ENDED,
	"STALE_CAPTURE_RESPONSE": ERR_CODE_STALE_CAPTURE_RESPONSE,
	"RECONCILIATION_REQUIRED": ERR_CODE_RECONCILIATION_REQUIRED,
	"INTERNAL_ERROR": ERR_CODE_INTERNAL,
}

# -----------------------------------------------------------------------------
# Canonical Command Metadata & Parameter Specifications
# -----------------------------------------------------------------------------
static func get_canonical_commands() -> Dictionary:
	return {
		"run_project": {
			"track": "real",
			"description": "Start the configured main scene in standalone GameAbility process (authoritative execution).",
			"params": {
				"save_policy": {"type": "string", "enum": ["require_clean", "save"], "default": "require_clean"},
				"conflict_policy": {"type": "string", "enum": ["reject", "preempt"], "default": "reject"},
				"operation_id": {"type": "string", "default": ""},
				"preempt": {"type": "bool", "deprecated": true, "replacement": "conflict_policy"}
			},
			"returns": {
				"accepted": "bool",
				"session_id": "string",
				"operation_id": "string",
				"state": "string",
				"mode": "string",
				"target_scene": "string",
				"preflight_saved": "bool"
			}
		},
		"run_scene": {
			"track": "real",
			"description": "Start a specific scene in standalone GameAbility process.",
			"params": {
				"path": {"type": "string", "required": false},
				"scene_path": {"type": "string", "deprecated": true, "replacement": "path"},
				"scene": {"type": "string", "deprecated": true, "replacement": "path"},
				"save_policy": {"type": "string", "enum": ["require_clean", "save"], "default": "require_clean"},
				"conflict_policy": {"type": "string", "enum": ["reject", "preempt"], "default": "reject"},
				"operation_id": {"type": "string", "default": ""},
				"preempt": {"type": "bool", "deprecated": true, "replacement": "conflict_policy"}
			},
			"returns": {
				"accepted": "bool",
				"session_id": "string",
				"operation_id": "string",
				"state": "string",
				"mode": "string",
				"target_scene": "string",
				"preflight_saved": "bool"
			}
		},
		"run_current_scene": {
			"track": "real",
			"description": "Start the currently opened editor scene in standalone GameAbility process.",
			"params": {
				"save_policy": {"type": "string", "enum": ["require_clean", "save"], "default": "require_clean"},
				"conflict_policy": {"type": "string", "enum": ["reject", "preempt"], "default": "reject"},
				"operation_id": {"type": "string", "default": ""},
				"preempt": {"type": "bool", "deprecated": true, "replacement": "conflict_policy"}
			},
			"returns": {
				"accepted": "bool",
				"session_id": "string",
				"operation_id": "string",
				"state": "string",
				"mode": "string",
				"target_scene": "string",
				"preflight_saved": "bool"
			}
		},
		"stop_project": {
			"track": "real",
			"description": "Stop the active standalone GameAbility run session. Fails if only preview is running.",
			"params": {
				"session_id": {"type": "string", "default": ""},
				"operation_id": {"type": "string", "default": ""}
			},
			"returns": {
				"accepted": "bool",
				"session_id": "string",
				"operation_id": "string",
				"state": "string",
				"mode": "string",
				"stop_requested": "bool",
				"already_stopped": "bool"
			}
		},
		"get_execution_state": {
			"track": "read-only",
			"description": "Retrieve authoritative execution state, active session, target scene, and capabilities.",
			"params": {},
			"returns": {
				"state": "string",
				"phase": "string",
				"mode": "string",
				"desired_mode": "string",
				"session_id": "string",
				"pending_session_id": "string",
				"operation_id": "string",
				"target_scene": "string",
				"is_preempting": "bool",
				"transition_started_at_ms": "int",
				"capabilities": "dictionary",
				"last_session": "dictionary",
				"unresolved_error": "variant"
			}
		},
		"take_screenshot": {
			"track": "capture",
			"description": "Capture frame strictly from requested source ('editor', 'preview', 'game') with zero fallback.",
			"params": {
				"source": {"type": "string", "enum": ["editor", "preview", "game"], "default": "editor"},
				"viewport": {"type": "string", "deprecated": true, "replacement": "source"},
				"save_path": {"type": "string", "default": ""},
				"path": {"type": "string", "deprecated": true, "replacement": "save_path"},
				"operation_id": {"type": "string", "default": ""}
			},
			"returns": {
				"requested_source": "string",
				"actual_source": "string",
				"backend": "string",
				"session_id": "string",
				"request_id": "string",
				"path": "string",
				"global_path": "string",
				"width": "int",
				"height": "int",
				"format": "string",
				"sha256": "string",
				"capture_timestamp_ms": "int"
			}
		}
	}

# -----------------------------------------------------------------------------
# Compatibility Alias Map
# -----------------------------------------------------------------------------
static func get_alias_map() -> Dictionary:
	return {
		"run_main_scene": {"target": "run_project", "deprecated": false},
		"stop_playing_scene": {"target": "stop_project", "deprecated": false},
		"play_main_scene": {"target": "run_project", "deprecated": true, "replacement": "run_project"},
		"play_scene": {"target": "run_scene", "deprecated": true, "replacement": "run_scene"},
		"play_current_scene": {"target": "run_current_scene", "deprecated": true, "replacement": "run_current_scene"},
		"stop_scene": {"target": "stop_project", "deprecated": true, "replacement": "stop_project"},
		"is_simulation_running": {"target": "get_execution_state", "deprecated": true, "replacement": "get_execution_state"},
		"get_game_screenshot": {"target": "take_screenshot", "default_params": {"source": "game"}, "deprecated": true, "replacement": "take_screenshot(source=\"game\")"},
		"capture_game_screenshot": {"target": "take_screenshot", "default_params": {"source": "game"}, "deprecated": true, "replacement": "take_screenshot(source=\"game\")"},
		"get_editor_screenshot": {"target": "take_screenshot", "default_params": {"source": "editor"}, "deprecated": true, "replacement": "take_screenshot(source=\"editor\")"},
		"capture_screenshot": {"target": "take_screenshot", "default_params": {"source": "editor"}, "deprecated": true, "replacement": "take_screenshot(source=\"editor\")"},
		"get_screenshot": {"target": "take_screenshot", "default_params": {"source": "editor"}, "deprecated": true, "replacement": "take_screenshot(source=\"editor\")"}
	}
