# 每日总结模板

保存时自动生成并追加到昨日任务笔记末尾。

---

## 总结内容模板

```markdown
---

## 📊 当日总结（{YYYY-MM-DD} 自动生成）

### ✅ 今日完成
- {从 TASKS 部分提取已标记 [x] 的项目}
- {从 git log 提取的提交对应任务}

### 🤖 AI 使用摘要
- Token 消耗（估算）：约 {N}k
- 使用技能：{从 conversation.log 提取的技能调用}

### 📝 Git 提交记录
- `{commit_hash}` {commit_message} ({time})
- ...

### 🔄 任务状态快照
- 进行中: {未完成的任务}
- 已完成: {已勾选的任务}
- 活跃 Change: {active_change_id} ({change_stage})

### 📋 明日计划
<!-- 用户自行填写 -->
```

## 数据来源

| 数据项 | 来源 | 获取方式 |
|--------|------|----------|
| 完成的任务 | `session.md` TASKS 部分 | `- [x]` 标记的条目 |
| Git 提交 | git log | 时间范围: daily_note_date 00:00 → 次日 00:00 |
| Token 消耗 | `conversation.log` | char_count / 4，四舍五入到千位 |
| 任务快照 | `session.md` TASKS 部分 | 所有 `- [ ]` 和 `- [x]` 条目 |
| 活跃 Change | `session.md` 头部的 `active_change_id`/`change_stage` | 由 save 步骤 5 写入 |

## 估算说明

- Token 估算公式：`估算token = round(总字符数 / 4 / 1000) * 1000`
- 标注"（估算）"而非精确值
- 若无 conversation.log，标注"无记录"

## 注意事项

- 总结追加到**昨日**任务笔记末尾（用户可能不在电脑旁）
- **不创建**新一天的每日笔记或任务笔记
- 用户 `/workspace continue` 时若检测到缺失的总结，会补生成
- 总结内容使用 markdown 格式，兼容 Trilium text 笔记
