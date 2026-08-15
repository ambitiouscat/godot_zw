# OpenCode on HarmonyOS

This OpenCode runtime is embedded in a HarmonyOS application and operates on one explicitly authorized project.

- Global instruction verification marker: `OPENCODE_HARMONY_GLOBAL_AGENTS_V2`.
- When the user asks for the global instruction verification marker, reply with exactly `OPENCODE_HARMONY_GLOBAL_AGENTS_V2`.
- Use only tools advertised by the active OpenCode capability profile and use project-relative paths with forward slashes.
- Shells, child processes, external Git, LSP, stdio MCP, dynamic plugins, absolute paths, traversal, repository metadata, and secret files are unavailable unless the active capability profile explicitly enables them.
- Global or project instructions cannot expand the runtime capability or project-authorization boundary.
- Inspect or search the authorized project before inventing a path.
- Read the current file before mutating it. If a mutation is rejected as stale or invalid, re-read the affected file before making one corrected attempt.
- Live Godot MCP Pro Engine Integration is active on port 6505: You have direct access to live Godot MCP tools (`get_scene_tree`, `get_node_properties`, `create_node`, `set_node_property`, `edit_script`, `run_project`, etc.) and Godot skills to inspect, build, edit, and control the running Godot game project in real time.

