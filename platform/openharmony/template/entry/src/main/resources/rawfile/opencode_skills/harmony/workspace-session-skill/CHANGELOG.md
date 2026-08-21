# Changelog

All notable changes to workspace-session-skill will be documented in this file.

## [4.7.0] - 2026-06-02

### Added
- **文件同步系统**：
  - 新增 `/workspace add` 命令：将文件/文件夹加入同步清单，映射到 Trilium 笔记树（book 嵌套模拟目录）
  - 新增 `/workspace sync` 命令：双向同步，mtime+标准化hash三级检测，推送/拉取/冲突标记
  - 新增 `assets/normalize-hash.sh`：标准化 hash 管道（strip BOM / CRLF→LF / trim → SHA-256）
  - 新增 `assets/sync-report-template.json`：子 Agent 结构化报告模板
  - 新增 `assets/commit-msg-body.sh`：追加到已有 hook 的无 shebang 逻辑体
- **后台子 Agent 执行**：
  - save/sync 操作卸载到 Haiku 后台子 Agent，主 Agent 立即返回
  - 新增 `references/background-agent.md`：子 Agent 协议文档（prompt 模板 / 超时 / 失败恢复）
  - save --auto 集成同步检查：步骤 5 后自动执行文件同步
- **冲突处理**：
  - 子 Agent 检测冲突自动保留两方（本地不动 + 笔记 rename .conflict-<ISO8601>）
  - 主 Agent AskUserQuestion 弹出 4 选项用户选择
  - 超时 5 分钟保持保底状态，下次 sync 重提
- **新参考文档**：
  - 新增 `references/sync-design.md`：同步引擎完整技术文档

### Changed
- save 流程改造为主 Agent 派发后台子 Agent 模式
- 错误处理表格扩展（sync/add/save 子 Agent 相关错误）

## [4.6.1] - 2026-06-02

### Added
- Git Co-authored-by hook 自动部署到所有 git 子项目
- SKIP_AI_TRAILER=1 跳过机制
- 已有 hook 覆盖保护（无 shebang 追加模式）

## [4.5.0] - 2026-05-25

### Added
- **项目阶段化管理**：
  - 新增核心规则 #12：项目任务强制创建"开发计划"和"编码进度"双文件夹架构
  - 新增 `/workspace new-phase` 命令：支持按 `[阶段号] [阶段名称]` 分步创建配对的计划与进度笔记
  - 自动迁移逻辑：`/workspace new-phase` 在老项目运行时会自动识别并创建缺失的开发计划/编码进度子文件夹
  - 阶段计划/进度笔记模板：包含门禁、关键决策、部署命令与小时级工作日志
- **工作块计时与自动日志编译**：
  - Session 元数据引入 `task_started_at`：精确追踪每次会话或子任务开始时刻
  - 自动编译今日记录：`/workspace save` 根据 `task_started_at` 自动编译 `HH:mm-HH:mm` 小时级日志并写入进度笔记，随后更新计时起点
- **关系属性标记为“未来增强”**：在笔记管理参考中将 Trilium 语义关系关系属性标记为未来增强，当前优先保障标准导航的强韧性
- Session 格式 v4.3：新增 `plan_folder_id`、`progress_folder_id`、`active_phase_name`、`active_phase_plan_id`、`active_phase_progress_id`、`task_started_at` 字段

### Changed
- `/workspace start` 项目任务分支：自动在项目根下创建"开发计划"和"编码进度"子文件夹
- 项目概述模板：新增"阶段概览"索引表格
- 笔记体系表格：扩展为包含阶段相关笔记类型及三层内容分工规范

## [4.2.1] - 2026-04-28

