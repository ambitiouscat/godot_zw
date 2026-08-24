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
var ticker: InEditorSimulationTicker = null

var _saved_edited_process_mode: int = Node.PROCESS_MODE_INHERIT
var _saved_edited_visible: bool = true
var _saved_low_processor_mode: bool = true

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

	# 1. Unlock continuous 60 FPS main loop for smooth gameplay
	_saved_low_processor_mode = OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false

	# 2. Suspend background 3D editor scene rendering and processing (0 GPU waste)
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root and is_instance_valid(edited_root):
		_saved_edited_process_mode = edited_root.process_mode
		_saved_edited_visible = edited_root.visible
		edited_root.process_mode = Node.PROCESS_MODE_DISABLED
		edited_root.visible = false

	# 3. Create root overlay Control precisely covering the 3D MainScreen area
	overlay_root = Control.new()
	overlay_root.name = "InEditorGameOverlay"
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP

	# 4. Opaque dark backdrop to guarantee 0 background grid/gizmo bleed-through
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.1, 0.1, 0.12, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(backdrop)

	# 5. Create isolated SubViewportContainer filling the 3D viewport area
	sub_viewport_container = SubViewportContainer.new()
	sub_viewport_container.name = "GameContainer"
	sub_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub_viewport_container.stretch = true
	sub_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.add_child(sub_viewport_container)

	# 6. Create SubViewport
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

	# 7. Instantiate the target scene inside SubViewport
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		stop_simulation()
		return {"error": {"code": -32603, "message": "Failed to load scene: %s" % scene_path}}

	simulated_scene_root = packed.instantiate()
	if simulated_scene_root == null:
		stop_simulation()
		return {"error": {"code": -32603, "message": "Failed to instantiate scene: %s" % scene_path}}

	sub_viewport.add_child(simulated_scene_root)

	# 8. Attach Simulation Ticker to drive _process and _physics_process on all non-@tool game scripts
	ticker = InEditorSimulationTicker.new()
	ticker.name = "SimulationTicker"
	ticker.target_root = simulated_scene_root
	sub_viewport.add_child(ticker)

	# 9. Create floating in-viewport HUD control capsule
	_create_hud_capsule(scene_path)

	# 10. Align overlay position & size precisely to 3D MainScreen area
	var main_screen: Control = EditorInterface.get_editor_main_screen()
	if main_screen != null:
		_update_overlay_rect()
		if not main_screen.resized.is_connected(_update_overlay_rect):
			main_screen.resized.connect(_update_overlay_rect)
		if not main_screen.item_rect_changed.is_connected(_update_overlay_rect):
			main_screen.item_rect_changed.connect(_update_overlay_rect)

	# Mount overlay onto Editor BaseControl
	var base_ctrl: Control = EditorInterface.get_base_control()
	if base_ctrl != null:
		base_ctrl.add_child(overlay_root)
	elif main_screen != null:
		main_screen.add_child(overlay_root)
	else:
		add_child(overlay_root)

	_update_overlay_rect()

	is_running = true
	running_scene_path = scene_path

	simulation_started.emit(scene_path)
	print("[InEditorGameRunner] 60 FPS 3D-Viewport simulation started for: %s (size: %dx%d)" % [scene_path, w, h])

	return {
		"result": {
			"running": true,
			"scene": scene_path,
			"mode": "in_editor_viewport",
			"viewport_size": {"width": w, "height": h}
		}
	}


## Update overlay position and size to match the 3D main screen area exactly
func _update_overlay_rect() -> void:
	if overlay_root and is_instance_valid(overlay_root):
		var main_screen: Control = EditorInterface.get_editor_main_screen()
		if main_screen and is_instance_valid(main_screen):
			var rect: Rect2 = main_screen.get_global_rect()
			overlay_root.global_position = rect.position
			overlay_root.size = rect.size


