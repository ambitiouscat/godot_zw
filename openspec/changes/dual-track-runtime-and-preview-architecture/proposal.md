## Why

In-editor script simulation cannot execute non-`@tool` GDScript logic (such as procedural scene spawning, chess pieces, dynamic UI updates, and game loops) without either compromising editor stability through unsafe `@tool` mutations/autoload hijacking, or omitting script execution entirely (resulting in incomplete visual output).

This change removes the custom in-editor viewport simulation runner, restores standard editor viewport inspection, and establishes standalone `GameAbility` as the sole, authoritative execution and Stage 4 QA acceptance runtime, while resolving critical session correlation, screenshot reliability, and READY/EXIT lifecycle handshakes.

## What Changes

- **BREAKING** Remove the custom in-editor viewport simulation track (`InEditorGameRunner`, SubViewport overlay, HUD capsule, and `simulate_*` commands). Standard editor inspection remains available via `source="editor"`.
- Establish standalone `GameAbility` as the sole, authoritative runtime for game execution and Stage 4 Visual/Functional QA acceptance.
- Implement typed `LifecycleCoordinator` managing asynchronous `GameAbility` states (`IDLE`, `STARTING`, `RUNNING`, `STOPPING`, `RECONCILING`), UUID `session_id`, `operation_id`, random `boot_nonce`, and serialized idempotency reducers.
- Remove the 15-second run-state reset timer in OpenHarmony `BridgeCallbacks.ets`.
- Implement reliable `GameAbility` screenshot capture via `mcp_screenshot_service.gd` and `editor_commands.gd` with full provenance metadata (`backend: "game_ability_viewport"`, `sha256`, dimensions, format) and zero cross-source fallback.
- Enforce strict session correlation and READY/EXIT handshakes between `EditorAbility`, `BridgeCallbacks`, and `GameAbility`.
- Provide an automated, fail-safe acceptance test suite validating start, screenshot, longevity (>20s), and clean stop.

## Capabilities

### New Capabilities

- `game-ability-runtime-control`: Authoritative standalone `GameAbility` execution, session correlation, OpenHarmony lifecycle bridge, reliable screenshot capture, and clean termination.

### Modified Capabilities

- `game-dev-workflow-standards`: Require real-run `GameAbility` evidence for Stage 4 Visual and Functional QA.

## Impact

- `editor/plugins/godot_mcp/`: Removal of `in_editor_game_runner.gd`, update of `lifecycle_coordinator.gd`, `command_router.gd`, `command_schemas.gd`, `plugin.gd`, and `editor_commands.gd`.
- `platform/openharmony/template/entry/src/main/ets/`: OpenHarmony bridge and ability lifecycle handlers.
- Skills and documentation: `AGENTS.md`, `GODOT_GAME_DEV_PROTOCOL.md`, `godot-visual-qa`, and `godot-game-gen`.
