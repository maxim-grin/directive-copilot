# Architecture decision records

One file per decision that shapes the system and would be expensive or
confusing to reverse. A PR that makes or reverses such a decision adds or
supersedes a record in the same PR.

## Writing one

1. Copy `template.md` to `NNNN-short-title.md`, using the next free number.
2. Fill in Context (the forces, with measured numbers where they exist),
   Decision (what we do, stated as a rule), and Consequences (what it costs,
   what it rules out).
3. Add a row to the index below.

## Superseding one

Records are history, so they are never rewritten:

- Write a new record that states the new decision and links the old one.
- In the old record, change **only** the `Status:` line, to
  `Superseded by [NNNN](NNNN-....md)`. Never edit its Context or Decision.

`.claude/hooks/protect-files.sh` enforces this for agents: a committed
record accepts an edit to its Status line and nothing else.

## Index

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-homelab-first-config-only-move-to-azure.md) | Homelab first; the move to Azure is config-only | Accepted |
| [0002](0002-confidence-comes-from-a-pluggable-judge.md) | Confidence comes from a pluggable judge, never the answering model | Accepted |
| [0003](0003-kustomize-on-the-homelab-terraform-on-azure.md) | Kustomize on the homelab, Terraform on Azure | Accepted |
| [0004](0004-tools-enforce-rules-the-makefile-owns-commands.md) | Tools enforce rules; the Makefile owns the commands | Accepted |
| [0005](0005-hosted-llms-same-models-in-both-environments.md) | Hosted LLMs, the same models in both environments | Accepted |
