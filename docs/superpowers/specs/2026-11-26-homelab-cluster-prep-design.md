# Homelab cluster prep (milestone 0)

Date: 2026-11-26
Size: a project, spanning this repo and `maxim-grin/homelab`.

## Measured starting point

No app, eval scores, token costs or rows exist yet. Memory sizes below come
from the homelab repo's Terraform code and `.tfvars.example` files. Live
`.tfvars` and actual memory use were **not** checked.

| Machine | Assigned now | After |
| --- | --- | --- |
| Talos `prod` control plane | 4 GB | 4 GB |
| Talos `prod` workers (2) | 4 GB each | 7 GB each |
| kubeadm `dev` control plane + worker | 3 GB each | destroyed |
| `claude-code`, NFS, Vault VMs | 4 + 2 + 2 GB | unchanged |
| LXCs (5) | 256 MB each | unchanged |
| **Total of 32 GB** | **27.25 GB** | **27.25 GB** |

vCPU per `prod` node goes from 2 to 4 (`node_cores` covers all three nodes).
The host has 6 cores, 12 threads; embeddings and later the decision judge
are CPU-bound.

Node disks go from 20 GB to 40 GB (all three nodes, same restart): the
compressed images alone are 3.4 GB (Ollama), 0.7 GB (LiteLLM) and 0.16 GB
(pgvector), and 10 GB disks already caused evictions on `dev`.

## Intent

Everything the app needs from the homelab exists and is proven before any
app code: a database with pgvector, local embeddings, and a LiteLLM gateway
answering on all four aliases.

## Goals

- `prod` workers at 7 GB, all nodes Ready, existing apps still healthy.
- An ArgoCD app `directive-copilot` holding Postgres + pgvector, a nightly
  dump, Ollama and LiteLLM.
- `chat`, `judge`, `chat-dev` and `embed` each answer a `curl`; `embed`
  returns 768 numbers.
- `PLAN.md` and the ADRs describe this setup.

## Non-goals

- App image, app Deployment, Ingress, DNS name, migrations, ingest.
- The decision judge service.
- Off-machine backups, monitoring or alert rules for the new app.
- The Azure stage.

## Anti-goals

- A secret in either public repo.
- Destroying anything but the two kubeadm `dev` VMs. `claude-code` is defined
  in the same Terraform root and must survive; `dev`'s old NFS directories
  stay on `nfs-01`.
- An existing `prod` app (jobboard, shortener, monitoring) losing data.
- Terraform applied, VMs restarted or `main` merged by an agent.

## Constraints

- Merging to `homelab` `main` deploys. Its `CLAUDE.md` governs work there:
  branch first, one PR per logical change, ADR and runbook in the same PR.
- Secrets reach manifests only as `<path:kv-prod/data/directive-copilot/...>`
  placeholders; values are seeded from `ansible/secret.yaml`.
- Plain Kustomize manifests, so no new chart repo in the AppProject.
- Images pinned to a version, never `latest` (homelab ADR 0007).
- Pods meet the `restricted` pod security level, as `shortener` does.
- Prod resize needs a hand restart (`automatic_reboot = false`), one node at
  a time. The single control plane's restart takes the API down briefly.

## Approaches

**Where it runs**

| Option | Trade-off |
| --- | --- |
| Grow the `dev` worker | Disposable cluster, but taking memory from elsewhere leaves the host under 3 GB |
| Existing `prod` workers as they are | Nothing to resize; 4 GB workers already run monitoring and jobboard |
| New k3s VM | Matches the old plan; needs the most memory |
| **Destroy the `dev` cluster, grow `prod`** (picked) | Same host commitment, survives like other real apps; no staging cluster. First picked as a shutdown; the owner chose destroy, since nothing on `dev` is worth keeping |

**Where manifests live**

| Option | Trade-off |
| --- | --- |
| **`homelab/argocd/apps/directive-copilot/`** (picked) | Argo CD's recommended split of config from source; fits the ApplicationSet and Vault; a new env var takes two PRs |
| `deploy/k8s/` here, Argo pointed at this repo | One PR per change; needs its own Application and allowlist entry, against the homelab's one pattern |

