# Directive Copilot: plan

The design contract for Directive Copilot, for humans and agents alike:
scope, architecture, interfaces, data model, evaluation, cost tracking,
milestones and definition of done. `README.md` covers running it,
`CLAUDE.md` covers working on it, `docs/decisions/` records why, and
`REFERENCES.md` lists the sources.

A small RAG + agentic workflow app that answers questions about Alberta Energy Regulator (AER) directives, cites the exact clause it used, and sends low-confidence answers to a human reviewer before they're released. It tracks what every answer costs, in LLM tokens and in infrastructure, and measures its own quality with an evaluation set and a pluggable judge.

It's built to run **first on a homelab Kubernetes cluster** (VMs on a single CPU-only mini PC, with the chat models hosted), then **on Azure** with no code changes: only configuration and infrastructure differ.

## The 30-second "aha"

1. The user asks: *"We're flaring during a well test and the gas is about 2% H2S. Who do we notify, and how much notice do we need?"*
2. The app returns a short answer with the cited directive section shown beside it (directive, edition, section number, quoted text).
3. If confidence is low, the answer goes to a **review queue** instead of straight back. A reviewer approves, edits or rejects it, and only then does the user see it.
4. An `/evals` page shows how the system scores on a fixed question set: answer correctness, citation accuracy, refusals and escalations. It compares judges (an LLM vs. a small local decision model) and environments (the same models through OpenRouter vs. Azure) on quality, cost and latency.
5. Every answer shows what it cost (*"1,840 tokens · $0.004"*), and a `/costs` page shows the all-in cost per question: LLM spend plus a share of the infrastructure.

## Scope

**In scope**
- 2–3 directives, **current editions only** (suggested: **Directive 060** flaring/incineration/venting, **Directive 017** measurement requirements, optionally **Directive 056** facility licensing). Download the PDFs from aer.ca into `data/raw/` and note each one's edition date. Directives are reissued and sections get renumbered between editions.
- Ingestion: PDF → section-aware chunks → embeddings → pgvector.
- A 4-node LangGraph workflow (below).
- A pluggable judge (`llm` or `decision`), used by the grade node and by the eval runner. The decision-model judge runs inside the cluster: no external API, nothing leaves the network.
- A minimal UI: an Ask page, a Review queue page, an Evals page and a Costs page.
- An evaluation set of about 20 hand-written cases with expected answers, required facts and expected sections.
- Token and cost tracking per LLM/judge call, plus infrastructure cost.
- Two environments: **homelab** (Kubernetes on one mini PC; LLMs via OpenRouter) and **azure** (Container Apps; the same LLMs via Microsoft Foundry).

**Out of scope (stub or skip)**
- Auth / users. The reviewer is just a page; hard-code `reviewer = "demo"`.
- Multi-tenant, document upload UI, fancy styling.
- Cloud emulators. The homelab runs real Postgres and real models; Azure-only services aren't emulated.
- Self-hosted chat models. The homelab has no GPU, and by rough estimate a CPU-only 8B model would take tens of seconds to minutes per answer at this prompt size (about 5,000 tokens of context).
- Any proprietary or employer data. Use only public AER documents.

## Environments

The same container image runs in both. Everything that differs is an environment variable or infrastructure.

**Homelab hardware:** one mini PC, Intel i5-10500T (6 cores, 35 W TDP), 32 GB DDR4, 1 TB SSD, **no GPU**. That decides what runs locally: Postgres, embeddings and the CPU decision model do; chat models don't.

