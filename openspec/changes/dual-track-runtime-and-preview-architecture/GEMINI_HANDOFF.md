# Gemini 实施交接说明

## 交接目标

实施 OpenSpec change：`dual-track-runtime-and-preview-architecture`。

唯一有效的 change 路径：

`godot_zw/openspec/changes/dual-track-runtime-and-preview-architecture/`

旧的工作区外层副本不是实施依据。所有 OpenSpec 命令从 `godot_zw` 目录执行。

## 开始实施前

1. 完整读取仓库根目录的 `AGENTS.md`、`GODOT_GAME_DEV_PROTOCOL.md`。
2. 完整读取本 change 的 `proposal.md`、三份 delta spec、`design.md` 和 `tasks.md`。
3. 执行严格校验：

   ```bash
   openspec validate dual-track-runtime-and-preview-architecture --type change --strict --no-interactive
   ```

4. 检查 `improve-godot-mcp-runtime-qa` 与本 change 的重叠内容。保留已实现的命令反射和日志能力；截图来源、provenance 和失败语义以本 change 为准。
5. 只有用户明确批准 Approval Gate 1 后，才能进入 apply 和修改代码。

## 不得改变的架构约束

- `run_*` 只启动真实 `GameAbility`；`simulate_*` 只启动编辑器预览。
- `stop_project` 只停止真实运行；`stop_simulation` 只停止预览。错轨停止必须返回冲突。
- 默认 `conflict_policy` 是 `reject`。只有显式 `preempt` 才能结束另一轨。
- STARTING 阶段只能返回 `accepted`，收到匹配 READY 前不得声称 RUNNING。
- `REAL_STOP_ACK` 只表示已接收停止请求；收到匹配 `REAL_EXIT` 前不得进入 `IDLE` 或启动目标预览。
- 所有 Want、READY、STOP、EXIT、截图请求和响应都必须校验 `session_id`、`operation_id`、`event_id` 或 `request_id`，以及 `boot_nonce`。
- 删除 15 秒错误复位，但保留可配置的启动/停止握手超时。任何超时都不得终止或清空已确认健康的 RUNNING 会话。
- 预览不得改写项目脚本、生成 `@tool`、挂接 `node_added` 重写器或实例化项目 Autoload。
- 预览不得修改 `edited_root` 的持久属性或 dirty 状态。
- 真实截图服务不得依赖 `ProjectSettings` Autoload。优先使用 GameAbility 内的 ArkTS/XComponent capture agent；黑帧或旧帧时只能切换到同一 GameAbility 的 native root-Viewport backend。
- `source: "game"` 失败时不得返回 editor 或 preview 图片。`source` 不得根据当前状态重新解释。
- 规范所说的文件不变，是显式保存或 clean preflight 之后的 `project.godot` 与 `.tscn` 基线不变，不包含 `.godot` 缓存和应用私有运行文件。

## 实施顺序

严格按 `tasks.md` 顺序执行：

1. 先锁定命令、响应、错误和别名 contract，并建立会失败的 contract tests。
2. 实现唯一生命周期协调器和状态机单元测试。
3. 接入 router、工具栏、HUD 和 Ability 事件，消除旁路调用。
4. 替换预览 runner，完成脚本隔离和 edited-root 零修改。
5. 完成跨进程 session/ACK 生命周期桥。
6. 完成 GameAbility capture agent、原子 IPC 和严格 provenance。
7. 最后移除旧 Autoload 和截图回退路径。
8. 更新协议、技能、打包镜像并执行实机验收。

不要先删除旧路径再补新路径。新生命周期和真实截图闭环通过测试后，再移除旧兼容实现。

## 每项任务的完成证据

勾选任务前，至少保存以下证据之一：

- 自动化测试名称与通过结果；
- 关键状态/事件日志，包含 session 和 operation；
- GameAbility 截图响应及 provenance；
- 前后 SHA-256 清单；
- 真机操作、窗口状态和退出 ACK；
- 源文件与打包 rawfile 的哈希比对。

不得因为代码已提交或构建成功而直接勾选设备验收任务。

## 必测失败路径

- 启动失败、启动中 stop、停止中 start、重复 start/stop；
- 会话 A 的迟到 READY、EXIT、STOP ACK、截图污染会话 B；
- `REAL_STOP_ACK` 已到但 `REAL_EXIT` 未到；
- 截图 ACK 超时、捕获超时、黑帧、旧帧、损坏 PNG、错误 SHA、目录穿越；
- capture 期间 session 退出；
- 默认冲突与显式 preemption 的双向切换；
- dirty scene 的 `require_clean` 拒绝和显式 `save` 基线；
- 用户关闭窗口、返回编辑器、崩溃/系统终止、编辑器重启后的 reconciliation。

## 停止条件

出现以下情况时，停止实施并报告，不得自行缩减规范：

- GameAbility 与 EditorAbility 无法通过预定文件 IPC 或 loopback 通道交换关联事件；
- XComponent 和 native root-Viewport 两个真实 GameAbility backend 都无法产生可验证的递增帧；
- 必须修改 `project.godot` 或 `.tscn` 才能注入运行 QA 服务；
- 无法区分真实退出、停止已接收和状态未知；
- 需要恢复静默截图回退、15 秒运行复位或动态 `@tool` 改写才能通过测试。

## 结束实施

完成 `tasks.md` 后，提交测试、真机截图、生命周期日志、文件哈希和已知限制，进入 Approval Gate 2。用户批准前，不归档 change。
