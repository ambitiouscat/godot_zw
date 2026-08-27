## Purpose

Defines how authoritative standalone GameAbility sessions select, report, preserve, and verify floating, split, native-window, or fullscreen presentation on HarmonyOS devices without losing real Godot runtime behavior.

## ADDED Requirements

### Requirement: Real-Run Presentation API Contract
The system SHALL accept an optional `presentation` value of `auto`, `windowed`, `floating`, `split`, or `fullscreen` on every real `run_*` command. `windowed` SHALL represent an AI-safe non-fullscreen selection policy rather than a concrete operating-system window type. Every accepted start and execution-state response SHALL report `requested_presentation`, `resolved_policy`, `actual_presentation`, `session_id`, and target scene.

#### Scenario: AI omits presentation
- **WHEN** an MCP or AI client invokes a real `run_*` command through the HarmonyOS editor without `presentation`
- **THEN** the system resolves the request as `presentation: "windowed"` and reports that default explicitly

#### Scenario: Explicit request overrides defaults
- **WHEN** a client provides a valid explicit `presentation`
- **THEN** the system applies that value ahead of the MCP default and the human Editor preference

#### Scenario: Human starts a run from the Editor UI
- **WHEN** a human invokes Run with the device-local UI selection left at its default
- **THEN** the system uses `Auto` and does not reinterpret the action as the MCP-specific omitted-parameter default

### Requirement: Presentation Capability Discovery
The system SHALL query presentation support at runtime and SHALL expose the detected device category, supported concrete presentations, capability source, system constraints, and `recommended_presentation: "windowed"` with a reason stating that it keeps the editor visible and controllable during AI debugging. Cached capability results SHALL be invalidated when the device, display, windowing configuration, or application lifecycle makes them stale.

#### Scenario: Inspect capabilities before starting
- **WHEN** a client queries real-run capabilities on a connected HarmonyOS device
- **THEN** the response identifies the detected device category, supported presentations, recommendation, reason, constraints, and source of the capability result

#### Scenario: Capability state changes
- **WHEN** a previously cached presentation is no longer legal after a display, orientation, system-configuration, or device change
- **THEN** the system refreshes capabilities before accepting a new start and does not claim stale support

### Requirement: Device-Aware Presentation Selection
The system SHALL resolve presentation according to the detected device category and SHALL report the concrete result as `floating`, `split`, `native_window`, or `fullscreen`. On a tablet, `auto` and `windowed` SHALL try floating, then split, then fail. On a 2-in-1 device, `auto` and `windowed` SHALL preserve the platform's native resizable window behavior and fail if it cannot be obtained. On a phone, `auto` SHALL use fullscreen, while an explicit `windowed` request SHALL fail if neither floating nor split is supported. Explicit `floating`, `split`, and `fullscreen` requests SHALL be strict.

#### Scenario: Start AI-safe real run on a tablet
- **WHEN** a tablet receives `presentation: "windowed"` and supports floating presentation
- **THEN** the system starts the GameAbility as floating and reports `actual_presentation: "floating"`

#### Scenario: Fall back from floating to split on a tablet
- **WHEN** a tablet receives `presentation: "windowed"`, floating is unavailable, and split presentation is supported
- **THEN** the system starts the GameAbility in split presentation and reports `actual_presentation: "split"`

#### Scenario: Preserve 2-in-1 native window behavior
- **WHEN** a 2-in-1 device receives `presentation: "auto"` or `presentation: "windowed"` and native windowed execution is available
- **THEN** the system starts the complete GameAbility in its native resizable window and reports `actual_presentation: "native_window"`

#### Scenario: Preserve phone default compatibility
- **WHEN** a phone receives `presentation: "auto"`
- **THEN** the system starts the GameAbility fullscreen and reports `actual_presentation: "fullscreen"`

#### Scenario: Honor an explicit fullscreen request
- **WHEN** any supported device receives `presentation: "fullscreen"`
- **THEN** the system either starts fullscreen and reports it or returns a presentation-specific error without substituting another mode

### Requirement: No Silent Fullscreen Fallback
The system MUST NOT silently convert `windowed`, `floating`, or `split` into fullscreen. A failed presentation request SHALL return a stable error code, requested mode, attempted modes, capability evidence, and recovery guidance without reporting a running session.

#### Scenario: Tablet has no AI-safe presentation
- **WHEN** a tablet receives `presentation: "windowed"` and supports neither floating nor split presentation
- **THEN** the system returns `PRESENTATION_UNAVAILABLE`, does not start fullscreen, and identifies the missing platform capability

