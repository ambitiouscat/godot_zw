@tool
extends Node

## InEditorGameRunner
## Manages in-editor isolated SubViewport scene simulations for Godot MCP on OpenHarmony.

var editor_plugin: EditorPlugin

var is_running: bool = false
var running_scene_path: String = ""
var sub_viewport: SubViewport = null
var sub_viewport_container: SubViewportContainer = null
var simulated_scene_root: Node = null

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

	# Create isolated SubViewport container
	sub_viewport_container = SubViewportContainer.new()
	sub_viewport_container.name = "InEditorGameContainer"
	sub_viewport_container.stretch = true
	sub_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS

	sub_viewport = SubViewport.new()
	sub_viewport.name = "InEditorGameViewport"
	
	# Fetch project window size or default to 1280x720
	var w: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var h: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	sub_viewport.size = Vector2i(w, h)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.handle_input_locally = true
	sub_viewport.gui_disable_input = false
	sub_viewport.physics_object_picking = true
	sub_viewport.process_mode = Node.PROCESS_MODE_ALWAYS

	sub_viewport_container.add_child(sub_viewport)
	add_child(sub_viewport_container)

	# Instantiate the target scene
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		stop_simulation()
		return {"error": {"code": -32603, "message": "Failed to load scene: %s" % scene_path}}

	simulated_scene_root = packed.instantiate()
	if simulated_scene_root == null:
		stop_simulation()
		return {"error": {"code": -32603, "message": "Failed to instantiate scene: %s" % scene_path}}

	sub_viewport.add_child(simulated_scene_root)

	is_running = true
	running_scene_path = scene_path

	print("[InEditorGameRunner] Simulation started for: %s (size: %dx%d)" % [scene_path, w, h])

	return {
		"result": {
			"running": true,
			"scene": scene_path,
			"mode": "in_editor_viewport",
			"viewport_size": {"width": w, "height": h}
		}
	}


## Stop the active simulation and clean up nodes
func stop_simulation() -> Dictionary:
	if not is_running and sub_viewport == null:
		return {"result": {"stopped": true, "was_running": false}}

	var prev_scene: String = running_scene_path
	is_running = false
	running_scene_path = ""

	if simulated_scene_root and is_instance_valid(simulated_scene_root):
		simulated_scene_root.queue_free()
		simulated_scene_root = null

	if sub_viewport and is_instance_valid(sub_viewport):
		sub_viewport.queue_free()
		sub_viewport = null

	if sub_viewport_container and is_instance_valid(sub_viewport_container):
		sub_viewport_container.queue_free()
		sub_viewport_container = null

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
