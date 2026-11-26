# 0006: ArgoCD manifests in the homelab repo, Terraform on Azure

Status: Superseded by [0007](0007-dev-cluster-destroyed-manifests-unchanged.md)
Date: 2026-11-26

Supersedes [0003](0003-kustomize-on-the-homelab-terraform-on-azure.md).

## Context

0003 assumed a cluster this repo would deploy to itself. The homelab already
runs a Talos `prod` cluster delivered by ArgoCD from the public
[homelab](https://github.com/maxim-grin/homelab) repo: one ApplicationSet
generates an app from each `argocd/apps/<app>/config.yaml`, secrets come
from Vault through argocd-vault-plugin, and a merge to that repo's `main` is
the deploy.

Argo CD's
[best practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
call keeping manifests apart from application source highly recommended.

The host has 32 GB, about 27 GB of it assigned to VMs and containers (sizes
from the homelab's Terraform code and examples, not measured). The `prod`
workers have 4 GB each, too little to add this app.

## Decision

- Homelab manifests live in the homelab repo, under
  `argocd/apps/directive-copilot/`, following that repo's conventions. This
  repo holds no Kubernetes manifests and no homelab deploy targets.
- The app runs on the `prod` cluster. The `dev` cluster is shut down (not
  destroyed) and its 6 GB moves to the two `prod` workers.
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
- There is no staging cluster while `dev` is down, for this app or any
  other on the homelab.
- `make check-infra` covers Azure only; the homelab repo's CI checks the
  manifests.
- Revisit if the Azure stage moves to AKS, or `dev` is needed again and the
  host has the memory for it.
