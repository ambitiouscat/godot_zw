# === workspace-session-skill: Co-authored-by 自动追加 ===
# 以下为追加到已有 commit-msg hook 的逻辑体（无 shebang）
# 环境变量 SKIP_AI_TRAILER=1 可跳过本次追加

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
# === end workspace-session-skill ===
