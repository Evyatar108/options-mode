# Options Mode

Options Mode is a hook-only Claude Code plugin that keeps user-facing turns in choice-prompt mode. It injects the rules at session start, handles `/options-mode on|off|status`, and uses a deterministic Stop hook: assistant prose must either use the `AskUserQuestion` tool with concrete choices or include the literal `<options-mode>no-question</options-mode>` tag.

## Install

Register the marketplace once:

```text
/plugin marketplace add Evyatar108/options-mode
```

Install the plugin:

```text
/plugin install options-mode@options-mode --scope user
```

> Also published as part of [`gim-home/ai-developer-toolkit`](https://github.com/gim-home/ai-developer-toolkit) — install via `/plugin install options-mode@ai-developer-toolkit` if you already use that marketplace.

Restart Claude Code after installation so SessionStart hooks are loaded.

## Requirements

Options Mode has no external runtime dependency. The Claude Code surfaces run as local hooks, and Stop-hook enforcement does not call another CLI or model.

## Tag Protocol

The no-question tag is a case-sensitive substring match:

```text
<options-mode>no-question</options-mode>
```

Use `AskUserQuestion` when the turn needs a user decision. Use the no-question tag when the turn is plain prose, a status update, or any other non-asking response.

Examples:

```text
Build completed and tests are still running.
<options-mode>no-question</options-mode>
```

```text
I updated the README and started the harness.
<options-mode>no-question</options-mode>
```

Claude Code enforces this in the Stop hook when options mode is on. Codex support is advisory only: the repo-level SessionStart hook injects the same rules text when running Codex from this checkout, but Codex does not get Stop-hook enforcement or `/options-mode` command handling from this plugin.

## OS Support

| Surface | Support |
| --- | --- |
| Claude Code plugin hooks | Windows, macOS, Linux |
| Claude Code statusline | Bash on macOS/Linux/WSL/Git Bash; PowerShell on Windows |
| Codex repo-level SessionStart | macOS/Linux in v1 per caveman precedent |

## Commands

- `/options-mode on` writes the per-session flag `<configRoot>/.options-active-<sha256(session_id)[0:32]>` with `on`.
- `/options-mode off` writes the same per-session flag with `off`.
- `/options-mode status` reports the effective mode plus the session and default state, e.g. `options mode: on (session=unset, default=on)`.
- `/options-mode default on` sets the global default to `on` (stored in `<configRoot>/options.json`).
- `/options-mode default off` sets the global default to `off`.
- `/options-mode default clear` removes the stored default; the file is unlinked if no other keys remain.
- `/options-mode default status` (or just `/options-mode default`) reports `on`, `off`, or `unset`.

As of v0.4.0 the flag is per session: every new Claude Code session falls back to the Global Default (below) when no per-session flag is set, and the per-session flag always wins when present. The plugin never deletes per-session flag files. The legacy machine-wide path `<configRoot>/.options-active` is read only when a hook is invoked without a `session_id` for older Claude Code builds and repo harness scripts.

### Global Default

`/options-mode default` lets users pick a permanent default for every new session without per-session opt-in. The default is stored in `<configRoot>/options.json` (typically `~/.claude/options.json`) under the `defaultMode` key. Per-session flags continue to override the default — e.g. with `defaultMode: "on"`, running `/options-mode off` in a single session keeps that session off without changing the file.

Precedence for the effective default is **env → file → off**: `OPTIONS_DEFAULT_MODE=on|off` in the environment is the escape hatch and overrides anything written by `/options-mode default`. With both set, the displayed default in `/options-mode status` reflects the resolved precedence (env wins).

## Statusline

The plugin ships `hooks/options-mode-statusline.{sh,ps1}` for the Claude Code statusline. The badge shows `[OPTIONS MODE]` (orange) when the effective mode is on; nothing when off, matching the caveman pattern. Effective-mode lookup mirrors the hooks: per-session flag wins, then global default (`OPTIONS_DEFAULT_MODE` env → `options.json::defaultMode` → off).

Wire it in `~/.claude/settings.json` with one of:

```json
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -File ${CLAUDE_PLUGIN_ROOT}/hooks/options-mode-statusline.ps1"
}
```

```json
"statusLine": {
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/options-mode-statusline.sh"
}
```

Claude Code passes `{"session_id": "...", ...}` as stdin JSON to the statusline command; both scripts parse `session_id` and compute the same per-session flag path the hooks use. Restart Claude Code after editing `settings.json` so the new statusLine config is loaded. Only one `statusLine` command can be registered at a time; if a second plugin needs a badge later, wrap both in a single script.

## Codex Scope

Codex support is repo-local-dev only in v1. The repo-level `.codex/config.toml` and `.codex/hooks.json` fire only when running Codex from this checkout or a clone/fork containing those files.

Users who want Codex rule injection in their own repos must manually copy `.codex/config.toml` and `.codex/hooks.json` into that repo. Home-local Codex install at `~/.codex/hooks.json` is deferred to v2.

## Troubleshooting

Warnings and counters are stored under the Claude config root:

- `<configRoot>/.options-statusline-warn` throttles statusline setup warnings.
- `<configRoot>/.options-stop-counter-*` tracks consecutive Stop-hook blocks for a session and is removed when the sixth consecutive miss fails open.
- `<configRoot>/options.log` records detailed WARN lines and rotates at 64 KB.

If Stop-hook enforcement blocks a turn, either ask the user with `AskUserQuestion` and mutually exclusive choices or append `<options-mode>no-question</options-mode>` to a non-asking turn.

## Known Failure Modes

- False `Other...` options: the model may overuse catch-all choices when it should provide mutually exclusive labels.
- Drift after compaction: SessionStart reinjects the rules on `compact`, but compacted context can still lose recent task nuance.
- Paste-workflow breakage: workflows that expect the model to ask for free-form pasted content may need `/options-mode off` temporarily.
- Tagless drift: after five consecutive blocks, the sixth tag miss fails open and clears the Stop-hook counter to avoid an infinite loop.

## v1 Limitations

- Claude Code has full SessionStart, UserPromptSubmit, Stop, and statusline support.
- Codex ships SessionStart rule injection only; no Codex Stop hook or `/options-mode` command enforcement in v1.
- Standalone install/uninstall shell scripts are not shipped.
- Home-local Codex hook installation is deferred to v2.
