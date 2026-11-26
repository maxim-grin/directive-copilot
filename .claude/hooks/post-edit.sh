#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit): format, lint and validate the file that
# was just changed. Problems go to stderr with exit 2 so Claude sees and fixes
# them (PostToolUse can't undo the edit; it only reports). This hook works on
# the one changed file for speed; the whole-repo versions are Makefile targets.
set -uo pipefail

input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[[ -z "$file" || ! -f "$file" ]] && exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rel="${file#"$root"/}"
cd "$root" || exit 0

problems=""
run() { out=$("$@" 2>&1) || problems+=$'\n'"\$ $*"$'\n'"$(tail -n 30 <<<"$out")"; }

case "$rel" in
  *.py)
    run uv run ruff format "$rel"
    run uv run ruff check --fix "$rel"
    ;;
  web/src/api/schema.d.ts|web/openapi.json) ;;  # generated
  web/*.ts|web/*.tsx|web/*.css|web/*.json)
    run web/node_modules/.bin/prettier --write --ignore-unknown "$rel"
    ;;
  deploy/k8s/*)
    run kubectl kustomize deploy/k8s/overlays/homelab
    ;;
  deploy/azure/*.tf)
    dir=$(dirname "$rel")
    run terraform -chdir="$dir" fmt "$(basename "$rel")"
    [[ -d "$dir/.terraform" ]] || run terraform -chdir="$dir" init -backend=false -input=false
    run terraform -chdir="$dir" validate -no-color
    ;;
esac

# API changed -> regenerate the TypeScript client so web/ can't drift.
case "$rel" in
  copilot/api.py|copilot/schemas/*|copilot/routes/*)
    run bash -c 'uv run python -c "import json; from copilot.api import app; print(json.dumps(app.openapi()))" > web/openapi.json'
    run web/node_modules/.bin/openapi-typescript web/openapi.json -o web/src/api/schema.d.ts
    ;;
esac

if [[ -n "$problems" ]]; then
  echo "Post-edit checks failed for $rel:$problems" >&2
  exit 2
fi
exit 0
