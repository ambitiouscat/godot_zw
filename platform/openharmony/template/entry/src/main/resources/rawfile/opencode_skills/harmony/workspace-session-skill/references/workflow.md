# 工作流详解

本文档详细说明各工作流的执行步骤。核心规则参见 skill.md。

**重要**：执行清单是强制性的，必须完成每个步骤。

---

## 开始工作 (/workspace start)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 获取当前日期 | Claude 直接计算当前日期和星期，格式：`YYYY年M月D日 星期X` | 日期格式正确 |
| 2 | 创建工作目录 | 创建 `.workspace-session-skill/` 目录 | 目录存在 |
| 3 | 读取配置文件 | 从 `~/.agents/skills_settings.json` 读取 `workspaceSession` | 配置加载成功 |
| 4 | 同步配置到本地 | 写入 `.workspace-session-skill/config.json` | 文件存在 |
| 5 | 询问任务类型 | 项目任务 or 简单任务 | 用户选择 |
| 6 | 检查会话文件 | `.workspace-session-skill/session.md` | 存在则加载 |
| 7 | 执行任务类型分支 | 见下方详细流程 | 按类型执行 |
| 8 | 设置自动保存 | CronCreate 创建 60 分钟间隔任务 | 返回 job_id |
| 9 | 输出会话状态 | 显示工作目录、笔记位置、任务信息 | 用户确认 |

### 任务类型分支

#### 项目任务流程

```
用户选择"项目任务"
    ↓
检查 project_notes.root 配置
    ↓ 未配置 → 提示用户选择：配置后继续 或 改为简单任务
    ↓ 已配置
询问项目名称
    ↓
在 project_notes.root 下创建项目笔记（book类型）
    ↓
创建项目概述子笔记（text类型，markdown格式）
    ↓
检查/创建当月目录（book类型）在 daily_notes.root 下
    ↓
创建每日笔记（book类型）在当月目录下
    ↓
创建初始任务笔记（text类型，markdown格式）在每日笔记下
    ↓
更新项目概述：添加任务笔记引用
    ↓
更新配置：current_note_id, current_note_date
    ↓
更新会话文件：task_type=project, project_note_id, project_name
    ↓
完成
```

#### 简单任务流程

```
用户选择"简单任务"
    ↓
检查/创建当月目录（book类型）在 daily_notes.root 下
    ↓
创建每日笔记（book类型）在当月目录下
    ↓
询问任务名称/描述
    ↓
创建初始任务笔记（text类型，markdown格式）在每日笔记下
    ↓
更新配置：current_note_id, current_note_date
    ↓
更新会话文件：task_type=simple
    ↓
完成
```

### 详细操作说明

#### 1. 获取当前日期

Claude 直接计算当前日期和星期，无需执行命令。

示例：`2026年4月2日 星期四`

#### 3-4. 读取和同步配置

```javascript
// 读取全局配置
const globalConfig = ~/.agents/skills_settings.json
const config = globalConfig.workspaceSession

// 同步到项目本地
写入 {工作目录}/.workspace-session-skill/config.json
```

#### 5. 询问任务类型

```
请问这是什么类型的任务？
1. 项目任务 - 需要创建项目笔记，跨多天完成
2. 简单任务 - 仅记录到每日笔记
```

#### 7. 项目任务 - 创建项目笔记

**前置检查**：

1. 检查 `project_notes.root` 配置：
```
if (!config.project_notes.root) {
  提示用户：
  "project_notes.root 未配置，无法创建项目任务。
   请选择：
   1. 配置后继续 - 我来帮你配置
   2. 改为简单任务 - 仅使用每日笔记"
}
```

**Trilium 操作**：

1. 创建项目集合笔记：
```
create_note(
  parentNoteId: project_notes.root,
  title: "{项目名称}",
  type: "book"
)
```

2. 创建项目概述子笔记（使用 markdown 格式）：
```
create_note(
  parentNoteId: {项目笔记ID},
  title: "项目概述",
  type: "text",
  format: "markdown",
  content: "# 项目概述\n\n## 基本信息\n- **项目名称**：{项目名称}\n- **开始日期**：{YYYY-MM-DD}\n- **状态**：进行中\n\n## 进度追踪\n\n## 相关笔记引用\n"
)
```

