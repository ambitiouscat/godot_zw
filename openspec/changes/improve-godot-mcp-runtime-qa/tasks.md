## 1. MCP Routing and Introspection

- [x] 1.1 Add dd_input_action compatibility alias mapped to set_input_action in godot_zw/editor/plugins/godot_mcp/command_router.gd
- [x] 1.2 Implement list_methods handler in command_router.gd returning all registered MCP methods
- [x] 1.3 Implement get_documentation handler in command_router.gd providing method existence and signature schema

## 2. In-Engine Viewport Screenshot & Hybrid Gateway Routing

- [x] 2.1 Enhance mcp_screenshot_service.gd / untime_commands.gd to capture live RenderingServer viewport frames (rame_post_draw) when iewport: " game\ or source: \game\ is requested
- [x] 2.2 Update GodotMcpServerGateway.ets to forward screenshot requests with iewport: \game\ or source: \game\ directly to the engine WebSocket client instead of intercepting ArkUI
- [x] 2.3 Ensure screenshot files save to es://screenshots/ with valid file paths and dimensions returned

## 3. Game Runtime Log Streaming

- [x] 3.1 Intercept and buffer running game stdout/stderr output into the MCP runtime logger
- [x] 3.2 Update get_output_log to return buffered game logs when source: \game\ or source: \all\ is requested

## 4. Verification & Deployment

- [x] 4.1 Run packaging pipeline to update rawfile staging and recalculate hashes
- [x] 4.2 Build and install HAP to test device
- [x] 4.3 Verify list_methods, dd_input_action, ake_screenshot(source: \game\), and get_output_log on tablet