#### Scenario: System configuration disables an otherwise supported mode
- **WHEN** the device class supports the requested presentation but current system configuration disables it
- **THEN** the system returns `PRESENTATION_DISABLED` with the detected constraint and does not request privileged configuration changes

#### Scenario: Platform rejects launch options
- **WHEN** the operating system rejects the requested start presentation or legal launch options
- **THEN** the system returns `PRESENTATION_START_REJECTED`, reconciles whether a GameAbility was created, and does not claim success prematurely

### Requirement: Unified Real-Run Lifecycle
The system SHALL use only `IDLE`, `REAL_STARTING`, `REAL_RUNNING`, `REAL_STOPPING`, and `RECONCILING` for execution lifecycle. Presentation SHALL remain immutable session data and SHALL NOT create execution states such as `FLOATING_RUNNING` or a separate simulation track. A session SHALL enter `REAL_RUNNING` only after a matching GameAbility READY event confirms its actual presentation.

#### Scenario: Start remains transitional until ready
- **WHEN** a GameAbility launch is accepted but its matching READY event has not arrived
- **THEN** execution remains `REAL_STARTING` and reports the requested presentation without claiming an actual running presentation

#### Scenario: Window observation becomes uncertain
- **WHEN** EditorAbility foregrounding, a window callback gap, or a presentation callback failure makes the session's liveness uncertain
- **THEN** the system enters or retains `RECONCILING` until GameAbility liveness and actual presentation are verified

#### Scenario: Presentation metadata does not create another runtime
- **WHEN** a real session is reported as floating, split, native-window, or fullscreen
- **THEN** the execution mode remains real run and no preview or embedded runtime is started

### Requirement: Session Correlation, Idempotency, and Run Conflicts
The system SHALL correlate launch, READY, presentation, geometry, capture, stop, exit, and crash events with one immutable `session_id`. Repeating an identical normalized run operation SHALL return the existing operation or active session, while requesting a different scene or presentation during a run SHALL return `RUN_CONFLICT`. Changing scene or presentation SHALL require an observed stop followed by a new run.

#### Scenario: Retry the same start operation
- **WHEN** a client retries a start with the same operation identity and normalized scene and presentation
- **THEN** the system returns the existing operation or session and does not create another GameAbility

#### Scenario: Request a different presentation while running
- **WHEN** a real session is active and a client requests the same scene with a different presentation
- **THEN** the system returns `RUN_CONFLICT` and leaves the active session unchanged

#### Scenario: Ignore a stale lifecycle event
- **WHEN** a presentation, exit, or crash event belongs to an earlier session
- **THEN** the system records and ignores it without changing the current session

### Requirement: Deterministic Stop, Close, Crash, and Editor Exit
The system SHALL converge the matching real session to `IDLE` after an explicit `stop_project`, user closure of the runtime window, confirmed GameAbility crash, or Editor exit cleanup. Closing the runtime window SHALL return focus to EditorAbility when it remains alive. Editor shutdown SHALL not leave an associated GameAbility orphaned.

#### Scenario: Stop the active real run
- **WHEN** `stop_project` targets the active session
- **THEN** the system closes the matching GameAbility, observes its terminal event, and only then reports `IDLE`

#### Scenario: User closes the runtime window
- **WHEN** the user closes the active floating, split, native, or fullscreen GameAbility window
- **THEN** the session records a user-close outcome, returns to `IDLE`, and restores EditorAbility focus when possible

#### Scenario: Runtime crashes
- **WHEN** the active GameAbility terminates abnormally
- **THEN** the system reports a correlated crash outcome, cancels pending capture work, and reconciles to `IDLE` without a stale running flag

#### Scenario: Editor exits while a run is active
- **WHEN** the owning EditorAbility exits with an associated real session
- **THEN** the system requests cleanup of that session and reports any cleanup failure instead of intentionally leaving an orphan runtime

### Requirement: Legal Window Geometry and Device-Local Persistence
For floating or native-window presentation, the system SHALL use a system-legal initial rectangle, persist the last confirmed valid rectangle per device in Editor-local configuration, and restore it only after capability and display revalidation. The system SHALL clamp or replace geometry after resize, rotation, display, or available-area changes so the runtime remains reachable and visible. Presentation preferences and capability caches SHALL remain device-local.

#### Scenario: First floating launch
- **WHEN** no valid rectangle is stored for the connected device
- **THEN** the system uses a legal system-provided or system-constrained initial rectangle and reports the confirmed bounds

#### Scenario: Restore a previous window rectangle
- **WHEN** a later run has a stored rectangle that remains legal for the current display
- **THEN** the system restores that rectangle and reports the actual confirmed bounds