3. 创建初始任务笔记（使用 markdown 格式）：
```
create_note(
  parentNoteId: {每日笔记ID},
  title: "{项目名}-进行中",
  type: "text",
  format: "markdown",
  content: "# {项目名}\n\n## 任务描述\n初始任务，项目启动。\n\n## 进度\n- [ ] 项目初始化\n\n---\n[→ 项目笔记](#root{project_root_path}/{project_note_id})"
)
```

4. 更新项目概述引用：
```
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{
    old_string: "## 进度追踪\n\n## 相关笔记引用",
    new_string: "## 进度追踪\n\n### {YYYY-MM-DD} ({星期})\n- [→ 任务笔记: {项目名}](#root{daily_root_path}/{month_dir_id}/{daily_note_id}/{任务笔记ID})\n\n## 相关笔记引用"
  }]
)
```

#### 7. 简单任务 - 创建任务笔记

1. 创建任务笔记（使用 markdown 格式）：
```
create_note(
  parentNoteId: {每日笔记ID},
  title: "{任务名}-进行中",
  type: "text",
  format: "markdown",
  content: "# {任务名}\n\n## 任务描述\n\n## 进度\n- [ ] 待办项\n"
)
```

#### 每日笔记创建

**Trilium 操作**：

1. 查找或创建月度目录：
```
// 查找月度目录
search_notes(
  ancestorNoteId: daily_notes.root,
  query: "title:{YY}年{M}月份"
)

// 不存在则创建
create_note(
  parentNoteId: daily_notes.root,
  title: "{YY}年{M}月份",
  type: "book"
)
```

2. 查找或创建每日笔记：
```
// 查找每日笔记
search_notes(
  ancestorNoteId: {月度目录ID},
  query: "title:{YYYY}年{M}月{D}日"
)

// 不存在则创建
create_note(
  parentNoteId: {月度目录ID},
  title: "{YYYY}年{M}月{D}日 星期{X}",
  type: "book"
)
```

3. 更新配置：
```
更新 config.json:
  daily_notes.current_note_id = "trilium:{每日笔记ID}"
  daily_notes.current_note_date = "{YYYY-MM-DD}"
```

---

## 继续工作 (/workspace continue)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 获取当前日期 | Claude 直接计算当前日期和星期 | 日期格式正确 |
| 2 | 读取会话文件 | `.workspace-session-skill/session.md` | 解析成功 |
| 3 | 检查日期变化 | 比较 `daily_note_date` 与当前日期 | 判断是否跨天 |
| 4 | 跨天处理 | 创建新每日笔记，更新配置 | 新笔记已创建 |
| 4b | 检查昨日总结 | 跨天时使用**跨天前**的 `current_task_note_id`（昨日任务笔记），检查是否有每日总结章节。无则按 `references/daily-summary-template.md` 补生成。**勿用步骤 4 更新后的新 ID**。 | 总结已存在或补生成 |
| 5 | 验证定时任务 | CronList 检查任务存在 | 无则重建 |
| 6 | 展示上下文摘要 | 显示任务、决策、下一步、OpenSpec 变更状态（`active_change_id`、`change_stage`） | 用户可见 |

---

## 保存工作 (/workspace save)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 检查会话文件 | 读取 `session.md` | 文件存在且有效 |
| 2 | 更新时间戳 | `last_update` = 当前时间 | 时间戳已更新 |
| 3 | 更新任务状态 | 同步 TASKS 部分 | 任务列表已更新 |
| 4 | 更新上下文 | 添加决策、文件引用到 CONTEXT | 内容已追加 |
| 5 | 检测OpenSpec变更 | 扫描 `openspec/changes/`，更新 `active_change_id`、`change_stage` | 字段已更新 |
| 6 | 追加日志 | 在 LOG 部分添加本次对话摘要 | 日志已追加 |
| 7 | 同步项目概述（项目任务时） | 更新 Trilium 项目概述的"进度追踪"部分 | 进度已同步 |

### 同步项目概述（项目任务）

当 `task_type=project` 时，需要同步更新 Trilium 中的项目概述笔记：

