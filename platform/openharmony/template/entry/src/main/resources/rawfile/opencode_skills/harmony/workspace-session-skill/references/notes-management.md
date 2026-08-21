# 笔记管理详解

本文档详细说明笔记层级结构、项目笔记管理和任务笔记。

---

## 四级笔记结构

| 类型 | 用途 | 生命周期 | 笔记类型 | 位置 | 命名格式 |
|------|------|----------|----------|------|----------|
| 项目笔记 | 跨天项目记录 | 项目期间保持 | book | project_notes.root | 项目名称 |
| 月度目录 | 月度容器 | 每月一个 | book | daily_notes.root | YY年M月份 |
| 每日笔记 | 当天事务容器 | 每天一个 | book | 月度目录下 | YYYY年M月D日 星期X |
| 任务笔记 | 具体任务记录 | 每个任务一个 | text | 每日笔记下 | {任务名}-{状态} |

---

## 目录结构示例

### 项目任务时

```
项目笔记目录 (project_notes.root)
├── VTK伪装Godot (book)              # 项目集合
│   ├── 项目概述 (text)              # 子笔记（markdown格式）
│   ├── 开发计划 (book)              # [必需] 存放所有阶段的 Task List / Plan
│   │   ├── Phase 0: 核心验证 (text)
│   │   └── Phase 1: 业务注入 (text)
│   └── 编码进度 (book)              # [必需] 存放所有阶段的 Execution / Progress
│       ├── Phase 0 实施-已完成 (text)
│       └── Phase 1 实施-进行中 (text)

每日笔记目录 (daily_notes.root)
├── 26年4月份 (book)                 # 月度目录（年份2位）
│   ├── 2026年4月1日 星期二 (book)   # 每日笔记（年份4位）
│   │   └── 推流插件编译-完成 (text) # 任务笔记（markdown格式）
│   └── 2026年4月2日 星期四 (book)   # 每日笔记（最新，在最后）
│       ├── 登录功能-进行中 (text)   # 任务笔记（markdown格式）
│       └── 推流测试-部署中 (text)   # 任务笔记（markdown格式）
```

### 简单任务时

```
每日笔记目录 (daily_notes.root)
├── 26年4月份 (book)                 # 月度目录（年份2位）
│   ├── 2026年4月1日 星期二 (book)   # 每日笔记（年份4位）
│   │   └── 临时修复-完成 (text)     # 任务笔记（markdown格式）
│   └── 2026年4月2日 星期四 (book)   # 每日笔记
│       └── 代码审查-进行中 (text)   # 任务笔记（markdown格式）
```

---

## 项目笔记规则

### 创建时机

用户选择"项目任务"时创建。

### 创建流程

1. **创建项目集合笔记**（book 类型）：
```
create_note(
  parentNoteId: project_notes.root,
  title: "{项目名称}",
  type: "book",
  content: ""
)
```

2. **创建项目概述子笔记**（text 类型）：
```
create_note(
  parentNoteId: {项目笔记ID},
  title: "项目概述",
  type: "text",
  format: "markdown",
  content: "# 项目概述\n\n## 基本信息\n- **项目名称**：{项目名称}\n- **开始日期**：{YYYY-MM-DD}\n- **状态**：进行中\n\n## 阶段概览\n\n| 阶段 | 计划 | 进度 | 状态 |\n|------|------|------|------|\n\n## 进度追踪\n\n## 相关笔记引用\n"
)
```

3. **创建开发计划子文件夹**（book 类型）：
```
create_note(
  parentNoteId: {项目笔记ID},
  title: "开发计划",
  type: "book",
  content: ""
)
```

4. **创建编码进度子文件夹**（book 类型）：
```
create_note(
  parentNoteId: {项目笔记ID},
  title: "编码进度",
  type: "book",
  content: ""
)
```

**重要**：步骤 3 和 4 创建的子文件夹 ID 必须存入 session.md（`plan_folder_id`、`progress_folder_id`），供后续 `/workspace new-phase` 使用。

