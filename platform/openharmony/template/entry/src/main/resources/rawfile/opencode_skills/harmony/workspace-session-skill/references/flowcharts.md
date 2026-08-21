# workspace-session-skill 流程图

## 整体架构流程图

```mermaid
flowchart TB
    subgraph 用户交互层["用户交互层"]
        A1["/workspace 命令"]
        A2["自然语言触发<br/>开始工作/保存工作/继续工作"]
    end

    subgraph 命令解析["命令解析"]
        B1{解析命令类型}
        B2["start → 开始工作流"]
        B3["continue → 继续工作流"]
        B4["save → 保存工作流"]
        B5["end → 结束工作流"]
        B6["new-task → 新任务流"]
        B7["new-phase → 新阶段流"]
        B8["pull → Git拉取"]
        B9["push → Git推送"]
        B10["weekly-summary → 周报流"]
        B11["status → 状态查询"]
        B12["config → 配置查询"]
    end

    subgraph 配置层["配置管理层"]
        C1["读取 ~/.agents/skills_settings.json"]
        C2["提取 workspaceSession 配置"]
        C3{配置验证}
        C4["Trilium MCP 可用?"]
        C5["使用 Trilium"]
        C6["降级本地模式"]
        C7["同步到项目本地<br/>.workspace-session-skill/config.json"]
    end

    subgraph 存储层["存储层"]
        D1["会话文件<br/>.workspace-session-skill/session.md"]
        D2["对话日志<br/>.workspace-session-skill/conversation.log"]
        D3["Trilium 笔记"]
        D4["本地 Markdown"]
    end

    A1 --> B1
    A2 --> B1
    B1 --> B2 & B3 & B4 & B5 & B6 & B7 & B8 & B9 & B10 & B11 & B12

    B2 --> C1
    C1 --> C2 --> C3
    C3 --> C4
    C4 -->|是| C5
    C4 -->|否| C6
    C5 --> C7
    C6 --> C7

    C5 --> D3
    C6 --> D4
    D3 --> D1 & D2
    D4 --> D1 & D2
```

## 开始工作流程图

```mermaid
flowchart TB
    Start["用户: 开始工作 /workspace start"]

    subgraph 初始化阶段["初始化阶段"]
        A1["获取当前日期<br/>date '+%Y年%m月%d日 %A'"]
        A2["创建 .workspace-session-skill/ 目录"]
        A3["读取 ~/.agents/skills_settings.json"]
    end

    subgraph 配置同步["配置同步阶段"]
        B1["提取 workspaceSession 配置"]
        B2["写入 config.json 到项目目录"]
        B3["验证 Trilium 连接"]
    end

    subgraph 任务类型["任务类型选择"]
        C1["询问任务类型"]
        C2["项目任务"]
        C3["简单任务"]
    end

    subgraph 笔记创建["笔记创建阶段"]
        D1["项目任务: 创建项目笔记 (book)"]
        D2["项目任务: 创建项目概述 (text)"]
        D3["检查/创建月度目录"]
        D4["创建每日笔记<br/>YYYY年M月D日 星期X (book)"]
        D5["更新配置: current_note_id/date"]
    end

    subgraph 自动保存["自动保存设置"]
        E1["CronCreate 定时任务"]
        E2["cron: 7 * * * *"]
        E3["记录 cron_job_id"]
        E4["初始化对话日志"]
    end

    subgraph 完成["完成阶段"]
        F1["显示会话状态"]
        F2["会话激活<br/>status: active"]
    end

    Start --> A1 --> A2 --> A3
    A3 --> B1 --> B2 --> B3
    B3 --> C1
    C1 -->|"项目任务"| C2 --> D1 --> D2 --> D3 --> D4 --> D5
    C1 -->|"简单任务"| C3 --> D3 --> D4 --> D5
    D5 --> E1
    E1 --> E2 --> E3 --> E4
    E4 --> F1 --> F2
```

## 继续工作流程图

