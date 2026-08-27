# Game Development Workflow Standards Specification

## Purpose

Defines mandatory architecture, file-governance, and verification standards for
Godot AI game generation in this repository.

## Requirements

### Requirement: Scene-First Visual Assembly via In-Engine MCP
The system and all AI developer agents SHALL construct all static scene structures, meshes, collision shapes, materials, primary 3D cameras, and primary lights directly into `.tscn` scene files using live engine MCP tools before attaching scripts. Static level content SHALL remain visible and interactive in the Godot editor viewport without running the project.

#### Scenario: Inspect a generated scene before runtime
- **WHEN** a generated scene is opened in the Godot editor
- **THEN** its static geometry, materials, lighting, collisions, and camera nodes are visible without running the project

#### Scenario: Instantiate transient runtime entities
- **WHEN** gameplay dynamically spawns bullets, particles, enemies, or item drops
- **THEN** the script instantiates dedicated packed scenes instead of constructing static level geometry in `_ready()`

### Requirement: 5-Tier Categorized Project Directory Hierarchy
The system and all AI developer agents SHALL organize project files under `scenes/`, `scripts/`, `assets/`, `resources/`, and `openspec/`, and SHALL NOT place loose project content in the `res://` root.

#### Scenario: Place generated project files
- **WHEN** an agent creates a scene, script, static asset, or engine resource
- **THEN** the file is placed in its matching directory and scripts mirror the scene hierarchy where applicable
