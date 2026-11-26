#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit): rules that need logic a permission
# pattern can't express. Static path rules (secrets, data/raw/) live in
# permissions.deny in .claude/settings.json. Exit 2 = block.
set -uo pipefail

input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[[ -z "$file" ]] && exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rel="${file#"$root"/}"

block() { echo "Blocked: $1" >&2; exit 2; }

# Eval cases are written by hand. Claude may create the file once (to
# scaffold the format) but not edit it afterwards.
if [[ "$rel" == "evals/cases.yaml" && -f "$root/$rel" && "${DC_ALLOW_CASES:-0}" != "1" ]]; then
  block "evals/cases.yaml is hand-written by the user. Suggest the change in chat instead."
fi

# Committed migrations are immutable: add a new revision instead.
if [[ "$rel" == copilot/migrations/versions/* ]] \
   && git -C "$root" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
  block "$rel is a committed migration. Create a new alembic revision instead."
fi

# Accepted ADRs are never rewritten: supersede them with a new record and
# change only the old one's Status line.
if [[ "$rel" == docs/decisions/[0-9]*.md && -f "$root/$rel" ]] \
   && git -C "$root" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
  tool=$(jq -r '.tool_name' <<<"$input")
  old=$(jq -r '.tool_input.old_string // empty' <<<"$input")
  new=$(jq -r '.tool_input.new_string // empty' <<<"$input")
  status_only() { [[ "$1" =~ ^Status:[^$'\n']*$ ]]; }
  if [[ "$tool" != "Edit" ]] || ! status_only "$old" || ! status_only "$new"; then
    block "$rel is a committed ADR. Only its Status line may change; write a new ADR to supersede it."
  fi
fi

exit 0
