@tool
extends Node

## GameAbility capture agent helper service.
## Monitors for screenshot requests and captures the game root viewport.

const REQUEST_PATH := "user://mcp_screenshot_request"
const RESPONSE_PATH := "user://mcp_screenshot_response.json"
const SCREENSHOT_PATH := "user://mcp_screenshot.png"
const SCREENSHOT_TMP_PATH := "user://mcp_screenshot_tmp.png"


func _ready() -> void:
	print("[MCPScreenshot] MCPScreenshot service ready in process! user_data_dir = ", OS.get_user_data_dir())
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta: float) -> void:
	if FileAccess.file_exists(REQUEST_PATH):
		print("[MCPScreenshot] Detected screenshot request at ", REQUEST_PATH)
		_handle_screenshot_request()


func _handle_screenshot_request() -> void:
	var req_data: Dictionary = {}
	if FileAccess.file_exists(REQUEST_PATH):
		var file := FileAccess.open(REQUEST_PATH, FileAccess.READ)
		if file != null:
			var txt := file.get_as_text()
			file.close()
			if not txt.is_empty():
				var parsed: Variant = JSON.parse_string(txt)
				if parsed is Dictionary:
					req_data = parsed
		DirAccess.remove_absolute(REQUEST_PATH)

	# Wait a tick for viewport render completion
	await get_tree().create_timer(0.05).timeout

	var image: Image = null
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var tex: ViewportTexture = viewport.get_texture()
		if tex != null:
			image = tex.get_image()

	if image == null:
		image = DisplayServer.screen_get_image()

	if image == null:
		print("[MCPScreenshot] Failed to get viewport/screen image in GameAbility")
		var err_dict := {
			"status": "error",
			"error": "Failed to get viewport image in GameAbility",
			"request_id": req_data.get("request_id", "")
		}
		var rf := FileAccess.open(RESPONSE_PATH, FileAccess.WRITE)
		if rf != null:
			rf.store_string(JSON.stringify(err_dict))
			rf.close()
		return

	var err: Error = image.save_png(SCREENSHOT_PATH)
	if err != OK:
		print("[MCPScreenshot] Failed to save screenshot to %s: %s" % [SCREENSHOT_PATH, error_string(err)])
		return

	var png_buffer: PackedByteArray = image.save_png_to_buffer()
	var ctx := HashingContext.new()
	var sha := ""
	if ctx.start(HashingContext.HASH_SHA256) == OK:
		ctx.update(png_buffer)
		sha = ctx.finish().hex_encode()

	var resp_dict: Dictionary = {
		"status": "ok",
		"request_id": req_data.get("request_id", ""),
		"session_id": req_data.get("session_id", ""),
		"boot_nonce": req_data.get("boot_nonce", ""),
		"width": image.get_width(),
		"height": image.get_height(),
		"format": "png",
		"sha256": sha,
		"timestamp_ms": Time.get_ticks_msec(),
		"backend": "game_ability_viewport"
	}

	var resp_file := FileAccess.open(RESPONSE_PATH, FileAccess.WRITE)
	if resp_file != null:
		resp_file.store_string(JSON.stringify(resp_dict))
		resp_file.close()
