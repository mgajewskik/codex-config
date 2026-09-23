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
- `agents/` - two model-based workers, `sol` and `luna`, and a dedicated
  read-only `reviewer`.
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
- The main conversation defaults to GPT-6 Astra medium for approach, decisions,
  and integration; another main model can be selected for the session. Subagents
  keep substantive research and execution out of its context.

| Profile | Model and effort | Use |
| --- | --- | --- |
| `luna` | GPT-6 Luna high | Bounded research, mechanical edits, focused checks |
| `sol` | GPT-6 Sol high | Substantial implementation, diagnosis, research, testing |
| `reviewer` | Active main model, high effort | Independent Spec and Standards review |

Workers receive a task-specific role in a focused, free-form brief. They inherit
the parent's permissions; research-only briefs prohibit edits but are not a
separate sandbox. Sol and Luna keep their pinned models when the main model
changes. The reviewer inherits the main model: an Astra main gets an Astra
reviewer, and a Sol main gets a Sol reviewer, both at high effort. There is no
global subagent model override; unnamed subagents also inherit, so ordinary work
uses the named worker profiles. The reviewer has a read-only profile, and its effective
permissions must be checked before relying on that boundary. Codex can override
that profile with the parent's live permissions. When it does, run the dedicated
reviewer from a fresh `codex --sandbox read-only --model <active-main-model>`
session and collect its decision. Carry over the original session's active model.

Major or high-risk changes automatically receive one fresh review after local
validation, covering task-scoped uncommitted and new files as well as committed
changes. Completion requires `Decision: PASS` or an explicit user waiver. This
review does not invoke the separate `review` skill, which remains available for
explicit fixed-point branch/PR reviews. Ordinary small changes do not gain an
extra review requirement merely because workers exist.

Start a fresh Codex session after changing these profiles. Model routing and
smaller briefs aim to reduce Astra usage and preserve context; total token,
credit, and elapsed-time savings depend on the task and have not been measured.

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
- Require independent review for major or high-risk changes under the
  `AGENTS.md` PASS-gate, including safety and permission changes.

## Unattended loop

`loop.sh` runs one bounded task at a time in a fresh
`codex exec --profile loop --ephemeral` process. Give it a task or PRD file
with explicit acceptance criteria and a completion rule, then run
`mise run loop -- TASK.md 5` from this repository root. In another normal Git
checkout, run `bash ~/.codex/loop.sh TASK.md 5` or add the same Mise task there.
The agent must wait for reviewer PASS before committing and stops when it emits
`<promise>COMPLETE</promise>`. Use this only in trusted repositories: the loop
profile permits recursive Git-metadata writes, live network access, and the
configured documentation/code-search MCP servers. Linked worktrees are
rejected, and each iteration currently has no timeout. Codex hooks remain
enabled, including the RTK command wrapper and dangerous-command guardrails,
but the loop should still be used only on trusted input.

## What this is

This is a working personal config, not a polished starter template.

Some paths, hooks, subagents, and MCP assumptions are specific to my machine and
workflow. The useful part is the structure: reusable behavior in `AGENTS.md`,
Codex-specific control in `config.toml`, and enforcement/observability in
hooks where prose alone is not enough.

Local state, auth, logs, sessions, caches, and model/history files are not the
point of the repo and should stay out of version control.
