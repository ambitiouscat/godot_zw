## Context

See proposal.md for motivation.
Currently, on OpenHarmony Godot builds:
1. GodotMcpServerGateway.ets routes 	ake_screenshot directly to ArkUI componentSnapshot.get('godot_surface'). This works for editor surfaces but captures the editor UI rather than running game scenes.
2. command_router.gd lacks aliases for dd_input_action and reflection handlers (list_methods, get_documentation).
3. Running games write logs to standard output, but the in-engine MCP log collector (get_output_log) is not bridged across the runtime boundary.

## Goals / Non-Goals

**Goals:**
- Provide true game viewport image extraction via engine RenderingServer / Viewport textures when iewport: " game\ or source: \game\ is requested.
- Enable GodotMcpServerGateway.ets to delegate viewport capture to the Godot engine process via WebSocket command get_game_screenshot / capture_game_screenshot when in play mode.
- Add dd_input_action, list_methods, and get_documentation to command_router.gd.
- Buffer game output logs in the engine MCP logger so get_output_log(source: \game\) returns execution logs.

**Non-Goals:**
- Modifying OS-level screen recorder or native system screenshot APIs.
- Altering the Godot rendering pipeline architecture.

## Decisions

### Decision 1: Hybrid Screenshot Routing
- **Approach**: In GodotMcpServerGateway.ets, inspect params?.viewport or params?.source or is_playing state. If iewport === 'game' or source === 'game', forward the command directly to the in-engine WebSocket client (mcp_screenshot_service.gd / untime_commands.gd). If not playing or requesting editor UI, capture the native ArkUI surface.
- **Alternatives Considered**:
 - *ArkUI-only capture*: Fails when game runs in sub-viewport or separate rendering layer.
 - *Engine-only capture*: Cannot capture the ArkUI IDE chrome (toolbars, file trees, inspectors).

### Decision 2: MCP Command Router Registration and Aliasing
- **Approach**: In command_router.gd:
 1. Map dd_input_action to _command_handlers[\set_input_action\].
 2. Implement list_methods returning sorted keys of _command_handlers.
 3. Implement get_documentation returning method existence and schema metadata.
- **Alternatives Considered**:
 - *Client-side remapping*: Fragile and requires modifying every agent tool calling wrapper.

### Decision 3: In-Engine Game Output Log Ring Buffer
- **Approach**: In untime_commands.gd / editor_commands.gd, tap into Godot's EditorInterface.get_output_log() or stdout capture and retain the last 500 lines tagged with [game] or [editor].

## Risks / Trade-offs

- **[Risk]** Viewport texture capture on Vulkan / Mobile renderer may require waiting for the next frame end (wait RenderingServer.frame_post_draw).
 → **Mitigation**: Implement wait RenderingServer.frame_post_draw before grabbing get_viewport().get_texture().get_image().
- **[Risk]** Large screenshot payloads over WebSocket.
 → **Mitigation**: Save directly to es://screenshots/... on the filesystem and return path and dimensions, with optional base64 only when explicitly requested.
