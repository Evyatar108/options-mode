#!/usr/bin/env node

// agentStop hook — schema is undocumented in public Copilot CLI docs as of 2026-05-03.
// This hook logs the full stdin payload to ~/.copilot/options-mode.log so the schema
// can be reverse-engineered empirically, then performs a best-effort enforcement check
// by walking all string values in the payload and matching for either the
// no-question tag substring or an ask_user tool invocation.
//
// If the heuristic detects a violation, the hook emits a decision payload using
// multiple likely field-name conventions (decision/block, permissionDecision/permissionDecisionReason,
// block/blockReason) so whichever shape Copilot honors will fire.
//
// Always exits 0. Update the heuristic + emitted decision shape after observing real
// agentStop stdin payloads in the log file.

const {
  OPTIONS_NO_QUESTION_TAG,
  isOptionsActive,
  readStdinJson,
  appendLog
} = require('./copilot-config');

const ASK_USER_HINTS = ['"ask_user"', "'ask_user'", '"name":"ask_user"', '"tool":"ask_user"', '"tool_name":"ask_user"'];

function collectStrings(node, out) {
  if (node == null) return;
  if (typeof node === 'string') {
    out.push(node);
    return;
  }
  if (Array.isArray(node)) {
    for (const v of node) collectStrings(v, out);
    return;
  }
  if (typeof node === 'object') {
    for (const k of Object.keys(node)) collectStrings(node[k], out);
  }
}

function hasNoQuestionTag(text) {
  return text.indexOf(OPTIONS_NO_QUESTION_TAG) !== -1;
}

function hasAskUser(rawJson, joinedStrings) {
  const haystack = rawJson + '\n' + joinedStrings;
  for (const h of ASK_USER_HINTS) {
    if (haystack.indexOf(h) !== -1) return true;
  }
  return false;
}

(function main() {
  const stdin = readStdinJson();

  if (!isOptionsActive()) {
    process.stdout.write('{}');
    process.exit(0);
  }

  let raw = '';
  try {
    raw = JSON.stringify(stdin);
  } catch (e) {}

  if (stdin && (stdin.agentStopActive === true || stdin.stop_hook_active === true)) {
    appendLog('INFO agentStop short-circuit recursive');
    process.stdout.write('{}');
    process.exit(0);
  }

  appendLog(`DEBUG agentStop stdin keys=${Object.keys(stdin || {}).join(',')} bytes=${raw.length}`);
  appendLog(`DEBUG agentStop stdin raw=${raw.slice(0, 4000)}`);

  const strings = [];
  collectStrings(stdin, strings);
  const joined = strings.join('\n');

  if (hasNoQuestionTag(joined)) {
    appendLog('INFO agentStop pass tag-found');
    process.stdout.write('{}');
    process.exit(0);
  }

  if (hasAskUser(raw, joined)) {
    appendLog('INFO agentStop pass ask_user-found');
    process.stdout.write('{}');
    process.exit(0);
  }

  const reason = `Add ${OPTIONS_NO_QUESTION_TAG} tag if this turn is not asking the user, or call ask_user with a choices array.`;
  const decision = {
    decision: 'block',
    reason,
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
    block: true,
    blockReason: reason
  };
  appendLog(`WARN agentStop block reason="${reason.slice(0, 120)}"`);
  process.stdout.write(JSON.stringify(decision));
  process.exit(0);
})();