It runs Proxmox and is shared with other workloads. The app goes on the Talos `prod` cluster (one 4 GB control plane, two 7 GB workers, 4 vCPU each), delivered by ArgoCD from the [homelab](https://github.com/maxim-grin/homelab) repo ([ADR 0007](docs/decisions/0007-dev-cluster-destroyed-manifests-unchanged.md)).

| Concern | homelab (stage 1) | azure (final stage) |
|---|---|---|
| Runtime | Talos Kubernetes: Deployment + Service + Ingress (ingress-nginx, cert-manager TLS) | Azure Container Apps |
| One-off tasks (migrate, ingest, evals) | Kubernetes Jobs | Container Apps Jobs |
| Scheduled cost refresh | Kubernetes CronJob | Container Apps scheduled Job |
| Database | Postgres 16 + pgvector, a one-replica StatefulSet (`pgvector/pgvector:pg16`) on `nfs-prod` storage; nightly `pg_dump` CronJob to a second `nfs-prod` volume (same SSD: covers a bad migration or deleted data, not a lost disk) | Azure Database for PostgreSQL Flexible Server with the `vector` extension allow-listed |
| LLM gateway | LiteLLM in the cluster: the app's one OpenAI-compatible endpoint, mapping aliases to providers | LiteLLM as a Container App, same aliases, different targets |
| Answers (`chat`) | GPT-6 Luna via OpenRouter, provider pinned to OpenAI | GPT-6 Luna via Microsoft Foundry |
| LLM judge (`judge`) | Claude Haiku 5.5 via OpenRouter, provider pinned to Anthropic | Claude Haiku 5.5 via Microsoft Foundry (hosted on Azure) |
| Development (`chat-dev`) | A free OpenRouter model (`openrouter/free`); never used for evals or the demo | Not deployed |
| Embeddings (`embed`) | `nomic-embed-text` (768-dim) on Ollama, CPU, one request at a time | An Azure embedding model (1536-dim); re-ingest |
| Decision judge | GLiNER2.5-Decide in the cluster (CPU) | The same image as an internal-only Container App |
| Secrets | Vault (`kv-prod/directive-copilot/`) → argocd-vault-plugin → Kubernetes Secret → env vars | Container Apps secrets (optionally Key Vault references) → the same env vars |
| Image registry | GHCR | Azure Container Registry |
| PDFs | Baked into the image under `data/raw/` (public documents) | Same image |
| LLM billing | OpenRouter prepaid credits (no monthly expiry; may expire 1 year after purchase); auto top-up off | Azure pay-as-you-go, billed monthly for use |
| Infra cost | `config/infra.homelab.yaml` estimate (measured power draw + hardware share + amortised OpenRouter top-up fee) | `config/infra.azure.yaml` estimate, optionally Azure Cost Management actuals |
| Deploy tooling | ArgoCD + Kustomize, manifests in the homelab repo (`argocd/apps/directive-copilot/`); merging there deploys | Terraform with the `azurerm` provider (`deploy/azure/`) |

The app never calls an Azure-specific SDK for secrets, storage or models: config arrives as env vars, the PDFs ship in the image, and every model call goes through LiteLLM by alias. Moving to Azure changes LiteLLM's config, not the app.

The same two models run in both environments, so the homelab-vs-Azure comparison on `/evals` measures the infrastructure, not a model swap. Answers and the LLM judge come from different model families, so the judge isn't grading its own writing.

## Stack

| Layer | Choice |
|---|---|
| API | Python 3.12, FastAPI, Pydantic v2 |
| Orchestration | LangGraph (with a Postgres checkpointer for human-in-the-loop interrupts) |
| LLM / embeddings | `llm.py` adapter: `openai_compatible` (LiteLLM, in both environments) or `fake` (tests) |
| Judge | `Judge` interface with two implementations: LLM judge (default; Claude Haiku 5.5 via the `judge` alias) and GLiNER2.5-Decide behind a small in-cluster service |
| Storage | PostgreSQL 16 + pgvector |
| UI | React + TypeScript SPA (Vite), TanStack Query, React Router; built to static files and served by FastAPI |
| API types | Generate a TS client from FastAPI's OpenAPI schema (`openapi-typescript`) so types stay in sync |
| Packaging | `uv`, multi-stage Dockerfile |
| Deploy | ArgoCD on the homelab; Terraform (`azurerm`) on Azure |
| Tests | pytest |

## Architecture

```
            ┌──────────────┐
question ──▶│  retrieve    │  hybrid search: pgvector + Postgres full-text, top-k=6
            └──────┬───────┘
                   ▼
            ┌──────────────┐
            │  answer      │  LLM answers ONLY from retrieved chunks,
            └──────┬───────┘  returns JSON: {answer, citations[]}
                   ▼
            ┌──────────────┐
            │  grade       │  1. deterministic citation checks
            └──────┬───────┘  2. judge: P(answer supported by cited text)
                   ▼
          confidence ≥ threshold ?
            │yes            │no
            ▼               ▼
        respond       ┌──────────────┐
                      │ human_review │  LangGraph interrupt(); resumes on
                      └──────┬───────┘  approve / edit / reject
                             ▼
                          respond
```

### Homelab deployment

```
namespace: directive-copilot (Talos prod cluster)
┌────────────────────────────────────────────────────────────────────────────┐
│ Ingress ─▶ Service ─▶ app (FastAPI + SPA)                                  │
│                        │      │       │                                    │
│              ┌─────────┘      │       └──▶ decision (GLiNER2.5-Decide, CPU)│
│              ▼                ▼                                            │
│   Postgres + pgvector      LiteLLM ─▶ Ollama (embed only)                  │
│   (nfs-prod PVC)              │                                            │
│                               └────────────────────────────────────────────┼──▶ OpenRouter ─▶ GPT-6 Luna (chat)
│                                                                            │                ─▶ Claude Haiku 5.5 (judge)
│ Jobs: migrate · ingest · eval                                              │                ─▶ free model (chat-dev)
│ CronJobs: costs-refresh · pg_dump (nightly)                                │
└────────────────────────────────────────────────────────────────────────────┘
```

### Node contracts

- **retrieve(state) → chunks**: returns `[{chunk_id, directive, edition, section, text, score}]`.
- **answer(state) → draft**: structured output:
  ```json
  {
    "answer": "string",
    "citations": [{"chunk_id": "…", "quote": "exact substring"}],
    "answerable": true
  }
  ```
  If the context doesn't contain the answer, it must say so and set `answerable: false`. Use the provider's structured-output mode, still validate with Pydantic, and retry once with the validation error before failing the run (free dev models are less reliable at JSON).
- **grade(state) → grade**:
  1. Deterministic checks: every `quote` is an exact substring of its chunk, and every `chunk_id` was retrieved. Any failure → confidence 0.
  2. Judge decisions (see below): `supported` = P(the answer is fully supported by the cited text) and `on_topic` = P(the answer addresses the question). With the `decision` judge these are asked as one joint decision, so the two answers can't contradict each other.
  3. `confidence = min(supported, on_topic)`. `answerable: false` skips the judge and returns the refusal with confidence 1 (refusing is the correct behaviour).
  We don't ask the model to rate its own confidence: self-reported scores are poorly calibrated.
- **human_review(state)**: calls `interrupt()` and persists the run. The review UI resumes the graph with `{decision, edited_answer?, note?}`.

## Judge

One interface, two implementations, chosen with `JUDGE=llm|decision` (plus `fake` for tests):

```python
class Decision(BaseModel):
    p_yes: float            # 0..1
    reason: str | None = None

class Judge(Protocol):
    name: str
    def decide(self, question: str, fields: dict[str, str]) -> Decision: ...
```

- **`LLMJudge`** (default, the baseline): Claude Haiku 5.5 through the `judge` alias, with structured output returning a yes/no verdict, at low or no reasoning effort (reasoning tokens bill as output and add latency). If the provider returns logprobs, `p_yes` comes from the yes/no token logprobs; reasoning models often don't, and then it's 0 or 1. That's the main reason to measure the decision judge, which always returns a probability.
- **`DecisionJudge`** → **GLiNER2.5-Decide**: an open-weight (Apache 2.0) 340M encoder decision model from Fastino. It doesn't generate text: it takes text plus typed questions and returns probabilities for each answer, and it can decode related questions jointly so they stay consistent. It runs on CPU, so it's a small Deployment in the cluster (`services/decision/`: a FastAPI wrapper around the `gliner2` library, one `/decide` endpoint). Check the model's maximum input length; if chunk + question + answer doesn't fit, judge each citation separately and take the minimum.
- Both are used by the **grade node** (live traffic) and by the **eval runner**, and both report usage to `llm_usage` (node = `judge`) so their cost shows up on `/costs`.

**Known limits of decision models.** They're built for bounded judgments, not reasoning, and their vendors flag exact arithmetic, counting and date math as weak spots. Several eval cases here are exactly that (2% vs. 1% H2S, 24 hours' notice), so `/evals` breaks judge accuracy down by case tag. Published benchmarks for these models are vendor-run on routing and classification suites, not on judging answers to regulatory questions: your labelled cases are the real test.

