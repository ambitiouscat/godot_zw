## Why

Standalone `GameAbility` is the only execution path that provides complete Godot scripts, input, audio, rendering, and lifecycle behavior, but on HarmonyOS tablets it can take over the screen and hide `EditorAbility`. That interruption prevents an AI client from continuing an inspect-run-capture-debug loop, while the currently connected 2-in-1 device's native window behavior does not prove tablet behavior.

This change adds a device-aware Run Presentation contract so real execution can remain visible beside the editor on tablets, without reviving the incomplete SubViewport simulation or pretending that a separate process is embedded in Godot Game View.

## What Changes

- Add `presentation: "auto" | "windowed" | "floating" | "split" | "fullscreen"` to real `run_*` commands, with requested and actual presentation reported for every accepted session.
- **BREAKING** For MCP/AI calls made through the HarmonyOS editor, an omitted `presentation` resolves to the recommended `windowed` policy instead of implicitly allowing a fullscreen takeover. Explicit parameters continue to take precedence.
- Define `windowed` as an AI-safe selection policy, not a native window type: tablet uses floating, then split, then a hard error; 2-in-1 preserves the native windowed presentation; phone rejects an explicitly requested unsupported windowed presentation rather than silently entering fullscreen.
- Keep the human Editor UI device-local with `Auto / Windowed / Floating / Split / Fullscreen`, defaulting to `Auto`; do not persist these choices in project files.
- Detect presentation capabilities at runtime and expose `recommended_presentation: "windowed"`, supported modes, capability source, constraints, and an explanation that the recommendation keeps the editor visible and controllable during AI debugging.
- Keep one real-run lifecycle state machine (`IDLE`, `REAL_STARTING`, `REAL_RUNNING`, `REAL_STOPPING`, `RECONCILING`); presentation is session metadata, not a parallel execution mode.
- Define strict conflict, idempotency, stop/close/crash reconciliation, window-geometry restoration, rotation/resize handling, input-coordinate correctness, and session correlation behavior.
- Require authoritative `source: "game"` screenshots from the active GameAbility root viewport with `session_id` and `request_id`; never substitute an editor image or include editor/system chrome.
- Preserve explicit fullscreen real run as the mandatory final Stage 4 release/fullscreen QA path.
- Add tablet-first acceptance, 2-in-1 regression coverage, phone-default compatibility, runtime longevity, and project/scene byte-immutability checks.
- Do not implement Embedded Game View, `FEATURE_WINDOW_EMBEDDING`, `embed_process`, SubViewport simulation, privileged window-manager configuration, or manual system-toolbar conversion as acceptance behavior.

## Capabilities

### New Capabilities

- `windowed-real-run-presentation`: Device-aware presentation selection and capability reporting for authoritative GameAbility runs, including lifecycle integration, geometry, capture provenance, failure semantics, and tablet-first acceptance.

### Modified Capabilities

- `game-dev-workflow-standards`: Make AI-safe windowed real run the recommended iterative QA presentation while retaining explicit fullscreen GameAbility evidence for final Stage 4 acceptance.

## Impact

- Godot MCP/editor plugin command schemas, routing, execution-state reporting, UI preferences, and screenshot metadata under `editor/plugins/godot_mcp/`.
- HarmonyOS `EditorAbility` to `GameAbility` launch options and lifecycle bridge under `platform/openharmony/template/entry/src/main/ets/`.
- GameAbility window creation/presentation, legal geometry, surface resize, rotation, focus, close, and crash handling.
- Device validation on a target tablet as the primary acceptance device, the currently connected 2-in-1 as a regression device, and phone behavior where available.
- No mutation of `project.godot`, `.tscn`, Autoload settings, export configuration, or game source files.
- Depends only on public HarmonyOS application window-management capabilities available to the installed device/system configuration; inability to provide floating or split presentation on the target tablet is reported as a platform blocker, not hidden by fullscreen fallback.
