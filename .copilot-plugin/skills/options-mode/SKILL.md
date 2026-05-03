---
name: options-mode
description: Toggle Copilot CLI options-mode on or off, or report status. Args - on, off, status (defaults to status if no arg).
---

The user invoked `/options-mode` to control Copilot CLI's options-mode plugin. The plugin enforces that every decision turn ends with an `ask_user` tool call (with a `choices` array) instead of plain prose. Mode is stored in `~/.copilot/.options-mode-active`.

Parse the argument from the user's message:

- `on` — enable enforcement
- `off` — disable enforcement
- `status` (or no argument) — report current state

Then run the matching shell command:

| Arg | Command |
| --- | --- |
| `on` | `mkdir -p ~/.copilot && printf 'on\n' > ~/.copilot/.options-mode-active` |
| `off` | `mkdir -p ~/.copilot && printf 'off\n' > ~/.copilot/.options-mode-active` |
| `status` | `cat ~/.copilot/.options-mode-active 2>/dev/null \| tr -d '[:space:]' \|\| printf 'off'` |

After running, reply with **one line**:

```
options mode (copilot): <on|off>
```

Where `<on|off>` is the resulting mode (or the read-back for status).

Then append on a new final line:

```
<options-mode>no-question</options-mode>
```

This skill is a status/non-question turn, so the no-question tag is required when options-mode is currently `on`.

Note: enabling options-mode takes effect on the **next session**, when the SessionStart hook re-injects the rules text. To anchor it for the current session as well, restart the Copilot CLI session after toggling on.
