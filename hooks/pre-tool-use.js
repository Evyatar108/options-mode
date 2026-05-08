#!/usr/bin/env node
const { getOptionsMode, appendLog } = require('./config');

const AUTO_CONTINUE_MSG = "The user isn't here right now, please try to continue as much as possible.";

function readStdin() { try { return require('fs').readFileSync(0, 'utf8'); } catch (e) { return ''; } }
function parseInput(raw) { try { return JSON.parse(raw || '{}'); } catch (e) { return {}; } }

async function main() {
  const input = parseInput(readStdin());
  if (input.tool_name !== 'AskUserQuestion') return;
  if (input.agent_id || input.agent_type) return;
  let mode;
  try { mode = getOptionsMode(input.session_id); } catch (e) { return; }
  if (mode !== 'auto') return;

  appendLog(`INFO options PreToolUse auto-continue (auto mode)`);
  process.stdout.write(JSON.stringify({ decision: 'block', reason: AUTO_CONTINUE_MSG }));
}
main().catch(() => {});
