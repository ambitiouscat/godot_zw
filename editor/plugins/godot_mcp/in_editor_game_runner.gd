@tool
extends Node

## InEditorGameRunner
## Manages in-editor isolated SubViewport scene simulations for Godot MCP on OpenHarmony.

signal simulation_started(scene_path: String)
signal simulation_stopped(scene_path: String)

var editor_plugin: EditorPlugin

var is_running: bool = false
var running_scene_path: String = ""
var overlay_root: Control = null
var sub_viewport: SubViewport = null
var sub_viewport_container: SubViewportContainer = null
var backdrop: ColorRect = null
var hud_panel: PanelContainer = null
var simulated_scene_root: Node = null

var _saved_edited_process_mode: int = Node.PROCESS_MODE_INHERIT
var _saved_edited_visible: bool = true

static var _instance: Node = null

static func get_instance() -> Node:
	return _instance


func _enter_tree() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	stop_simulation()
	if _instance == self:
		_instance = null


## Start in-editor simulation for a given scene or the project's main scene
func start_simulation(scene_path: String = "") -> Dictionary:
	if scene_path.is_empty():
		var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
		if not main_scene.is_empty():
			scene_path = main_scene
		elif editor_plugin and EditorInterface.get_edited_scene_root():
			scene_path = EditorInterface.get_edited_scene_root().scene_file_path

	if scene_path.is_empty():
		return {"error": {"code": -32602, "message": "No scene path specified and no main scene configured in project settings"}}

	if not ResourceLoader.exists(scene_path):
		return {"error": {"code": -32602, "message": "Scene file does not exist: %s" % scene_path}}

	# Stop previous simulation if active
	if is_running:
		stop_simulation()

	# 1. Suspend background 3D editor scene rendering and processing (0 GPU waste)
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root and is_instance_valid(edited_root):
		_saved_edited_process_mode = edited_root.process_mode
		_saved_edited_visible = edited_root.visible
		edited_root.process_mode = Node.PROCESS_MODE_DISABLED
		edited_root.visible = false

	# 2. Create root overlay Control
	overlay_root = Control.new()
	overlay_root.name = "InEditorGameOverlay"
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 3. Opaque dark backdrop to guarantee 0 background bleed-through
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.1, 0.1, 0.12, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(backdrop)

	# 4. Create isolated SubViewportContainer
	sub_viewport_container = SubViewportContainer.new()
	sub_viewport_container.name = "GameContainer"
	sub_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_viewport_container.stretch = true
	sub_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	sub_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_root.add_child(sub_viewport_container)

	# 5. Create SubViewport
	sub_viewport = SubViewport.new()
	sub_viewport.name = "InEditorGameViewport"
	
	var w: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var h: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	sub_viewport.size = Vector2i(w, h)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	sub_viewport.handle_input_locally = true
	sub_viewport.gui_disable_input = false
	sub_viewport.physics_object_picking = true
	sub_viewport.process_mode = Node.PROCESS_MODE_ALWAYS

	sub_viewport_container.add_child(sub_viewport)

	# 6. Instantiate the target scene inside SubViewport
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		stop_simulation()
		return {"error": {"code": -32603, "message": "Failed to load scene: %s" % scene_path}}

	simulated_scene_root = packed.instantiate()
	if simulated_scene_root == null:
		stop_simulation()
		return {"error": {"code": -32603, "message": "Failed to instantiate scene: %s" % scene_path}}

	sub_viewport.add_child(simulated_scene_root)

	# 7. Create floating in-viewport HUD control capsule
	_create_hud_capsule(scene_path)

	# 8. Mount overlay onto Editor BaseControl (top-level UI root)
	var base_ctrl: Control = EditorInterface.get_base_control()
	if base_ctrl != null:
		base_ctrl.add_child(overlay_root)
	else:
		var main_screen: Control = EditorInterface.get_editor_main_screen()
		if main_screen != null:
			main_screen.add_child(overlay_root)
		else:
			add_child(overlay_root)

	is_running = true
	running_scene_path = scene_path

	simulation_started.emit(scene_path)
	print("[InEditorGameRunner] Full-screen simulation started for: %s (size: %dx%d)" % [scene_path, w, h])

	return {
		"result": {
			"running": true,
			"scene": scene_path,
			"mode": "in_editor_viewport",
			"viewport_size": {"width": w, "height": h}
		}
	}


## Create in-viewport semi-transparent HUD capsule
func _create_hud_capsule(scene_path: String) -> void:
	hud_panel = PanelContainer.new()
	hud_panel.name = "SimulationHUD"
	
	hud_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_panel.anchor_left = 1.0
	hud_panel.anchor_right = 1.0
	hud_panel.anchor_top = 0.0
	hud_panel.anchor_bottom = 0.0
	hud_panel.offset_left = -260
	hud_panel.offset_top = 20
	hud_panel.offset_right = -20
	hud_panel.offset_bottom = 62
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	style.border_color = Color(0.3, 0.8, 0.4, 0.8)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	hud_panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hud_panel.add_child(hbox)

	var status_lbl := Label.new()
	var scene_name := scene_path.get_file()
	status_lbl.text = "🟢 %s" % scene_name
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.4))
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(status_lbl)

	var stop_btn := Button.new()
	stop_btn.text = "⏹ 退出"
	stop_btn.tooltip_text = "停止当前仿真并返回编辑器"
	stop_btn.focus_mode = Control.FOCUS_NONE
	stop_btn.pressed.connect(func(): stop_simulation())
	hbox.add_child(stop_btn)

	overlay_root.add_child(hud_panel)


## Stop the active simulation, restore background editor, and clean up nodes
func stop_simulation() -> Dictionary:
	if not is_running and overlay_root == null and sub_viewport == null:
		return {"result": {"stopped": true, "was_running": false}}

	var prev_scene: String = running_scene_path
	is_running = false
	running_scene_path = ""

	# 1. Restore background 3D editor scene visibility and processing
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root and is_instance_valid(edited_root):
		edited_root.process_mode = _saved_edited_process_mode
		edited_root.visible = _saved_edited_visible

	# 2. Free simulated game nodes and overlay container
	if simulated_scene_root and is_instance_valid(simulated_scene_root):
		simulated_scene_root.queue_free()
		simulated_scene_root = null

	if overlay_root and is_instance_valid(overlay_root):
		overlay_root.queue_free()
		overlay_root = null
		sub_viewport_container = null
		sub_viewport = null
		hud_panel = null
		backdrop = null

	simulation_stopped.emit(prev_scene)
	print("[InEditorGameRunner] Simulation stopped for: %s" % prev_scene)

	return {"result": {"stopped": true, "was_running": true, "scene": prev_scene}}


## Get the root node of the active simulated scene
func get_simulated_root() -> Node:
	if is_running and simulated_scene_root and is_instance_valid(simulated_scene_root):
		return simulated_scene_root
	return null


## Get the active SubViewport
func get_viewport() -> SubViewport:
	if is_running and sub_viewport and is_instance_valid(sub_viewport):
		return sub_viewport
	return null


## Forward an InputEvent to the simulated SubViewport
func forward_input_event(event: InputEvent) -> bool:
	if is_running and sub_viewport and is_instance_valid(sub_viewport):
		sub_viewport.push_input(event)
		return true
	return false


## Capture image frame directly from SubViewport
func capture_frame_image() -> Image:
	if is_running and sub_viewport and is_instance_valid(sub_viewport):
		var tex: ViewportTexture = sub_viewport.get_texture()
		if tex:
			return tex.get_image()
	return null
