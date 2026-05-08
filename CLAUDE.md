# Options Mode Plugin

Options Mode is a hook-only plugin. Runtime code is CommonJS under `hooks/`; tests live in `tests/run.sh` and must stay offline/deterministic by using isolated `CLAUDE_CONFIG_DIR`, `COPILOT_CONFIG_DIR`, and `HOME` roots.

## v0.16.0 Migration Note

Two UX improvements:

**Feature 1 — Recommended-first ordering unconditional.** All four rules-text constants (`OPTIONS_RULES_TEXT`, `OPTIONS_RULES_TEXT_STRICT`, `OPTIONS_RULES_FOR_COPILOT`, `OPTIONS_RULES_FOR_COPILOT_STRICT`) changed line from "Include a Recommended option first when one option is clearly best." to "Always put the recommended or default option first (as Option 1). Label it 'Recommended' to make the best choice obvious." `.codex/hooks.json` inline command byte-synced accordingly (hand-edit only; `test_rule_text_sync` enforces).

**Feature 2 — New `auto` mode.** Builds on `strict`. Four valid post-turn states:

1. `AskUserQuestion` tool call — `PreToolUse` hook intercepts before UI renders and returns `"The user isn't here right now, please try to continue as much as possible."`. Model proceeds autonomously.
2. `<options-mode>task-complete</options-mode>` — new tag; model uses when task is genuinely done (no user interaction needed). Copilot form: `[//]: # (options-mode-task-complete)`.
3. `<options-mode>background-task</options-mode>` / `<options-mode>background-agent</options-mode>` — existing bg tags, pass as usual.
4. `no-question` tag — **NOT valid** in auto mode (strict-based, no prose escape).

New files/changes:
- `hooks/pre-tool-use.js` — new PreToolUse hook (Claude Code); intercepts `AskUserQuestion` in auto mode.
- `hooks/hooks.json` — new `PreToolUse` entry, matcher `AskUserQuestion`, command `node ${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.js`.
- `hooks/copilot-pre-tool-use.js` — rewritten from probe stub; adds auto-continue before pass-through `{}`.
- `hooks/config.js` — `'auto'` added to `VALID_MODES`; `OPTIONS_TASK_COMPLETE_TAG`; `OPTIONS_RULES_TEXT_AUTO`; `isOptionsActive()` includes `auto`.
- `hooks/copilot-config.js` — same for Copilot surface; `OPTIONS_TASK_COMPLETE_TAG = '[//]: # (options-mode-task-complete)'`; `OPTIONS_RULES_FOR_COPILOT_AUTO`.
- `hooks/stop.js` — no-question guard extended to exclude `auto`; task-complete tag added; `BLOCK_REASON_AUTO` inline.
- `hooks/copilot-agent-stop.js` — active-mode guard widened to include `auto`; same stop.js changes mirrored.
- `hooks/session-start.js`, `hooks/copilot-session-start.js` — emit `OPTIONS_RULES_TEXT_AUTO` / `OPTIONS_RULES_FOR_COPILOT_AUTO` when mode is `auto`.
- `hooks/user-prompt-submit.js` — re-injects `OPTIONS_RULES_TEXT_AUTO` for auto; usage strings updated.
- Statusline scripts — both `.sh` and `.ps1` accept `auto`; badge renders `[OPTIONS MODE: auto]`.
- `OPTIONS_RULES_TEXT_AUTO` is intentionally NOT byte-synced to `.codex/hooks.json` (same design as `OPTIONS_RULES_TEXT_STRICT`).

Bumps `0.15.4` → `0.16.0` across all three plugin manifests and all three marketplace indexes.

## v0.15.4 Migration Note

**Copilot strict rules: `allow_freeform: true` is now permitted alongside populated `choices`.** v0.15.2 forced `allow_freeform: false` in strict, on the theory that "the user picks, not types". In practice that strips a useful Copilot affordance — the user can both pick a labeled choice AND type a freeform answer when neither label fits — without addressing the original UX bug. Re-reading that bug: the symptom was an `ask_user` call with `allow_freeform: true` AND no `choices`, leaving only a typed-text input. The bug is the missing `choices`, not the freeform flag.

`hooks/copilot-config.js::OPTIONS_RULES_FOR_COPILOT_STRICT` now reads:

> `allow_freeform: true is permitted, AS LONG AS choices is also populated with 2-4 concrete labels. The strict-mode contract is that the user always has concrete labels to pick from; whether they can also type freeform alongside is allowed. Never call ask_user with allow_freeform: true and no choices — that is the freeform-only failure that strict mode forbids.`

The strict-mode contract is now defined by `choices` being populated, not by `allow_freeform`. Anchors line drops `allow_freeform: false` and adds `choices REQUIRED` to underline the actual invariant. The reminder line about valid post-turn states drops the parenthetical `allow_freeform: false` requirement (still says `choices populated`).

Claude Code (`OPTIONS_RULES_TEXT_STRICT`) is unchanged — `AskUserQuestion` has no `allow_freeform` parameter, and the v0.15.2 wording already permits free-form Other as ONE of the 2-4 labels (last position) without the freeform-only failure mode being possible.

Hook-level enforcement is still rules-text-only on both surfaces. A model emitting `ask_user` without `choices` still passes the agentStop hook today; the strengthened rules text remains the only guardrail.

Bumps `0.15.3` → `0.15.4` in lockstep across all three plugin manifests and all three marketplace indexes.

## v0.15.3 Migration Note

**Multi-model review pass (Claude + Codex gpt-5.5 + Copilot GPT-5.4) on the v0.15.0 → v0.15.2 series.** Seven items addressed in lockstep:

