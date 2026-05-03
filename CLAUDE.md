# Options Mode Plugin

Options Mode is a hook-only plugin. Runtime code is CommonJS under `hooks/`; tests live in `tests/run.sh` and must stay offline/deterministic by using isolated `CLAUDE_CONFIG_DIR` and `HOME` roots.

## v0.9.0 Migration Note

Options Mode v0.9.0 hides the `options-mode` skill from the Claude Code surface and renames the statusline badge from `[OPTIONS]` to `[OPTIONS MODE]`.

The skill move is forced by a Claude Code routing change: `/<plugin>:<skill>` is now resolved as a direct Skill-tool invocation that does not honor `UserPromptSubmit` block decisions, so `/options-mode:options-mode on` no longer flows through `hooks/user-prompt-submit.js` and could not toggle the per-session flag. Previously (Claude Code <= 2.1.x at some prior point) UPS did intercept that form. To restore the safety boundary, the skill directory moved from `plugins/options-mode/skills/` to `plugins/options-mode/.codex-plugin/skills/` so Claude Code's `<plugin-root>/skills/` scan finds nothing; only Codex consumers (which read `.codex-plugin/plugin.json::skills`) still see it. `test_codex_plugin_skills_field` enforces the invariant on both sides — codex skill exists at the new path AND `<plugin-root>/skills/` does not exist. Users must type the bare `/options-mode on|off|status|default ...` form for Claude Code; the slash-namespaced form is no longer reachable in Claude Code. Codex behavior is unchanged.

The badge rename is cosmetic: `hooks/options-mode-statusline.{sh,ps1}` and `tests/run.sh` now emit and assert `[OPTIONS MODE]` to read naturally next to other "mode" badges (e.g. `[CAVEMAN]`). Bump from `0.8.0` to `0.9.0` covers both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, plus the three marketplace indexes.

## v0.8.0 Migration Note

Options Mode v0.8.0 makes the statusline session-aware, global-default-aware, and silent-when-off. The scripts at `hooks/options-mode-statusline.{sh,ps1}` now read `session_id` from stdin JSON (Claude Code passes `{session_id, model, workspace, transcript_path, ...}` to statusLine commands), compute the per-session flag at `<configRoot>/.options-active-<sha256(session_id)[0:32]>`, and fall back to `<configRoot>/options.json` `defaultMode` (with `OPTIONS_DEFAULT_MODE` env taking precedence over the file). Effective-mode logic mirrors `hooks/config.js::isOptionsActive()` exactly.

The legacy single-file path `<configRoot>/.options-active` is consulted only as a back-compat fallback when stdin lacks `session_id` — same boundary as `getFlagPath()` in `hooks/config.js`. The `[OPTIONS:OFF]` rendering is deliberately removed: the badge appears only when the effective mode is `on`, matching the caveman pattern. Bump from `0.7.0` to `0.8.0` covers both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, plus the three marketplace indexes.

## v0.7.0 Migration Note

Options Mode v0.7.0 hard-renames the Stop-hook bypass tag from `<options-mode>continue</options-mode>` to `<options-mode>no-question</options-mode>`. The exported constant `OPTIONS_CONTINUE_TAG` becomes `OPTIONS_NO_QUESTION_TAG` (same value semantics, new identifier). No backward-compat alias: any prose still emitting the legacy tag will be blocked by `stop.js` until the model self-corrects (block-then-fail-open after five misses still applies, see Loop Counter).

The new name asserts the per-turn invariant ("this turn is not a question") rather than the prior `continue` semantic, which read as misleading on terminal turns. A second `done` tag was considered and explicitly rejected during review because (a) Stop-hook semantics are binary so a second tag is decorative, and (b) `<options-mode>done</options-mode>` would collide with Ralph's `<ralph-orchestrator>COMPLETE</ralph-orchestrator>` terminal-marker convention watched by `/loop` dynamic mode and Monitor flows.