**Why the LLM judge stays the default:** it's the best-understood option and on Azure it uses an already-approved vendor. The decision judge is what you turn on and measure; it runs entirely inside your network and costs nothing per call. Switching the default is an ADR, backed by the judge comparison on `/evals`.

## Data model

```sql
documents (id, directive, title, edition_date, source_url, sha256)
chunks    (id, document_id, section, heading, text, tsv tsvector,
           embedding vector(EMBED_DIM), embed_model)
questions (id, text, created_at)
runs      (id, question_id, thread_id, status, draft jsonb, grade jsonb,
           final_answer jsonb, judge, profile, created_at, resolved_at)
           -- status: answered | pending_review | approved | edited | rejected
reviews   (id, run_id, decision, edited_answer, note, reviewer, created_at)

eval_cases   (id, slug, directive, question, expected_answer, answerable bool,
              must_include text[], must_not_include text[],
              expected_sections text[], tags text[])
eval_runs    (id, judge, profile, env, chat_model, embed_model, git_sha,
              started_at, finished_at, summary jsonb)
              -- profile: e.g. "homelab-openrouter", "azure-foundry"
eval_results (id, eval_run_id, case_id, run_id, answer text,
              facts_ok bool,           -- must_include / must_not_include checks
              judge_correct_p float,   -- judge P(answer matches expected_answer)
              correct bool,            -- facts_ok AND judge_correct_p >= 0.5
              citation_hit bool, escalated bool,
              human_label bool null,   -- your own verdict, set on /evals
              latency_ms, cost_usd numeric(10,6), created_at)

llm_usage    (id, run_id null, eval_run_id null, node, kind, provider, model,
              input_tokens, output_tokens, cost_usd numeric(10,6), created_at)
              -- kind: chat | embedding | judge; node: answer | grade | judge | retrieve | ingest
infra_costs  (id, env, period_start date, period_end date, resource, service,
              cost_usd numeric(10,2), source, fetched_at)
              -- source: estimate | azure_cost_management
```

