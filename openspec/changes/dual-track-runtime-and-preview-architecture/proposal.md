## Why

The custom editor-viewport simulation cannot reproduce a standalone Godot run safely or faithfully. If project scripts are suppressed, dynamic gameplay is missing; if ordinary game scripts are forced into the editor process, they can mutate the editor SceneTree, Autoload state, project settings, and scene files. Maintaining that path creates a second, misleading execution model.

This change therefore supersedes the earlier dual-track design. It removes the simulation track and makes standalone `GameAbility` the only gameplay runtime and the only source accepted for functional and Stage 4 visual QA. The normal editor viewport remains available for static scene inspection.

## What Changes

- **BREAKING** Remove `InEditorGameRunner`, its SubViewport overlay/HUD/input proxy, all `simulate_*` commands, `stop_simulation`, preview lifecycle states, and `take_screenshot(source="preview")`.
- Route `run_project`, `run_scene`, and `run_current_scene` exclusively to standalone `GameAbility`; route `stop_project` exclusively to the active real-run session.
- Replace inferred editor play state with a real-only lifecycle coordinator driven by correlated `GameAbility` events.
- Correlate every lifecycle event with `session_id`, `operation_id`, and `boot_nonce`; stale or mismatched events cannot change state.
- Remove duration-based process resets. Transition timeouts enter reconciliation but never terminate or clear a confirmed healthy run.
- Keep screenshot sources strictly limited to `editor` and `game`, with no cross-source or system-screen fallback.
- Remove project Autoload/`ProjectSettings.save()` instrumentation. Runtime inspection, input, and capture use run-scoped transport or return an explicit capability error.
- Keep windowed/embedded runtime presentation as a separate change; this change first restores one correct authoritative runtime.

## Capabilities

### New Capabilities

- `game-ability-runtime-control`: Authoritative standalone `GameAbility` execution, correlated lifecycle, and strict capability-gated runtime services/capture.

### Modified Capabilities

- `game-dev-workflow-standards`: Stage 4 functional and visual acceptance must use `GameAbility`; editor screenshots are static inspection evidence only.

## Impact

- `editor/plugins/godot_mcp/`: command schema/router, lifecycle coordinator, runtime capability gates, plugin initialization, and tests.
- `platform/openharmony/`: launch metadata and correlated Ability lifecycle events.
- `platform/openharmony/template/editor/.../rawfile/`: packaged mirror must exactly match the source add-on and must not retain obsolete simulation assets.
- OpenSpec and active documentation: remove dual-track/preview claims and record only evidence-backed completion.
