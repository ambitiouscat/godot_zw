## ADDED Requirements

### Requirement: Canonical Gameplay Commands Target Only GameAbility

The system SHALL route every canonical gameplay start and stop command to standalone `GameAbility`. It SHALL NOT register or dispatch editor simulation commands.

#### Scenario: Start project

- **WHEN** a client calls `run_project` from `IDLE`
- **THEN** the system starts a correlated `GameAbility` session and reports `REAL_STARTING`
- **AND** it does not create an editor SubViewport simulation

#### Scenario: Removed simulation command

- **WHEN** a client calls any `simulate_*` command or `stop_simulation`
- **THEN** the method is absent or rejected as unsupported
- **AND** no lifecycle or scene-tree state changes

### Requirement: Real-Only Correlated Lifecycle

The lifecycle coordinator SHALL use only `IDLE`, `REAL_STARTING`, `REAL_RUNNING`, `REAL_STOPPING`, and `RECONCILING`, and SHALL accept state-changing runtime events only when event, session, operation, and boot nonce match the active transition.

#### Scenario: Runtime readiness

- **WHEN** a matching `REAL_READY` arrives after the GameAbility surface and first frame are ready
- **THEN** `REAL_STARTING` transitions to `REAL_RUNNING`

#### Scenario: Stale readiness

- **WHEN** a READY event has an empty, stale, or mismatched correlation field
- **THEN** the event is ignored
- **AND** the lifecycle state does not change

#### Scenario: Uncertain transition timeout

- **WHEN** a real start or stop handshake times out without conclusive runtime evidence
- **THEN** the coordinator enters `RECONCILING`
- **AND** it does not falsely report `IDLE`

#### Scenario: Long-running game

- **WHEN** a session is confirmed `REAL_RUNNING`
- **THEN** no duration-based timer terminates it or clears its state

### Requirement: Strict Screenshot Sources

The screenshot API SHALL accept only `source="editor"` and `source="game"` and SHALL never substitute another source.

#### Scenario: Preview source rejected

- **WHEN** a client requests `source="preview"`
- **THEN** the API returns `INVALID_ARGUMENT`
- **AND** no screenshot from another source is returned

#### Scenario: Game unavailable

- **WHEN** a client requests `source="game"` without a matching running and capture-ready GameAbility session
- **THEN** the API returns `RUN_STATE_CONFLICT`, `GAME_NOT_READY`, or `CAPABILITY_UNAVAILABLE`
- **AND** it does not capture the editor or OS screen

#### Scenario: Verified game artifact

- **WHEN** a correlated GameAbility capture succeeds
- **THEN** the response includes matching session/request identifiers, actual source, GameAbility backend, capture timestamp, dimensions, byte count, format, SHA-256, and provenance
- **AND** the editor has independently validated the committed artifact bytes and correlation fields

### Requirement: Project Files Remain Immutable

MCP runtime instrumentation SHALL NOT persist project Autoloads, call `ProjectSettings.save()` during launch/capture, mutate edited-scene nodes, or store transport artifacts in `res://`. The platform MAY register a correlated capture agent in the GameAbility process's in-memory `ProjectSettings`. A one-time migration MAY remove and save only exact legacy MCP Autoload entries previously persisted by the plugin.

#### Scenario: Start, inspect, capture, and stop

- **WHEN** a clean project completes a real-run acceptance sequence
- **THEN** `project.godot` and every `.tscn` file retain their clean-baseline SHA-256 values

#### Scenario: Legacy MCP Autoload migration

- **WHEN** an affected project contains an exact legacy MCP Autoload key/path pair
- **THEN** a compatibility script permits startup and the editor removes and saves only that owned entry
- **AND** a user-owned Autoload with the same name or a different path is preserved

### Requirement: Runtime Commands Are Honest and Isolated

Runtime inspection and input commands SHALL operate only through a correlated GameAbility-side capability. If unavailable, they SHALL return a stable explicit error.

#### Scenario: Runtime agent unavailable

- **WHEN** a runtime inspection or input command is called and no matching GameAbility agent is ready
- **THEN** the command returns `CAPABILITY_UNAVAILABLE` or `GAME_NOT_READY`
- **AND** it does not inspect or mutate `edited_scene_root`

### Requirement: Observable Execution State

`get_execution_state` SHALL expose the active state, session and operation identifiers, target scene, timestamps, readiness/capability flags, and last terminal outcome without advertising preview support.

#### Scenario: Idle capabilities

- **WHEN** the editor is idle
- **THEN** the response reports `IDLE`, `real_run_supported: true`, and `preview_supported: false`

### Requirement: Reproducible Acceptance Evidence

Completed device-acceptance tasks SHALL retain a runnable script and report tied to the exact build and device, including start/READY, live runtime behavior, strict game capture, longevity, stop/EXIT, final `IDLE`, and project-file hash assertions.

#### Scenario: Evidence review

- **WHEN** a reviewer reruns the retained acceptance procedure against the recorded build
- **THEN** every claimed assertion can be reproduced without relying on narrative-only statements
