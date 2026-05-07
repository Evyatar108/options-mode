#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLUGIN_ROOT="$ROOT/plugins/options-mode"
NODE_BIN="$(command -v node)"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2" >&2
  exit 1
}

test_codex_plugin_interface_fields() {
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const manifest = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'plugins/options-mode/.codex-plugin/plugin.json'), 'utf8'));
const required = ['displayName', 'shortDescription', 'category', 'capabilities'];
for (const field of required) {
  const value = manifest.interface && manifest.interface[field];
  if (Array.isArray(value)) {
    if (value.length === 0) throw new Error(`interface.${field} must be non-empty`);
    continue;
  }
  if (!value) throw new Error(`interface.${field} must be non-empty`);
}
NODE
  pass test_codex_plugin_interface_fields
}

test_copilot_skills_dir_renamed() {
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.cwd();
const pluginRoot = path.join(root, 'plugins/options-mode');
// v0.12.0 rename: .copilot-plugin/skills/ -> .copilot-plugin/copilot-skills/
// to prevent Claude Code's plugin discovery from picking up the Copilot skill body
// (which writes to ~/.copilot/.options-mode-active, the wrong path for Claude Code).
const oldDir = path.join(pluginRoot, '.copilot-plugin/skills');
if (fs.existsSync(oldDir)) throw new Error(`legacy .copilot-plugin/skills/ must not exist (would re-expose skill to Claude Code); got ${oldDir}`);
const newSkillFile = path.join(pluginRoot, '.copilot-plugin/copilot-skills/options-mode/SKILL.md');
if (!fs.existsSync(newSkillFile)) throw new Error(`copilot skill SKILL.md missing at ${newSkillFile}`);
const copilotManifest = JSON.parse(fs.readFileSync(path.join(pluginRoot, '.github/plugin/plugin.json'), 'utf8'));
if (copilotManifest.skills !== '.copilot-plugin/copilot-skills/') throw new Error(`bad copilot manifest skills field: ${copilotManifest.skills}`);
NODE
  pass test_copilot_skills_dir_renamed
}

test_codex_plugin_skills_field() {
  node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.cwd();
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'plugins/options-mode/.codex-plugin/plugin.json'), 'utf8'));
if (manifest.skills !== './skills/') throw new Error(`bad skills field: ${manifest.skills}`);
const codexSkillsDir = path.join(root, 'plugins/options-mode/.codex-plugin/skills/options-mode');
if (!fs.existsSync(path.join(codexSkillsDir, 'SKILL.md'))) throw new Error('codex skill SKILL.md missing at .codex-plugin/skills/options-mode/');
const claudeSkillsRoot = path.join(root, 'plugins/options-mode/skills');
if (fs.existsSync(claudeSkillsRoot)) throw new Error('plugin-root skills/ must not exist (would expose skill to Claude Code, defeating the v0.9.0 hide-skill fix)');
const required = ['displayName', 'shortDescription', 'category', 'capabilities'];
for (const field of required) {
  const value = manifest.interface && manifest.interface[field];
  if (Array.isArray(value)) {
    if (value.length === 0) throw new Error(`interface.${field} must be non-empty`);
    continue;
  }
  if (!value) throw new Error(`interface.${field} must be non-empty`);
}
NODE
  pass test_codex_plugin_skills_field
}

test_escape_for_bash_single_quote() {
  node <<'NODE'
const { escapeForBashSingleQuote } = require('./plugins/options-mode/hooks/config');
const { spawnSync } = require('child_process');
const inputs = [
  "foo'bar",
  "don't",
  "it's a \"test\"",
  "a'b'c'd'e",
  String.raw`literal \n and \t backslash sequences`,
  'multi\nline\nstring',
  '$VAR and `cmd`',
  String.raw`back\slashes\here`,
  'Café — naïve résumé',
];
let allPass = true;
for (const input of inputs) {
  const escaped = escapeForBashSingleQuote(input);
  const result = spawnSync('bash', ['-c', "printf '%s' " + escaped], { encoding: 'utf8' });
  const stderr = (result.stderr || '').trim();
  if (result.status !== 0 || stderr) {
    process.stderr.write('round-trip FAIL ' + JSON.stringify(input) + ' stderr: ' + stderr + '\n');
    allPass = false;
    continue;
  }
  if (result.stdout !== input) {
    process.stderr.write('round-trip MISMATCH ' + JSON.stringify(input) + ' -> got ' + JSON.stringify(result.stdout) + '\n');
    allPass = false;
  }
}
if (!allPass) process.exit(1);
NODE
  pass test_escape_for_bash_single_quote
}

