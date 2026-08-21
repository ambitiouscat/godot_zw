# workspace-session-skill

工作区会话管理技能，用于 AI Agent 跨会话持久化工作状态、记录关键对话、追踪任务进度。

## 功能特性

- 🔄 **跨会话状态保持** - 新会话可无缝接续上次工作
- 📝 **智能笔记管理** - 每日笔记、任务笔记、项目笔记三级结构
- 📊 **项目概述笔记** - 本地 Markdown 项目进度追踪
- 🔗 **双向引用** - 任务笔记与项目笔记互相跳转
- ⏰ **自动保存** - Cron 定时任务自动保存进度
- 🖥️ **多 Agent 支持** - Claude Code、Cursor、Gemini CLI、OpenCode 等
- 📦 **双存储模式** - Trilium MCP / 本地 Markdown 降级
- 🔗 **符号链接安装** - 单一源码，更新自动同步到所有 Agent

## 快速开始

### 安装

```bash
# 克隆到统一位置
git clone https://gitee.com/ambitiouscat/workspace-session-skill.git \
  ~/.agents/skills/workspace-session-skill

# 运行安装脚本（自动检测已安装的 Agent）
cd ~/.agents/skills/workspace-session-skill
./install.sh

# 或指定平台
./install.sh --platform claude-code
./install.sh --platform cursor
./install.sh --all              # 安装到所有平台
```

### 安装说明

安装脚本会创建**符号链接**，而不是复制文件：

| Agent | 安装位置 |
|-------|----------|
| Claude Code | `~/.claude/plugins/workspace` → 源码 |
| Cursor | `~/.cursor/plugins/workspace` → 源码 |
| OpenCode | `~/.config/opencode/skills/workspace` → 源码 |

**好处**：更新源码后，所有 Agent 自动同步，无需重新安装。

### 更新

```bash
cd ~/.agents/skills/workspace-session-skill
git pull
# 所有 Agent 自动同步
```

### 配置

使用 `skills_settings.json`：

```json
{
  "workspaceSession": {
    "daily_notes": {
      "root": "trilium:YOUR_NOTE_ID",
      "root_path": "#root/path/to/note"
    },
    "project_notes": {
      "root": "trilium:YOUR_NOTE_ID",
      "root_path": "#root/path/to/note"
    }
  }
}
```

**配置文件位置**（按优先级）：
1. `~/.agents/skills_settings.json` ← **唯一有效来源**
2. `.workspace-session-skill/config.json` ← 项目本地（自动同步）

无配置时自动使用本地路径 `.workspace-session-skill/notes/`

### 使用

```
/workspace start            # 开始工作会话（询问项目/简单任务）
/workspace save             # 保存当前进度
/workspace continue         # 继续上次会话
/workspace new-task 任务名  # 创建任务笔记
/workspace status           # 显示会话状态
/workspace end              # 结束工作会话
```

自然语言：`开始工作`、`保存工作`、`继续工作`、`结束工作`

## 多平台支持

| 平台 | 配置目录 | 安装说明 |
|------|----------|----------|
| Claude Code | `.claude-plugin/` | 自动检测 |
| Cursor | `.cursor-plugin/` | 自动检测 |
| OpenCode | `.opencode/` | 见 `.opencode/INSTALL.md` |
| Codex | `.codex/` | 见 `.codex/INSTALL.md` |

## 文档结构

```
workspace-session-skill/
├── .claude-plugin/
│   └── plugin.json            # Claude Code 元数据
├── .cursor-plugin/
│   └── plugin.json            # Cursor 元数据
├── .opencode/
│   └── INSTALL.md             # OpenCode 安装说明
├── .codex/
│   └── INSTALL.md             # Codex 安装说明
├── skill.md                   # 核心技能定义
├── hooks/
│   └── hooks.json             # Hooks 配置
├── scripts/
│   ├── log-user.js            # 用户输入记录
│   └── log-assistant.js       # 助手回复记录
├── commands/
│   └── workspace.md           # 斜杠命令定义
├── references/                # 详细参考文档
└── install.sh                 # 符号链接安装脚本
```

## 参考文档

从 `references/README.md` 开始，按需查阅：

| 文档 | 用途 |
|------|------|
| configuration.md | 配置管理详解 |
| workflow.md | 工作流详细步骤 |
| notes-management.md | 笔记层级结构和管理 |
| flowcharts.md | 可视化流程图 |

## 版本与变更

见 [CHANGELOG.md](CHANGELOG.md)

## 许可证

MIT License