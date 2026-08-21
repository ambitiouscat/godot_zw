# WORKSPACE SESSION
workspace: {{WORKSPACE_PATH}}
started: {{STARTED_TIME}}
last_update: {{LAST_UPDATE}}
status: active
task_type: {{TASK_TYPE}}

# 笔记引用
daily_note_id: {{DAILY_NOTE_ID}}
daily_note_date: {{DAILY_NOTE_DATE}}
month_dir_id: {{MONTH_DIR_ID}}
current_task_note_id: {{CURRENT_TASK_NOTE_ID}}
project_note_id: {{PROJECT_NOTE_ID}}
project_name: {{PROJECT_NAME}}
overview_note_id: {{OVERVIEW_NOTE_ID}}
plan_folder_id: {{PLAN_FOLDER_ID}}
progress_folder_id: {{PROGRESS_FOLDER_ID}}
active_phase_name: {{ACTIVE_PHASE_NAME}}
active_phase_plan_id: {{ACTIVE_PHASE_PLAN_ID}}
active_phase_progress_id: {{ACTIVE_PHASE_PROGRESS_ID}}
task_started_at: {{TASK_STARTED_AT}}
active_change_id: {{ACTIVE_CHANGE_ID}}
change_stage: {{CHANGE_STAGE}}

# 自动保存
autosave: 60m
cron_job_id: {{CRON_JOB_ID}}

---
# TASKS
- [ ] 待完成任务1
- [ ] 待完成任务2

---
# CONTEXT
决策:
- 关键决策及原因

文件:
- 相关文件引用

下一步:
1. 待执行操作

---
# LOG
## {{STARTED_TIME}} - 会话开始
初始化工作会话。

关键点:
- 开始新工作会话