test_rule_text_sync() {
  node <<'NODE'
const fs = require('fs');
const { OPTIONS_RULES_TEXT, escapeForBashSingleQuote } = require('./plugins/options-mode/hooks/config');
if (!/^[\x00-\x7F]*$/.test(OPTIONS_RULES_TEXT)) throw new Error('OPTIONS_RULES_TEXT contains non-ASCII');
const hooks = JSON.parse(fs.readFileSync('.codex/hooks.json', 'utf8'));
const entry = hooks.hooks.SessionStart.flatMap((item) => item.hooks || []).find((hook) => hook._owner === 'options-mode');
if (!entry) throw new Error('options-mode hook entry missing');
const expected = `printf '%s\\n' ${escapeForBashSingleQuote(OPTIONS_RULES_TEXT)}`;
if (entry.command !== expected) throw new Error('inline command is not synced with OPTIONS_RULES_TEXT');
const match = entry.command.match(/^printf '%s\\n' '([\s\S]*)'$/);
if (!match) throw new Error('inline command shape mismatch');
const unescaped = match[1].replace(/'\\''/g, "'").replace(/\r\n/g, '\n');
const rules = OPTIONS_RULES_TEXT.replace(/\r\n/g, '\n');
if (unescaped !== rules) throw new Error('decoded rules text mismatch');
NODE
  pass test_rule_text_sync
}

test_codex_config_toml() {
  if node -e "require.resolve('@iarna/toml')" >/dev/null 2>&1; then
    node <<'NODE'
const fs = require('fs');
const toml = require('@iarna/toml');
const parsed = toml.parse(fs.readFileSync('.codex/config.toml', 'utf8'));
if (!parsed.features || parsed.features.codex_hooks !== true) throw new Error('codex_hooks not true');
NODE
  else
    awk 'BEGIN{in_features=0; found=0} /^[[:space:]]*\[features\][[:space:]]*$/ {in_features=1; next} /^[[:space:]]*\[/ {in_features=0} in_features {sub(/[[:space:]]*#.*/, ""); if ($0 ~ /^[[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*true[[:space:]]*$/) found=1} END{exit found ? 0 : 1}' .codex/config.toml \
      || fail test_codex_config_toml 'codex_hooks = true missing from [features]'
  fi
  pass test_codex_config_toml
}

test_codex_hook_replay() {
  local command out source
  command="$(jq -r '.hooks.SessionStart[0].hooks[] | select(._owner=="options-mode") | .command' .codex/hooks.json)"
  [[ -n "$command" && "$command" != "null" ]] || fail test_codex_hook_replay 'options-mode command missing'
  for source in startup resume; do
    out="$(bash -c "$command")"
    [[ "$out" == *"OPTIONS MODE ACTIVE"* ]] || fail test_codex_hook_replay "missing active anchor for $source"
    [[ "$out" == *"AskUserQuestion choice prompt"* ]] || fail test_codex_hook_replay "missing AskUserQuestion anchor for $source"
    [[ "$out" == *"Recommended"* ]] || fail test_codex_hook_replay "missing Recommended anchor for $source"
    [[ "$out" == *"mutually exclusive labels"* ]] || fail test_codex_hook_replay "missing labels anchor for $source"
    [[ "$out" == *"<options-mode>no-question</options-mode>"* ]] || fail test_codex_hook_replay "missing no-question tag anchor for $source"
  done
  pass test_codex_hook_replay
}

test_docs_presence() {
  grep -q 'Tag Protocol' plugins/options-mode/README.md || fail test_docs_presence 'README missing tag protocol'
  grep -q '<options-mode>no-question</options-mode>' plugins/options-mode/README.md || fail test_docs_presence 'README missing no-question tag'
  grep -q 'OS Support' plugins/options-mode/README.md || fail test_docs_presence 'README missing OS support'
  grep -q '.options-statusline-warn' plugins/options-mode/README.md || fail test_docs_presence 'README missing statusline sentinel'
  grep -q '.options-stop-counter-' plugins/options-mode/README.md || fail test_docs_presence 'README missing stop counter sentinel'
  grep -q 'v0.5.0 Migration Note' plugins/options-mode/CLAUDE.md || fail test_docs_presence 'CLAUDE missing v0.5.0 migration note'
  grep -q 'Tag Protocol' plugins/options-mode/CLAUDE.md || fail test_docs_presence 'CLAUDE missing tag protocol'
  grep -q '<options-mode>no-question</options-mode>' plugins/options-mode/CLAUDE.md || fail test_docs_presence 'CLAUDE missing no-question tag'
  grep -q '_owner' plugins/options-mode/CLAUDE.md || fail test_docs_presence 'CLAUDE missing _owner'
  pass test_docs_presence
}

run_session_start() {
  local source="$1"
  local config_root="$2"
  local session_id="${3:-}"
  local payload
  if [[ -n "$session_id" ]]; then
    payload="{\"hook_event_name\":\"SessionStart\",\"source\":\"$source\",\"session_id\":\"$session_id\"}"
  else
    payload="{\"hook_event_name\":\"SessionStart\",\"source\":\"$source\"}"
  fi
  CLAUDE_CONFIG_DIR="$config_root" HOME="$config_root/home" PATH="/nonexistent" \
    "$NODE_BIN" "$PLUGIN_ROOT/hooks/session-start.js" <<<"$payload"
}

session_flag_name() {
  local session_id="$1"
  "$NODE_BIN" -e "process.stdout.write('.options-active-' + require('crypto').createHash('sha256').update(process.argv[1]).digest('hex').slice(0, 32))" "$session_id"
}

test_session_start_emits_rules_when_active() {
  local sid="sess-active-fixed"
  local flag_name
  flag_name="$(session_flag_name "$sid")"
  for source in startup resume compact clear; do
    local dir out
    dir="$(mktemp -d)"
    printf on > "$dir/$flag_name"
    out="$(run_session_start "$source" "$dir" "$sid")"
    [[ "$out" == *"OPTIONS MODE ACTIVE"* ]] || fail test_session_start_emits_rules_when_active "missing active anchor for $source"
    [[ "$out" == *"AskUserQuestion choice prompt"* ]] || fail test_session_start_emits_rules_when_active "missing AskUserQuestion anchor for $source"
    [[ "$out" == *"Recommended"* ]] || fail test_session_start_emits_rules_when_active "missing Recommended anchor for $source"
    [[ "$out" == *"mutually exclusive labels"* ]] || fail test_session_start_emits_rules_when_active "missing labels anchor for $source"
    [[ "$out" == *"<options-mode>no-question</options-mode>"* ]] || fail test_session_start_emits_rules_when_active "missing no-question tag anchor for $source"
    [[ "$(cat "$dir/$flag_name")" == "on" ]] || fail test_session_start_emits_rules_when_active "flag mutated for $source"
  done
  pass test_session_start_emits_rules_when_active
}

test_session_start_default_off_omits_rules() {
  local dir out sid="sess-default-off"
  dir="$(mktemp -d)"
  out="$(run_session_start startup "$dir" "$sid")"
  [[ "$out" != *"OPTIONS MODE ACTIVE"* ]] || fail test_session_start_default_off_omits_rules "rules emitted when default off"
  [[ ! -e "$dir/$(session_flag_name "$sid")" ]] || fail test_session_start_default_off_omits_rules "session flag created when default off"
  [[ ! -e "$dir/.options-active" ]] || fail test_session_start_default_off_omits_rules "legacy flag created when default off"
  pass test_session_start_default_off_omits_rules
}

test_session_start_preserves_off() {
  local dir sid="sess-preserves-off"
  local flag_name
  flag_name="$(session_flag_name "$sid")"
  dir="$(mktemp -d)"
  printf off > "$dir/$flag_name"
  run_session_start startup "$dir" "$sid" >/dev/null
  [[ "$(cat "$dir/$flag_name")" == "off" ]] || fail test_session_start_preserves_off "SessionStart overwrote off flag"
  pass test_session_start_preserves_off
}

test_per_session_isolation() {
  local dir out sid_on="sess-iso-on" sid_off="sess-iso-off"
  local flag_on flag_off
  flag_on="$(session_flag_name "$sid_on")"
  flag_off="$(session_flag_name "$sid_off")"
  dir="$(mktemp -d)"
  printf on > "$dir/$flag_on"
  printf off > "$dir/$flag_off"

  out="$(run_session_start startup "$dir" "$sid_on")"
  [[ "$out" == *"OPTIONS MODE ACTIVE"* ]] || fail test_per_session_isolation "session-on did not emit rules"

  out="$(run_session_start startup "$dir" "$sid_off")"
  [[ "$out" != *"OPTIONS MODE ACTIVE"* ]] || fail test_per_session_isolation "session-off emitted rules"

  pass test_per_session_isolation
}

run_user_prompt_submit() {
  local config_root="$1"
  local prompt="$2"
  CLAUDE_CONFIG_DIR="$config_root" HOME="$config_root/home" \
    node "$PLUGIN_ROOT/hooks/user-prompt-submit.js" <<JSON
{"hook_event_name":"UserPromptSubmit","prompt":"$prompt"}
JSON
}

assert_block_reason() {
  local name="$1"
  local out="$2"
  local reason="$3"
  OUT="$out" REASON="$reason" node <<'NODE'
const out = JSON.parse(process.env.OUT);
if (out.decision !== 'block') throw new Error(`decision was ${out.decision}`);
if (out.reason !== process.env.REASON) throw new Error(`reason was ${out.reason}`);
NODE
  pass "$name"
}

test_user_prompt_submit_commands() {
  local dir out before after
  dir="$(mktemp -d)"

  out="$(run_user_prompt_submit "$dir" '/options-mode on')"
  assert_block_reason test_user_prompt_submit_on "$out" 'options mode: on'
  [[ "$(cat "$dir/.options-active")" == "on" ]] || fail test_user_prompt_submit_commands "on did not write flag"

  out="$(run_user_prompt_submit "$dir" '/options-mode off')"
  assert_block_reason test_user_prompt_submit_off "$out" 'options mode: off'
  [[ "$(cat "$dir/.options-active")" == "off" ]] || fail test_user_prompt_submit_commands "off did not write flag"

  before="$(cat "$dir/.options-active")"
  out="$(run_user_prompt_submit "$dir" '/options-mode status')"
  after="$(cat "$dir/.options-active")"
  assert_block_reason test_user_prompt_submit_status "$out" 'options mode: off (session=off, default=unset)'
  [[ "$before" == "$after" ]] || fail test_user_prompt_submit_commands "status mutated flag"

  before="$(cat "$dir/.options-active")"
  out="$(run_user_prompt_submit "$dir" '/options-mode foo')"
  after="$(cat "$dir/.options-active")"
  assert_block_reason test_user_prompt_submit_foo "$out" 'options mode: usage /options-mode on|off|strict|status|default [on|off|strict|clear|status]'
  [[ "$before" == "$after" ]] || fail test_user_prompt_submit_commands "foo mutated flag"
}

test_hooks_json_wiring() {
  node <<'NODE'
const fs = require('fs');
const hooks = JSON.parse(fs.readFileSync('plugins/options-mode/hooks/hooks.json', 'utf8')).hooks;
const session = hooks.SessionStart[0];
if (session.matcher !== 'startup|resume|compact|clear') throw new Error('bad SessionStart matcher');
const sessionHook = session.hooks[0];
if (sessionHook.command !== 'node ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.js') throw new Error('bad SessionStart command');
if (sessionHook.timeout !== 5) throw new Error('bad SessionStart timeout');
const upsHook = hooks.UserPromptSubmit[0].hooks[0];
if (upsHook.command !== 'node ${CLAUDE_PLUGIN_ROOT}/hooks/user-prompt-submit.js') throw new Error('bad UserPromptSubmit command');
if (upsHook.timeout !== 5) throw new Error('bad UserPromptSubmit timeout');
const stopHook = hooks.Stop[0].hooks[0];
if (stopHook.command !== 'node ${CLAUDE_PLUGIN_ROOT}/hooks/stop.js') throw new Error('bad Stop command');
if (stopHook.timeout !== 35) throw new Error('bad Stop timeout');
NODE
  pass test_hooks_json_wiring
}

test_config_exports() {
  node <<'NODE'
const config = require('./plugins/options-mode/hooks/config');
for (const key of ['OPTIONS_NO_QUESTION_TAG', 'OPTIONS_BACKGROUND_TASK_TAG', 'OPTIONS_BACKGROUND_AGENT_TAG', 'OPTIONS_RULES_TEXT', 'OPTIONS_RULES_TEXT_STRICT', 'escapeForBashSingleQuote', 'getFlagPath', 'getConfigRoot', 'getConfigPath', 'getDefaultMode', 'getDefaultModeRaw', 'setDefaultMode', 'clearDefaultMode', 'isOptionsActive', 'getOptionsMode', 'hasValidFlag']) {
  if (!(key in config)) throw new Error(`missing export ${key}`);
}
for (const key of ['spawn' + 'CodexSync', 'resolve' + 'CodexCommand']) {
  if (key in config) throw new Error(`deleted export still present ${key}`);
}
if (config.OPTIONS_NO_QUESTION_TAG !== '<options-mode>no-question</options-mode>') throw new Error('bad no-question tag');
if (config.OPTIONS_BACKGROUND_TASK_TAG !== '<options-mode>background-task</options-mode>') throw new Error('bad background-task tag');
if (config.OPTIONS_BACKGROUND_AGENT_TAG !== '<options-mode>background-agent</options-mode>') throw new Error('bad background-agent tag');
if (config.VALID_MODES.join(',') !== 'on,off,strict') throw new Error('bad modes: ' + config.VALID_MODES.join(','));
NODE
  pass test_config_exports
}

run_statusline_bash() {
  local dir="$1"
  local stdin_payload="$2"
  shift 2
  CLAUDE_CONFIG_DIR="$dir" HOME="$dir/home" "$@" \
    bash "$PLUGIN_ROOT/hooks/options-mode-statusline.sh" <<<"$stdin_payload"
}

run_statusline_pwsh() {
  local ps_bin="$1"
  local dir="$2"
  local stdin_payload="$3"
  shift 3
  CLAUDE_CONFIG_DIR="$dir" HOME="$dir/home" "$@" \
    "$ps_bin" -NoProfile -File "$PLUGIN_ROOT/hooks/options-mode-statusline.ps1" <<<"$stdin_payload"
}

test_statusline_bash() {
  local dir out sid="sess-statusline-bash"
  local flag_name
  flag_name="$(session_flag_name "$sid")"

  # 1. Per-session flag = on -> [OPTIONS MODE]
  dir="$(mktemp -d)"
  printf on > "$dir/$flag_name"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_bash "per-session on did not render [OPTIONS MODE]"

  # 2. Per-session flag = off -> empty
  dir="$(mktemp -d)"
  printf off > "$dir/$flag_name"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}")"
  [[ -z "$out" ]] || fail test_statusline_bash "per-session off rendered '$out', expected empty"

  # 3. No per-session flag, options.json defaultMode=on -> [OPTIONS MODE]
  dir="$(mktemp -d)"
  printf '%s' '{"defaultMode":"on"}' > "$dir/options.json"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_bash "default=on did not render [OPTIONS MODE]"

  # 4. No per-session flag, no options.json -> empty
  dir="$(mktemp -d)"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}")"
  [[ -z "$out" ]] || fail test_statusline_bash "default-off rendered '$out', expected empty"

  # 5. OPTIONS_DEFAULT_MODE=on env override (no per-session flag, no file)
  dir="$(mktemp -d)"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}" env OPTIONS_DEFAULT_MODE=on)"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_bash "env OPTIONS_DEFAULT_MODE=on did not render [OPTIONS MODE]"

  # 6. Legacy .options-active=on with no session_id on stdin -> [OPTIONS MODE]
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_statusline_bash "$dir" "")"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_bash "legacy fallback on did not render [OPTIONS MODE]"

  pass test_statusline_bash
}

