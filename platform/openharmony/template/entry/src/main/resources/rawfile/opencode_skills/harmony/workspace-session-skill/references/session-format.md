# 会话文件格式

## 统一存储目录

所有文件统一存放在：

```
{工作目录}/.workspace-session-skill/
├── config.json              # 项目本地配置（从全局配置同步）
├── session.md               # 当前会话状态
├── conversation.log         # 对话日志
├── notes/                   # 本地笔记（Trilium不可用时使用）
└── archive/                 # 归档目录
```

**说明**：不再区分不同 Agent 的目录，统一使用 `.workspace-session-skill` 目录。

---

## 目录结构详解

### config.json

从 `~/.agents/skills_settings.json` 同步的配置：

```json
{
  "daily_notes": {
    "root": "trilium:fGRkBZG1A113",
    "root_path": "#root/V83RZAMdWE4t/j7IuML86uLAF/fGRkBZG1A113",
    "current_note_id": "trilium:TnB8WuXqf9VO",
    "current_note_date": "2026-04-02",
    "month_dir_id": "trilium:AbCdEfGh1234",
    "current_task_note_id": "trilium:gJw8ODEyJ1nw"
  },
  "project_notes": {
    "root": "trilium:wz1kyVAE8HVO",
    "root_path": "#root/V83RZAMdWE4t/j7IuML86uLAF/wz1kyVAE8HVO",
    "plan_folder_id": "trilium:XyZ123AbCdEf",
    "progress_folder_id": "trilium:GhI456JkLmNop",
    "overview_note_id": "trilium:Ov123XyZ456Ab"
  },
  "active_phase": {
    "phase_name": "Phase 0: 核心验证",
    "plan_note_id": "trilium:PhasePlan001",
    "progress_note_id": "trilium:PhaseProgress001"
  }
}
```

### session.md

当前会话状态：

```markdown
# WORKSPACE SESSION
workspace: D:/work/project
started: 2026-04-02T10:30:00+08:00
last_update: 2026-04-02T14:20:00+08:00
status: active
task_type: project

# 笔记引用
daily_note_id: trilium:TnB8WuXqf9VO
daily_note_date: 2026-04-02
month_dir_id: trilium:AbCdEfGh1234
current_task_note_id: trilium:gJw8ODEyJ1nw
project_note_id: trilium:DeAmum2SLplk
project_name: VTK伪装Godot
overview_note_id: trilium:Ov123XyZ456Ab
plan_folder_id: trilium:XyZ123AbCdEf
progress_folder_id: trilium:GhI456JkLmNop
active_phase_name: "[v1.0] Phase 0: 核心验证"
active_phase_plan_id: trilium:PhasePlan001
active_phase_progress_id: trilium:PhaseProgress001
task_started_at: 2026-04-02T10:35:00+08:00
active_change_id: workspace-skill-enhancements
change_stage: apply

# 自动保存
autosave: 60m
cron_job_id: "job_xxx"

---
# TASKS
- [ ] 实现 token 刷新接口
- [ ] 添加单元测试
- [x] 完成登录接口

---
# CONTEXT
决策:
- 使用 JWT 进行身份验证 - 无状态、易扩展
- token 有效期 15 分钟 - 平衡安全性和体验

文件:
- 主文件: src/auth/login.cpp
- 配置: config/settings.json

下一步:
1. 实现 refresh 接口
2. 添加并发锁机制

---
# LOG
## 2026-04-02 10:30 - 初始化认证模块
用户要求实现用户认证功能，讨论后决定使用 JWT。

关键点:
- 选择 JWT 而非 session
- 计划支持 refresh token
```

### conversation.log

对话日志格式：

```
[2026-04-02 10:30:15] USER: 开始工作
[2026-04-02 10:30:45] CLAUDE: 创建工作区会话，初始化每日笔记...
[2026-04-02 10:35:22] USER: 实现用户登录功能
[2026-04-02 10:36:01] CLAUDE: 我来帮你实现用户登录功能...
```

---

## 字段说明

### session.md 元数据

