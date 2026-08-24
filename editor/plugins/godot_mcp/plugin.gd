@tool
extends EditorPlugin

const _MCP_AUTOLOADS: Array[Array] = [
	["autoload/MCPScreenshot", "res://addons/godot_mcp/mcp_screenshot_service.gd"],
	["autoload/MCPInputService", "res://addons/godot_mcp/mcp_input_service.gd"],
	["autoload/MCPGameInspector", "res://addons/godot_mcp/mcp_game_inspector_service.gd"],
]

const _MCP_TEMP_FILES: Array[String] = [
	"mcp_game_request",
	"mcp_game_response",
	"mcp_input_commands",
	"mcp_screenshot_request",
]

var websocket_server: Node
var command_router: Node
var status_panel: Control
var sim_button: Button = null
var _sim_runner: Node = null
var auto_dismiss_dialogs: bool = false
# Track which autoloads THIS session injected (vs project-owned)
var _session_injected_autoloads: Array[String] = []

func _enter_tree() -> void:
	_register_project_settings()

	# Create command router
	command_router = preload("res://addons/godot_mcp/command_router.gd").new()
	command_router.name = "MCPCommandRouter"
	command_router.editor_plugin = self
	add_child(command_router)

	# Register top toolbar simulation button
	sim_button = Button.new()
	sim_button.text = "▶ 视口仿真"
	sim_button.tooltip_text = "在当前 3D 视口内运行场景仿真"
	sim_button.focus_mode = Control.FOCUS_NONE
	sim_button.pressed.connect(_on_sim_button_pressed)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, sim_button)

	call_deferred("_setup_sim_runner")

	# Create WebSocket server
	websocket_server = preload("res://addons/godot_mcp/websocket_server.gd").new()
	websocket_server.name = "MCPWebSocketServer"
	websocket_server.command_router = command_router
	add_child(websocket_server)

	# Create status panel
	var panel_scene: PackedScene = preload("res://addons/godot_mcp/ui/status_panel.tscn")
	status_panel = panel_scene.instantiate()
	add_control_to_bottom_panel(status_panel, "MCP Pro")
	status_panel.call_deferred("setup", websocket_server, command_router)

	# Inject MCP autoloads into project settings
	_inject_autoloads()

	websocket_server.start_server()
	var cfg := ConfigFile.new()
	var ver := "unknown"
	if cfg.load("res://addons/godot_mcp/plugin.cfg") == OK:
		ver = cfg.get_value("plugin", "version", "unknown")
	print("[MCP] Godot MCP Pro v%s started (port 6510)" % ver)


func _setup_sim_runner() -> void:
	if is_instance_valid(command_router):
		_sim_runner = command_router.get_node_or_null("InEditorGameRunner")
	if _sim_runner:
		if not _sim_runner.simulation_started.is_connected(_on_sim_started):
			_sim_runner.simulation_started.connect(_on_sim_started)
		if not _sim_runner.simulation_stopped.is_connected(_on_sim_stopped):
			_sim_runner.simulation_stopped.connect(_on_sim_stopped)
		if _sim_runner.is_running:
			_on_sim_started(_sim_runner.running_scene_path)


func _exit_tree() -> void:
	# Remove MCP autoloads and clean up temp files
	_remove_autoloads()
	_cleanup_temp_files()

	if sim_button:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, sim_button)
		sim_button.queue_free()
		sim_button = null

	if websocket_server:
		websocket_server.stop_server()

	if status_panel:
		remove_control_from_bottom_panel(status_panel)
		status_panel.queue_free()

	if command_router:
		command_router.queue_free()

	if websocket_server:
		websocket_server.queue_free()

	print("[MCP] Godot MCP Pro stopped")


func _on_sim_button_pressed() -> void:
	if _sim_runner == null and is_instance_valid(command_router):
		_sim_runner = command_router.get_node_or_null("InEditorGameRunner")
	if _sim_runner:
		if not _sim_runner.simulation_started.is_connected(_on_sim_started):
			_sim_runner.simulation_started.connect(_on_sim_started)
		if not _sim_runner.simulation_stopped.is_connected(_on_sim_stopped):
			_sim_runner.simulation_stopped.connect(_on_sim_stopped)

		if _sim_runner.is_running:
			_sim_runner.stop_simulation()
		else:
			_sim_runner.start_simulation("")


func _on_sim_started(_scene: String) -> void:
	if sim_button and is_instance_valid(sim_button):
		sim_button.text = "⏹ 停止仿真"
		sim_button.tooltip_text = "点击停止当前仿真并返回 3D 编辑器"
		sim_button.modulate = Color(1.0, 0.4, 0.4)


func _on_sim_stopped(_scene: String) -> void:
	if sim_button and is_instance_valid(sim_button):
		sim_button.text = "▶ 视口仿真"
		sim_button.tooltip_text = "在当前 3D 视口内运行场景仿真"
		sim_button.modulate = Color.WHITE


## Declares the opt-in connection token setting so it is discoverable in
## Project Settings. Defaults to false, so nothing changes unless a user turns
## it on — see SECURITY.md for what it does and does not protect against.
func _register_project_settings() -> void:
	const KEY := "godot_mcp_pro/require_connection_token"
	if not ProjectSettings.has_setting(KEY):
		ProjectSettings.set_setting(KEY, false)
	ProjectSettings.set_initial_value(KEY, false)
	ProjectSettings.add_property_info({
		"name": KEY,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "Require MCP servers to present the token in user://mcp_auth_token before accepting commands.",
	})
	ProjectSettings.set_as_basic(KEY, true)