test_statusline_powershell() {
  local ps_bin dir out sid="sess-statusline-ps"
  local flag_name
  ps_bin="$(command -v pwsh || command -v powershell || true)"
  if [[ -z "$ps_bin" ]]; then
    pass test_statusline_powershell_skipped
    return
  fi
  flag_name="$(session_flag_name "$sid")"

  # 1. Per-session flag = on -> [OPTIONS MODE]
  dir="$(mktemp -d)"
  printf on > "$dir/$flag_name"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_powershell "per-session on did not render [OPTIONS MODE]"

  # 2. Per-session flag = off -> empty
  dir="$(mktemp -d)"
  printf off > "$dir/$flag_name"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}")"
  [[ -z "$out" ]] || fail test_statusline_powershell "per-session off rendered '$out', expected empty"

  # 3. No per-session flag, options.json defaultMode=on -> [OPTIONS MODE]
  dir="$(mktemp -d)"
  printf '%s' '{"defaultMode":"on"}' > "$dir/options.json"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_powershell "default=on did not render [OPTIONS MODE]"

  # 4. No per-session flag, no options.json -> empty
  dir="$(mktemp -d)"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}")"
  [[ -z "$out" ]] || fail test_statusline_powershell "default-off rendered '$out', expected empty"

  # 5. OPTIONS_DEFAULT_MODE=on env override
  dir="$(mktemp -d)"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}" env OPTIONS_DEFAULT_MODE=on)"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_powershell "env OPTIONS_DEFAULT_MODE=on did not render [OPTIONS MODE]"

  # 6. Legacy .options-active=on with no session_id on stdin -> [OPTIONS MODE]
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "")"
  [[ "$out" == *"[OPTIONS MODE]"* ]] || fail test_statusline_powershell "legacy fallback on did not render [OPTIONS MODE]"

  pass test_statusline_powershell
}

test_statusline_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$PLUGIN_ROOT/hooks/options-mode-statusline.sh"
    pass test_statusline_shellcheck
  else
    pass test_statusline_shellcheck_skipped
  fi
}

run_stop_fixture() {
  local config_root="$1"
  local stdin_fixture="$2"
  local transcript="$3"
  local input
  input="$(sed "s#__TRANSCRIPT__#$transcript#g" "$PLUGIN_ROOT/tests/fixtures/stdin/$stdin_fixture")"
  CLAUDE_CONFIG_DIR="$config_root" HOME="$config_root/home" \
    node "$PLUGIN_ROOT/hooks/stop.js" <<<"$input"
}

run_stop_stdin_file() {
  local config_root="$1"
  local stdin_fixture="$2"
  local transcript="$3"
  local input_file
  input_file="$(mktemp)"
  if command -v cygpath >/dev/null 2>&1; then transcript="$(cygpath -m "$transcript")"; fi
  sed "s#__TRANSCRIPT__#$transcript#g" "$PLUGIN_ROOT/tests/fixtures/stdin/$stdin_fixture" > "$input_file"
  CLAUDE_CONFIG_DIR="$config_root" HOME="$config_root/home" \
    "$NODE_BIN" "$PLUGIN_ROOT/hooks/stop.js" < "$input_file"
  local status=$?
  rm -f "$input_file"
  return "$status"
}

