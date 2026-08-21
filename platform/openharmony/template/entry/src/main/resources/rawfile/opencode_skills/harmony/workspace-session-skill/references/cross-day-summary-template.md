# Cross-Day Summary Template

This template is used by auto-save when detecting a day change (after 00:00).

## Usage

When `daily_note_date` differs from current date:
1. Generate summary for `daily_note_date`
2. Append to `conversation.log`
3. Update `daily_note_date` to current date
4. Delete cron job (if configured)

## Template Structure

```markdown
## 📊 跨日总结 — {date}

### ✅ 完成工作
{List of completed tasks with brief descriptions}

### 🔄 进行中
{List of ongoing tasks with current status}

### 📝 Git 提交
{List of commits with hash and message}

### 💬 对话记录
- Codex: {count} 条消息
- Claude: {count} 条消息
- Token 消耗: ~{estimate}k tokens

### 🎯 明日计划
{Next steps and priorities}
```

## Example

```markdown
## 📊 跨日总结 — 2026-07-21

### ✅ 完成工作
- 实现模型目录缓存刷新机制
- 修复 fetch 初始化兼容性问题
- 添加请求边界控制

### 🔄 进行中
- 模型目录全量同步优化
- 错误重试机制完善

### 📝 Git 提交
- i3d544: 636b11a2 fix(opencode): package bounded catalog refresh (11:32)
- i3d544: d405f9a2 fix(opencode): initialize compatible fetch before catalog (15:20)
- i3d544: 884c1ea3 fix(opencode): package catalog refresh reconciliation (16:50)
- h5-ui: e554b2a fix(opencode): bound catalog refresh requests (11:32)

### 💬 对话记录
- Codex: 27 条消息
- Claude: 42 条消息
- Token 消耗: ~250k tokens

### 🎯 明日计划
- 继续优化模型目录同步性能
- 解决重试按钮状态显示问题
```
