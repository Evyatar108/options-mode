#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const VALID_MODES = ['on', 'off', 'strict'];
const MAX_FLAG_BYTES = 64;
const MAX_LOG_BYTES = 64 * 1024;
const FLAG_NAME = '.options-mode-active';
const LOG_NAME = 'options-mode.log';
// Copilot uses a CommonMark reference-link comment idiom so that markdown
// renderers strip it from the rendered output. The previous `<!--...-->` HTML
// comment form (v0.13.0) was passed through verbatim by Copilot CLI's renderer
// and was visible to the user. Claude Code keeps the bare
// `<options-mode>...</options-mode>` form because its renderer already strips the
// unknown XML wrapper. Both forms are independent across surfaces — see
// hooks/config.js::OPTIONS_NO_QUESTION_TAG for the Claude Code value.
//
// The reference-link form parses as a link reference definition with label `//`,
// URL `#`, and `(options-mode-no-question)` as the title. CommonMark renderers do
// not emit text for link reference definitions, so the line is hidden. Must be
// emitted on its own line at block level for the parse to succeed.
const OPTIONS_NO_QUESTION_TAG = '[//]: # (options-mode-no-question)';
const OPTIONS_BACKGROUND_TASK_TAG = '[//]: # (options-mode-background-task)';
const OPTIONS_BACKGROUND_AGENT_TAG = '[//]: # (options-mode-background-agent)';

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
  `Do NOT append ${OPTIONS_NO_QUESTION_TAG} when your turn ends with a question to the user (last sentence ending with "?", or imperative asks like "Want me to...", "Should I...", "Let me know..."). Call ask_user with concrete choices instead.`,
  'If options mode is off, do not enforce ask_user choice prompts.',
  '',
  `Canonical anchors: OPTIONS MODE ACTIVE; ask_user; choices; Recommended; ${OPTIONS_NO_QUESTION_TAG}.`
].join('\n');

const OPTIONS_RULES_FOR_COPILOT_STRICT = [
  'OPTIONS MODE ACTIVE (strict).',
  '',
  'Every turn MUST end with one of three states: an ask_user tool call, the background-task tag, or the background-agent tag. Plain prose without one of those three is forbidden in strict mode and will be blocked.',
  'When you need the user to make a decision or answer a question, end your turn with an ask_user tool call instead of plain prose. Never leave the user with no choices to pick from when you are asking for input.',
  'Pass concrete arguments to ask_user. STRICT MODE RULES (override the on-mode defaults):',
  '  - question: the actual question.',
  '  - choices: REQUIRED, 2-4 short, mutually exclusive labels. ALWAYS populate this — never call ask_user without choices, even for an opening turn with no prior context. For an opening turn, provide 2-4 broad category labels (for example: Bug fix, New feature, Refactor, Explain code, Other).',
  '  - allow_freeform: true is permitted, AS LONG AS choices is also populated with 2-4 concrete labels. The strict-mode contract is that the user always has concrete labels to pick from; whether they can also type freeform alongside is allowed. Never call ask_user with allow_freeform: true and no choices — that is the freeform-only failure that strict mode forbids.',
  'Prefix the strongest choice with "Recommended: " when one option is clearly best, so it sits first in the list.',
  `When you are polling a background task (build, test run, long-running command) and waiting for it to finish, append ${OPTIONS_BACKGROUND_TASK_TAG} as the final line of your response. This tag asserts the turn is a status update on a background task, not a question.`,
  `When you are polling a background agent (subagent, peer agent, orchestrator) and waiting for it to report back, append ${OPTIONS_BACKGROUND_AGENT_TAG} as the final line of your response. This tag asserts the turn is a status update on a background agent, not a question.`,
  `The non-strict ${OPTIONS_NO_QUESTION_TAG} tag is NOT a valid bypass in strict mode. There is no plain-prose escape hatch: every turn must be either an ask_user call (choices populated; allow_freeform either) or one of the two background tags above.`,
  'If options mode is off, do not enforce ask_user choice prompts.',
  '',
  `Canonical anchors: OPTIONS MODE ACTIVE; strict; ask_user; choices REQUIRED; Recommended; ${OPTIONS_BACKGROUND_TASK_TAG}; ${OPTIONS_BACKGROUND_AGENT_TAG}.`
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

// Copilot has no env-var or options.json default fallback path — by v0.10.0
// design the flag at <copilotConfigRoot>/.options-mode-active is the only
// source of truth on this surface (Copilot CLI hooks did not carry session
// state at the time, so per-session toggling was deferred and the flag is
// machine-wide). The Claude Code mirror in hooks/config.js has env -> file ->
// off precedence; that asymmetry is intentional and documented in CLAUDE.md.
function getOptionsMode() {
  // Mirror Claude-side fail-open semantics: on a real read error (not just
  // missing file), return 'on' so enforcement stays active. _readFlagInternal
  // throws on real fs errors and returns null on ENOENT/invalid content.
  try {
    const mode = _readFlagInternal(getFlagPath());
    return mode === null ? 'off' : mode;
  } catch (e) {
    return 'on';
  }
}

function isOptionsActive() {
  const mode = getOptionsMode();
  return mode === 'on' || mode === 'strict';
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
  OPTIONS_BACKGROUND_TASK_TAG,
  OPTIONS_BACKGROUND_AGENT_TAG,
  OPTIONS_RULES_FOR_COPILOT,
  OPTIONS_RULES_FOR_COPILOT_STRICT,
  VALID_MODES,
  FLAG_NAME,
  getConfigRoot,
  getFlagPath,
  readFlag,
  isOptionsActive,
  getOptionsMode,
  safeWriteFlag,
  appendLog,
  readStdinJson
};
