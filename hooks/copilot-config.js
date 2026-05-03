#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const VALID_MODES = ['on', 'off'];
const MAX_FLAG_BYTES = 64;
const MAX_LOG_BYTES = 64 * 1024;
const FLAG_NAME = '.options-mode-active';
const LOG_NAME = 'options-mode.log';
const OPTIONS_NO_QUESTION_TAG = '<options-mode>no-question</options-mode>';

const OPTIONS_RULES_FOR_COPILOT = [
  'OPTIONS MODE ACTIVE.',
  '',
  'When you need the user to make a decision or answer a question, end your turn with an ask_user tool call instead of plain prose. Never leave the user with no choices to pick from when you are asking for input.',
  'Pass concrete arguments to ask_user:',
  '  - question: the actual question.',
  '  - choices: 2-4 short, mutually exclusive labels the user can reasonably pick from.',
  '  - allow_freeform: false unless the available choices may not cover the user intent.',
  'Prefix the strongest choice with "Recommended: " when one option is clearly best, so it sits first in the list.',
  `When you are not asking the user for input and are returning plain prose, append ${OPTIONS_NO_QUESTION_TAG} as the final line of your response. This tag asserts the turn is not a question and should not be converted into an ask_user prompt.`,
  'If options mode is off, do not enforce ask_user choice prompts.',
  '',
  `Canonical anchors: OPTIONS MODE ACTIVE; ask_user; choices; Recommended; ${OPTIONS_NO_QUESTION_TAG}.`
].join('\n');

function getConfigRoot() {
  return process.env.COPILOT_CONFIG_DIR || path.join(os.homedir(), '.copilot');
}

function getFlagPath() {
  return path.join(getConfigRoot(), FLAG_NAME);
}

function _readFlagInternal(flagPath) {
  let st;
  try {
    st = fs.lstatSync(flagPath);
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
  if (st.isSymbolicLink() || !st.isFile()) return null;
  if (st.size > MAX_FLAG_BYTES) return null;

  const O_NOFOLLOW = typeof fs.constants.O_NOFOLLOW === 'number' ? fs.constants.O_NOFOLLOW : 0;
  const flags = fs.constants.O_RDONLY | O_NOFOLLOW;
  let fd;
  let out;
  try {
    fd = fs.openSync(flagPath, flags);
    const buf = Buffer.alloc(MAX_FLAG_BYTES);
    const n = fs.readSync(fd, buf, 0, MAX_FLAG_BYTES, 0);
    out = buf.slice(0, n).toString('utf8');
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }

  const raw = out.trim().toLowerCase();
  if (!VALID_MODES.includes(raw)) return null;
  return raw;
}

function readFlag() {
  try {
    return _readFlagInternal(getFlagPath());
  } catch (e) {
    return null;
  }
}

function isOptionsActive() {
  return readFlag() === 'on';
}

function safeWriteFlag(content) {
  try {
    const flagPath = getFlagPath();
    const flagDir = path.dirname(flagPath);
    fs.mkdirSync(flagDir, { recursive: true });

    try {
      if (fs.lstatSync(flagDir).isSymbolicLink()) return;
    } catch (e) {
      return;
    }

    try {
      if (fs.lstatSync(flagPath).isSymbolicLink()) return;
    } catch (e) {
      if (e.code !== 'ENOENT') return;
    }

    const tempPath = path.join(flagDir, `.options-mode-active.${process.pid}.${Date.now()}`);
    const O_NOFOLLOW = typeof fs.constants.O_NOFOLLOW === 'number' ? fs.constants.O_NOFOLLOW : 0;
    const flags = fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | O_NOFOLLOW;
    let fd;
    try {
      fd = fs.openSync(tempPath, flags, 0o600);
      fs.writeSync(fd, String(content));
      try { fs.fchmodSync(fd, 0o600); } catch (e) {}
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
    }
    try {
      fs.renameSync(tempPath, flagPath);
    } catch (renameErr) {
      if (renameErr && (renameErr.code === 'EEXIST' || renameErr.code === 'EBUSY' || renameErr.code === 'EACCES')) {
        appendLog(`WARN safeWriteFlag rename failed code=${renameErr.code} path=${flagPath}`);
      }
      try { fs.unlinkSync(tempPath); } catch (e) {}
    }
  } catch (e) {}
}

function appendLog(line) {
  try {
    const logPath = path.join(getConfigRoot(), LOG_NAME);
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    try {
      const st = fs.statSync(logPath);
      if (st.size >= MAX_LOG_BYTES) {
        try { fs.unlinkSync(`${logPath}.1`); } catch (e) {}
        fs.renameSync(logPath, `${logPath}.1`);
      }
    } catch (e) {}
    fs.appendFileSync(logPath, line.replace(/[\r\n]+/g, ' ') + '\n');
  } catch (e) {}
}

function readStdinJson() {
  try {
    const raw = fs.readFileSync(0, 'utf8');
    if (!raw) return {};
    return JSON.parse(raw);
  } catch (e) {
    return {};
  }
}

module.exports = {
  OPTIONS_NO_QUESTION_TAG,
  OPTIONS_RULES_FOR_COPILOT,
  VALID_MODES,
  FLAG_NAME,
  getConfigRoot,
  getFlagPath,
  readFlag,
  isOptionsActive,
  safeWriteFlag,
  appendLog,
  readStdinJson
};