**Embedding dimension:** pgvector columns have a fixed size. The migration reads `EMBED_DIM` (e.g. 768 for `nomic-embed-text`, 1536 for Azure `text-embedding-3-small`). Switching embedding models means a fresh `chunks` table and a re-ingest; ingestion refuses to mix `embed_model` values in one table.

## API

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/ask` | `{question}` → `{run_id, status, answer?, citations?, cost?}` |
| GET | `/api/runs/{id}` | run detail incl. draft, grade, final, usage by node |
| GET | `/api/reviews` | pending review queue |
| POST | `/api/reviews/{run_id}` | `{decision, edited_answer?, note?}` → resumes graph |
| POST | `/api/evals/run` | `{judge?: "llm" \| "decision"}` → runs the eval set, returns summary |
| GET | `/api/evals/latest` | latest eval summary per judge and profile |
| GET | `/api/evals/compare?by=judge\|profile` | comparison (agreement with human labels, correctness, cost, latency) |
| PATCH | `/api/evals/results/{id}` | `{human_label}` → your verdict on one result |
| GET | `/api/costs?days=30` | LLM + judge usage by node/model, infra costs, all-in cost per question |
| GET | `/healthz`, `/readyz` | liveness; readiness checks the DB and the LLM endpoint |

SPA routes (client-side): `/` (ask), `/review`, `/evals`, `/costs`, `/runs/:id`. FastAPI serves `web/dist` at `/` with a catch-all fallback to `index.html`; everything under `/api` stays the JSON API.

## Ingestion

`python -m copilot.ingest data/raw/*.pdf` (runs as the `ingest` Job in both environments)

1. Extract text with `pymupdf`.
2. Split on section headings (e.g. regex for `^\d+(\.\d+)*\s` patterns), then sub-chunk to about 800 tokens with overlap and keep `section` + `heading` metadata.
3. Record `edition_date` (from the PDF's front page: "Release date") and a `sha256` of the file.
4. Embed and upsert. Ingestion is idempotent: re-running with the same file and embedding model is a no-op, and a new edition of a directive replaces the old one's chunks.

## Evaluation

### Writing the cases
- `evals/cases.yaml`: about 20 cases **written by hand** while reading the directives, not generated, so you know the material and the scores mean something.
- Check every answer key against the directive PDF itself, not summary pages, and fill `expected_sections` from the edition you ingested.
- Mix of case types:
  - straightforward lookups
  - **threshold/branch cases** where the model must apply a rule to the numbers in the question (e.g. H2S above vs. below 1%)
  - **sibling cases**: the same question with one detail changed, so the right answer changes
  - **recent-change cases** covering requirements added in the latest edition, which a model working from memory won't know
  - 3–4 **unanswerable** cases (`answerable: false`) to check it refuses instead of making things up

Example:

```yaml
- slug: d060-notify-well-test-sour
  directive: "060"
  question: >
    We're planning to flare during a well test and the gas is about 2% H2S.
    Who do we have to notify, how far out, and how much notice do we need to give?
  expected_answer: >
    Notify the AER field centre and all residents within 3 km, at least
    24 hours before the flaring starts. (Below 1% H2S, the radius is 1.5 km.)
    Notification isn't required for flaring during an emergency.
  answerable: true
  must_include: ["AER field centre", "3 km", "24 hours"]
  must_not_include: ["1.5 km applies"]
  expected_sections: ["TODO: from the ingested edition"]
  tags: [notification, well-test, h2s-threshold]
```

### Scoring each case
1. **Fact checks (deterministic, free):** each `must_include` item appears in the answer (normalised: case, units like "3 km"/"3 kilometres"), and no `must_not_include` item does. Fall back to a judge question per fact only when a string match is too strict.
2. **Correctness (judge):** P(answer agrees with `expected_answer`). `correct = facts_ok AND p >= 0.5`.
3. **Citation hit:** any cited section is in `expected_sections`.
4. **Refusal accuracy** for `answerable: false` cases.

### What `/evals` shows
- Per run: correctness, citation hit rate, refusal accuracy, escalation rate, p50 latency, cost per question (average and p95) and total run cost, labelled with its judge and profile.
- Per case: the answer, each check, and a ✓/✗ toggle to set **your own `human_label`**.
- **Judge comparison** (run the set with each judge, then label about 20 results yourself):

  | Judge | Agreement with your labels | Agreement on `h2s-threshold` / numeric cases | Cost per eval run | p50 latency per decision |
  |---|---|---|---|---|
  | LLM | … | … | … | … |
  | GLiNER2.5-Decide | … | … | … | … |

  The per-tag column is the point: it shows where a cheap local judge is good enough and where it isn't.

- **Profile comparison** (after the Azure stage):

  | Profile | Correctness | Citation hit | Refusal accuracy | Cost per question | p50 latency |
  |---|---|---|---|---|---|
  | homelab-openrouter | … | … | … | … | … |
  | azure-foundry | … | … | … | … | … |

  Same models in both rows, so differences come from the infrastructure: network path, provider region, embedding model.

  In both tables, show the cases where the rows disagree. Those are the interesting ones to talk through.
- **Evals only run on pinned paid models.** The runner refuses to start if `CHAT_MODEL` or `JUDGE_MODEL` is the `chat-dev` alias or any `:free` model: free models rotate and rate-limit, which would make runs incomparable.
- `make eval JUDGE=llm|decision` runs it locally; `make eval-job` runs it as a Job in the current environment. CI fails if citation hit rate or correctness drops below a set threshold.

## Cost tracking

### LLM and judge tokens
- A LangChain `BaseCallbackHandler` (`UsageTracker`) reads `usage_metadata` from every chat response in `on_llm_end`. It's passed in through the graph's `config={"callbacks": [...]}`, so every LLM call inside the graph is captured without per-node code.
- Embedding calls (query time and ingestion) are counted separately in the embedding wrapper (token count from the API response, or from `tiktoken` as a fallback).
- `DecisionJudge` doesn't go through LangChain, so it records its own usage with `kind=judge`: the decision service returns the input token count from its tokenizer. It runs in the cluster, so it's priced at $0 per token and its cost is part of the infra estimate.
- `config/prices.yaml` maps provider/model → USD per 1M input/output tokens (cached input listed separately). OpenRouter passes provider list prices through, so the table is the same in both environments; its 5.5% top-up fee goes into the homelab infra estimate, not per-token prices. Local models (Ollama embeddings, GLiNER) are priced at $0 per token; their cost lives in the infra estimate. `cost_usd` is calculated and **stored when the row is written**, so later price changes don't rewrite history.
- If streaming is added, enable usage reporting on streams (e.g. `stream_usage=True`).

### Infrastructure
- **Estimates (both environments):** `config/infra.<env>.yaml` lists resources with a monthly cost. A CronJob / scheduled Job (`python -m copilot.costs refresh`) writes one row per resource per day to `infra_costs` with `source=estimate`.
  - **homelab:** measured power draw (a smart plug's idle and load watts × hours × your $/kWh; the CPU's 35 W TDP isn't the whole PC's draw) plus a hardware share (purchase price ÷ expected lifetime in months), plus the OpenRouter top-up fee amortised per month. State the assumptions on the page.
  - **azure:** list prices for Container Apps, Postgres Flexible Server, Container Registry and Log Analytics.
- **Optional (azure actuals):** if `AZURE_SUBSCRIPTION_ID` and a resource group are set, pull daily actual cost per resource from the Azure Cost Management Query API (`azure-mgmt-costmanagement`, a service principal or managed identity with *Cost Management Reader*), written with `source=azure_cost_management`. Azure cost data lags by 8–24h, so the page labels the "as of" date.
- Tag all Azure resources `app=directive-copilot` so their costs can be filtered.

### What the UI shows
- **Answer card / run page:** total tokens and cost, broken down by node (answer vs. judge vs. embeddings).
- **Costs page:**
  - LLM and judge spend over time, split by node and model.
  - Infra spend by resource for the period, labelled with environment and source.
  - **All-in cost per question** = (LLM + judge + infra spend) ÷ questions answered in the period, shown next to LLM-only cost per question.
  - A "what if" input: questions per day, judge and environment → projected monthly cost (infra is mostly fixed, LLM scales linearly). The homelab vs. Azure comparison is a good talking point.

## Project layout

```
copilot/
  api.py          # FastAPI app + routes + health checks
  graph.py        # LangGraph definition
  nodes/          # retrieve.py, answer.py, grade.py, review.py
  judges/         # base.py (Judge, Decision), llm.py, decision.py, fake.py
  llm.py          # provider adapter: openai_compatible (LiteLLM) | fake
  settings.py     # pydantic-settings; all config from env vars
  db.py           # SQLAlchemy / psycopg, migrations via alembic
  ingest.py
  evals.py        # runner, fact checks, judge + profile comparison
  usage.py        # UsageTracker callback + price lookup
  costs.py        # infra cost refresh (estimate or Azure Cost Management)
config/
  prices.yaml           # list prices per model (same in both environments; local models = 0)
  infra.homelab.yaml    # power + hardware estimate
  infra.azure.yaml      # Azure list-price estimate
web/              # Vite + React + TS
  src/
    api/          # generated OpenAPI types + fetch wrappers
    pages/        # AskPage.tsx, ReviewPage.tsx, EvalsPage.tsx, CostsPage.tsx, RunPage.tsx
    components/   # AnswerCard, CitationList, ReviewItem, EvalTable, CompareTable, CostBadge, CostChart
  vite.config.ts  # dev proxy: /api -> http://localhost:8000
deploy/             # Azure only; homelab manifests live in the homelab repo
  azure/
    versions.tf   # terraform + azurerm provider pins, backend "azurerm" (remote state)
    main.tf       # resource group, tags, Log Analytics
    registry.tf   # ACR
    postgres.tf   # Postgres Flexible Server, azure.extensions = VECTOR, database, firewall
    openai.tf     # Foundry / Azure OpenAI account; GPT-6 Luna, embedding model (and Claude Haiku 5.5 if Terraform can)
    apps.tf       # Container Apps environment, app, internal decision and LiteLLM apps, migrate/ingest/eval jobs, costs scheduled job
    variables.tf  # location, name prefix, image_tag, model names, sizes
    outputs.tf    # app URL, ACR login server, Postgres host
    terraform.tfvars.example   # copy to terraform.tfvars (gitignored)
    litellm-config.yaml        # Azure targets for the model aliases
    bootstrap/    # one-off: storage account + container for remote state
services/
  decision/       # FastAPI wrapper around gliner2 + GLiNER2.5-Decide: /decide, /healthz; own Dockerfile and pyproject
data/raw/         # AER PDFs (committed or downloaded at build time; baked into the image)
evals/cases.yaml
tests/            # unit tests for fact checks, citation checks, cost math; graph test with a fake LLM + fake judge
Dockerfile        # multi-stage: node builds web/dist, python image serves API + static
Makefile          # every check command (fmt, lint, test, check-web, check-infra, eval);
                  # deploy targets (deploy-azure) added per milestone
CLAUDE.md         # how agents work on the repo; rules that tools enforce point at the tool
PLAN.md           # this file
REFERENCES.md     # sources
docs/
  decisions/      # ADRs: one file per architectural decision
  superpowers/    # specs/ and plans/ produced by the superpowers workflow
tools/
  check_commit_msg.py   # commit-msg rules, shared by the git hook and CI
```

## Config

All config is env vars (read by `settings.py`). On the homelab they come from a ConfigMap + Secret defined in the homelab repo; on Azure from Container Apps env vars + secrets. `.env` for local runs is never committed.

```
ENV=homelab                       # homelab | azure
PROFILE=homelab-openrouter        # label stored on runs and eval runs
DATABASE_URL=postgresql+psycopg://...

LLM_PROVIDER=openai_compatible    # openai_compatible | fake (tests)
LLM_BASE_URL=http://litellm:4000  # LiteLLM in both environments
LLM_API_KEY=...                   # LiteLLM master key (provider keys live in LiteLLM's Secret)
CHAT_MODEL=chat                   # LiteLLM alias; chat-dev while building (free model)
EMBED_MODEL=embed                 # LiteLLM alias
EMBED_DIM=768                     # must match EMBED_MODEL (1536 on Azure)

CONFIDENCE_THRESHOLD=0.7
JUDGE=llm                         # llm | decision | fake (tests)
JUDGE_MODEL=judge                 # LiteLLM alias for the LLM judge (Claude Haiku 5.5)
DECISION_URL=http://decision:8080 # JUDGE=decision

# optional, azure actual costs
AZURE_SUBSCRIPTION_ID=...
AZURE_RESOURCE_GROUP=...
```

**LiteLLM model aliases** (a ConfigMap in the homelab repo's `argocd/apps/directive-copilot/`; on Azure, `deploy/azure/litellm-config.yaml` mounted into the LiteLLM Container App). The app only knows the aliases:

| Alias | Homelab target | Azure target |
|---|---|---|
| `chat` | `openrouter/openai/gpt-6-luna`, provider pinned to OpenAI, low reasoning effort | GPT-6 Luna deployment in Microsoft Foundry |
| `judge` | `openrouter/anthropic/claude-haiku-5.5`, provider pinned to Anthropic, low effort | Claude Haiku 5.5 deployment in Microsoft Foundry (hosted on Azure) |
| `chat-dev` | `openrouter/openrouter/free` (OpenRouter's free-model router) | not defined |
| `embed` | `ollama/nomic-embed-text:v1.5` | Azure embedding deployment |

- **Pin providers** in the OpenRouter aliases (provider routing, fallbacks off) so an eval run can't silently move between hosts. Turn on zero data retention in the OpenRouter account.
- Check during milestone 0 that LiteLLM's model IDs match OpenRouter's current catalogue, and during milestone 8 that LiteLLM can reach Claude on Foundry; if not, point `judge` at the Anthropic API directly for the Azure stage.
- **Billing:** buy OpenRouter credits manually, about $15 at a time (the 5.5% card fee has a $0.80 minimum, so smaller top-ups pay proportionally more), auto top-up off. Credits don't reset monthly; OpenRouter may expire them a year after purchase, and only refunds within 24 hours. Buying $10 or more also raises the free-model limit from 50 to 1,000 requests a day, which the `chat-dev` loop needs.

## Milestones (about 2.5 days; 7 and the Cost Management part of 9 can be cut)

**Stage 1: homelab**

0. **Cluster prep (half a day):** in the homelab repo: destroy the `dev` Kubernetes cluster, grow the `prod` workers to 7 GB and the nodes to 4 vCPU; add the `directive-copilot` app: namespace, Postgres + pgvector on `nfs-prod` + nightly `pg_dump` CronJob, Ollama with `nomic-embed-text` only (`OLLAMA_NUM_PARALLEL=1`, CPU limit), LiteLLM with `chat`/`judge`/`chat-dev`/`embed` aliases, secrets in Vault. OpenRouter account with zero data retention and ~$15 of credits. Check every alias with `curl`.
1. **Skeleton (1.5h):** FastAPI hello + health checks, alembic migrations, Vite React app, multi-stage Dockerfile, image published to GHCR, app and migrations added to the homelab app, app reachable through the Ingress.
2. **Ingest (1.5h):** parse 2 directives (current editions), chunk, record edition date, embed, run as a Job, verify with a raw similarity query.
3. **Graph happy path (2h):** retrieve → answer → respond with citations on `/`, built against `chat-dev`; structured output + Pydantic validation + one retry; then switch to `chat` and check cost per answer.
4. **Grading + HITL (2h):** deterministic citation checks, `Judge` interface + `LLMJudge`, interrupt, review queue page, resume.
5. **Evals (2h):** write cases.yaml by hand, fact checks, runner (locally and as a Job), `/evals` page with human-label toggle.
6. **Token tracking + homelab cost (2h):** `UsageTracker`, `llm_usage` table, prices.yaml, cost badge on answers, cost columns on evals, `infra.homelab.yaml` + costs CronJob, `/costs` page.
7. **Decision judge + comparison (2h):** `services/decision/` (GLiNER2.5-Decide wrapper, its own small image) deployed as a CPU Deployment; `DecisionJudge`; run evals with both judges, label ~20 results, judge comparison by case tag on `/evals`.

**Stage 2: Azure**

8. **Provision (2.5h):** apply `deploy/azure/bootstrap` once for remote state, then `terraform plan` / `apply` for ACR, Container Apps environment, Postgres Flexible Server (allow-list the extension with an `azurerm_postgresql_flexible_server_configuration` setting `azure.extensions = VECTOR`, then `CREATE EXTENSION vector` in the migration), a Foundry / Azure OpenAI account (`azurerm_cognitive_account` + `azurerm_cognitive_deployment` for GPT-6 Luna and the embedding model; Claude Haiku 5.5 is a partner model, so check whether Terraform can deploy it or it's a one-time portal step recorded in the README), the LiteLLM Container App, Log Analytics; use a pay-as-you-go subscription, since free trials have zero LLM quota; `default_tags`-style `tags` on everything (`app=directive-copilot`). Secrets go in as Container Apps secrets from Terraform outputs/variables, never committed `.tfvars`.
9. **Move and compare (2h):** push the same images (app + decision) to ACR; run the decision service as an internal-only Container App; point LiteLLM's aliases at the Foundry deployments; set env vars (`ENV=azure`, `PROFILE=azure-foundry`, `EMBED_DIM=1536`); run migrate + ingest as Container Apps Jobs; seed 2 pending reviews; `infra.azure.yaml` (+ Cost Management actuals if time allows); re-run evals and fill in the profile comparison.

## Definition of done

**Homelab**
- [ ] An ArgoCD sync into an empty namespace, then the ingest Job, gives a working app (DB, embeddings, LiteLLM aliases, migrations).
- [ ] Evals refuse to run on `chat-dev` or any free model.
- [ ] Every answer shows clickable citations with the quoted text and the directive edition.
- [ ] At least one sample question reliably goes to review.
- [ ] Unanswerable questions get a refusal, not a made-up answer.
- [ ] `/evals` shows real numbers from the latest run, including cost per question, and compares the judges against your own labels, broken down by case tag (if milestone 7 is done).
- [ ] Every answer shows its token count and cost, split by node.
- [ ] `/costs` shows LLM, judge and infra spend and all-in cost per question, with the environment and data source labelled.
- [ ] Tests pass with a fake LLM and fake judge (no API keys or cluster needed in CI, except for the eval job).

**Azure**
- [ ] The same image tag runs on Azure; the only changes are env vars and Terraform.
- [ ] `terraform plan` shows no changes after a deploy (no drift from manual `az` edits).
- [ ] `terraform destroy` tears the whole Azure environment down cleanly, so the demo costs nothing when it's not needed.
- [ ] Public URL loads in under 3s; the ask flow works with no setup.
- [ ] `/evals` shows the homelab vs. Azure profile comparison.
- [ ] `/costs` shows Azure infra cost (estimate, or actuals labelled with their "as of" date).

**Both**
- [ ] README has a 3-line "try this" section with sample questions.
- [ ] Disclaimer in the footer: *Demo only; not legal or regulatory advice. Always consult the current directive on aer.ca.*

## Stretch ideas (only after done)

- **Decision-model reranking:** retrieve the top 30 with hybrid search, have the decision service score each chunk's relevance in one parallel call, keep the best 6. Compare citation hit rate with and without it on `/evals`.
- Detect when aer.ca publishes a new edition of an ingested directive, re-ingest it, and re-run evals to show what changed.
- Feed reviewer edits back in as few-shot examples, or into the eval set.
- Use judge probabilities to tune `CONFIDENCE_THRESHOLD`: plot escalation rate vs. error rate on the eval set.
- GitHub Actions to build, run tests, push to ACR, post `terraform plan` on PRs and `apply` on merge.
- Use managed identity on Azure instead of keys for Postgres and Azure OpenAI.
- Swap the hand-rolled search for Azure AI Search to show the enterprise path.
- Trace every run with LangSmith, Langfuse or OpenTelemetry and link to it from the run detail.
- Stream answer tokens to the Ask page over SSE (`/api/ask/stream`).
