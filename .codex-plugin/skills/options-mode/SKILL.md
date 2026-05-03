---
name: options-mode
description: Control choice-prompt mode for the Options Mode plugin.
---

# Options Mode

Use `/options-mode on`, `/options-mode off`, or `/options-mode status` to control options mode in Claude Code. Use `/options-mode default on|off|clear|status` to manage the global default stored in `<configRoot>/options.json` (per-session flags still override it).

This skill is Codex-only. Codex plugin users can invoke it as `/options-mode:options-mode` when the plugin skill surface is available. In v1, Codex support is repo-local startup rule injection only. Claude Code does not see this skill (the directory lives under `.codex-plugin/skills/` since v0.9.0); Claude Code users must use the bare `/options-mode ...` slash form, which the `UserPromptSubmit` hook intercepts.
