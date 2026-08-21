---
name: godot-api
version: 1.0.0
description: |
  Official Godot 4.x node and GDScript API reference.
  Use when looking up standard Godot 4.x node types, properties, signals, lifecycle methods, and GDScript idioms.
author: GDAI / Godot Team
license: MIT
---

# Godot 4.x API & Node Reference

Standard, authoritative reference for Godot 4.x nodes and GDScript scripting.

## Common 3D Nodes
- **`Node3D`**: Base 3D transform node (`position`, `rotation_degrees`, `scale`).
- **`Camera3D`**: 3D camera (`current = true`, `fov = 75.0`).
- **`DirectionalLight3D`**: Sun/ambient light (`light_energy`, `shadow_enabled = true`).
- **`MeshInstance3D`**: Visual mesh container (`mesh`, `material_override`).
- **`CollisionShape3D`**: Physical shape (`shape = BoxShape3D.new()`).

## Common Physics Nodes
- **`CharacterBody3D`**: Kinematic player/NPC controller (`velocity`, `move_and_slide()`, `is_on_floor()`).
- **`RigidBody3D`**: Simulated physics object (`mass`, `apply_central_impulse(vec)`, `freeze`).
- **`StaticBody3D`**: Non-moving collision geometry (floors, walls).
- **`Area3D`**: Trigger volume (`body_entered` signal, `monitoring = true`).

## Lifecycle Callbacks
- `_ready()`: Called once when node enters the active scene tree.
- `_process(delta: float)`: Called every render frame (use for UI, animations, non-physics logic).
- `_physics_process(delta: float)`: Called every fixed physics tick (60Hz default) — use for `move_and_slide()`, velocity adjustments, physics queries.
- `_input(event: InputEvent)`: Called on raw input events.
- `_unhandled_input(event: InputEvent)`: Called for unconsumed game action inputs.