Byte-synced surfaces updated in lockstep: `.codex/hooks.json` inline command, `plugins/options-mode/tests/run.sh` (test_codex_hook_replay, test_session_start_emits_rules_when_active, test_docs_presence, test_config_exports, test_tag_substring_positions), and the two tagged transcript fixtures under `plugins/options-mode/tests/fixtures/transcripts/`. The Ralph cooperative emit at `plugins/ralph/CLAUDE.md` is updated to match. Plugin manifests `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` plus the three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`) bump from `0.6.0` to `0.7.0`.

## v0.5.0 Migration Note

Options Mode v0.5.0 removed the Stop-hook classifier and replaced it with a deterministic tag protocol. Stop enforcement no longer spawns `codex`, reads classifier output, or honors `OPTIONS_CLASSIFIER_*` / `OPTIONS_CONFIDENCE_THRESHOLD` configuration. The SessionStart Codex login health check was also removed.

The removed classifier sentinels are no longer written: `.options-codex-missing-warn`, `.options-codex-error-warn`, `.options-codex-auth-warn`, and `.options-codex-diagnostics`. Retained files are `.options-active*`, `.options-statusline-warn`, `.options-stop-counter-*`, and `options.log`.

The new failure mode is tagless drift: when the last assistant turn has plain prose without `AskUserQuestion` and without `<options-mode>no-question</options-mode>`, the Stop hook blocks up to five times. On the sixth consecutive miss for the same `(transcript_path, last-assistant-id)` pair, it logs a WARN, removes that counter, and fails open.

## Options Rules Anchors

Harness checks use these stable substrings from `hooks/config.js::OPTIONS_RULES_TEXT`: `OPTIONS MODE ACTIVE`, `AskUserQuestion choice prompt`, `Recommended`, `mutually exclusive labels`, and `<options-mode>no-question</options-mode>`. Update the harness if the canonical rules text changes.

## Flag Contract

As of v0.4.0 the mode flag is **per session**: `<configRoot>/.options-active-<sha256(session_id)[0:32]>`, containing literal `on` or `off`. The legacy single-machine path `<configRoot>/.options-active` is retained as the back-compat fallback when a hook receives no `session_id` (for older Claude Code builds and for repo-level harness scripts that do not propagate the session id). The default mode is `off` (was `on` through v0.3.0): a session with no flag file falls back to the global default (see Global Default below) and is inactive when that resolves to `off`. `/options-mode on` writes the per-session flag, so each session opts in independently. Read failure semantics differ from missing semantics: `_readFlagInternal()` distinguishes ENOENT (returns `null`, defers to `getDefaultMode()`) from real read errors (rethrown so `isOptionsActive()` fails open to active). The legacy intentional-divergence-from-caveman naming (`.options-*` temp-file prefixes, options-mode-specific error text) is unchanged.

`safeWriteFlag()` performs a `lstatSync` symlink check on the destination, then writes a temp file with `O_EXCL | O_NOFOLLOW` and `renameSync`s it into place. There is a TOCTOU window between the symlink check and the rename: `renameSync` does not carry `O_NOFOLLOW` semantics on the destination, so a concurrent attacker with write access to `flagDir` could replace `flagPath` with a symlink between the two syscalls. This is accepted as out-of-threat-model — `flagDir` is `~/.claude` (or a user-controlled `CLAUDE_CONFIG_DIR`), and a local attacker with write access to that directory already has full control of Claude Code's config. The acceptance is cross-referenced from the in-code comment in `hooks/config.js::safeWriteFlag()`. Rename failures with `EEXIST`/`EBUSY`/`EACCES` are logged via `appendLog` to `<configRoot>/options.log` so race attempts are observable.

Auxiliary files under `<configRoot>` — the SessionStart statusline sentinel (`.options-statusline-warn`), the per-`(transcript, uuid)` Stop-hook loop counters (`.options-stop-counter-<sha256>`), and the rotating audit log (`options.log`) — are written via plain `fs.writeFileSync`/`fs.appendFileSync` without `O_NOFOLLOW` or `lstat` pre-checks, so they are not symlink-safe in the way `safeWriteFlag()` is for `.options-active`. This asymmetry is intentional and shares the same threat-model boundary as the flag file: a local attacker who can write to `<configRoot>` already controls Claude Code's entire configuration surface (settings, hooks, plugins) and has full game-over on the host, so hardening the auxiliary writers against symlink redirection would not raise the attacker bar. A full `safeWriteFile` helper refactor is therefore deferred as over-engineering for v1; the asymmetry is documented here so future security reviews can find the explicit acceptance rather than re-discovering it.

## SessionStart Contract

`hooks/session-start.js` emits `OPTIONS_RULES_TEXT` to stdout for `startup|resume|compact|clear`, except in subagents and except when the per-session flag is `off` or missing (default-off). The `clear` matcher is required so `/clear` re-injects the rules for sessions that already have `on` written instead of leaving them ruleless until the next prompt. SessionStart never auto-writes a flag — the file only exists once `/options-mode on` (or `off`) has been issued for that session, so each session opts in independently and an explicit `/options-mode off` survives restarts, compaction, and `/clear`.

The statusline reminder is gated by `<configRoot>/.options-statusline-warn` and must include both snippets:

```json
"statusLine": { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/options-mode-statusline.sh" }
```

```json
"statusLine": { "type": "command", "command": "pwsh -File ${CLAUDE_PLUGIN_ROOT}/hooks/options-mode-statusline.ps1" }
```

> **Migration note:** if you copy-pasted the old `choices-statusline.{sh,ps1}` snippets into `~/.claude/settings.json`, the script files were renamed in this rebrand. Update the snippet to the `options-mode-statusline.{sh,ps1}` paths above or the statusline command will fail silently.

## Global Default

`<configRoot>/options.json` holds the user-managed global default mode for sessions that have no per-session flag set. Schema is a plain JSON object with a single relevant key:

```json
{ "defaultMode": "on" }
```

`defaultMode` accepts `"on"` or `"off"`; any other value is ignored. `setDefaultMode(mode)` and `clearDefaultMode()` perform an atomic read-modify-write (preserving any other keys callers may have stored) using the same `lstat` symlink check + `O_EXCL | O_NOFOLLOW` temp + `renameSync` pattern as `safeWriteFlag()`. The same TOCTOU acceptance applies — see Flag Contract above and the in-code comment in `_writeConfigJsonAtomic()`. `clearDefaultMode()` deletes the key and `unlinkSync`s the file when the resulting object is empty so `~/.claude/options.json` does not linger as `{}`.

`getDefaultModeRaw()` returns `'on' | 'off' | null`, distinguishing "explicitly set" from "unset". `getDefaultMode()` is a thin wrapper that maps `null` to `'off'` for callers that just want the effective default. The status report uses `getDefaultModeRaw()` so it can render `unset` instead of fabricating an `off`.

Precedence inside `getDefaultMode()` is **env → file → off**. The `OPTIONS_DEFAULT_MODE` env var is the escape hatch and overrides the file value; the `/options-mode default` slash command writes only the file. With both set, the displayed default in `/options-mode status` reflects the resolved precedence (env wins) rather than the raw file value — this is intentional so the status line tracks the mode users will actually experience.

If `options.json` is corrupt, `setDefaultMode()` overwrites it with a valid JSON object containing only `defaultMode`; `clearDefaultMode()` unlinks it. Neither helper surfaces parse errors to the user mid-slash-command.

## Statusline Contract

`hooks/options-mode-statusline.{sh,ps1}` are standalone scripts (no Node dependency at statusline runtime) that mirror `hooks/config.js::isOptionsActive()` for rendering only. Claude Code invokes the configured `statusLine.command` with a JSON payload on stdin shaped like `{"session_id": "...", "model": {...}, "workspace": {...}, "transcript_path": "...", ...}`. Statuslines that ignore stdin silently fall through to the legacy fallback path and render incorrectly on per-session sessions.

Decision flow:

1. Parse stdin as JSON and extract `session_id` (PowerShell uses `ConvertFrom-Json`; bash prefers `jq` and falls back to a `grep -Eo` extractor since `jq` is not guaranteed on Git Bash).
2. If `session_id` is present, compute `<configRoot>/.options-active-<sha256(session_id)[0:32]>` and read it via the same safety guards as the hooks (refuse symlinks/reparse points, cap at 64 bytes, lowercase + `[a-z0-9-]` whitelist, accept only `on`/`off`).
3. If `session_id` is absent, fall back to the legacy `<configRoot>/.options-active` path — same back-compat boundary as `getFlagPath()`.
4. If neither flag yields a valid mode, defer to `getDefaultMode()` precedence: `OPTIONS_DEFAULT_MODE` env var → `<configRoot>/options.json::defaultMode` → unset.
5. Render `[OPTIONS MODE]` in ANSI 172 (orange) only when the effective mode resolves to `on`; exit 0 silently for `off`, unset, parse errors, missing files, or any other failure (fail-silent-on-error policy).

The badge is intentionally invisible when the effective mode is `off`, matching the caveman pattern. Do not re-introduce `[OPTIONS:OFF]`. The portable sha256 helper in `options-mode-statusline.sh` tries `sha256sum` first (Git Bash/Linux) and falls back to `shasum -a 256` (macOS); statusline tests must not depend on `jq` being installed.

## UserPromptSubmit Contract

`hooks/user-prompt-submit.js` owns `/options-mode on|off|status` and `/options-mode default [on|off|clear|status]`. Per-session subcommands write literal flag values and emit `{"decision":"block","reason":"options mode: <state>"}`. The `default` subcommand variants emit `options mode default: <on|off|cleared|unset>` (with `default` alone aliasing to `default status`). The status report includes session and default state in a parseable suffix:

```
options mode: <effective> (session=<on|off|unset>, default=<on|off|unset>)
```

The leading `options mode:` token is preserved for log/grep parsers; only the parenthetical is new. Bad subcommands return the usage line `options mode: usage /options-mode on|off|status|default [on|off|clear|status]`.

## Stop-Hook Contract

`hooks/stop.js` exits 0 with empty stdout for all fail-open and short-circuit cases. The decision flow is:

1. Exit empty when `stop_hook_active === true` (recursive Stop call).
2. Exit empty when input has `agent_id` or `agent_type` (subagent invocation).
3. Exit empty when `isOptionsActive(session_id)` is false (mode is off or missing).
4. Exit empty when `transcript_path` is missing or the transcript file does not exist.
5. Parse the transcript from the end and fail open when no valid assistant envelope is found.
6. Normalize the last assistant content and exit empty when it contains an `AskUserQuestion` `tool_use` block.
7. Exit empty when normalized assistant text is blank or contains the literal `<options-mode>no-question</options-mode>` substring.
8. Increment the loop counter for the `(transcript_path, last-assistant-id)` pair; on the sixth consecutive miss, log a WARN, unlink the counter, and fail open.
9. Emit `{"decision":"block","reason":"Add <options-mode>no-question</options-mode> tag if this turn is not asking the user, or use AskUserQuestion with concrete choices."}`.

Transcript parsing walks valid JSONL envelopes from the end, chooses the last real Claude Code assistant envelope (`type: "assistant"` with `message.content`) first, then falls back to the legacy fixture shape (`role: "assistant"` with `content`). It accepts string content or array-of-blocks content, concatenates text blocks with newlines, detects `AskUserQuestion` `tool_use` blocks, and ignores malformed JSONL lines individually.

## Tag Protocol

The canonical no-question tag is the literal `<options-mode>no-question</options-mode>`. Matching is a case-sensitive substring check against the last assistant text; the tag can appear at the start, middle, or end, but `OPTIONS_RULES_TEXT` instructs models to append it as the final line for readability.

Use the tag only for plain prose, NOT a request for user input. Semantically, it asserts "this turn is not a question; do not convert it into an `AskUserQuestion` prompt." When the assistant needs the user to decide, choose, confirm, or answer a question, use an `AskUserQuestion` tool call with concrete choices instead of the tag.

Cross-CLI portability: Claude Code enforces the tag in the Stop hook. Codex CLI receives the same rules through the repo-level SessionStart hook, but that path is advisory only; Codex does not run the Claude Code Stop hook.

## Loop Counter

Stop-hook block loops are counted per `(transcript_path, last-assistant-id)`. The preferred id is the last assistant envelope `uuid`; fallback is `sha256(text).slice(0,16) + ':' + length`. The sixth consecutive block gives up with a WARN and no decision.

Counter files at `<configRoot>/.options-stop-counter-<32-char-sha256-hex>` have the following retention contract: the file is created on the first block for a given `(transcript_path, last-assistant-id)` pair and incremented on each subsequent block. Once the give-up threshold (`count > 5`) is reached, the counter file is unlinked because that pair is in terminal give-up state and will not be re-evaluated. Counter files for pairs that never reach give-up (the common case where the model self-corrects within five blocks) are left in place; they are ~1-2 bytes each and the SHA-256 keyspace prevents collisions, so accumulation is bounded by the number of distinct stuck-then-recovered assistant turns across all transcripts using the same config root.

Block reasons are stripped of control characters and ANSI escapes, capped at 200 chars for stdout, and logged uncapped for audit.

## Conflict Matrix

| Other Stop hook | Interaction |
| --- | --- |
| agent-peers listener lifecycle | Options Mode exits immediately when `stop_hook_active` is true, so recursive Stop invocations do not fight the listener guard; agent-peers Stop-hook lifecycle remains independent. |
| Any hook that already emits `AskUserQuestion` | Options Mode detects the tool_use in the last assistant message and exits empty. |
| Any hook that blocks after Options Mode | Claude Code evaluates hook decisions independently; Options Mode's block reason is: `Add <options-mode>no-question</options-mode> tag if this turn is not asking the user, or use AskUserQuestion with concrete choices.` |

## Repo-Level Codex Hook

`.codex/hooks.json` carries the repo-local Options Mode SessionStart hook with `_owner: "options-mode"`. Its inline command must stay byte-synced with `hooks/config.js::OPTIONS_RULES_TEXT` via `escapeForBashSingleQuote(s)` and `printf '%s\n' '<escaped>'`; `plugins/options-mode/tests/run.sh::test_rule_text_sync` enforces that contract.

Coordination convention: see the canonical six-rule `_owner` convention in the parent `CLAUDE.md` under "Repo-level Codex hooks". In summary:

1. **Hand-edited only** — no auto-generation, no JSON-formatter round-trips.
2. **Every `SessionStart` entry MUST carry `_owner`** — entries without `_owner` are invalid.
3. **Merge = append** — never reorder, modify, or remove another plugin's entries.
4. **Uninstall = remove only your own `_owner`-matched entry** — leave all other entries intact.
5. **Delete `.codex/` when empty** — if your removal leaves `SessionStart` empty, delete the entire `.codex/` directory (including `config.toml`).
6. **`_owner`-less entries from future plugins → leave in place** — treat as unknown-owner; do not remove during uninstall.

`/plugin uninstall options-mode` does not touch repo-level `.codex/hooks.json`; manually remove the `_owner: "options-mode"` entry when uninstalling from a checkout.
