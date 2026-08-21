#!/bin/sh
# 标准化内容 hash 计算
# 用法: normalize-hash.sh <file>
# 输出: 16 位 hex SHA-256 (stdout)
#
# 标准化管道: strip BOM → CRLF→LF → trailing whitespace trim → SHA-256 → [0:16]
# 目的: 消除操作系统/编辑器编码差异，相同逻辑内容产生相同 hash
#
# 平台要求: GNU sed (支持 \x hex 转义) + sha256sum
#   - Windows (Git Bash): ✅ 内置
#   - Linux: ✅ 内置
#   - macOS: 需 brew install coreutils (gsed + gsha256sum)

file="$1"

if [ ! -f "$file" ]; then
    echo "ERROR: file not found: $file" >&2
    exit 1
fi

# 读取文件 → 标准化 → SHA-256 → 取前 16 位
# 注: \x hex 转义在 GNU sed 中可用，POSIX sed 不支持
sed '
    # Strip BOM (UTF-8 EF BB BF, UTF-16LE FF FE, UTF-16BE FE FF)
    1s/^\xEF\xBB\xBF//
    1s/^\xFF\xFE//
    1s/^\xFE\xFF//
    # CRLF → LF
    s/\r$//
    # Trailing whitespace trim per line
    s/[[:space:]]*$//
' "$file" | sha256sum | cut -c1-16