1. **`on`-mode now silently accepts bg tags** (`hooks/stop.js`, `hooks/copilot-agent-stop.js`). The v0.15.0 dispatch only accepted bg tags in strict and only `no-question` in `on`, contradicting the CLAUDE.md Tag Protocol table that documented bg tags as "yes (silently treated as a tag)" in `on`. Code now matches the doc: bg tags pass in either mode; `no-question` passes only in `on`. Symmetric flow makes a `strict→on` mode flip non-disruptive for sessions that retained bg-tag emission.
2. **Copilot `getOptionsMode()` fail-open semantics mirrored to Claude** (`hooks/copilot-config.js`). v0.15.0 returned `'off'` on real fs read errors (fail-closed → enforcement bypassed). Now calls `_readFlagInternal` directly inside its own try/catch and returns `'on'` on thrown errors, matching Claude-side `hooks/config.js::getOptionsMode()`. ENOENT/invalid-content paths still return `'off'`. Inherited v0.14.0 behavior was already fail-closed; v0.15.3 brings both surfaces into alignment.
3. **Copilot machine-wide-only design documented in code** (`hooks/copilot-config.js::getOptionsMode()` block comment). Codex/Claude reviewers flagged the asymmetry vs Claude's env-var/options.json fallback. Confirmed intentional per v0.10.0 design (Copilot CLI hooks did not carry session state) and inline-commented so future readers don't try to "fix" the asymmetry.
4. **Single `getOptionsMode` call in `hooks/copilot-agent-stop.js`** replaces the v0.15.0 `isOptionsActive()` + later `getOptionsMode()` pair (two `_readFlagInternal` calls per turn). The non-strict short-circuit now branches on the single mode read.
5. **Test fixtures use ANSI-C `$'...\n...'` quoting** (`tests/run.sh::write_strict_transcript`, `write_copilot_transcript`). v0.15.0 used `'\n'` literal which was preserved verbatim through `$TEXT` env var into Node — substring checks passed but the "tag on its own line at block level" CommonMark contract for the Copilot bg-tag form was not exercised. Now the bg tags appear on dedicated lines, validating the same parse path users actually hit.
6. **Statusline header comments refreshed** (`hooks/options-mode-statusline.{sh,ps1}`). Comments said "renders [OPTIONS MODE] only when effective mode is on"; now correctly describe both `on` and `strict` rendering.
7. **New tests `test_codex_hooks_no_strict_leak`** asserts `OPTIONS_RULES_TEXT_STRICT` substrings (`background-task`, `background-agent`, `OPTIONS MODE ACTIVE (strict)`) do **not** appear in `.codex/hooks.json`. Plus `test_on_mode_background_task_tag_passes`, `test_on_mode_background_agent_tag_passes`, `test_copilot_on_background_task_tag_passes` cover the new `on`-mode bg-tag pass paths.

Known gaps NOT addressed (rules-text-only, hook-level enforcement intentionally out-of-scope):

- The Stop / agentStop hooks check only that `AskUserQuestion` / `ask_user` is present, not that `choices` is populated or `allow_freeform: false`. v0.15.2 closed this via stronger rules text; a model that ignores rules can still emit a freeform-only ask and pass the hook. Adding shape validation would require empirical knowledge of each tool's argument schema and is deferred.
- BLOCK_REASON_STRICT is 181 chars (Claude) / 162 chars (Copilot) under the 200-char `sanitizeReason()` cap. Headroom is fragile against future wording tweaks; no static-length test added.

Bumps `0.15.2` → `0.15.3` in lockstep across all three plugin manifests and all three marketplace indexes.

## v0.15.2 Migration Note

**Strict rules-text tightened on both surfaces** to close a freeform-input escape that surfaced empirically on the Copilot CLI surface. Symptom: a strict-mode session opening with no prior context emitted `ask_user` with `allow_freeform: true` and no `choices`, presenting only a typed-text input box — defeating the entire mode. Root cause: the v0.15.0 rules text said `allow_freeform: false unless the available choices may not cover the user intent`, which the model interpreted as a license for opening turns.

Fixes (rules-text only — no hook-level enforcement added):

- **Copilot (`hooks/copilot-config.js::OPTIONS_RULES_FOR_COPILOT_STRICT`)**: `choices` is now stated as REQUIRED, `allow_freeform` is now declared `false` always in strict (the on-mode "unless" clause is dropped), and an explicit opening-turn instruction lists category-label examples (`Bug fix, New feature, Refactor, Explain code, Other`).
- **Claude Code (`hooks/config.js::OPTIONS_RULES_TEXT_STRICT`)**: same opening-turn wording. `AskUserQuestion` has no `allow_freeform` parameter on the tool-call shape (its built-in "Other (free-form)" affordance is always available to the user), so there is no Claude-side flag to flip false; the rules-text change reframes free-form Other from a "use only when..." escape to "allowed as ONE of the 2-4 labels (last position)" plus a direct ban on emitting a tool call with no concrete labels.

Both strict rule strings gained a new anchor: `allow_freeform: false` (Copilot) — sits next to the existing `Recommended` and `mutually exclusive labels` anchors. The on-mode rules text is unchanged on both surfaces; only strict variants were tightened. `.codex/hooks.json` is unaffected (it byte-syncs with `OPTIONS_RULES_TEXT`, the on variant). No new tests were added because the existing `test_session_start_strict_emits_strict_rules` still passes — it asserts on the bg-tag and `OPTIONS MODE ACTIVE` / `strict` substrings, all of which remain.

Bumps from `0.15.1` to `0.15.2` in lockstep across all three plugin manifests and all three marketplace indexes.

## v0.15.1 Migration Note

