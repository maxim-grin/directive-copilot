# 0004: Tools enforce rules; the Makefile owns the commands

Status: Accepted
Date: 2026-11-25

## Context

The rules for working on this repo started as a 500-line CLAUDE.md
carried over from another project. Rules in prose cost context on every
agent turn and are followed only as reliably as the reader remembers them.
Meanwhile the same check commands were spelled out separately in Claude
Code hooks, pre-commit and CI, with the pytest marker filter alone repeated
in four places.

## Decision

- A rule a tool can check lives in that tool: the commit-msg checker,
  pre-commit, ruff/mypy config, pytest config, `.claude/settings.json`
  permissions (static path and command rules), or `.claude/hooks/` (rules
  that need logic, such as the current branch or kube context).
- CLAUDE.md keeps only judgment rules and project invariants, plus a short
  table pointing at where each enforced rule lives.
- Every check command is a Makefile target. Hooks, pre-commit and CI call
  the targets instead of repeating commands. pytest's default run (unit
  suite, no network) is set once, in `pyproject.toml`.

## Consequences

- Changing a command means editing one target; CLAUDE.md stays about 130
  lines.
- The `.claude/` guards apply to agents only; `no-commit-to-branch` and the
  commit-msg checker apply to everyone. GitHub branch protection on `main`
  is still needed for anything pushed from elsewhere.