run_stop_json() {
  local config_root="$1"
  local transcript="$2"
  shift 2
  if command -v cygpath >/dev/null 2>&1; then transcript="$(cygpath -m "$transcript")"; fi
  CLAUDE_CONFIG_DIR="$config_root" HOME="$config_root/home" "$@" \
    "$NODE_BIN" "$PLUGIN_ROOT/hooks/stop.js" <<JSON
{"hook_event_name":"Stop","transcript_path":"$transcript"}
JSON
}

assert_empty_output() {
  local name="$1"
  local out="$2"
  [[ -z "$out" ]] || fail "$name" "expected empty stdout, got: $out"
  pass "$name"
}

assert_stop_block() {
  local name="$1"
  local out="$2"
  OUT="$out" node <<'NODE'
const { BLOCK_REASON } = require('./plugins/options-mode/hooks/stop');
const out = JSON.parse(process.env.OUT);
if (out.decision !== 'block') throw new Error(`decision was ${out.decision}`);
if (out.reason !== BLOCK_REASON) throw new Error(`reason was ${out.reason}`);
if (out.reason.length > 200) throw new Error(`reason length ${out.reason.length}`);
NODE
  pass "$name"
}

test_stop_short_circuits() {
  local dir transcript out missing
  transcript="$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-status-without-tag.jsonl"

  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_fixture "$dir" stop-active.json "$transcript")"
  assert_empty_output test_stop_active "$out"

  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_fixture "$dir" stop-subagent.json "$transcript")"
  assert_empty_output test_stop_subagent "$out"

  dir="$(mktemp -d)"
  printf off > "$dir/.options-active"
  out="$(run_stop_fixture "$dir" stop-flag-off.json "$transcript")"
  assert_empty_output test_stop_flag_off "$out"

  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_fixture "$dir" stop-no-transcript.json "$transcript")"
  assert_empty_output test_stop_no_transcript "$out"

  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  missing="$PLUGIN_ROOT/tests/fixtures/transcripts/does-not-exist.jsonl"
  out="$(run_stop_json "$dir" "$missing")"
  assert_empty_output test_stop_missing_transcript_file "$out"

  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/no-assistant.jsonl")"
  assert_empty_output test_stop_no_assistant "$out"
}

test_tag_present_skip() {
  local dir out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-with-tag.jsonl")"
  assert_empty_output test_tag_present_skip "$out"
}

test_tag_absent_block() {
  local dir out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-status-without-tag.jsonl")"
  assert_stop_block test_tag_absent_block "$out"
}

test_tag_substring_positions() {
  local dir transcript out label text
  for label in start middle end; do
    transcript="$(mktemp)"
    case "$label" in
      start) text='<options-mode>no-question</options-mode>\nDone.' ;;
      middle) text='Done.\n<options-mode>no-question</options-mode>\nNext.' ;;
      end) text='Done.\n<options-mode>no-question</options-mode>' ;;
    esac
    TEXT="$text" TRANSCRIPT="$transcript" node <<'NODE'
const fs = require('fs');
const envelope = {
  type: 'assistant',
  message: { role: 'assistant', content: [{ type: 'text', text: process.env.TEXT }] },
  uuid: `assistant-tag-${process.env.TEXT.length}`
};
fs.writeFileSync(process.env.TRANSCRIPT, `${JSON.stringify(envelope)}\n`);
NODE
    dir="$(mktemp -d)"
    printf on > "$dir/.options-active"
    out="$(run_stop_json "$dir" "$transcript")"
    assert_empty_output "test_tag_substring_positions_$label" "$out"
  done
  pass test_tag_substring_positions
}

test_askuserquestion_present_skip() {
  local dir out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-real-askuserquestion.jsonl")"
  assert_empty_output test_askuserquestion_present_skip "$out"
}

test_offline_smoke_cases() {
  local dir out status smoke_flag
  smoke_flag="$(session_flag_name "sess-smoke")"

  dir="$(mktemp -d)"
  printf on > "$dir/$smoke_flag"
  set +e
  out="$(run_stop_stdin_file "$dir" stop-smoke-tagless.json "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-status-without-tag.jsonl")"
  status=$?
  set -e
  [[ "$status" == "0" ]] || fail test_offline_smoke_cases "Case A exit status $status"
  assert_stop_block test_offline_smoke_case_a_tagless_blocks "$out"

  dir="$(mktemp -d)"
  printf on > "$dir/$smoke_flag"
  set +e
  out="$(run_stop_stdin_file "$dir" stop-smoke-tagged.json "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-with-tag.jsonl")"
  status=$?
  set -e
  [[ "$status" == "0" ]] || fail test_offline_smoke_cases "Case B exit status $status"
  assert_empty_output test_offline_smoke_case_b_tagged_silent "$out"

  dir="$(mktemp -d)"
  printf on > "$dir/$smoke_flag"
  set +e
  out="$(run_stop_stdin_file "$dir" stop-smoke-askuserquestion.json "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-real-askuserquestion.jsonl")"
  status=$?
  set -e
  [[ "$status" == "0" ]] || fail test_offline_smoke_cases "Case C exit status $status"
  assert_empty_output test_offline_smoke_case_c_askuserquestion_silent "$out"

  pass test_offline_smoke_cases
}

test_ralph_polling_with_tag_skip() {
  local dir out status smoke_flag
  smoke_flag="$(session_flag_name "sess-smoke")"
  dir="$(mktemp -d)"
  printf on > "$dir/$smoke_flag"
  set +e
  out="$(run_stop_stdin_file "$dir" stop-smoke-tagged.json "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-ralph-polling-with-tag.jsonl")"
  status=$?
  set -e
  [[ "$status" == "0" ]] || fail test_ralph_polling_with_tag_skip "exit status $status"
  assert_empty_output test_ralph_polling_with_tag_skip "$out"
}

test_off_flag_bypass() {
  local dir out transcript
  transcript="$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-status-without-tag.jsonl"
  dir="$(mktemp -d)"
  printf off > "$dir/.options-active"
  out="$(run_stop_fixture "$dir" stop-flag-off.json "$transcript")"
  assert_empty_output test_off_flag_bypass "$out"
}

test_subagent_skip() {
  local dir out transcript
  transcript="$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-status-without-tag.jsonl"
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_fixture "$dir" stop-subagent.json "$transcript")"
  assert_empty_output test_subagent_skip "$out"
}

test_multiple_assistant_entries() {
  local dir out transcript
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  transcript="$PLUGIN_ROOT/tests/fixtures/transcripts/multiple-assistant-entries.jsonl"
  if command -v cygpath >/dev/null 2>&1; then transcript="$(cygpath -m "$transcript")"; fi
  out="$(run_stop_json "$dir" "$transcript")"
  assert_stop_block test_multiple_assistant_entries "$out"
}

test_old_shape_fixture_fallbacks() {
  local dir out
  for fixture in last-msg-old-shape-question.jsonl last-msg-old-shape-status.jsonl; do
    dir="$(mktemp -d)"
    printf on > "$dir/.options-active"
    out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/$fixture")"
    assert_stop_block "test_old_shape_fixture_fallbacks_${fixture%.jsonl}" "$out"
  done
  pass test_old_shape_fixture_fallbacks
}

test_real_shape_transcript_parse() {
  local transcript
  transcript="$(mktemp)"
  cat > "$transcript" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"},{"type":"text","text":"there"}]},"uuid":"real-shape-text"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"pick"},{"type":"tool_use","name":"AskUserQuestion","input":{}}]},"uuid":"real-shape-tool"}
JSONL
  TRANSCRIPT="$transcript" node <<'NODE'
const { parseTranscript, normalizeAssistantContent } = require('./plugins/options-mode/hooks/stop');
const envelope = parseTranscript(process.env.TRANSCRIPT);
if (!envelope) throw new Error('missing assistant envelope');
if (envelope.uuid !== 'real-shape-tool') throw new Error(`wrong envelope ${envelope.uuid}`);
const normalized = normalizeAssistantContent(envelope);
if (normalized.text !== 'pick') throw new Error(`bad text ${JSON.stringify(normalized.text)}`);
if (normalized.hasAskUserQuestion !== true) throw new Error('AskUserQuestion not detected');
NODE
  pass test_real_shape_transcript_parse
}

