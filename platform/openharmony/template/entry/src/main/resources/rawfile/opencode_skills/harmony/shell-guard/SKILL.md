---
name: shell-guard
version: 1.0.0
description: |
  Shell execution safety guard. This skill MUST be loaded before running ANY shell command in i3DAct workflows.
  Use it to detect the current platform, verify the shell environment, and enforce timeout wrapping on every blocking command.
  Load this skill when: starting any i3DAct game generation session, running engine commands, or when unsure about which platform or shell you are on.
author: i3DAct
license: MIT
---

# Shell Guard — Execution Safety

Platform detection, shell verification, and timeout enforcement for all i3DAct shell commands.

## Pre-flight Gate (MANDATORY — Run Once Per Session)

Before executing ANY engine command (`i3d.*`, `dotnet build`, `python`), run this exact command:

```bash
timeout --version 2>/dev/null && timeout 1 echo "shell-guard: ok"
```

**If this command succeeds**: GNU `timeout` is available. Proceed with engine commands, but wrap every blocking command with `timeout` (see Timeout Policy below).

> **Windows note:** The native Windows `timeout` (pauses for N seconds) will silently "succeed" with exit 0 but is NOT the GNU version. `timeout --version` distinguishes them — GNU prints a version string, Windows native prints an error or pauses.

**Note:** The GNU `timeout` command (kills a process after N seconds) is different from the Windows `timeout` command (pauses for N seconds). This skill requires the GNU version, available via Git Bash / MSYS2 / WSL on Windows, or GNU coreutils on Linux. The Windows native `timeout` will NOT work.

**If this command fails**: `timeout` is NOT available in the current shell. STOP immediately. Do NOT run any engine commands. Report to the user:
> "shell-guard: `timeout` command not available. Engine commands may hang indefinitely without timeout protection. Please ensure GNU coreutils is installed (`timeout` command)."

**Never skip this gate.** Never assume `timeout` is available without verifying.

## One-shot Session Init

For session startup, combine all detection into a single command instead of 3 separate calls:

```bash
timeout 5 bash -c '
  echo "shell=$BASH_VERSION"
  echo "platform=$(uname -s 2>/dev/null || echo windows)"
  echo "timeout=$(timeout --version 2>&1 | head -1)"
  echo "cwd=$(pwd)"
  echo "has_project_i3d=$([ -f project.i3d ] && echo yes || echo no)"
  for bin in i3d.windows.exe i3d.linux; do
    if command -v "$bin" >/dev/null 2>&1; then echo "engine=$bin"; break; fi
  done
  echo "dotnet=$(dotnet --version 2>/dev/null)"
  echo "python=$(python --version 2>&1 || python3 --version 2>&1)"
  # Tool availability for visual-qa — checks .opencode/bin/ relative to CWD
  for tool in .opencode/bin/ai-media.exe .opencode/bin/ffmpeg.exe; do
    if [ -f "$tool" ] && [ -s "$tool" ]; then echo "tool_ok=$tool"; fi
  done
  for tool in .opencode/bin/ai-media .opencode/bin/ffmpeg; do
    if [ -f "$tool" ] && [ -s "$tool" ]; then echo "tool_ok=$tool"; fi
  done
'
```

Parse output lines for `shell`, `platform`, `timeout`, `engine`, `dotnet`, `python`. If `timeout` line is empty, STOP (see Pre-flight Gate). If `engine` line is empty, the engine binary is not on PATH — ask user for the path. If `python` line is empty or shows version < 3.10, warn the user — `tools/asset_gen.py` and `tools/rembg_matting.py` require Python 3.10+. Parse `tool_ok=` lines. If no `tool_ok=ai-media` found, visual-qa will fall back to model vision + MCP tools. If no `tool_ok=ffmpeg` found, video conversion will fail — suggest the user copy ffmpeg from the vibeCoding template.

## Platform Detection

Do NOT guess the platform. Detect it by running:

```bash
uname -s 2>/dev/null || echo "windows"
```

Then map to the correct engine binary:

| `uname -s` output | Platform | Engine binary | Shell | `timeout` |
|---|---|---|---|---|
| `MINGW*` / `MSYS*` / `CYGWIN*` / `windows` | Windows | `i3d.windows.exe` | Git Bash (MSYS2) | GNU coreutils (built-in) |
| `Linux` | Linux (Ubuntu/麒麟/统信) | `i3d.linux` | bash | GNU coreutils (native) |

**Rules:**
- Never hardcode `i3d.windows.exe` — use the detected binary name
- Forward slashes (`/`) in all paths on all platforms

## Timeout Policy (MANDATORY)

**Every shell command that can block MUST be wrapped with `timeout`. No exceptions.** A hung process kills the entire pipeline.

### Timeout Values

