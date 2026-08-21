# Trilium 集成

本文档说明与 Trilium 笔记系统的集成方式。配置管理参见 `configuration.md`。

---

## 核心操作

> **v2 接口**：triliumnext-mcp v1.0.0 已合并 35→19 工具。下表为当前 v2 工具名。

| 操作 | 工具 | 用途 |
|------|------|------|
| 创建笔记 | `mcp__trilium__create_note` | 创建每日/任务/项目笔记 |
| 写入笔记 | `mcp__trilium__write_note` | 万能写入（按 mode 切换行为） |
| 读取笔记 | `mcp__trilium__get_note` | 默认返回 content，`include_content=false` 仅元数据 |
| 搜索笔记 | `mcp__trilium__search_notes` | 查找笔记 |
| 组织笔记 | `mcp__trilium__organize_note` | 移动/克隆/重排/取消链接 |
| 删除笔记 | `mcp__trilium__delete_note` | `action="delete"` **必填**（v2 不再默认删除） |
| 属性管理 | `mcp__trilium__set_attribute` / `get_attributes` / `delete_attribute` | 标签和关系 |
| 日历笔记 | `mcp__trilium__get_special_note` | `kind="day"` / `kind="inbox"` |
| 修订管理 | `mcp__trilium__create_revision` / `get_revisions` | 快照和历史 |
| 附件 | `mcp__trilium__create_attachment` / `get_attachment` | 文件和图片 |
| 系统操作 | `mcp__trilium__manage_system` | `action="backup"` / `action="export"` |

### `write_note` mode 参数（v2 核心变化）

| mode | v1 等价 | 用途 |
|------|---------|------|
| `"edit"` | `update_note_content(changes=...)` | **搜索替换/增量编辑**（最常用） |
| `"replace"` | `update_note_content(content=...)` | 全量替换内容 |
| `"metadata"` | `update_note(title=...)` | 改标题/类型/MIME |
| `"append"` | `append_note_content(content=...)` | 追加到末尾 |
| *（diff）* | `update_note_content(patch=...)` | `"edit"` 模式下也可传 `patch`（unified diff） |

**⚠️ `write_note(mode="append")` 限制**（同 v1 的 `append_note_content`）：
- **禁止**用于项目概述笔记（末尾是"相关笔记引用"，追加会错位）
- **禁止**用于任务笔记（末尾有 `[→ 项目笔记]` 跳转链接）
- **禁止**用于阶段进度笔记（末尾有 `[→ 阶段计划]` 和 `[→ 项目概述]` 链接）
- 推荐使用 `write_note(mode="edit", changes=...)` 在正确位置精确插入内容

---

## 每日笔记查找

### 重要警告

> ⚠️ **不要使用 `get_special_note(kind="day")` API（v1 为 `get_day_note()`）**
>
> 它返回 Trilium 内置日历系统笔记，不在配置目录下。

### 正确流程

```
1. 月度目录:
   search_notes(ancestorNoteId=daily_notes.root, query="title:{YY}年{X}月份")

2. 每日笔记:
   search_notes(ancestorNoteId=月度目录ID, query="title:{YYYY}年{M}月{D}日")
```

---

## 链接格式

### 内部链接（Trilium 内使用）

**Markdown 格式**（推荐）：
```markdown
[链接显示文本](#root/完整路径/目标笔记ID)
```

**HTML 格式**：
```html
<a href="#root/完整路径/目标笔记ID">[链接显示文本]</a>
```

**关键规则**：
- 路径从 `#root/` 开始，包含完整层级到目标笔记 ID
- 在 Trilium 内创建的笔记链接必须使用此格式

**示例**：
```markdown
[→ 任务笔记: 测试项目](#root/gpGBkVSJbp5o/WswpdHC8Slyd/FuT5x6wnIWXH/lqeH1j03yujZ/UhQgGAM739Km/StQhUSsLQY94)
```

### 外部链接（本地 Markdown 使用）

```markdown
[{日期} {任务标题}](trilium:{noteId})
```

**注意**：`trilium:{noteId}` 格式仅在本地 Markdown 文件中有效，点击后在 Trilium 应用中打开对应笔记。**在 Trilium 内部笔记中此格式无法跳转**。

---

## 项目概述集成

本地项目概述笔记与 Trilium 笔记系统协同工作：

| 存储位置 | 文件/笔记 | 特点 |
|----------|----------|------|
| 项目目录 | PROJECT_OVERVIEW.md | 快速查看、版本控制、离线访问 |
| Trilium | 项目笔记 (book) | 双向引用、层级管理、搜索 |

**协同关系**：
```
本地 PROJECT_OVERVIEW.md              Trilium 项目笔记
─────────────────────────────────────────────────────────
基本信息 → Trilium 链接         →     项目笔记集合 (book)
相关笔记引用                    →     任务笔记 (internalLink)
进度追踪内容                    →     任务笔记内容
```

### ⚠️ 项目概述写入铁律

由于项目概述笔记末尾的 `## 相关笔记引用` 是全文最稳定的锚点，所有写入**必须**遵循以下模式：

**唯一正确模式**：`mode="edit"` + `changes`，`old_string` = `"## 相关笔记引用"`

```
write_note(
  mode: "edit",
  noteId: {overview_note_id},
  changes: [{
    old_string: "## 相关笔记引用",
    new_string: "<新日期条目>\n\n## 相关笔记引用"
  }]
)
```

**三条禁令**：

| 禁止 | 原因 |
|------|------|
| `mode="append"` | 追加到全文末尾 = 插在 `## 相关笔记引用` 之后，破坏笔记结构 |
| `mode="replace"` | 不先读全再写 = 覆盖其他 agent 并发写入的内容 |
| 无锚点 `mode="edit"` | 每次读全文找边界 = 误匹配风险，尤其是大笔记 |

**为什么 `## 相关笔记引用` 是唯一安全锚点**：
- 它是全文最稳定的标题，永不会被删除或重命名
- 新条目永远插在它之前，不会越界
- 不需要读全文（`old_string` 长度只需 20 字符）
- 并发安全：两个 agent 同时 edit 不同位置 → Trilium diff 能正确处理

详见 `notes-management.md` → 项目概述笔记

---

## 降级处理

当 Trilium MCP 不可用或配置为空时：
- 使用本地 Markdown 文件
- 路径：`{工作目录}/.workspace-session-skill/notes/`
- 文件名：`{YYYY-MM-DD}-{主题}.md`

---