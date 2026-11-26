# Directive Copilot

Ask a question about Alberta Energy Regulator (AER) directives and get a
short answer that cites the exact clause it came from. If the system isn't
confident, a person reviews the answer before you see it. Every answer shows
what it cost.

> Demo project, not legal or regulatory advice. Always check the current
> directive on [aer.ca](https://www.aer.ca).

## Why I built this

I live in Alberta, a Canadian province whose economy leans heavily on
developing its natural resources. One day I got curious: how does a person,
or a company, actually start developing a resource here, and who decides
what they're allowed to do?

That question led me to the [Alberta Energy Regulator](https://www.aer.ca)
and its directives: the documents that set the rules for everything from
licensing a well to flaring gas. They're thorough, but they're also long
walls of text, written for specialists who already know where to look.
Finding one specific answer can mean reading dozens of pages.

It struck me as a perfect use case for AI: keep the directives as the
single source of truth, but let people ask questions in plain language and
get a short answer that points to the exact clause it came from. And
because the subject is regulation, the system has to know when it isn't
sure and hand the question to a person instead of guessing.

## What it does

- **Answers with citations.** Retrieval over the current editions of
  Directive 060 (flaring, incinerating, venting) and Directive 017
  (measurement). Every quote is checked word for word against the source.
- **Sends doubtful answers to a reviewer.** A judge scores whether the
  answer is supported by its citations; below the threshold, the answer
  waits in a review queue to be approved, edited or rejected.
- **Measures itself.** A hand-written eval set scores correctness, citation
  accuracy and refusals. It compares an LLM judge with a small local
  decision model, and the homelab with Azure on the same models.
- **Shows the cost.** Tokens and dollars per answer, plus an all-in cost per
  question that includes infrastructure.

It runs on a homelab Kubernetes cluster first (one CPU-only mini PC; chat
models are hosted, through OpenRouter), then on Azure with the same image,
the same models through Microsoft Foundry, and different configuration.

## Try it

Questions to ask once it's running:

- *We're flaring during a well test and the gas is about 2% H2S. Who do we
  notify, and how much notice do we need?*
- *Same well test, but the gas is 0.5% H2S. What changes?*
- *What's the flaring limit for a Saskatchewan well?* (outside the
  directives, so it should decline)

## Run it locally

Prerequisites: `uv`, Node 22, and access to the homelab cluster (Postgres +
pgvector and LiteLLM running in the `directive-copilot` namespace, with an
OpenRouter key in LiteLLM's Secret). The homelab app is deployed from the
`homelab` repo, not this one. Set `CHAT_MODEL=chat-dev` while
building to use a free model; evals need the paid `chat` and `judge`.

```bash
uv sync --group dev && uv run pre-commit install
npm --prefix web ci

# The commands need the current kube context to be the `prod` cluster. Claude
# Code's hook also only allows a context named `homelab`, or the name in
# DC_KUBE_CONTEXT (kubectl itself ignores that variable).
kubectl -n directive-copilot port-forward svc/postgres 5432 &
kubectl -n directive-copilot port-forward svc/litellm 4000 &

uv run fastapi dev copilot/api.py   # API on :8000
npm --prefix web run dev            # UI; Vite proxies /api to the API
```

Configuration is environment variables only: see the Config section of
[PLAN.md](PLAN.md#config).

## Checks

```bash
make help              # list targets
make lint test         # what the pre-push hook and CI run for Python
make check-web         # frontend checks + generated API types up to date
make check-infra       # Terraform validation, no cloud access
make test-integration  # needs DATABASE_URL (Postgres + pgvector)
make eval              # real models; costs money
```

Warning: the port-forwarded database is the live one on `prod` (there is no staging), so run `make test-integration` only against a throwaway Postgres.

The same targets run in Claude Code hooks, pre-commit and CI.

## Docs

| File | For |
| --- | --- |
| [PLAN.md](PLAN.md) | Design contract: architecture, data model, evals, costs, milestones |
| [CLAUDE.md](CLAUDE.md) | How agents (and people) work on the repo |
| [docs/decisions/](docs/decisions/README.md) | Architecture decision records |
| [REFERENCES.md](REFERENCES.md) | Sources: regulations, frameworks, models, cloud docs |
