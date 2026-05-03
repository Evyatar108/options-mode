#!/usr/bin/env node

const {
  OPTIONS_RULES_TEXT,
  getFlagPath,
  isOptionsActive,
  safeWriteFlag,
  readFlag,
  getDefaultModeRaw,
  setDefaultMode,
  clearDefaultMode
} = require('./config');

function readStdin(callback) {
  let input = '';
  process.stdin.on('data', chunk => { input += chunk; });
  process.stdin.on('end', () => callback(input));
}

function parseInput(raw) {
  try { return raw ? JSON.parse(raw) : {}; } catch (e) { return {}; }
}

function block(reason) {
  process.stdout.write(JSON.stringify({ decision: 'block', reason }));
}

readStdin(raw => {
  const data = parseInput(raw);
  const prompt = String(data.prompt || '').trim();
  const lower = prompt.toLowerCase();
  const sessionId = data.session_id;

  if (lower.startsWith('/options-mode')) {
    const tokens = lower.split(/\s+/);
    const arg = tokens[1] || 'status';
    if (arg === 'on' || arg === 'off') {
      safeWriteFlag(getFlagPath(sessionId), arg);
      block(`options mode: ${arg}`);
      return;
    }
    if (arg === 'status') {
      const effective = isOptionsActive(sessionId) ? 'on' : 'off';
      const sessionRaw = readFlag(getFlagPath(sessionId));
      const session = sessionRaw === null ? 'unset' : sessionRaw;
      const defaultRaw = getDefaultModeRaw();
      const defaultLabel = defaultRaw === null ? 'unset' : defaultRaw;
      block(`options mode: ${effective} (session=${session}, default=${defaultLabel})`);
      return;
    }
    if (arg === 'default') {
      const sub = tokens[2] || 'status';
      if (sub === 'on' || sub === 'off') {
        setDefaultMode(sub);
        block(`options mode default: ${sub}`);
        return;
      }
      if (sub === 'clear') {
        clearDefaultMode();
        block('options mode default: cleared');
        return;
      }
      if (sub === 'status') {
        const defaultRaw = getDefaultModeRaw();
        block(`options mode default: ${defaultRaw === null ? 'unset' : defaultRaw}`);
        return;
      }
      block('options mode: usage /options-mode on|off|status|default [on|off|clear|status]');
      return;
    }
    block('options mode: usage /options-mode on|off|status|default [on|off|clear|status]');
    return;
  }

  if (isOptionsActive(sessionId)) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext: OPTIONS_RULES_TEXT
      }
    }));
  }
});