### 项目概述模板

**使用 `format="markdown"` 参数创建，内容如下**：

```markdown
# 项目概述

## 基本信息
- **项目名称**：{项目名称}
- **开始日期**：{YYYY-MM-DD}
- **状态**：进行中 | 已完成 | 已暂停

## 阶段概览

| 阶段 | 计划 | 进度 | 状态 |
|------|------|------|------|
| Phase 0: 核心验证 | [→ 计划](#root{project_root_path}/{project_note_id}/{plan_folder_id}/{phase_plan_id}) | [→ 进度](#root{project_root_path}/{project_note_id}/{progress_folder_id}/{phase_progress_id}) | 进行中 |

## 进度追踪

### {YYYY-MM-DD} ({星期})
- [→ 任务笔记: {项目名}](#root{daily_root_path}/{month_dir_id}/{daily_note_id}/{task_note_id})
- ✅ {已完成项}
- ⏳ {进行中项}

## 相关笔记引用
```

**结构说明**：
- **阶段概览**：所有阶段的索引表格，包含计划和进度的双向链接
- **进度追踪**：记录每日进度，包含任务笔记链接和完成项
- **相关笔记引用**：用户主动添加的其他相关笔记引用

---

## 月度目录规则

### 创建规则

- **类型**：book
- **标题格式**：`YY年M月份`（年份2位，月份阿拉伯数字不补零）
- **位置**：daily_notes.root 下

### 查找或创建

```
// 查找月度目录（注意：年份2位，月份阿拉伯数字，结尾有"份"字）
search_notes(
  ancestorNoteId: daily_notes.root,
  query: "title:{YY}年{M}月份"  // 例如：title:26年4月份
)

// 不存在则创建
create_note(
  parentNoteId: daily_notes.root,
  title: "{YY}年{M}月份",  // 例如：26年4月份
  type: "book",
  content: ""  // book 类型传空内容
)
```

---

## 每日笔记规则

### 创建规则

- **类型**：book
- **标题格式**：`YYYY年M月D日 星期X`
- **位置**：月度目录末尾
- **内容**：空集合，不预设子笔记
- **创建前必须搜索**：先 search 检查是否已存在

### 查找或创建流程

**重要**：不要使用 `get_special_note(kind="day")` API，它返回 Trilium 内置日历笔记。

**星期计算规则**：Claude 直接根据系统日期计算星期几，**不要调用任何 API 获取星期**。

```
// 1. 查找月度目录（年份2位，月份阿拉伯数字，结尾有"份"字）
search_notes(
  ancestorNoteId: daily_notes.root,
  query: "title:{YY}年{M}月份"  // 例如：title:26年4月份
)

// 2. 无则创建月度目录
create_note(
  parentNoteId: daily_notes.root,
  title: "{YY}年{M}月份",  // 例如：26年4月份
  type: "book",
  content: ""  // book 类型传空内容
)

// 3. 查找每日笔记（年份4位，月/日阿拉伯数字）
search_notes(
  ancestorNoteId: {月度目录ID},
  query: "title:{YYYY}年{M}月{D}日"  // 例如：title:2026年4月2日
)

// 4. 无则创建每日笔记
create_note(
  parentNoteId: {月度目录ID},
  title: "{YYYY}年{M}月{D}日 星期{X}",  // 例如：2026年4月2日 星期四
  type: "book",
  content: ""  // book 类型传空内容
)
```

### 更新配置

创建或获取每日笔记后，更新 config.json：

```json
{
  "daily_notes": {
    "current_note_id": "trilium:{每日笔记ID}",
    "current_note_date": "{YYYY-MM-DD}"
  }
}
```

---

## 任务笔记规则

### 命名格式

`{任务名}-{当前状态或步骤}`

示例：
- `登录功能-进行中`
- `登录功能-完成`
- `推流插件测试-部署测试准备中`

### 创建规则

- **类型**：text
- **位置**：每日笔记下
- **命名**：`{任务名}-{状态}`

