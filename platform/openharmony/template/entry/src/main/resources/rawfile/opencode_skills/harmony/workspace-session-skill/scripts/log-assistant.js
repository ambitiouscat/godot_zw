#!/usr/bin/env node
/**
 * log-assistant.js - 记录助手回复摘要到对话日志（跨平台）
 * 用于 Stop hook，从 stdin 读取回复内容
 */

const fs = require('fs');
const { getTimestamp, rotateLogIfNeeded, ensureLogDir, getLogFilePath, truncateAndClean } = require('./log-utils');

const workspace = process.env.CLAUDE_WORKSPACE || process.env.WORKSPACE_FOLDER || '.';
const logFile = getLogFilePath(workspace);

// 最大摘要长度
const MAX_SUMMARY_LENGTH = 200;

async function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);

    // 超时保护
    setTimeout(() => {
      if (data) {
        console.warn('stdin read timeout, partial data captured');
      }
      resolve(data);
    }, 5000);
  });
}

async function main() {
  try {
    // 从 stdin 读取回复
    const reply = await readStdin();

    // 跳过空内容
    if (!reply || !reply.trim()) {
      return;
    }

    // 跳过 session 元数据 JSON — 不是有效的工作摘要
    const trimmed = reply.trim();
    if (trimmed.startsWith('{"session_id"') || trimmed.startsWith('{ "session_id"')) {
      return;
    }

    const summary = truncateAndClean(reply, MAX_SUMMARY_LENGTH);

    // 跳过纯空白或无意义内容
    if (!summary || summary.length < 5) {
      return;
    }

    // 确保目录存在
    ensureLogDir(logFile);

    // 检查日志大小并轮转
    rotateLogIfNeeded(logFile);

    // 记录助手回复摘要（使用 [SYSTEM] 标签，格式与 save --auto 对齐）
    const timestamp = getTimestamp();
    const entry = `[${timestamp}] [SYSTEM] ${summary}\n`;
    fs.appendFileSync(logFile, entry, 'utf8');
  } catch (err) {
    console.error('Failed to log assistant reply:', err.message);
  }
}

main();
