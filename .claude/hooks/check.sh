#!/usr/bin/env bash
# Stop: before Claude finishes a turn, run the fast checks on what changed.
# Exit 2 sends the failures back to Claude so it keeps working.
# Same targets as pre-commit and CI. Integration tests and evals are NOT
# run here (need Postgres / cost money): `make test-integration`, `make eval`.
set -uo pipefail

input=$(cat)
# Already continuing because of this hook: don't loop forever.
[[ "$(jq -r '.stop_hook_active // false' <<<"$input")" == "true" ]] && exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 0

changed=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
[[ -z "$changed" ]] && exit 0

problems=""
run() { out=$("$@" 2>&1) || problems+=$'\n'"\$ $*"$'\n'"$(tail -n 40 <<<"$out")"; }

if grep -Eq '\.py$|^pyproject\.toml$|^uv\.lock$' <<<"$changed"; then
  run make lint
  run make test
fi

if grep -Eq '^web/' <<<"$changed"; then
  run make lint-web
fi

if grep -Eq '^copilot/migrations/versions/' <<<"$changed"; then
  # Only one migration head allowed.
  heads=$(uv run alembic heads 2>/dev/null | grep -c . || true)
  [[ "$heads" -gt 1 ]] && problems+=$'\n'"alembic has $heads heads; merge them."
fi

if [[ -n "$problems" ]]; then
  echo "Checks failed before finishing:$problems" >&2
  exit 2
fi
exit 0
