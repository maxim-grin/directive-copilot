# 0008: Hosted LLMs through direct providers, no zero data retention yet

Status: Accepted
Date: 2026-11-28

Supersedes [0005](0005-hosted-llms-same-models-in-both-environments.md).

## Context

0005 asked OpenRouter for zero data retention and pinned `chat` to OpenAI
and `judge` to Anthropic. The two don't fit together. OpenRouter's
[retention settings](https://openrouter.ai/docs/guides/features/zdr)
disable first-party OpenAI and Anthropic endpoints, and its
[endpoint list](https://openrouter.ai/api/v1/endpoints/zdr), read on
2026-11-28, offered `gpt-6-luna` only on Azure, `claude-haiku-5.5` only on
Amazon Bedrock and Google Vertex, and no free chat model.

The owner wants to try the direct providers first, and to try free models
through OpenRouter. The homelab sends out questions and retrieved chunks of
public AER text.

Moving the pins to Azure and Bedrock was the alternative: retention stays
zero, but neither goal is met.

## Decision

- Chat models are hosted, never self-hosted on the homelab.
- Answers: GPT-6 Luna. LLM judge: Claude Haiku 5.5, a different family,
  so the judge doesn't grade its own model's writing.
- Homelab: both via OpenRouter, pinned to OpenAI and Anthropic with
  fallbacks off, credits topped up by hand (about $15, auto top-up off).
  Azure: both via Microsoft Foundry, pay-as-you-go.
- Zero data retention is off in the OpenRouter account for now.
- The app calls LiteLLM by alias (`chat`, `judge`, `chat-dev`, `embed`) in
  both environments; only LiteLLM's targets change.
- A free model behind `chat-dev` is for the development loop only. The eval
  runner refuses free models.
- Embeddings and the decision judge stay local on the homelab.

## Consequences

- Providers may keep prompts under their own policies, and free-model hosts
  may train on them. Nothing private goes into a question or the corpus.
- No GPU needed, and answer latency is the hosted model's, not the CPU's.
- The project depends on two external providers plus OpenRouter.
- The homelab vs. Azure comparison isolates infrastructure, since the
  models are identical.
- Revisit before anyone else's questions or non-public text reach the app,
  or once the direct providers and free models have been tried. Turning
  retention on means moving both pins first.
- Revisit also if a GPU is added to the homelab, or if Foundry stops
  offering either model.