**操作步骤**：
1. 获取项目概述笔记 ID
2. 读取当前内容（使用 `format: "markdown"` 获取原始格式）
3. 检查当天的进度条目是否已存在
4. 使用 `write_note` 的 `mode="edit"` + `changes` 模式在 `## 进度追踪` 和 `## 相关笔记引用` 之间插入或更新

**⚠️ 禁止使用 `write_note(mode="append")`**：项目概述末尾是 `## 相关笔记引用`，追加会插入到错误位置。必须使用 `mode="edit"` + `changes` 模式精确定位。

**⚠️ 对话缓存保护**：更新项目概述时必须保留所有已有内容，禁止覆盖或删除已有进度记录。

**Trilium 操作**：
```
// 1. 获取项目概述笔记
search_notes(
  ancestorNoteId: {project_note_id},
  query: "title:项目概述"
)

// 2. 读取当前内容（markdown格式）
get_note(noteId: {项目概述ID}, format: "markdown")

// 3. 当天条目不存在 → 在"进度追踪"和"相关笔记引用"之间插入
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{
    old_string: "## 进度追踪\n\n## 相关笔记引用",
    new_string: "## 进度追踪\n\n### {YYYY-MM-DD} ({星期})\n- [→ 任务笔记: {项目名}](#root{daily_root_path}/{month_dir_id}/{daily_note_id}/{task_note_id})\n- ✅ {已完成项}\n- ⏳ {进行中项}\n\n## 相关笔记引用"
  }]
)

// 4. 当天条目已存在 → 精确更新当天内容
write_note(
  mode: "edit",
  noteId: {项目概述ID},
  changes: [{old_string: "当天旧内容", new_string: "更新后内容"}]
)
```

**注意**：
- 任务笔记链接放在"进度追踪"的日期下
- 链接必须使用 `#root/完整路径/noteId` 格式（不能用 `trilium:{noteId}`）
- "相关笔记引用"用于用户主动添加其他引用
- **禁止使用 `write_note(mode="append")`**（会追加到"相关笔记引用"之后）
- 使用锚点 `"## 进度追踪\n\n## 相关笔记引用"` 精确定位插入位置
- **禁止删除或覆盖已有进度记录**

### --auto 参数特殊处理

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 检查日志修改时间 | 获取 `conversation.log` 的 mtime | 时间戳获取成功 |
| 2 | 与 last_update 比较 | 判断是否有新对话 | 有/无新对话 |
| 3 | 无新对话 | 若无新对话且未跨天，跳过保存。若跨天，检查昨日 `conversation.log` 是否有内容：有则触发步骤 4b，无则跳过。 | 静默退出或触发生成 |
| 4 | 有新对话 | 执行正常保存流程，然后执行跨天检测（步骤 4b） | 保存完成 |
| 4b | 跨天检测 | 比较 `daily_note_date` 与当前日期。跨天时生成昨日总结追加到昨日任务笔记末尾，**不创建新笔记**。 | 总结已生成 |

### 跨天生成昨日总结

当 `save --auto` 检测到跨天时：

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| C1 | 获取 git log | `git log --since --until` 以昨日日期范围为界 | 提交记录已获取 |
| C2 | 估算 token | `conversation.log` 字符数/4，四舍五入到千位 | token 估算值 |
| C3 | 读取任务状态 | 从 `session.md` TASKS 部分获取 | 任务快照 |
| C4 | 读取 change 信息 | 若 `active_change_id` 非空，读取 change 状态 | change 状态 |
| C5 | 生成总结 | 按 `references/daily-summary-template.md` 格式 | 格式正确 |
| C6 | 追加到笔记 | 使用 `write_note` mode="edit" + changes 模式追加到昨日任务笔记末尾 | 内容已追加 |

**⚠️ 不创建新笔记**：跨天只生成昨日总结，不创建今天的每日笔记或任务笔记。用户明天 `/workspace continue` 时自行决定新任务方向。

---

## 结束工作 (/workspace end)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 执行最终保存 | 调用 save 流程 | 状态已保存 |
| 2 | 删除定时任务 | CronDelete(id: cron_job_id) | 任务已删除 |
| 3 | 更新状态 | status: completed | 状态已更新 |
| 4 | 询问归档选项 | 保留（默认）/归档/⚠️删除（需二次确认） | 用户选择 |

