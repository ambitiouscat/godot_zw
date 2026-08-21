---
description: "工作区会话管理 - 开始/继续/保存/结束工作会话"
---

# 工作区会话管理命令

根据用户提供的参数执行相应的工作区会话操作。

---

## ⚠️ 强制规则（违反视为执行失败）

1. **必须询问任务类型**：`/workspace start` 必须询问用户选择"项目任务"或"简单任务"
2. **统一存储目录**：所有文件存放在 `.workspace-session-skill/`（**禁止**使用 `.claude/`）
3. **session.md 格式**：使用纯 Markdown 格式（**禁止**使用 YAML frontmatter）
4. **创建初始任务笔记**：创建每日笔记后必须创建任务笔记
5. **Trilium 链接格式**：内部链接用 `#root/path/noteId`（**禁止**用 `trilium:noteId`）
6. **正确计算星期**：Claude 直接根据系统日期计算星期几（**禁止调用 API 获取**）
7. **严禁 get_special_note(kind="day")**：**永远禁止**调用 `get_special_note(kind="day")` MCP 工具获取/创建每日笔记。Trilium 内置日历笔记（标题 "DD - 周X"、父节点 "MM - 月份名"、带 dateNote 标签）与 workspace 笔记体系完全隔离。获取每日笔记必须通过 `search_notes(ancestorNoteId=month_dir_id, ...)`，创建必须通过 `create_note(parentNoteId=month_dir_id, ...)`。这是最常见的静默错误——工具名叫 "get day note" 但指向错误位置。
8. **不设置 notePosition**：Trilium 默认将新笔记追加到容器末尾，无需手动设置
9. **禁止响应废弃命令**：`/workspace project start` 已废弃，应提示用户使用 `/workspace start`
10. **create_note 必须有 content**：所有 create_note 调用必须包含 content 参数（book 类型传空字符串）
11. **对话缓存保护**：发现 `conversation.log`、`session.md` 或 Trilium 笔记中已有对话缓存数据时，**禁止删除或覆盖**。默认在后面追加新内容。未经用户明确同意，永远不得删除或覆盖已有缓存数据。具体规则：
   - `conversation.log`：**永远禁止 Write 工具**。Write 全量替换整个文件，会丢失全部历史。必须用 `Bash >>` 追加或 Edit 末尾替换。仅当文件不存在时才可 Write 创建新文件。
   - `session.md`：**永远禁止 Write 工具**。所有修改必须用 Edit 做局部替换或末尾追加。Write 会覆盖 LOG/CONTEXT/TASKS 全部历史。
   - Trilium 笔记内容：**项目概述和任务笔记均禁止使用 `write_note(mode="append")`**（会追加到"相关笔记引用"或"→ 项目笔记"链接之后），必须使用 `write_note` 的 `mode="edit"` + `changes` 模式在正确位置插入/更新
   - 归档时只能重命名/移动，不能删除原始文件
12. **跨天不创建新笔记**：`save --auto` 跨天时只生成昨日总结追加到昨日任务笔记末尾，**不创建**今天的每日笔记或任务笔记。创建新笔记由用户 `/workspace continue` 时决定任务方向。生成总结后立即关闭定时任务（CronDelete），后续晚间无需继续定时保存。
13. **Git Co-authored-by 钩子检查**：`/workspace start` 和 `/workspace continue` 必须扫描当前工作目录下所有含 `.git/` 的仓库（当前目录及一级子目录），检查 `.git/hooks/commit-msg` 是否包含 `Co-authored-by: Sisyphus` 标记。未安装或缺失标记的仓库，自动从 `~/.agents/skills/workspace-session-skill/assets/commit-msg-hook.sh` 复制并 `chmod +x`。`/workspace end` 时汇报钩子覆盖情况（列出所有已安装的仓库）。详见下方"Git Hook 检查流程"。
14. **continue 必须读取本地 config.json**：`/workspace continue` 跨天处理时，`daily_notes.root` 和 `project_notes.root` **必须**从本地 `.workspace-session-skill/config.json` 读取，**禁止**使用全局 `~/.agents/skills_settings.json` 中的值。全局配置可能已被其他项目修改，导致每日笔记/任务笔记创建到错误的父目录下。

### 日期格式规范

| 类型 | 格式 | 示例 |
|------|------|------|
| 月度目录 | `YY年M月份` | `26年4月份` |
| 每日笔记 | `YYYY年M月D日 星期X` | `2026年4月2日 星期四` |

**格式变量**：
- YY = 年份后2位（阿拉伯数字）
- YYYY = 年份4位（阿拉伯数字）
- M = 月份（阿拉伯数字，不补零）
- D = 日期（阿拉伯数字，不补零）
- X = 星期（中文：一/二/三/四/五/六/日）

---

## ⚠️ 执行清单（必须按顺序执行）

**重要**：以下步骤**每项必须执行**，完成后在内部标记 ✓。未完成清单的执行视为失败。

---

## Git Hook 检查流程

`/workspace start` 和 `/workspace continue` 执行时必须检查。`/workspace end` 时汇报状态。

### Hook 模板

内置模板位于 `~/.agents/skills/workspace-session-skill/assets/commit-msg-hook.sh`。

Hook 逻辑：每次 `git commit` 后自动在提交消息末尾追加 `Co-authored-by: Sisyphus <sisyphus@ai>`（如已存在则跳过）。设置 `SKIP_AI_TRAILER=1` 环境变量可跳过本次追加，用于纯手工编写的提交。

### 扫描规则

1. 若当前工作目录本身有 `.git/` → 检查当前目录
2. 若当前工作目录无 `.git/` → 扫描所有含 `.git/` 的一级子目录
3. 对每个 git 仓库，检查 `.git/hooks/commit-msg` 是否存在且包含 `Co-authored-by: Sisyphus`

### 部署步骤

| # | 操作 | 命令 |
|---|------|------|
| 1 | 扫描 git 仓库 | `for d in . */; do [ -d "${d}.git" ] \|\| [ -f "${d}.git" ] && echo "${d%/}"; done`（`-f` 兼容 git worktree 的 `.git` 文件） |
| 2 | 解析 hook 路径 | `HOOK_PATH=$(git -C <repo> rev-parse --git-path hooks/commit-msg)` — 自动适配普通仓库和 worktree（worktree 的 `.git` 是文件，hooks 在 gitdir 中） |
| 3 | 检查已有 hook | `grep -q "Co-authored-by: Sisyphus" "$HOOK_PATH" 2>/dev/null` |
| 3a | hook 已包含标记 | 无需操作，标记为 `✓` |
| 3b | hook 不存在 | `cp ~/.agents/skills/workspace-session-skill/assets/commit-msg-hook.sh "$HOOK_PATH" && chmod +x "$HOOK_PATH"` |
| 3c | hook 存在但不含标记（覆盖保护） | **禁止直接覆盖**。读取已有 hook 内容，将 **`assets/commit-msg-body.sh`**（无 shebang 逻辑体，用分隔注释包裹）**追加**到已有 hook 末尾：`cat ~/.agents/skills/workspace-session-skill/assets/commit-msg-body.sh >> "$HOOK_PATH"`<br>• 追加内容以 `# === workspace-session-skill` 开头、`# === end workspace-session-skill ===` 结尾，清晰标记边界<br>• 由于不含 `#!/bin/sh`，不会在脚本中间产生无效 shebang<br>• 追加后验证已有 hook 仍可正常执行 |
| 4 | 汇报结果 | 格式：`✓ <repo> (已激活)` / `→ <repo> (已部署)` / `⊕ <repo> (已追加到已有 hook)` |

