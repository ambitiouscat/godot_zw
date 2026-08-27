## Context

See `proposal.md` for motivation and the capability specs for observable behavior.

The verified HarmonyOS baseline already separates `EditorAbility` and `GameAbility` into `:editor` and `:game` processes and targets HarmonyOS 5.1 / API 18 for phone, tablet, and 2-in-1. `BridgeCallbacks.ets` currently launches GameAbility with `startAbilityForResult(want)` without presentation options. `GameAbility.ets` then calls `setWindowLayoutFullScreen(true)` on phone and tablet. `GameWindow.ets` already observes window-size and ArkUI area changes and resizes the Godot XComponent surface, which is the correct base for resizable presentation.

Godot's OpenHarmony `DisplayServer` does not advertise process embedding and the platform `OS::create_instance` path does not provide a real child-process handle suitable for `embed_process`. Therefore this change operates on the existing standalone GameAbility window; it does not claim that the process is embedded in Godot Game View.

The repository currently contains an unarchived historical runtime/preview change whose proposal and deltas are inconsistent, and current code inspection still finds preview states in the lifecycle coordinator. Gemini's separately requested rollback/removal work is a prerequisite: implementation of this change must first verify the real-run-only baseline and must not repair, restore, or depend on the old preview change implicitly.

The public HarmonyOS multi-window documentation supports these implementation directions:

- UIAbility `supportWindowMode` declares fullscreen, split, and floating support, and `preferMultiWindowOrientation` declares the landscape multi-window preference.
- API-level split launch uses `StartOptions.windowMode` with primary or secondary split modes.
- On tablet and 2-in-1, a WindowStage can declare supported modes and a main window can use `recover()` to enter a floating window when the device/system allows it.

These are capability declarations and requests, not guarantees. The target tablet must verify the actual result before the session reports READY.

## Goals / Non-Goals

**Goals:**

- Preserve complete standalone GameAbility execution while selecting and observing its top-level HarmonyOS presentation.
- Keep EditorAbility visible for AI iteration on a tablet through an explicit, strict `windowed` policy.
- Make requested policy, attempted modes, actual presentation, geometry, lifecycle, and capture provenance machine-observable and session-correlated.
- Keep implementation compatible with API 18 and limited to public application-scope APIs.
- Maintain the existing 2-in-1 native-window experience and phone's human `Auto` fullscreen default.

**Non-Goals:**

- Rendering real execution into Godot's internal Game View or enabling Godot process embedding.
- Restoring or improving the SubViewport simulation runner.
- Live conversion of an active run between presentation modes; callers stop and start a new session.
- Changing system free-window configuration, using root/system signing, or relying on restricted window APIs.
- Treating manual system-toolbar conversion as successful automation.
- Redesigning gameplay UI for arbitrary aspect ratios beyond making the Godot surface and input mapping follow the actual content area.

## Decisions

### 1. Keep execution backend and presentation orthogonal

There is one execution backend: standalone GameAbility. `presentation` is immutable metadata on that real session, not an execution mode and not a second state machine. This retains the complete engine environment and prevents a return to unsafe editor-process script execution.

Alternative considered: use SubViewport or `@tool`-rewritten scripts inside the editor. Rejected because it cannot safely reproduce arbitrary project scripts, Autoloads, scene changes, input, audio, and lifecycle.

Alternative considered: expose `FEATURE_WINDOW_EMBEDDING` and call `embed_process`. Rejected because the OpenHarmony backend lacks the required process/window-handle contract; advertising it would create a false capability.

### 2. Normalize request policy separately from actual presentation

The command layer uses these types:

```text
RequestedPresentation = auto | windowed | floating | split | fullscreen
ResolvedPolicy        = auto | windowed | strict_floating | strict_split | strict_fullscreen
ActualPresentation    = floating | split | native_window | fullscreen
```

Resolution precedence is:

1. An explicit API parameter.
2. For an MCP/AI call with no parameter, `windowed`.
3. For a human Editor action with no explicit override, the device-local UI preference, default `Auto`.
4. The device policy table below.