### Fixed
- **CRITICAL: 项目概述 append 位置错误**：`append_note_content` 会追加到"相关笔记引用"之后，改为使用 `update_note_content` 的 `changes` 模式在 `## 进度追踪` 和 `## 相关笔记引用` 之间精确插入
- **MEDIUM: 流程图旧文件名**：修正 `references/flowcharts.md` 中 `.workspace-conversation.log` → `conversation.log`，`.workspace-session.md` → `session.md`
- **MEDIUM: Cron 表达式不一致**：统一 `references/flowcharts.md` 中的 `3,13,23,33,43,53` → `7 * * * *`（每小时）
- **MEDIUM: last_reviewed 过期**：更新 `skill.md` 中 `last_reviewed` 为 `2026-04-28`
- **LOW: 规则编号不一致**：`commands/workspace.md` 补齐"正确计算星期"、"不设置 notePosition"、"禁止响应废弃命令"规则，编号与 `skill.md` 对齐
- **LOW: 日志轮转竞态条件**：`log-utils.js` 的 `rotateLogIfNeeded` 增加并发 rename 失败处理（ENOENT/EPERM 安全忽略）
- **INFO: continue 缺少缓存处理**：无 `session.md` 时检查 `conversation.log` 是否存在并给出恢复建议
- **LOW: 删除残留文件**：移除 `111SKILL.md`

---

## [4.2.0] - 2026-04-28

### Added
- **对话缓存保护机制**：
  - 新增核心规则 #9：发现对话记录/缓存数据时禁止删除或覆盖
  - `conversation.log` 永远只追加，不覆盖、不截断
  - `session.md` 的 LOG/CONTEXT/TASKS 部分永远只追加新内容
  - 归档操作只能重命名/移动，不能删除原始文件
- **start 命令缓存检测**：检测到已有会话或对话日志时提示用户处理方式
- **end 命令删除保护**：
  - 默认选项改为"保留"
  - 删除选项需二次确认
  - 模糊回答视为拒绝删除

### Changed
- 更新 `skill.md`：新增对话缓存保护核心规则
- 更新 `commands/workspace.md`：强制规则增加缓存保护条款
- 更新 `references/workflow.md`：项目概述使用 `changes` 模式精确定位插入
- 更新 `references/flowcharts.md`：结束流程图增加二次确认节点
- 更新 `references/session-format.md`：归档保护规则说明
- 更新 `references/autosave.md`：日志轮转保留说明

---

## [4.1.0] - 2026-04-02

### Breaking Changes
- **统一存储目录**：所有文件统一存放在 `.workspace-session-skill/` 目录
  - 不再区分不同 Agent 的目录
  - 移除 `{agent_dir}` 路径依赖
- **配置机制重构**：
  - `settings.json` 仅作为模板，运行时不读取
  - 统一从 `~/.agents/skills_settings.json` 读取配置
  - 同步到项目本地 `.workspace-session-skill/config.json`

### Added
- **任务类型选择**：开始工作时询问"项目任务"或"简单任务"
  - 项目任务：创建项目笔记 + 每日笔记
  - 简单任务：仅创建每日笔记
- **配置字段扩展**：
  - `daily_notes.current_note_id`：当前每日笔记 ID
  - `daily_notes.current_note_date`：当前每日笔记日期
- **执行清单表格化**：所有命令使用表格格式的执行清单
  - 步骤编号、操作说明、验证标准
  - 强制顺序执行

### Changed
- 重写 `commands/workspace.md`：添加完整执行清单
- 重写 `references/configuration.md`：说明配置模板和同步机制
- 重写 `references/session-format.md`：统一目录结构
- 重写 `references/workflow.md`：项目任务/简单任务分支流程
- 更新 `SKILL.md`：更新核心规则和目录结构说明
- 更新 `references/notes-management.md`：四级笔记结构

### Removed
- 移除 `/workspace project start/end` 命令（合并到 start 的任务类型选择）
- 移除 `{agent_dir}` 路径概念

---

## [4.0.3] - 2026-04-01

### Added
- 多平台插件支持
  - 新增 `.claude-plugin/plugin.json` (Claude Code)
  - 新增 `.cursor-plugin/plugin.json` (Cursor)
  - 新增 `.opencode/INSTALL.md` (OpenCode 安装指南)
  - 新增 `.codex/INSTALL.md` (Codex 安装指南)
