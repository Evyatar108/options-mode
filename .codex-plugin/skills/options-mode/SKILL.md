---
name: options-mode
description: Control choice-prompt mode for the Options Mode plugin.
---

# Options Mode

Use `/options-mode on`, `/options-mode off`, `/options-mode strict`, or `/options-mode status` to control options mode in Claude Code. Use `/options-mode default on|off|strict|clear|status` to manage the global default stored in `<configRoot>/options.json` (per-session flags still override it).

Modes:

- `on` — enforce AskUserQuestion choice prompts; allow plain prose only when the assistant appends `<options-mode>no-question</options-mode>`.
- `strict` — same enforcement, but the `no-question` tag is **not** a valid bypass; the only accepted post-turn states are an `AskUserQuestion` call or one of the two background tags `<options-mode>background-task</options-mode>` / `<options-mode>background-agent</options-mode>` (added v0.15.0).
- `off` — disable enforcement.

Do not map `strict` to `on`. They are distinct modes with different post-turn contracts.

This skill is Codex-only. Codex plugin users can invoke it as `/options-mode:options-mode` when the plugin skill surface is available. Codex support is repo-local startup rule injection only — no Stop or `agentStop` hook on this surface. Claude Code does not see this skill (the directory lives under `.codex-plugin/skills/` since v0.9.0); Claude Code users must use the bare `/options-mode ...` slash form, which the `UserPromptSubmit` hook intercepts. Copilot CLI has its own parallel skill at `.copilot-plugin/copilot-skills/options-mode/SKILL.md` (added v0.10.0, renamed in v0.12.0); the two skill bodies differ because Copilot CLI's tool is `ask_user` and the toggle path writes `~/.copilot/.options-mode-active` instead of the Claude per-session flag.