`windowed` never appears as `actual_presentation`; it is a policy that selects a concrete non-fullscreen result. Returning both requested and actual values prevents an AI from assuming that a request was honored exactly.

| Device category | `auto` | `windowed` | Explicit concrete mode |
|---|---|---|---|
| Tablet | floating → split → error | floating → split → error | Strict; no substitution |
| 2-in-1 | native window → error | native window → error | Strict; no substitution |
| Phone | fullscreen | floating → split → error | Strict; no substitution |
| Unknown | capability-driven, no unsafe assumption | floating → split → error | Strict; no substitution |

Alternative considered: allow `windowed` to fall back to fullscreen so every run starts. Rejected because fullscreen takeover defeats the AI-control requirement and masks capability failure.

### 3. Add a two-stage HarmonyOS presentation adapter

The ArkTS bridge owns a typed presentation adapter with two stages:

1. **Discover and request**: inspect device type, relevant system capabilities/API availability, declared WindowStage modes, display work area, and cached probe evidence. Construct only legal public launch/window requests.
2. **Verify**: after GameAbility creates and loads its main window, observe actual window status and geometry. READY is emitted only after the Godot surface is initialized and the concrete presentation is confirmed.

For split presentation, the adapter uses the API-18-supported `StartOptions.windowMode` primary/secondary split request where available. If the API 18 type surface does not provide a `startAbilityForResult` overload with StartOptions, launch uses the supported `startAbility(want, options)` overload and the explicit session lifecycle channel becomes the terminal authority; exit detection must not be weakened merely to keep the Promise pattern.

For floating presentation, GameAbility declares/sets floating as a supported WindowStage mode on tablet or 2-in-1 and requests `recover()` on its main window before reporting READY. The adapter validates the observed non-fullscreen status and window rectangle. Merely calling `recover()` is not success.

For fullscreen, the existing full-layout and system-bar behavior is applied only for an explicit fullscreen resolution or phone `Auto`. Window layout fullscreen is treated as content/window presentation configuration, not evidence by itself; observed status and geometry still populate the session result.

`module.json5` explicitly declares GameAbility support for the intended fullscreen, split, and floating modes and retains landscape multi-window preference. Device-specific policy remains runtime logic because static manifest fields cannot express the required per-device defaults.

Alternative considered: trust manifest declarations as capability discovery. Rejected because system free-window configuration and device policy can still reject or alter a request.

### 4. Expose capability evidence with confidence and freshness

The capability provider returns a versioned record containing:

```text
device_category
supported_presentations[]
recommended_presentation = windowed
recommendation_reason
capability_source
constraints[]
probe_status per presentation
display_id and legal_work_area
observed_at and cache_generation
```

Static/API discovery yields `advertised` support. A successful on-device presentation yields `verified` support for the current device/configuration generation. Rejection yields a stable constraint and invalidates optimistic cache data. Rotation, display change, lifecycle recreation, relevant configuration change, or device reconnect increments the generation.

The external `supported_presentations` list includes only verified or presently requestable public modes and includes confidence/probe metadata; it does not claim unconditional support based solely on device category.

Alternative considered: hard-code tablet = floating and 2-in-1 = window. Rejected because HarmonyOS free-window availability is system-configuration dependent.

### 5. Extend the real-run session envelope and READY handshake

The lifecycle coordinator stores one typed session envelope:

```text
session_id, operation_id, boot_nonce
target_scene
requested_presentation, resolved_policy, attempted_presentations
actual_presentation, window_rect
device_category, capability_generation
state, transition_time, terminal_outcome
```

The command router validates and normalizes presentation before requesting a session. The bridge passes `session_id`, `boot_nonce`, scene/run arguments, and requested policy to GameAbility. GameAbility sends correlated PRESENTATION_READY, geometry, capture, stop, exit, and crash evidence back. READY requires both engine/surface readiness and presentation verification.

