---
name: godot-visual-qa
version: 1.0.0
description: |
  Visual Quality Assurance for Godot games using native multimodal vision.
  Use when validating gameplay screenshots, framing, materials, lighting, and layout without any external binary dependencies.
author: GDAI / Godot Team
license: MIT
---

# Godot Visual QA (Native Multimodal)

Verify game visuals directly using in-engine MCP screenshot capture and native AI vision (`read`).

---

## 📸 Standard Verification Workflow

1. **Start Project**:
   ```
   MCP: run_project()
   ```
2. **Capture In-Engine Screenshot**:
   ```
   MCP: take_screenshot(output_path="res://screenshots/test_play.png")
   ```
3. **AI Native Vision Inspection**:
   ```
   AI: read("res://screenshots/test_play.png")
   ```
4. **Stop Project**:
   ```
   MCP: stop_project()
   ```

---

## 🔍 Visual Review Checklist

When reading the screenshot image, inspect the following criteria:

1. **Framing & Viewport**:
   - Is the main actor/player centered or framed comfortably in view?
   - Is the camera clipping through walls, floors, or terrain?
2. **Lighting & Atmosphere**:
   - Is the scene well-lit, or is it pitch black?
   - Are shadows casting correctly to ground the objects in 3D space?
3. **Meshes & Materials**:
   - Are materials rendering with expected colors and reflections (roughness, metallic, emission)?
   - Are any textures stretched or missing (default magenta/grey)?
4. **UI & HUD**:
   - Are text labels, health bars, or score counters readable and anchored properly?
