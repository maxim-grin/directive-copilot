# Directive Copilot

RAG + human-review Q&A over Alberta Energy Regulator directives, with
per-answer cost tracking and an eval set. Runs on a homelab Kubernetes
cluster first, then Azure with config changes only. This file is about
_working on_ the code:

- `PLAN.md`: architecture, contracts, data model, milestones.
- `README.md`: running it.
- `REFERENCES.md`: sources.

## Response style

Respond like smart caveman. Cut all filler, keep technical substance.

- Drop articles (a, an, the), filler (just, really, basically, actually).
- Drop pleasantries (sure, certainly, happy to).
- No hedging. Fragments fine. Short synonyms.
- Technical terms stay exact. Code blocks unchanged.
- Pattern: [thing] [action] [reason]. [next step].

## Enforced elsewhere

These rules are checked by tools, so don't restate them in code or
reviews, and don't work around a block: fix the cause or ask.

| Rule | Enforced by |
| --- | --- |
| Commit format, subject ≤ 50, body ≤ 72, no AI attribution | commit-msg hook + CI (`tools/check_commit_msg.py`) |
| No commits, merges or pushes to `main`; no `gh pr merge` | pre-commit `no-commit-to-branch`, `.claude` hooks + permissions |
| No reading or editing secrets (`.env*`, `*.tfstate`, `*.tfvars`) | `.claude/settings.json` permissions, gitleaks |
| Hand-written `evals/cases.yaml`, immutable migrations and ADRs, read-only `data/raw/` | `.claude/hooks/protect-files.sh`, permissions |
| Graph/judge/ingest code never imports FastAPI | ruff `TID251` |
| Type hints and docstrings on every function | mypy strict, ruff `D101`–`D103` |
| No task/plan references in code | pre-commit `no-plan-references` |
| No test touches the network | `pytest-socket` (`--allow-hosts` loopback only) |
| Formatting, lint, tests | `make` targets, run by hooks, pre-commit and CI alike |

## Adding a feature

**Branch first, before the spec.** The spec, plan and code travel together
on one branch; `main` gets finished work through a reviewed PR only.

Use the `superpowers` skills by name with the Skill tool. Don't approximate
them by hand.

| Step | Skill | Produces |
| --- | --- | --- |
| Agree a design | `superpowers:brainstorming` | `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` |
| Order the work | `superpowers:writing-plans` | `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` |
| Build, test first | `superpowers:test-driven-development`, then `superpowers:executing-plans` | green commits |
| Review | `superpowers:requesting-code-review` | findings |

- **Draft PR as soon as the spec is committed** (`gh pr create --draft`),
  and push after every later commit so the PR never lags the branch.
- **When done, `gh pr ready <n>`. The owner merges.** Use
  `superpowers:finishing-a-development-branch` for its pre-merge checks
  only, and stop before it merges.
- **Work with no spec** (a one-file fix) opens a ready PR directly.
- **One PR per logical change.**
- **Classify size first.** A one-file fix needs no spec. If a "small" change
  grows, stop and upgrade it to spec + plan.
- **Specs lead with measured evidence:** eval scores, token costs, latency,
  row counts from the database. "Add appropriate handling" is a defect.
- **Plans carry constraints, ordering and verified syntax** (a signature, a
  SQL form, a tricky fixture), not finished code. Code in a plan makes "does
  it match the plan?" a tautology and goes stale immediately.
- **A supervisor driving subagents owns the plan's checkboxes.** Tick a task
  when it's implemented _and_ verified by review, never on an implementer's
  DONE.
- **Use `superpowers:systematic-debugging` before proposing any fix, and
  `superpowers:verification-before-completion` before claiming anything
  passes.** Run the command and read the output.
- **A change that makes or reverses an architectural decision adds or
  supersedes a record in `docs/decisions/` in the same PR.** Superseding
  changes only the old record's Status line (see `docs/decisions/README.md`).

## Commits and PRs

Conventional Commits; the checker enforces the format. **Default to no
body**; add one or two sentences only when the diff can't carry the _why_.
PR descriptions: a short summary, plus a one-line test note if needed. No
headers or checklists except for multi-task feature landings.

## Invariants

Load-bearing, not enforced by a tool. Breaking one breaks the demo's claims.

- **Answers come only from retrieved chunks.** Every citation quote is an
  exact substring of its chunk, checked in code before any judge runs.
- **The model never rates its own confidence.** Confidence is the judge's
  probability; self-reported scores are poorly calibrated.
- **One embedding model per `chunks` table.** pgvector dimensions are fixed;
  switching models means a new table and a re-ingest, never a mix.
- **Costs are stored when the row is written,** at the prices of that
  moment. Never recompute history from current prices.
- **The same image runs on the homelab and Azure.** Everything that differs
  is an env var. No Azure SDK for secrets or storage.
- **Ingestion is idempotent per file hash and embedding model;** a new
  directive edition replaces the old one's chunks.
- **Eval answer keys are checked against the directive PDF,** not summary
  pages, with `expected_sections` from the ingested edition.
- **Models are called only through LiteLLM aliases** (`chat`, `judge`,
  `chat-dev`, `embed`), never a provider SDK or URL in app code. The
  decision judge runs inside the cluster.
- **Evals and the demo run on pinned paid models.** `chat-dev` (a free
  model) is for building only; the eval runner refuses it.

## Comments and docstrings

- **Comments explain _why_ and name the bug that motivated the code.** A
  comment restating the line is noise; one saying what breaks if you
  "simplify" it is the point.
- **Be concise:** state the rule and the failure it prevents in one to three
  sentences. History belongs in the commit message.
- **Docstrings are the contract for a caller who never reads the body:**
  what's returned, what `None` means, what's raised, side effects. One line
  is usually enough.

## Testing

- `make test` is the unit suite: fake LLM, fake judge, no DB, no network.
  `@pytest.mark.integration` tests need Postgres + pgvector (`DATABASE_URL`).
- `@pytest.mark.eval` calls real models and costs money. **Never run
  `make eval` unless asked.**
- Test names are full sentences: `test_quote_missing_from_chunk_zeroes_confidence`.

## Examining content

Read narrowly: `grep -n` to locate, then `Read` with offset/limit. Never
read a whole large file to inspect part of it. Hand large artifacts to
subagents as file paths.