test_old_shape_transcript_fallback() {
  local transcript
  transcript="$(mktemp)"
  cat > "$transcript" <<'JSONL'
{"role":"user","content":"hello"}
{"role":"assistant","content":[{"type":"text","text":"legacy"},{"type":"text","text":"assistant"}],"uuid":"old-shape-text"}
JSONL
  TRANSCRIPT="$transcript" node <<'NODE'
const { parseTranscript, normalizeAssistantContent } = require('./plugins/options-mode/hooks/stop');
const envelope = parseTranscript(process.env.TRANSCRIPT);
if (!envelope) throw new Error('missing assistant envelope');
if (envelope.uuid !== 'old-shape-text') throw new Error(`wrong envelope ${envelope.uuid}`);
const normalized = normalizeAssistantContent(envelope);
if (normalized.text !== 'legacy\nassistant') throw new Error(`bad text ${JSON.stringify(normalized.text)}`);
if (normalized.hasAskUserQuestion !== false) throw new Error('unexpected AskUserQuestion');
NODE
  pass test_old_shape_transcript_fallback
}

test_mixed_shape_old_after_real_picks_last() {
  local dir out transcript
  transcript="$PLUGIN_ROOT/tests/fixtures/transcripts/mixed-shape-old-after-real.jsonl"
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$transcript")"
  assert_stop_block test_mixed_shape_old_after_real_picks_last "$out"
}

test_stop_fs_error_fail_open() {
  local dir out
  dir="$(mktemp -d)"
  printf off > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-status-without-tag.jsonl" env OPTIONS_TEST_INJECT_FS_ERROR=1)"
  assert_stop_block test_stop_fs_error_fail_open "$out"
}

test_sanitize_reason_keeps_classifier_prefix_out() {
  node <<'NODE'
const { sanitizeReason } = require('./plugins/options-mode/hooks/stop');
const reason = sanitizeReason('\u001b[31mhello\u001b[0m\nworld');
if (reason !== 'hello world') throw new Error(`unexpected sanitized reason: ${reason}`);
const long = sanitizeReason('x'.repeat(260));
if (long.length !== 200) throw new Error(`unexpected cap: ${long.length}`);
if (long.startsWith('Use AskUserQuestion with concrete choices: ')) throw new Error('legacy prefix present');
NODE
  pass test_sanitize_reason_keeps_classifier_prefix_out
}

test_log_rotation() {
  local dir
  dir="$(mktemp -d)"
  CLAUDE_CONFIG_DIR="$dir" HOME="$dir/home" "$NODE_BIN" <<'NODE'
const fs = require('fs');
const path = require('path');
const { appendLog, MAX_LOG_BYTES } = require('./plugins/options-mode/hooks/config');
const logPath = path.join(process.env.CLAUDE_CONFIG_DIR, 'options.log');
fs.mkdirSync(process.env.CLAUDE_CONFIG_DIR, { recursive: true });
fs.writeFileSync(logPath, 'x'.repeat(MAX_LOG_BYTES));
appendLog('after rotation');
if (!fs.existsSync(`${logPath}.1`)) throw new Error('rotated log missing');
if (fs.readFileSync(logPath, 'utf8') !== 'after rotation\n') throw new Error('new log content mismatch');
NODE
  pass test_log_rotation
}

test_loop_counter_bail_at_6() {
  local dir out i
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  for i in 1 2 3 4 5; do
    out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/missing-uuid.jsonl")"
    OUT="$out" node -e 'const out=JSON.parse(process.env.OUT); if(out.decision!=="block") throw new Error("expected block")'
  done
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/missing-uuid.jsonl")"
  assert_empty_output test_loop_counter_bail_at_6 "$out"
  [[ "$(find "$dir" -name '.options-stop-counter-*' -print | wc -l)" == "0" ]] || fail test_loop_counter_bail_at_6 "counter file was not unlinked"
}

run_session_start_subagent() {
  local config_root="$1"
  local payload='{"hook_event_name":"SessionStart","source":"startup","agent_id":"sub-1"}'
  CLAUDE_CONFIG_DIR="$config_root" HOME="$config_root/home" PATH="/nonexistent" \
    "$NODE_BIN" "$PLUGIN_ROOT/hooks/session-start.js" <<<"$payload"
}

read_options_json() {
  local config_root="$1"
  CLAUDE_CONFIG_DIR="$config_root" "$NODE_BIN" -e '
const fs = require("fs");
const path = require("path");
const p = path.join(process.env.CLAUDE_CONFIG_DIR, "options.json");
process.stdout.write(fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "");
'
}

test_default_set_on_writes_options_json() {
  local dir out
  dir="$(mktemp -d)"
  out="$(run_user_prompt_submit "$dir" '/options-mode default on')"
  assert_block_reason test_default_set_on_writes_options_json_block "$out" 'options mode default: on'
  local content
  content="$(read_options_json "$dir")"
  [[ "$content" == '{"defaultMode":"on"}' ]] || fail test_default_set_on_writes_options_json "options.json contents wrong: $content"
  pass test_default_set_on_writes_options_json
}

test_default_set_off_overwrites() {
  local dir out
  dir="$(mktemp -d)"
  printf '%s' '{"otherKey":"keep"}' > "$dir/options.json"
  out="$(run_user_prompt_submit "$dir" '/options-mode default on')"
  assert_block_reason test_default_set_off_overwrites_on "$out" 'options mode default: on'
  out="$(run_user_prompt_submit "$dir" '/options-mode default off')"
  assert_block_reason test_default_set_off_overwrites_off "$out" 'options mode default: off'
  CONTENT="$(read_options_json "$dir")" node <<'NODE'
const obj = JSON.parse(process.env.CONTENT);
if (obj.defaultMode !== 'off') throw new Error(`defaultMode was ${obj.defaultMode}`);
if (obj.otherKey !== 'keep') throw new Error(`otherKey lost: ${JSON.stringify(obj)}`);
NODE
  pass test_default_set_off_overwrites
}

test_default_clear_removes_key() {
  local dir
  dir="$(mktemp -d)"
  run_user_prompt_submit "$dir" '/options-mode default on' >/dev/null
  [[ -f "$dir/options.json" ]] || fail test_default_clear_removes_key "options.json missing pre-clear"
  local out
  out="$(run_user_prompt_submit "$dir" '/options-mode default clear')"
  assert_block_reason test_default_clear_removes_key_block "$out" 'options mode default: cleared'
  [[ ! -e "$dir/options.json" ]] || fail test_default_clear_removes_key "options.json not unlinked"
  pass test_default_clear_removes_key
}

test_default_clear_preserves_other_keys() {
  local dir out
  dir="$(mktemp -d)"
  printf '%s' '{"otherKey":"keep","defaultMode":"on"}' > "$dir/options.json"
  out="$(run_user_prompt_submit "$dir" '/options-mode default clear')"
  assert_block_reason test_default_clear_preserves_other_keys_block "$out" 'options mode default: cleared'
  CONTENT="$(read_options_json "$dir")" node <<'NODE'
const obj = JSON.parse(process.env.CONTENT);
if ('defaultMode' in obj) throw new Error(`defaultMode survived: ${JSON.stringify(obj)}`);
if (obj.otherKey !== 'keep') throw new Error(`otherKey lost: ${JSON.stringify(obj)}`);
NODE
  pass test_default_clear_preserves_other_keys
}

