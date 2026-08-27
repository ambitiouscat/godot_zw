## Purpose

Defines observable command, lifecycle, correlation, screenshot-provenance, and
source-file immutability contracts for real Godot execution and editor preview.

## ADDED Requirements

### Requirement: Canonical Dual-Track Command Contract
The system SHALL route `run_project`, `run_scene`, and `run_current_scene` only to standalone `GameAbility`; SHALL route `simulate_project`, `simulate_scene`, and `simulate_current_scene` only to in-editor preview; SHALL route `stop_project` only to real run; and SHALL route `stop_simulation` only to preview.

#### Scenario: Start the configured main scene in real mode
- **WHEN** a client invokes `run_project` from `IDLE`
- **THEN** the system accepts a real-run operation and does not mount a preview overlay

#### Scenario: Start the configured main scene in preview mode
- **WHEN** a client invokes `simulate_project` from `IDLE`
- **THEN** the system accepts a preview operation and does not launch `GameAbility`

#### Scenario: Reject a wrong-track stop
- **WHEN** a client invokes `stop_project` while only preview is active, or invokes `stop_simulation` while only real run is active
- **THEN** the system returns `STATE_CONFLICT` without stopping the active session

### Requirement: Command Compatibility and Deprecation
The system SHALL preserve the alias mapping defined in `design.md`, SHALL return `deprecated_alias: true` and a canonical `replacement` for deprecated aliases, and SHALL NOT preserve the fork-specific behavior in which `play_*` starts preview.

#### Scenario: Use a deprecated play alias
- **WHEN** a client invokes `play_scene` with a scene path
- **THEN** the system invokes canonical `run_scene`, reports the alias deprecation, and starts no preview session

#### Scenario: Use deprecated scene-path fields
- **WHEN** a client invokes `run_scene` or `simulate_scene` with `scene_path` or `scene` instead of `path`
- **THEN** the system normalizes the value, reports the deprecated field, and applies canonical command behavior

### Requirement: Asynchronous Lifecycle State Contract
The system SHALL expose stable states `IDLE`, `PREVIEW_RUNNING`, and `REAL_RUNNING`, transitional states `PREVIEW_STARTING`, `PREVIEW_STOPPING`, `REAL_STARTING`, `REAL_STOPPING`, and `RECONCILING`, and SHALL enter a RUNNING state only after the matching runtime reports READY.

#### Scenario: Real start remains transitional until ready
- **WHEN** the real start request is accepted but matching `REAL_READY` has not arrived
- **THEN** the command reports `accepted` and the execution state remains `REAL_STARTING`, not `REAL_RUNNING`

#### Scenario: Real stop remains transitional until exit
- **WHEN** `REAL_STOP_ACK` has arrived but matching `REAL_EXIT` has not arrived
- **THEN** the state remains `REAL_STOPPING` and no pending preview is started

#### Scenario: Reconcile uncertain state
- **WHEN** the editor restarts, a lifecycle handshake times out, or observed runtime state conflicts with tracked state
- **THEN** the system enters `RECONCILING`, rejects new starts, verifies actual runtime ownership, and only then selects a stable state

### Requirement: Session-Correlated and Idempotent Operations
The system SHALL generate an immutable UUID-based `session_id` for each accepted start, SHALL correlate all lifecycle and capture messages to that session, SHALL serialize mutating operations, and SHALL deduplicate retries by `operation_id`.

#### Scenario: Ignore a stale exit event
- **WHEN** an EXIT event for session A arrives after session B became current
- **THEN** the system logs and ignores the event without changing session B

#### Scenario: Retry an accepted operation
- **WHEN** a client repeats an operation with the same `operation_id` and identical normalized arguments
- **THEN** the system returns the existing operation and does not start or stop a second runtime

#### Scenario: Reject an operation ID collision
- **WHEN** a client reuses an `operation_id` with different normalized arguments
- **THEN** the system returns `INVALID_OPERATION_ID` without changing lifecycle state

### Requirement: Explicit Conflict and Preemption Policy
Every start command SHALL default to `conflict_policy: "reject"`; SHALL accept `conflict_policy: "preempt"` for an explicit mode switch; and SHALL complete the source session's terminal stop acknowledgement before starting the target session.

#### Scenario: Reject an implicit destructive switch
- **WHEN** a preview start is requested while real run is active without explicit preemption
- **THEN** the system returns `STATE_CONFLICT` and leaves the real session running

#### Scenario: Preempt real run with preview
- **WHEN** a preview start is requested with `conflict_policy: "preempt"` while real run is active
- **THEN** the system stops the matching real session, waits for `REAL_EXIT`, and only then starts the reserved preview session

#### Scenario: Abort target when source stop is uncertain
- **WHEN** the source session's stop fails or times out during preemption
- **THEN** the target session is not started and the system enters the verified source state or `RECONCILING`

