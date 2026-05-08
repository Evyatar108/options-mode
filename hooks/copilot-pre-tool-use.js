#!/usr/bin/env node

const { getOptionsMode, appendLog, readStdinJson } = require('./copilot-config');

const AUTO_CONTINUE_MSG = "The user isn't here right now, please try to continue as much as possible.";

(function main() {
  const stdin = readStdinJson();
  const rawSize = (() => { try { return JSON.stringify(stdin).length; } catch (e) { return 0; } })();
  const keys = stdin && typeof stdin === 'object' ? Object.keys(stdin).join(',') : '';
  appendLog(`DEBUG preToolUse stdin keys=${keys} bytes=${rawSize}`);
  appendLog(`DEBUG preToolUse stdin raw=${JSON.stringify(stdin)}`);

  // Auto-continue guard: must come before the pass-through write/exit below.
  if (stdin && stdin.tool_name === 'ask_user') {
    let mode;
    try { mode = getOptionsMode(stdin.session_id); } catch (e) { /* fall through to pass-through */ }
    if (mode === 'auto') {
      appendLog(`INFO options Copilot preToolUse auto-continue (auto mode)`);
      process.stdout.write(JSON.stringify({ decision: 'block', reason: AUTO_CONTINUE_MSG }));
      process.exit(0);
    }
  }

  process.stdout.write('{}');
  process.exit(0);
})();