### 创建流程

**使用 `format="markdown"` 参数创建，内容如下**：

```
// 从 config.json 获取当前每日笔记 ID
const dailyNoteId = config.daily_notes.current_note_id

// 创建任务笔记（markdown 格式）
create_note(
  parentNoteId: dailyNoteId,
  title: "{任务名}-进行中",
  type: "text",
  format: "markdown",
  content: "# {任务名}\n\n## 任务描述\n\n## 进度\n- [ ] 待办项\n\n## 今日工作记录\n",
)
```

### 任务笔记模板

**项目任务时**：

```markdown
# {任务名}

## 任务描述

## 进度
- [ ] 待办项

## 今日工作记录


---
[→ 项目笔记](#root{project_root_path}/{project_note_id})
```

**简单任务时**：

```markdown
# {任务名}

## 任务描述

## 进度
- [ ] 待办项

## 今日工作记录

```

### 双向引用（有项目笔记时）

#### 任务笔记 → 项目笔记

在任务笔记末尾添加跳转链接（使用完整路径格式）：

```markdown
---
[→ 项目笔记](#root{project_root_path}/{project_note_id})
```

**注意**：`project_root_path` 来自配置 `project_notes.root_path`，格式如 `#root/V83RZAMdWE4t/j7IuML86uLAF/wz1kyVAE8HVO`

#### 项目笔记 → 任务笔记

在项目概述的"进度追踪"部分添加（使用完整路径格式）：

```markdown
### {YYYY-MM-DD} ({星期})
- [→ 任务笔记: {项目名}](#root{daily_root_path}/{月度目录ID}/{每日笔记ID}/{任务笔记ID})
```

**重要**：Trilium 内部链接必须使用 `#root/完整路径/目标笔记ID` 格式，`trilium:{noteId}` 格式仅用于外部 Markdown 文件。

**路径构建**：
- `daily_root_path` = `daily_notes.root_path`（从配置获取）
- 月度目录ID、每日笔记ID、任务笔记ID = 创建时获取并存储

---

## 阶段笔记规则

项目任务采用阶段化管理。每个阶段包含一对笔记：
- **阶段计划笔记**（在"开发计划"下）：Task List / Plan，定义该阶段要完成的事项
- **阶段进度笔记**（在"编码进度"下）：Execution / Progress，记录实际执行过程

### 创建时机

通过 `/workspace new-phase` 命令创建。首次创建时若项目的"开发计划"或"编码进度"子文件夹不存在，自动创建。

### 阶段计划笔记模板

**命名格式**：`[v{X.X}] Phase {N}: {阶段名}`（如 `[v1.0] Phase 0: 核心验证`），初始版本为 `v1.0`

**内容模板**（使用 `format="markdown"`）：

```markdown
# [v1.0] Phase {N}: {阶段名}

## 目标

{阶段的核心目标，1-2句话}

## 任务清单

- [ ] 任务 {N}.1: {任务描述}
- [ ] 任务 {N}.2: {任务描述}
- [ ] 任务 {N}.3: {任务描述}

## 验收标准

- [ ] {标准 1}
- [ ] {标准 2}

## 变更日志

- **v1.0** ({YYYY-MM-DD}): 初始版本

## 相关资源

- [→ 项目概述](#root{project_root_path}/{project_note_id}/项目概述ID)
- [→ 进度笔记](#root{project_root_path}/{project_note_id}/{progress_folder_id}/{phase_progress_id})
```

### 阶段进度笔记模板

**命名格式**：`Phase {N} 实施-{状态}`（如 `Phase 0 实施-已完成`）

**内容模板**（使用 `format="markdown"`）：