#### Scenario: Rotate or change available display area
- **WHEN** the display rotates or its legal work area changes while the runtime is visible
- **THEN** the system updates the game surface and clamps the window into the current legal area without leaving it offscreen

### Requirement: Complete Runtime Behavior in Resizable Presentations
Floating, split, and native-window presentations SHALL run the same standalone GameAbility scripts, physics, rendering, audio, Input Map, scene transitions, and lifecycle as fullscreen. Surface dimensions, viewport scaling, and pointer or touch coordinates SHALL follow the confirmed content area after every resize or rotation. A healthy real run SHALL remain active for more than 30 seconds without a guessed self-termination timer.

#### Scenario: Exercise gameplay in a floating window
- **WHEN** a scene dynamically initializes content and receives input in floating presentation
- **THEN** the same game logic and input actions execute as in fullscreen, with coordinates mapped to the current game content area

#### Scenario: Resize an active runtime
- **WHEN** the floating, split, or native window content area changes
- **THEN** the render surface and input mapping update to the new confirmed dimensions without stretching stale coordinates or restarting the game session

#### Scenario: Keep a healthy session running
- **WHEN** a confirmed real session remains healthy for longer than 30 seconds
- **THEN** it stays `REAL_RUNNING` until an explicit or observed terminal event occurs

### Requirement: Authoritative Game Capture Provenance
`take_screenshot(source: "game")` SHALL capture only the active real GameAbility root viewport, excluding EditorAbility and operating-system window chrome. Every successful capture SHALL return matching `session_id` and unique `request_id`, actual presentation, backend, dimensions, timestamp, and integrity metadata. Capture failure SHALL return a hard error and SHALL NOT fall back to an editor, preview, or system-composited screenshot.

#### Scenario: Capture a floating real run
- **WHEN** a capture-ready floating GameAbility receives `take_screenshot(source: "game")`
- **THEN** the response contains only the game root viewport and matching session, request, presentation, and integrity provenance

#### Scenario: Game capture is unavailable
- **WHEN** no matching capture-ready real session exists or the GameAbility capture backend fails
- **THEN** the system returns a lifecycle- or capture-specific error with no image from another source

#### Scenario: Session ends during capture
- **WHEN** the matching real session closes or crashes before its capture is committed
- **THEN** the request returns `SESSION_ENDED` and a late response cannot satisfy a later request

### Requirement: Project Immutability and Application-Scope Windowing
Real-run presentation, capability detection, launch, capture, and cleanup SHALL NOT modify `project.godot`, `.tscn` files, Autoload declarations, source files, export configuration, or project-local presentation preferences. The application SHALL use only public application-scope HarmonyOS capabilities and SHALL NOT require root access, privileged signing, restricted window-manager APIs, or edits to system window-manager configuration.

#### Scenario: Compare project bytes around a run
- **WHEN** a clean project is run, resized, captured, and stopped in any presentation
- **THEN** byte hashes of `project.godot` and all `.tscn` files remain unchanged and no temporary Autoload entry is created

#### Scenario: Presentation requires privileged system mutation
- **WHEN** the desired presentation is unavailable without root, privileged signing, restricted APIs, or system configuration edits
- **THEN** the system reports the unsupported constraint and does not attempt the privileged mutation

### Requirement: Tablet-First Acceptance and Explicit Platform Blocker
The target tablet SHALL be the primary acceptance device for AI-safe windowed real run. Acceptance SHALL require automatic launch into floating or split presentation with EditorAbility still visible and controllable; complete runtime behavior; resize, rotation, geometry, input, longevity, lifecycle, capture-provenance, and immutability evidence. The currently connected 2-in-1 SHALL provide regression evidence but SHALL NOT substitute for tablet acceptance. Manual conversion through a system toolbar SHALL be diagnostic evidence only.

#### Scenario: Pass target-tablet acceptance
- **WHEN** the implementation is validated on the designated tablet
- **THEN** a real GameAbility automatically starts floating or split without fullscreen takeover and passes the required runtime, lifecycle, capture, and immutability checks

#### Scenario: Tablet cannot provide floating or split
- **WHEN** the target tablet exposes neither an automatic floating nor split launch path to the application
- **THEN** the change is reported as blocked by platform capability and does not claim the user's goal complete

#### Scenario: Verify the currently connected 2-in-1
- **WHEN** regression tests run on the HarmonyOS 2-in-1 device
- **THEN** its native windowed GameAbility remains functional, but the result is labeled as regression evidence rather than tablet proof

#### Scenario: Perform final Stage 4 release QA
- **WHEN** an agent claims final release/fullscreen Stage 4 acceptance
- **THEN** it supplies a separate explicit fullscreen GameAbility session and authoritative game capture in addition to iterative windowed evidence