test_default_status_reports_unset() {
  local dir out
  dir="$(mktemp -d)"
  out="$(run_user_prompt_submit "$dir" '/options-mode default status')"
  assert_block_reason test_default_status_reports_unset_block "$out" 'options mode default: unset'

  out="$(run_user_prompt_submit "$dir" '/options-mode default')"
  assert_block_reason test_default_status_reports_unset_alias "$out" 'options mode default: unset'
}

test_default_status_reports_on_after_set() {
  local dir out
  dir="$(mktemp -d)"
  run_user_prompt_submit "$dir" '/options-mode default on' >/dev/null
  out="$(run_user_prompt_submit "$dir" '/options-mode default status')"
  assert_block_reason test_default_status_reports_on_after_set "$out" 'options mode default: on'
}

test_session_flag_overrides_default() {
  local dir out
  dir="$(mktemp -d)"
  run_user_prompt_submit "$dir" '/options-mode default on' >/dev/null
  out="$(run_user_prompt_submit "$dir" '/options-mode off')"
  assert_block_reason test_session_flag_overrides_default_off "$out" 'options mode: off'
  out="$(run_user_prompt_submit "$dir" '/options-mode status')"
  assert_block_reason test_session_flag_overrides_default_status "$out" 'options mode: off (session=off, default=on)'

  CLAUDE_CONFIG_DIR="$dir" node <<'NODE'
const { isOptionsActive } = require('./plugins/options-mode/hooks/config');
if (isOptionsActive(undefined) !== false) throw new Error('expected isOptionsActive=false when session flag off overrides default on');
NODE
  pass test_session_flag_overrides_default_isactive
}

test_default_on_with_no_session_flag_activates() {
  local dir out sid="sess-default-activates"
  dir="$(mktemp -d)"
  run_user_prompt_submit "$dir" '/options-mode default on' >/dev/null

  CLAUDE_CONFIG_DIR="$dir" SID="$sid" node <<'NODE'
const { isOptionsActive } = require('./plugins/options-mode/hooks/config');
if (isOptionsActive(process.env.SID) !== true) throw new Error('expected isOptionsActive=true with default=on, no session flag');
NODE

  out="$(run_session_start startup "$dir" "$sid")"
  [[ "$out" == *"OPTIONS MODE ACTIVE"* ]] || fail test_default_on_with_no_session_flag_activates "SessionStart did not emit rules with default=on"
  [[ "$out" == *"AskUserQuestion choice prompt"* ]] || fail test_default_on_with_no_session_flag_activates "missing AskUserQuestion anchor"
  pass test_default_on_with_no_session_flag_activates
}

test_default_subagent_no_inject() {
  local dir out
  dir="$(mktemp -d)"
  run_user_prompt_submit "$dir" '/options-mode default on' >/dev/null
  out="$(run_session_start_subagent "$dir")"
  [[ -z "$out" ]] || fail test_default_subagent_no_inject "subagent SessionStart emitted with default=on: $out"
  pass test_default_subagent_no_inject
}

test_env_overrides_file_default() {
  local dir out
  dir="$(mktemp -d)"
  printf '%s' '{"defaultMode":"off"}' > "$dir/options.json"
  out="$(CLAUDE_CONFIG_DIR="$dir" HOME="$dir/home" OPTIONS_DEFAULT_MODE=on \
    node "$PLUGIN_ROOT/hooks/user-prompt-submit.js" <<<'{"hook_event_name":"UserPromptSubmit","prompt":"/options-mode default status"}')"
  assert_block_reason test_env_overrides_file_default_status "$out" 'options mode default: on'

  CLAUDE_CONFIG_DIR="$dir" OPTIONS_DEFAULT_MODE=on node <<'NODE'
const { getDefaultMode, getDefaultModeRaw } = require('./plugins/options-mode/hooks/config');
if (getDefaultMode() !== 'on') throw new Error(`getDefaultMode was ${getDefaultMode()}`);
if (getDefaultModeRaw() !== 'on') throw new Error(`getDefaultModeRaw was ${getDefaultModeRaw()}`);
NODE
  pass test_env_overrides_file_default
}

test_bad_default_subarg() {
  local dir out
  dir="$(mktemp -d)"
  out="$(run_user_prompt_submit "$dir" '/options-mode default bogus')"
  assert_block_reason test_bad_default_subarg_block "$out" 'options mode: usage /options-mode on|off|strict|status|default [on|off|strict|clear|status]'
  [[ ! -e "$dir/options.json" ]] || fail test_bad_default_subarg "bogus subarg created options.json"
  pass test_bad_default_subarg
}

write_strict_transcript() {
  # writes a Claude Code assistant transcript with the given inline text to $1
  local out="$1" text="$2"
  TRANSCRIPT="$out" TEXT="$text" "$NODE_BIN" <<'NODE'
const fs = require('fs');
const envelope = {
  type: 'assistant',
  message: { role: 'assistant', content: [{ type: 'text', text: process.env.TEXT }] },
  uuid: `assistant-strict-${Buffer.from(process.env.TEXT).toString('base64').slice(0, 16)}`
};
fs.writeFileSync(process.env.TRANSCRIPT, JSON.stringify(envelope) + '\n');
NODE
}

write_copilot_transcript() {
  # writes a Copilot events.jsonl with one assistant.message carrying the given content to $1
  local out="$1" content="$2"
  TRANSCRIPT="$out" CONTENT="$content" "$NODE_BIN" <<'NODE'
const fs = require('fs');
const evt = {
  type: 'assistant.message',
  id: `copilot-strict-${Buffer.from(process.env.CONTENT).toString('base64').slice(0, 16)}`,
  data: { content: process.env.CONTENT, toolRequests: [] }
};
fs.writeFileSync(process.env.TRANSCRIPT, JSON.stringify(evt) + '\n');
NODE
}

run_copilot_agent_stop() {
  local copilot_root="$1" transcript="$2"
  if command -v cygpath >/dev/null 2>&1; then transcript="$(cygpath -m "$transcript")"; fi
  COPILOT_CONFIG_DIR="$copilot_root" HOME="$copilot_root/home" \
    "$NODE_BIN" "$PLUGIN_ROOT/hooks/copilot-agent-stop.js" <<JSON
{"timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp","sessionId":"sess-copilot-strict","transcriptPath":"$transcript","stopReason":"end_turn"}
JSON
}

test_get_options_mode_returns_strict() {
  local dir sid="sess-strict-mode"
  local flag_name
  flag_name="$(session_flag_name "$sid")"
  dir="$(mktemp -d)"
  printf strict > "$dir/$flag_name"
  CLAUDE_CONFIG_DIR="$dir" SID="$sid" node <<'NODE'
const { getOptionsMode, isOptionsActive } = require('./plugins/options-mode/hooks/config');
if (getOptionsMode(process.env.SID) !== 'strict') throw new Error(`expected strict, got ${getOptionsMode(process.env.SID)}`);
if (isOptionsActive(process.env.SID) !== true) throw new Error('isOptionsActive should be true for strict');
NODE
  pass test_get_options_mode_returns_strict
}

test_get_options_mode_env_override() {
  local dir
  dir="$(mktemp -d)"
  CLAUDE_CONFIG_DIR="$dir" OPTIONS_DEFAULT_MODE=strict node <<'NODE'
const { getOptionsMode } = require('./plugins/options-mode/hooks/config');
if (getOptionsMode() !== 'strict') throw new Error(`expected strict, got ${getOptionsMode()}`);
NODE
  pass test_get_options_mode_env_override
}

assert_stop_block_strict() {
  local name="$1" out="$2"
  OUT="$out" node <<'NODE'
const { BLOCK_REASON_STRICT } = require('./plugins/options-mode/hooks/stop');
const out = JSON.parse(process.env.OUT);
if (out.decision !== 'block') throw new Error(`decision was ${out.decision}`);
if (out.reason !== BLOCK_REASON_STRICT) throw new Error(`reason was ${out.reason}`);
if (out.reason.length > 200) throw new Error(`reason length ${out.reason.length}`);
NODE
  pass "$name"
}

