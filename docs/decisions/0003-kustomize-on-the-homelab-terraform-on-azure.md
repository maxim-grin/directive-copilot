# 0003: Kustomize on the homelab, Terraform on Azure

Status: Superseded by [0006](0006-argocd-manifests-in-homelab-terraform-on-azure.md)
Date: 2026-11-25

## Context

The homelab is Kubernetes; Azure Container Apps doesn't use Kubernetes
manifests, so one manifest set can't cover both. Bicep was the first plan
for Azure; Terraform was chosen instead as the more widely used tool. AKS
would let the manifests be reused but costs more than a demo needs.

## Decision

- Homelab: Kustomize (`deploy/k8s/`), base plus a `homelab` overlay.
- Azure: Terraform with the `azurerm` provider (`deploy/azure/`), remote
  state in an Azure Storage account created once by `deploy/azure/bootstrap`.
- Never run `terraform apply` with `-auto-approve`, and leave `destroy` to
  the owner. Agents are blocked from both by `.claude/hooks/guard-bash.sh`.

## Consequences

- Two deployment definitions to keep in step; `make check-infra` validates
  both in CI without cloud credentials.
- Revisit if the Azure stage moves to AKS: then one Kustomize tree with an
  `azure` overlay would replace the Container Apps Terraform.
