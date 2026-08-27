# Build and Static Verification

Date: 2026-08-27 (Asia/Shanghai)

## Inputs

- Engine profile: `release-debug`
- Engine target: `platform=openharmony target=editor`
- Engine options: `debug_symbols=yes optimize=speed dev_build=no vulkan=yes ohos_opengl3=yes module_zip_enabled=yes`
- Parallel jobs: 16
- HAP product/module/mode: `default`, `entry@default`, `debug`
- DevEcoCli: 1.0.0
- SCons: 4.10.1 under Python 3.12

## Results

- OpenHarmony engine compilation: passed.
- Native NAPI link: passed after rebuilding `libgodot.so` with `godot_set_runtime_ready_callback`.
- ArkTS compilation: passed.
- HAP packaging and signing: passed.
- OpenSpec strict validation: passed.
- Source/rawfile Godot MCP add-on recursive diff: identical (54 files; zero list or SHA-256 differences).
- Static residue scan: no simulation handler/state/source or preview capture route remains.
- Connected HarmonyOS 2-in-1 deployment: passed.
- Packaged GDScript parsing and plugin startup: passed; the editor registered 229 commands without the prior `editor_commands.gd`, `command_router.gd`, or `plugin.gd` compile errors.
- Legacy persistent MCP Autoload migration: passed; exact owned entries were removed without missing-script startup errors.
- Authoritative GameAbility launch: passed; `run_project` returned the `REAL_STARTING` session response in 16 ms and the correlated first-frame event advanced it to `REAL_RUNNING`.
- GameAbility root-viewport screenshot: passed at 2090 x 1324, 98,902 bytes, SHA-256 `a7dbad43f5d78db090ef8bd899642c886d9f474d52cd153e5d5d7699a60666f1`, with `requested_source=game`, `actual_source=game_ability`, and backend `game_ability_root_viewport`.
- Runtime longevity: passed beyond 21 seconds without the former 15-second termination behavior.
- Explicit stop: passed; the correlated `REAL_STOP_ACK` produced `IDLE` with `last_session.outcome=stop_requested`, and the `:game` process was absent from the OS process table two seconds later.

Fresh build artifacts:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `platform/openharmony/template/entry/build/default/outputs/default/entry-default-signed.hap` | 276089499 | `3223b8e2e23bc4432e664314b9613c1526f9efebdf6c4e650658e8b31d53bc93` |

## Warnings and Limits

- The successful build retained pre-existing ArkTS warnings for device-specific capabilities/permissions and packaged Python source. None was introduced as a compiler error by this change.
- No compatible host Godot editor executable is present in this checkout, so the packaged GDScript unit suite was not executed as a standalone host test. The same packaged scripts were parsed and exercised through the installed editor and GameAbility acceptance flow.
- The device acceptance used the connected 2-in-1 presentation. Phone/tablet fullscreen presentation remains a separate device-class verification item.
- Project/scene immutability should be measured after the one-time legacy-Autoload migration baseline, because that explicitly authorized migration intentionally updates `project.godot` once.
