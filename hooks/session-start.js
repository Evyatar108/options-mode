#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const {
  OPTIONS_RULES_TEXT,
  OPTIONS_RULES_TEXT_STRICT,
  getConfigRoot,
  getOptionsMode
} = require('./config');

function readStdin(callback) {
  let input = '';
  process.stdin.on('data', chunk => { input += chunk; });
  process.stdin.on('end', () => callback(input));
}

function parseInput(raw) {
  try { return raw ? JSON.parse(raw) : {}; } catch (e) { return {}; }
}

function hasStatusLine(settingsPath) {
  try {
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    return Boolean(settings.statusLine);
  } catch (e) {
    return false;
  }
}

function statuslineReminder(configRoot) {
  const sentinel = path.join(configRoot, '.options-statusline-warn');
  if (fs.existsSync(sentinel)) return '';
  if (hasStatusLine(path.join(configRoot, 'settings.json'))) return '';
  try { fs.writeFileSync(sentinel, '1', { flag: 'wx' }); } catch (e) {}
  return [
    'OPTIONS STATUSLINE SETUP: add one of these settings.json snippets if you want the badge.',
    'Bash: "statusLine": { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/options-mode-statusline.sh" }',
    'PowerShell: "statusLine": { "type": "command", "command": "pwsh -File ${CLAUDE_PLUGIN_ROOT}/hooks/options-mode-statusline.ps1" }'
  ].join('\n');
}

readStdin(raw => {
  const input = parseInput(raw);
  if (input.agent_id || input.agent_type) return;

  const configRoot = getConfigRoot();
  const sessionId = input.session_id;
  const mode = getOptionsMode(sessionId);
  let rulesBlock = '';
  if (mode === 'strict') rulesBlock = OPTIONS_RULES_TEXT_STRICT;
  else if (mode === 'on') rulesBlock = OPTIONS_RULES_TEXT;

  const output = [rulesBlock, statuslineReminder(configRoot)]
    .filter(Boolean)
    .join('\n\n');
  process.stdout.write(output);
});
