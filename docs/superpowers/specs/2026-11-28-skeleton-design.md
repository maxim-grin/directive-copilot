# Skeleton (milestone 1)

Date: 2026-11-28
Size: a project, spanning this repo and `maxim-grin/homelab`.

## Measured starting point

- This repo holds `tools/` and its tests (25 pass). No `copilot/`, no
  Dockerfile, and `web/` has only `.prettierignore`.
- Homelab: Postgres 16 (pgvector 0.8.7 available, extension not created),
  LiteLLM and Ollama run in `directive-copilot`. The app has no tables.
- Idle workers used 2931 MiB and 1854 MiB of 6915 MiB; LiteLLM 1004 MiB.
- No eval scores, token costs or rows exist yet.
- CI's `image` job also builds `services/decision`, which does not exist, so
  a version tag pushed today would fail.

## Intent

A deployed, empty app before any features: merging to `homelab` migrates the
database and serves a page at `https://aerc.mgryn.cc`. Every later milestone
ships through the same path.

## Goals

- The page loads on the home network with a valid certificate and shows
  whether the API is ready.
- The sync migrates the database, on an empty one and on every later sync.
- `ghcr.io/maxim-grin/directive-copilot:0.1.0` is public.
- A release is a version tag here, then an image bump in `homelab`.

## Non-goals

Model calls, ingestion, application tables, login, public internet access,
Azure, the decision service, metrics and alerts.

## Anti-goals

- A secret in either public repo.
- A migration run against the live database from a laptop or a test.
- A migration that breaks the app version still serving.
- A health check that calls a model (costs money).

## Constraints

- Namespace enforces the `restricted` pod security level.
- One image for the app and the migration, same image later on Azure; all
  differences are env vars.
- Home network only: DNS-only records pointing at the worker nodes, as for
  `jobs.mgryn.cc`.
- The database password is hex, so it can sit in a URL unescaped.
- Revisions live in `copilot/migrations/versions/`, are immutable once
  committed, and have one head.

## Approaches

How migrations run on deploy:

| Approach | Trade-off |
| --- | --- |
| Init container in the app pod | Same as `jobboard`, fewest parts; runs once per pod, failure seen only on the pod |
| **ArgoCD `Sync` hook Job in a wave after Postgres** (picked) | Runs once whatever the replica count, visible as a resource, same shape as an Azure Job; needs sync waves, and an unhealthy earlier wave stalls a release |
| ArgoCD pre-sync hook | Runs before Postgres exists on a first deploy |
| By hand | One sync would not give a working app |

## Design

### This repo

| Part | Decision |
| --- | --- |
| API (`copilot/api.py`) | `GET /healthz` checks nothing external. `GET /readyz` runs a query against the database, 503 if it fails; it does not check the gateway. Serves `web/dist` with an `index.html` fallback; an unknown `/api/...` path is a JSON 404, never the page |
| Settings | Environment variables only. `DATABASE_URL` is required; model variables arrive with the milestone that uses them |
| Migrations | Alembic. First revision: `CREATE EXTENSION IF NOT EXISTS vector` |
| `python -m copilot.migrate` | Upgrades to head. If the database is at a revision this image does not have (a rollback), logs a warning and exits 0. Every other failure exits non-zero |
| Web | Vite, React, TypeScript. One page: title, readiness status, and the footer "Demo only; not legal or regulatory advice. Always consult the current directive on aer.ca." API types generated from OpenAPI |
| Image | Multi-stage Dockerfile, numeric non-root user, port 8000 |
| CI | Drop the `decision` image until milestone 7. Pull requests build the image without publishing |
| `PLAN.md` | `/readyz` wording updated to match |

### `homelab`

Added to `argocd/apps/directive-copilot/`:

- Deployment (one replica) with both probes, Service, and Ingress for
  `aerc.mgryn.cc` using `letsencrypt-prod`.
- Job running the migrate command as a `Sync` hook, replaced before the next
  run so the last log stays readable.
- Sync waves: what the database needs first, then the migration, then the
  app. LiteLLM, Ollama and the backup never come before the migration, so a
  broken gateway cannot block a release.
- `DATABASE_URL` built in the secret manifest from the existing password
  placeholder. No new Vault field.
- Image pinned by tag and digest. ADR and runbook entry.

### Rule for every later milestone

A migration must work with the previous release's code: add first, remove a
release later. The old pods serve while the migration runs.

### Release order (owner)

1. Add the two DNS records.
2. Merge the app PR here; tag `v0.1.0`.
3. Check the package's visibility and make it public if it is not.
4. Merge the `homelab` PR.

## Done when

- `https://aerc.mgryn.cc` loads from the home network, certificate valid,
  page reads ready.
- A test shows `/readyz` returns 503 with the database unreachable.
- Integration tests migrate an empty pgvector database twice, and the migrate
  command exits 0 against a database ahead of it.
- `prod-directive-copilot` is `Synced` and `Healthy`, the migration Job
  completed, and `select extversion from pg_extension where extname =
  'vector'` returns a row.
- The image pulls without credentials.
- Postgres, LiteLLM and Ollama stay Ready.

## Risks

- Adding waves to a running app has not been tried on this cluster.
- The database-ahead rule would also let a wrongly old image deploy; only the
  warning shows it.
- A new GHCR package may start private; the app would sit in
  `ImagePullBackOff`.

## Left to the builder

Library and base image versions, homelab file layout, wave numbers, resource
requests and limits, page styling.
