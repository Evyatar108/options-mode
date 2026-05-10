---
name: options-mode
description: Control choice-prompt mode for the Options Mode plugin. Use bare `/options-mode on|off|strict|auto|status` — handled by the UserPromptSubmit hook.
---

# Options Mode

The bare `/options-mode <arg>` slash command is intercepted by the `UserPromptSubmit` hook in `hooks/user-prompt-submit.js`. The hook writes the per-session flag at `~/.claude/options-mode/sessions-configs/<sha256(session_id)[0:32]>` and emits a block decision so the prompt never reaches the model.

If you reach this skill body via `/options-mode:options-mode <arg>` (the namespaced form), the hook layer has already done its job — there is nothing more to do here. Reply to the user with a one-line confirmation of the intended mode and stop.

Modes:

- `on` — enforce AskUserQuestion choice prompts; allow plain prose only with `<options-mode>no-question</options-mode>` tag.
- `strict` — same as on, but the no-question tag is **not** a valid bypass; only AskUserQuestion or background tags end a turn.
- `auto` — for unattended sessions; AskUserQuestion is intercepted by `PreToolUse` and auto-replied "user isn't here", `<options-mode>task-complete</options-mode>` signals clean done.
- `off` — disable enforcement.
- `status` — report current effective mode.

Do not map `strict`, `auto`, or `off` to each other. They are distinct modes with different post-turn contracts.
