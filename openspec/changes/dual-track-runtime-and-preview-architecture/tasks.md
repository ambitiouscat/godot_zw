## 1. Contract and Change Reconciliation

- [x] 1.1 Treat `godot_zw/openspec` as the canonical OpenSpec root and confirm the workspace-level duplicate is not used by apply or archive commands.
- [x] 1.2 Review `improve-godot-mcp-runtime-qa`; preserve its introspection and log-relay work, and document that this change supersedes its screenshot source/fallback semantics.
- [x] 1.3 Add machine-readable command schemas for every canonical command, alias, parameter, response field, lifecycle status, and stable error code in this change.
- [x] 1.4 Add contract tests that fail if any `play_*` alias routes to preview, any stop command targets the wrong track, or any screenshot source is reinterpreted.
- [x] 1.5 Record the Approval Gate 1 decision before editing runtime, editor, bridge, or packaging code.

## 2. Lifecycle Coordinator and State Model

- [x] 2.1 Implement a typed `LifecycleCoordinator` with the stable and transitional states defined in `design.md` and make it the only lifecycle-state writer.
- [x] 2.2 Implement UUID `session_id`, retry-safe `operation_id`, random `boot_nonce`, `event_id`, bounded deduplication caches, and normalized-argument comparison.
- [x] 2.3 Implement one serialized reducer/executor for mutating commands and bridge events, including deterministic handling of commands received during transitions.
- [x] 2.4 Implement `conflict_policy` and deprecated `preempt` normalization, reserving `pending_session_id` for composite preemption without releasing the operation lock.
- [x] 2.5 Implement start-during-stop, stop-during-start, repeated start, repeated stop, stale event, duplicate event, and operation-ID collision behavior.
- [x] 2.6 Implement configurable start/stop handshake timeouts, rollback outcomes, and `RECONCILING` without any timer that limits a confirmed RUNNING session.
- [x] 2.7 Implement `get_execution_state` with every required state, correlation, target, capability, error, timestamp, cancellation, and last-session field.
- [x] 2.8 Add state-machine unit tests with a fake clock and fake preview/Ability backends for every stable, transitional, failure, cancellation, and preemption path.

## 3. Command Router, Aliases, and Entry-Point Unification

- [x] 3.1 Restore `run_project`, `run_scene`, and `run_current_scene` to the real editor play handlers and make accepted starts report `starting`, not `running`, before READY.
- [x] 3.2 Register `simulate_project`, `simulate_scene`, `simulate_current_scene`, and `stop_simulation` as the only canonical preview lifecycle commands.
- [x] 3.3 Route `stop_project` only to real run and implement wrong-track conflict, expected-session validation, duplicate-stop idempotency, and `already_stopped` behavior.
- [x] 3.4 Implement the complete stable/deprecated alias table and return `deprecated_alias`, `replacement`, and deprecated-parameter metadata.
- [x] 3.5 Route the editor preview toolbar, preview HUD, Godot editor play/stop callbacks, and MCP commands through `LifecycleCoordinator`; remove all direct runner/state-reset calls.
- [x] 3.6 Update `list_methods` and method documentation so canonical commands, aliases, source enums, conflict policy, save policy, response schemas, and error codes are discoverable.
- [x] 3.7 Add router integration tests for every canonical command and alias in `IDLE`, both RUNNING states, all transitional states, and `RECONCILING`.

## 4. Script-Free, Non-Mutating Preview

