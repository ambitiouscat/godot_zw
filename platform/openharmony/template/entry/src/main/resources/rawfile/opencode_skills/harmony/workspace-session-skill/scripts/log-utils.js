/**
 * log-utils.js - 共享日志工具函数
 */

const fs = require('fs');
const path = require('path');

// 最大日志大小 (1MB)
const MAX_LOG_SIZE = 1024 * 1024;

/**
 * 获取 ISO 格式时间戳
 * @returns {string} 格式: YYYY-MM-DD HH:mm:ss
 */
function getTimestamp() {
  const now = new Date();
  return now.toISOString().replace('T', ' ').substring(0, 19);
}

/**
 * 检查并轮转日志文件
 * @param {string} logFile - 日志文件路径
 */
function rotateLogIfNeeded(logFile) {
  try {
    if (fs.existsSync(logFile)) {
      const stats = fs.statSync(logFile);
      if (stats.size > MAX_LOG_SIZE) {
        const archivePath = logFile.replace('.log', `-${Date.now()}.log`);
        try {
          fs.renameSync(logFile, archivePath);
          console.log(`Log rotated: ${archivePath}`);
        } catch (renameErr) {
          // 另一个进程可能已轮转此文件，安全忽略
          if (renameErr.code !== 'ENOENT' && renameErr.code !== 'EPERM') {
            console.warn(`Log rotation skipped: ${renameErr.message}`);
          }
        }
      }
    }
  } catch (err) {
    // 忽略轮转错误，继续记录
  }
}

/**
 * 确保日志目录存在
 * @param {string} logFile - 日志文件路径
 */
function ensureLogDir(logFile) {
  const logDir = path.dirname(logFile);
  if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
  }
}

/**
 * 获取日志文件路径
 * @param {string} workspace - 工作区路径
 * @returns {string} 日志文件路径
 */
function getLogFilePath(workspace) {
  return path.join(workspace, '.workspace-session-skill', 'conversation.log');
}

/**
 * 截断并清理文本
 * @param {string} text - 输入文本
 * @param {number} maxLength - 最大长度
 * @returns {string} 处理后的文本
 */
function truncateAndClean(text, maxLength) {
  const cleaned = text.replace(/\n/g, ' ').replace(/\s+/g, ' ').trim();
  return cleaned.length > maxLength
    ? cleaned.substring(0, maxLength) + '...'
    : cleaned;
}

module.exports = {
  getTimestamp,
  rotateLogIfNeeded,
  ensureLogDir,
  getLogFilePath,
  truncateAndClean,
  MAX_LOG_SIZE
};
