# CLAUDE.md — Godot AI Developer Instructions

> **Master Standard**: This project strictly follows the 《Godot Game Development Master Protocol (GGD-Protocol-v1)》 located at skills/GODOT_GAME_DEV_PROTOCOL.md and GODOT_GAME_DEV_PROTOCOL.md.

## 🚨 Critical Behavioral Guardrails

1. **Strict 6-Stage Lifecycle**:
   - Stage 0: Reconnaissance (`get_editor_state`, `get_project_structure`)
   - Stage 1: Specialist Routing (`game-designer`, `level-design`, `godot-game-script-engineer`, `game-audio`, `godot-shader-dev`)
   - Stage 2: Architecture & OpenSpec Proposal (Fun Hypothesis, Design Pillars, Core Loops, Input Map, Task breakdown)
   - 🛑 **[Approval Gate 1]**: Present proposal to user and wait for confirmation before generating code!
   - Stage 3: 5-Layer Forward MCP Construction (Autoload → Meshes/Mats → Nodes/Collisions → Typed Scripts → Settings)
   - Stage 4: Self-Healing Diagnostics & Multimodal Visual QA (`run_project` → `get_editor_errors` → `take_screenshot(source="game")` → `stop_project`)
   - 🛑 **[Approval Gate 2]**: Present visual QA analysis to user.
   - Stage 5: Archive & Session Checkpoint

2. **Authoritative GameAbility Runtime**:
   - **Real Run**: `run_project`, `run_scene`, `run_current_scene`, `stop_project` target standalone `GameAbility` and are the only gameplay execution path.
   - **Editor Inspection**: `take_screenshot(source="editor")` is limited to static editor/scene inspection and cannot satisfy Stage 4 runtime acceptance.
   - **Stage 4 Evidence**: `take_screenshot(source="game")` must come from the active correlated `GameAbility` session.
   - **Zero Cross-Source Fallback**: screenshot source is strictly `"editor" | "game"`; unavailable game capture returns an explicit error and never falls back to the editor or OS screen.

3. **MCP-First (No Manual .tscn Editing)**:
   - Always call live MCP tools (`create_scene`, `create_node`, `create_collision_shape_3d`, `set_node_property`, etc.) to build scene trees and bind resources.
   - Never handcraft raw .tscn text files.

4. **GDScript 2.0 Static Typing**:
   - Explicit parameter types, return types (`func foo(bar: float) -> void`), and typed arrays (`Array[Node3D]`).
   - Signals must be typed and snake_case (`signal score_changed(new_score: int)`).

5. **Cross-Platform Input**:
   - Use Input Map actions (`move_left`, `move_right`, `move_forward`, `move_back`, `action_jump`, `action_primary`) to support both HarmonyOS touch and PC keyboard/mouse.

## Agent skills

### Issue tracker
Local markdown issue tracking under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Domain docs
Single-context layout (`CONTEXT.md` and `docs/adr/` at repo root). See `docs/agents/domain.md`.
