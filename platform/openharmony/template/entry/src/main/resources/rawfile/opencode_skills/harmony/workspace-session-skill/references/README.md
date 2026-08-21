# 参考文档导航

本目录包含 workspace-session-skill 的详细参考文档。

## 文档索引

| 文档 | 用途 | 查阅场景 |
|------|------|----------|
| [configuration.md](configuration.md) | 配置管理详解 | 配置 skills_settings.json、理解配置优先级 |
| [workflow.md](workflow.md) | 工作流详解 | 了解 start/continue/save/end 详细步骤 |
| [notes-management.md](notes-management.md) | 笔记管理详解 | 创建笔记、理解三级结构、双向引用 |
| [session-format.md](session-format.md) | 会话文件格式 | 解析 .workspace-session.md |
| [autosave.md](autosave.md) | 自动保存机制 | 配置定时保存、理解 Cron 任务 |
| [trilium-integration.md](trilium-integration.md) | Trilium 集成 | 使用 Trilium MCP、链接格式 |
| [project-overview.md](project-overview.md) | 项目概述笔记 | 本地项目进度追踪 |
| [flowcharts.md](flowcharts.md) | 流程图 | 可视化理解工作流程 |

## 快速查阅指南

### 我想配置笔记存储位置

→ 阅读 [configuration.md](configuration.md)

### 我想了解工作流执行步骤

→ 阅读 [workflow.md](workflow.md)

### 我想创建项目笔记

→ 阅读 [notes-management.md](notes-management.md) → 项目笔记管理

### 我想了解 Trilium 链接格式

→ 阅读 [notes-management.md](notes-management.md) → Trilium 链接格式

### 我想配置自动保存

→ 阅读 [autosave.md](autosave.md)

### 我想理解会话文件结构

→ 阅读 [session-format.md](session-format.md)

### 我想查看流程图

→ 阅读 [flowcharts.md](flowcharts.md)

---

## 文档关系

```
skill.md (核心定义)
    │
    ├── 配置管理 → configuration.md
    │                   └── trilium-integration.md
    │
    ├── 工作流 → workflow.md
    │               └── autosave.md
    │
    ├── 笔记管理 → notes-management.md
    │                   ├── session-format.md
    │                   └── project-overview.md
    │
    └── 流程图 → flowcharts.md
```

---