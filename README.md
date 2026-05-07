# Options Mode

<p align="center">
  <img src="assets/logo.png" alt="Options Mode logo" width="280" />
</p>

You give an agent a task. It works for a while, then comes back with a paragraph of preamble and a question buried at the end. You scroll, read, type a reply, hope it's clear enough — and the agent goes off again. Now multiply that by five agents you're babysitting in parallel. Or by the fact that you're driving from your phone on the train. The slow part isn't the model — it's you reading prose and typing replies.

I built **options-mode**, a plugin for Claude Code and GitHub Copilot CLI that forces every decision turn through the built-in choice-prompt tool. Instead of reading prose and typing a reply, you get a short list of clear options — one marked **Recommended** — and pick with arrow keys + Enter.

## Before / After

> **Normal:** Paragraphs of context. A question buried at the end. You scroll, read, type a reply, hope it's clear enough.

![Normal response — wall of prose with the question buried at the end](assets/before.png)

> **Options Mode:** Two to four labels on screen. Recommended one tagged. Arrow keys, Enter, done. Next turn fires.

![Options Mode response — arrow-key picker with concrete labeled choices and one marked Recommended](assets/after.png)

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

## Commands

- `/options-mode on` — enable choice-prompt enforcement for this session. Plain prose is allowed when the model marks the turn as not-a-question.
- `/options-mode strict` — like `on`, but **every** response back to the user must come with concrete options. The plain-prose escape is removed. Useful when next-step suggestions are usually obvious — the model surfaces them as choices and you continue with one keystroke instead of typing.
- `/options-mode off` — disable enforcement for this session.
- `/options-mode status` — show the current effective mode.
- `/options-mode default on|off|strict|clear|status` — manage the global default that applies to new sessions.