test_strict_no_question_tag_blocks() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-active"
  transcript="$(mktemp)"
  write_strict_transcript "$transcript" $'Done with the work.\n<options-mode>no-question</options-mode>'
  out="$(run_stop_json "$dir" "$transcript")"
  assert_stop_block_strict test_strict_no_question_tag_blocks "$out"
}

test_strict_background_task_tag_passes() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-active"
  transcript="$(mktemp)"
  write_strict_transcript "$transcript" $'Build still running.\n<options-mode>background-task</options-mode>'
  out="$(run_stop_json "$dir" "$transcript")"
  assert_empty_output test_strict_background_task_tag_passes "$out"
}

test_strict_background_agent_tag_passes() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-active"
  transcript="$(mktemp)"
  write_strict_transcript "$transcript" $'Agent still working.\n<options-mode>background-agent</options-mode>'
  out="$(run_stop_json "$dir" "$transcript")"
  assert_empty_output test_strict_background_agent_tag_passes "$out"
}

test_strict_AskUserQuestion_passes() {
  local dir out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-active"
  out="$(run_stop_json "$dir" "$PLUGIN_ROOT/tests/fixtures/transcripts/last-msg-real-askuserquestion.jsonl")"
  assert_empty_output test_strict_AskUserQuestion_passes "$out"
}

test_strict_block_reason_mentions_bg_tags() {
  node <<'NODE'
const { BLOCK_REASON_STRICT } = require('./plugins/options-mode/hooks/stop');
if (BLOCK_REASON_STRICT.indexOf('<options-mode>background-task</options-mode>') === -1) {
  throw new Error('strict block reason missing background-task tag');
}
if (BLOCK_REASON_STRICT.indexOf('<options-mode>background-agent</options-mode>') === -1) {
  throw new Error('strict block reason missing background-agent tag');
}
if (BLOCK_REASON_STRICT.indexOf('AskUserQuestion') === -1) {
  throw new Error('strict block reason missing AskUserQuestion');
}
NODE
  pass test_strict_block_reason_mentions_bg_tags
}

test_on_mode_no_question_tag_still_passes() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  transcript="$(mktemp)"
  write_strict_transcript "$transcript" $'Done.\n<options-mode>no-question</options-mode>'
  out="$(run_stop_json "$dir" "$transcript")"
  assert_empty_output test_on_mode_no_question_tag_still_passes "$out"
}

test_on_mode_background_task_tag_passes() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  transcript="$(mktemp)"
  write_strict_transcript "$transcript" $'Build polling.\n<options-mode>background-task</options-mode>'
  out="$(run_stop_json "$dir" "$transcript")"
  assert_empty_output test_on_mode_background_task_tag_passes "$out"
}

test_on_mode_background_agent_tag_passes() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-active"
  transcript="$(mktemp)"
  write_strict_transcript "$transcript" $'Agent polling.\n<options-mode>background-agent</options-mode>'
  out="$(run_stop_json "$dir" "$transcript")"
  assert_empty_output test_on_mode_background_agent_tag_passes "$out"
}

test_copilot_strict_blocks_no_question_tag() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-mode-active"
  transcript="$(mktemp)"
  write_copilot_transcript "$transcript" $'Done with work.\n[//]: # (options-mode-no-question)'
  out="$(run_copilot_agent_stop "$dir" "$transcript")"
  OUT="$out" node <<'NODE'
const out = JSON.parse(process.env.OUT);
if (out.decision !== 'block') throw new Error(`decision was ${out.decision}`);
if (out.reason.indexOf('background-task') === -1) throw new Error('strict copilot reason missing background-task');
if (out.reason.indexOf('background-agent') === -1) throw new Error('strict copilot reason missing background-agent');
NODE
  pass test_copilot_strict_blocks_no_question_tag
}

test_copilot_strict_passes_background_task() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-mode-active"
  transcript="$(mktemp)"
  write_copilot_transcript "$transcript" $'Build polling.\n[//]: # (options-mode-background-task)'
  out="$(run_copilot_agent_stop "$dir" "$transcript")"
  [[ "$out" == '{}' ]] || fail test_copilot_strict_passes_background_task "expected pass {}, got: $out"
  pass test_copilot_strict_passes_background_task
}

test_copilot_strict_passes_background_agent() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf strict > "$dir/.options-mode-active"
  transcript="$(mktemp)"
  write_copilot_transcript "$transcript" $'Agent polling.\n[//]: # (options-mode-background-agent)'
  out="$(run_copilot_agent_stop "$dir" "$transcript")"
  [[ "$out" == '{}' ]] || fail test_copilot_strict_passes_background_agent "expected pass {}, got: $out"
  pass test_copilot_strict_passes_background_agent
}

test_copilot_on_no_question_tag_regression() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-mode-active"
  transcript="$(mktemp)"
  write_copilot_transcript "$transcript" $'Done.\n[//]: # (options-mode-no-question)'
  out="$(run_copilot_agent_stop "$dir" "$transcript")"
  [[ "$out" == '{}' ]] || fail test_copilot_on_no_question_tag_regression "on-mode regression: expected {}, got: $out"
  pass test_copilot_on_no_question_tag_regression
}

test_copilot_on_background_task_tag_passes() {
  local dir transcript out
  dir="$(mktemp -d)"
  printf on > "$dir/.options-mode-active"
  transcript="$(mktemp)"
  write_copilot_transcript "$transcript" $'Build polling.\n[//]: # (options-mode-background-task)'
  out="$(run_copilot_agent_stop "$dir" "$transcript")"
  [[ "$out" == '{}' ]] || fail test_copilot_on_background_task_tag_passes "expected pass {}, got: $out"
  pass test_copilot_on_background_task_tag_passes
}

test_codex_hooks_no_strict_leak() {
  node <<'NODE'
const fs = require('fs');
const hooks = JSON.parse(fs.readFileSync('.codex/hooks.json', 'utf8'));
const entry = hooks.hooks.SessionStart.flatMap((item) => item.hooks || []).find((hook) => hook._owner === 'options-mode');
if (!entry) throw new Error('options-mode hook entry missing');
if (entry.command.indexOf('background-task') !== -1) throw new Error('strict bg-task tag leaked into .codex/hooks.json');
if (entry.command.indexOf('background-agent') !== -1) throw new Error('strict bg-agent tag leaked into .codex/hooks.json');
if (entry.command.indexOf('OPTIONS MODE ACTIVE (strict)') !== -1) throw new Error('strict header leaked into .codex/hooks.json');
NODE
  pass test_codex_hooks_no_strict_leak
}

test_user_prompt_submit_strict_writes_flag() {
  local dir out
  dir="$(mktemp -d)"
  out="$(run_user_prompt_submit "$dir" '/options-mode strict')"
  assert_block_reason test_user_prompt_submit_strict_writes_flag_block "$out" 'options mode: strict'
  [[ "$(cat "$dir/.options-active")" == "strict" ]] || fail test_user_prompt_submit_strict_writes_flag "strict did not write flag"
  pass test_user_prompt_submit_strict_writes_flag
}

test_default_set_strict_writes_options_json() {
  local dir out
  dir="$(mktemp -d)"
  out="$(run_user_prompt_submit "$dir" '/options-mode default strict')"
  assert_block_reason test_default_set_strict_writes_options_json_block "$out" 'options mode default: strict'
  local content
  content="$(read_options_json "$dir")"
  [[ "$content" == '{"defaultMode":"strict"}' ]] || fail test_default_set_strict_writes_options_json "options.json wrong: $content"
  pass test_default_set_strict_writes_options_json
}

test_user_prompt_submit_status_strict() {
  local dir out
  dir="$(mktemp -d)"
  run_user_prompt_submit "$dir" '/options-mode strict' >/dev/null
  out="$(run_user_prompt_submit "$dir" '/options-mode status')"
  assert_block_reason test_user_prompt_submit_status_strict "$out" 'options mode: strict (session=strict, default=unset)'
}

