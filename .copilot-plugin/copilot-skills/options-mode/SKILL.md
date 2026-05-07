---
name: options-mode
description: Toggle Copilot CLI options-mode on, off, or strict, or report status. Args - on, off, strict, status (defaults to status if no arg).
---

The user invoked `/options-mode` to control Copilot CLI's options-mode plugin. The plugin enforces that every decision turn ends with an `ask_user` tool call (with a `choices` array) instead of plain prose. Mode is stored in `~/.copilot/.options-mode-active`.

Parse the argument from the user's message:

- `on` — enable enforcement; plain prose may bypass with the `[//]: # (options-mode-no-question)` reference-link tag.
- `strict` — enable strict enforcement (v0.15.0+); the `no-question` tag is **not** a valid bypass. Only `ask_user` calls or the two background tags `[//]: # (options-mode-background-task)` / `[//]: # (options-mode-background-agent)` end a turn.
- `off` — disable enforcement.
- `status` (or no argument) — report current state.

Do not map `strict` to `on`. They are distinct modes with different post-turn contracts.

Then run the matching shell command:

| Arg | Command |
| --- | --- |
| `on` | `mkdir -p ~/.copilot && printf 'on\n' > ~/.copilot/.options-mode-active` |
| `strict` | `mkdir -p ~/.copilot && printf 'strict\n' > ~/.copilot/.options-mode-active` |
| `off` | `mkdir -p ~/.copilot && printf 'off\n' > ~/.copilot/.options-mode-active` |
| `status` | `cat ~/.copilot/.options-mode-active 2>/dev/null \| tr -d '[:space:]' \|\| printf 'off'` |

After running, reply with **one line**:

```
options mode (copilot): <on|off|strict>
```

Where `<on|off|strict>` is the resulting mode (or the read-back for status).

Then append on a new final line:

```
[//]: # (options-mode-no-question)
```

This skill is a status/non-question turn, so the no-question tag is required when options-mode is currently `on`. The reference-link form is parsed by CommonMark renderers as a link reference definition (label `//`, target `#`, title `options-mode-no-question`) and is not emitted in the rendered output, so the user does not see the literal sentinel. It must be on its own line at block level.

Note: enabling options-mode takes effect on the **next session**, when the SessionStart hook re-injects the rules text. To anchor it for the current session as well, restart the Copilot CLI session after toggling on.