### end 命令汇报

`/workspace end` 执行时扫描所有 git 仓库，汇报 hook 状态：

```
🔧 Git Hook 状态
   ✓ ai-agent-harmoney       — Co-authored-by 已激活
   ✓ i3d544-harmony          — Co-authored-by 已激活
   ⚠ opencode               — 未安装（非活跃项目）
```

---

## start 命令

开始新的工作会话。

### 命令格式

```
/workspace start              # 使用当前目录
/workspace start D:/work/api  # 指定目录
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 获取当前日期 | Claude 直接计算当前日期和星期，格式：`YYYY年M月D日 星期X`（如：2026年4月2日 星期四）。**不要调用任何 API 获取星期**，Claude 根据系统日期直接计算。 | 日期格式正确，星期正确 |
| 2 | 创建工作目录 | 创建 `.workspace-session-skill/`、`screens/`、`Logs/`、`docs/` 目录（如不存在）。若存在 `res/`，迁移到 `screens/`。 | 所有标准目录存在 |
| 2b | 检查/部署 Git Hook | 扫描当前目录及一级子目录所有 git 仓库，按"Git Hook 检查流程"执行。缺失则自动从 `assets/commit-msg-hook.sh` 部署。 | 所有 git 仓库已安装 hook |
| 2c | 询问 Git 同步 | 询问用户："是否初始化顶层 Git 用于跨设备同步工作区数据？" 若确认，执行"Git 工作区初始化"流程（见下方）。若拒绝，`config.json` 中标记 `sync_enabled: false`。 | 用户已选择 |
| 3 | 读取配置文件 | 从 `~/.agents/skills_settings.json` 读取 `workspaceSession` | 配置加载成功 |
| 4 | 同步配置到本地 | 写入 `.workspace-session-skill/config.json` | 文件存在 |
| 5 | 询问任务类型 | "项目任务" or "简单任务" | 用户选择 |
| 6 | 检查会话文件和缓存 | `.workspace-session-skill/session.md` 和 `conversation.log` | 存在则按缓存保护规则处理（见下方） |
| 7 | 执行任务类型分支 | 见下方详细流程 | 按类型执行 |
| 8 | 设置自动保存 | CronCreate：`cron="7 * * * *"`，`prompt="/workspace save --auto"`。返回 job_id 后，**立即**将其写入 `session.md`（`cron_job_id={job_id}`）和 `config.json`（`autosave.cron_job_id={job_id}`） | job_id 已持久化 |
| 9 | 输出会话状态 + openspec 检查 | 显示工作目录、笔记位置、任务信息。**检查 `openspec/` 目录**：若不存在或为空，提醒用户："💡 建议执行 `openspec init` 来管理变更提案"。若已初始化，确认："✅ OpenSpec 已配置"。 | 用户确认 |

### 缓存保护处理（步骤 6 详细说明）

当检测到已有会话文件或对话日志时，按以下规则处理：

| 检测到的情况 | 处理方式 |
|-------------|---------|
| 仅 session.md 存在（无 conversation.log） | 提示用户："发现已有会话记录，是否继续上次的工作？1. 继续工作（推荐） 2. 开始新会话（旧数据将归档保留）" |
| 仅 conversation.log 存在（无 session.md） | 保留日志文件，在末尾继续追加，不截断不覆盖 |
| 两者都存在 | 提示用户："发现已有会话和对话记录，如何处理？1. 继续上次工作（推荐） 2. 归档旧数据后开始新会话" |
| 有归档目录 archive/ | 不动归档文件，仅处理当前活跃文件 |

**强制规则**：
- **禁止**删除任何已有缓存数据
- **禁止 Write 覆盖** conversation.log 已有内容（必须用 `Bash >>` 追加）
- **禁止 Write 覆盖** session.md 已有内容（必须用 Edit 局部替换）
- 归档操作只能**移动**（重命名），不能删除
- 用户选择"开始新会话"时，旧数据自动归档到 `archive/` 目录

### 任务类型分支流程

#### 项目任务

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 7.1 | 检查 project_notes.root | 验证配置存在 | 未配置则提示用户选择：配置后继续 或 改为简单任务 |
| 7.2 | 询问项目名称 | 获取用户输入 | 名称确定 |
| 7.3 | 创建项目笔记 | `create_note(parentNoteId=project_notes.root, title=项目名称, type=book, content="")` | 返回 project_note_id |
| 7.4 | 创建项目概述 | `create_note(parentNoteId=project_note_id, title="项目概述", type=text, format="markdown", content=概述模板)` → 返回 `overview_note_id`，**必须存储**供 new-phase 使用 | 子笔记已创建，ID 已记录 |
| 7.5 | 创建开发计划子文件夹 | `create_note(parentNoteId=project_note_id, title="开发计划", type=book, content="")` | 返回 plan_folder_id |
| 7.6 | 创建编码进度子文件夹 | `create_note(parentNoteId=project_note_id, title="编码进度", type=book, content="")` | 返回 progress_folder_id |
| 7.7 | 检查/创建月度目录 | `search_notes(ancestorNoteId=daily_notes.root, query="title:{YY}年{M}月份")`，无则创建：`create_note(parentNoteId=daily_notes.root, title="{YY}年{M}月份", type=book, content="")` | 返回 month_dir_id |
| 7.8 | 检查/创建每日笔记 | `search_notes(ancestorNoteId=month_dir_id, query="title:{YYYY}年{M}月{D}日")`，无则创建：`create_note(parentNoteId=month_dir_id, title="{YYYY}年{M}月{D}日 星期{X}", type=book, content="")` | 返回 daily_note_id |
| 7.9 | 创建初始任务笔记 | `create_note(parentNoteId=daily_note_id, title="{项目名}-进行中", type=text, format="markdown", content=任务模板)` | 返回 task_note_id |
| 7.10 | 更新项目概述引用 | 在项目概述"进度追踪"添加任务笔记链接（使用 month_dir_id 构建完整路径） | 链接已添加 |
| 7.11 | 更新配置 | 写入 config.json（嵌套结构）：`daily_notes.current_note_id`、`daily_notes.current_note_date`、`daily_notes.month_dir_id`、`daily_notes.current_task_note_id`；`project_notes.plan_folder_id`、`project_notes.progress_folder_id`、`project_notes.overview_note_id` | 配置已更新 |
| 7.12 | 创建会话文件 | 写入 `session.md`，包含全部必填字段：`workspace`、`started`/`last_update`、`status=active`、`task_type=project`、`daily_note_id`、`daily_note_date`、`month_dir_id`、`current_task_note_id`、`project_note_id`、`project_name`、`plan_folder_id`、`progress_folder_id`、`overview_note_id`、`task_started_at={当前时间}` | 文件已创建 |
| 7.13 | 初始化对话日志 | 创建 `conversation.log` | 文件已创建 |

**项目概述模板**（使用 markdown 格式，初始创建）：
```markdown
# 项目概述

## 基本信息
- **项目名称**：{项目名称}
- **开始日期**：{YYYY-MM-DD}
- **状态**：进行中

## 阶段概览

| 阶段 | 计划 | 进度 | 状态 |
|------|------|------|------|

## 进度追踪

## 相关笔记引用
```

**项目概述模板**（更新后，包含进度条目）：
```markdown
# 项目概述

## 基本信息
- **项目名称**：{项目名称}
- **开始日期**：{YYYY-MM-DD}
- **状态**：进行中 | 已完成 | 已暂停

## 阶段概览

