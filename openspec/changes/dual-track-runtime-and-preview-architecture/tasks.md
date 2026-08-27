## 1. Contract Reconciliation

- [x] 1.1 Record the approved decision to remove editor simulation and retain standalone `GameAbility` as the only gameplay runtime.
- [x] 1.2 Rewrite this change's proposal, design, and specs so they supersede the obsolete dual-track/preview requirements.
- [x] 1.3 Make schemas, method discovery, compatibility aliases, and stable errors match the single-track contract.
- [x] 1.4 Add contract tests that fail on any preview state/source/command or simulation dispatch.

## 2. Remove the Simulation Track

- [x] 2.1 Remove preview modes, states, capabilities, event names, comments, and dead `InEditorGameRunner` references from lifecycle code.
- [x] 2.2 Ensure `simulate_project`, `simulate_scene`, `simulate_current_scene`, `stop_simulation`, and `is_simulation_running` are neither discoverable nor internally dispatchable.
- [x] 2.3 Remove preview screenshot handling and every game-capture path that can fall back to editor or system-screen capture.
- [x] 2.4 Remove obsolete simulation files, manifests, packaged assets, and tests; synchronize the source and rawfile add-on trees.

## 3. Real-Only Lifecycle and Bridge

- [x] 3.1 Implement the `IDLE` / `REAL_STARTING` / `REAL_RUNNING` / `REAL_STOPPING` / `RECONCILING` state machine.
- [x] 3.2 Require exact event type, `session_id`, `operation_id`, and `boot_nonce` matches for every state-changing event.
- [x] 3.3 Remove `EditorInterface.is_playing_scene()` and deferred editor-play callbacks as READY evidence.
- [x] 3.4 Propagate launch metadata through the native/OpenHarmony bridge and feed READY, STOP_ACK, EXIT, and failure events into the production coordinator.
- [x] 3.5 Make uncertain transition timeouts enter reconciliation; retain no duration limit for confirmed running sessions.
- [x] 3.6 Add lifecycle/bridge tests for stale, empty, duplicate, mismatched, reordered, timeout, repeated-start, repeated-stop, and long-running cases.

## 4. Zero-Pollution Runtime Services and Capture

- [x] 4.1 Remove persistent runtime Autoload injection/removal and every `ProjectSettings.save()` call used to install MCP instrumentation; retain only exact-owned one-time legacy cleanup.
- [x] 4.2 Implement a correlated run-scoped GameAbility capture agent; inspection and input return an honest stable capability error until their own agents exist.
- [ ] 4.3 Use unique per-session/per-request paths, atomic commit ordering, deadlines, path containment, and exact-session cleanup for any file-backed transport.
- [ ] 4.4 Validate screenshot session, nonce, request ID, status, timestamps, source, backend, PNG metadata, byte count, dimensions, and SHA-256 before success.
- [ ] 4.5 Reject stale, late, corrupt, partial, mismatched, path-traversal, unsupported-backend, and concurrent-request-confusion responses.
- [ ] 4.6 Isolate runtime inspection/input from `edited_scene_root` and test both idle and live-runtime behavior.
- [ ] 4.7 Add strict capture tests proving zero cross-source fallback and independent artifact verification.
- [ ] 4.8 Verify the one-time legacy cleanup removes only exact MCP key/path pairs and that subsequent starts produce no missing-Autoload errors.

## 5. Packaging, Documentation, and Static Verification

- [x] 5.1 Synchronize the implemented source add-on into the OpenHarmony rawfile package and verify exact file/hash parity plus obsolete-file removal.
- [x] 5.2 Remove active dual-track, simulation, preview-capture, and unsupported runtime-service claims from protocols, skills, examples, and MCP documentation.
- [ ] 5.3 Run OpenSpec strict validation, GDScript/static checks, ArkTS/native checks, repository tests, source/package diffs, and retain the logs.
- [x] 5.4 Build the exact HAP and record inputs, output path, package hash, and warnings.

## 6. Device Acceptance and Approval Gate 2

- [ ] 6.1 Install the recorded HAP and verify method discovery rejects simulation and exposes only `editor | game` screenshot sources.
- [ ] 6.2 Verify start -> correlated READY -> live runtime inspection/capture -> correlated stop ACK/EXIT -> final `IDLE`.
- [ ] 6.3 Verify stale session/nonce/request responses cannot complete another request and no unavailable capability falls back to editor or OS capture.
- [ ] 6.4 Run a confirmed real session for at least 60 seconds and prove no duration timer clears or terminates it.
- [ ] 6.5 Compare clean-baseline SHA-256 values for `project.godot` and all `.tscn` files after start, runtime operations, capture, failure paths, and stop.
- [ ] 6.6 Store the runnable acceptance script, raw transcript, exact-build metadata, report, and proof artifacts under this change.
- [ ] 6.7 Present the retained device evidence and known limitations at Approval Gate 2; do not archive before user approval.
