---
name: workspace
description: >-
  工作区会话管理技能。用于持久化工作状态、记录关键对话、追踪任务进度。
  激活关键词: 开始工作, 继续工作, 保存工作, 结束工作, 新任务, workspace, session, 拉取, 推送, 同步, pull, push
license: MIT
metadata:
  author: User
  version: 4.7.0
  created: 2026-03-19
  last_reviewed: 2026-06-02
  review_interval_days: 90
  references:
    - file: references/README.md
      description: 文档导航
    - file: references/workflow.md
      description: 工作流详解
    - file: references/configuration.md
      description: 配置管理
    - file: references/notes-management.md
      description: 笔记管理
    - file: references/session-format.md
      description: 会话格式
    - file: references/trilium-integration.md
      description: Trilium集成
    - file: references/autosave.md
      description: 自动保存
    - file: references/background-agent.md
      description: 后台子Agent协议
    - file: references/flowcharts.md
      description: 工作流流程图
    - file: references/daily-summary-template.md
      description: 每日总结模板
    - file: references/project-overview.md
      description: 本地项目概述笔记
---

# /workspace — 工作区会话管理

帮助用户持久化工作状态、记录关键信息、追踪任务进度，确保跨会话无缝接续工作。

---

## 命令

| 命令 | 说明 |
|------|------|
| `/workspace start` | 开始会话（询问项目/简单任务并初始化双层架构） |
| `/workspace continue` | 继续会话 |
| `/workspace save [--auto]` | 保存进度（自动编译时间块日志并同步） |
| `/workspace end` | 结束会话 |
| `/workspace new-task [名称]` | 创建任务笔记 |
| `/workspace new-phase [阶段号] [名称]` | [新增] 创建新阶段的计划与进度笔记，支持自动迁移 |
| `/workspace weekly-summary [周次]` | 生成本周工作总结 |
| `/workspace pull` | Git 拉取远端最新工作区数据 |
| `/workspace push` | Git 推送本地（自动 squash 多提交为一个） |
| `/workspace status` | 显示状态 |
| `/workspace config` | 显示配置 |

**自然语言**：开始工作、继续工作、保存工作、结束工作、新任务、新阶段、本周总结、周报、拉取、推送、同步（=拉取远端）

---

## 核心规则

### ⚠️ 强制执行规则

**每条命令执行前必须阅读 `commands/workspace.md` 并严格按清单执行！**

违反以下规则视为执行失败：
1. **必须询问任务类型**：start 命令必须询问"项目任务"或"简单任务"
2. **必须使用统一目录**：所有文件存放在 `.workspace-session-skill/`，**不是** `.claude/`
3. **必须使用 Markdown 格式**：session.md 使用纯 Markdown 格式，**不是** YAML frontmatter
4. **必须创建初始任务笔记**：创建每日笔记后立即创建任务笔记
5. **必须使用正确链接格式**：Trilium 内链接用 `#root/path/noteId`，**不是** `trilium:noteId`
6. **必须正确计算星期**：Claude 直接根据系统日期计算星期几，**不要调用 API 获取**。
7. **严禁 get_special_note()**：**永远禁止**调用 `get_special_note(kind="day")`（v1: `get_day_note()`）。Trilium 内置日历笔记与 workspace 笔记体系完全隔离，使用它会导致每日笔记创建到错误位置。必须通过 `search_notes(ancestorNoteId=month_dir_id, ...)` + `create_note(parentNoteId=month_dir_id, ...)` 手动管理。
8. **不设置 notePosition**：Trilium 默认将新笔记追加到容器末尾，无需手动设置
9. **禁止响应废弃命令**：`/workspace project start` 已废弃，应提示用户使用 `/workspace start`
10. **create_note 必须有 content**：所有 create_note 调用必须包含 content 参数（book 类型传空字符串）
11. **对话缓存保护**：发现对话记录/缓存数据时，**禁止删除或覆盖**。默认在后面追加新内容。
12. **跨天不创建新笔记**：`save --auto` 跨天时只生成昨日总结追加到昨日任务笔记末尾，**不创建**今天的每日笔记或任务笔记。创建新笔记由用户 `/workspace continue` 时决定任务方向。生成总结后立即关闭定时任务。
13. **项目任务强制阶段化**：项目任务必须在项目笔记下创建 `开发计划` 和 `编码进度` 两个子文件夹（book 类型）。所有阶段工作通过 `/workspace new-phase` 创建配对的计划笔记和进度笔记。
14. **continue 必须读取本地 config.json**：`/workspace continue` 跨天处理时，`daily_notes.root` 和 `project_notes.root` **必须**从本地 `.workspace-session-skill/config.json` 读取，**禁止**使用全局 `~/.agents/skills_settings.json` 中的值。

