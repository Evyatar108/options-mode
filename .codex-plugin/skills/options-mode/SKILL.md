---
name: options-mode
description: Control choice-prompt mode for the Options Mode plugin.
---

# Options Mode

Use `/options-mode on`, `/options-mode off`, or `/options-mode status` to control options mode in Claude Code. Use `/options-mode default on|off|clear|status` to manage the global default stored in `<configRoot>/options.json` (per-session flags still override it).

This skill is Codex-only. Codex plugin users can invoke it as `/options-mode:options-mode` when the plugin skill surface is available. Codex support is repo-local startup rule injection only — no Stop or `agentStop` hook on this surface. Claude Code does not see this skill (the directory lives under `.codex-plugin/skills/` since v0.9.0); Claude Code users must use the bare `/options-mode ...` slash form, which the `UserPromptSubmit` hook intercepts. Copilot CLI has its own parallel skill at `.copilot-plugin/skills/options-mode/SKILL.md` (added v0.10.0); the two skill bodies differ because Copilot CLI's tool is `ask_user` and the toggle path writes `~/.copilot/.options-mode-active` instead of the Claude per-session flag.
