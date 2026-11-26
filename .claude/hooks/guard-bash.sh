#!/usr/bin/env bash
# PreToolUse (Bash): guards that need logic a permission pattern can't
# express (current branch, kube context, flags in any position). Static
# rules (force push, gh pr merge, az group delete, secrets via cat) live in
# permissions in .claude/settings.json.
#   deny -> exit 2 with a reason
#   ask  -> JSON permissionDecision "ask" so the user confirms
set -uo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -z "$cmd" ]] && exit 0

HOMELAB_CONTEXT="${DC_KUBE_CONTEXT:-homelab}"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

deny() { echo "Blocked: $1" >&2; exit 2; }
ask() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",
    permissionDecision:"ask", permissionDecisionReason:$r}}'
  exit 0
}
has() { grep -Eq -- "$1" <<<"$cmd"; }

# Git: main receives finished work only, through a PR the owner merges.
if has '(^|[;&|[:space:]])git[[:space:]]'; then
  branch=$(git -C "$root" branch --show-current 2>/dev/null || true)
  if [[ "$branch" == "main" ]] && has 'git[[:space:]]+(commit|merge|cherry-pick|rebase)([[:space:]]|$)'; then
    deny "you're on main. Create a feature branch first: git checkout -b <feature-name>"
  fi
  has 'git[[:space:]]+push([[:space:]].*)?[[:space:]](origin[[:space:]]+)?(HEAD:)?(refs/heads/)?main([[:space:]]|$)' \
    && deny "don't push to main; push the feature branch and open a PR."
fi

# Kubernetes: homelab context only, no data-destroying deletes
if has '(^|[;&|[:space:]])(kubectl|helm|kustomize|tilt|skaffold)[[:space:]]'; then
  if has '--context[= ]' && ! has "--context[= ]$HOMELAB_CONTEXT([[:space:]]|$)"; then
    deny "only the '$HOMELAB_CONTEXT' kube context is allowed."
  fi
  if has 'kubectl[[:space:]]' && ! has 'kubectl[[:space:]]+kustomize'; then
    current=$(kubectl config current-context 2>/dev/null || echo "none")
    [[ "$current" != "$HOMELAB_CONTEXT" ]] \
      && deny "current kube context is '$current', expected '$HOMELAB_CONTEXT'. Ask the user to switch."
  fi
  has 'kubectl[[:space:]]+delete[[:space:]]+(ns|namespace|namespaces|pvc|pv|persistentvolume)' \
    && deny "deleting namespaces or volumes destroys data. Ask the user to do it."
  has 'kubectl[[:space:]]+delete' && ask "kubectl delete in $HOMELAB_CONTEXT"
fi

# Azure: read-only and what-if run freely; anything that changes resources asks
if has '(^|[;&|[:space:]])az[[:space:]]' \
   && has '[[:space:]](create|update|delete|set|start|stop|restart|purge|deploy|up|push|import)([[:space:]]|$)' \
   && ! has 'what-if'; then
  ask "this az command changes Azure resources (and may cost money). Consider 'az deployment group what-if' first."
fi

# Terraform: plan/fmt/validate run freely; apply asks; destroy and
# auto-approve are the user's call. A hook, not a permission pattern,
# because -chdir can come before the subcommand.
if has '(^|[;&|[:space:]])terraform[[:space:]]'; then
  tf='terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+'
  has '(^|[[:space:]])-auto-approve' && deny "no -auto-approve; let the user review the plan."
  has "${tf}destroy" && deny "terraform destroy is the user's call. Show them the command instead."
  has "${tf}(apply|import|taint|untaint|state[[:space:]]+(rm|mv|push)|force-unlock)" \
    && ask "this terraform command changes Azure resources or state (and may cost money). Run 'terraform plan' first."
fi

exit 0
