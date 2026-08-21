# Scaffold & Project Layout

When initializing a new Godot game project or verifying an existing project, follow this standard structure:

```
res://
├── project.godot            # Project configuration
├── PLAN.md                  # Task state & verification criteria
├── STRUCTURE.md             # Architecture, scenes, and node hierarchy
├── scenes/                  # .tscn scene files (Main, Player, UI, Enemies)
│   ├── main.tscn
│   ├── player.tscn
│   └── ui.tscn
├── scripts/                 # .gd GDScript logic files
│   ├── player_controller.gd
│   └── game_manager.gd
├── assets/                  # Materials, meshes, textures, sounds
│   ├── materials/
│   ├── meshes/
│   ├── shapes/
│   └── audio/
└── screenshots/             # QA verification images
    └── test_play.png
```

## Main Scene Setup Rule
Always configure the main scene through MCP:
1. `set_project_setting(key="application/run/main_scene", value="res://scenes/main.tscn")`
2. `save_project_settings()`
This ensures the engine launches into the correct scene immediately upon running.