## Design

### Pull requests, in order

1. **This repo:** this spec, the plan, `PLAN.md`, ADR 0006, and the
   leftovers: drop the Kustomize half of `make check-infra` (and
   `setup-kubectl` in CI), and say in `README.md` which kube context the
   port-forwards use.
2. **`homelab`, capacity:** retire `dev` from ArgoCD, remove its VMs from
   Terraform, raise `prod` memory, cores and disks, ADR and runbooks.
3. **`homelab`, app:** the `directive-copilot` app.

### Retiring `dev` (order matters)

1. Remove the `env: dev` entries and stop anything that would re-register the
   cluster.
2. The same merge removes the `dev` cluster registration. Then delete the
   `dev-*` Applications **without cascade**: the ApplicationSet never deletes
   them itself, and a cascade would remove the workloads and their `nfs-dev`
   data.
3. `terraform apply` in `environments/dev`: exactly 2 to destroy, nothing
   else. Never `terraform destroy` that root.
4. Only then raise `prod` memory, so the host is never over-committed.

Rebuilding: shrink `prod` first, restore the module and app entries from
git, apply, run the Ansible playbooks, register the cluster. Volumes start
empty.

### The app

`argocd/apps/directive-copilot/` with `config.yaml` (one `prod` entry),
`base/` and `prod/`, namespace `directive-copilot`.

| Part | Decision |
| --- | --- |
| Postgres | One-replica StatefulSet, `pgvector/pgvector` for Postgres 16, `nfs-prod` volume, Service `postgres`, database and user `copilot` |
| Backup | Nightly `pg_dump` CronJob to a separate `nfs-prod` volume, newest 14 kept. The NFS `backups` share is not exported to the workers |
| Ollama | `nomic-embed-text` only, model pulled onto a volume without a hand step, `OLLAMA_NUM_PARALLEL=1`, CPU limit |
| LiteLLM | Service `litellm:4000`, alias ConfigMap, master key required, no database. OpenRouter aliases pin the provider with fallbacks off |
| Secrets | Postgres password, LiteLLM master key, OpenRouter key |

Aliases and targets are the table in `PLAN.md`'s Config section. Check the
model IDs against OpenRouter's current catalogue.

### Operator steps (only the owner can do these)

OpenRouter account (zero data retention off for now, see ADR 0008; about
$15, auto top-up off),
secret values into `secret.yaml` and the Vault seed, PR merges, ArgoCD
deletes, `terraform apply`, VM restarts, and a kube context
for `prod`. This repo's hook allows only a context named `homelab`: name it
that, or set `DC_KUBE_CONTEXT`.

### Done when

- `kubectl get nodes` shows three Ready nodes with the new sizes.
- No `dev-*` Application remains; `qm list` shows no 4101 or 4201 and
  `claude-code` still runs; `jobs.mgryn.cc` still serves.
- `directive-copilot` is Synced, Healthy, and its pods Ready.
- `vector` appears in `pg_available_extensions` (the app's migration creates
  it later).
- A manually triggered backup produces a dump `pg_restore --list` reads.
- Four `curl` checks through a port-forward pass.
- Node memory use is recorded, as the baseline for later milestones.

## Risks

- Memory estimate for this stack, 2–3 GB (4–5 GB with the decision judge),
  is a guess until measured. Two 7 GB workers should hold it.
- Live `prod.tfvars` may differ from the example; read the Terraform plan,
  and treat any destroy as a stop.
- Postgres on NFS follows jobboard's precedent; it is not tested for this
  load.
- Something in the homelab may still expect `dev` to be reachable
  (playbooks, checks, dashboards). Search before destroying it.

## Open, not blocking

The host is shared, so `PLAN.md`'s "hardware share" cost estimate needs a
rule for what fraction belongs to this app. Decide at the cost milestone.

## Left to the builder

Image versions, resource requests and limits (start small, adjust from
measurements), how the model pull runs, the dump schedule, and manifest file
layout within the homelab's conventions.