**SKILL.md bodies teach `strict`.** v0.15.0 widened `VALID_MODES` and the `UserPromptSubmit` slash-command dispatcher, but the two SKILL.md skill bodies (`.codex-plugin/skills/options-mode/SKILL.md` and `.copilot-plugin/copilot-skills/options-mode/SKILL.md`) still listed only `on`/`off`/`status` as valid args. Models invoking the skill via `/options-mode:options-mode strict` mapped `strict` to `on`. Both SKILL bodies now document `strict` alongside `on` and `off`, with an explicit "do not map strict to on" callout. The Copilot SKILL.md gained a `strict` row in the toggle-command table that writes `strict\n` to `~/.copilot/.options-mode-active` (the `VALID_MODES` widening in `hooks/copilot-config.js` makes that flag value valid).

Bumps `0.15.0` to `0.15.1` in lockstep across all three plugin manifests and all three marketplace indexes.

## v0.15.0 Migration Note

**New `strict` mode** alongside existing `on` and `off`. Toggled per-session via `/options-mode strict` and per-machine via `/options-mode default strict`. In strict mode the only valid post-turn states are an `AskUserQuestion` (Claude Code) / `ask_user` (Copilot) tool call, or one of two new background-execution tags. The `<options-mode>no-question</options-mode>` plain-prose escape hatch is **not** a valid bypass in strict mode — every turn must prompt or signal background polling.

New tag constants (independent across surfaces):

- Claude Code (`hooks/config.js`): `OPTIONS_BACKGROUND_TASK_TAG = '<options-mode>background-task</options-mode>'`, `OPTIONS_BACKGROUND_AGENT_TAG = '<options-mode>background-agent</options-mode>'` — bare XML form (Claude Code's renderer strips unknown XML wrappers).
- Copilot CLI (`hooks/copilot-config.js`): `OPTIONS_BACKGROUND_TASK_TAG = '[//]: # (options-mode-background-task)'`, `OPTIONS_BACKGROUND_AGENT_TAG = '[//]: # (options-mode-background-agent)'` — CommonMark reference-link form (parses as link-reference definition; renderer hides it). Must be on its own line at block level.

Substring matching applies in `hooks/stop.js` (Claude Code) and `hooks/copilot-agent-stop.js` (Copilot): when `getOptionsMode()` returns `'strict'`, the bg-tag check replaces the `no-question` substring check.

Two new rules-text constants run in parallel with the existing ones:

- Claude Code: `OPTIONS_RULES_TEXT` (unchanged, `on` mode) + new `OPTIONS_RULES_TEXT_STRICT`. SessionStart and UserPromptSubmit pick by `getOptionsMode(sessionId)`.
- Copilot: `OPTIONS_RULES_FOR_COPILOT` (unchanged, `on` mode) + new `OPTIONS_RULES_FOR_COPILOT_STRICT`.

`.codex/hooks.json` keeps the `on`-variant rules text (byte-synced with `OPTIONS_RULES_TEXT` per `test_rule_text_sync`). `OPTIONS_RULES_TEXT_STRICT` is intentionally **not** propagated to Codex — Codex consumers see the `on` rules regardless of mode, and there is no Codex Stop/agentStop enforcement to honor strict mode anyway.

Statusline rendering forks: `on` → `[OPTIONS MODE]`, `strict` → `[OPTIONS MODE: strict]`, `off`/unset → silent. Same orange ANSI 172 in both badge variants. Both `hooks/options-mode-statusline.sh` and `.ps1` accept `strict` in their `OPTIONS_DEFAULT_MODE` env-parse path and `options.json::defaultMode` parse path.

`OPTIONS_DEFAULT_MODE` env var now also accepts `strict`, surviving the same env → file → off precedence as `on`/`off`.

Helper API: `isOptionsActive(sessionId)` keeps its boolean signature (`mode === 'on' || mode === 'strict'`). New `getOptionsMode(sessionId)` returns `'on'|'off'|'strict'` for hooks that need to discriminate `on` vs `strict`. The Copilot mirror exports `getOptionsMode()` (no session id).

`BLOCK_REASON_STRICT` deny reason on each surface mentions both bg tag forms and the AskUserQuestion/ask_user call but does not name the (forbidden) `no-question` tag — staying under the 200-char `sanitizeReason()` cap.

Bumps from `0.14.0` to `0.15.0` in lockstep across all three plugin manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.github/plugin/plugin.json`) and all three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`).

## v0.14.0 Migration Note

**Copilot CLI tag form changed to CommonMark reference-link.** The v0.13.0 HTML-comment form `<!--options-mode-no-question-->` was empirically NOT stripped by Copilot CLI's markdown renderer — the literal text was visible to the user. The Copilot-surface canonical tag in `hooks/copilot-config.js::OPTIONS_NO_QUESTION_TAG` is now `[//]: # (options-mode-no-question)`, the standard CommonMark idiom for inline comments. CommonMark parses this as a link reference definition (label `//`, URL `#`, title `options-mode-no-question`) and renderers do not emit text for link reference definitions, so the line is hidden. Must be emitted on its own line at block level for the parse to succeed — inline placement (e.g., end of a paragraph) would break the parse and leave the literal text visible.

Substring matching in `hooks/copilot-agent-stop.js` automatically tracks the new constant value (`content.indexOf(OPTIONS_NO_QUESTION_TAG)`); the BLOCK_REASON template literal also picks up the new tag form so models learn the correct sentinel from the deny reason. The Copilot SKILL.md at `.copilot-plugin/copilot-skills/options-mode/SKILL.md` is updated to instruct emitting the new form. The hook comment in `.github/plugin/hooks.json::agentStop` and the CLAUDE.md Tag Protocol + Anchors sections are updated. Claude Code (`hooks/config.js`) and Codex (`.codex/hooks.json`) are unchanged — they keep the bare `<options-mode>no-question</options-mode>` form because Claude Code's renderer already strips the unknown XML wrapper and Codex mirrors Claude Code's rules text.

Bumps from `0.13.0` to `0.14.0` in lockstep across all three plugin manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.github/plugin/plugin.json`) and all three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`).