### Requirement: Real-Run Readiness, Longevity, and Exit
The system SHALL correlate real-run readiness and termination to the active session, SHALL NOT infer readiness from a deferred editor call or process exit Promise, and SHALL NOT impose a duration timeout on a confirmed healthy game session.

#### Scenario: Maintain a long-running game
- **WHEN** a matching `REAL_READY` session continues for at least 60 seconds without an EXIT event
- **THEN** the system remains `REAL_RUNNING` and continues to support state queries, game screenshots, and explicit stop

#### Scenario: Stop a matching real session
- **WHEN** `stop_project` is invoked with the active session and `GameAbility` accepts and exits
- **THEN** the system observes matching STOP and EXIT acknowledgements, records the terminal outcome, and transitions to `IDLE`

#### Scenario: Foreground does not prove death
- **WHEN** `EditorAbility` returns to foreground while a real session is tracked
- **THEN** the system reconciles liveness and does not clear the session solely because of the foreground event

### Requirement: Strict Screenshot Source and Provenance
The system SHALL treat screenshot source as the exact enum `editor`, `preview`, or `game`; SHALL capture only the matching backend; and SHALL return `requested_source`, `actual_source`, `backend`, `session_id`, `request_id`, artifact integrity data, and capture provenance on success.

#### Scenario: Capture preview evidence
- **WHEN** `take_screenshot` requests `source: "preview"` during `PREVIEW_RUNNING`
- **THEN** the system captures the active preview SubViewport and returns `actual_source: "preview_subviewport"`, `backend: "in_editor_subviewport"`, and the matching preview session

#### Scenario: Capture real-game evidence
- **WHEN** `take_screenshot` requests `source: "game"` during capture-ready `REAL_RUNNING`
- **THEN** the system captures the matching `GameAbility` surface or native root viewport and reports the actual GameAbility backend and matching session

#### Scenario: Do not reinterpret game as preview
- **WHEN** `take_screenshot` requests `source: "game"` while preview is active and no real session is running
- **THEN** the system returns `RUN_STATE_CONFLICT` and does not return a preview or editor image

### Requirement: Correlated Capture Integrity
Every real-game capture SHALL use a unique `request_id`, SHALL bind request and response to the active `session_id` and boot nonce, SHALL atomically commit the image before its response, and SHALL reject stale, incomplete, out-of-session, or integrity-invalid results.

#### Scenario: Reject a previous session's frame
- **WHEN** a capture response has the expected request ID but a stale session ID, nonce, or capture timestamp
- **THEN** the system rejects it as `STALE_CAPTURE_RESPONSE` and continues waiting only until the current request deadline

#### Scenario: Complete concurrent captures without cross-talk
- **WHEN** two game capture requests are accepted concurrently
- **THEN** each request receives only its own correlated image and response, regardless of response order

#### Scenario: End a capture with its session
- **WHEN** the real session exits while a capture is pending
- **THEN** the pending request returns `SESSION_ENDED` and no late frame satisfies a later request

### Requirement: No Cross-Source Screenshot Fallback
The system SHALL return a stable capture or lifecycle error when the requested backend is unavailable, not ready, busy, timed out, or invalid, and SHALL NEVER substitute an editor or preview image for a requested game image.

#### Scenario: Game capture backend fails
- **WHEN** both allowed GameAbility capture backends fail for the active session
- **THEN** the system returns `CAPTURE_BACKEND_UNAVAILABLE` with correlation and recovery metadata and no image from another source

### Requirement: Clean Preflight and Source-File Immutability
Start commands SHALL default to `save_policy: "require_clean"`, SHALL reject unsaved edited scenes without starting, and SHALL establish the source-file hash baseline only after an explicitly requested preflight save has completed. Runtime control and capture SHALL NOT modify `project.godot` or `.tscn` files after that baseline.

#### Scenario: Reject an implicit save
- **WHEN** a start command uses the default save policy while the edited scene has unsaved changes
- **THEN** the system returns `UNSAVED_CHANGES`, does not save, and does not start either track

#### Scenario: Establish a post-save baseline
- **WHEN** a start command uses `save_policy: "save"` and the preflight save succeeds
- **THEN** the response reports `preflight_saved: true` and the session baseline is established after the save

#### Scenario: Preserve project sources across a session
- **WHEN** a clean-baseline preview or real run is started, captured, and stopped
- **THEN** SHA-256 values for `project.godot` and all `.tscn` files match the baseline and no temporary MCP Autoload is present in `ProjectSettings`

### Requirement: Observable Execution State
The system SHALL expose `get_execution_state` in every state and SHALL return state, phase, mode, desired mode, current and pending session IDs, operation ID, target scene, cancellation status, transition time, capabilities, unresolved error, and last session outcome.

#### Scenario: Inspect a transition
- **WHEN** a client calls `get_execution_state` while real run is stopping for a preview preemption
- **THEN** the response identifies `REAL_STOPPING`, the real source session, the reserved preview session, the composite operation, and the desired preview mode

