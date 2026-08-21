---
name: resource-finder
version: 1.0.0
description: |
  Local resource discovery — search project and engine cache for downloaded assets.
  Use before AI generation to avoid recreating resources the user already has locally.
author: i3DAct
license: MIT
metadata:
  category: asset
---

# Resource Finder

Discover locally available resources before falling back to AI generation.

## Triggers

**Explicit** — user expresses needing a named resource. Keywords include:
使用/加载/导入/需要/有没有/找个/查一下/有...吗/在哪 + 资源/模型/插件/纹理/图片/材质 + name

**Implicit** — other skills call `Skill(skill="resource-finder")` with a resource name query.
Resource-finder does not know or care who called it — it only returns "found + path" or "not found."

**Batch**: pass multiple comma-separated names in one call: `Skill(skill="resource-finder") "car model, track texture, sky background"`. Returns results for each.

## Configuration

```
Cache path:  {LOCALAPPDATA}\i3d\610\Plugins\unOfficial
             ↑ Auto-detect: $env:LOCALAPPDATA on Windows, typically C:\Users\<you>\AppData\Local
Copy target: {project}/assets/  (mkdir -p if missing)
```

## Search Flow

```
Parse resource name + type from query
    │
    ▼
① Project-wide search — Glob tool (NOT shell find)
   Exclude: .git/ .i3d/ node_modules/ *.dll *.exe *.pdb
    │
    ├─ Found → return path
    └─ Not found ↓
② Search cache: resolve $env:LOCALAPPDATA → \i3d\610\Plugins\unOfficial
   Use ls | grep first, fall back to find -maxdepth 3 -iname
    │
    ├─ Found → mkdir -p {project}/assets/ → cp -r to {project}/assets/ → return new path
    └─ Not found ↓
③ Return: NOT_FOUND. Caller decides: notify user to download, or trigger AI generation.

⚠️ Exit guard: 3+ search failures or >30s → return NOT_FOUND. No retry loops.
```

### Step ①: Project-wide search

Use the **Glob tool** (NOT shell `find` — avoids path-quoting issues on Windows):

```
Glob(pattern="{name}*")           # exact: Glob("{name}.glb")
Glob(pattern="**/*{name}*")       # partial: search subdirectories
```

Filter results by the resource-type extension list. Apply exclusion rules after Glob returns — skip paths matching `.git/`, `.i3d/`, `node_modules/`, `*.dll`, `*.exe`, `*.pdb`.

**Case-insensitive matching** — try both the given name and alternate capitalizations.
Rank results: exact filename match > partial match > containing-directory name match.
When multiple candidates tie, return shortest path first. List remaining candidates for caller review.

### Step ②: Engine cache search

Resolve the cache path by reading `$env:LOCALAPPDATA` from the environment, then appending `\i3d\610\Plugins\unOfficial`.

**Use `ls` first** (single command, no path translation needed):
```bash
ls "{resolved_path}" | grep -i "{name}"       # case-insensitive match
```

If `ls` fails (unusual directory layout), fall back to `find` with the direct Windows path:
```bash
find "{resolved_path}" -maxdepth 3 -iname "*{name}*" -not -name "*.dll"
```

If found, `mkdir -p {project}/assets/` then handle by type:

- **Single files** (`.glb`, `.fbx`, `.png`, etc.): copy to `{project}/assets/`.
- **Archives** (`.rar`, `.zip`): extract to `{project}/assets/`. Use `unzip` for `.zip`; for `.rar`, use `7z x` if available, or PowerShell `Expand-Archive` for `.zip` as fallback.

**⚠️ Filename normalization**: If the source file has a non-ASCII name (Chinese, Unicode), rename to ASCII during copy/extraction. The engine's resource importer fails on non-ASCII filenames. Example: `电脑.glb` → `computer.glb`. For archives, rename the extracted directory to an ASCII name.

Return the new project-local path.

### Exit guard

If 3+ search attempts fail or the search takes more than 30 seconds, return `NOT_FOUND` immediately. Do not retry with different path formats or shell variants — the caller handles the fallback.

### Step ③: Not found

Return a clear not-found status. Do NOT trigger generation — that is the caller's decision.

## Resource Type → Extension Mapping

| Type | Aliases | Extensions | Notes |
|------|---------|-----------|-------|
| 3D model | model, 模型, mesh, 网格 | `.gltf` `.glb` `.fbx` `.dae` `.obj` `.blend` `.escn` | 7 formats, all engine-readable |
| Plugin | plugin, 插件, 扩展 | `.s3extension` | Engine plugins |
| Image / Texture | texture, 纹理, 图片, 贴图, background, 背景 | `.png` `.jpg` `.jpeg` `.bmp` `.tga` | Common image formats |
| Unspecified | — | `*` | Match all extensions |

### Engine 3D format reference

| Always registered | Optionally enabled |
|-------------------|-------------------|
| .gltf .glb (glTF 2.0) | .blend (Blender → glTF) |
| .fbx (ufbx) | .fbx (FBX2glTF) |
| .dae (Collada) .obj (Wavefront) .escn (engine export) | |

Registration order: DAE → OBJ → ESCN → glTF/GLB → Blend → FBX-ufbx → FBX2glTF

## Exclusion Rules

| Rule | Scope |
|------|-------|
| Exclude directories | `.git/` `.i3d/` `node_modules/` |
| Exclude extensions | `.dll` `.exe` `.pdb` |

## Return Format

- **Found in project**: `FOUND: <relative-path>`
- **Found in cache, copied**: `FOUND: <relative-path> (copied from cache)`
- **Not found**: `NOT_FOUND`
- **Multiple candidates**: list all paths, note which was selected as primary
