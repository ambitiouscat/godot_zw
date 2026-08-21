#!/bin/sh
# Git commit-msg hook — 自动追加 AI 协作标记
# 由 workspace-session-skill 自动部署
# 安装路径: <project>/.git/hooks/commit-msg
#
# 跳过机制: 设置环境变量 SKIP_AI_TRAILER=1 可跳过本次追加
#   git commit -m "..."  →  自动追加 Co-authored-by
#   SKIP_AI_TRAILER=1 git commit -m "..."  →  不追加

COMMIT_MSG_FILE="$1"
TRAILER="Co-authored-by: Sisyphus <sisyphus@ai>"

# 环境变量跳过
if [ "$SKIP_AI_TRAILER" = "1" ]; then
    exit 0
fi

# 如果已有 Sisyphus 标记，跳过
if grep -q "Co-authored-by: Sisyphus" "$COMMIT_MSG_FILE"; then
    exit 0
fi

# 在文件末尾追加空行 + trailer
printf "\n%s\n" "$TRAILER" >> "$COMMIT_MSG_FILE"
