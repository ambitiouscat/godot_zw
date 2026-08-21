# 项目概述笔记

本文档说明项目概述笔记的结构与同步机制。笔记管理基础参见 `notes-management.md`。

---

## 存储架构（双层）

项目概述跨两层存储，各有分工：

| 存储层 | 位置 | 用途 |
|--------|------|------|
| Trilium 笔记 | 项目笔记 → `项目概述`（text 类型） | 主存储：阶段概览、进度追踪、笔记引用 |
| 本地配置文件 | `.workspace-session-skill/config.json` | 加速读取：`project_notes.*` 结构，含所有关键 ID |

**当前设计**：项目概述全部存储在 Trilium，本地 `config.json` 仅存 ID 引用。不再使用独立的本地 `PROJECT_OVERVIEW.md` 文件。

---

## Trilium 项目概述结构

```
项目笔记 (book)
  ├── 项目概述 (text, markdown)
  │   ├── ## 基本信息
  │   ├── ## 阶段概览 (表格)
  │   ├── ## 进度追踪 (按日期)
  │   └── ## 相关笔记引用
  ├── 开发计划 (book)
  │   └── [v1.0] Phase N: 阶段名 (text)
  └── 编码进度 (book)
      └── Phase N 实施-进行中 (text)
```

## 项目概述模板

```markdown
# 项目概述

## 基本信息
- **项目名称**：{项目名称}
- **开始日期**：{YYYY-MM-DD}
- **状态**：进行中 | 已完成 | 已暂停
- **Git 同步仓库**: {remote_url}

## 阶段概览

| 阶段 | 计划 | 进度 | 状态 |
|------|------|------|------|
| Phase N: {阶段名} | [→ 计划](#root/.../plan_id) | [→ 进度](#root/.../progress_id) | 进行中 |

## 进度追踪

### {YYYY-MM-DD} ({星期})
- [→ 任务笔记: {项目名}](#root/.../task_note_id)
- ✅ {已完成项}
- ⏳ {进行中项}

## 相关笔记引用
```

## 同步时机

| 触发时机 | 同步操作 |
|----------|----------|
| `/workspace start`（项目任务） | 创建项目笔记 + 项目概述（初始模板） |
| `/workspace save`（项目任务） | 更新进度追踪（新增日期条目或更新已有条目） |
| `/workspace new-phase` | 追加阶段概览表格行 |
| `/workspace end` | 状态标记为已完成/已暂停 |

## 同步方法

**禁止使用 `write_note(mode="append")`** — 会追加到"相关笔记引用"之后，位置错误。

必须使用 `write_note` 的 `mode="edit"` + `changes` 模式：

- **新增日期条目**：锚点 `"## 进度追踪\n\n## 相关笔记引用"`，在两者间插入
- **更新已有条目**：匹配当天条目的 `old_string`，替换为更新内容
- **追加阶段行**：匹配表格末尾 `\n\n## 进度追踪`，在前插入新行

详见 `commands/workspace.md` → save → 同步项目概述。

## 链接格式

内部跳转链接使用 Trilium 格式：
```markdown
[→ 任务笔记: {项目名}](#root/{root_path}/{month_dir_id}/{daily_note_id}/{task_note_id})
```

**注意**：`trilium:{noteId}` 格式仅用于外部 `.md` 文件，Trilium 内部笔记中无法跳转。

---

## 本地 config.json 中的项目键

```json
{
  "project_notes": {
    "root": "trilium:DeAmum2SLplk",
    "root_path": "#root/gpGBkVSJbp5o/.../DeAmum2SLplk",
    "description": "完整问题处理记录-项目",
    "plan_folder_id": "KlxQuwxSDldc",
    "progress_folder_id": "p21tOLOWdF2H",
    "overview_note_id": "KK97wCnXJYrR"
  }
}
```

这些值由 `/workspace start` 写入，供 `continue`/`save`/`new-phase` 读取使用。