`startAbilityForResult` may remain a useful exit signal where its required overload is available, but it is not readiness proof and is not the sole liveness source. Editor foreground events do not imply GameAbility death. Any ambiguous launch rejection, missing window callback, or callback/Promise disagreement moves the coordinator to `RECONCILING` until actual ownership is established.

An identical idempotent request reuses the operation/session result. A different target scene or normalized presentation while starting/running returns `RUN_CONFLICT`. Presentation changes are implemented as confirmed stop followed by a fresh start; there is no live window-mode mutation API in this change.

Alternative considered: model each presentation as a state. Rejected because it multiplies transitions and allows lifecycle and window status to diverge.

### 6. Make launch failure atomic and errors diagnostic

The adapter records attempted presentations in order and verifies after each accepted request. A failed request must establish whether a GameAbility was created before returning:

- `PRESENTATION_UNAVAILABLE`: no legal requested/fallback mode is exposed.
- `PRESENTATION_DISABLED`: device class/API advertises the mode but current system policy disables it.
- `PRESENTATION_START_REJECTED`: StartOptions or the runtime window request is rejected.
- `PRESENTATION_VERIFY_FAILED`: a window starts but actual presentation cannot be confirmed or violates the policy.
- `RUN_CONFLICT`: an incompatible session already owns the runtime.

If a prohibited fullscreen GameAbility appears during `windowed` launch, the bridge stops that correlated session, reconciles its terminal event, and returns `PRESENTATION_VERIFY_FAILED`; it never returns success with fullscreen metadata.

### 7. Store only confirmed, device-local window preferences

Human presentation preference, last valid floating/native rectangle, and capability cache live in Editor/application-local preferences keyed by device identity and display characteristics. They are never written to the opened Godot project.

The initial floating rectangle comes from the system or is clamped to the legal work area. Geometry is persisted only after the OS confirms it. `windowSizeChange`, area change, display/orientation change, and window-status callbacks update the Godot surface and session geometry. On restore, stale/offscreen rectangles are clamped or discarded. Split and fullscreen do not reuse arbitrary floating coordinates.

Alternative considered: save presentation in `project.godot` so it follows the project. Rejected because this is a debugging-device preference and would pollute user projects and source hashes.

### 8. Keep render surface and input in one coordinate space

The existing XComponent size/area callbacks remain the authority for the game content rectangle. All touch, mouse, and hover coordinates are converted into physical pixels relative to the same current ArkUI content area supplied to the Godot surface. Geometry generation numbers prevent an event measured against an old rectangle from being applied as if it belonged to a newer layout.

Resize and rotation tests use a scene with deterministic edge/corner targets and known Input Map actions, not only visual screenshots. Audio, physics, scripts, dynamic scene creation, and scene transitions run unchanged because GameAbility remains the real backend.

### 9. Capture inside GameAbility, never from the system composition

`take_screenshot(source: "game")` is routed to the matching GameAbility screenshot service. The service captures the Godot root viewport before operating-system chrome/composition and atomically returns the artifact with `session_id`, `request_id`, `boot_nonce`, actual presentation, dimensions, timestamp, and integrity hash. Pending requests end with their session.

A floating capture is authoritative iteration evidence for game pixels, while an explicit fullscreen capture remains mandatory final Stage 4 evidence. System screenshots that happen to show EditorAbility and GameAbility together may be retained as supplemental window-placement evidence, but never satisfy `source: "game"`.

Alternative considered: crop a system screenshot to the game window. Rejected because chrome, scaling, race conditions, and stale window geometry make provenance unreliable.

### 10. Keep UI and API defaults intentionally different

The Editor UI adds one device-local selector: `Auto / Windowed / Floating / Split / Fullscreen`, default `Auto`. MCP schema descriptions put `windowed` first as the recommended value and state why. Capability introspection returns the same recommendation so clients need not encode device policy themselves.

This intentional difference preserves familiar phone behavior for humans while protecting unattended AI sessions. Responses always expose the source of the default (`explicit`, `mcp_default`, or `editor_preference`) to remove ambiguity.

### 11. Validate the target tablet as a hard gate

