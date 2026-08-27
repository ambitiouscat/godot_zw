# Project Learnings

## [LRN-20260827-001] knowledge_gap

**Logged**: 2026-08-27T18:27:00+08:00
**Priority**: high
**Status**: resolved
**Area**: tests

### Summary
Godot JSON numeric fields must be validated as either `int` or `float` before normalization.

### Details
A GameAbility screenshot response wrote `byte_count` as an integer, but `JSON.parse_string()` decoded the number as a float. An `int`-only contract rejected a valid, hash-verified PNG response.

### Suggested Action
For integral JSON protocol fields, accept finite `int` or `float` values, normalize with `int()`, and then apply range and integrity checks. Cover the float representation in contract tests.

### Metadata
- Source: error
- Related Files: editor/plugins/godot_mcp/lifecycle/runtime_capture_protocol.gd, editor/plugins/godot_mcp/tests/test_runtime_capture.gd
- Tags: godot, json, gdscript, protocol-validation

### Resolution
- **Resolved**: 2026-08-27T18:27:00+08:00
- **Commit/PR**: N/A
- **Notes**: Numeric validation now accepts both representations; a real 2090x1324 GameAbility capture passed byte-count, PNG, and SHA-256 checks.

---

## [LRN-20260827-002] best_practice

**Logged**: 2026-08-27T18:27:00+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
Use the correlated GameAbility lifecycle channel as the terminal authority for explicit stops across isolated HarmonyOS Ability processes.

### Details
On the tested 2-in-1 device, GameAbility received the stop Want, returned `REAL_STOP_ACK`, called the OS termination API, and exited with code 0, but the editor-side `startAbilityForResult()` Promise did not resolve. Waiting only for that Promise or for a fire-and-forget `onWindowStageDestroy()` network event left the coordinator in `RECONCILING` after a successful stop.

### Suggested Action
Require exact session, operation, nonce, event ID, timestamp, and source correlation. Treat `REAL_STOP_ACK`, emitted immediately before the OS termination call, as the explicit-stop terminal signal; retain `REAL_EXIT` for spontaneous or abrupt exits. Never infer death from editor focus changes.

### Metadata
- Source: error
- Related Files: editor/plugins/godot_mcp/lifecycle/lifecycle_coordinator.gd, platform/openharmony/template/entry/src/main/ets/gameability/GameAbility.ets, platform/openharmony/template/entry/src/main/ets/core/BridgeCallbacks.ets
- Tags: harmonyos, ability, lifecycle, gameability, mcp

### Resolution
- **Resolved**: 2026-08-27T18:27:00+08:00
- **Commit/PR**: N/A
- **Notes**: Device acceptance reached IDLE with outcome `stop_requested`, and the `:game` process was absent from the OS process table two seconds later.

---
