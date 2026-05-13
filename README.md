# My Codex config

This repo is my personal Codex CLI setup.

I keep it public mostly as a snapshot of how I like Codex to work: practical
agent behavior, a few safety guardrails, shell-command hooks, MCP wiring, and
custom subagents for focused work.

## What's here

- `config.toml` - main Codex configuration, model defaults, feature flags, MCP
  servers, TUI preferences, and Codex-specific developer instructions.
- `AGENTS.md` - reusable working rules: stay evidence-oriented, keep diffs
  small, verify claims, and treat risky debugging targets carefully.
- `agents/` - custom subagent definitions for research, implementation,
  testing, review, and web/documentation lookup lanes.
- `hooks.json` and `hooks/` - global Bash hooks for logging command attempts,
  blocking dangerous command patterns, protecting sensitive paths, and enforcing
  the `rtk` shell-command prefix.
- `HOOKS.md` - notes on how the hook system is intended to behave and how to
  test it safely.
- `RTK.md` - short prompt-visible reminder for the shell command wrapper.

## How it is built

The config is split into a few layers:

- Portable behavior lives in `AGENTS.md`.
- Codex-specific orchestration lives in `config.toml` under
  `developer_instructions`.
- Safety-sensitive command handling lives in `hooks/`, not just in prose rules.
- Subagents live in `agents/` and are meant to keep large research, testing, and
  review tasks out of the main context when that helps.

The setup also wires in MCP servers I use often:

- `context7` for library and framework documentation lookup.
- `codebase_memory_mcp` for indexed codebase discovery, symbol search, and
  call/data-flow exploration.

## General rules

The main preferences are:

- Prefer local evidence over guesses.
- Keep changes surgical and easy to review.
- Use the smallest tool or command that answers the question.
- Prefix shell commands with `rtk`.
- Treat unknown debugging targets as production unless stated otherwise.
- Use reviewer-style scrutiny for significant config, hook, security, policy,
  permission, or multi-file behavior changes.

## What this is

This is a working personal config, not a polished starter template.

Some paths, hooks, subagents, and MCP assumptions are specific to my machine and
workflow. The useful part is the structure: reusable behavior in `AGENTS.md`,
Codex-specific control in `config.toml`, and enforcement/observability in
hooks where prose alone is not enough.

Local state, auth, logs, sessions, caches, and model/history files are not the
point of the repo and should stay out of version control.
