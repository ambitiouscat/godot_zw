@tool
extends RefCounted

## Shared file protocol between the editor MCP command and the run-scoped
## GameAbility capture agent. Every artifact is request-specific so stale or
## concurrent replies cannot be mistaken for the active request.

const BACKEND := "game_ability_root_viewport"
const REQUEST_PREFIX := "mcp_capture_request_"
const RESPONSE_PREFIX := "mcp_capture_response_"
const IMAGE_PREFIX := "mcp_capture_image_"
const SESSION_DIRECTORY := "mcp_capture_sessions"
const JSON_SUFFIX := ".json"
const PNG_SUFFIX := ".png"
const TEMP_SUFFIX := ".tmp"
const MAX_TOKEN_LENGTH := 160


static func is_valid_token(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_TOKEN_LENGTH:
		return false
	# Tokens are also directory names. A slash-free token of "." or ".." still
	# has path traversal semantics and must never reach session_dir().
	if value == "." or value == "..":
		return false
	for index: int in value.length():
		var codepoint: int = value.unicode_at(index)
		var allowed := (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 65 and codepoint <= 90)
			or (codepoint >= 97 and codepoint <= 122)
			or codepoint == 46
			or codepoint == 58
			or codepoint == 95
			or codepoint == 45
		)
		if not allowed:
			return false
	return true


static func is_valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var codepoint: int = value.unicode_at(index)
		if not ((codepoint >= 48 and codepoint <= 57) or (codepoint >= 97 and codepoint <= 102)):
			return false
	return true


static func request_path(base_dir: String, request_id: String) -> String:
	return _join(base_dir, REQUEST_PREFIX + request_id + JSON_SUFFIX)


static func response_path(base_dir: String, request_id: String) -> String:
	return _join(base_dir, RESPONSE_PREFIX + request_id + JSON_SUFFIX)


static func image_path(base_dir: String, request_id: String) -> String:
	return _join(base_dir, IMAGE_PREFIX + request_id + PNG_SUFFIX)


static func session_dir(base_dir: String, session_id: String) -> String:
	if not is_valid_token(session_id):
		return ""
	return _join(_join(base_dir, SESSION_DIRECTORY), session_id)


static func request_id_from_filename(filename: String) -> String:
	if not filename.begins_with(REQUEST_PREFIX) or not filename.ends_with(JSON_SUFFIX):
		return ""
	var length := filename.length() - REQUEST_PREFIX.length() - JSON_SUFFIX.length()
	if length <= 0:
		return ""
	var request_id := filename.substr(REQUEST_PREFIX.length(), length)
	return request_id if is_valid_token(request_id) else ""


static func validate_success_response(response: Dictionary, expected_session_id: String, expected_operation_id: String, expected_boot_nonce: String, expected_request_id: String) -> String:
	if str(response.get("status", "")) != "ok":
		return "Capture response status is not 'ok'"
	var expected := {
		"session_id": expected_session_id,
		"operation_id": expected_operation_id,
		"boot_nonce": expected_boot_nonce,
		"request_id": expected_request_id,
	}
	for key: String in expected:
		if str(response.get(key, "")) != str(expected[key]):
			return "Capture response %s does not match the active request" % key
	if str(response.get("backend", "")) != BACKEND:
		return "Capture response backend is not the GameAbility root viewport"
	if str(response.get("requested_source", "")) != "game" or str(response.get("actual_source", "")) != "game_ability":
		return "Capture response source provenance is invalid"
	if str(response.get("format", "")) != "png":
		return "Capture response format is not PNG"
	var width: Variant = response.get("width", null)
	var height: Variant = response.get("height", null)
	if not (width is int or width is float) or not (height is int or height is float):
		return "Capture response dimensions are invalid"
	if int(width) <= 0 or int(height) <= 0:
		return "Capture response dimensions are invalid"
	var byte_count: Variant = response.get("byte_count", null)
	# JSON numbers are decoded as floats by Godot even when the producer wrote
	# an integer. Accept both numeric representations, then normalize with int().
	if not (byte_count is int or byte_count is float) or int(byte_count) <= 0:
		return "Capture response byte count is invalid"
	if not is_valid_sha256(str(response.get("sha256", ""))):
		return "Capture response SHA-256 is invalid"
	var timestamp: Variant = response.get("capture_timestamp_ms", null)
	if not (timestamp is int or timestamp is float) or int(timestamp) <= 0:
		return "Capture response timestamp is invalid"
	return ""


static func _join(base_dir: String, filename: String) -> String:
	return base_dir + ("" if base_dir.ends_with("/") else "/") + filename