## v0.13.0 Migration Note

**Copilot CLI tag form changed to HTML comment.** The Copilot-surface canonical tag in `hooks/copilot-config.js::OPTIONS_NO_QUESTION_TAG` is now `<!--options-mode-no-question-->` (was `<options-mode>no-question</options-mode>`). Copilot CLI's markdown renderer leaves the literal `<options-mode>` form visible to the user; standard markdown renderers hide HTML comments, so the new form keeps the sentinel out of the rendered output. The Claude Code surface in `hooks/config.js` keeps the bare `<options-mode>no-question</options-mode>` form because Claude Code's renderer already strips the unknown XML wrapper and only displays the inner `no-question` text.

Substring matching in `hooks/copilot-agent-stop.js` automatically tracks the new constant value (`content.indexOf(OPTIONS_NO_QUESTION_TAG)`); the BLOCK_REASON template literal also picks up the new tag form so models learn the correct sentinel from the deny reason. The Copilot SKILL.md at `.copilot-plugin/copilot-skills/options-mode/SKILL.md` is updated to instruct emitting `<!--options-mode-no-question-->` instead of the bare tag. The hook comment in `.github/plugin/hooks.json::agentStop` mentions the new form.

The Codex repo-level SessionStart hook at `.codex/hooks.json` byte-syncs `OPTIONS_RULES_TEXT` (Claude Code rules), which still references the bare `<options-mode>...` tag. Codex has no Stop or agentStop hook on this surface, so the tag is purely advisory there — keeping Codex aligned with Claude Code's renderer-friendly form rather than the Copilot-only HTML comment is intentional.

**Hook-side trailing-`?` heuristic from v0.11.0 reverted.** The Stop hook (`hooks/stop.js`) and Copilot agentStop hook (`hooks/copilot-agent-stop.js`) return to the pre-v0.11.0 behavior: presence of `<options-mode>no-question</options-mode>` is a pure substring bypass, no last-line `?` test. Removed: `BLOCK_REASON_TAG_QUESTION`, `lastProseLineEndsWithQuestion()`, the `tag-with-question` audit-log label, and the matching test cases (`test_tag_with_question_blocks`, `test_last_prose_line_ends_with_question_helper`, `assert_stop_block_tag_question`). Fixture `tests/fixtures/transcripts/last-msg-tag-with-question.jsonl` deleted. Fixture `tests/fixtures/transcripts/last-msg-ralph-polling-with-tag.jsonl` restored to its pre-v0.11.0 text ("Codex review still running. Wait or proceed?") so the original Ralph cooperative-polling pattern works again — `?` in prose plus the tag is no longer a block trigger.

The OPTIONS_RULES_TEXT and OPTIONS_RULES_FOR_COPILOT sentence added in v0.11.0 ("Do NOT append `<options-mode>no-question</options-mode>` when your turn ends with a question to the user...") is **kept** as advisory rules-text guidance. SessionStart still injects it on Claude Code (`hooks/config.js`) and Copilot (`hooks/copilot-config.js`); `.codex/hooks.json` is still byte-synced. Models that follow the rule self-correct; models that don't are not blocked at the hook layer. The trailing-`?` test was removed because it was both narrower than the rule (couldn't catch imperative asks like "Want me to..." that don't end with `?`) and wider than the intent (the Ralph polling pattern legitimately uses "Wait or proceed?" with the tag as a status update, and the heuristic blocked that).

Bumps from `0.12.0` to `0.13.0` in lockstep across all three plugin manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.github/plugin/plugin.json`) and all three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`).

## v0.12.0 Migration Note

Two fixes plus a deferred-investigation probe:

**1. Claude Code skill leakage fix (rename of `.copilot-plugin/skills/`).** The v0.9.0 hide-skill design assumed Claude Code's plugin discovery only scans `<plugin-root>/skills/`, so the Codex variant lived under `.codex-plugin/skills/`. v0.10.0 added a Copilot variant under `.copilot-plugin/skills/` with the same hide assumption. In practice (observed 2026-05-05) typing `/options-mode:options-mode on` in Claude Code DOES reach the Copilot skill body, which writes the machine-wide flag at `~/.copilot/.options-mode-active` rather than the per-session Claude Code flag. The skill directory is renamed to `.copilot-plugin/copilot-skills/options-mode/SKILL.md` to break whatever Claude Code-side glob is reaching `.copilot-plugin/skills/`. The Copilot manifest at `.github/plugin/plugin.json::skills` is updated to `.copilot-plugin/copilot-skills/` to match. New test `tests/run.sh::test_copilot_skills_dir_renamed` asserts both invariants: legacy path absent and new path + manifest field present. Codex is unaffected — `.codex-plugin/skills/` is unchanged.

**2. Copilot hook stdin-logging probe (deferred Issue B).** Empirical evidence from `~/.copilot/options-mode.log` (Copilot CLI 1.0.22+, 2026-05-05) shows `agentStop` stdin carries `{timestamp, cwd, sessionId, transcriptPath, stopReason}` — the v0.10.0 assumption that Copilot CLI lacks `sessionId` is wrong. Per-session toggling at `agentStop` enforcement time is therefore feasible, but the toggle write-path is still open. Codex feasibility ranking favored a hybrid model: keep `~/.copilot/.options-mode-active` as the v0.10.0 machine-wide default plus add `~/.copilot/.options-mode-active-<sha256(sessionId)>` as a per-session override, with toggling driven by a `preToolUse` intercept on the skill body's shell exec. Both branches depend on stdin schemas that are not yet documented. v0.12.0 ships a logging-only probe so we can confirm:
  - Does `sessionStart` stdin carry `sessionId`? `hooks/copilot-session-start.js` now logs `keys=...` plus the raw payload via `appendLog` before its existing `additionalContext` injection — same DEBUG/raw shape as `copilot-agent-stop.js` so log readers can grep both events identically.
  - Does `preToolUse` carry `sessionId` and shell-tool args? New `hooks/copilot-pre-tool-use.js` is a pass-through stub: read stdin, log keys + raw, emit `{}`. Wired in `.github/plugin/hooks.json::preToolUse` with `timeoutSec: 5`. **No enforcement, no blocking** — this turn's design is to capture data, not change behavior.

