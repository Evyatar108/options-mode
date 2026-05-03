# Options Mode

<p align="center">
  <img src="logo.png" alt="Options Mode logo" width="280" />
</p>

You give an agent a task. It works for a while, then comes back with a paragraph of preamble and a question buried at the end. You scroll, read, type a reply, hope it's clear enough — and the agent goes off again. Now multiply that by five agents you're babysitting in parallel. Or by the fact that you're driving from your phone on the train. The slow part isn't the model — it's you reading prose and typing replies.

I built **options-mode**, a plugin for Claude Code and GitHub Copilot CLI that forces every decision turn through the built-in choice-prompt tool. Instead of reading prose and typing a reply, you get a short list of clear options — one marked **Recommended** — and pick with arrow keys + Enter.

## Before / After

> **Normal:** Paragraphs of context. A question buried at the end. You scroll, read, type a reply, hope it's clear enough.

![Normal response — wall of prose with the question buried at the end](before.png)

> **Options Mode:** Two to four labels on screen. Recommended one tagged. Arrow keys, Enter, done. Next turn fires.

![Options Mode response — arrow-key picker with concrete labeled choices and one marked Recommended](after.png)

Same decision. Seconds instead of a minute. Works the same in a terminal, on an iPad, or while triaging six agent windows.

## Why It Helps

- **Options at a glance.** Recommended choice marked, alternatives listed — no parsing prose to find the actual decision.
- **Zero typing.** Arrow keys + Enter. The keyboard barely moves.
- **Remote steering.** On a phone or tablet, tap the option you want. No touch-screen typing, no autocorrect duels.
- **Multi-agent context switching.** When five agents are blocked waiting for you, scanning labels and tapping is much cheaper than reading each one's verbose status and writing a reply back.

## Install

Register the marketplace once:

```text
/plugin marketplace add Evyatar108/options-mode
```

Install the plugin:

```text
/plugin install options-mode@options-mode --scope user
```

Restart your CLI after installation so SessionStart hooks are loaded. Works on Claude Code and GitHub Copilot CLI.

## Requirements

Options Mode has no external runtime dependency. The Claude Code and Copilot CLI surfaces run as local Node hooks, and post-turn enforcement does not call another CLI or model.

## Commands

- `/options-mode on` — enable choice-prompt enforcement for this session.
- `/options-mode off` — disable enforcement for this session.
- `/options-mode status` — show the current effective mode.
- `/options-mode default on|off|clear|status` — manage the global default that applies to new sessions.

### Global Default

`/options-mode default` lets users pick a permanent default for every new session without per-session opt-in. The default is stored in `<configRoot>/options.json` (typically `~/.claude/options.json`) under the `defaultMode` key. Per-session flags continue to override the default — e.g. with `defaultMode: "on"`, running `/options-mode off` in a single session keeps that session off without changing the file.

Precedence for the effective default is **env → file → off**: `OPTIONS_DEFAULT_MODE=on|off` in the environment is the escape hatch and overrides anything written by `/options-mode default`. With both set, the displayed default in `/options-mode status` reflects the resolved precedence (env wins).

## v1 Limitations

- Claude Code has full SessionStart, UserPromptSubmit, Stop, and statusline support.
- Codex ships SessionStart rule injection only; no Codex Stop hook or `/options-mode` command enforcement in v1.
- Standalone install/uninstall shell scripts are not shipped.
- Home-local Codex hook installation is deferred to v2.
