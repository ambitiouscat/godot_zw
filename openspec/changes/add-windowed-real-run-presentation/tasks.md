## 1. Baseline and Prerequisite Gate

- [ ] 1.1 Wait for the separately requested Gemini rollback to finish, then inventory the real-run command, lifecycle, capture, and HarmonyOS bridge paths; verify this change starts from a real-GameAbility baseline and does not invoke, restore, or depend on SubViewport simulation. If that prerequisite is not true, stop and reconcile the rollback separately before editing this change.
- [ ] 1.2 Record baseline automated-test results and byte hashes for `project.godot` and all `.tscn` files, and preserve unrelated user changes in the dirty worktree.
- [ ] 1.3 Compile a minimal API-18 type check for the available `startAbility` / `startAbilityForResult` StartOptions overloads, WindowStage supported-mode APIs, main-window `recover()`, and observable window-status APIs; record the supported public path and reject any restricted/system-only alternative.

## 2. MCP Presentation Contract and Editor Preference

- [ ] 2.1 Extend real `run_*` command schemas with `auto | windowed | floating | split | fullscreen`, validation errors, requested/resolved/actual response fields, and `windowed` as the documented recommended MCP value.
- [ ] 2.2 Implement invocation-source-aware normalization so an omitted MCP/AI parameter resolves to `windowed`, an explicit parameter wins, and a human Editor action uses the device-local selector with default `Auto`.
- [ ] 2.3 Add a presentation-capability query/introspection response containing device category, concrete supported modes with probe confidence, `recommended_presentation: "windowed"`, recommendation reason, capability source, constraints, display/work-area data, and cache generation.
- [ ] 2.4 Add the human Editor selector `Auto / Windowed / Floating / Split / Fullscreen` and persist it only in Editor/application-local settings, never in the opened project.
- [ ] 2.5 Add command-schema/router tests for all enum values, invalid values, default-source precedence, aliases, capability output, and the breaking omitted-MCP default.

## 3. Unified Real-Run Session and Lifecycle

- [ ] 3.1 Extend the real-run session envelope with immutable requested presentation, resolved policy, attempted presentations, actual presentation, window rectangle, device/capability generation, `session_id`, `operation_id`, and `boot_nonce`.
- [ ] 3.2 Keep execution limited to `IDLE`, `REAL_STARTING`, `REAL_RUNNING`, `REAL_STOPPING`, and `RECONCILING`; make READY depend on both engine/surface readiness and verified actual presentation rather than editor foreground or launch-Promise acceptance.
- [ ] 3.3 Implement idempotent identical starts, stale-event rejection, `RUN_CONFLICT` for a different scene or presentation, and stop-then-start semantics for presentation changes without live mode conversion.
- [ ] 3.4 Add lifecycle tests for READY ordering, retry deduplication, conflicting starts, stale session/nonce events, ambiguous launch reconciliation, stop ordering, and sessions lasting more than 30 seconds without a guessed reset timer.

## 4. HarmonyOS Presentation Adapter

- [ ] 4.1 Update GameAbility manifest/window declarations for public fullscreen, split, and floating support while retaining landscape multi-window preference and phone/tablet/2-in-1 packaging compatibility.
- [ ] 4.2 Implement typed capability discovery using device type, API/syscap availability, WindowStage support, current display/legal work area, and advertised-versus-verified probe evidence with cache invalidation.
- [ ] 4.3 Implement strict tablet `windowed`/`auto` selection as floating request and verification, then split request and verification, then `PRESENTATION_UNAVAILABLE`; never continue to fullscreen.
- [ ] 4.4 Implement 2-in-1 `auto`/`windowed` as verified native resizable-window behavior and phone `Auto` as fullscreen, while keeping explicit `floating`, `split`, and `fullscreen` requests strict.
- [ ] 4.5 Implement GameAbility-side presentation setup before READY: supported WindowStage modes plus verified `recover()` for floating, API-18 StartOptions for split, and fullscreen layout/system-bar handling only for explicit fullscreen or phone `Auto`.
- [ ] 4.6 Return `PRESENTATION_UNAVAILABLE`, `PRESENTATION_DISABLED`, `PRESENTATION_START_REJECTED`, or `PRESENTATION_VERIFY_FAILED` with attempted modes and capability evidence; if a prohibited fullscreen window appears during `windowed`, terminate and reconcile that session before returning failure.
- [ ] 4.7 Add ArkTS unit/contract tests or injectable adapter tests for device policy, capability freshness, request ordering, actual-mode verification, strict explicit modes, and every failure code.

## 5. Cross-Process Lifecycle and Cleanup

