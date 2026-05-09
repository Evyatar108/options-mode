---
name: options-mode
description: Toggle Copilot CLI options-mode on, off, strict, or auto, or report status. Args - on, off, strict, auto, status (defaults to status if no arg).
---

The user invoked `/options-mode` to control Copilot CLI's options-mode plugin. The plugin enforces that every decision turn ends with an `ask_user` tool call (with a `choices` array) instead of plain prose. Mode is stored per-session in `~/.copilot/.options-mode-active-<hash>` (v0.16.5+); the machine-wide `~/.copilot/.options-mode-active` remains as a fallback default.

Parse the argument from the user's message:

- `on` — enable enforcement; plain prose may bypass with the `[//]: # (options-mode-no-question)` reference-link tag.
- `strict` — enable strict enforcement (v0.15.0+); the `no-question` tag is **not** a valid bypass. Only `ask_user` calls or the two background tags `[//]: # (options-mode-background-task)` / `[//]: # (options-mode-background-agent)` end a turn.
- `auto` — for unattended sessions (v0.16.0+); every turn must end with an `ask_user` call (hook auto-replies "user isn't here"), `[//]: # (options-mode-task-complete)`, or a background tag.
- `off` — disable enforcement.
- `status` (or no argument) — report current state.

Do not map `strict` to `on` or `auto`. Do not map `auto` to `on` or `strict`. They are distinct modes with different post-turn contracts.

Then run the matching shell command:

| Arg | Command |
| --- | --- |
| `on` | `Write-Output 'options-mode-set:on'` |
| `strict` | `Write-Output 'options-mode-set:strict'` |
| `auto` | `Write-Output 'options-mode-set:auto'` |
| `off` | `Write-Output 'options-mode-set:off'` |
| `status` | `Write-Output 'options-mode-status'` |

The preToolUse hook intercepts these marker commands, writes the per-session flag, and lets the command pass through so it exits 0. Do not use any other path or command — the hook only recognises this exact format.

After running, reply with **one line**:

```
options mode (copilot): <on|off|strict|auto>
```

Where `<on|off|strict|auto>` is the resulting mode. For status, the hook injects the current mode via `additionalContext` — read it from there.

Then append the appropriate sentinel on a new final line based on the **resulting** mode:

- `on` or `strict` → append `[//]: # (options-mode-no-question)` (this is a status turn, not a question)
- `auto` → append `[//]: # (options-mode-task-complete)` (the toggle is complete; no-question is not valid in auto mode)
- `off` → append `[//]: # (options-mode-no-question)`
- `status` → append `[//]: # (options-mode-no-question)`

The reference-link forms are parsed by CommonMark renderers as link reference definitions and are not emitted in the rendered output. Each must be on its own line at block level.

Note: the preToolUse hook intercepts the shell command above and redirects the write to a per-session flag file. The machine-wide path in the command above is intentional — the hook rewrites the destination transparently.
