# Godot MCP-First Recipes Cheat Sheet

This document contains standard, high-reliability MCP call sequences for common Godot 4.x game development tasks.

---

## 1. 3D Environment & Static Ground

```gdscript
# 1. Create Ground StaticBody
MCP: create_node(name="Ground", type="StaticBody3D", parent=".")

# 2. Add MeshInstance3D child
MCP: create_mesh_instance_3d(name="GroundMesh", parent="Ground")

# 3. Create BoxMesh and assign to GroundMesh
MCP: create_box_mesh(path="res://assets/meshes/ground_mesh.tres", properties={"size": Vector3(30, 0.5, 30)})
MCP: update_property(node_path="Ground/GroundMesh", property="mesh", value="res://assets/meshes/ground_mesh.tres")

# 4. Create Material and assign to GroundMesh
MCP: create_material(path="res://assets/materials/ground_mat.tres", properties={"albedo_color": Color(0.2, 0.6, 0.3, 1), "roughness": 0.8})
MCP: update_property(node_path="Ground/GroundMesh", property="material_override", value="res://assets/materials/ground_mat.tres")

# 5. Add CollisionShape3D child and shape
MCP: create_collision_shape_3d(name="GroundCollision", parent="Ground")
MCP: create_box_shape_3d(path="res://assets/shapes/ground_shape.tres", properties={"size": Vector3(30, 0.5, 30)})
MCP: update_property(node_path="Ground/GroundCollision", property="shape", value="res://assets/shapes/ground_shape.tres")
```

---

## 2. 3D Player Character (Capsule)

```gdscript
# 1. Create Player CharacterBody3D at position (0, 1, 0)
MCP: create_node(name="Player", type="CharacterBody3D", parent=".", properties={"position": Vector3(0, 1, 0)})

# 2. Create Capsule Mesh
MCP: create_mesh_instance_3d(name="PlayerMesh", parent="Player")
MCP: create_capsule_mesh(path="res://assets/meshes/player_capsule.tres", properties={"radius": 0.4, "height": 1.8})
MCP: update_property(node_path="Player/PlayerMesh", property="mesh", value="res://assets/meshes/player_capsule.tres")

# 3. Create Capsule Collision
MCP: create_collision_shape_3d(name="PlayerCollision", parent="Player")
MCP: create_capsule_shape_3d(path="res://assets/shapes/player_col.tres", properties={"radius": 0.4, "height": 1.8})
MCP: update_property(node_path="Player/PlayerCollision", property="shape", value="res://assets/shapes/player_col.tres")

# 4. Attach Player Movement Script
File: write_to_file("res://scripts/player_controller.gd", <CharacterBody3D script>)
MCP: attach_script(node_path="Player", script_path="res://scripts/player_controller.gd")
```

---

## 3. 3D Camera & Directional Lighting

```gdscript
# 1. Main Camera positioned behind & above player, looking at center
MCP: create_camera_3d(name="MainCamera", parent=".", properties={"position": Vector3(0, 5, 8), "rotation_degrees": Vector3(-30, 0, 0), "current": true})

# 2. Sun Lighting
MCP: create_light_3d(name="DirectionalLight3D", parent=".", type="DirectionalLight3D", properties={"rotation_degrees": Vector3(-45, 45, 0), "light_energy": 1.2, "shadow_enabled": true})
```

---

## 4. Collectible Coin (Area3D / RigidBody3D)

```gdscript
# 1. Create Coin Area3D
MCP: create_node(name="Coin", type="Area3D", parent=".", properties={"position": Vector3(0, 1, 0)})

# 2. Cylinder Mesh
MCP: create_mesh_instance_3d(name="CoinMesh", parent="Coin", properties={"rotation_degrees": Vector3(90, 0, 0)})
MCP: create_cylinder_mesh(path="res://assets/meshes/coin_mesh.tres", properties={"top_radius": 0.4, "bottom_radius": 0.4, "height": 0.1})
MCP: update_property(node_path="Coin/CoinMesh", property="mesh", value="res://assets/meshes/coin_mesh.tres")

# 3. Gold Emissive Material
MCP: create_material(path="res://assets/materials/gold_mat.tres", properties={
    "albedo_color": Color(1.0, 0.84, 0.0, 1.0),
    "metallic": 0.9,
    "roughness": 0.2,
    "emission_enabled": true,
    "emission": Color(0.8, 0.6, 0.0, 1.0)
})
MCP: update_property(node_path="Coin/CoinMesh", property="material_override", value="res://assets/materials/gold_mat.tres")

# 4. Collision Shape
MCP: create_collision_shape_3d(name="CoinCollision", parent="Coin")
MCP: create_cylinder_shape_3d(path="res://assets/shapes/coin_shape.tres", properties={"radius": 0.4, "height": 0.1})
MCP: update_property(node_path="Coin/CoinCollision", property="shape", value="res://assets/shapes/coin_shape.tres")
```

---

## 5. GridMap Level Baking

```gdscript
# Export all MeshInstance3D nodes from a tileset scene into a MeshLibrary resource
MCP: export_mesh_library(scene_path="res://scenes/tileset_source.tscn", output_path="res://assets/tile_library.tres")

# Create GridMap node and assign mesh library
MCP: create_node(name="GridMap", type="GridMap", parent=".", properties={"mesh_library": "res://assets/tile_library.tres", "cell_size": Vector3(2, 2, 2)})
```
