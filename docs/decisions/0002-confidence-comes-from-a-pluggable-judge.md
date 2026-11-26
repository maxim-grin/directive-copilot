# 0002: Confidence comes from a pluggable judge, never the answering model

Status: Accepted
Date: 2026-11-25

## Context

The human-review step escalates answers below a confidence threshold, so
the confidence number decides what a reviewer sees. Models' self-reported
confidence is poorly calibrated, and LLM judges tend to answer near 0 or
1. Small decision models such as GLiNER2.5-Decide return probabilities,
run on CPU inside the cluster, and cost nothing per call, but are weaker at
arithmetic and threshold reasoning, which several eval cases need.

## Decision

- Confidence = min(P(supported by cited text), P(on topic)), from a judge.
  The answering model is never asked to rate itself.
- Deterministic citation checks (every quote is an exact substring of a
  retrieved chunk) run first; a failure sets confidence to 0 with no judge
  call.
- The judge is pluggable (`JUDGE=llm|decision`). The LLM judge (Claude
  Haiku 5.5, a different family from the answering model) is the default;
  the decision judge is enabled and measured against hand-labelled eval
  results, broken down by case tag.

## Consequences

- Every judge reports usage to `llm_usage`, so judge cost is visible next
  to answer cost.
- Switching the default judge is itself a decision: supersede this record
  with the eval numbers that justify it.