```markdown
# Phase {N} 实施: {阶段名}

## 任务描述

{阶段目标和范围描述}

## 项目结构

```
{该阶段涉及的关键文件树}
```

## 进度

- [x] 任务 {N}.1: {任务描述}
- [x] 任务 {N}.2: {任务描述}
- [ ] 任务 {N}.3: {任务描述}

## 门禁验证

| 验证项 | 状态 | 说明 |
|--------|------|------|
| {验证项 1} | ✅ / ❌ / ⏳ | {说明} |
| {验证项 2} | ✅ / ❌ / ⏳ | {说明} |

## 关键技术决策

| 决策 | 原因 | 影响范围 |
|------|------|----------|
| {决策描述} | {选择原因} | {影响范围} |

## 构建/部署命令

\`\`\`bash
{构建或部署的关键命令}
\`\`\`

## 今日工作记录

### {YYYY-MM-DD}

| 时间段 | 任务 | 摘要 |
|--------|------|------|
| HH:mm-HH:mm | Task {N}.1: {任务名} | {一句话摘要} |
| HH:mm-HH:mm | Task {N}.2: {任务名} | {一句话摘要} |


---
[→ 阶段计划](#root{project_root_path}/{project_note_id}/{plan_folder_id}/{phase_plan_id})
[→ 项目概述](#root{project_root_path}/{project_note_id}/项目概述ID)
```

### 双向语义链接

阶段计划笔记和进度笔记之间通过末尾链接建立双向引用：

- 阶段计划笔记末尾 → 指向进度笔记
- 阶段进度笔记末尾 → 指向阶段计划 + 项目概述

此外，创建阶段时在项目概述的"阶段概览"表格中插入一行索引记录。

### 关系属性（未来增强）

> [!NOTE]
> 尽管 Trilium 允许定义丰富的关系属性（如 `relation:implementsPlan` 指向计划，`relation:trackedProgress` 指向进度），这有利于后续开发自定义脚本或渲染仪表盘。
> 但在当前阶段，**此特性标记为“未来增强”**。当前系统开发中，应当**优先确保文档模版结构的完整**，并依靠标准 Markdown 与 HTML 相对链接（如 `#root/...`）来完成强韧的导航链接建立。

### 工作记录同步规则

`/workspace save` 时自动同步阶段进度笔记的以下区域：

| 区域 | 同步方式 | 规则 |
|------|---------|------|
| 任务描述 | 全量替换 | 从对应阶段计划笔记的 `## 目标` 拉取最新内容 |
| 项目结构 | 增量追加 | `git diff --name-only` 扫描变更文件，追加到文件树 |
| 进度 (checkbox) | 全量同步 | 与 session.md TASKS 对齐 |
| 门禁验证 | 增量更新 | CONTEXT 中有新验证结果时更新表格 |
| 关键技术决策 | 增量追加 | CONTEXT 中有新决策时追加行 |
| 今日工作记录 | 增量追加 | HH:mm-HH:mm 格式，每行一个时间块 |

三层内容分工：

| 位置 | 抽象层级 | 规则 |
|------|---------|------|
| 项目概述 > 进度追踪 | 工作块摘要（合并同类项） | 如"代码审查修复(9项)" |
| 阶段进度 > 任务描述 | 与计划同步 | 每次 save 从计划笔记"目标"全量拉取 |
| 阶段进度 > 项目结构 | 自动扫描 | 每次 save 执行 `git diff --name-only` 扫描变更文件 |
| 阶段进度 > 今日工作记录 | 小时级详细展开 | HH:mm-HH:mm 格式，每项一行 |
| 任务笔记 > 进度 | Checkbox 状态 + 详细记录 | 保留全部 checkboxes |

同步时使用 `write_note` 的 `mode="edit"` + `changes` 模式，禁止使用 `write_note(mode="append")`（避免追加到末尾链接之后）。

---

## 计划基线与版本修订规范

### 核心理念

项目任务执行过程中，**禁止 `/workspace save` 自动覆盖或篡改 `开发计划` 文件夹下的计划表**。必须维持两者的清晰物理隔离：

