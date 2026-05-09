#!/usr/bin/env node

// agentStop hook for GitHub Copilot CLI.
//
// stdin shape (observed 2026-05-05, Copilot CLI 1.0.22+):
//   { timestamp, cwd, sessionId, transcriptPath, stopReason }
//
// stdin does NOT carry assistant text, so we read transcriptPath (events.jsonl),
// walk backward to the most recent `assistant.message` event, and check it for
// an `ask_user` toolRequest or the no-question tag substring in `data.content`.
//
// Block decision is emitted with multiple field-name shapes (decision/reason,
// permissionDecision/permissionDecisionReason, block/blockReason) so whichever
// shape Copilot honors will fire. Empirically `decision`+`reason` is honored —
// the reason text is reinjected as the next user.message.
//
// Loop-counter give-up mirrors hooks/stop.js: keyed on
// (transcriptPath, last-assistant-message id), bail after 5 consecutive blocks.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const {
  OPTIONS_NO_QUESTION_TAG,
  OPTIONS_BACKGROUND_TASK_TAG,
  OPTIONS_BACKGROUND_AGENT_TAG,
  OPTIONS_TASK_COMPLETE_TAG,
  getOptionsMode,
  readStdinJson,
  appendLog,
  getConfigRoot
} = require('./copilot-config');

const BLOCK_REASON = `Add ${OPTIONS_NO_QUESTION_TAG} tag if this turn is not asking the user, or call ask_user with a choices array.`;
const BLOCK_REASON_STRICT = `Strict options mode: call ask_user with a choices array, or append ${OPTIONS_BACKGROUND_TASK_TAG} or ${OPTIONS_BACKGROUND_AGENT_TAG} when polling.`;

function parseTranscript(transcriptPath) {
  let raw;
  try {
    raw = fs.readFileSync(transcriptPath, 'utf8');
  } catch (e) {
    return null;
  }

  for (let end = raw.length; end > 0; ) {
    let start = raw.lastIndexOf('\n', end - 1) + 1;
    const line = raw.slice(start, end).trim();
    end = start - 1;
    if (!line) continue;
    let evt;
    try { evt = JSON.parse(line); } catch (e) { continue; }
    if (evt && evt.type === 'assistant.message') return evt;
  }

  return null;
}

function extractContent(evt) {
  const data = (evt && evt.data) || {};
  const content = typeof data.content === 'string' ? data.content : '';
  const toolRequests = Array.isArray(data.toolRequests) ? data.toolRequests : [];
  let hasAskUser = false;
  for (const req of toolRequests) {
    if (req && typeof req === 'object' && req.name === 'ask_user') { hasAskUser = true; break; }
  }
  return { content, hasAskUser };
}

function assistantKey(evt, content) {
  const id = evt && (evt.id || (evt.data && evt.data.messageId));
  if (id) return String(id);
  const hash = crypto.createHash('sha256').update(content).digest('hex').slice(0, 16);
  return `${hash}:${content.length}`;
}

function counterPath(transcriptPath, key) {
  const id = crypto.createHash('sha256').update(`${transcriptPath}\n${key}`).digest('hex').slice(0, 32);
  return path.join(getConfigRoot(), `.options-stop-counter-${id}`);
}

function incrementLoopCounter(transcriptPath, key) {
  const file = counterPath(transcriptPath, key);
  let count = 0;
  try { count = Number(fs.readFileSync(file, 'utf8')) || 0; } catch (e) {}
  count += 1;
  try { fs.writeFileSync(file, String(count)); } catch (e) {}
  return count;
}

function emitPass() {
  process.stdout.write('{}');
  process.exit(0);
}

function emitBlock(reason) {
  const decision = {
    decision: 'block',
    reason,
    permissionDecision: 'deny',
    permissionDecisionReason: reason,
    block: true,
    blockReason: reason
  };
  process.stdout.write(JSON.stringify(decision));
  process.exit(0);
}

(function main() {
  const stdin = readStdinJson();

  if (stdin && (stdin.agentStopActive === true || stdin.stop_hook_active === true)) {
    appendLog('INFO agentStop short-circuit recursive');
    emitPass();
  }

  const sessionId = stdin && stdin.sessionId;
  let mode = 'on';
  try { mode = getOptionsMode(sessionId); } catch (e) {}
  if (mode !== 'on' && mode !== 'strict' && mode !== 'auto') emitPass();

  const transcriptPath = stdin && (stdin.transcriptPath || stdin.transcript_path);
  if (!transcriptPath || !fs.existsSync(transcriptPath)) {
    appendLog(`DEBUG agentStop no transcriptPath path=${transcriptPath || ''}`);
    emitPass();
  }

  const evt = parseTranscript(transcriptPath);
  if (!evt) {
    appendLog('DEBUG agentStop no assistant.message in transcript');
    emitPass();
  }

  const { content, hasAskUser } = extractContent(evt);

  if (hasAskUser) {
    if (mode === 'auto') {
      appendLog('INFO agentStop auto-continue ask_user-found (auto mode)');
      emitBlock("The user isn't here right now, please try to continue as much as possible.");
    } else {
      appendLog('INFO agentStop pass ask_user-found');
      emitPass();
    }
  }

  const reason = mode === 'strict' ? BLOCK_REASON_STRICT
    : mode === 'auto' ? `Auto options mode: call ask_user for decisions (hook auto-responds), or append ${OPTIONS_TASK_COMPLETE_TAG} when done, or use a background tag when polling.`
    : BLOCK_REASON;

  if (content.indexOf(OPTIONS_BACKGROUND_TASK_TAG) !== -1) {
    appendLog(`INFO agentStop pass background-task-tag-found mode=${mode}`);
    emitPass();
  }
  if (content.indexOf(OPTIONS_BACKGROUND_AGENT_TAG) !== -1) {
    appendLog(`INFO agentStop pass background-agent-tag-found mode=${mode}`);
    emitPass();
  }
  if (mode === 'auto' && content.indexOf(OPTIONS_TASK_COMPLETE_TAG) !== -1) {
    appendLog(`INFO agentStop pass task-complete-tag-found mode=${mode}`);
    emitPass();
  }
  if (mode !== 'strict' && mode !== 'auto' && content.indexOf(OPTIONS_NO_QUESTION_TAG) !== -1) {
    appendLog('INFO agentStop pass no-question-tag-found');
    emitPass();
  }

  if (!content.trim()) {
    appendLog('INFO agentStop pass empty-content (intermediate tool turn)');
    emitPass();
  }

  const key = assistantKey(evt, content);
  const count = incrementLoopCounter(transcriptPath, key);
  if (count > 5) {
    appendLog(`WARN agentStop gave up after ${count} blocks for ${transcriptPath} ${key}`);
    try { fs.unlinkSync(counterPath(transcriptPath, key)); } catch (e) {}
    emitPass();
  }

  appendLog(`WARN agentStop block count=${count} key=${key} mode=${mode} reason="${reason.slice(0, 120)}"`);
  emitBlock(reason);
})();