| 字段 | 必填 | 说明 |
|------|------|------|
| `workspace` | 是 | 工作目录绝对路径 |
| `started` | 是 | 开始时间 (ISO 8601) |
| `last_update` | 是 | 最后更新时间 |
| `status` | 是 | active/paused/completed |
| `task_type` | 是 | project/simple（项目任务/简单任务） |

### session.md 笔记引用

| 字段 | 必填 | 说明 |
|------|------|------|
| `daily_note_id` | 是 | 每日笔记 ID |
| `daily_note_date` | 是 | 每日笔记日期 |
| `month_dir_id` | 是 | 月度目录 ID（用于链接构建） |
| `current_task_note_id` | 是 | 当前任务笔记 ID |
| `project_note_id` | 否 | 项目笔记 ID（项目任务时） |
| `project_name` | 否 | 项目名称（项目任务时） |
| `overview_note_id` | 否 | 项目概述笔记 ID（项目任务时，new-phase 需要） |
| `plan_folder_id` | 否 | 开发计划子文件夹 ID（项目任务时） |
| `progress_folder_id` | 否 | 编码进度子文件夹 ID（项目任务时） |
| `active_phase_name` | 否 | 当前活跃阶段名称，如 "[v1.0] Phase 0: 核心验证" |
| `active_phase_plan_id` | 否 | 当前活跃阶段的计划笔记 ID |
| `active_phase_progress_id` | 否 | 当前活跃阶段的进度笔记 ID |
| `task_started_at` | 否 | 当前任务开始时间（ISO 8601），用于计算 HH:mm-HH:mm 工作记录 |
| `active_change_id` | 否 | 当前活跃的 OpenSpec change ID（自动检测，为空时表示无活跃 change） |
| `change_stage` | 否 | 当前 change 所处阶段。合法值：`explore`、`propose`、`apply`、`archive`、空（无活跃 change） |

### TASKS 部分

使用 Markdown 任务列表：
- `- [ ]` 待完成
- `- [x]` 已完成

### CONTEXT 部分

精简为核心信息：
- **决策**: 关键决策及原因
- **文件**: 相关文件引用
- **下一步**: 待执行操作

**结构化子块**（save 7c 自动解析并同步到阶段进度笔记）：

```markdown
## 门禁
| 验证项 | 状态 | 说明 |
|--------|------|------|
| 编译通过 (debug) | ✅ | 2026-05-25 验证通过 |

## 决策:
- 使用 JWT 进行身份验证 → 原因: 无状态易扩展 → 影响: auth 模块
```

- **门禁**: Markdown 表格，save 7c 逐行合并到阶段进度笔记的 `## 门禁验证` 表格
- **决策:**: 每条格式为 `{决策} → 原因: {原因} → 影响: {影响范围}`，save 7c 解析后追加到 `## 关键技术决策` 表格

### LOG 部分

对话记录格式：
```
## {时间} - {主题}
{摘要}

关键点:
- {要点1}
- {要点2}
```

---

## 状态值

| 状态 | 含义 |
|------|------|
| `active` | 会话活跃 |
| `paused` | 暂停 |
| `completed` | 已完成 |

## 任务类型

| 类型 | 含义 | Trilium笔记 |
|------|------|-------------|
| `project` | 项目任务 | 创建项目笔记 + 每日笔记 |
| `simple` | 简单任务 | 仅创建每日笔记 |

---

## 归档格式

归档目录：

```
.workspace-session-skill/archive/
├── 2026-04-01-session.md
├── 2026-04-01-conversation.log
└── ...
```

归档文件命名：
- 会话：`{YYYY-MM-DD}-session.md`
- 日志：`{YYYY-MM-DD}-conversation.log`

**归档保护规则**：
- 归档操作只能**移动**（重命名），不能删除文件内容
- 归档文件永远保留，不会被自动清理
- 开始新会话时，已有缓存数据自动归档而非删除

---

## 格式版本

会话文件格式版本: 4.3

> 注：此为文件格式版本，与技能版本独立。技能版本见 [CHANGELOG.md](../CHANGELOG.md)
