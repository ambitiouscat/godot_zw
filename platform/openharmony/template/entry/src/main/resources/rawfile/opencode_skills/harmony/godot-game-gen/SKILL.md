---
name: godot-game-gen
version: 1.1.0
description: |
  Master orchestrator for generating complete Godot 4.x games from natural language.
  Use when the user asks to "make a Godot game", "build a 3D game", "generate a game in Godot", "create a platformer", or develop/update Godot game projects.
author: GDAI / Godot Team
license: MIT
---

# Godot Game Generator (MCP-First)

Generate and update complete, playable Godot 4.x games from natural language prompts using in-engine MCP tools and native multimodal verification.

---

## ⚡ Core Principle: MCP-First In-Engine Driving

**ALWAYS prefer driving live MCP tools over directly writing raw scene (.tscn) text files:**

1. **Scene & Node Assembly (100% MCP)**:
   - Call `create_scene`, `create_node`, `create_camera_3d`, `create_light_3d`, `create_mesh_instance_3d`, `create_collision_shape_3d`.
   - Never handcraft raw `.tscn` text concatenation — Godot's live MCP manages UIDs, hierarchy, and type validation safely in-memory without corrupting scene indices.
2. **Meshes & Materials (100% MCP)**:
   - Call `create_box_mesh`, `create_cylinder_mesh`, `create_sphere_mesh`, `create_capsule_mesh`, `create_plane_mesh`, `create_standard_material_3d`, `create_resource`.
   - The engine serializes valid `.tres` resources automatically.
3. **Properties & Resource Binding (100% MCP)**:
   - Call `update_property`, `set_node_property`, `set_resource_property`.
4. **GDScript & Shader Writing (File Edit + MCP Attach)**:
   - Write standard GDScript `.gd` code files using file writing tools.
   - Attach scripts to nodes using MCP `attach_script` or setting the node's `script` property.
   - Call `rescan_filesystem` / `refresh_filesystem` to notify the engine.
5. **Runtime Verification & Multimodal QA (100% MCP)**:
   - Run the game with `run_project` / `play_scene`.
   - Capture gameplay screen with `take_screenshot(path="res://screenshots/verify.png")`.
   - Directly invoke your native **`read`** tool on the screenshot image to visually verify framing, lighting, and gameplay elements.
   - Stop execution with `stop_project`.

---

## 🛑 Strict MCP Whitelist & Anti-Hallucination Rules

**ONLY use the following validated MCP methods. NEVER guess or invent method names:**

| Valid MCP Method | Correct Usage | Forbidden Hallucinated Method (DO NOT USE) |
|---|---|---|
| `get_editor_state` | Query active scene, root node, playing status | `get_state`, `check_editor` ❌ |
| `get_editor_errors` | Query active compilation and runtime errors | `get_debugger_errors` ❌, `get_errors` ❌ |
| `get_output_log` | Query console stdout/stderr logs (`source="all"|"game"`) | `read_log` ❌, `get_console` ❌ |
| `open_scene` | Open or reload a scene in editor (`path="res://..."`) | `revert_scene` ❌, `reload_scene` ❌ |
| `save_scene` | Save active scene to disk | `save_all` ❌ |
| `create_scene` | Create new scene with root Node3D/Node2D | `new_scene` ❌ |
| `get_scene_tree` | Get hierarchy tree of active scene | `get_nodes` ❌, `dump_scene` ❌ |
| `create_node` | Add node under parent (`parent_path`, `type`, `name`) | `add_node` ❌ |
| `set_node_property` | Set property on node (`node_path`, `property`, `value`) | `set_prop` ❌ |
| `attach_script` | Attach GDScript to node (`node_path`, `script_path`) | `bind_script` ❌ |
| `run_project` | Run main scene or active scene | `play_game` ❌, `launch_project` ❌ |
| `stop_project` | Terminate running game | `kill_game` ❌ |
| `take_screenshot` | Capture current viewport (`path="res://..."`) | `capture_screen` ❌ |
| `export_mesh_library` | Bake meshes in scene to MeshLibrary `.tres` | `bake_gridmap` ❌ |

---

## 📋 6-Phase Pipeline

```
User Prompt (or OpenSpec Task)
    │
    ├── 1. Project Exploration & Plan
    │       ├── Check existing state: get_editor_state, get_project_structure
    │       ├── Scan existing assets: resource-finder
    │       └── Plan tasks into PLAN.md & STRUCTURE.md (or openspec/tasks.md)
    │
    ├── 2. Architecture & Main Scene Setup
    │       ├── Create main scene: create_scene(path="res://main.tscn", root_type="Node3D", open_in_editor=true)
    │       └── Set main scene in settings: set_project_setting("application/run/main_scene", "res://main.tscn") -> save_project_settings
    │
    ├── 3. MCP Node & Resource Assembly
    │       ├── Build 3D world: Ground, Environment, Lighting, Cameras
    │       ├── Build Actors: Player (CharacterBody3D), Items (RigidBody3D/Area3D)
    │       └── Generate & bind meshes/materials via MCP primitive tools
    │
    ├── 4. GDScript Logic Implementation
    │       ├── Write gameplay scripts (*.gd)
    │       └── Attach scripts to nodes via MCP attach_script
    │
    ├── 5. Runtime & Native Multimodal Visual QA Gate
    │       ├── run_project
    │       ├── take_screenshot(path="res://screenshots/test_play.png")
    │       ├── read(filePath="res://screenshots/test_play.png") -> Analyze visual elements
    │       └── stop_project
    │
    └── 6. Error Diagnostics & Final Polish
            ├── get_editor_errors -> Resolve any warnings/errors
            └── Present completed project summary
```

---

## 🛠️ Sub-Guides

| Guide | Purpose |
|---|---|
| `mcp-recipes.md` | Copy-pasteable MCP tool sequences for common Godot 3D/2D patterns |
| `scaffold.md` | Project structure and configuration conventions |
| `task-execution.md` | Execution loop and error recovery rules |
| `quirks.md` | Godot 4.x engine gotchas and best practices |