| Category | Timeout | Examples |
|---|---|---|
| Engine commands | `timeout 60` | `i3d.*.exe --headless`, `dotnet build` |
| Single API call | `timeout 120` | `asset_gen.py image`, `asset_gen.py retarget`, `pip install` |
| Multi-step API | `timeout 180` | `asset_gen.py glb`, `asset_gen.py rig`, `rembg_matting.py` single |
| Long batch jobs | `timeout 300` | `rembg_matting.py --batch`, `asset_gen.py video` |
| Quick local ops | `timeout 30` | `git`, `magick`, `grid_slice.py`, `find_loop_frame.py` |

**Hard upper limit**: 300 seconds. The code layer (bash.ts) enforces an absolute maximum of 10 minutes as a safety net, but skills should never request more than 300 seconds without explicit user approval.

### Wrapping Pattern

```bash
# CORRECT (replace ENGINE_BIN with detected binary: i3d.windows.exe / i3d.linux):
timeout 60 ENGINE_BIN --headless --import 2>&1
timeout 60 dotnet build 2>&1
timeout 120 python tools/asset_gen.py image --prompt "..." -o out.png

# WRONG — NEVER do this:
ENGINE_BIN --headless --import                     # no timeout = may hang forever
cmd /c ENGINE_BIN --headless --import              # bypassing shell = bypassing safety
powershell -c "& ENGINE_BIN --headless"            # wrong shell
start /wait ENGINE_BIN --headless                  # no timeout protection
```

### Timeout Exit Codes

- **Exit code 124** (GNU `timeout`): the command was killed because it exceeded the timeout. Retry once. If it times out twice, report to the user.
- **Exit code 0 or other**: normal completion. Proceed.

## Shell Environment Rules

### Do

- Use bash-compatible commands: `mkdir -p`, `touch`, `rm -rf`, `grep`, `cat`, `cp`
- Use forward slashes in all paths
- Use `python` not `python3` on Windows; on Linux use `python3` if `python` points to Python 2
- Run `timeout 1 echo "shell-guard: ok"` to verify the environment before engine commands

### Don't

- **NEVER generate PowerShell commands**: No `New-Item`, `Remove-Item`, `Set-Content`, `Write-Output`, `$env:VAR`
- **NEVER use `cmd /c` to bypass shell**: This circumvents timeout protection
- **NEVER guess the shell type**: Always detect via the Pre-flight Gate
- **NEVER run engine commands without `timeout`**: Even if you "think" it will be fast
- **NEVER use Linux-only tools on Windows**: `xvfb-run`, `chmod`, `env VAR=val`, `perl -e 'alarm'`
- **NEVER assume GPU availability**: On Linux, check. On Windows, DirectX/Vulkan is always available.
- **NEVER copy engine binaries into the project**: Do NOT copy `ai-media.exe`, `ffmpeg.exe`, or `config.json` from the engine's `.opencode/bin/` into any project directory. These files contain backend configuration (API keys, provider presets, encryption) that must never appear in project code. Always invoke them by their full path from the engine installation directory.
- **NEVER combine `--headless` with `--write-movie`**: `--headless` activates RendererDummy which cannot produce frames. The engine will error out. Screenshots and recordings MUST NOT include `--headless`. Only `--import`, `--quit`, and `--script` (scene builders) use `--headless`.

## Process Recovery

**CRITICAL — Vibe Coding mode**: In Vibe Coding, the AI is running INSIDE the i3d engine process. **NEVER use `taskkill /IM i3d.windows.exe` or `pkill -f i3d`** — these will kill the host engine process and terminate the AI session. The `timeout` wrapper already kills the child process on timeout (exit 124); no manual kill is needed.

If a command returns exit code 124 (timeout fired):

1. **The timeout already killed the hung subprocess** — no manual kill needed. Do NOT run `taskkill` or `pkill`.
2. **Retry once**: Re-run the command with `timeout`.
3. **If retry also times out**: Report to user with full context (which command, what timeout was used, what output was captured). Let the user decide how to proceed.

If a command hangs WITHOUT timeout wrapping (should never happen, but if it does):

1. **Do NOT blindly kill engine processes.** In Vibe Coding mode, this kills the AI host.
2. **Linux only — kill the specific PID**: If you know the exact PID of the hung child process: `kill -TERM <PID>`. Never use `pkill -f i3d`.
3. **Windows**: Report to the user. Do not attempt to kill via taskkill — there is no way to selectively kill a child process by name without also matching the parent.

## Integration With Other Skills

This skill is a **dependency** for any skill that executes shell commands:
- `i3dact-gen` — reads `shell-guard` before any engine command in its pipeline
- `visual-qa` — uses `timeout` wrapping per shell-guard's timeout policy
- Future skills — reference `shell-guard` the same way

When a skill references `shell-guard`, it means: **the rules in this document apply to all shell commands issued by that skill**. There is no need for the calling skill to duplicate these rules.