Once `~/.copilot/options-mode.log` shows real payloads from both events, decide whether to ship hybrid+intercept toggling (preferred path #1 in the Codex ranking) or fall back to the next-session-only path (#5, document machine-wide as the user-facing model). Until then the Copilot toggling contract is unchanged: the skill body still writes `~/.copilot/.options-mode-active` machine-wide.

**3. v0.10.0 design note correction.** The v0.10.0 migration note above asserts: "The flag is machine-wide in v1 — there is no `session_id` in Copilot CLI hook stdin we can use to derive a per-session flag, so per-session toggling is deferred." That second clause is empirically false as of Copilot CLI 1.0.22+ (`sessionId` present in `agentStop`; `sessionStart` and `preToolUse` to be confirmed by the v0.12.0 probe). The text is left in place as a v0.10.0-era statement; the v0.12.0 probe is the path to overturning it.

Bumps from `0.11.0` to `0.12.0` in lockstep across all three plugin manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.github/plugin/plugin.json`) and all three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`).

## v0.11.0 Migration Note

Tag-with-question heuristic. Previously the Stop hook (`hooks/stop.js`) and Copilot agentStop hook (`hooks/copilot-agent-stop.js`) treated the no-question tag as a pure substring bypass — any presence of `<options-mode>no-question</options-mode>` short-circuited the block check, so a model could append the tag while still asking a question in prose ("Want me to do it? `<options-mode>no-question</options-mode>`") and slip past enforcement. v0.11.0 strips the tag from the assistant text, trims and filters empty lines, then matches `/\?$/` against the last non-empty line. When the tag is present and that test fires, the hook blocks with a new dedicated reason.

New exports in `hooks/stop.js`: `BLOCK_REASON_TAG_QUESTION` and `lastProseLineEndsWithQuestion(text)`. Mirrored in `hooks/copilot-agent-stop.js` with copy-flavored wording (`call ask_user with a choices array instead`). Loop-counter give-up at `count > 5` is shared with the existing missing-tag block path: same `(transcript_path, last-assistant-id)` key, same fail-open after the sixth consecutive miss. Audit-log lines now carry a `tag-with-question` vs `missing-tag` label so operators can distinguish the two stuck-loop modes.

The OPTIONS_RULES_TEXT (`hooks/config.js`) and OPTIONS_RULES_FOR_COPILOT (`hooks/copilot-config.js`) gain a sentence calling out the ban explicitly: "Do NOT append `<options-mode>no-question</options-mode>` when your turn ends with a question to the user (last sentence ending with `?`, or imperative asks like 'Want me to...', 'Should I...', 'Let me know...'). Use AskUserQuestion with concrete choices instead." (Copilot text says "Call ask_user with concrete choices instead.") The `.codex/hooks.json` inline command is byte-synced with the new OPTIONS_RULES_TEXT — `tests/run.sh::test_rule_text_sync` enforces.

False-positive risk: rhetorical questions in prose are safe — only the **last** non-empty line is matched. "What if X? Then Y." passes because the last line ends with `.`. The Ralph cooperative-polling fixture (`tests/fixtures/transcripts/last-msg-ralph-polling-with-tag.jsonl`) was updated from "Wait or proceed?" to "Polling again." so the Ralph polling pattern remains exempt; Ralph itself never emits `?` in cooperative status updates per `plugins/ralph/CLAUDE.md` v5.23.3.

Imperative asks ("Want me to...", "Should I...", "Let me know...") that happen to **not** end with `?` will currently slip past the heuristic. The OPTIONS_RULES_TEXT addition warns the model against the broader class, but enforcement is only the trailing-`?` check — extending to a regex of imperative-ask phrases was considered and rejected as too noisy for v0.11.0.

New tests in `tests/run.sh`: `test_tag_with_question_blocks` (asserts block with `BLOCK_REASON_TAG_QUESTION`) and `test_last_prose_line_ends_with_question_helper` (unit cases for the helper covering trailing `?`, mid-sentence `?`, inline tag, empty content). New fixture `tests/fixtures/transcripts/last-msg-tag-with-question.jsonl` with "Want me to do it?\n\n`<options-mode>no-question</options-mode>`" in the last assistant message; added to `test_required_fixtures_exist`.

Bumps from `0.10.1` to `0.11.0` in lockstep across all three plugin manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.github/plugin/plugin.json`) and all three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`).

## v0.10.1 Migration Note