```mermaid
flowchart TB
    Start["用户: 继续工作 /workspace continue"]

    subgraph 恢复检查["恢复检查阶段"]
        A1["获取当前日期<br/>date 命令"]
        A2{会话文件存在?}
        A3["提示: 请先 start"]
        A4["读取会话文件<br/>解析 Markdown"]
    end

    subgraph 日期处理["日期处理阶段"]
        B1{日期变化?}
        B2["创建新每日笔记<br/>在当月目录最后位置"]
        B3["更新 notes_dir"]
        B4["使用现有笔记"]
        B5{有项目笔记?}
        B6["在任务笔记添加<br/>项目笔记跳转链接"]
    end

    subgraph 总结检查["每日总结检查"]
        B7{昨日笔记<br/>有每日总结?}
        B8["补生成昨日总结<br/>git log + token + 任务快照"]
        B9["追加到昨日任务笔记末尾"]
        B10["跳过（已有总结）"]
    end

    subgraph 任务验证["任务验证阶段"]
        C1["CronList 检查"]
        C2{定时任务存在?}
        C3["重新创建 Cron 任务"]
        C4["验证笔记连接"]
    end

    subgraph 状态展示["状态展示阶段"]
        D1["显示上下文恢复"]
        D2["工作目录 / 每日笔记"]
        D3["项目笔记 (如有)"]
        D4["当前任务 / 已完成"]
        D5["关键决策"]
        D6["活跃 Change: ID (阶段)"]
    end

    Start --> A1 --> A2
    A2 -->|不存在| A3
    A2 -->|存在| A4 --> B1
    B1 -->|新的一天| B2 --> B3 --> B7
    B1 -->|同一天| B4 --> B5
    B7 -->|无| B8 --> B9 --> B5
    B7 -->|有| B10 --> B5
    B5 -->|是| B6 --> C1
    B5 -->|否| C1
    C1 --> C2
    C2 -->|无| C3 --> C4
    C2 -->|有| C4
    C4 --> D1 --> D2 --> D3 --> D4 --> D5 --> D6
```

## 保存工作流程图

```mermaid
flowchart TB
    Start["用户: 保存工作 /workspace save [摘要]"]

    subgraph 状态更新["状态更新"]
        A1["更新 last_update 时间戳"]
        A2["用户摘要 → CONTEXT"]
        A3{自动摘要?}
        A4["提取关键信息<br/>话题/决策/问题/待处理"]
    end

    subgraph 变更追踪["OpenSpec 变更追踪"]
        A5["扫描 openspec/changes/"]
        A6["检测最近修改的 change"]
        A7["更新 session.md<br/>active_change_id + change_stage"]
    end

    subgraph 跨天检测["跨天检测 (--auto)"]
        B0{"--auto 模式?"}
        B0a{日期跨天?}
        B0b["生成昨日总结<br/>git log + token + 任务快照"]
        B0c["追加到昨日任务笔记末尾<br/>⚠️ 不创建新笔记"]
        B0d["跳过（未跨天）"]
    end

    subgraph 笔记同步["笔记同步"]
        B1{有项目笔记?}
        B2["更新任务笔记<br/>追加工作内容"]
        B3["更新项目笔记<br/>追加进度记录"]
        B4["仅更新任务笔记"]
    end

    subgraph 日志记录["日志记录"]
        C1["追加对话日志<br/>.workspace-session-skill/conversation.log"]
        C2["记录时间/摘要/决策"]
    end

    subgraph 完成["完成"]
        D1["显示保存成功"]
        D2["会话状态保持 active"]
    end

    Start --> A1 --> A2 --> A3
    A3 -->|有摘要| A4
    A3 -->|无摘要| A5
    A4 --> A5
    A5 --> A6 --> A7
    A7 --> B0
    B0 -->|是| B0a
    B0 -->|否| B1
    B0a -->|是| B0b --> B0c --> B1
    B0a -->|否| B0d --> B1
    B1 -->|是| B2 --> B3 --> C1
    B1 -->|否| B4 --> C1
    C1 --> C2 --> D1 --> D2
```

## 结束工作流程图

```mermaid
flowchart TB
    Start["用户: 结束工作 /workspace end"]

    subgraph 最终保存["最终保存"]
        A1["执行保存工作流"]
        A2["更新最后状态"]
    end

    subgraph 清理阶段["清理阶段"]
        B1["CronDelete 定时任务"]
        B2["删除 cron_job_id"]
        B3["状态改为 completed"]
    end

    subgraph 归档选项["归档选项"]
        C1{询问归档方式}
        C2["保留（默认）<br/>会话文件保持"]
        C3["归档<br/>移动到 archive/（数据完整保留）"]
        C4["⚠️ 删除<br/>需二次确认"]
        C5{用户确认删除?}
        C6["拒绝删除<br/>自动改为保留"]
        C7["确认删除<br/>清除会话文件"]
    end

    subgraph 完成["完成"]
        D1["显示结束总结"]
        D2["会话结束"]
    end

    Start --> A1 --> A2 --> B1 --> B2 --> B3 --> C1
    C1 -->|"保留（默认）"| C2 --> D1
    C1 -->|"归档"| C3 --> D1
    C1 -->|"删除"| C4 --> C5
    C5 -->|"模糊回答/拒绝"| C6 --> D1
    C5 -->|"明确确认"| C7 --> D1
    D1 --> D2
```

## 项目笔记流程图

