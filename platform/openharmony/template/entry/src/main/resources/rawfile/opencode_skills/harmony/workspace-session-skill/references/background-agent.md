# 后台子 Agent 协议

## 概览

save 操作卸载到后台子 Agent（`general-purpose`），主 Agent 立即返回，完成后通知。

## 子 Agent 配置

| 参数 | 值 |
|------|-----|
| 模型 | general-purpose（默认即可，无需指定；若环境支持 haiku 可用 `agent_type="haiku"` 降本） |
| 超时 | 5 分钟 (300000ms) |
| 隔离 | 无 (共享工作目录) |
| 后台 | true |

## 子 Agent Prompt 模板

派发时主 Agent 组装以下 prompt：

```
你是 workspace-session-skill 的后台执行 Agent。

## 任务
执行 save 操作。

## 上下文
- 工作目录: {workspace_dir}
- session.md: {session_summary}
- 项目 noteId: {project_note_id}
- 项目概述 noteId: {overview_note_id}
- 任务笔记 noteId: {task_note_id}
- 活跃阶段进度 noteId: {phase_progress_id}
- 活跃 OpenSpec change: {active_change_id}（如 `ai-conversations-storage-optimization`）

## 操作清单
1. **读取 OpenSpec change 获取权威进度**（如有 active_change_id）：
   - 读取 `openspec/changes/{active_change_id}/tasks.md`，提取已完成/未完成任务数
   - 读取 `openspec/changes/{active_change_id}/proposal.md` 标题
   - 在 session.md LOG 和 Trilium 笔记中**引用 change 目录路径**，而非重复 change 内容
2. 更新 session.md (last_update, TASKS, CONTEXT)
3. 同步项目概述 (进度追踪)
4. 同步任务笔记 (进度 + 今日工作记录)
5. 同步阶段进度（如有活跃阶段）
6. 输出结果摘要

## 规则
- 禁止使用 AskUserQuestion
- 禁止删除任何数据
- 冲突时保留两方
- 超时 5 分钟自动终止
- 错误不中断，继续处理剩余文件
```

## 主 Agent 派发

```
子 Agent 启动后主 Agent 立即返回:
  "💾 保存已后台执行，完成后通知"

子 Agent 完成 → 主 Agent 收到通知:
  - status=ok      → "✅ 保存完成"
  - status=error   → "⚠️ 后台保存异常: <error>"
```

## OpenSpec Change 作为权威记录

当 `active_change_id` 非空时，后台 Agent 必须遵循以下原则：

**权威来源**：`openspec/changes/{active_change_id}/` 目录是变更的权威记录。
- tasks.md 包含精确的任务完成状态（`- [x]` / `- [ ]`）
- proposal.md 包含 WHY 和 WHAT
- design.md 包含技术决策
- specs/ 包含 GIVEN/WHEN/THEN 行为规格

**记录规则**：
1. **session.md LOG**：写入对 change 的引用 + 1-2 句本轮进展摘要，格式：
   ```
   HH:MM save: [{change_id}] 本轮：{具体进展}。Change 进度：{N}/{M} tasks。详见 openspec/changes/{change_id}/
   ```
2. **Trilium 项目概述**：引用 change 目录，标注进度（如 "8/9 issues fixed"）
3. **Trilium 任务笔记**：列出本轮具体修复的 issue 编号和简要描述
4. **禁止**在 session.md 或 Trilium 中复制 tasks.md 的全部内容

## 失败恢复

| 场景 | 处理 |
|------|------|
| 子 Agent 超时 (5min) | 通知用户 "⚠️ 后台保存超时"，last_update 不更新 |
| 子 Agent 异常退出 | 通知用户，保留 .workspace-session-skill/ 中的数据 |
| 子 Agent MCP 不可用 | 降级：仅更新 session.md 本地文件，跳过 Trilium 操作 |
| 连续失败 3 次 | 提示用户检查 Trilium MCP 服务状态 |

## save --auto 特殊处理

save --auto 执行顺序（跨天检测优先，分两阶段）：

### 阶段 1：跨天检测（主 Agent 同步执行，不 spawn 子 Agent）

1. 比较 `daily_note_date` 与当前日期。若不跨天或 conversation.log 为空，跳过此阶段，进入阶段 2
2. **跨天 + 有新对话**：主 Agent 先执行同步保存（按 save 清单步骤 1-6c），确保 session.md、TASKS、CONTEXT、Trilium 笔记全部更新到最新
3. **跨天（有新对话或无新对话）**：生成昨日总结（按 daily-summary-template.md），追加到昨日任务笔记
4. CronDelete 关闭定时任务

**关键设计**：跨天时如果有新对话（如凌晨还在工作的场景），先保存再总结，避免总结遗漏。保存必须同步执行（不能走后台子 Agent），因为总结依赖保存后的最新数据。

### 阶段 2：正常保存（仅在未跨天时执行）

1. 检查 conversation.log mtime:
   - mtime ≤ last_update → 无新对话 → 跳过 (不 spawn)
   - mtime > last_update → 有新对话 → spawn 后台子 Agent

子 Agent Prompt 中无需包含跨天指令（跨天已在阶段 1 由主 Agent 处理完毕）。