The implementation sequence may compile and run first on the connected 2-in-1, but that proves only regression behavior. The change remains incomplete until the user connects the target tablet and the automatic floating→split policy is exercised. A system-toolbar conversion is diagnostic only. If neither public path works on that tablet, the result is a documented platform blocker and a separate Embedded Game View research change may be proposed.

Final Stage 4 validation uses a separate explicit fullscreen session so windowed iteration does not weaken release/fullscreen QA.

## Risks / Trade-offs

- **[Risk] API 18 exposes split launch but floating may require post-create `recover()`, causing a transient fullscreen or focus takeover.** → Verify window status before READY and fail tablet acceptance if automatic launch cannot keep EditorAbility available; do not hide the issue with a successful response.
- **[Risk] Device type and manifest support overstate actual system free-window availability.** → Use two-stage advertised/verified capability evidence and stable failure codes, with target-device probes.
- **[Risk] `startAbilityForResult` and presentation StartOptions overloads differ on the API 18 SDK.** → Compile against the pinned SDK first; use the supported launch overload plus the explicit correlated lifecycle channel rather than removing presentation control or inventing a signature.
- **[Risk] Editor/Game processes observe callbacks out of order.** → Require `session_id` and `boot_nonce`, serialize mutating operations, ignore stale events, and reconcile ambiguous ownership.
- **[Risk] Resizing exposes stale render or input coordinates.** → Use a shared content rectangle/generation for surface size and input conversion and test corners after every geometry change.
- **[Risk] Persisted geometry becomes invalid after rotation, display change, or system layout changes.** → Revalidate against current legal work area and discard/clamp invalid rectangles.
- **[Risk] A healthy long-running game is mistaken for a failed launch.** → Remove guessed session-duration resets; use explicit READY/EXIT/crash evidence and a >30-second longevity test.
- **[Risk] Historical preview artifacts cause implementation to reintroduce or depend on simulation.** → Add a baseline preflight task and keep this change's code/test edits scoped to real run and Run Presentation.
- **[Trade-off] Strict no-fullscreen fallback means some tablets return an error instead of running.** → This is intentional: it preserves AI controllability and makes the real platform limitation visible.

## Migration Plan

1. **Baseline gate:** finish and verify the separate Gemini rollback. Confirm real `run_*` routes to GameAbility, no preview path is invoked by this change, and capture/lifecycle tests have a known baseline. Do not apply the inconsistent historical preview change as a dependency.
2. **Add contracts without changing defaults:** add typed presentation values, capability/introspection output, session fields, errors, and tests. Unknown/omitted values remain test-visible.
3. **Add HarmonyOS adapter:** declare supported GameAbility window modes, implement API-18 capability/request/verification paths, correlated lifecycle events, geometry, and capture metadata.
4. **Add Editor preference and enable default:** add the human selector, then change only MCP omitted-parameter resolution to `windowed` after automated schema/contract tests pass.
5. **Regression validation:** build/package/install and verify native-window, resize, lifecycle, screenshot, longevity, and immutability on the connected 2-in-1.
6. **Primary acceptance:** after the user connects the tablet, run the full automatic floating→split matrix. Record a platform blocker if both paths fail.
7. **Final QA:** run and capture an explicit fullscreen GameAbility session, present Approval Gate 2 evidence, and only then mark implementation tasks complete.

Rollback is code-only and device-local: revert the presentation adapter/default change and clear only the new application-local preference/cache keys. Project files require no migration or restoration. While rolled back, explicit or default real run returns to the prior standalone GameAbility behavior; the implementation must not retain a misleading `windowed` recommendation if the adapter is disabled.

## References

- [HarmonyOS multi-window support](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/multi-window-support-V5)
- [HarmonyOS free-window troubleshooting and device constraints](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/multi-faq-V13)
- [HarmonyOS PC/tablet floating-window configuration guidance](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-697)
- [Godot game embedding architecture](https://docs.godotengine.org/en/latest/tutorials/editor/game_embedding.html)