| 阶段 | 计划 | 进度 | 状态 |
|------|------|------|------|
| Phase 0: {阶段名} | [→ 计划](#root{project_root_path}/{project_note_id}/{plan_folder_id}/{phase_plan_id}) | [→ 进度](#root{project_root_path}/{project_note_id}/{progress_folder_id}/{phase_progress_id}) | 进行中 |

## 进度追踪

### {YYYY-MM-DD} ({星期})
- [→ 任务笔记: {项目名}](#root{daily_root_path}/{month_dir_id}/{daily_note_id}/{task_note_id})
- ✅ {已完成项}
- ⏳ {进行中项}

## 相关笔记引用
```

**任务笔记模板**（使用 markdown 格式）：
```markdown
# {项目名}

## 任务描述
初始任务，项目启动。

## 进度
- [ ] 项目初始化

## 今日工作记录


---
[→ 项目笔记](#root{project_root_path}/{project_note_id})
```

**初始任务笔记创建后，立即更新项目概述**：
```markdown
## 进度追踪

### {YYYY-MM-DD} ({星期})
- [→ 任务笔记: {项目名}](#root{daily_root_path}/{month_dir_id}/{daily_note_id}/{task_note_id})
```

**链接路径构建详解**：

完整链接格式：`#root/{daily_root_path}/{month_dir_id}/{daily_note_id}/{task_note_id}`

| 组件 | 来源 | 示例 |
|------|------|------|
| `#root` | 固定前缀 | `#root` |
| `daily_root_path` | 配置 `daily_notes.root_path` 去掉 `#root/` 前缀 | `V83RZAMdWE4t/j7IuML86uLAF/fGRkBZG1A113` |
| `month_dir_id` | 步骤 7.7 创建/查找时获取，存入 config.json 和 session.md | `AbCdEfGh1234` |
| `daily_note_id` | 步骤 7.8 创建时获取，存入 config.json 和 session.md | `TnB8WuXqf9VO` |
| `task_note_id` | 步骤 7.9 创建时获取 | `gJw8ODEyJ1nw` |

**构建示例**：
```
原始配置：
  daily_notes.root_path: "#root/V83RZAMdWE4t/j7IuML86uLAF/fGRkBZG1A113"
  
创建笔记后获取：
  month_dir_id: AbCdEfGh1234
  daily_note_id: TnB8WuXqf9VO
  task_note_id: gJw8ODEyJ1nw

构建链接：
  #root/V83RZAMdWE4t/j7IuML86uLAF/fGRkBZG1A113/AbCdEfGh1234/TnB8WuXqf9VO/gJw8ODEyJ1nw
```

**注意**：`root_path` 已包含 `#root/` 前缀，构建链接时需去掉再重新拼接。

#### 简单任务

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 7.1 | 检查/创建月度目录 | `search_notes(ancestorNoteId=daily_notes.root, query="title:{YY}年{M}月份")`，无则创建：`create_note(parentNoteId=daily_notes.root, title="{YY}年{M}月份", type=book, content="")` | 返回 month_dir_id |
| 7.2 | 检查/创建每日笔记 | `search_notes(ancestorNoteId=month_dir_id, query="title:{YYYY}年{M}月{D}日")`，无则创建：`create_note(parentNoteId=month_dir_id, title="{YYYY}年{M}月{D}日 星期{X}", type=book, content="")` | 返回 daily_note_id |
| 7.3 | 询问任务名称 | 获取用户输入的任务描述 | 名称确定 |
| 7.4 | 创建初始任务笔记 | `create_note(parentNoteId=daily_note_id, title="{任务名}-进行中", type=text, format="markdown", content=任务模板)` | 返回 task_note_id |
| 7.5 | 更新配置 | 写入 config.json（嵌套结构）：`daily_notes.current_note_id`、`daily_notes.current_note_date`、`daily_notes.month_dir_id`、`daily_notes.current_task_note_id`；`autosave.cron_job_id={job_id}` | 配置已更新 |
| 7.6 | 创建会话文件 | 写入 `session.md`，包含全部必填字段：`workspace`、`started`/`last_update`、`status=active`、`task_type=simple`、`daily_note_id`、`daily_note_date`、`month_dir_id`、`current_task_note_id`、`task_started_at={当前时间}` | 文件已创建 |
| 7.7 | 初始化对话日志 | 创建 `conversation.log` | 文件已创建 |

**任务笔记模板**（简单任务）：
```markdown
# {任务名}

## 任务描述

## 进度
- [ ] 待办项

## 今日工作记录

```

### 目录结构

```
{工作目录}/.workspace-session-skill/
├── config.json          # 项目本地配置
├── session.md           # 当前会话状态
└── conversation.log     # 对话日志
```

---

## continue 命令

继续上次的工作会话。

### 命令格式

```
/workspace continue
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 获取当前日期 | Claude 直接计算当前日期和星期。**不要调用任何 API 获取星期**，Claude 已知当前日期，可直接计算星期几。 | 日期格式正确，星期正确 |
| 2 | 读取会话文件 | `.workspace-session-skill/session.md` | 解析成功 |
| 2a | 读取本地配置文件 | `.workspace-session-skill/config.json`，获取 `daily_notes.root`、`daily_notes.root_path`、`project_notes.root`、`project_notes.root_path`。**必须使用本地 config.json 中的值**，禁止使用全局 `~/.agents/skills_settings.json` 中的值（全局配置可能已被其他项目修改）。 | 配置已加载 |
| 2b | 检查/部署 Git Hook | 扫描当前目录及一级子目录所有 git 仓库，按"Git Hook 检查流程"执行。缺失则自动从 `assets/commit-msg-hook.sh` 部署。 | 所有 git 仓库已安装 hook |
| 2c | 会话文件不存在时 | 检查 `conversation.log` 是否存在：<br>• 存在：提示"发现对话日志但无会话文件，建议：1. `/workspace start` 开始新会话（日志保留） 2. 手动恢复"<br>• 不存在：提示"请先使用 `/workspace start` 开始会话" | 已提示用户 |
| 3 | 检查日期变化 | 比较 `daily_note_date` 与当前日期 | 判断是否跨天 |
| 4 | 跨天处理 | 见下方详细流程 | 按情况执行 |
| 4b | 检查昨日总结 | 跨天时使用**跨天前**的 `current_task_note_id`（即昨日任务笔记）检查是否有每日总结章节（搜索"📊 当日总结"或"## 📊"）。无则按 `references/daily-summary-template.md` 补生成。**勿用步骤 4 更新后的新 ID**。 | 总结已存在或补生成 |
| 5 | 验证定时任务 | CronList 检查任务存在。无则 CronCreate 重建，返回的 job_id 写入 `session.md`（`cron_job_id`）和 `config.json`（`autosave.cron_job_id`） | 任务存在或已重建并持久化 |
| 6 | 展示上下文摘要 | 显示任务、决策、下一步、OpenSpec 变更状态 | 用户可见 |

### 跨天处理流程

当检测到 `daily_note_date` 与当前日期不同时：

| 情况 | 操作 |
|------|------|
| 同一天 | 无需特殊处理，继续当前会话 |
| 跨天（同月） | 创建新每日笔记，更新 month_dir_id、current_note_id、current_note_date |
| 跨月 | 创建新月度目录 + 新每日笔记，更新所有相关 ID |

**跨天处理步骤**（所有 `daily_notes.root` / `project_notes.root` 均来自步骤 2a 读取的**本地** `config.json`，非全局配置）：

> ⚠️ **严禁使用 `get_special_note(kind="day")` 工具！** Trilium 的 `get_special_note(kind="day")` 返回内置日历笔记（标题格式 "DD - 周X"、父节点为日历月份 `MM - 月份名`），与 workspace 笔记体系完全隔离。使用它会导致每日笔记创建到错误的位置。必须用 `search_notes()` + `create_note()` 手动查找/创建。

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 4.1 | 检查月度目录 | `search_notes(ancestorNoteId={本地config.json的daily_notes.root}, query="title:{YY}年{M}月份")`。**不可用 get_special_note(kind="day") 替代**。 | 存在则获取 ID |
| 4.2 | 无则创建月度目录 | `create_note(parentNoteId={本地config.json的daily_notes.root}, title="{YY}年{M}月份", type=book, content="")` | 返回 month_dir_id |
| 4.3 | 检查/创建每日笔记 | `search_notes(ancestorNoteId=month_dir_id, query="title:{YYYY}年{M}月{D}日")`，无则创建：`create_note(parentNoteId=month_dir_id, title="{YYYY}年{M}月{D}日 星期{X}", type=book, content="")`。**不可用 get_special_note(kind="day") 替代**。 | 返回 daily_note_id |
| 4.3b | ⚠️ 验证每日笔记位置 | **必须**调用 `get_note(noteId=daily_note_id, include_content=false)` 验证：(1) `parentNoteIds` 包含 `month_dir_id`；(2) title 格式为 `YYYY年M月D日 星期X`（非 Trilium 日历格式 `DD - 周X`）；(3) type 为 `book`。**任一条件不满足 → 说明误用了 get_special_note(kind="day")，返回步骤 4.3 重新创建**。 | parent 正确、title 格式正确、type=book |
| 4.4 | 更新会话文件 | 更新 `daily_note_id`、`daily_note_date`、`month_dir_id`，重置 `task_started_at` 为当前时间 | 文件已更新 |
| 4.5 | 更新配置文件 | 写入 config.json：`daily_notes.current_note_id`、`daily_notes.current_note_date`、`daily_notes.month_dir_id`（嵌套结构） | 配置已更新 |
| 4.6 | 询问任务延续 | "是否继续之前未完成的任务？" | 用户选择 |

**任务延续选项**：
- **继续**：创建新任务笔记，标题为 `{任务名}-继续`，复制未完成项到新笔记
- **新任务**：询问新任务名称，创建新任务笔记
- **跳过**：不创建任务笔记，仅恢复会话

### 输出格式

```
📋 工作会话恢复
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
工作目录: {workspace}
任务类型: {task_type}
每日笔记: {daily_note_id}
项目笔记: {project_note_id} (项目任务时)
开始时间: {started}
上次更新: {last_update}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 当前任务: {tasks}
✅ 已完成: {completed}
🔑 关键决策: {decisions}
🔄 活跃 Change: {active_change_id} ({change_stage})  (如无则为 "无")
```

---

## save 命令

保存当前工作进度。

### 命令格式

```
/workspace save                        # 基本保存
/workspace save "完成了认证模块设计"    # 带摘要保存
/workspace save --auto                 # 自动保存（Cron调用）
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 0 | 派发后台子 Agent | spawn 后台子 Agent（`run_in_background=true`），prompt 按 `references/background-agent.md` 模板组装。**不指定 agent_type**（使用通用 Agent 确保始终可用）。主 Agent 立即返回 "💾 保存已后台执行，完成后通知"。子 Agent 执行下方清单。 | 子 Agent 已启动 |
| 0b | 子 Agent: 检查会话文件 | 读取 `session.md` | 文件存在且有效 |
| 1 | 子 Agent: 更新时间戳 | `last_update` = 当前时间（ISO 8601 格式） | 时间戳已更新 |
| 2 | 子 Agent: 更新任务状态 | 同步 TASKS 部分，标记已完成项 | 任务列表已更新 |
| 3 | 子 Agent: 更新上下文 | 添加决策、文件引用到 CONTEXT 部分 | 内容已追加 |
| 4 | 子 Agent: 检测OpenSpec变更 | 扫描 `openspec/changes/` 目录，检测最近修改的 change，更新 `session.md` 的 `active_change_id` 和 `change_stage` 字段。目录不存在或为空时设为空。 | 字段已更新 |
| 5 | 子 Agent: 自动归档检查 | 检查 `session.md` 行数。超过 500 行时，执行按周归档：将 CONTEXT 和 LOG 中超过 2 周的条目移至 `context-archive/YYYY-Www.md`，裁剪 session.md。同时将旧 conversation.log 条目（超过 2 周的）归档到 context-archive 对应周文件中。 | 归档已执行或阈值未触发 |
| 6 | 子 Agent: 追加日志 | 在 LOG 部分添加本次对话摘要 | 日志已追加 |
| 7a | 子 Agent: 同步项目概述（项目任务时） | 更新 Trilium 项目概述的"进度追踪"部分（工作块级摘要） | 进度已同步 |
| 7b | 子 Agent: 同步任务笔记（项目任务时） | 更新 Trilium 任务笔记的"进度"和"今日工作记录"部分（详细展开） | 任务笔记已同步 |
| 7c | 子 Agent: 同步阶段进度笔记（有活跃阶段时） | 更新 Trilium 阶段进度笔记的"任务描述"、"项目结构"、"进度"、"门禁验证"、"关键技术决策"、"今日工作记录"部分 | 阶段进度已同步 |

### 数据保留策略

**session.md CONTEXT 清理**：
- CONTEXT 部分记录关键决策和文件引用，随每次 save 追加
- 每月首次 save 时，检查 CONTEXT 条目数量
- 超过 20 条时，将 60 天前的旧条目移到 `## CONTEXT_ARCHIVE`（折叠，不删除）
- 保留近 60 天内容在 `## CONTEXT`，旧内容在 `## CONTEXT_ARCHIVE`

**conversation.log 保留**：
- 每次 save 追加一行摘要（非完整对话，仅时间戳+事件摘要）
- 每行约 100 字符，全年约 36KB（每天 10 次 save）
- 无需主动截断（增长速度极慢）
- 如需归档：`mv conversation.log archive/{YYYY-MM-DD}-conversation.log`

### 检测 OpenSpec 变更（步骤 4 详细说明）

**操作**：扫描 `openspec/changes/` 目录，被动记录活跃 Change。

| 检测情况 | 处理方式 |
|---------|---------|
| `openspec/changes/` 目录存在且有子目录 | Glob 列出所有子目录，按修改时间排序，取最近修改的 change；读取 `proposal.md` 判断阶段（存在 proposal 无 tasks 完成=propose，tasks 全部完成=apply，目录中有 `.archived` 标记=archive）。写入 `session.md` 的 `active_change_id` 和 `change_stage` 字段。 |
| 多个活跃 change | 取最近修改的 change 作为 `active_change_id`，可列出其他 change 到 CONTEXT |
| `openspec/changes/` 目录不存在或为空 | `active_change_id` 和 `change_stage` 设为空，无操作 |

**实现方式**：使用 Glob 工具扫描文件系统，不调用 OpenSpec CLI 或技能。目录不存在时静默跳过。

### ⚠️ 项目概述写入铁律

项目概述笔记末尾的 `## 相关笔记引用` 是全文最稳定的锚点，所有写入**必须**遵循此模式。

**唯一正确模式**：`mode="edit"` + `changes`，`old_string` = `"## 相关笔记引用"`

**三条禁令**：

| 禁止 | 原因 |
|------|------|
| `mode="append"` | 追加到全文末尾 = 插在 `## 相关笔记引用` 之后，破坏笔记结构 |
| `mode="replace"` | 不先读全再写 = 覆盖其他 agent 并发写入的内容 |
| 无锚点 `mode="edit"` | 每次读全文找边界 = 误匹配风险，尤其是大笔记 |

详见 `references/trilium-integration.md`。

### 同步项目概述（项目任务）

当 `task_type=project` 时，需要同步更新 Trilium 中的项目概述笔记：

**操作步骤**：
1. 获取项目概述笔记 ID（从 session.md 的 `overview_note_id` 获取）
2. 读取项目概述当前内容（使用 `format: "markdown"`），查找当天日期条目是否已存在
3. **当天条目不存在**：使用锚点 `"## 相关笔记引用"` 在其前面插入新日期条目
4. **当天条目已存在**：精确替换当天条目内容

**首次创建 + 后续追加（统一模式）**：
```
// 永远用 "## 相关笔记引用" 作为锚点，在其前面插入
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{
    old_string: "## 相关笔记引用",
    new_string: "### {YYYY-MM-DD} ({星期})\n\n- [→ 任务笔记: {项目名}](#root{daily_root_path}/{month_dir_id}/{daily_note_id}/{task_note_id})\n- ✅ {已完成项}\n- ⏳ {进行中项}\n\n## 相关笔记引用"
  }]
)
```

**更新已有日期条目**：
```
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{old_string: "当天旧内容", new_string: "更新后内容"}]
)
```

**注意**：
- **唯一锚点**：永远只用 `"## 相关笔记引用"`，不要用 `"## 进度追踪\n\n## 相关笔记引用"`（多一个依赖就多一个断裂点）
- 链接必须使用 `#root/完整路径/noteId` 格式
- "相关笔记引用"用于用户主动添加其他引用

### 同步任务笔记（项目任务）

当 `task_type=project` 时，同步更新 Trilium 中的任务笔记（当日详细任务）：

**操作步骤**：
1. 从 `current_task_note_id` 获取任务笔记 ID
2. 读取任务笔记当前内容
3. 使用 `write_note` 的 `mode="edit"` + `changes` 模式更新"进度"部分的 checkbox 状态和新增项
4. 使用 `write_note` 的 `mode="edit"` + `changes` 模式追加"今日工作记录"部分的条目

**⚠️ 禁止使用 `write_note(mode="append")`**：任务笔记末尾有 `[→ 项目笔记](#root/...)` 链接，追加会插入到链接之后导致布局错乱。必须使用 `write_note` 的 `mode="edit"` + `changes` 模式在"今日工作记录"区域内精确插入。

**内容分工原则**：

| 位置 | 抽象层级 | 规则 |
|------|---------|------|
| 项目概览 | 工作块（合并同类项） | 将相关工作合并为一条，如"代码审查修复(9项)"而非逐条列出 |
| 任务笔记 | 详细（逐条展开） | 保留全部 checkboxes + 逐项工作记录 + 完整上下文 |

**示例**：
```
项目概览:  ✅ 代码审查与安全审查 (9 fixes + skill-vetter SAFE)
任务笔记:  - [x] SQL注入防护 (sq_escape)
           - [x] db_init symlink路径修复
           - [x] jq依赖检测
           - [x] duration_ms写入
           ...（全部9项）
```

### 同步阶段进度笔记（项目任务 + 活跃阶段时）

当 `task_type=project` 且存在 `active_phase_progress_id` 时，同步阶段进度笔记：

**操作步骤**：
1. 从 session.md 获取 `active_phase_progress_id`
2. 读取阶段进度笔记当前内容（使用 `format: "markdown"`）
3. **计算时间跨度（小时级日志）**：
   - 读取 session.md 中的 `task_started_at`。
   - 若 `task_started_at` 存在，计算其到当前系统时间（last_update）的时间段，格式化为 `HH:mm-HH:mm`（例如 `15:14-15:40`）。
   - 将当前会话中执行的特定任务名称与简短摘要整理成一行表格数据：
     `| HH:mm-HH:mm | Task {N}.{n}: {任务名} | {摘要} |`
   - 如果用户运行 `/workspace save "完成了XXX"`，则使用传入的文字作为摘要；否则根据本轮对话的 LOG 内容自动提炼一句话摘要。
   - 记录完毕后，**将 `task_started_at` 更新为当前系统时间**，保存到 `session.md` 和 `config.json` 中，以便下一次任务时间块能够全新开始追踪。
4. 使用 `write_note` 的 `mode="edit"` + `changes` 模式更新以下部分：
   - **任务描述**：从对应阶段计划笔记的 `## 目标` 部分读取最新内容，全量替换 `## 任务描述` 区域（保持与计划基线同步）。
   - **项目结构**：执行 `git diff --name-only HEAD -- '*.ets' '*.ts' '*.cpp' '*.h' '*.json5' 2>/dev/null || git ls-files -- '*.ets' '*.ts' '*.cpp' '*.h' '*.json5'` 扫描本阶段涉及的文件，将新增文件路径追加到 `## 项目结构` 代码块中（去重，保留既有条目）。新仓库无 HEAD 时自动降级为 `git ls-files`。
   - **进度**：同步 checkbox 状态和新增项（与当前 `session.md` 的 TASKS 全量同步）。
   - **门禁验证**：扫描 session.md CONTEXT 中的 `## 门禁` 子块，解析 Markdown 表格行 `| 验证项 | 状态 | 说明 |`，逐行合并到阶段进度笔记的 `## 门禁验证` 表格（同验证项覆盖状态，新验证项追加行）。
   - **关键技术决策**：扫描 session.md CONTEXT 中的 `## 决策:` 子块，解析 `{决策} → 原因: {原因} → 影响: {影响范围}` 格式，追加到阶段进度笔记的 `## 关键技术决策` 表格。
   - **今日工作记录**：将第 3 步算出的 `HH:mm-HH:mm` 这一行追加到今日进度笔记的 `## 今日工作记录` 部分的相应日期表格中。

**⚠️ 禁止使用 `write_note(mode="append")`**：阶段进度笔记末尾有跳转链接，追加会插入到错误位置。必须使用 `write_note` 的 `mode="edit"` + `changes` 模式定位 `## 今日工作记录` 并精确在表格末尾追加行。

**今日工作记录格式**：
```
| HH:mm-HH:mm | Task {N}.{n}: {任务名} | {一句话摘要} |
```

**内容分工（三层）**：

| 位置 | 抽象层级 | 规则 |
|------|---------|------|
| 项目概述 > 进度追踪 | 工作块摘要 | 合并同类项，如"代码审查修复(9项)"，而非逐条展开 |
| 阶段进度 > 任务描述 | 与计划同步 | 每次 save 从计划笔记的"目标"全量拉取 |
| 阶段进度 > 项目结构 | 自动扫描 | 每次 save 执行 `git diff --name-only` 扫描变更文件 |
| 阶段进度 > 今日工作记录 | 小时级详细展开 | 由 `task_started_at` 自动计算的 HH:mm-HH:mm 格式，每项一行 |
| 任务笔记 > 进度 | Checkbox + 详细记录 | 保留全部 checkboxes 和日常对话记录 |

### --auto 参数特殊处理

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| **0** | **跨天检测（最优先）** | 在任何其他逻辑之前，先比较 `daily_note_date` 与当前日期。若跨天，检查 conversation.log 是否有内容。若有内容，执行跨天流程（步骤 0a-0c），然后退出。若 conversation.log 为空，直接跳过（无工作内容无需总结）。 | 跨天总结已生成或确认无需生成 |
| **0a** | **跨天 + 有新对话：先同步保存** | 检测是否有新对话（mtime > last_update）。**若有新对话，必须先执行一次同步保存（不走后台子 Agent，主 Agent 直接按 save 清单步骤 1-6c 执行），确保 session.md、项目概述、任务笔记、阶段进度全部更新到最新状态，然后再生成总结。** 若为新对话触发的 cron 调用（当前上下文中有实质性工作），也视为有新对话。保存完成后，`last_update` 已更新，`session.md` TASKS/CONTEXT 已同步。 | 保存完成，数据已是最新 |
| **0b** | **生成昨日总结** | 执行跨天总结流程（步骤 C1-C6）。此时 session.md 和 Trilium 笔记已是最新状态（步骤 0a 已保存），总结不会遗漏任何对话信息。 | 总结已生成并追加到昨日任务笔记 |
| **0c** | **关闭定时任务** | `CronDelete(id: cron_job_id)`，停止自动保存。跨天总结已生成，后续为晚间时段无需继续定时保存。明天 `/workspace continue` 时会重新创建。**不创建新一天的笔记。** | 定时任务已删除 |
| 1 | 检查日志修改时间 | 获取 `conversation.log` 的 mtime | 时间戳获取成功 |
| 2 | 与 last_update 比较 | 判断是否有新对话 | 有/无新对话 |
| 3 | 无新对话（mtime ≤ last_update） | 执行**二级验证**（步骤 3b）。若二级验证也判定无新对话，跳过保存，静默退出。 | 不执行后续步骤 |
| 3b | 二级验证（mtime 判定无新对话时执行） | **mtime 检测可能因文件系统延迟、日志未及时刷盘等原因产生假阴性。** 当 mtime 判定无新对话时，必须执行以下检查，**任一命中即视为"有新对话"，跳转到步骤 4**：<br>• **上下文感知**：当前 cron 触发周期内，对话中是否发生了实质性工作（代码编辑、文件创建/修改、构建执行、git 操作、配置变更）？若是 → 视为有新对话<br>• **session.md 变更**：session.md 的 mtime 是否晚于 last_update？若是 → 视为有新对话<br>• **git 变更**：执行 `git diff --stat HEAD 2>/dev/null` 或 `git status --short 2>/dev/null`，是否有未提交的变更？若有且这些变更产生于上次 save 之后 → 视为有新对话<br>• **显式标记**：用户是否在对话中明确要求保存或提到需要持久化？若是 → 视为有新对话<br>上述检查全部未命中时，才确认"确实无新对话"。 | 避免因 mtime 假阴性导致漏保存 |
| 4 | 有新对话 | 执行正常保存流程（后台子 Agent 异步保存） | 保存完成 |

### 跨天生成昨日总结

当 `save --auto` 检测到跨天时，生成昨日工作总结并追加到昨日任务笔记末尾：

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| C1 | 获取 git log | `git log --since="{{daily_note_date}}T00:00:00+08:00" --until="{{today}}T00:00:00+08:00" --format="%h %s (%ad)" --date=format:"%H:%M"` | 提交记录已获取 |
| C2 | 估算 token 消耗 | 读取 `conversation.log` 字符数，以 `char_count / 4` 估算 token 数，四舍五入到千位 | token 估算值 |
| C3 | 读取任务状态 | 从 `session.md` 的 TASKS 部分获取当前任务列表状态 | 任务快照 |
| C4 | 读取 change 信息 | 若 `active_change_id` 非空，读取对应 `openspec/changes/{id}/` 的状态 | change 状态 |
| C5 | 生成总结内容 | 按 `references/daily-summary-template.md` 模板格式生成昨日总结 | 格式正确 |
| C6 | 追加到昨日任务笔记 | 使用 `write_note` 的 `mode="edit"` + `changes` 模式，在昨日任务笔记末尾追加总结内容 | 内容已追加 |

**⚠️ 跨天检测逻辑**：`daily_note_date`（如 "2026-05-18"）与当前日期比较，仅当不同且 conversation.log 有内容时才生成总结。**跨天时若有新对话，必须先同步保存（步骤 0a）再生成总结，不能走后台子 Agent。**

**⚠️ 不创建新笔记**：跨天只生成昨日总结，不创建今天的每日笔记或任务笔记。用户明天 `/workspace continue` 时自行决定新任务。

**⚠️ 跨天总结后关闭定时任务**：生成昨日总结说明当天工作已结束（晚间时段），已在步骤 0c 中关闭定时任务。

---

## end 命令

结束工作会话。

### 命令格式

```
/workspace end
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 执行最终保存（同步） | **不走后台子 Agent**。主 Agent 直接按 save 清单步骤 1-6c 同步执行（跳过步骤 0 的 spawn 操作），确保 session.md 和 Trilium 笔记更新完成后才继续后续步骤。 | 状态已保存且写入完成 |
| 1b | 汇报 Hook 状态 | 扫描所有 git 仓库并报告 Co-authored-by hook 安装状态（按"Git Hook 检查流程"中 end 命令汇报格式） | 状态已汇报 |
| 2 | 删除定时任务 | 调用 `CronDelete(id: cron_job_id)` | 任务已删除 |
| 3 | 更新状态 | 会话文件 `status: completed` | 状态已更新 |
| 4 | 询问归档选项 | 提供选项：<br>• **保留**（默认） - 保持当前状态，下次可继续<br>• **归档** - 移动到 archive/，数据完整保留<br>• ⚠️ 删除 - **需要二次确认**，明确告知用户数据将永久丢失 | 用户选择并执行 |

### 归档选项详细说明

**保留**（默认推荐）：
- 会话文件和对话日志保持原位
- 下次 `/workspace continue` 可直接恢复

**归档**：
- `session.md` → `archive/{YYYY-MM-DD}-session.md`
- `conversation.log` → `archive/{YYYY-MM-DD}-conversation.log`
- 归档文件永远保留，不会被自动清理

**删除**（需二次确认）：
- 必须明确告知用户："⚠️ 此操作将永久删除会话文件和对话记录，无法恢复。确定要继续吗？"
- 用户必须明确回复"确认删除"或"是"才能执行
- 任何模糊回答（如"嗯"、"ok"）均视为拒绝，不执行删除
- 即使删除，归档目录中的历史数据不受影响

---

## new-task 命令

创建新的任务笔记。**名称参数必填**。

### 命令格式

```
/workspace new-task 代码审查
/workspace new-task 推流插件测试
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 获取每日笔记 ID | 从 config.json 读取 `current_note_id` | noteId 有效 |
| 2 | 创建任务笔记 | `create_note(parentNoteId=daily_note_id, title="{任务名}-进行中", type=text, format="markdown", content=任务模板)` | 笔记已创建 |
| 3 | 有项目笔记时 | 添加双向引用链接：<br>• 任务笔记开头添加项目笔记跳转链接<br>• 项目概述添加任务笔记引用 | 链接已添加 |
| 4 | 更新配置 | 写入 config.json：`daily_notes.current_task_note_id={新任务ID}` | 配置已更新 |
| 5 | 更新会话文件 | 追加任务到 TASKS 部分，更新 `task_started_at` 为当前时间（ISO 8601），重置计时块 | 任务已记录 |

---

## new-phase 命令

为项目任务创建新阶段，生成配对的计划笔记（存放在 `开发计划` 子文件夹内）和进度笔记（存放在 `编码进度` 子文件夹内）。

### 命令格式

```
/workspace new-phase [阶段号] [阶段名称]
```

**示例**：
```
/workspace new-phase 0 "核心验证"
/workspace new-phase 1 "业务注入"
```

### 前置条件

- `task_type=project`（非项目任务时提示无法使用）
- 必须已初始化项目笔记。若项目的 `开发计划` 或 `编码进度` 子文件夹不存在，则在本次命令执行时自动创建（支持无缝迁移老项目）。

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 读取会话文件 | 读取 `session.md`，确认 `task_type=project` | 类型为 project |
| 2 | 解析阶段参数 | 解析输入参数。接受两个独立参数：`[阶段号]`（纯数字，如 `0`）与 `[阶段名称]`（如 `核心验证`）。若用户传入了单个字符串参数，尝试通过正则表达式匹配 `(?:Phase\s*)?(\d+)[:：\s]\s*(.*)` 提取阶段号与名称，失败则报错。 | 阶段号 N 与阶段名称已提取 |
| 3 | 检查子文件夹与迁移 | 检查 `session.md` 中是否存在 `plan_folder_id` 和 `progress_folder_id` 引用。<br>• **存在**：直接使用。<br>• **缺失或不可用（兼容老项目迁移）**：在 Trilium 中通过 `project_note_id` 查找是否存在名称为 `"开发计划"` 和 `"编码进度"` 的子笔记。若已存在，直接获取其 ID ；若不存在，则使用 `create_note(parentNoteId=project_note_id, title="...", type="book", content="")` 主动创建它们。获取 ID 后同步更新 `session.md` 和 `config.json` 中的 `plan_folder_id` 和 `progress_folder_id` 字段。 | 子文件夹 ID 可用，且本地状态已同步 |
| 4 | 创建阶段计划笔记 | 在 `plan_folder_id` 下创建 `[v1.0] Phase {N}: {阶段名}`（text类型）：`create_note(parentNoteId=plan_folder_id, title="[v1.0] Phase {N}: {阶段名}", type="text", format="markdown", content=阶段计划模板)` | 返回 phase_plan_id |
| 5 | 创建阶段进度笔记 | 在 `progress_folder_id` 下创建 `Phase {N} 实施-进行中`（text类型）：`create_note(parentNoteId=progress_folder_id, title="Phase {N} 实施-进行中", type="text", format="markdown", content=阶段进度模板)` | 返回 phase_progress_id |
| 6 | 构建双向链接 | 使用 `write_note` 的 `mode="edit"` + `changes` 模式更新两篇笔记末尾的链接，利用 `#root/完整路径/noteId` 相对路径互指对方。 | 链接已建立 |
| 7 | 更新项目概述表格 | 使用 `write_note` 的 `mode="edit"` + `changes` 模式在 `项目概述` 笔记的 `## 阶段概览` 索引表格中追加本阶段信息行（详见下方）。 | 表格已新增本行 |
| 8 | 初始化今日时间块 | 在 `session.md` 中写入 `task_started_at` 字段为当前 ISO 8601 时间戳，初始化阶段的计时追踪。 | `task_started_at` 已写入 |
| 9 | 更新会话与配置 | 将 `active_phase_name="[v1.0] Phase {N}: {阶段名}"`、`active_phase_plan_id`、`active_phase_progress_id` 写入 `session.md`；将 `active_phase.phase_name`、`active_phase.plan_note_id`、`active_phase.progress_note_id`（嵌套结构）写入 `config.json`。 | 本地及配置状态更新成功 |

### 阶段计划笔记模板

使用 `format="markdown"` 创建：

```markdown
# [v1.0] Phase {N}: {阶段名}

## 目标

{阶段的核心目标，1-2句话}

## 任务清单

- [ ] 任务 {N}.1: {任务描述}
- [ ] 任务 {N}.2: {任务描述}

## 验收标准

- [ ] {标准 1}
- [ ] {标准 2}

## 变更日志

- **v1.0** ({YYYY-MM-DD}): 初始版本

## 相关资源

- [→ 项目概述](#root{project_root_path}/{project_note_id}/{项目概述ID})
- [→ 进度笔记](#root{project_root_path}/{project_note_id}/{progress_folder_id}/{phase_progress_id})
```

### 阶段进度笔记模板

使用 `format="markdown"` 创建：

```markdown
# Phase {N} 实施: {阶段名}

## 任务描述

{阶段目标和范围描述}

## 项目结构

\`\`\`
{该阶段涉及的关键文件树}
\`\`\`

## 进度

- [ ] 任务 {N}.1: {任务描述}
- [ ] 任务 {N}.2: {任务描述}

## 门禁验证

| 验证项 | 状态 | 说明 |
|--------|------|------|
| 编译通过 (debug) | ⏳ | |
| 编译通过 (release) | ⏳ | |
| ArkTS 语法检查无新增错误 | ⏳ | |
| 无内存泄漏 | ⏳ | |

## 关键技术决策

| 决策 | 原因 | 影响范围 |
|------|------|----------|

## 构建/部署命令

\`\`\`bash
# debug 构建
hvigorw assembleHap --mode module -p product=default -p buildMode=debug

# release 构建
hvigorw assembleHap --mode module -p product=default -p buildMode=release
\`\`\`

## 今日工作记录

### {YYYY-MM-DD}

| 时间段 | 任务 | 摘要 |
|--------|------|------|
| HH:mm-HH:mm | Task {N}.1: {任务名} | {一句话摘要} |


---
[→ 阶段计划](#root{project_root_path}/{project_note_id}/{plan_folder_id}/{phase_plan_id})
[→ 项目概述](#root{project_root_path}/{project_note_id}/{项目概述ID})
```

### 更新项目概述（步骤 7 详解）

在项目概述"阶段概览"表格中插入新阶段行。

**老项目迁移**：执行前先读取项目概述内容。若未找到 `## 阶段概览` 标题（老项目），先使用 `write_note` 的 `mode="edit"` + `changes` 模式在 `## 基本信息` 部分之后插入 `## 阶段概览` 空表格：

```
// 先插入阶段概览区域（仅在老项目需要时）
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{
    old_string: "- **状态**：进行中\n\n## 进度追踪",
    new_string: "- **状态**：进行中\n\n## 阶段概览\n\n| 阶段 | 计划 | 进度 | 状态 |\n|------|------|------|------|\n\n## 进度追踪"
  }]
)
```

**首次添加阶段（表格为空）**：
```
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{
    old_string: "| 阶段 | 计划 | 进度 | 状态 |\n|------|------|------|------|",
    new_string: "| 阶段 | 计划 | 进度 | 状态 |\n|------|------|------|------|\n| Phase {N}: {阶段名} | [→ 计划](#root{project_root_path}/{project_note_id}/{plan_folder_id}/{phase_plan_id}) | [→ 进度](#root{project_root_path}/{project_note_id}/{progress_folder_id}/{phase_progress_id}) | 进行中 |"
  }]
)
```

**追加后续阶段**：
```
// 关键：捕获表格末尾换行 + 空行 + ## 进度追踪，新行插入同一表格内
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{
    old_string: "\n\n## 进度追踪",
    new_string: "\n| Phase {N}: {阶段名} | [→ 计划](#root{project_root_path}/{project_note_id}/{plan_folder_id}/{phase_plan_id}) | [→ 进度](#root{project_root_path}/{project_note_id}/{progress_folder_id}/{phase_progress_id}) | 进行中 |\n\n## 进度追踪"
  }]
)
```

### 错误处理

| 错误场景 | 提示信息 | 建议操作 |
|----------|----------|----------|
| 非项目任务 | "new-phase 仅适用于项目任务，当前为简单任务" | 使用 /workspace start 创建项目任务 |
| 缺少项目笔记 | "项目笔记不存在，请先执行 /workspace start" | 初始化项目 |
| 阶段已存在 | "Phase {N} 已存在，是否创建新版本？" | 确认覆盖或改名 |
| 阶段参数格式无效 | "请使用两个参数: `/workspace new-phase <阶段号> <阶段名称>`，如 `new-phase 0 "核心验证"`" | 补充参数 |

---

## status 命令

显示当前会话状态。

```
/workspace status
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 读取会话文件 | `session.md` | 文件存在 |
| 2 | 读取配置文件 | `config.json` | 文件存在 |
| 3 | 显示状态 | 输出工作目录、笔记位置、任务状态等 | 用户可见 |

---

## config 命令

显示配置信息。

```
/workspace config
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 读取全局配置 | `~/.agents/skills_settings.json` | 文件存在 |
| 2 | 读取本地配置 | `.workspace-session-skill/config.json` | 文件存在（如已同步） |
| 3 | 显示配置来源 | 显示有效配置及来源文件 | 用户可见 |

---

## weekly-summary 命令

生成本周工作总结，按 `assets/weekly-summary-template.txt` 格式输出。

### 命令格式

```
/workspace weekly-summary              # 当前周
/workspace weekly-summary 2026-W20     # 指定 ISO 周
```

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 解析周参数 | 无参数取当前 ISO 周，有参数解析 ISO 周次。计算周一的日期 (`YYYY-MM-DD`) 到周日。 | 日期范围正确 |
| 2 | 搜索本周笔记 | 优先按月度目录缩小范围后搜索，减少 MCP 调用次数。对本周每天在对应月度目录中搜索每日笔记。无 Trilium 时降级到本地文件。 | 笔记列表获取 |
| 3 | 读取笔记内容 | 对每天笔记用 `get_note(noteId={id}, format="markdown")` 提取任务描述和完成状态。 | 内容已提取 |
| 4 | 扫描 OpenSpec changes | Glob 扫描 `openspec/changes/*/proposal.md`，读取标题和状态。按日期范围筛选相关 changes。 | changes 列表获取 |
| 5 | 按模板格式输出 | 每项一行：`{序号}. {任务名}（{状态}）：{一句话描述}`；末尾：`下周计划：` 占位。参考 `assets/weekly-summary-template.txt` 精炼程度。 | 格式正确 |

### 数据源优先级

| 优先级 | 数据源 | 说明 |
|--------|--------|------|
| 1 | Trilium 每日笔记 | 主要来源：任务名、描述、状态 |
| 2 | `openspec/changes/` | 补充：change 标题、提案摘要 |
| 3 | `conversation.log` | 降级时：本地对话记录 |

### 输出模板

```
本周工作（{周一日期} - {周日日期}）
  1. {任务名}（{状态}）：{一句话描述}
  2. ...

遗留 / 下周计划：...
```

### 错误处理

| 场景 | 处理 |
|------|------|
| 本周无笔记 | 输出 "本周无活动记录"，提示检查日期范围 |
| Trilium 不可用 | 降级搜索 `.workspace-session-skill/` 本地文件 |
| 无 OpenSpec 目录 | 仅输出笔记内容，跳过 changes 部分 |

---

## Git 工作区初始化流程

`/workspace start` 步骤 2c 中用户确认 Git 同步后的执行流程：

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| G1 | 检查已有 Git | `git status` 检查当前目录是否为 git 仓库。已是则跳过 init，仅更新 remote 和配置。 | 已有仓库不重复初始化 |
| G2 | git init | `git init` 初始化仓库，`git checkout -b master` 创建 master 分支 | 仓库已初始化 |
| G3 | 询问 remote URL | 获取用户输入的远端地址（如 `git@gitee.com:user/repo.git`）。若用户不知道，可跳过稍后配置。 | URL 已获取或跳过 |
| G4 | git remote add | `git remote add origin <url>` | remote 已配置 |
| G5 | 生成 .gitignore | 创建 deny-by-default 白名单 `.gitignore`（`/*` deny，`!/.workspace-session-skill/`、`!/screens/`、`!/Logs/`、`!/docs/`、`!/openspec/` whitelist） | .gitignore 已创建 |
| G6 | 创建 .gitattributes | `echo "conversation.log merge=union" > .gitattributes` | 文件已创建 |
| G7 | 配置 union 合并 | `git config merge.union.driver "git merge-file --union %A %O %B"` | 驱动已配置 |
| G8 | 写入 config.json | 在 `config.json` 添加 `git` 段：`remote_url`, `remote_name`, `branch`, `auto_pull_on_continue=true`, `auto_push_on_save=false`, `last_sync`, `last_push` | 配置已写入 |
| G9 | 初始提交 | `git add -A && git commit -m "init: workspace session data"` | 初始提交完成 |
| G10 | 推送到远端 | `git push -u origin master`（如有 remote URL） | 推送完成 |
| G11 | 更新项目概述 | 在 Trilium 项目概述笔记的 `## 基本信息` 添加 `- **Git 同步仓库**: <remote_url>` | 信息已记录 |

**已有 Git 仓库的处理**：若工作区本身已是 git 仓库，步骤 G1 检测到后跳过 G2-G5，仅执行 G6-G11（添加 .gitattributes + 配置 union + 写 config.json + 更新项目概述）。

---

## continue 命令 Git 同步增强

在 `/workspace continue` 执行清单中，**步骤 2a（读取本地配置）之后**，插入 Git 同步步骤：

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 2a+ | Git 同步拉取 | 若 `config.json` 中 `git.auto_pull_on_continue` 为 true，执行 `sync_remote.sh pull`（工作区根目录）。若脚本不存在或远程不可用，静默跳过不阻断 continue。 | 数据已同步或跳过 |

**同步结果处理**：
- 脚本返回 0：同步成功，继续后续步骤
- 脚本返回非 0（冲突）：向用户展示冲突信息，**不阻断** continue（会话仍然加载，冲突稍后处理）
- 无脚本/无网络/无 remote：静默跳过，不影响 continue 流程

---

## pull 命令

从远端拉取最新工作区数据。

### 命令格式

```
/workspace pull
```

### 执行流程

1. 执行 `sync_remote.sh pull`（工作区根目录）
2. 脚本自动 `git pull --rebase`
3. 若有冲突：
   - `conversation.log`：`merge=union` 自动合并追加行
   - 其他文件：告知用户冲突文件路径，**不阻断**（会话继续加载，冲突稍后处理）
4. 无脚本/无网络/无 remote：静默跳过

---

## push 命令

推送工作区数据到远端仓库。

### 命令格式

```
/workspace push
```

### 执行流程

1. 执行 `sync_remote.sh push`（工作区根目录）
2. 脚本自动列出本地所有未推送提交
3. 若有多个提交，自动 squash 为一个：`sync: YYYY-MM-DD HH:mm — <摘要>`
4. 单一提交时直接 push，无需 squash

### 自动保存行为

`/workspace save` 和 `/workspace save --auto` **仅做本地 commit**，不自动 push。push 由用户通过本命令或 `sync_remote.sh push` 手动触发。

---

## 自然语言触发

| 自然语言 | 对应命令 |
|----------|----------|
| 开始工作 | `/workspace start` |
| 继续工作 | `/workspace continue` |
| 保存工作 | `/workspace save` |
| 结束工作 | `/workspace end` |
| 新任务 | `/workspace new-task` |
| 新阶段 | `/workspace new-phase` |
| 本周总结 | `/workspace weekly-summary` |
| 周报 | `/workspace weekly-summary` |
| 拉取 | `/workspace pull` |
| 推送 | `/workspace push` |
| 同步 | `/workspace pull`（拉取远端最新数据） |

---

## 相关文档

- 配置管理: `references/configuration.md`
- 工作流程: `references/workflow.md`
- 会话格式: `references/session-format.md`
- 自动保存: `references/autosave.md`
- 后台 Agent: `references/background-agent.md`