### 执行清单（必须完成）

**重要**：所有命令执行必须完成 `commands/workspace.md` 中定义的执行清单的每一步骤。

未完成清单的执行视为失败，需要重新执行。

清单要点：
- 每个步骤都有明确的操作和验证标准
- 必须按顺序执行
- 完成后在内部标记 ✓

### 配置

- **模板文件**：`settings.json`（仅作参考，运行时不读取）
- **运行时配置**：`~/.agents/skills_settings.json`（唯一有效来源）
- **项目本地**：`.workspace-session-skill/config.json`（从全局同步）

详见 `references/configuration.md`

### 任务类型

| 类型 | 说明 | Trilium笔记 |
|------|------|-------------|
| 项目任务 | 跨多天，需项目管理 | 项目笔记 + 每日笔记 |
| 简单任务 | 单日完成，临时性 | 仅每日笔记 |

### 统一存储目录

所有文件存放在：

```
{工作目录}/.workspace-session-skill/
├── config.json          # 项目本地配置
├── session.md           # 当前会话状态
├── conversation.log     # 对话日志
├── notes/               # 本地笔记（降级时）
└── archive/             # 归档目录
```

详见 `references/session-format.md`

### 笔记体系

| 类型 | 用途 | 位置 | 命名 |
|------|------|------|------|
| 项目笔记 | 跨天项目 | project_notes.root | 项目名称 |
| 开发计划 | 阶段计划清单 | 项目笔记下 | 开发计划 |
| 编码进度 | 阶段执行记录 | 项目笔记下 | 编码进度 |
| 阶段计划笔记 | 单阶段 Task List | 开发计划下 | Phase N: 阶段名 |
| 阶段进度笔记 | 单阶段执行详情 | 编码进度下 | Phase N 实施-{状态} |
| 月度目录 | 月度容器 | daily_notes.root | YY年M月份 |
| 每日笔记 | 当天容器 | 月度目录下 | YYYY年M月D日 星期X |
| 任务笔记 | 具体任务 | 每日笔记下 | {任务名}-{状态} |

详见 `references/notes-management.md`

### 每日笔记规则

- book 类型，位置：当月目录末尾
- **禁止** `get_special_note(kind="day")`（v1: `get_day_note()`），使用 `search_notes()` 查找
- **创建前必须搜索**：创建每日笔记前先搜索是否已存在

### Trilium 链接

**内部链接**（Trilium 内使用，推荐 Markdown 格式）：
```markdown
[链接文本](#root/完整路径/目标笔记ID)
```

**外部链接**（本地 Markdown 文件使用）：
```markdown
[链接文本](trilium:{noteId})
```

**注意**：`trilium:{noteId}` 格式仅用于本地文件，在 Trilium 内部笔记中无法跳转。

详见 `references/trilium-integration.md`

---

## 自动保存

- Cron 任务，间隔 60 分钟
- **仅在有新对话时更新**
- 命令：`/workspace save --auto`
- **跨天总结生成后自动关闭定时任务**，次日 `/workspace continue` 时重建

详见 `references/autosave.md`

---

## 错误处理

| 场景 | 处理 |
|------|------|
| Trilium 不可用 | 降级本地 Markdown |
| 会话文件损坏 | 提示重建 |
| 笔记目录不存在 | 询问创建 |
| 配置缺失 | 提示创建 ~/.agents/skills_settings.json |

---

## 快速参考

```
/workspace start        # 开始（选择项目/简单任务）
/workspace save         # 保存
/workspace continue     # 继续
/workspace end          # 结束
/workspace new-task     # 新任务
/workspace new-phase    # 新阶段
/workspace weekly-summary  # 本周总结
/workspace pull         # 拉取远端
/workspace push         # 推送本地
/workspace status       # 查看状态
/workspace config       # 查看配置
```

**关键文件**：
- 统一目录：`.workspace-session-skill/`
- 会话状态：`.workspace-session-skill/session.md`
- 本地配置：`.workspace-session-skill/config.json`
- 全局配置：`~/.agents/skills_settings.json`

**详细文档**：`references/README.md`