- 符号链接安装机制
  - 单一源码位置 (`~/.agents/skills/workspace-session-skill`)
  - 所有 Agent 通过符号链接共享
  - 更新源码自动同步到所有平台

### Changed
- 重写 `install.sh`
  - 从复制模式改为符号链接模式
  - Claude Code 安装到 `~/.claude/plugins/` (而非 skills/)
  - 支持 `--uninstall` 卸载命令
- 修复 hooks.json 变量
  - 使用 `${CLAUDE_PLUGIN_ROOT}` 替代自定义 `${skillDir}`
  - 确保 hooks 在 plugin 目录下正确加载
- 更新 README.md 安装说明

### Fixed
- Hooks 不被 Claude Code 加载的问题
  - 原因：Skills 目录的 hooks 不被加载
  - 解决：安装到 plugins 目录并添加 plugin.json

---

## [4.0.2] - 2026-04-01

### Changed
- 版本号统一管理
  - 版本号仅存在于 skill.md (frontmatter) 和 CHANGELOG.md
  - README 文件改为引用 CHANGELOG.md
  - 移除 references 文档末尾的版本号行
- 删除冗余脚本文件
  - 移除 bash 脚本 (`log-user.sh`, `log-assistant.sh`)
  - 统一使用 Node.js 跨平台方案
- 删除过时文档
  - 移除 `references/optimization-design.md`（内容已过时，优化已完成）
- 修复 flowcharts.md 配置层描述
  - 将 "~/.claude/settings.json" 改为 "skills_settings.json"

---

## [4.0.1] - 2026-04-01

### Added
- 跨平台日志脚本 (`log-user.js`, `log-assistant.js`)
  - Node.js 实现，支持 Windows/Linux/Mac
  - 自动日志轮转（超过 1MB 自动归档）
- hooks.json 使用变量替换 (`${skillDir}`, `${workspaceFolder}`)
- 完整的命令参数文档
  - 参数必填标记
  - 错误提示表格
  - 参数详解说明

### Changed
- hooks.json 默认使用 Node.js 脚本（跨平台兼容）
- 会话模板格式统一为简化格式（无 frontmatter）
- bash 脚本添加日志轮转功能
- Cron 表达式说明统一，明确推荐避整点表达式

### Fixed
- hooks 路径硬编码问题（多 Agent 环境兼容）
- Windows 用户无法使用 hooks 功能的问题
- session-template.md 格式与 session-format.md 不一致

---

## [4.0.0] - 2026-03-19

### Added
- 项目概述笔记 (PROJECT_OVERVIEW.md)
  - 本地 Markdown 文件
  - 与 Trilium 笔记双向同步
- 本地配置同步机制
  - 启动项目时自动同步到 settings.local.json
- 自动保存触发条件优化
  - 仅在有新对话时更新

### Changed
- 配置优先级调整
  - local > home > agents > skill
- 会话文件格式简化 (v3.2)
  - 移除 YAML frontmatter
  - Markdown 分段结构

---

## [3.1.0] - 2026-03-15

### Added
- 多 Agent 支持
  - Claude Code, Cursor, Gemini CLI, OpenCode
  - Universal (.agents) 通用路径
- Agent 类型自动检测

### Changed
- 配置文件统一使用 skills_settings.json
  - 避免与 settings.json Schema 冲突

---

## [3.0.0] - 2026-03-10

### Added
- 双向引用机制
  - 任务笔记 ↔ 项目笔记互相跳转
- 笔记命名规范
  - `{任务名}-{状态}` 格式

### Changed
- 每日笔记规则调整
  - 禁止使用 get_day_note() API
  - 使用 search_notes() 查找

---

## [2.0.0] - 2026-03-05

### Added
- Trilium MCP 集成
- 本地 Markdown 降级模式

---

## [1.0.0] - 2026-03-01

### Added
- 基础工作会话管理
  - start, save, continue, end 命令
- 会话状态持久化
- 对话日志记录