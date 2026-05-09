#!/usr/bin/env node

const { getOptionsMode, safeWriteSessionFlag, appendLog, readStdinJson, VALID_MODES } = require('./copilot-config');

const AUTO_CONTINUE_MSG = "The user isn't here right now, please try to continue as much as possible.";

(function main() {
  const stdin = readStdinJson();
  const rawSize = (() => { try { return JSON.stringify(stdin).length; } catch (e) { return 0; } })();
  const keys = stdin && typeof stdin === 'object' ? Object.keys(stdin).join(',') : '';
  appendLog(`DEBUG preToolUse stdin keys=${keys} bytes=${rawSize}`);
  appendLog(`DEBUG preToolUse stdin raw=${JSON.stringify(stdin)}`);

  const sessionId = stdin && stdin.sessionId;

  // Per-session toggle: SKILL.md runs Write-Output 'options-mode-set:<mode>' or
  // Write-Output 'options-mode-status'. We detect it, act, and return {} (allow)
  // for set commands so the shell command exits 0 with no "Denied" confusion.
  // For status we deny with the current mode value so the model can report it.
  const shellTools = new Set(['powershell', 'bash', 'shell', 'cmd']);
  if (stdin && shellTools.has(stdin.toolName)) {
    let toolArgs = {};
    try { toolArgs = typeof stdin.toolArgs === 'string' ? JSON.parse(stdin.toolArgs) : (stdin.toolArgs || {}); } catch (e) {}
    const cmd = (toolArgs.command || '').trim();

    const setMatch = cmd.match(/options-mode-set:(\w+)/);
    if (setMatch) {
      const mode = setMatch[1].toLowerCase();
      if (VALID_MODES.includes(mode)) {
        safeWriteSessionFlag(sessionId, mode);
        appendLog(`INFO preToolUse options-mode set sessionId=${sessionId} mode=${mode}`);
        // Allow the command to run (exits 0, prints the marker — harmless).
        process.stdout.write('{}');
        process.exit(0);
      }
    }

    if (cmd.includes('options-mode-status')) {
      const mode = getOptionsMode(sessionId);
      appendLog(`INFO preToolUse options-mode status sessionId=${sessionId} mode=${mode}`);
      process.stdout.write(JSON.stringify({
        additionalContext: `options mode (copilot): ${mode}`
      }));
      process.exit(0);
    }
  }

  // Auto-continue guard: intercept ask_user in auto mode before dialog renders.
  if (stdin && stdin.toolName === 'ask_user') {
    let mode;
    try { mode = getOptionsMode(sessionId); } catch (e) { /* fall through */ }
    if (mode === 'auto') {
      appendLog(`INFO options Copilot preToolUse auto-continue (auto mode)`);
      process.stdout.write(JSON.stringify({
        permissionDecision: 'deny',
        permissionDecisionReason: AUTO_CONTINUE_MSG,
        decision: 'block',
        reason: AUTO_CONTINUE_MSG
      }));
      process.exit(0);
    }
  }

  process.stdout.write('{}');
  process.exit(0);
})();