## Create in-viewport semi-transparent HUD capsule safely inside 3D viewport
func _create_hud_capsule(scene_path: String) -> void:
	var hud_layer := MarginContainer.new()
	hud_layer.name = "HUDLayer"
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_theme_constant_override("margin_top", 16)
	hud_layer.add_theme_constant_override("margin_right", 24)
	hud_layer.add_theme_constant_override("margin_left", 16)
	hud_layer.add_theme_constant_override("margin_bottom", 16)

	hud_panel = PanelContainer.new()
	hud_panel.name = "SimulationHUD"
	hud_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	hud_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.92)
	style.border_color = Color(0.3, 0.85, 0.4, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	hud_panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hud_panel.add_child(hbox)

	var status_lbl := Label.new()
	var scene_name := scene_path.get_file()
	status_lbl.text = "🟢 %s (仿真运行中)" % scene_name
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.4))
	hbox.add_child(status_lbl)

	var stop_btn := Button.new()
	stop_btn.text = "⏹ 退出"
	stop_btn.tooltip_text = "停止当前仿真并返回 3D 编辑器"
	stop_btn.focus_mode = Control.FOCUS_NONE
	stop_btn.pressed.connect(func(): stop_simulation())
	hbox.add_child(stop_btn)

	hud_layer.add_child(hud_panel)
	overlay_root.add_child(hud_layer)


## Stop the active simulation, restore background editor, and clean up nodes
func stop_simulation() -> Dictionary:
	if not is_running and overlay_root == null and sub_viewport == null:
		return {"result": {"stopped": true, "was_running": false}}

	var prev_scene: String = running_scene_path
	is_running = false
	running_scene_path = ""

	# 1. Restore editor low-processor power saving mode
	OS.low_processor_usage_mode = _saved_low_processor_mode

	# 2. Unbind main_screen resize events
	var main_screen: Control = EditorInterface.get_editor_main_screen()
	if main_screen and is_instance_valid(main_screen):
		if main_screen.resized.is_connected(_update_overlay_rect):
			main_screen.resized.disconnect(_update_overlay_rect)
		if main_screen.item_rect_changed.is_connected(_update_overlay_rect):
			main_screen.item_rect_changed.disconnect(_update_overlay_rect)

	# 3. Restore background 3D editor scene visibility and processing
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root and is_instance_valid(edited_root):
		edited_root.process_mode = _saved_edited_process_mode
		edited_root.visible = _saved_edited_visible

	# 4. Free simulation ticker and simulated game nodes
	if ticker and is_instance_valid(ticker):
		ticker.queue_free()
		ticker = null

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


## =============================================================================
## Inner Class: InEditorSimulationTicker
## Drives continuous _process(delta) and _physics_process(delta) callbacks
## across all non-@tool game script nodes in the SubViewport simulation sandbox.
## =============================================================================
class InEditorSimulationTicker extends Node:
	var target_root: Node = null
	var _process_nodes: Array[Node] = []
	var _physics_nodes: Array[Node] = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_rescan_nodes()
		if target_root and is_instance_valid(target_root):
			target_root.child_entered_tree.connect(_on_child_entered)
			target_root.child_exiting_tree.connect(_on_child_exiting)

	func _process(delta: float) -> void:
		for i in range(_process_nodes.size() - 1, -1, -1):
			var node := _process_nodes[i]
			if not is_instance_valid(node) or not node.is_inside_tree():
				_process_nodes.remove_at(i)
				continue
			if node.process_mode == Node.PROCESS_MODE_DISABLED:
				continue
			if node.has_method("_process"):
				node.call("_process", delta)

	func _physics_process(delta: float) -> void:
		for i in range(_physics_nodes.size() - 1, -1, -1):
			var node := _physics_nodes[i]
			if not is_instance_valid(node) or not node.is_inside_tree():
				_physics_nodes.remove_at(i)
				continue
			if node.process_mode == Node.PROCESS_MODE_DISABLED:
				continue
			if node.has_method("_physics_process"):
				node.call("_physics_process", delta)

	func _on_child_entered(node: Node) -> void:
		_register_node_recursive(node)

	func _on_child_exiting(node: Node) -> void:
		_unregister_node_recursive(node)

	func _rescan_nodes() -> void:
		_process_nodes.clear()
		_physics_nodes.clear()
		if target_root and is_instance_valid(target_root):
			_register_node_recursive(target_root)

	func _register_node_recursive(node: Node) -> void:
		if not is_instance_valid(node):
			return
		if node.get_script() != null:
			if node.has_method("_process") and not _process_nodes.has(node):
				_process_nodes.append(node)
			if node.has_method("_physics_process") and not _physics_nodes.has(node):
				_physics_nodes.append(node)
		for child in node.get_children():
			_register_node_recursive(child)

	func _unregister_node_recursive(node: Node) -> void:
		_process_nodes.erase(node)
		_physics_nodes.erase(node)
		for child in node.get_children():
			_unregister_node_recursive(child)
