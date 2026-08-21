# Task Execution & Recovery Loop

## Execution Rules

1. **Incremental Verification**:
   - For every scene created or modified, verify the tree using `get_scene_tree()`.
   - If an MCP tool returns an error, do not proceed with downstream steps. Read the error message, adjust the parameters, and re-execute.

2. **Visual Verification Gate**:
   - After completing node assembly and logic scripts, ALWAYS run the project with `run_project()`.
   - Take a screenshot with `take_screenshot(output_path="res://screenshots/verify.png")`.
   - Read the image using your native vision capabilities (`read`).
   - Confirm that:
     - The camera is aimed properly at the playable area.
     - The lighting and shadows are visible.
     - Meshes, materials, and colors render as designed.
   - Stop the project with `stop_project()`.

3. **Error Free Gate**:
   - Check `get_editor_errors()`.
   - Ensure there are no unresolved runtime exceptions, missing resources, or script compile failures.
