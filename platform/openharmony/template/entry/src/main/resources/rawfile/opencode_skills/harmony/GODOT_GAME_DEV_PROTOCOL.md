# Godot 游戏开发总控协议规范 (GGD-Protocol-v1)

> **版本**: 1.0.0
> **适用环境**: Godot 4.x (OpenHarmony / PC / Linux) + OpenCode + Godot In-Engine MCP
> **角色定位**: 本协议为整个 AI 智能体开发流程的最高指导规范。所有交互、代码编写、节点装配与测试验证必须严格遵循本协议状态机流转。

---

## 🧭 全局生命周期状态机 (6-Stage Lifecycle)

`
[ 用户意图 / GDD 文档输入 ]
       │
       ▼
┌────────────────────────────────────────────────────────┐
│ Stage 0: 探测与会话初始化 (Reconnaissance)             │
│ • 调用 get_editor_state、get_project_structure         │
│ • 读取 .workspace-session 恢复上下文                   │
└───────────────────────┬────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│ Stage 1: 意图分类与专家指派 (Specialist Routing)       │
│ • 新游戏 / 功能扩展 / 关卡设计 / 视听打磨 / 错误自愈     │
└───────────────────────┬────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│ Stage 2: 架构设计与 OpenSpec 提案 (GDD Architecture)   │
│ • Fun Hypothesis + 3-5 Design Pillars                  │
│ • Core Loop (0-30s / 5-30min / long-term) + 经济平衡   │
│ • 跨平台 Input Map (鸿蒙触控 + PC 键鼠)                │
│ • 生成标准 OpenSpec 提案 (proposal/design/tasks)       │
│ 🛑【卡点一：里程碑确认 (Approval Gate 1)】             │
└───────────────────────┬────────────────────────────────┘
                        │ 用户批准 (Approved)
                        ▼
┌────────────────────────────────────────────────────────┐
│ Stage 3: 5层依赖正向 MCP 引擎装配 (MCP Construction)   │
│ • Layer 1: Input Map 与全局 Autoload 单例              │
│ • Layer 2: 基础材质与 Mesh 3D 图元资源                 │
│ • Layer 3: 场景树层级与物理碰撞 (CollisionShape)       │
│ • Layer 4: GDScript 2.0 强类型脚本编写与绑定           │
│ • Layer 5: 主场景保存与 ProjectSettings 保存           │
└───────────────────────┬────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│ Stage 4: 自愈诊断与多模态视觉验收 (Visual QA Gate)     │
│ • run_project 启动                                     │
│ • get_editor_errors + get_output_log 自愈 (最多3轮)    │
│ • take_screenshot 截屏并通过 Vision 模型多模态核验     │
│ • stop_project                                         │
│ 🛑【卡点二：成果交付验收 (Approval Gate 2)】           │
└───────────────────────┬────────────────────────────────┘
                        │ 用户确认交付
                        ▼
┌────────────────────────────────────────────────────────┐
│ Stage 5: 归档交付与会话固化 (Archive & Checkpoint)     │
│ • 激活 openspec-archive-change 归档变更                │
│ • 激活 workspace-session-skill 保存断点会话日志        │
└────────────────────────────────────────────────────────┘
`

---

## 🏛️ 阶段细则与执行准则

### Stage 0: 探测与会话初始化 (Reconnaissance)
1. **获取事实**：调用 get_editor_state() 查看当前打开场景、根节点及运行状态。
2. **扫描文件**：调用 get_project_structure() 获取已有资产目录，避免重复生成资源。

### Stage 1: 意图分类与专家指派 (Specialist Routing)
- **A. 全新游戏开发 (New Game)**: 激活 game-designer + godot-game-gen 主控。
- **B. 系统与玩法扩展 (Feature Expansion)**: 激活 openspec-propose + godot-game-script-engineer。
- **C. 关卡与空间构建 (Level Design)**: 激活 level-design。
- **D. 视听与着色器打磨 (Juice & Shaders)**: 激活 game-audio + godot-shader-dev + game-art。
- **E. 报错自愈 (Bug Fix & Error Doctor)**: 激活 godot-error-doctor。