test_user_prompt_submit_usage_includes_strict() {
  local dir out
  dir="$(mktemp -d)"
  out="$(run_user_prompt_submit "$dir" '/options-mode bogus')"
  assert_block_reason test_user_prompt_submit_usage_includes_strict "$out" 'options mode: usage /options-mode on|off|strict|status|default [on|off|strict|clear|status]'
}

test_statusline_bash_strict() {
  local dir out sid="sess-statusline-strict-bash"
  local flag_name
  flag_name="$(session_flag_name "$sid")"

  # 1. Per-session flag = strict -> [OPTIONS MODE: strict]
  dir="$(mktemp -d)"
  printf strict > "$dir/$flag_name"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE: strict]"* ]] || fail test_statusline_bash_strict "per-session strict did not render: '$out'"

  # 2. options.json defaultMode=strict -> [OPTIONS MODE: strict]
  dir="$(mktemp -d)"
  printf '%s' '{"defaultMode":"strict"}' > "$dir/options.json"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE: strict]"* ]] || fail test_statusline_bash_strict "default=strict did not render: '$out'"

  # 3. OPTIONS_DEFAULT_MODE=strict env override
  dir="$(mktemp -d)"
  out="$(run_statusline_bash "$dir" "{\"session_id\":\"$sid\"}" env OPTIONS_DEFAULT_MODE=strict)"
  [[ "$out" == *"[OPTIONS MODE: strict]"* ]] || fail test_statusline_bash_strict "env strict did not render: '$out'"

  pass test_statusline_bash_strict
}

test_statusline_powershell_strict() {
  local ps_bin dir out sid="sess-statusline-strict-ps"
  local flag_name
  ps_bin="$(command -v pwsh || command -v powershell || true)"
  if [[ -z "$ps_bin" ]]; then
    pass test_statusline_powershell_strict_skipped
    return
  fi
  flag_name="$(session_flag_name "$sid")"

  dir="$(mktemp -d)"
  printf strict > "$dir/$flag_name"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE: strict]"* ]] || fail test_statusline_powershell_strict "per-session strict did not render: '$out'"

  dir="$(mktemp -d)"
  printf '%s' '{"defaultMode":"strict"}' > "$dir/options.json"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}")"
  [[ "$out" == *"[OPTIONS MODE: strict]"* ]] || fail test_statusline_powershell_strict "default=strict did not render: '$out'"

  dir="$(mktemp -d)"
  out="$(run_statusline_pwsh "$ps_bin" "$dir" "{\"session_id\":\"$sid\"}" env OPTIONS_DEFAULT_MODE=strict)"
  [[ "$out" == *"[OPTIONS MODE: strict]"* ]] || fail test_statusline_powershell_strict "env strict did not render: '$out'"

  pass test_statusline_powershell_strict
}

test_session_start_strict_emits_strict_rules() {
  local sid="sess-strict-rules" dir out
  local flag_name
  flag_name="$(session_flag_name "$sid")"
  dir="$(mktemp -d)"
  printf strict > "$dir/$flag_name"
  out="$(run_session_start startup "$dir" "$sid")"
  [[ "$out" == *"<options-mode>background-task</options-mode>"* ]] || fail test_session_start_strict_emits_strict_rules "missing background-task anchor"
  [[ "$out" == *"<options-mode>background-agent</options-mode>"* ]] || fail test_session_start_strict_emits_strict_rules "missing background-agent anchor"
  [[ "$out" == *"OPTIONS MODE ACTIVE"* ]] || fail test_session_start_strict_emits_strict_rules "missing active anchor"
  [[ "$out" == *"strict"* ]] || fail test_session_start_strict_emits_strict_rules "missing strict keyword"
  pass test_session_start_strict_emits_strict_rules
}

test_required_fixtures_exist() {
  local rel
  for rel in \
    transcripts/last-msg-question.jsonl \
    transcripts/last-msg-question-array.jsonl \
    transcripts/last-msg-status.jsonl \
    transcripts/last-msg-askuserquestion.jsonl \
    transcripts/last-msg-with-tag.jsonl \
    transcripts/last-msg-status-without-tag.jsonl \
    transcripts/last-msg-real-askuserquestion.jsonl \
    transcripts/last-msg-ralph-polling-with-tag.jsonl \
    transcripts/last-msg-old-shape-question.jsonl \
    transcripts/last-msg-old-shape-status.jsonl \
    transcripts/missing-uuid.jsonl \
    transcripts/malformed.jsonl \
    transcripts/no-assistant.jsonl \
    transcripts/multiple-assistant-entries.jsonl \
    transcripts/mixed-shape-old-after-real.jsonl \
    stdin/stop-active.json \
    stdin/stop-subagent.json \
    stdin/stop-flag-off.json \
    stdin/stop-no-transcript.json \
    stdin/stop-smoke-askuserquestion.json \
    stdin/stop-smoke-tagged.json \
    stdin/stop-smoke-tagless.json \
    stdin/ups-options-mode-on.json \
    stdin/ups-options-mode-off.json \
    stdin/ups-options-mode-status.json \
    stdin/ups-options-mode-foo.json; do
    [[ -f "$PLUGIN_ROOT/tests/fixtures/$rel" ]] || fail test_required_fixtures_exist "missing $rel"
  done
  pass test_required_fixtures_exist
}

cd "$ROOT"
test_codex_plugin_interface_fields
test_copilot_skills_dir_renamed
test_codex_plugin_skills_field
test_escape_for_bash_single_quote
test_rule_text_sync
test_codex_config_toml
test_codex_hook_replay
test_docs_presence
test_config_exports
test_hooks_json_wiring
test_session_start_emits_rules_when_active
test_session_start_default_off_omits_rules
test_session_start_preserves_off
test_per_session_isolation
test_user_prompt_submit_commands
test_default_set_on_writes_options_json
test_default_set_off_overwrites
test_default_clear_removes_key
test_default_clear_preserves_other_keys
test_default_status_reports_unset
test_default_status_reports_on_after_set
test_session_flag_overrides_default
test_default_on_with_no_session_flag_activates
test_default_subagent_no_inject
test_env_overrides_file_default
test_bad_default_subarg
test_statusline_bash
test_statusline_powershell
test_statusline_shellcheck
test_required_fixtures_exist
test_stop_short_circuits
test_tag_present_skip
test_tag_absent_block
test_tag_substring_positions
test_askuserquestion_present_skip
test_offline_smoke_cases
test_ralph_polling_with_tag_skip
test_off_flag_bypass
test_subagent_skip
test_multiple_assistant_entries
test_old_shape_fixture_fallbacks
test_real_shape_transcript_parse
test_old_shape_transcript_fallback
test_mixed_shape_old_after_real_picks_last
test_stop_fs_error_fail_open
test_sanitize_reason_keeps_classifier_prefix_out
test_loop_counter_bail_at_6
test_log_rotation
test_get_options_mode_returns_strict
test_get_options_mode_env_override
test_strict_no_question_tag_blocks
test_strict_background_task_tag_passes
test_strict_background_agent_tag_passes
test_strict_AskUserQuestion_passes
test_strict_block_reason_mentions_bg_tags
test_on_mode_no_question_tag_still_passes
test_on_mode_background_task_tag_passes
test_on_mode_background_agent_tag_passes
test_copilot_strict_blocks_no_question_tag
test_copilot_strict_passes_background_task
test_copilot_strict_passes_background_agent
test_copilot_on_no_question_tag_regression
test_copilot_on_background_task_tag_passes
test_codex_hooks_no_strict_leak
test_user_prompt_submit_strict_writes_flag
test_default_set_strict_writes_options_json
test_user_prompt_submit_status_strict
test_user_prompt_submit_usage_includes_strict
test_statusline_bash_strict
test_statusline_powershell_strict
test_session_start_strict_emits_strict_rules
