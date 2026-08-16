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

## 2. Tool Priority & Dual-Track Workflow

### Track A: Real-Time In-Engine Operations (Preferred for Scenes & Nodes)
- When creating, querying, modifying, or inspecting nodes, scene tree hierarchies, transforms, and node properties:
  **ALWAYS prioritize using live Godot MCP Pro tools**:
  - `get_scene_tree`: Inspect the currently active live scene graph.
  - `get_node_properties`: Read properties of any node in the scene.
  - `create_node`: Create and attach nodes directly in the live scene.
  - `set_node_property`: Modify transforms, materials, exported variables.
  - `attach_script`: Link GDScript files to scene nodes.
  - `run_project`: Launch and test the game project in-engine.
- **Why**: Direct in-memory engine manipulation renders immediately in the 3D/2D viewport, retains full Godot Undo/Redo history, and eliminates manual `.tscn` text parsing syntax bugs.

### Track B: Code & Asset File Creation (For GDScript, Shaders, Resources)
- Use `write` and `edit` for writing GDScript (`.gd`), Shaders (`.gdshader`), and configuration (`project.godot`).
- Always read (`read`) the existing file before mutating it to ensure line accuracy.
- When creating a new runnable scene, ensure `project.godot` (`run/main_scene="res://..."`) points to the valid scene path.

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