### 归档选项说明

| 选项 | 操作 | 说明 |
|------|------|------|
| **保留**（默认） | 不动文件 | 下次可 `/workspace continue` 直接恢复 |
| **归档** | 移动到 `archive/` | 数据完整保留，按日期命名 |
| ⚠️ **删除** | 删除文件 | **必须二次确认**，需用户明确回复"确认删除" |

**对话缓存保护规则**：
- 归档操作只能**移动**（重命名），不能删除文件内容
- 删除选项需要用户明确确认（模糊回答视为拒绝）
- 归档目录中的历史数据永远不受影响

---

## 新任务 (/workspace new-task)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 获取每日笔记 ID | 从 config.json 读取 `current_note_id` | noteId 有效 |
| 2 | 创建任务笔记 | create_note，使用 markdown 格式，命名 `{任务名}-进行中` | 笔记已创建 |
| 3 | 有项目笔记时 | 添加双向引用链接 | 链接已添加 |
| 4 | 更新会话文件 | 追加到 TASKS 列表 | 任务已记录 |

---

## 状态查询 (/workspace status)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 读取会话文件 | session.md | 文件存在 |
| 2 | 读取配置文件 | config.json | 文件存在 |
| 3 | 显示状态 | 输出工作目录、笔记位置、任务状态等 | 用户可见 |

---

## 周报总结 (/workspace weekly-summary)

### 执行清单

| # | 步骤 | 操作 | 验证标准 |
|---|------|------|----------|
| 1 | 解析周参数 | 无参数取当前 ISO 周，计算周一至周日日期范围 | 日期范围正确 |
| 2 | 搜索本周笔记 | 对本周每天在 Trilium 中搜索每日笔记；无 Trilium 时降级本地 | 笔记列表获取 |
| 3 | 读取笔记内容 | 提取任务描述和完成状态 | 内容已提取 |
| 4 | 扫描 OpenSpec changes | Glob 扫描 `openspec/changes/*/proposal.md`，筛选本周相关 | changes 列表 |
| 5 | 按模板格式输出 | 每项一行，格式参考 `assets/weekly-summary-template.txt` 精炼程度 | 格式正确 |

### 输出格式

```
本周工作（{周一日期} - {周日日期}）
  1. {任务名}（{状态}）：{一句话描述}
  2. ...

遗留 / 下周计划：...
```

### 数据源优先级

1. Trilium 每日笔记（主）
2. `openspec/changes/`（补）
3. 本地 `.workspace-session-skill/` 文件（降级）

---

## Trilium 笔记结构

### 项目任务时的笔记结构

```
项目笔记目录 (project_notes.root)
├── VTK伪装Godot (book)              # 项目集合
│   └── 项目概述 (text)              # 子笔记（markdown格式）

每日笔记目录 (daily_notes.root)
├── 26年4月份 (book)                # 月度目录
│   └── 2026年4月2日 星期四 (book)   # 每日笔记
│       ├── VTK伪装Godot-进行中 (text)   # 任务笔记（markdown格式）
│       └── 推流测试-完成 (text)     # 任务笔记
```

### 简单任务时的笔记结构

```
每日笔记目录 (daily_notes.root)
├── 26年4月份 (book)                # 月度目录
│   └── 2026年4月2日 星期四 (book)   # 每日笔记
│       └── 临时修复-完成 (text)     # 任务笔记（markdown格式）
```

---

## 链接格式说明

### 任务笔记 → 项目笔记

在任务笔记末尾添加：
```markdown
---
[→ 项目笔记](#root{project_root_path}/{project_note_id})
```

示例：
```markdown
---
[→ 项目笔记](#root/gpGBkVSJbp5o/WswpdHC8Slyd/xD1mL4GOv0yp/8sWYAriL5cR6/DeAmum2SLplk/6YKRaFEH417L)
```

### 项目概述 → 任务笔记

在项目概述"进度追踪"部分添加：
```markdown
### 2026-04-02 (四)
- [→ 任务笔记: VTK伪装Godot](#root/V83RZAMdWE4t/j7IuML86uLAF/fGRkBZG1A113/AbCdEfGh1234/TnB8WuXqf9VO/gJw8ODEyJ1nw)
```
