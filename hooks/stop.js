#!/usr/bin/env node

const fs = require('fs');
const crypto = require('crypto');
const path = require('path');

const { appendLog, getConfigRoot, isOptionsActive, OPTIONS_NO_QUESTION_TAG } = require('./config');

const BLOCK_REASON = `Add ${OPTIONS_NO_QUESTION_TAG} tag if this turn is not asking the user, or use AskUserQuestion with concrete choices.`;

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch (e) {
    return '';
  }
}

function parseInput(raw) {
  try {
    return JSON.parse(raw || '{}');
  } catch (e) {
    return {};
  }
}

function parseTranscript(transcriptPath) {
  let raw;
  try {
    raw = fs.readFileSync(transcriptPath, 'utf8');
  } catch (e) {
    return null;
  }

  const envelopes = [];
  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      envelopes.push(JSON.parse(line));
    } catch (e) {}
  }

  for (let i = envelopes.length - 1; i >= 0; i -= 1) {
    const envelope = envelopes[i];
    if (envelope && (envelope.type === 'assistant' || envelope.role === 'assistant')) return envelope;
  }

  return null;
}

function normalizeAssistantContent(envelope) {
  const content = envelope && envelope.message && envelope.message.content !== undefined
    ? envelope.message.content
    : envelope && envelope.content;
  if (typeof content === 'string') {
    return { text: content, hasAskUserQuestion: false };
  }

  if (!Array.isArray(content)) {
    return { text: '', hasAskUserQuestion: false };
  }

  const texts = [];
  let hasAskUserQuestion = false;
  for (const block of content) {
    if (!block || typeof block !== 'object') continue;
    if (block.type === 'tool_use' && block.name === 'AskUserQuestion') {
      hasAskUserQuestion = true;
      continue;
    }
    if (block.type === 'text' && typeof block.text === 'string') texts.push(block.text);
  }

  return { text: texts.join('\n'), hasAskUserQuestion };
}

function assistantKey(envelope, text) {
  if (envelope && envelope.uuid) return String(envelope.uuid);
  const hash = crypto.createHash('sha256').update(text).digest('hex').slice(0, 16);
  return `${hash}:${text.length}`;
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

function sanitizeReason(reason) {
  const DEFAULT = BLOCK_REASON;
  const cleaned = String(reason || '')
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/[\x00-\x1F\x7F]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!cleaned) return DEFAULT;
  return cleaned.slice(0, 200);
}

async function main() {
  const input = parseInput(readStdin());

  if (input.stop_hook_active === true) return;
  if (input.agent_id || input.agent_type) return;

  try {
    if (!isOptionsActive(input.session_id)) return;
  } catch (e) {}

  if (!input.transcript_path || !fs.existsSync(input.transcript_path)) return;

  const lastAssistant = parseTranscript(input.transcript_path);
  if (!lastAssistant) return;

  const normalized = normalizeAssistantContent(lastAssistant);
  if (normalized.hasAskUserQuestion) return;
  if (!normalized.text || !normalized.text.trim()) return;
  if (normalized.text.includes(OPTIONS_NO_QUESTION_TAG)) return;

  const key = assistantKey(lastAssistant, normalized.text);
  const count = incrementLoopCounter(input.transcript_path, key);
  if (count > 5) {
    appendLog(`WARN options Stop hook gave up after ${count} blocks for ${input.transcript_path} ${key}`);
    try { fs.unlinkSync(counterPath(input.transcript_path, key)); } catch (e) {}
    return;
  }

  appendLog(`INFO options Stop hook blocked missing continue tag: ${BLOCK_REASON}`);
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: sanitizeReason(BLOCK_REASON)
  }));
}

if (require.main === module) {
  main().catch(err => {
    appendLog(`WARN options Stop hook failed open: ${err && err.message ? err.message : err}`);
  });
}

module.exports = {
  BLOCK_REASON,
  parseTranscript,
  normalizeAssistantContent,
  sanitizeReason
};
