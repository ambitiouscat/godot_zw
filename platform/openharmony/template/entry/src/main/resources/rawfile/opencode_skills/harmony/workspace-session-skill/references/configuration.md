# 配置管理详解

## 核心原则

**重要**：技能目录下的 `settings.json` 只是**配置模板**，运行时不直接读取。

实际配置从 `~/.agents/skills_settings.json` 读取。

---

## 配置文件位置

### 运行时配置（唯一有效来源）

```
~/.agents/skills_settings.json
```

此文件是跨 Agent 共享的统一配置，所有 Agent 都从这里读取配置。

### 配置模板（仅供参考）

```
{技能目录}/settings.json
```

此文件仅作为模板参考，不会被运行时读取。用户需要将配置复制到 `~/.agents/skills_settings.json`。

---

## 配置文件格式

### skills_settings.json 格式

```json
{
  "workspaceSession": {
    "daily_notes": {
      "root": "trilium:NOTE_ID",
      "root_path": "#root/path/to/daily/notes",
      "description": "每日笔记目录（book类型，存放月度目录）",
      "current_note_id": "",
      "current_note_date": ""
    },
    "project_notes": {
      "root": "trilium:NOTE_ID",
      "root_path": "#root/path/to/project/notes",
      "description": "项目笔记目录（book类型，存放项目集合）"
    },
    "default_local_path": "notes"
  }
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `daily_notes.root` | string | 是 | 每日笔记根目录 ID，格式 `trilium:NOTE_ID` |
| `daily_notes.root_path` | string | 否 | 完整路径，用于链接生成 |
| `daily_notes.current_note_id` | string | 自动 | 当前每日笔记 ID（自动更新） |
| `daily_notes.current_note_date` | string | 自动 | 当前每日笔记日期 `YYYY-MM-DD`（自动更新） |
| `daily_notes.month_dir_id` | string | 自动 | 当前月度目录 ID（自动更新） |
| `daily_notes.current_task_note_id` | string | 自动 | 当前任务笔记 ID（自动更新，用于 save 时定位） |
| `project_notes.root` | string | 否 | 项目笔记根目录 ID |
| `project_notes.root_path` | string | 否 | 完整路径 |
| `default_local_path` | string | 否 | Trilium 不可用时的本地路径 |

### 值格式

- **Trilium 笔记**：`"trilium:{noteId}"`，如 `"trilium:FuT5x6wnIWXH"`
- **本地路径**：`"local:{路径}"`，如 `"local:notes"`

---

## 配置同步机制

### 同步目标

开始工作时，将 `~/.agents/skills_settings.json` 中的配置同步到项目本地：

```
{工作目录}/.workspace-session-skill/config.json
```

### 同步时机

| 命令 | 同步操作 |
|------|----------|
| `/workspace start` | 读取全局配置，同步到项目本地 |
| `/workspace continue` | 检查配置是否需要更新 |

### 同步流程

1. 读取 `~/.agents/skills_settings.json` 的 `workspaceSession` 字段
2. 检查 `{工作目录}/.workspace-session-skill/` 目录是否存在
3. 不存在则创建目录
4. 写入 `config.json` 到该目录
5. 后续操作使用本地 `config.json`

---

## 配置更新

### current_note_id 和 current_note_date 更新

创建或获取每日笔记后，更新这些字段：

```json
{
  "daily_notes": {
    "current_note_id": "trilium:TnB8WuXqf9VO",
    "current_note_date": "2026-04-02",
    "month_dir_id": "trilium:AbCdEfGh1234",
    "current_task_note_id": "trilium:gJw8ODEyJ1nw"
  }
}
```

更新位置：
1. 项目本地：`{工作目录}/.workspace-session-skill/config.json`
2. 全局配置：`~/.agents/skills_settings.json`（可选）

---

## 配置验证

### 格式验证

- `root` 格式：`trilium:{noteId}` 或 `local:{path}`
- noteId 长度：12 字符字母数字

### 连接验证

- Trilium 配置：调用 `search_notes` 或 `get_note` 测试连接
- 连接失败：提示并降级本地模式

### 验证失败处理

- 警告提示但不阻塞启动
- 自动使用降级模式（本地路径）
- 记录验证日志到对话日志

---

## 降级处理

当 Trilium MCP 不可用或配置为空时：

- 使用本地 Markdown 文件
- 路径：`{工作目录}/.workspace-session-skill/notes/`
- 文件名：`{YYYY-MM-DD}.md`

---

## 配置示例

### 完整配置示例

```json
{
  "workspaceSession": {
    "daily_notes": {
      "root": "trilium:fGRkBZG1A113",
      "root_path": "#root/V83RZAMdWE4t/j7IuML86uLAF/fGRkBZG1A113",
      "description": "每日笔记目录",
      "current_note_id": "trilium:TnB8WuXqf9VO",
      "current_note_date": "2026-04-02",
      "month_dir_id": "trilium:AbCdEfGh1234",
      "current_task_note_id": "trilium:gJw8ODEyJ1nw"
    },
    "project_notes": {
      "root": "trilium:wz1kyVAE8HVO",
      "root_path": "#root/V83RZAMdWE4t/j7IuML86uLAF/wz1kyVAE8HVO",
      "description": "项目笔记目录"
    },
    "default_local_path": "notes"
  }
}
```