```mermaid
flowchart TB
    Start["用户选择: 项目任务"]

    subgraph 检查配置["检查配置"]
        A1{"project_notes.root<br/>已配置?"}
        A2["提示: 配置后继续<br/>或改为简单任务"]
    end

    subgraph 创建项目["创建项目笔记"]
        B1["询问项目名称"]
        B2["在 project_notes.root 下<br/>创建项目集合 (book)"]
        B3["创建项目概述子笔记 (text)"]
        B4["包含'相关笔记引用'部分"]
    end

    subgraph 创建每日["创建每日笔记"]
        C1["检查/创建月度目录"]
        C2["创建每日笔记 (book)"]
        C3["更新配置<br/>current_note_id/date"]
    end

    subgraph 更新会话["更新会话"]
        D1["写入 session.md<br/>task_type=project"]
        D2["记录 project_note_id"]
    end

    Start --> A1
    A1 -->|"未配置"| A2
    A1 -->|"已配置"| B1 --> B2 --> B3 --> B4
    B4 --> C1 --> C2 --> C3 --> D1 --> D2
```

## 新任务流程图

```mermaid
flowchart TB
    Start["用户: 新任务 /workspace new-task [名称]"]

    subgraph 创建任务["创建任务笔记"]
        A1["获取每日笔记 ID"]
        A2["创建任务笔记 (text)<br/>命名: 任务名-进行中"]
        A3{有项目笔记?}
        A4["添加双向引用"]
        A5["无引用直接记录"]
    end

    subgraph 更新会话["更新会话"]
        B1["追加到 tasks 列表"]
        B2["记录创建时间"]
    end

    subgraph 完成["完成"]
        C1["显示任务创建成功"]
        C2["任务笔记 ID"]
    end

    Start --> A1 --> A2 --> A3
    A3 -->|是| A4 --> B1
    A3 -->|否| A5 --> B1
    B1 --> B2 --> C1 --> C2
```

## 周报总结流程图

```mermaid
flowchart TB
    Start["用户: 周报总结 /workspace weekly-summary [周次]"]

    subgraph 日期解析["日期解析"]
        A1["解析 ISO 周参数"]
        A2["计算周一至周日日期范围"]
        A3{"参数有效?"}
        A4["提示错误，建议格式"]
    end

    subgraph 数据采集["数据采集"]
        B1["搜索本周每日笔记<br/>Trilium search_notes"]
        B2["读取笔记内容<br/>提取任务和状态"]
        B3{"Trilium 可用?"}
        B4["降级: 读取本地<br/>.workspace-session-skill/"]
        B5["扫描 openspec/changes/"]
        B6["读取 proposal.md 摘要"]
    end

    subgraph 生成输出["生成输出"]
        C1{"本周有活动?"}
        C2["按 assets/weekly-summary-template.txt 格式<br/>每项一行精炼输出"]
        C3["输出 "本周无活动记录""]
    end

    Start --> A1 --> A2 --> A3
    A3 -->|无效| A4
    A3 -->|有效| B1 --> B3
    B3 -->|否| B4 --> B5
    B3 -->|是| B2 --> B5
    B5 --> B6 --> C1
    C1 -->|有| C2
    C1 -->|无| C3
```

## Trilium 笔记层级结构图

```mermaid
flowchart TB
    subgraph 每日事务["每日事务 (daily_notes.root)"]
        M1["26年三月份 (book)"]
        M2["26年四月份 (book)"]

        subgraph 三月["26年三月份"]
            D1["2026年3月19日 星期四 (book)"]
            D2["2026年3月20日 星期五 (book)"]
            D3["2026年3月23日 星期日 (book)<br/>位置: 最后"]

            subgraph 19日["19日任务"]
                T1["推流插件编译-完成 (text)"]
            end

            subgraph 20日["20日任务"]
                T2["VTK伪装Godot-开始 (text)"]
                T3["VTK伪装Godot-完成 (text)"]
            end

            subgraph 23日["23日任务"]
                T4["推流插件测试-部署测试准备中 (text)"]
            end
        end

        D1 --> T1
        D2 --> T2 & T3
        D3 --> T4
    end

    subgraph 项目笔记["项目笔记 (project_notes.root)"]
        P1["完整问题处理记录-项目"]

        subgraph VTK项目["VTK伪装Godot (book)"]
            P2["项目概述 (text)<br/>含相关笔记引用"]
            P3["迁移结果 (text)"]
            P4["关键决策 (text)"]

            P2 -->|"链接"| T2 & T3
        end
    end

    M1 --> D1 & D2 & D3
    P1 --> VTK项目
```

## 双向引用机制图

```mermaid
flowchart LR
    subgraph 任务笔记["任务笔记 (text)"]
        A1["开头部分"]
        A2["↓"]
        A3["<a href='#root/.../项目ID'><br/>[→ 项目笔记: VTK伪装Godot]</a>"]
        A4["↓"]
        A5["工作内容记录"]
    end

    subgraph 项目概述["项目概述 (text)"]
        B1["项目描述"]
        B2["↓"]
        B3["相关笔记引用"]
        B4["↓"]
        B5["<a href='#root/.../任务ID'><br/>[2026年3月20日 VTK伪装Godot-开始]</a>"]
        B6["<a href='#root/.../任务ID'><br/>[2026年3月20日 VTK伪装Godot-完成]</a>"]
    end

    A3 -->|"跳转"| B1
    B5 & B6 -->|"跳转"| A1
```

