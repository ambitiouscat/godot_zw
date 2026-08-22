## Why

During Godot AI development workflow execution on HarmonyOS, three critical tooling gaps were identified in Stage 3 (MCP Construction) and Stage 4 (Visual QA Gate):
1. **Runtime Screenshot Blindness**: 	ake_screenshot captures only the editor's ArkUI surface (
ative_arkui_surface) rather than the active game runtime viewport, preventing multimodal vision models from inspecting live game scenes and CanvasLayer UI.
2. **MCP Command Aliasing & Reflection Gap**: The protocol document specifies dd_input_action, but the MCP plugin only registered set_input_action. Missing introspection tools (list_methods, get_documentation) caused unnecessary execution errors during capability discovery.
3. **Runtime Debug Log Isolation**: get_output_log(source: " game\) returned empty lines because game runtime standard output was not bridged to the MCP server gateway.

Fixing these gaps ensures complete, automated, closed-loop AI game generation, diagnostics, and multimodal visual verification without human workaround intervention.

## What Changes

- **Engine-Level Native Viewport Screenshot**:
 - Implement native Godot engine viewport capture via RenderingServer.viewport_get_texture() / Viewport.get_texture().get_image() inside the Godot MCP server.
 - When ake_screenshot is called with source: \game\ or iewport: \game\, capture the actual rendering viewport rather than the editor UI frame.
 - Support automatic PNG file saving and base64/image metadata return.

- **MCP Command Compatibility Aliases & Introspection**:
 - Add dd_input_action as an alias for set_input_action in command_router.gd.
 - Implement list_methods to return all registered MCP commands dynamically.
 - Implement get_documentation to provide method availability and signature schema.

- **Game Runtime Output Log Relay**:
 - Intercept and bridge stdout/stderr and print() logs from the game process/runtime into the MCP log ring buffer.
 - Enable get_output_log(source: \game\) to return real-time game logs.

## Capabilities

### New Capabilities
- godot-mcp-runtime-qa: Engine-native viewport screenshot capture and game output log capture for multimodal QA.
- godot-mcp-command-introspection: Dynamic method introspection (list_methods, get_documentation) and command alias resolution for Godot MCP.

### Modified Capabilities
*(None)*

## Impact
- godot_zw/editor/plugins/godot_mcp/command_router.gd: Command alias registration and reflection handlers.
- godot_zw/editor/plugins/godot_mcp/commands/runtime_commands.gd & scene_commands.gd: Viewport texture extraction and log buffering.
- godot_zw/platform/openharmony/template/entry/src/main/ets/core/GodotMcpServerGateway.ets: Hybrid screenshot router (delegates game viewport to engine, editor to ArkUI).
- AI agent workflow efficiency: 0 trial-and-error errors in Stage 3 and full visual closed-loop in Stage 4.