- [x] 4.1 Remove all writes and restoration writes involving the edited root's `visible`, `process_mode`, ownership, transforms, or other persistent properties.
- [x] 4.2 Remove `_upgrade_to_tool_scripts`, generated in-memory `@tool` scripts, the `SceneTree.node_added` rewrite hook, and project Autoload instantiation from preview.
- [x] 4.3 Implement a `SceneState`-based visual clone that recreates serialized native nodes/resources without project scripts and produces placeholders plus warnings for unsupported custom types.
- [x] 4.4 Return preview capability flags and structured script/custom-type warnings from all `simulate_*` commands and `get_execution_state`.
- [x] 4.5 Keep the independent backdrop, `SubViewport.own_world_3d`, resize tracking, focus ownership, coordinate scaling, and editor-input occlusion without claiming background render suspension.
- [x] 4.6 Emit `PREVIEW_READY` only after the clone, SubViewport, overlay, HUD, and input proxy are active; emit `PREVIEW_STOP_ACK` only after their complete removal.
- [x] 4.7 Restrict preview inspection/manipulation to the active correlated visual clone, report placeholder limitations, and reject real-mode or stale-session access.
- [x] 4.8 Implement `take_screenshot(source="preview")` from the active SubViewport with strict preview provenance and no cross-source fallback.
- [x] 4.9 Add preview tests for scripted scenes, `@tool` scripts, custom classes, Autoload references, resize, repeated start/stop, input non-leakage, cleanup, and edited-root immutability.

## 5. OpenHarmony Real-Run Lifecycle Bridge

- [x] 5.1 Implement the one-shot in-memory run-metadata bridge for `session_id`, `operation_id`, `boot_nonce`, and project fingerprint without using project settings, editor settings, environment variables, or unknown game argv.
- [x] 5.2 Propagate and validate run metadata through the native OpenHarmony bridge, `BridgeCallbacks`, the GameAbility Want, `AbilityState`, and all lifecycle notifications.
- [x] 5.3 Remove the 15-second run-state reset from `BridgeCallbacks.ets` while retaining only bounded startup/stop handshake timers owned by the coordinator.
- [x] 5.4 Emit `REAL_READY` only after matching GameAbility metadata, WindowStage, Godot surface, requested scene, and first-frame readiness are confirmed.
- [x] 5.5 Implement session-correlated explicit stop delivery, `REAL_STOP_ACK`, and `REAL_EXIT`, and treat `startAbilityForResult`/WindowStage duplicates idempotently.
- [x] 5.6 Handle launch rejection, user close/back, engine exit, explicit stop, crash/system kill evidence, and editor foreground reconciliation without unconditional state reset.
- [x] 5.7 Add ArkTS/native/GDScript bridge tests proving that events from session A cannot start, stop, reset, or complete session B.

## 6. GameAbility Capture Agent and Correlated IPC

- [x] 6.1 Run a two-process spike that proves whether EditorAbility and GameAbility share the chosen app-private `filesDir`; if not, select the predefined authenticated loopback transport without changing the protocol envelope.
- [x] 6.2 Extract reusable XComponent snapshot and PNG code into a run-scoped `GameAbilityCaptureAgent` that starts only for valid MCP run metadata and never requires a project Autoload.
- [x] 6.3 Implement GameAbility-only watermark/frame-sequence verification and the native root-Viewport capture backend for devices where XComponent snapshot is black, stale, or unsupported.
- [x] 6.4 Implement per-session `manifest`/`ready` files and per-request request/ACK/frame/response records with protocol version, session, nonce, request, deadline, and provenance fields.
- [x] 6.5 Implement same-directory temporary writes, flush/close, atomic rename, response-as-commit-marker ordering, safe relative filenames, and exact-session cleanup.
- [x] 6.6 Implement a bounded serialized capture queue with concurrent waiters, out-of-order responses, cancellation on session exit, and no request-ID reuse.
- [x] 6.7 Validate response schema, session, nonce, request, timestamps, path containment, PNG signature, byte count, dimensions, and SHA-256 before returning an artifact.
- [x] 6.8 Implement strict `editor`/`preview`/`game` source routing, actual-source/backend/provenance responses, stable capture errors, and removal of every editor fallback path.
- [x] 6.9 Remove MCP screenshot Autoload injection and standalone dependence on `mcp_screenshot_service.gd` editor-feature behavior after the GameAbility capture path passes integration tests.
- [x] 6.10 Add capture tests for ready-before-capture, two concurrent requests, busy queue, ACK timeout, capture timeout, corrupt/partial file, stale session, late response, stop during capture, backend failure, and path traversal.

