# OpenCode on HarmonyOS — Godot Engine AI Assistant

This OpenCode runtime is embedded in the Godot 4.7 (GDAI) application on OpenHarmony NEXT and operates on the authorized game project.

- Global instruction verification marker: `OPENCODE_HARMONY_GLOBAL_AGENTS_V2`.
- When the user asks for the global instruction verification marker, reply with exactly `OPENCODE_HARMONY_GLOBAL_AGENTS_V2`.

---

## 1. Project Context & Environment

- **Engine Version**: Godot 4.7 (GDAI-4.7) on OpenHarmony NEXT (ARM64).
- **Project Root**: `res://`. All file paths MUST use project-relative forward slash notation (e.g., `res://scenes/main.tscn`, `res://scripts/player.gd`, `res://project.godot`).
- **Sandbox Boundary**: Standard OS shells, external git binaries, and host-level commands outside the project directory are unavailable. All work must remain inside the authorized `res://` project.

---

## 2. Tool-First Execution Principle & Escalation Strategy

### Core Rule: Always Try Engine MCP Tools First
- **Step 1 (First Choice — In-Engine Live Tools)**:
  Before touching text files on disk, ALWAYS first attempt to use the specialized live Godot MCP tools:
  - **Scene & Node Operations**: `godot_get_scene_tree`, `godot_get_node_properties`, `godot_create_node`, `godot_set_node_property`, `godot_delete_node`.
  - **Resources & Materials**: `godot_execute` with `create_resource`, `edit_resource`, `create_standard_material_3d`, `create_shader`.
  - **Project Configuration & Main Scene**: `godot_execute` with `set_project_setting` or `set_main_scene` (e.g., `params: {"key": "application/run/main_scene", "value": "res://main.tscn"}`).
  - **Scene Persistence & Playback**: `godot_execute` with `save_scene`, `godot_run_project`, `godot_execute` with `run_scene` or `run_current_scene`.
  - **Error Diagnostics**: `godot_get_editor_errors`, `godot_execute` with `get_output_log`.
  - **Why**: Direct in-engine manipulation renders immediately in the viewport, records undo/redo history, and updates live editor memory state with zero external reload prompts.

- **Step 2 (Fallback — General File Operations)**:
  ONLY when:
  1. No matching in-engine MCP tool exists for the specific task;
  2. You are writing pure script code (`.gd`) or custom shader code (`.gdshader`);
  3. Or an in-engine tool is unavailable after attempting `godot_execute`;
  THEN use general file tools (`write`, `edit`, `read`) to accomplish the goal.
  - When editing existing files, always read (`read`) the file first to ensure line accuracy.
  - Avoid modifying `project.godot` with raw file tools when the editor is active unless `set_project_setting` is explicitly unavailable.

---

## 3. Strict GDScript 4 Syntax & Coding Rules

To prevent compilation and parse errors in Godot 4.7, you MUST strictly adhere to the following rules:

1. **Indentation**:
   - MUST use **Tabs (`\t`)** for indentation, NEVER spaces.

2. **Static Typing & Type Safety**:
   - Always provide static type annotations for variables, parameters, and return types:
     ```gdscript
     func _ready() -> void:
         pass

     func _process(delta: float) -> void:
         pass
     ```
   - **FORBIDDEN Type Inference on Untyped Variants**:
     - Do NOT use `:=` when the right-hand expression is an untyped `Variant` (e.g., dictionary lookup `dict[key]`, `get_node()`).
     - ❌ **WRONG**: `var planet_name := _planet_nodes[orbit_name].name` (Parse Error: Cannot infer type)
     - ✅ **CORRECT**: `var planet_name: String = (_planet_nodes[orbit_name] as Node).name`
     - ✅ **CORRECT**:
       ```gdscript
       var node: Node = _planet_nodes[orbit_name]
       var planet_name: String = node.name
       ```

3. **Standard Godot 4 Math API**:
   - Use standard GDScript built-in math functions:
     - Trigonometry: `cos(angle)`, `sin(angle)`, `tan(angle)`
     - Angles: `deg_to_rad(degrees)`, `rad_to_deg(radians)`
     - Clamping & Bounds: `clampf(val, min, max)`, `maxf(a, b)`, `minf(a, b)`, `lerpf(from, to, weight)`
     - Random: `randf()`, `randf_range(min, max)`, `randi()`, `randi_range(min, max)`
   - ❌ **FORBIDDEN**: Never use C/C++ math function names like `cosf()`, `sinf()`, `fabsf()` in GDScript.

4. **Iteration & Loops**:
   - Use `range()` for numeric loops:
     - ❌ `for i in 5:`
     - ✅ `for i in range(5):`
     - ✅ `for i in range(nodes.size()):`

5. **3D Node Orientation & Transforms**:
   - Use `Vector3.UP`, `Vector3.FORWARD`, `Vector3.RIGHT` for standard basis vectors.
   - Use `look_at(target_pos, Vector3.UP)` or `transform.looking_at(target_pos, Vector3.UP)` to orient nodes.
   - Keep mesh geometries clean and assign distinct `StandardMaterial3D` or `OrmMaterial3D` instances when custom albedo colors are needed.
