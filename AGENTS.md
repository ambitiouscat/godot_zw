# AGENTS.md — Godot AI Developer Instructions

> **Master Standard**: This project strictly follows the 《Godot Game Development Master Protocol (GGD-Protocol-v1)》 located at skills/GODOT_GAME_DEV_PROTOCOL.md and GODOT_GAME_DEV_PROTOCOL.md.

## 🚨 Critical Behavioral Guardrails & Iron Rules

1. **Strict 6-Stage Lifecycle**:
   - Stage 0: Reconnaissance (`get_editor_state`, `get_project_structure`)
   - Stage 1: Specialist Routing (`game-designer`, `level-design`, `godot-game-script-engineer`, `game-audio`, `godot-shader-dev`)
   - Stage 2: Architecture & OpenSpec Proposal (Fun Hypothesis, Design Pillars, Core Loops, Input Map, Task breakdown)
   - 🛑 **[Approval Gate 1]**: Present proposal to user and wait for confirmation before generating code!
   - Stage 3: 5-Layer Forward MCP Construction (Autoload → Meshes/Mats → Nodes/Collisions → Typed Scripts → Settings)
   - Stage 4: Self-Healing Diagnostics & Multimodal Visual QA (`run_project` → `get_editor_errors` → `take_screenshot` → `stop_project`)
   - 🛑 **[Approval Gate 2]**: Present visual QA analysis to user.
   - Stage 5: Archive & Session Checkpoint

2. **Scene-First Visual MCP Assembly (Mandatory 3D Viewport Visibility)**:
   - **🔴 REDLINE**: NEVER procedurally instantiate static level environments, terrain, boards, meshes, cameras, or lights via GDScript `new()` in `_ready()`!
   - **🟢 MANDATORY**: Always use MCP tools (`create_scene`, `create_node`, `create_box_mesh`, `create_collision_shape_3d`, `create_camera_3d`, `create_light_3d`, `set_node_property`, `save_scene`) to construct the full hierarchy in `.tscn` files so scenes are **100% visible and interactive in the Godot 3D editor viewport**.
   - **Dynamic Spawns**: Runtime code instantiation is ONLY permitted for transient dynamic entities (bullets, particles, spawned enemies) and MUST use `.tscn` templates via `load("res://scenes/entities/bullet.tscn").instantiate()`.

3. **5-Tier Categorized Project Directory Hierarchy**:
   - **🔴 REDLINE**: NEVER dump loose scripts, scenes, materials, textures, or audio into `res://` root!
   - **🟢 MANDATORY Hierarchy**:
     - `res://scenes/` — All `.tscn` scenes (`main.tscn`, `levels/`, `entities/`, `ui/`)
     - `res://scripts/` — All `.gd` logic scripts (mirroring `scenes/` structure)
     - `res://assets/` — Raw static assets (`models/`, `textures/`, `audio/sfx/`, `audio/bgm/`, `fonts/`)
     - `res://resources/` — Engine resources (`materials/`, `themes/`, `shapes/`)
     - `res://openspec/` — OpenSpec change tracking

4. **GDScript 2.0 Static Typing**:
   - Explicit parameter types, return types (`func foo(bar: float) -> void`), and typed arrays (`Array[Node3D]`, `Array[Dictionary]`).
   - Signals must be typed and snake_case (`signal score_changed(new_score: int)`).

5. **Cross-Platform Input**:
   - Use Input Map actions (`move_left`, `move_right`, `move_forward`, `move_back`, `action_jump`, `action_primary`) to support both HarmonyOS touch and PC keyboard/mouse.
