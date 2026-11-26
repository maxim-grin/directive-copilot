# 0005: Hosted LLMs, the same models in both environments

Status: Accepted
Date: 2026-11-25

## Context

The homelab is one mini PC: Intel i5-10500T (6 cores, 35 W), 32 GB RAM,
no GPU. By rough estimate, a CPU-only 8B chat model would take tens of
seconds to minutes per answer with about 5,000 tokens of context, and the
LLM judge would double that. Kev-style decision models need a GPU or Apple
Silicon. Embeddings, Postgres and GLiNER2.5-Decide run fine on this CPU.

Small hosted models are cheap at this volume: GPT-6 Luna and Claude Haiku
5.5 are both listed at $0.10 / $0.50 per million input/output tokens, about
a tenth of a cent per question including the judge. Both are also
available in Microsoft Foundry, the Azure stage's target.

For billing, prepaid credits that don't reset monthly were preferred over
subscriptions. OpenRouter sells prepaid credits at provider list prices plus
a 5.5% card fee ($0.80 minimum); credits may expire a year after purchase.
OpenCode Go was rejected: a monthly subscription aimed at coding agents,
with usage windows that a single eval run could hit, and no per-token
price for the cost page. OpenRouter's free models were rejected for evals
and the demo: they rotate, are rate-limited to 50 requests a day (1,000
after $10 of purchases), and may train on prompts.

## Decision

- Chat models are hosted, never self-hosted on the homelab.
- Answers: GPT-6 Luna. LLM judge: Claude Haiku 5.5, a different family,
  so the judge doesn't grade its own model's writing.
- Homelab: both via OpenRouter, provider-pinned, zero data retention,
  credits topped up by hand (about $15, auto top-up off). Azure: both via
  Microsoft Foundry, pay-as-you-go.
- The app calls LiteLLM by alias (`chat`, `judge`, `chat-dev`, `embed`) in
  both environments; only LiteLLM's targets change.
- A free model behind `chat-dev` is for the development loop only. The eval
  runner refuses free models.
- Embeddings and the decision judge stay local on the homelab.

## Consequences

- No GPU needed, and answer latency is the hosted model's, not the CPU's.
- The project depends on two external providers plus OpenRouter; the
  homelab sends questions and retrieved chunks (public AER text) out.
- The homelab vs. Azure comparison isolates infrastructure, since the
  models are identical.
- Revisit if a GPU is added to the homelab, or if Foundry stops offering
  either model.
