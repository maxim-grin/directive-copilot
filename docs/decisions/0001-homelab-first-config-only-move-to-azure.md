# 0001: Homelab first; the move to Azure is config-only

Status: Accepted
Date: 2026-11-25

## Context

The target environment is Azure (Container Apps, PostgreSQL Flexible
Server, Azure OpenAI), but building there from day one costs money for
every idle resource and slows iteration. A homelab Kubernetes cluster is
available. Cloud emulators were considered and rejected: the app uses
almost no Azure-specific services, and the ones it would need (Azure
OpenAI, Cost Management) aren't emulated anyway.

## Decision

- Build and run on the homelab first: Postgres + pgvector, embeddings and
  the decision judge in the cluster, and every model call through a LiteLLM
  gateway by alias (see [0005](0005-hosted-llms-same-models-in-both-environments.md)
  for which models and where they're hosted).
- Move to Azure as the last stage, using the same container image.
- Everything that differs between environments is an environment variable
  or infrastructure code. The app never calls an Azure SDK for secrets,
  storage or models: secrets arrive as env vars, the source PDFs ship in the
  image, and moving models means changing LiteLLM's config.

## Consequences

- Swapping embedding models across environments needs a re-ingest, because
  pgvector dimensions are fixed (768 locally vs. 1536 on Azure).
- The homelab vs. Azure eval comparison becomes a feature: same eval set,
  same models, two environments.
- Revisit if the app needs an Azure-only service with no env-var-shaped
  equivalent.