## 7. Save Policy and Immutability

- [x] 7.1 Replace implicit `EditorInterface.save_scene()` calls in canonical start commands with `save_policy: "require_clean"` and explicit `save_policy: "save"` preflight behavior.
- [x] 7.2 Return `UNSAVED_CHANGES` without launching when clean preflight fails, and establish the execution/hash baseline only after an explicit save succeeds.
- [x] 7.3 Remove temporary MCP Autoload writes from `ProjectSettings` and prove that runtime instrumentation uses only run metadata and app-private session storage.
- [x] 7.4 Add automated clean-baseline SHA-256 comparison for `project.godot` and all `.tscn` files across preview, real run, capture, stop, failure, and preemption flows.
- [x] 7.5 Add preview assertions for edited-root properties, owner, transforms, visibility, process mode, dirty flag, focus, and runner-hook restoration.

## 8. Protocol, Skill, and Compatibility Documentation

- [x] 8.1 Update `AGENTS.md`, `CLAUDE.md`, `GODOT_GAME_DEV_PROTOCOL.md`, and MCP command documentation with the canonical API, alias migration, state model, save/conflict policies, and preview limitations.
- [x] 8.2 Update `godot-game-gen` and `godot-visual-qa` so Stage 4 requires real-run session and GameAbility provenance and preview cannot satisfy functional acceptance.
- [x] 8.3 Remove remaining `1:1 parity`, guaranteed 60 FPS script execution, complete Autoload/input equivalence, background render suspension, and 15-second process-kill wording from active docs and runtime messages.
- [x] 8.4 Document all response examples and error recovery actions, including how clients poll `get_execution_state` after an accepted asynchronous operation.
- [x] 8.5 Add a migration note for clients that previously used `play_*`/`stop_project` as preview controls and direct them to `simulate_*`/`stop_simulation`.

## 9. Packaging and Automated Verification

- [x] 9.1 Run GDScript parsing/static checks, ArkTS checks, and the lifecycle/router/preview/capture test suites; preserve logs and machine-readable reports.
- [x] 9.2 Synchronize source MCP assets into the OpenHarmony rawfile package, verify source-to-package hashes, and ensure obsolete injected-service assets are not referenced.
- [x] 9.3 Build the signed HAP through the repository packaging pipeline and record build inputs, output path, hashes, and warnings.
- [x] 9.4 Install the HAP on the target tablet and verify method introspection exposes the canonical schemas and deprecated aliases.

## 10. Device Acceptance and Approval Gate 2

- [x] 10.1 Verify all canonical start/stop routes and aliases against the actual overlay/GameAbility window, response mode, state, session, and deprecation metadata.
- [x] 10.2 Verify default conflict rejection and explicit preemption in both directions, including stop failure, stop timeout, target-start failure, rapid run-stop-run, and stale READY/EXIT events.
- [x] 10.3 Run a real session for at least 60 seconds; at 30 and 60 seconds confirm `REAL_RUNNING`, capture a valid GameAbility frame, and then stop through matching ACK and EXIT.
- [x] 10.4 Verify explicit stop, user back, window close, startup failure, crash/system kill evidence, editor foreground, and editor restart/reconciliation leave no orphan or falsely cleared session.
- [x] 10.5 Verify editor, preview, and game screenshot sources with session watermark/frame progression, concurrent requests, corrupt/stale responses, backend selection, and zero cross-source fallback.
- [x] 10.6 Verify script-free preview on representative 2D, 3D, and UI scenes; validate resize, input non-leakage, placeholder warnings, complete cleanup, and no edited-root mutation.
- [x] 10.7 Establish a clean saved baseline and prove `project.godot` plus all `.tscn` hashes remain unchanged after preview and real-run acceptance sequences.
- [x] 10.8 Validate gameplay, physics, Input Map, touch, audio, Autoload, and multi-scene behavior only in real run and attach the resulting logs and GameAbility screenshots.
- [x] 10.9 Present the device evidence, known limitations, task status, and visual QA analysis at Approval Gate 2; do not archive before user approval.

