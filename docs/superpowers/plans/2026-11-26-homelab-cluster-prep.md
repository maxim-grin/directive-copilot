# Homelab Cluster Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Postgres + pgvector, local embeddings and a LiteLLM gateway running on the Talos `prod` cluster, every model alias proven with `curl`.

**Architecture:** `dev` is paused and its memory moves to the `prod` workers. A new ArgoCD app, `directive-copilot`, in the homelab repo holds three workloads and a backup CronJob. Agents write and verify the PRs; the owner merges, applies and restarts.

**Tech Stack:** Terraform (`telmate/proxmox`), ArgoCD + Kustomize, argocd-vault-plugin, `pgvector/pgvector`, Ollama, LiteLLM proxy, OpenRouter.

**Spec:** [2026-11-26-homelab-cluster-prep-design.md](../specs/2026-11-26-homelab-cluster-prep-design.md)

## Global Constraints

- Two repos: **DC** = `/home/ubuntu/directive-copilot` (branch `feat/homelab-cluster-prep`, draft PR #1), **HL** = `/home/ubuntu/homelab`. Each follows its own `CLAUDE.md`.
- Never merge, never push to `main`, never `terraform apply`, never touch a live cluster or VM. Steps marked **owner** are the owner's.
- Run `git push` and `gh pr create` as separate commands (DC's hook reads a chained `--base main` as a push to `main`). DC has no git identity configured: set author and committer per command from `main`'s last commit; HL has its own.
- No secret value in either repo. Only `<path:kv-prod/data/directive-copilot/...#FIELD>` placeholders.
- Plain Kustomize manifests; no Helm chart, no AppProject change.
- Pods meet `restricted`: `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, drop `ALL`.
- Images, tag and digest in the manifest:
  - `pgvector/pgvector:0.8.7-pg16@sha256:484e838076e04939d27d3e176e91c86eea96236126023be8d3059761122e579f`
  - `ollama/ollama:0.40.18@sha256:1cabd20e1762a7a8444bf4a7110b346d923cd77ab6c97c984434140638c913ec`
  - `ghcr.io/berriai/litellm:v1.111.0@sha256:ce00096d012719d58c52cecfa373f7c6256dd1b0ff08f6fa607e10e9628f1f46`
- Embedding model `nomic-embed-text:v1.5` (768-dim, 274 MB).
- Namespace `directive-copilot`; Services `postgres:5432`, `ollama:11434`, `litellm:4000`; every PVC names `nfs-prod`.
- `prod`: workers 7168 MB, `node_cores = 4`, `node_disk_size = "40G"`.
- Docker tests run on a VM with 19 GB free disk and 4 GB RAM: remove pulled images afterwards.

## Review Focus

1. **Node disk fills on image pull.** Compressed images: Ollama 3.4 GB, LiteLLM 0.7 GB, pgvector 0.16 GB, on 20 GB node disks. Expect no `DiskPressure` (Tasks 2, 3, 7).
2. **LiteLLM silently drops provider pinning**, so evals later move between hosts. Expect the upstream request to carry it (Task 6).
3. **A failed dump counts as a backup** or rotates good ones away. Expect a non-zero exit and nothing pruned (Task 4).
4. **Pod restart with no internet.** Ollama must start from the model already on its volume (Task 5).
5. **`chat-dev` fails under zero data retention**: free providers may be excluded. Expect a clear result and an owner decision, not a quietly relaxed setting (Task 7).

---

### Task 1: DC, drop the in-repo Kubernetes leftovers

**Files:** Modify `Makefile`, `.github/workflows/ci.yml`, `README.md`.

- [x] **Step 1:** In `Makefile`, remove `K8S_OVERLAY`, the `kubectl` presence check and the `kubectl kustomize` line from `check-infra`; its help text becomes `Terraform fmt + validate (no cloud access)`.
- [x] **Step 2:** In `ci.yml`, remove the `azure/setup-kubectl` step; in the `infra` job comment, say Terraform only.
- [x] **Step 3:** In `README.md`, say the homelab app is deployed from the `homelab` repo, that the port-forwards need the `prod` kube context, and change the `check-infra` comment to `Terraform validation, no cloud access`.
- [x] **Step 4: Verify.** `grep -rnE 'kubectl kustomize|K8S_OVERLAY|setup-kubectl|Kustomize \+' Makefile .github README.md` prints nothing; `make lint test` passes. `make check-infra` still fails until `deploy/azure/` exists; CI runs it only when the `infra` flag is set: `deploy/` changes, plus tags, new branches and a failed diff.
- [x] **Step 5:** Commit `chore: drop in-repo kubernetes checks`, push, `gh pr ready 1`.

### Task 2: HL, pause `dev` and grow `prod` (branch `feat/pause-dev-grow-prod`)

**Files:**
- Modify: `argocd/apps/{cert-manager,cert-manager-issuers,ingress-nginx,jobboard,kube-prometheus-stack,monitoring-secrets,nfs-provisioner,shortener}/config.yaml`
- Delete: `argocd/environments/prod/applications/clusters-dev.yaml`
- Modify: `terraform/environments/dev/{main.tf,dev.tftest.hcl}`, `terraform/environments/prod/{variables.tf,prod.tftest.hcl,prod.tfvars.example}`
- Create: `docs/decisions/0034-dev-paused-prod-grown.md`
- Modify: `docs/decisions/README.md`, `docs/runbooks/{playbooks-and-terraform.md,checks.md}`, `docs/operations.md`, `README.md`, `CLAUDE.md`, `argocd/README.md`

Keep every `argocd/apps/*/dev/` directory, `argocd/apps/clusters/dev/` and the VM definitions: resuming `dev` must be a revert.

- [x] **Step 1: Failing tests.** In `dev.tftest.hcl` flip the boot assertion to `alltrue([... : !n.start_at_node_boot])`, message `dev is paused: neither node starts at node boot`. In `prod.tftest.hcl` add `run "node_defaults"` asserting `var.node_cores == 4 && var.node_disk_size == "40G"`.
- [x] **Step 2:** In each of the two environment directories run `terraform init -backend=false && terraform test`. Expected: the new assertions FAIL.
- [x] **Step 3:** Set `start_at_node_boot = false` on `module "kubeadm-dev"` only (`claude_code` stays `true`). Change the two `prod` defaults. In the example tfvars set both workers to `memory = 7168`, with a comment that `dev`'s 6 GB moved here.
- [x] **Step 4:** `terraform test` passes in both; `terraform fmt -check -recursive terraform` is clean.
- [x] **Step 5:** Remove only the `env: dev` entry (and comments about it) from the eight `config.yaml` files; delete `clusters-dev.yaml`.
- [x] **Step 6:** `grep -rn 'env: dev' argocd/apps/*/config.yaml` prints nothing; `scripts/check-manifests.sh` ends `check-manifests: ok`.
- [x] **Step 7:** ADR 0034: `dev` paused, memory and sizes as above, no staging (suspends the dev-first step of 0028), disks grown because the new app's images do not fit 20 GB, rejected options from the spec. Add its index row.
- [x] **Step 8:** Runbook entry "Pause and resume dev" holding Task 3's commands (with `$PROD_KC`) and the reverse order for resuming (shrink `prod`, start the VMs, revert, `dev_register` playbook). Mark `dev` as paused wherever the listed docs describe it as running, including "promote jobboard" (new tags now go straight to `prod`).
- [x] **Step 9:** `scripts/check-runbooks.sh` and `pre-commit run --all-files` pass. Commit `ops: pause dev and grow prod`, push, open a ready PR whose description links the runbook entry.

### Task 3: Owner, roll out capacity

Runs after Task 8. The homelab runbook entry for removing `dev` holds the commands and stop gates and wins over this summary.

- [ ] **Step 1:** On `pve`, `lvs` shows the thin pool has well over 60 GB free after the `dev` disks go (three `prod` disks grow by 20 GB). In `prod.tfvars`, set both workers to 7168 and remove or update any `node_cores` / `node_disk_size` override.
- [ ] **Step 2:** Dump jobboard's database.
- [ ] **Step 3:** Merge the capacity PR. Expected: `clusters-dev` is gone; `dev-*` apps show `Unknown`.
- [ ] **Step 4:** Only then, delete the eight `dev-*` Applications, finalizers removed first.
- [ ] **Step 5:** `terraform apply` in `environments/dev`: 0 add, 0 change, **2 destroy** (4101 and 4201 only; nothing named `claude_code`). Anything else is a stop. Never `terraform destroy` this root.
- [ ] **Step 6:** `terraform apply` in `environments/prod`: 0 add, 3 change, 0 destroy.
- [ ] **Step 7:** Restart the `prod` nodes one at a time, workers first.
- [ ] **Step 8: Verify.** 4 CPU on all three nodes, about 7 GiB on workers, disk near 40 GB; all `prod-*` apps `Synced`/`Healthy`; `jobs.mgryn.cc` answers; `qm list` has no 4101 or 4201.

### Task 4: HL, namespace, Postgres and backup (branch `feat/directive-copilot-app`)

**Files:**
- Create under `argocd/apps/directive-copilot/`: `config.yaml`, `base/{kustomization.yaml,namespace.yaml,postgres-service.yaml,postgres-statefulset.yaml,backup-pvc.yaml,backup-cronjob.yaml,backup.sh}`, `prod/{kustomization.yaml,secret.yaml}`
- Create: `scripts/tests/directive-copilot-backup.test.sh`
- Modify: `.github/workflows/ci.yaml` (shellcheck list and a test step, beside the `verify-dev` ones)

**Interfaces:**
- Produces: Secret `directive-copilot-db` key `POSTGRES_PASSWORD`; database and user `copilot` on `postgres:5432`; `base/kustomization.yaml`, which Tasks 5 and 6 extend.
- `backup.sh`: env `BACKUP_DIR` (default `/backup`) plus libpq `PG*`. Dumps with `pg_dump -Fc` to `<name>.partial`, checks it with `pg_restore --list`, renames to `copilot-YYYYMMDDTHHMMSSZ.dump`, then keeps the 14 newest `*.dump` by name. Any failure: exit non-zero, remove the partial, prune nothing.

- [ ] **Step 1: Failing test** with stub `pg_dump` / `pg_restore` on `PATH`, in the style of `scripts/tests/verify-dev.test.sh`. Cases:
  - 15 old dumps + success: exit 0, exactly 14 `*.dump`, the new one present, the two oldest gone.
  - `pg_dump` exits 1: non-zero exit, all 15 old dumps still there, no new `*.dump`, no `*.partial`.
  - `pg_restore` exits 1: same assertions.
- [ ] **Step 2:** Run it. Expected: FAIL, script missing.
- [ ] **Step 3:** Write `backup.sh`; run the test to PASS; `shellcheck` both.
- [ ] **Step 4:** Write the manifests, following `argocd/apps/jobboard` and `shortener`.
  - `config.yaml`: one `prod` entry, `createNamespace`, `serverSideApply`, `serverSideDiff` all `true` (ADR 0030).
  - Namespace labelled `pod-security.kubernetes.io/enforce: restricted`.
  - StatefulSet `postgres`, 1 replica: uid, gid and `fsGroup` 999; `POSTGRES_USER`/`POSTGRES_DB` `copilot`; `PGDATA=/var/lib/postgresql/data/pgdata`; `POSTGRES_INITDB_ARGS="--locale=en_US.UTF-8 --encoding=UTF8"`; `pg_isready` probes; requests `100m`/`256Mi`, memory limit `1Gi`; claim template `data`, `10Gi`, with `apiVersion` and `kind` spelled out.
  - CronJob `postgres-backup`: Postgres image, `0 9 * * *`, `concurrencyPolicy: Forbid`, `restartPolicy: Never`, same uid, script from a `configMapGenerator`, PVC `postgres-backup` `5Gi`, `PGHOST=postgres`.
  - `prod/secret.yaml`: placeholder `<path:kv-prod/data/directive-copilot/db#POSTGRES_PASSWORD>`.
- [ ] **Step 5: Real restore check** (one-off, not committed): start the pgvector image with `--user 999:999`, run `backup.sh` against it from the same image. Expected: one `.dump`, and `psql -tAc "select default_version from pg_available_extensions where name='vector'"` prints `0.8.7`.
- [ ] **Step 6:** `scripts/check-manifests.sh` ok and lists `prod-directive-copilot`. Commit `feat: add directive-copilot database`.

### Task 5: HL, Ollama for embeddings

**Files:** Create `base/{ollama-deployment.yaml,ollama-service.yaml,ollama-pvc.yaml,pull-model.sh}` under the app; modify `base/kustomization.yaml`.

**Interfaces:**
- Consumes: Task 4's `base/kustomization.yaml`.
- Produces: `http://ollama:11434` serving `nomic-embed-text:v1.5`.
- `pull-model.sh`: env `MODEL`; starts `ollama serve` in the background, waits up to 60 s for it, exits 0 if `ollama show "$MODEL"` succeeds, otherwise `ollama pull "$MODEL"`; non-zero on timeout or pull failure.

- [ ] **Step 1: Failing check** (one-off, Docker): run the script in the Ollama image as `--user 10001:10001`, `HOME=/models`, `OLLAMA_MODELS=/models`, on a volume made mode 0777 (as the NFS share is). Expected: FAIL, script missing.
- [ ] **Step 2:** Write the script. First run exits 0 after pulling. Second run with `--network none` exits 0 without pulling.
- [ ] **Step 3:** Start the server on the same volume and user; `POST /v1/embeddings` with `{"model":"nomic-embed-text:v1.5","input":"hello"}` returns `.data[0].embedding` of length 768.
- [ ] **Step 4:** Manifests: Deployment `ollama`, 1 replica, `Recreate`; uid, gid, `fsGroup` 10001; init container `pull-model` and server share env and the PVC `ollama-models` (`2Gi`); `OLLAMA_NUM_PARALLEL=1`; HTTP readiness and liveness on `/`; server requests `100m`/`512Mi`, limits `cpu: 2`, `memory: 2Gi`; script from a `configMapGenerator`.
- [ ] **Step 5:** `shellcheck` the script (add to the CI list); `scripts/check-manifests.sh` ok. Commit `feat: add ollama embeddings`. Remove the Ollama image.

### Task 6: HL, LiteLLM, docs and PR

**Files:**
- Create: `base/{litellm-deployment.yaml,litellm-service.yaml,litellm-config.yaml}`, `docs/decisions/0035-directive-copilot-data-on-nfs.md`
- Modify: `base/kustomization.yaml`, `prod/secret.yaml`, `ansible/secret.yaml.example`, `docs/decisions/README.md`, `docs/runbooks/{checks.md,backups-and-recovery.md}`, `README.md`, `argocd/README.md`

**Interfaces:**
- Consumes: `ollama:11434`.
- Produces: `http://litellm:4000`, aliases `chat`, `judge`, `chat-dev`, `embed`; Secret `directive-copilot-llm` keys `LITELLM_MASTER_KEY`, `OPENROUTER_API_KEY` (paths `directive-copilot/llm#<KEY>`).

- [ ] **Step 1: Write `litellm-config.yaml`** (IDs checked against `openrouter.ai/api/v1/models` on 2026-11-26):

| `model_name` | `litellm_params` |
| --- | --- |
| `chat` | `model: openrouter/openai/gpt-6-luna`, `reasoning_effort: low`, `extra_body.provider: {only: [openai], allow_fallbacks: false}` |
| `judge` | `model: openrouter/anthropic/claude-haiku-5.5`, `reasoning_effort: low`, `extra_body.provider: {only: [anthropic], allow_fallbacks: false}` |
| `chat-dev` | `model: openrouter/openrouter/free` |
| `embed` | `model: ollama/nomic-embed-text:v1.5`, `api_base: http://ollama:11434` |

OpenRouter entries use `api_key: os.environ/OPENROUTER_API_KEY`; `general_settings.master_key: os.environ/LITELLM_MASTER_KEY`. No database.

- [ ] **Step 2: Forwarding check** (one-off, Docker, no real key, script in the scratchpad). Run the pinned LiteLLM image with this config, dummy keys and `OPENROUTER_API_BASE` pointing at a local server that records request bodies and returns a minimal chat completion. Send one request each to `chat`, `judge`, `chat-dev`. Assert:
  - `chat`: `model == "openai/gpt-6-luna"`, `provider == {"only": ["openai"], "allow_fallbacks": false}`, effort `low` (`reasoning_effort` or `reasoning.effort`).
  - `judge`: same with `anthropic/claude-haiku-5.5` and `["anthropic"]`.
  - `chat-dev`: `model == "openrouter/free"`.
  - A request without the master key gets 401.

  If effort is dropped or rejected, move it to `extra_body.reasoning: {effort: low}` and rerun. `embed` needs the real Ollama: run it alongside if disk allows, expect length 768; otherwise Task 7 covers it.
- [ ] **Step 3:** Manifests: Deployment `litellm`, uid 65532 (the image's user), args `--config /app/config/config.yaml --port 4000`, config from a `configMapGenerator` (key `config.yaml`), probes `/health/liveliness` and `/health/readiness`, requests `100m`/`512Mi`, memory limit `1536Mi`, both keys from the Secret. Add both placeholders to `prod/secret.yaml` and both paths (`directive-copilot/db`, `directive-copilot/llm`) under `kv-prod` in `secret.yaml.example`. Confirm the container starts as that uid in Docker.
- [ ] **Step 4:** ADR 0035: app on `prod`, Postgres and dumps on two `nfs-prod` volumes, same-SSD limit, no operator. Runbooks: "Check directive-copilot" in `checks.md` (Task 7 steps 4 to 6 as commands, keys read without echo) and "Dump directive-copilot's database" in `backups-and-recovery.md` (manual Job from the CronJob; retained-volume note). Add the app to both READMEs.
- [ ] **Step 5:** `scripts/check-manifests.sh`, `scripts/check-runbooks.sh`, `pre-commit run --all-files` pass. Commit `feat: add litellm gateway`, push, open a ready PR with the owner steps linked. Remove the test images.

### Task 7: Owner, secrets, deploy and prove

- [ ] **Step 1:** OpenRouter: account, zero data retention on, about $15 credit, auto top-up off, one API key.
- [ ] **Step 2:** `ansible-vault edit secret.yaml`: add both `kv-prod` paths (password and master key from `openssl rand -hex 32`; master key prefixed `sk-`). Run the runbook's **Seed**; Vault stays unsealed. This must precede the merge.
- [ ] **Step 3:** Merge the app PR. `prod-directive-copilot` is `Synced`/`Healthy`; all pods `Ready`; no node reports `DiskPressure`.
- [ ] **Step 4:** `kubectl -n directive-copilot exec postgres-0 -- psql -U copilot -d copilot -tAc "select default_version from pg_available_extensions where name='vector'"` prints `0.8.7`.
- [ ] **Step 5:** `kubectl -n directive-copilot create job backup-check --from=cronjob/postgres-backup` completes and its log names a `.dump` (the script has already run `pg_restore --list` on it).
- [ ] **Step 6:** Port-forward `svc/litellm 4000`. `chat`, `judge`, `chat-dev` answer `/v1/chat/completions`; `embed` returns 768 numbers from `/v1/embeddings`. OpenRouter's activity page shows OpenAI and Anthropic as providers. If `chat-dev` fails on data policy, record the error and decide; do not silently turn retention off.
- [ ] **Step 7:** Comment on the app PR with each worker's memory use (Grafana) and `kubectl -n directive-copilot get pods` output: the baseline for later milestones.

### Task 8: HL, remove the `dev` cluster instead of pausing it (branch `feat/pause-dev-grow-prod`)

Changes Task 2's result: the owner chose to destroy the two kubeadm VMs. Runs before Task 3.

**Files:** `terraform/environments/dev/{main.tf,outputs.tf,dev.tftest.hcl}`, ADR 0034 and its index row (unmerged, may be renamed), ADR 0028 Status line, the "Pause and resume dev" runbook entry, and every doc note Task 2 added.

- [ ] **Step 1: Failing test.** `dev.tftest.hcl` asserts the root plans `claude-code` (name and vmid 102) and no longer expects kubeadm nodes. Run `terraform test`: FAIL while the outputs and module remain as they are.
- [ ] **Step 2:** Remove `module "kubeadm-dev"` and the outputs that only describe it. `module "claude_code"` is unchanged. Keep variables, `ansible/` dev files and `argocd/apps/*/dev/` so a rebuild is a restore from git; satisfy tflint without deleting what a rebuild needs. No `removed` or `moved` block: the destroy is intended.
- [ ] **Step 3:** `terraform test`, `terraform fmt -check`, `tflint`, `scripts/check-manifests.sh`, `scripts/check-runbooks.sh` pass.
- [ ] **Step 4:** ADR 0034 states: `dev` destroyed, how to rebuild, old `nfs-dev` directories remain on `nfs-01`, no staging.
- [ ] **Step 5:** Runbook: remove-`dev` entry (merge, confirm apps `Unknown`, delete apps, apply `dev` with exactly 2 destroy, grow `prod`) with the existing stop gates, never `terraform destroy` in this root; and a rebuild order (shrink `prod`, restore module, outputs, test, app entries and `clusters-dev.yaml`, apply, Ansible, register). Remove pause-only steps (`start_at_node_boot`, shutting down and starting VMs) and `-target` warnings in docs that no longer apply.
- [ ] **Step 6:** Commit `ops: remove dev cluster from terraform`.