### Stage 2: 游戏架构设计与 OpenSpec 提案 (Architecture & GDD Design)
1. **GDD 核心要素提取**：
   - **Fun Hypothesis**：一句话定义 这游戏好玩的核心是_____。
   - **Design Pillars**：3-5 条不可妥协的玩家体验基准。
   - **三层核心循环**：
     - *瞬间循环 (0-30s)*: 操作 $\rightarrow$ 反馈 $\rightarrow$ 微奖励。
     - *单局循环 (5-30min)*: 目标 $\rightarrow$ 张力/挑战 $\rightarrow$ 结果。
     - *长期留存 (hours-weeks)*: 进阶、解锁、经济消耗。
   - **经济系统闭环**：每个产出（Source）必须有对应的消耗（Sink）。未实测数值统一标注 [PLACEHOLDER]。
   - **输入抽象**：抽象为 Input Actions（move_left, move_right, move_forward, move_back, ction_jump, ction_primary），无缝兼容鸿蒙触控虚拟按键与 PC 键鼠。
2. **产出 OpenSpec 变更**：
   - 建立 openspec/changes/<change-name>/：proposal.md, design.md, 	asks.md。
3. 🛑 **【卡点一：里程碑确认 (Approval Gate 1)】**：向用户呈现设计与任务清单，等待用户确认后再开始写代码或调 MCP。

### Stage 3: 5 层依赖正向 MCP 引擎装配 (5-Layer Forward Construction)
**核心原则**：严禁直接拼写或修改 .tscn 文本！必须按以下 5 层正向依赖顺序调用 MCP：

- **Layer 1: 输入与全局单例**
  - dd_input_action(action_name, events)
  - set_project_setting(autoload/EventBus, *res://event_bus.gd)
- **Layer 2: 基础材质与 Mesh 图元资源**
  - create_standard_material_3d(path, albedo_color, metallic, roughness)
  - create_box_mesh, create_sphere_mesh, create_cylinder_mesh, create_capsule_mesh, create_plane_mesh
- **Layer 3: 场景树与物理碰撞**
  - create_scene(path, root_type, open_in_editor=true)
  - create_node(parent_path, type, name)
  - create_collision_shape_3d(parent_path, shape_type, size)
  - create_camera_3d(parent_path, name, current=true)
  - create_light_3d(parent_path, light_type, name)
- **Layer 4: 强类型脚本编写与绑定**
  - 编写遵循 GDScript 2.0 强类型规范的代码文件（明确变量、参数、返回值类型，snake_case 强类型信号）。
  - ttach_script(node_path, script_path)
- **Layer 5: 主场景与项目保存**
  - save_scene()
  - set_project_setting(application/run/main_scene, res://main.tscn)
  - save_project_settings()

### Stage 4: 自愈诊断与多模态视觉验收 (Self-Healing & Visual QA)
1. **启动游戏**：un_project()
2. **自愈循环 (最多 3 轮)**：
   - 调用 get_editor_errors() 与 get_output_log(all, 50)。
   - 若存在编译错误或运行时异常，自动定位报错脚本、修复语法或引用，并重新热重载。
3. **视觉多模态验收**：
   - 调用 	ake_screenshot(res://screenshots/qa_verify.png)。
   - 使用模型多模态 Vision 能力直接读取图片，核验摄像机视口对齐、地面与主角是否正常着色、光影阴影及 UI 层次。
4. **停止运行**：stop_project()
5. 🛑 **【卡点二：成果交付验收 (Approval Gate 2)】**：向用户展示自愈与截图验收报告。

### Stage 5: 归档交付与会话固化 (Archive & Session Checkpoint)
1. 运行 openspec-archive-change 归档完成的特性变更。
2. 运行 workspace-session-skill 记录任务进度并提交工作日志。

---

## 🛠️ MCP 核心白名单快速索引

| 分类 | 核心可用 MCP 指令 |
|---|---|
| **场景 (Scene)** | create_scene, open_scene, save_scene, get_scene_tree, get_open_scenes |
| **节点 (Node)** | create_node, delete_node, ename_node, eparent_node, get_node, get_node_properties, set_node_property |
| **脚本 (Script)** | create_script, get_script_content, edit_script, alidate_script, ttach_script |
| **3D/材质 (Mesh/Mat)** | create_box_mesh, create_cylinder_mesh, create_sphere_mesh, create_capsule_mesh, create_plane_mesh, create_collision_shape_3d, create_camera_3d, create_light_3d, create_standard_material_3d, export_mesh_library |
| **配置 (Project)** | get_project_structure, get_project_setting, set_project_setting, save_project_settings, dd_input_action, escan_filesystem |
| **诊断 (QA/Debug)** | un_project, stop_project, get_editor_state, get_editor_errors, get_output_log, 	ake_screenshot |