func _inject_autoloads() -> void:
	_session_injected_autoloads.clear()
	var changed := false
	for entry: Array in _MCP_AUTOLOADS:
		var key: String = entry[0]
		var script: String = entry[1]
		var wanted := "*" + script
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, wanted)
			_session_injected_autoloads.append(key)
			changed = true
			continue

		var existing := str(ProjectSettings.get_setting(key))
		if existing == wanted or existing == script:
			# Left behind by a previous session that crashed or was killed
			# before _exit_tree ran. Reclaim it, or it stays in project.godot
			# forever and logs "Can't autoload" once the addon is gone.
			_session_injected_autoloads.append(key)
		else:
			# A different script owns this name. Injecting would clobber the
			# project's own autoload, and not injecting leaves the matching
			# MCP service unavailable — so say which it is.
			push_warning(
				"[MCP] Autoload '%s' already points at '%s', not the MCP service. Leaving it alone; the features backed by %s will not work." % [
					key, existing, script.get_file()
				]
			)
	# Autoloads are registered in memory; do not write to project.godot on disk
	# if changed:
	# 	ProjectSettings.save()


func _remove_autoloads() -> void:
	# Only remove autoloads that THIS session injected or reclaimed.
	# Pre-existing project-owned autoloads are preserved.
	var changed := false
	var wanted_by_key := {}
	for entry: Array in _MCP_AUTOLOADS:
		wanted_by_key[entry[0]] = entry[1]

	for key: String in _session_injected_autoloads:
		if not ProjectSettings.has_setting(key):
			continue
		var script: String = wanted_by_key.get(key, "")
		var current := str(ProjectSettings.get_setting(key))
		# The user may have repointed it at their own script mid-session;
		# removing that would delete their work rather than ours.
		if current != "*" + script and current != script:
			continue
		ProjectSettings.set_setting(key, null)
		changed = true
	_session_injected_autoloads.clear()
	# if changed:
	# 	ProjectSettings.save()


var _dialog_check_timer: float = 0.0
const _DIALOG_CHECK_INTERVAL: float = 0.5  # Check every 0.5 seconds

func _process(delta: float) -> void:
	# Check if game inspector requested debugger continue
	var flag_path := OS.get_user_data_dir() + "/mcp_debugger_continue"
	if FileAccess.file_exists(flag_path):
		DirAccess.remove_absolute(flag_path)
		_try_debugger_continue()

	# Periodically check for blocking editor dialogs (only when enabled by AI)
	if auto_dismiss_dialogs:
		_dialog_check_timer += delta
		if _dialog_check_timer >= _DIALOG_CHECK_INTERVAL:
			_dialog_check_timer = 0.0
			_auto_dismiss_dialogs()


func _try_debugger_continue() -> void:
	# Last resort: find and press the debugger Continue button to unstick the game
	var base: Node = EditorInterface.get_base_control()
	var continue_btn := _find_debugger_continue_button(base)
	if continue_btn and continue_btn.visible and not continue_btn.disabled:
		continue_btn.emit_signal("pressed")
		push_warning("[MCP] Auto-pressed debugger Continue button")
	else:
		push_warning("[MCP] Could not find debugger Continue button")


func _find_debugger_continue_button(node: Node) -> Button:
	# Search for the Continue button in ScriptEditorDebugger.
	# The editor UI is translated, so matching tooltip/label text fails for
	# non-English editors (issue #34: Italian → "Continua"). Match by the editor
	# theme icon "DebugContinue" first, falling back to English text.
	var continue_icon: Texture2D = null
	var base: Control = EditorInterface.get_base_control()
	if base != null and base.has_theme_icon("DebugContinue", "EditorIcons"):
		continue_icon = base.get_theme_icon("DebugContinue", "EditorIcons")
	return _find_continue_button_recursive(node, continue_icon)


func _find_continue_button_recursive(node: Node, continue_icon: Texture2D) -> Button:
	if node is Button:
		var btn: Button = node
		if continue_icon != null and btn.icon == continue_icon:
			return btn
		if btn.tooltip_text.contains("Continue") or btn.text == "Continue":
			return btn
	for child in node.get_children():
		var found: Button = _find_continue_button_recursive(child, continue_icon)
		if found:
			return found
	return null


func _auto_dismiss_dialogs() -> void:
	var base: Node = EditorInterface.get_base_control()
	if not base:
		return
	_find_and_dismiss_dialogs(base)


func _find_and_dismiss_dialogs(node: Node) -> void:
	if node is AcceptDialog and node.visible:
		var dialog: AcceptDialog = node
		# Never dismiss file dialogs or non-modal popups
		if dialog is FileDialog:
			return
		if not dialog.exclusive:
			return
		# Get dialog title/text for logging
		var title := dialog.title
		var text := dialog.dialog_text
		# Accept the dialog (presses OK / confirms)
		dialog.get_ok_button().emit_signal("pressed")
		push_warning("[MCP] Auto-dismissed editor dialog: '%s' — %s" % [title, text])
		return  # One dialog per check cycle to avoid side effects

	for child in node.get_children():
		# Only search visible Windows to keep the scan lightweight
		if child is Window and not child.visible:
			continue
		_find_and_dismiss_dialogs(child)


func _cleanup_temp_files() -> void:
	var user_dir := OS.get_user_data_dir()
	for filename: String in _MCP_TEMP_FILES:
		var path := user_dir + "/" + filename
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# Also clean up screenshot image
	var screenshot_path := user_dir + "/mcp_screenshot.png"
	if FileAccess.file_exists(screenshot_path):
		DirAccess.remove_absolute(screenshot_path)
