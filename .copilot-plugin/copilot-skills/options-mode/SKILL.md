---
name: options-mode
description: Toggle Copilot CLI options-mode on, off, strict, or auto, or report status. Args - on, off, strict, auto, status (defaults to status if no arg).
---

The user invoked `/options-mode` to control Copilot CLI's options-mode plugin. The plugin enforces that every decision turn ends with an `ask_user` tool call (with a `choices` array) instead of plain prose. Mode is stored in `~/.copilot/.options-mode-active`.

Parse the argument from the user's message:

- `on` — enable enforcement; plain prose may bypass with the `[//]: # (options-mode-no-question)` reference-link tag.
- `strict` — enable strict enforcement (v0.15.0+); the `no-question` tag is **not** a valid bypass. Only `ask_user` calls or the two background tags `[//]: # (options-mode-background-task)` / `[//]: # (options-mode-background-agent)` end a turn.
- `auto` — builds on `strict` (v0.16.0+); the `no-question` tag is **not** valid. Every turn must end with an `ask_user` call (the preToolUse hook intercepts and auto-replies "user isn't here"), `[//]: # (options-mode-task-complete)` (clean done signal), or a background tag. Use for unattended sessions.
- `off` — disable enforcement.
- `status` (or no argument) — report current state.

Do not map `strict` to `on` or `auto`. Do not map `auto` to `on` or `strict`. They are distinct modes with different post-turn contracts.

Then run the matching shell command:

| Arg | Command |
| --- | --- |
| `on` | `mkdir -p ~/.copilot && printf 'on\n' > ~/.copilot/.options-mode-active` |
| `strict` | `mkdir -p ~/.copilot && printf 'strict\n' > ~/.copilot/.options-mode-active` |
| `auto` | `mkdir -p ~/.copilot && printf 'auto\n' > ~/.copilot/.options-mode-active` |
| `off` | `mkdir -p ~/.copilot && printf 'off\n' > ~/.copilot/.options-mode-active` |
| `status` | `cat ~/.copilot/.options-mode-active 2>/dev/null \| tr -d '[:space:]' \|\| printf 'off'` |

After running, reply with **one line**:

```
options mode (copilot): <on|off|strict|auto>
```

Where `<on|off|strict|auto>` is the resulting mode (or the read-back for status).

Then append the appropriate sentinel on a new final line based on the **resulting** mode:

- `on` or `strict` → append `[//]: # (options-mode-no-question)` (this is a status turn, not a question)
- `auto` → append `[//]: # (options-mode-task-complete)` (the toggle is complete; no-question is not valid in auto mode)
- `off` → append `[//]: # (options-mode-no-question)`
- `status` → append `[//]: # (options-mode-no-question)`

The reference-link forms are parsed by CommonMark renderers as link reference definitions and are not emitted in the rendered output. Each must be on its own line at block level.

Note: enabling options-mode takes effect on the **next session**, when the SessionStart hook re-injects the rules text. To anchor it for the current session as well, restart the Copilot CLI session after toggling on.