- [ ] 5.1 Pass `session_id`, `operation_id`, `boot_nonce`, target scene/run arguments, and presentation request through EditorAbility-to-GameAbility launch data and correlate PRESENTATION_READY, geometry, stop, exit, and crash events on return.
- [ ] 5.2 Preserve `startAbilityForResult` exit observation only where the API-18 overload supports the required StartOptions; otherwise use the supported launch overload and make the explicit correlated lifecycle channel authoritative.
- [ ] 5.3 Remove any guessed duration-based run-state reset and implement deterministic `stop_project`, runtime-window close, GameAbility crash, Editor exit cleanup, and Editor focus restoration with terminal outcomes.
- [ ] 5.4 Add cross-process tests for callback/Promise reordering, close-button exit, explicit stop, crash, Editor foreground without game death, Editor shutdown, orphan prevention, and recovery from an uncertain launch result.

## 6. Geometry, Surface, and Input Correctness

- [ ] 6.1 Implement first-launch legal geometry and per-device/display persistence of only confirmed floating/native rectangles in application-local settings.
- [ ] 6.2 Revalidate, clamp, or discard stored geometry after rotation, display/work-area change, window-status change, or reconnect so the runtime cannot restore offscreen.
- [ ] 6.3 Drive the Godot XComponent surface and mouse/touch/hover coordinate conversion from one current content rectangle plus geometry generation across floating, split, native-window, resize, and rotation events.
- [ ] 6.4 Add deterministic geometry/input tests with edge and corner targets, multiple resizes, rotation, stale-generation events, and restoration on a changed work area.

## 7. Authoritative Game Screenshot Path

- [ ] 7.1 Route `take_screenshot(source: "game")` only to the matching GameAbility root-viewport capture service and exclude EditorAbility, system chrome, and system-composited cropping.
- [ ] 7.2 Return atomically committed capture data with `session_id`, unique `request_id`, `boot_nonce`, actual presentation, backend, dimensions, timestamp, and integrity hash; terminate pending requests with their session.
- [ ] 7.3 Add tests for floating and fullscreen captures, concurrent requests, stale response rejection, session end during capture, backend failure, and the absolute prohibition on editor/preview/system fallback.

## 8. Build, Security, and Source Immutability

- [ ] 8.1 Run the Godot MCP contract/lifecycle/screenshot test suites and the pinned HarmonyOS API-18 debug build; resolve all static typing, schema, and packaging failures without weakening the specified policy.
- [ ] 8.2 Audit the implementation to confirm it does not enable `FEATURE_WINDOW_EMBEDDING`, call `embed_process`, use restricted window APIs, require privileged signing/root, edit system window-manager configuration, or rely on a manual system toolbar.
- [ ] 8.3 Run clean-project start, resize, capture, stop, close, and crash scenarios and verify the post-run byte hashes of `project.godot` and every `.tscn` match the recorded baseline with no temporary Autoload or export-setting mutation.
- [ ] 8.4 Update MCP command documentation, workflow guidance, and device-validation instructions so AI clients see `windowed` as recommended while human UI remains `Auto` and final Stage 4 remains explicit fullscreen.

## 9. Device Verification and Approval Gate 2

- [ ] 9.1 On the currently connected HarmonyOS 2-in-1, verify native-window real run, complete scripts/audio/input/rendering, resize and geometry persistence, >30-second longevity, stop/close/crash convergence, authoritative game capture, and explicit fullscreen; label this as regression evidence only.
- [ ] 9.2 Pause device acceptance until the user replaces the connection with the target tablet, then record its exact device category, system/window capability evidence, display work area, and capability-generation result before launching.
- [ ] 9.3 On the target tablet, verify automatic MCP-default `windowed` launch chooses floating or split while EditorAbility stays visible and controllable, with no manual toolbar conversion and no transient result misreported as success.
- [ ] 9.4 On the target tablet, exercise dynamic gameplay, audio, Input Map actions, scene transition, resize, rotation, edge/corner coordinates, restored/clamped geometry, >30-second longevity, stop, close, crash, and authoritative floating/split capture.
- [ ] 9.5 If the target tablet supports neither automatic floating nor split through public application APIs, record `PRESENTATION_UNAVAILABLE` evidence, leave tablet acceptance incomplete, and report the platform blocker instead of silently using fullscreen; propose Embedded Game View research only as a separate future change.
- [ ] 9.6 Verify phone `Auto` remains fullscreen and explicit unsupported `windowed` fails without fullscreen fallback when a phone target is available; otherwise record the unexecuted device case without fabricating evidence.
- [ ] 9.7 Run a separate explicit fullscreen GameAbility session on the target tablet, capture authoritative final Stage 4 evidence, present the device matrix and lifecycle/capture/immutability results at Approval Gate 2, and mark implementation complete only after the gate is satisfied.
