# Godot Engine 4.7 for HarmonyOS NEXT (GDAI-4.7)

<p align="center">
  <img src="misc/logo/logo_outlined.svg" width="280" alt="Godot Engine logo">
</p>

本项目是 **Godot Engine 4.7**（4.7.2-rc / C++20）针对 **华为 HarmonyOS NEXT**（API 12+）的深度移植与全功能运行版本，并在 Godot 编辑器内嵌了 **OpenCode 原生 AI 编码助手**。

> [!IMPORTANT]
> - **核心开发分支**：`GDAI-4.7`（所有新功能开发、修复与编译必须在此分支进行）。
> - **运行形态**：Godot 原生全屏渲染（OpenGL ES 3.2 / Vulkan, Maleoon 916 GPU），OpenCode 作为 **原生 EditorDock 页签** 嵌入在编辑器右侧属性栏（Inspector / Signals / Groups / OpenCode）中。

---

## 目录

- [一、 项目核心特性与架构](#一-项目核心特性与架构)
- [二、 关键目录与代码结构](#二-关键目录与代码结构)
- [三、 编译与开发环境准备 (在新机器上配置)](#三-编译与开发环境准备-在新机器上配置)
- [四、 一键编译、打包与真机部署](#四-一键编译打包与真机部署)
- [五、 真机运行与命令调测](#五-真机运行与命令调测)
- [六、 OpenCode AI 助手架构与通信规范](#六-opencode-ai-助手架构与通信规范)
- [七、 AI 协作与二次开发守则](#七-ai-协作与二次开发守则)

---

## 一、 项目核心特性与架构

```
+-------------------------------------------------------------------------+
|                  HarmonyOS NEXT Host (MateBook / Tablet / Phone)        |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  |  Godot 4.7 Editor (C++20 Engine Core)                             |  |
|  |                                                                   |  |
|  |  +---------------------+  +-----------------+  +---------------+  |  |
|  |  | 场景树 / 文件系统   |  | 3D/2D Viewport  |  | 右侧面板 Dock |  |  |
|  |  | (SceneTree / Files) |  | (XComponent GLES|  | [属性|节点|AI] |  |  |
|  |  +---------------------+  +-----------------+  +-------+-------+  |  |
|  |                                                        |          |  |
|  |  +-----------------------------------------------------+          |  |
|  |  | OpenCodeDock (Native EditorDock / Right Panel Tab)             |  |
|  |  | - AI 模型选择 (DeepSeek / Claude 3.5 / GPT-4o / Qwen 2.5)       |  |
|  |  | - 上下文抓取 (自动读取当前活动脚本、选中节点层级与场景)        |  |
|  |  | - 异步网络 (HTTPRequest ↔ 127.0.0.1:4096 Loopback 通信)        |  |
|  |  +-----------------------------------------------------+          |  |
|  +-------------------------------------------------------------------+  |
|                                     ↕ IPC Loopback / NAPI               |
|  +-------------------------------------------------------------------+  |
|  |  Native Child Process (libopencode_formal_runtime.so)              |  |
|  |  - Node.js 运行时环境 (libnode.so.137)                            |  |
|  |  - OpenCode 离线运行沙箱与资产包 (20.73 MB, AGENTS.md, Manifests) |  |
|  +-------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

1. **纯原生 Godot 4.7.2 核心**：
   - 采用标准 Godot 4.7 引擎架构，支持完整 2D/3D 编辑器与桌面级交互体验。
   - 适配 HarmonyOS NEXT 渲染底座（`DisplayServerOpenHarmony`、`OS_OpenHarmony`、XComponent Surface、多点触控与键鼠映射）。
2. **原生 EditorDock 右侧属性页签**：
   - 摒弃游离外部的悬浮球或 ArkUI 抽屉，AI 助手作为标准 `EditorDock`（槽位 `DOCK_SLOT_RIGHT_UL`）直接融入 Godot 编辑器布局。
3. **独立子进程 (NCP) OpenCode 后端**：
   - 将 `libnode.so.137` 隔离在独立 Native 子进程中执行，彻底杜绝 JIT 约束、libuv 符号冲突及内存泄漏问题。
4. **工业级一键自动化流水线**：
   - `scripts/build.ps1` 串联了 SCons 多核交叉编译、CMake 符号隔离、资产同步、DevEco CLI 打包签名以及 `hdc` 自动化推送。

---

## 二、 关键目录与代码结构

```text
godot_zw/
├── editor/
│   ├── docks/
│   │   ├── opencode_dock.h          # OpenCode AI 原生 Dock 头文件
│   │   ├── opencode_dock.cpp        # OpenCode AI UI、上下文读取与 HTTP 交互实现
│   │   └── ...                      # 其它原生 Dock (Inspector, Signals, Groups)
│   └── editor_node.cpp              # 注册 OpenCodeDock 并注入 dock_5 默认布局
├── platform/
│   └── openharmony/                 # 鸿蒙平台底层适配 (OS, DisplayServer, Audio, KeyCodes)
│       └── template/entry/          # DevEco Studio 标准应用工程
│           ├── src/main/cpp/
│           │   ├── CMakeLists.txt   # NDK CMake 配置 (严格隔离 Node 头文件)
│           │   ├── napi_init.cpp    # Godot 引擎主 NAPI 入口
│           │   └── opencode/        # NCP 跨进程桥接与 Node 嵌入实现
│           ├── src/main/ets/        # ArkTS 前端 Ability 与窗口管理
│           └── src/main/resources/
│               └── rawfile/         # 打包进 HAP 的 OpenCode 离线资产与模板
├── scripts/
│   ├── build.ps1                    # 【核心】Windows PowerShell 一键编译、打包与部署脚本
│   ├── build.sh                     # Linux/macOS Shell 构建脚本
│   └── package-opencode-assets.mjs  # OpenCode 离线资产打包流水线
└── SConstruct                       # Godot 顶级 SCons 构建脚本
```

---

## 三、 编译与开发环境准备 (在新机器上配置)

在另一台全新机器上开始开发时，请确保满足以下依赖：

### 1. 软件环境
| 工具 | 推荐版本 | 说明 |
|------|---------|------|
| **操作系统** | Windows 10 / 11 64-bit | 推荐使用 PowerShell 7+ 或 Windows Terminal |
| **DevEco Studio** | 5.0 Release 或更高 | 内置 OpenHarmony SDK (API 12+)、Node.js、hvigorw |
| **Python** | 3.10 ~ 3.12 | 必须安装 SCons: `pip install scons` |
| **Git** | 2.40+ | 开启长路径支持: `git config --global core.longpaths true` |
| **hdc 命令行工具** | 随 DevEco 安装 | 确保 `hdc` 在系统环境变量 `PATH` 中 |

### 2. 环境变量检查
- 检查 `OPENHARMONY_SDK_PATH`：
  - 默认探测路径为 `D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony` 或 `C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony`。
  - 若安装在其他自定义路径，可在终端设置：
    ```powershell
    $env:OPENHARMONY_SDK_PATH = "你的DevEco安装目录/sdk/default/openharmony"
    ```
- 确保 `devecocli` 或 `hvigorw` 所在路径可被识别。

### 3. 克隆代码与检出分支
```powershell
git clone https://github.com/ambitiouscat/godot_zw.git
cd godot_zw
git checkout GDAI-4.7
```

---

## 四、 一键编译、打包与真机部署

项目根目录提供了功能完备的自动化脚本 [`scripts/build.ps1`](file:///E:/ai-work-E/project/harmonysos-godot/godot_zw/scripts/build.ps1)。

### 常用构建命令示例

```powershell
# 1. 完整全量构建：编译 libgodot.so + 打包签名 HAP + 自动推送到真机
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Profile release-debug -Package -Install

# 2. 仅重新打包并安装 HAP（当只修改了 ArkTS / C++ NAPI 桥接层，且未修改 Godot 引擎源码时）：
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -SkipEngine -Package -Install

# 3. 指定编译线程数（如 8 核机器）：
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Jobs 8 -Package -Install

# 4. 发布版本 (Release) 优化构建：
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Profile release -Package -Install
```

### 参数字典

| 参数 | 可选值 | 默认值 | 说明 |
|------|--------|--------|------|
| `-Profile` | `release-debug`, `release`, `debug` | `release-debug` | 编译优化与调试配置 |
| `-Target` | `editor`, `template_debug`, `template_release` | `editor` | 构建目标：编辑器或游戏导出模板 |
| `-Jobs` | 整数 (如 8, 16, 32) | `16` | SCons 多核并发编译线程数 |
| `-SkipEngine` | 开关 (`$true`/`$false`) | `$false` | 跳过 SCons 编译，直接打包 HAP |
| `-Package` | 开关 (`$true`/`$false`) | `$false` | 调用 DevEco CLI 打包生成签名 HAP |
| `-Install` | 开关 (`$true`/`$false`) | `$false` | 编译后通过 `hdc install -r` 一键安装到真机 |

---

## 五、 真机运行与命令调测

安装成功后，可以通过 `hdc` 命令行直接拉起对应 Ability：

### 1. 启动项目管理器 (ProjectManager)
```powershell
hdc shell aa start -a ProjectManagerAbility -b org.xiyue999.gdai
```

### 2. 直接以指定项目启动编辑器 (EditorAbility)
```powershell
hdc shell "aa start -a EditorAbility -b org.xiyue999.gdai --ps projectPath '/data/storage/el2/base/files/test_project' --ps godotMode 'editor'"
```

### 3. 查看实时引擎与 AI 交互日志
```powershell
# 查看 Godot 引擎渲染与逻辑日志
hdc shell "hilog -x" | Select-String "LIB_GODOT"

# 查看 OpenCode 跨进程服务日志
hdc shell "hilog -x" | Select-String "OpenCodeFormalRuntime"
```

---

## 六、 OpenCode AI 助手架构与通信规范

1. **UI 承载位置**：
   - 位于右侧属性栏 Tab 组 (`dock_5`)，与 **属性 (Inspector)**、**节点 (Signals/Groups)** 并列。
2. **上下文感知能力**：
   - **附加当前脚本**：通过 `ScriptEditor::get_singleton()->get_current_editor()` 实时抓取正在编辑的 GDScript 路径及全文代码。
   - **附加选中节点**：通过 `EditorSelection` 提取场景树中选中的节点名称、类型与绝对路径。
3. **通信交互链路**：
   - 前端 UI 使用 Godot `HTTPRequest` 异步向本地 loopback 发送 JSON：
     ```json
     {
       "prompt": "请帮我重构这个角色的跳跃逻辑...",
       "model": "deepseek-v3"
     }
     ```
   - 子进程中的 OpenCode Runtime 完成推理与 Tool Calls，返回结构化数据并由 `RichTextLabel` 实时渲染。

---

## 七、 AI 协作与二次开发守则

给后续接手的 AI 助手或开发者的重要备忘：

1. **坚持 Godot 原生 Dock 模式**：
   - 严禁在 ArkUI 层面堆叠覆盖式悬浮窗、抽屉或全屏拦截层。任何 AI 相关的功能增强（例如 Diff 对比、代码补全建议、可视化工作流）都应当在 `editor/docks/opencode_dock.cpp` 或通过 Godot 插件标准接口（`EditorPlugin`）实现。
2. **严格防护 NDK 头文件污染**：
   - OpenHarmony SDK 自带一套 `napi/native_api.h`，Node.js 也有自带的 `node_api.h` / `js_native_api.h`。在 CMakeLists.txt 中，Node 的包含路径必须仅赋给 `formal_node_embedder.cpp`，切勿置于全局 `include_directories` 中。
3. **保持 GDAI-4.7 分支整洁**：
   - 提交前先验证 SCons 与 DevEco 打包完整通过。
   - 保持 Commit 记录语义清晰（如 `feat: ...`, `fix: ...`）。
