@tool
extends RefCounted

## One-time cleanup for project.godot entries written by older MCP versions.
## Ownership is deliberately exact: a user Autoload is never removed merely
## because it shares a name or lives somewhere under addons/godot_mcp.

const LEGACY_AUTOLOADS: Dictionary = {
	"autoload/MCPScreenshot": "res://addons/godot_mcp/mcp_screenshot_service.gd",
	"autoload/MCPInputService": "res://addons/godot_mcp/mcp_input_service.gd",
	"autoload/MCPGameInspector": "res://addons/godot_mcp/mcp_game_inspector_service.gd",
}


static func is_owned_legacy_setting(key: String, value: Variant) -> bool:
	if not LEGACY_AUTOLOADS.has(key) or not value is String:
		return false
	var actual := _normalize_autoload_path(value as String)
	return actual == str(LEGACY_AUTOLOADS[key])


static func remove_owned_legacy_settings() -> Array[String]:
	var removed: Array[String] = []
	for key: String in LEGACY_AUTOLOADS:
		if not ProjectSettings.has_setting(key):
			continue
		if not is_owned_legacy_setting(key, ProjectSettings.get_setting(key)):
			continue
		ProjectSettings.set_setting(key, null)
		removed.append(key)
	return removed


static func _normalize_autoload_path(value: String) -> String:
	var path := value.strip_edges()
	if path.begins_with("*"):
		path = path.substr(1)
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		if uid != ResourceUID.INVALID_ID:
			var resolved := ResourceUID.get_id_path(uid)
			if not resolved.is_empty():
				path = resolved
	return path.simplify_path()