| 维度 | 开发计划笔记（计划表） | 编码进度笔记（进度表） |
|------|----------------------|----------------------|
| 物理定位 | `开发计划/` 子目录下 | `编码进度/` 子目录下 |
| 管理角色 | 静态基线（Static Baseline） | 动态轨迹（Dynamic Progress） |
| 生命周期 | 阶段启动时确定，非大变更不修改 | 每日随 `/workspace save` 高频增量更新 |
| 核心职责 | 记录承诺要做的事情与初始验收标准 | 记录实际已做的小时日志、决策与门禁状态 |
| 版本管理 | 包含显式版本号，如 `[v1.0]`、`[v2.0]` | 无需版本号，后缀对应实施状态（进行中/已完成） |

### 何时允许修改计划表

仅在发生以下项目级重大变更时，才允许对 `开发计划` 下的计划笔记发起版本修订流程：

1. **需求范围变更（Scope Change）**：需新增阶段性任务（如增加 Task 1.4）或废弃原定任务
2. **架构重构（Architecture Refactoring）**：底层依赖或技术路线发生重大漂移，导致阶段性目标和门禁验证项必须调整
3. **排期与里程碑调整**：阶段整体用时与关键节点发生重大改变

### 计划修订三步流

当需要调整计划时，Agent 必须遵循以下标准化流程，禁止随意修改：

#### 第一步：修订计划表并记录变更日志

- 编辑 `开发计划` 下的对应计划笔记，修改 `## 任务清单` 和 `## 验收标准`
- 在计划笔记末尾增设 `## 变更日志` 区域，清晰记录本次修订的原因与内容

**Changelog 示例**：
```
## 变更日志

- **v2.0** (2026-05-25): 新增 Task 1.4: FFI 内存对齐深度校验，因 Phase 0 验证发现双端 ABI 传递 C 结构体时存在 4 字节截断隐患
- **v1.0** (2026-05-20): 初始版本，包含 Task 1.1-1.3
```

#### 第二步：升级计划表标题版本号

- 将该计划笔记的 Trilium 标题进行版本升级
- 标题格式规范：`[v{X.X}] Phase {N}: {阶段名}`
- 示例：`[v1.0] Phase 1: 业务注入` → `[v2.0] Phase 1: 业务注入`
- 使用 `write_note(mode="metadata", title=...)` 更新 Trilium 笔记标题

#### 第三步：同步更新进度表 Task Checkbox

- 打开 `编码进度` 下对应的 `Phase {N} 实施-{状态}` 进度笔记
- 将 `## 进度` 部分的 Checkbox 列表与计划表的新清单全量同步（加入未勾选的新任务，如 `- [ ] 任务 1.4: ...`）
- 目的：确保后续 `/workspace save` 在提取 session.md 任务状态时，能将日志正确归纳到新增任务段中

### new-phase 创建时的版本初始化

`/workspace new-phase` 创建阶段计划笔记时，标题自动初始化为 `[v1.0] Phase {N}: {阶段名}`，无需手动设定。

### 对应命令

| 操作 | 命令/方式 |
|------|----------|
| 创建新阶段（自动设 v1.0） | `/workspace new-phase` |
| 修订计划表 | Agent 手动编辑计划笔记内容 |
| 升级版本号 | Agent 使用 `write_note(mode="metadata", title=...)` 修改标题 |
| 同步进度表 | Agent 使用 `write_note` 同步 checkbox |

---

## Trilium 链接格式

### 内部链接（Trilium 内使用）

```html
<a href="#root/完整路径/目标笔记ID">[链接显示文本]</a>
```

**关键规则**：
- 链接文本用方括号 `[]` 包裹
- 路径从 `#root/` 开始，包含完整层级到目标笔记 ID

### 外部链接（本地 Markdown 使用）

```markdown
[{日期} {任务标题}](trilium:{noteId})
```

点击后在 Trilium 应用中打开对应笔记。

---

## 降级处理

当 Trilium MCP 不可用或配置为空时：

- 使用本地 Markdown 文件
- 路径：`{工作目录}/.workspace-session-skill/notes/`
- 文件名：`{YYYY-MM-DD}.md`
