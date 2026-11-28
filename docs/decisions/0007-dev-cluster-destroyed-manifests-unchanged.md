# 0007: ArgoCD manifests in homelab, Terraform on Azure, no dev cluster

Status: Accepted
Date: 2026-11-26

Supersedes [0006](0006-argocd-manifests-in-homelab-terraform-on-azure.md),
changing only what happens to the `dev` cluster.

## Context

0006 shut the homelab `dev` cluster down and kept its two VMs so it could be
resumed. Nothing on it is worth keeping, and it can be rebuilt with Terraform
and Ansible. A defined but stopped cluster can also be started again by an
unrelated `terraform apply`, over-committing the 32 GB host.

## Decision

- Homelab manifests live in the
  [homelab](https://github.com/maxim-grin/homelab) repo, under
  `argocd/apps/directive-copilot/`, following that repo's conventions. This
  repo holds no Kubernetes manifests and no homelab deploy targets.
- The app runs on the `prod` cluster. The two `dev` Kubernetes VMs are
  removed from Terraform and destroyed; their 6 GB moves to the two `prod`
  workers. Other machines are untouched.
- A release is a version tag here, which publishes the image to GHCR, then
  an image tag bump in the homelab repo.
- Azure: Terraform with the `azurerm` provider (`deploy/azure/`), remote
  state in an Azure Storage account created once by `deploy/azure/bootstrap`.
- Never run `terraform apply` with `-auto-approve`, and leave `destroy` to
  the owner. Agents in this repo are blocked from both by
  `.claude/hooks/guard-bash.sh`.

## Consequences

- A change that adds an env var needs two PRs, in order: the app change and
  image tag here, then the manifest and tag bump in the homelab repo.
- The LiteLLM alias config is written twice, once per environment.
- There is no staging cluster. Rebuilding `dev` means restoring its
  Terraform module, shrinking `prod` first, and starting with empty volumes.
- `make check-infra` covers Azure only; the homelab repo's CI checks the
  manifests.
- Revisit if the Azure stage moves to AKS, or `dev` is needed again and the
  host has the memory for it.