## 数据流向图

```mermaid
flowchart TB
    subgraph 输入["用户输入"]
        I1["命令/自然语言"]
    end

    subgraph 处理["技能处理"]
        P1["命令解析"]
        P2["配置读取"]
        P3["状态管理"]
        P4["笔记操作"]
    end

    subgraph 本地存储["本地存储"]
        L1[".workspace-session-skill/session.md<br/>会话状态 Markdown"]
        L2[".workspace-session-skill/conversation.log<br/>对话日志"]
        L3["notes/*.md<br/>本地笔记(降级)"]
    end

    subgraph Trilium["Trilium MCP"]
        T1["create_note()"]
        T2["write_note()"]
        T3["write_note(mode=\"append\")"]
        T4["search_notes()"]
        T5["每日笔记 book"]
        T6["任务笔记 text"]
        T7["项目笔记 book"]
    end

    subgraph 自动保存["自动保存"]
        A1["CronCreate"]
        A2["每60分钟触发"]
        A3{"有新对话?<br/>检查日志修改时间"}
        A4["更新 last_update"]
        A5["跳过（无新内容）"]
    end

    I1 --> P1 --> P2 --> P3 --> P4
    P4 --> L1 & L2
    P4 --> T1 & T2 & T3 & T4
    T1 --> T5 & T6 & T7

    P3 --> A1 --> A2 --> A3
    A3 -->|"是"| A4 --> L1
    A3 -->|"否"| A5
```

---

## 拉取远端流程图

```mermaid
flowchart TB
    Start["用户: 拉取 /workspace pull"]

    subgraph 拉取["Git 拉取"]
        A1["执行 sync_remote.sh pull"]
        A2["git pull --rebase"]
        A3{有冲突?}
        A4["conversation.log<br/>merge=union 自动合并"]
        A5["告知用户冲突文件<br/>不阻断流程"]
        A6["拉取成功<br/>工作区数据已更新"]
    end

    subgraph 降级["降级处理"]
        B1{脚本存在?}
        B2["静默跳过<br/>无远端或无网络"]
    end

    Start --> B1
    B1 -->|否| B2
    B1 -->|是| A1 --> A2 --> A3
    A3 -->|无冲突| A6
    A3 -->|有冲突| A4 --> A5
```

## 推送远端流程图

```mermaid
flowchart TB
    Start["用户: 推送 /workspace push"]

    subgraph 推送["Git 推送"]
        A1["执行 sync_remote.sh push"]
        A2{本地有多个<br/>未推送提交?}
        A3["squash 为一个提交<br/>sync: YYYY-MM-DD HH:mm"]
        A4["直接 git push"]
        A5["推送成功"]
    end

    Start --> A1 --> A2
    A2 -->|多个| A3 --> A4 --> A5
    A2 -->|单个| A4
```

## 新阶段流程图

```mermaid
flowchart TB
    Start["用户: 新阶段 /workspace new-phase N 名称"]

    subgraph 验证["前置验证"]
        A1{task_type=project?}
        A2["提示: 仅项目任务可用"]
        A3["检查 plan/progress 文件夹"]
    end

    subgraph 创建["创建阶段笔记"]
        B1["创建阶段计划笔记<br/>Phase N: 阶段名"]
        B2["创建阶段进度笔记<br/>Phase N 实施-进行中"]
        B3["构建双向链接"]
        B4["更新项目概述阶段表格"]
    end

    subgraph 完成["完成"]
        C1["更新 session.md + config.json"]
        C2["active_phase 已设置"]
    end

    Start --> A1
    A1 -->|否| A2
    A1 -->|是| A3 --> B1 --> B2 --> B3 --> B4
    B4 --> C1 --> C2
```

---

## 快速参考

| 流程 | 核心操作 | 输出 |
|------|----------|------|
| 开始工作 | 询问任务类型+创建笔记+Cron | status: active |
| 继续工作 | 检查日期+恢复上下文 | 显示状态 |
| 保存工作 | 更新时间戳+笔记内容 | 记录日志 |
| 结束工作 | 清理Cron+归档（默认保留） | status: completed |
| 新任务 | 创建任务笔记+双向引用 | 任务ID |
| 新阶段 | 创建计划+进度笔记+表格更新 | active_phase 已设置 |
| 拉取 | sync_remote.sh pull → git pull --rebase | 工作区数据已同步 |
| 推送 | sync_remote.sh push → squash + push | 推送完成 |
| 项目任务 | 创建项目集合+概述+每日笔记 | project_note_id |