---
name: godot-error-doctor
version: 1.0.0
description: |
  Automated error diagnosis and self-healing for Godot projects.
  Use when encountering runtime errors, script compilation issues, node path failures, or MCP command errors.
author: GDAI / Godot Team
license: MIT
---

# Godot Error Doctor

Live diagnosis and automated recovery for Godot 4.x runtime and editor issues.

---

## 🩺 Diagnosis Flow

1. **Query Active Editor Errors**:
   ```
   MCP: get_editor_errors()
   ```
2. **Query Console Output Log**:
   ```
   MCP: get_output_log(limit=50)
   ```

---

## 🩹 Common Fixes

| Symptom | Probable Cause | Fix Strategy |
|---|---|---|
| `Node not found: NodePath(...)` | Relative path wrong or node not yet added | Use `get_node_or_null()` or check path via `get_scene_tree()`. |
| `Cannot get property 'X' on a null value` | Resource not loaded or node uninitialized | Ensure `_ready()` has fired or check `ResourceLoader.load()` result. |
| `Invalid call. Nonexistent function 'X'` | Method name typo or script not attached | Check GDScript method definition or attach script via `attach_script()`. |
| `UID conflict / corrupted scene` | Direct file editing collision | Re-create scene via MCP `create_scene()` or re-save with `save_scene()`. |