Bugfix release for the Copilot agentStop hook. v0.10.0 inspected only the stdin payload, but the observed schema (Copilot CLI 1.0.22+, 2026-05-05) is `{timestamp, cwd, sessionId, transcriptPath, stopReason}` — it carries no assistant text. The previous heuristic therefore always failed the tag check and looped: hook blocked → reason reinjected as `user.message` → model emitted the tag → hook blocked again because stdin still had no assistant text. The new `copilot-agent-stop.js` reads `transcriptPath` (Copilot's `events.jsonl`), walks backward to the most recent `assistant.message` event, and matches the no-question tag against `data.content` and `ask_user` against `data.toolRequests[*].name`. A loop-counter give-up keyed on `(transcriptPath, last-assistant-message-id)` mirrors `hooks/stop.js` and bails after 5 consecutive blocks. Empirically Copilot honors the `decision: block` + `reason` shape — the reason text becomes the next `user.message` content — so the multi-shape deny payload is retained for forward compatibility.

## v0.10.0 Migration Note

Options Mode v0.10.0 adds a **GitHub Copilot CLI** surface alongside the existing Claude Code plugin and repo-local Codex SessionStart support.

New files (Copilot-only, do not affect Claude Code):

- `hooks/copilot-config.js` — `OPTIONS_RULES_FOR_COPILOT` rules text (mentions `ask_user` / `choices` / `allow_freeform: false` instead of `AskUserQuestion`), Copilot flag at `<copilotConfigRoot>/.options-mode-active` (default `~/.copilot/.options-mode-active`, override via `COPILOT_CONFIG_DIR`), audit log at `<copilotConfigRoot>/options-mode.log`. Mirrors the safety pattern in `hooks/config.js` (lstat symlink check + `O_EXCL | O_NOFOLLOW` temp + atomic rename) with the same TOCTOU acceptance.
- `hooks/copilot-session-start.js` — emits `{additionalContext: OPTIONS_RULES_FOR_COPILOT}` when the flag is `on`, `{}` otherwise. Requires Copilot CLI 1.0.11+ for `additionalContext` to be honored (public docs reference page is stale; see changelog at github.com/github/copilot-cli/blob/main/changelog.md). The flag is machine-wide in v1 — there is no `session_id` in Copilot CLI hook stdin we can use to derive a per-session flag, so per-session toggling is deferred.
- `hooks/copilot-agent-stop.js` — post-turn enforcement (rewritten in v0.10.1). Reads `transcriptPath` from stdin, walks Copilot's `events.jsonl` backward to the latest `assistant.message`, and passes if `data.content` contains `<options-mode>no-question</options-mode>` or any entry of `data.toolRequests` has `name === 'ask_user'`. Otherwise emits a deny payload with multiple field-name shapes (`decision/reason`, `permissionDecision/permissionDecisionReason`, `block/blockReason`) — empirically `decision`+`reason` is honored. Loop-counter give-up at `count > 5` keyed on `(transcriptPath, last-assistant-message-id)` matches `hooks/stop.js` and uses the same `<configRoot>/.options-stop-counter-<sha256>` retention contract (note: `<configRoot>` here is `~/.copilot`, not `~/.claude`).
- `hooks/copilot-toggle.js` — on|off|status helper. CLI-callable directly; the skill body invokes the equivalent shell commands instead so it works without resolving the plugin install path.
- `.copilot-plugin/skills/options-mode/SKILL.md` — slash command. The body is a prompt template; Copilot CLI invokes it when the user types `/options-mode`. Body instructs the model to write the flag via `mkdir -p ~/.copilot && printf '<arg>\n' > ~/.copilot/.options-mode-active`. Lives under `.copilot-plugin/` (mirroring the `.codex-plugin/` precedent) so Claude Code's `<plugin-root>/skills/` scan still finds nothing — the test_codex_plugin_skills_field invariant continues to hold.
- `.github/plugin/plugin.json` — Copilot CLI plugin manifest. Set as a separate file from `.claude-plugin/plugin.json` because the schemas differ (Copilot has `agents`/`skills`/`hooks` path fields; Claude Code has its own manifest contract). Copilot CLI's manifest lookup hits `.github/plugin/plugin.json` before `.claude-plugin/plugin.json`, so the Copilot-shaped manifest wins for Copilot consumers and the Claude Code manifest stays untouched.
- `.github/plugin/hooks.json` — Copilot hooks config. Wires `sessionStart` and `agentStop` events to `node hooks/copilot-*.js`. Hook commands assume cwd defaults to plugin install root (`~/.copilot/installed-plugins/<MARKETPLACE>/<PLUGIN-NAME>/`).

What v0.10.0 does NOT change:

- Claude Code SessionStart, UserPromptSubmit, Stop, statusline behavior — all unchanged. The `OPTIONS_RULES_TEXT` constant in `hooks/config.js` still mentions `AskUserQuestion`; the new Copilot rules text in `hooks/copilot-config.js::OPTIONS_RULES_FOR_COPILOT` mentions `ask_user`. The two rule strings are independent and may diverge as each surface evolves.
- Codex repo-local SessionStart at `.codex/hooks.json` — unchanged.
- Existing tests in `tests/run.sh` — pre-existing assertions still pass; new Copilot smoke tests are not yet in `run.sh` and rely on the empirical `~/.copilot/options-mode.log` logged by `copilot-agent-stop.js` for iteration.

Bumps `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and the new `.github/plugin/plugin.json` to `0.10.0` in lockstep. Three marketplace indexes (`.claude-plugin/marketplace.json`, `.github/plugin/marketplace.json`, `.agents/plugins/marketplace.json`) all bumped + descriptions expanded to mention Copilot CLI. v0.10.1 bumps all three plugin manifests and the three marketplace indexes from `0.10.0` to `0.10.1` for the agentStop fix.

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

Harness checks use these stable substrings from `hooks/config.js::OPTIONS_RULES_TEXT` (Claude Code surface, `on` mode): `OPTIONS MODE ACTIVE`, `AskUserQuestion choice prompt`, `Recommended`, `mutually exclusive labels`, and `<options-mode>no-question</options-mode>`. The parallel `hooks/copilot-config.js::OPTIONS_RULES_FOR_COPILOT` constant uses Copilot-flavored anchors: `OPTIONS MODE ACTIVE`, `ask_user`, `choices`, `Recommended`, and `[//]: # (options-mode-no-question)` (CommonMark reference-link form as of v0.14.0 — see migration note). Update the relevant harness if either canonical rules text changes; the two strings intentionally diverge on the choice-prompt tool name (`AskUserQuestion` vs. `ask_user`) and the no-question tag form (`<options-mode>...</options-mode>` vs. `[//]: # (...)`), and may diverge further as each surface evolves.

The strict-mode rules-text constants — `hooks/config.js::OPTIONS_RULES_TEXT_STRICT` and `hooks/copilot-config.js::OPTIONS_RULES_FOR_COPILOT_STRICT` (both added in v0.15.0) — share the v0.15.0-specific anchors `strict` (the literal keyword in `OPTIONS MODE ACTIVE (strict).`), the surface-specific `background-task` and `background-agent` substrings, plus the surface-specific tool name (`AskUserQuestion` / `ask_user`). The `no-question` substring also appears in both strict variants but only as a callout that it is **not** a valid bypass — harness checks that want to assert strict-mode rules emission should match on `background-task` plus `background-agent` (with the bare-XML form on Claude Code and the reference-link form on Copilot) rather than on `no-question`. `OPTIONS_RULES_TEXT_STRICT` is intentionally not byte-synced to `.codex/hooks.json`.

The auto-mode rules-text constants — `hooks/config.js::OPTIONS_RULES_TEXT_AUTO` and `hooks/copilot-config.js::OPTIONS_RULES_FOR_COPILOT_AUTO` (added in v0.16.0) — use the anchors: `OPTIONS MODE ACTIVE (auto)` (the literal keyword), `AskUserQuestion`/`ask_user`, `task-complete`, `background-task`, `background-agent`. `OPTIONS_RULES_TEXT_AUTO` is intentionally NOT byte-synced to `.codex/hooks.json` (same design as `OPTIONS_RULES_TEXT_STRICT` — Codex advisory path receives only the `on`-mode rules).

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

`defaultMode` accepts `"on"`, `"off"`, or `"auto"`; any other value is ignored. `setDefaultMode(mode)` and `clearDefaultMode()` perform an atomic read-modify-write (preserving any other keys callers may have stored) using the same `lstat` symlink check + `O_EXCL | O_NOFOLLOW` temp + `renameSync` pattern as `safeWriteFlag()`. The same TOCTOU acceptance applies — see Flag Contract above and the in-code comment in `_writeConfigJsonAtomic()`. `clearDefaultMode()` deletes the key and `unlinkSync`s the file when the resulting object is empty so `~/.claude/options.json` does not linger as `{}`.

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
5. Render `[OPTIONS MODE]` in ANSI 172 (orange) when the effective mode resolves to `on`; render `[OPTIONS MODE: strict]` for `strict`; render `[OPTIONS MODE: auto]` for `auto`; exit 0 silently for `off`, unset, parse errors, missing files, or any other failure (fail-silent-on-error policy).

The badge is intentionally invisible when the effective mode is `off`, matching the caveman pattern. Do not re-introduce `[OPTIONS:OFF]`. The portable sha256 helper in `options-mode-statusline.sh` tries `sha256sum` first (Git Bash/Linux) and falls back to `shasum -a 256` (macOS); statusline tests must not depend on `jq` being installed.

## UserPromptSubmit Contract

`hooks/user-prompt-submit.js` owns `/options-mode on|off|strict|auto|status` and `/options-mode default [on|off|strict|auto|clear|status]`. Per-session subcommands write literal flag values and emit `{"decision":"block","reason":"options mode: <state>"}`. The `default` subcommand variants emit `options mode default: <on|off|strict|auto|cleared|unset>` (with `default` alone aliasing to `default status`). The status report includes session and default state in a parseable suffix:

```
options mode: <effective> (session=<on|off|strict|auto|unset>, default=<on|off|strict|auto|unset>)
```

The leading `options mode:` token is preserved for log/grep parsers; only the parenthetical is new. Bad subcommands return the usage line `options mode: usage /options-mode on|off|strict|auto|status|default [on|off|strict|auto|clear|status]`. Mode-set dispatch gates on `VALID_MODES.includes(arg)` (set in `hooks/config.js`), so adding a future mode only requires widening that list.

## Stop-Hook Contract

`hooks/stop.js` exits 0 with empty stdout for all fail-open and short-circuit cases. The decision flow is:

1. Exit empty when `stop_hook_active === true` (recursive Stop call).
2. Exit empty when input has `agent_id` or `agent_type` (subagent invocation).
3. Exit empty when `isOptionsActive(session_id)` is false (mode is `off` or missing).
4. Exit empty when `transcript_path` is missing or the transcript file does not exist.
5. Parse the transcript from the end and fail open when no valid assistant envelope is found.
6. Normalize the last assistant content and exit empty when it contains an `AskUserQuestion` `tool_use` block.
7. Exit empty when normalized assistant text is blank.
8. Resolve the effective mode via `getOptionsMode(session_id)`. Exit empty when the assistant text contains the `<options-mode>background-task</options-mode>` or `<options-mode>background-agent</options-mode>` substring (accepted in `on`, `strict`, and `auto`). When mode is `auto`, also exit empty when the text contains `<options-mode>task-complete</options-mode>` (`OPTIONS_TASK_COMPLETE_TAG`). When mode is not `strict` and not `auto`, also exit empty when the assistant text contains the `<options-mode>no-question</options-mode>` substring; in `strict` and `auto` that tag does **not** bypass.
9. Increment the loop counter for the `(transcript_path, last-assistant-id)` pair; on the sixth consecutive miss, log a WARN, unlink the counter, and fail open.
10. Emit `{"decision":"block","reason":<BLOCK_REASON|BLOCK_REASON_STRICT|BLOCK_REASON_AUTO>}` — `BLOCK_REASON_STRICT` is selected when mode is `strict`; `BLOCK_REASON_AUTO` (inline ternary in stop.js) is selected when mode is `auto` and instructs the model to use `AskUserQuestion` or `OPTIONS_TASK_COMPLETE_TAG` or a background tag; `BLOCK_REASON` is the on-mode default and instructs the model to add the `no-question` tag or use `AskUserQuestion`.

Transcript parsing walks valid JSONL envelopes from the end, chooses the last real Claude Code assistant envelope (`type: "assistant"` with `message.content`) first, then falls back to the legacy fixture shape (`role: "assistant"` with `content`). It accepts string content or array-of-blocks content, concatenates text blocks with newlines, detects `AskUserQuestion` `tool_use` blocks, and ignores malformed JSONL lines individually.

## Tag Protocol

Three tag categories are recognized in v0.15.0+, all using the same per-surface form (bare XML on Claude Code, CommonMark reference-link on Copilot):

| Category | Claude Code (`hooks/config.js`) | Copilot CLI (`hooks/copilot-config.js`) | Valid in `on` | Valid in `strict` | Valid in `auto` |
| --- | --- | --- | --- | --- | --- |
| no-question | `<options-mode>no-question</options-mode>` (`OPTIONS_NO_QUESTION_TAG`) | `[//]: # (options-mode-no-question)` (`OPTIONS_NO_QUESTION_TAG`, since v0.14.0) | yes | **no** | **no** |
| background-task | `<options-mode>background-task</options-mode>` (`OPTIONS_BACKGROUND_TASK_TAG`, v0.15.0+) | `[//]: # (options-mode-background-task)` (`OPTIONS_BACKGROUND_TASK_TAG`, v0.15.0+) | yes (silently treated as a tag) | yes | yes |
| background-agent | `<options-mode>background-agent</options-mode>` (`OPTIONS_BACKGROUND_AGENT_TAG`, v0.15.0+) | `[//]: # (options-mode-background-agent)` (`OPTIONS_BACKGROUND_AGENT_TAG`, v0.15.0+) | yes (silently treated as a tag) | yes | yes |
| task-complete | `<options-mode>task-complete</options-mode>` (`OPTIONS_TASK_COMPLETE_TAG`, v0.16.0+) | `[//]: # (options-mode-task-complete)` (`OPTIONS_TASK_COMPLETE_TAG` in `copilot-config.js`, v0.16.0+) | **no** | **no** | yes |

Matching is a case-sensitive substring check against the last assistant text on each surface; the tag can appear at the start, middle, or end, but the rules text on each surface instructs models to append it as the final line for readability. The Copilot forms must each be on their own line at block level for CommonMark to parse them as link-reference definitions.

Use no-question only for plain prose, NOT a request for user input. Semantically, it asserts "this turn is not a question; do not convert it into an `AskUserQuestion` prompt." Use background-task when polling a long-running command/build/test/etc, and background-agent when polling a subagent or peer agent. When the assistant needs the user to decide, choose, confirm, or answer a question, use an `AskUserQuestion` tool call (Claude Code) / `ask_user` (Copilot) with concrete choices instead of any tag.

In `on` mode, the no-question tag is the canonical bypass and the bg tags are accepted as substring matches but redundant — the rules text doesn't instruct models to use them. In `strict` mode, the no-question tag is **not** a valid bypass (the `BLOCK_REASON_STRICT` deny reason explicitly does not list it as accepted), and the bg tags become the only post-prose escape paths.

Cross-CLI portability:

- **Claude Code** enforces tags in the Stop hook (`hooks/stop.js`). Mode picked via `getOptionsMode(session_id)`.
- **Copilot CLI** enforces tags in the `agentStop` hook (`hooks/copilot-agent-stop.js`) by reading the transcript at `stdin.transcriptPath` and inspecting the last `assistant.message` event (see v0.10.1 Migration Note for schema and rationale). Mode picked via `getOptionsMode()` (no session id).
- **Codex CLI** receives the unchanged `on`-mode rules through the repo-level SessionStart hook at `.codex/hooks.json`, but that path is advisory only; Codex does not run a Stop or agentStop hook. Strict-mode rules are intentionally not propagated to Codex per v0.15.0 design.

## Loop Counter

Stop-hook block loops are counted per `(transcript_path, last-assistant-id)`. The preferred id is the last assistant envelope `uuid`; fallback is `sha256(text).slice(0,16) + ':' + length`. The sixth consecutive block gives up with a WARN and no decision.

Counter files at `<configRoot>/.options-stop-counter-<32-char-sha256-hex>` have the following retention contract: the file is created on the first block for a given `(transcript_path, last-assistant-id)` pair and incremented on each subsequent block. Once the give-up threshold (`count > 5`) is reached, the counter file is unlinked because that pair is in terminal give-up state and will not be re-evaluated. Counter files for pairs that never reach give-up (the common case where the model self-corrects within five blocks) are left in place; they are ~1-2 bytes each and the SHA-256 keyspace prevents collisions, so accumulation is bounded by the number of distinct stuck-then-recovered assistant turns across all transcripts using the same config root.

Block reasons are stripped of control characters and ANSI escapes, capped at 200 chars for stdout, and logged uncapped for audit.

## Conflict Matrix

| Other Stop hook | Interaction |
| --- | --- |
| agent-peers listener lifecycle | Options Mode exits immediately when `stop_hook_active` is true, so recursive Stop invocations do not fight the listener guard; agent-peers Stop-hook lifecycle remains independent. |
| Any hook that already emits `AskUserQuestion` | Options Mode detects the tool_use in the last assistant message and exits empty. |
| Any hook that blocks after Options Mode | Claude Code evaluates hook decisions independently; Options Mode's `on`-mode block reason is `Add <options-mode>no-question</options-mode> tag if this turn is not asking the user, or use AskUserQuestion with concrete choices.` In `strict` mode the block reason instead points to AskUserQuestion plus the `<options-mode>background-task</options-mode>` and `<options-mode>background-agent</options-mode>` tags. |

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
