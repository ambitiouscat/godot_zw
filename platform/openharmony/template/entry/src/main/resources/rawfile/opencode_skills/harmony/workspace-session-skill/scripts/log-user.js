#!/usr/bin/env node
/**
 * log-user.js - 记录用户输入到对话日志（跨平台）
 * 用于 UserPromptSubmit hook
 */

const fs = require('fs');
const { getTimestamp, rotateLogIfNeeded, ensureLogDir, getLogFilePath, truncateAndClean } = require('./log-utils');

const workspace = process.env.CLAUDE_WORKSPACE || process.env.WORKSPACE_FOLDER || '.';
const logFile = getLogFilePath(workspace);
const prompt = process.env.CLAUDE_PROMPT || '';

function main() {
  try {
    // 确保目录存在
    ensureLogDir(logFile);

    // 跳过空 prompt — 不写无效日志行
    if (!prompt || !prompt.trim()) {
      return;
    }

    // 检查日志大小并轮转
    rotateLogIfNeeded(logFile);

    // 记录用户输入摘要（单行，截断过长内容）
    const timestamp = getTimestamp();
    const summary = truncateAndClean(prompt, 200);
    const entry = `[${timestamp}] [USER] ${summary}\n`;
    fs.appendFileSync(logFile, entry, 'utf8');
  } catch (err) {
    console.error('Failed to log user input:', err.message);
  }
}

main();
