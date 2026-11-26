# References

Sources behind the design of Directive Copilot, grouped by topic. Each entry has a line on what it's used for in this project.

**Before quoting any of these in an article:**
- Check the date and edition. AER directives are reissued, and the decision-model field changes week to week.
- Most decision-model benchmark numbers are reported by the vendors themselves, on suites they chose.

## 1. Regulatory source material (AER)

- **Directive 060: Upstream Petroleum Industry Flaring, Incinerating, and Venting** (directive page). The main corpus for ingestion and eval cases.
  https://www.aer.ca/regulations-and-compliance-enforcement/rules-and-regulations/directives/directive-060
- **Directive 060 (PDF).** The file to ingest; take section numbers for `expected_sections` from it.
  https://static.aer.ca/prd/documents/directives/Directive060.pdf
- **Bulletin 2026-12: New Edition of Directive 060.** The March 2026 edition under Ministerial Order 10/2026, with requirements taking effect from 2030. Source for "recent-change" eval cases.
  https://www.aer.ca/node/5098
- **AER: flaring and incineration notification requirements.** Plain-language summary behind the example eval case (3 km / 1.5 km radius by H2S content, 24-hour notice, no notice in an emergency). Verify each fact against the PDF.
  https://www.aer.ca/node/2749
- **AER: Directive 060 variance applications.** Context on permits and how operators apply for exceptions.
  https://www.aer.ca/node/4259
- **Directive 017: Measurement Requirements for Oil and Gas Operations** (directive page). The second suggested corpus.
  https://www.aer.ca/node/494
- **Directive 017 (PDF, December 2024 edition).**
  https://static.aer.ca/prd/documents/directives/Directive017.pdf
- **Bulletin 2024-34: New Edition of Directive 017 and Directive 042.** What changed in the current edition.
  https://www.aer.ca/node/4587
- **IEA policy database: AER Directive 060.** A neutral third-party summary of the directive's scope.
  https://www.iea.org/policies/8712-alberta-aer-directive-060-upstream-petroleum-industry-flaring-incinerating-and-venting-upstream-provisions

## 2. RAG, orchestration and human-in-the-loop

- **LangGraph: Interrupts.** `interrupt()`, checkpointers and resuming with `Command(resume=...)`: the `human_review` node.
  https://docs.langchain.com/oss/python/langgraph/interrupts
- **LangGraph: Add human-in-the-loop.** Approve / edit / reject patterns.
  https://docs.langchain.com/oss/python/langgraph/add-human-in-the-loop
- **pgvector.** Vector type, HNSW/IVFFlat indexes, and hybrid search with Postgres full-text search.
  https://github.com/pgvector/pgvector

## 3. Evaluation and judges

### LLM-as-judge vs. decision models (overviews)
- **MarkTechPost: "Decision AI models explained: TypeSafe Jev vs Fastino GLiDE, GLiNER2.5-Decide and open-source competitors"** (2 Oct 2026). Category overview, use cases, the "when not to use" list (arithmetic, counting, dates) and a comparison table.
  https://www.marktechpost.com/2026/10/02/decision-ai-models-explained-typesafe-jev-vs-fastino-glide-gliner2-5-decide-and-open-source-competitors/
- **MarkTechPost: "20 Jev alternatives: the decision models taking on TypeSafe in 2026"** (17 Oct 2026).
  https://www.marktechpost.com/2026/10/17/20-jev-alternatives-the-decision-models-taking-on-typesafe-in-2026/
- **DataCamp: "Top 7 Open-Source TypeSafe Jev Alternatives"** (Sep 2026). Laya, Kev, Nimble and others, with local setup notes.
  https://www.datacamp.com/blog/top-open-source-jev-alternatives
- **Analytics Vidhya: "JEV vs LLM as a Judge"** (Oct 2026). Head-to-head test, including calibration (LLM judges cluster near 0 and 1).
  https://www.analyticsvidhya.com/blog/2026/10/jev-vs-llm-as-a-judge-evals/
- **"The Hitchhiker's Guide to System 1 Models: Fast Decision-Making Beyond LLMs"** (arXiv). Survey of the decision-model ecosystem.
  https://arxiv.org/pdf/2610.33775

### Decision models used or considered
- **GLiNER2.5-Decide** (Fastino, Apache 2.0, 340M). The `decision` judge.
  https://huggingface.co/fastino/gliner2.5-decide
- **GLiNER2 library** (Fastino). The Python package the decision service wraps.
  https://github.com/fastino-ai/GLiNER2
- **"GLiNER2: An Efficient Multi-Task Information Extraction System with Schema-Driven Interface"** (EMNLP 2025 demos). The paper behind the model family.
  https://arxiv.org/abs/2507.18546
- **Kev** (Jared Palmer, Apache 2.0). Open Jev-style decision models; considered as a judge and dropped because even Kev-0.8B needs a GPU or Apple Silicon.
  https://github.com/jaredpalmer/kev
  https://huggingface.co/jaredpalmer/kev-0.8b
- **kev-0.5b model card.** The superseded prototype; useful for its explicit "not intended for" list (legal, medical, hiring decisions).
  https://huggingface.co/jaredpalmer/kev-0.5b
- **Jev on OpenRouter.** What Jev is, the Decisions API, and the Noul/Choice/Score primitives. The reference for the System One contract that Kev implements.
  https://openrouter.ai/docs/guides/community/jev
- **TypeSafe docs** (Jev, System One concepts).
  https://docs.typesafe.ai
- **Fastino GLiDE API docs.** The hosted "thinking" decision model, considered and not used: it's API-only in practice.
  https://docs.fastino.ai/inference/systemone

### Decision models in eval tooling
- **DeepEval: JevEval (Jev-as-a-Judge).** Decision model for the verdict, LLM for the explanation.
  https://deepeval.com/blog/introducing-jev-as-a-judge
- **Langfuse: Jev-as-a-judge in Langfuse Evaluators** (22 Sep 2026).
  https://langfuse.com/blog/2026-09-22-running-evals-with-jev
- **MLflow: "Can Jev replace your LLM judge?"** Quality, cost and latency comparison.
  https://mlflow.org/blog/jev-llm-judge

## 3b. Hosted models and billing

- **OpenAI: GPT-6 Luna model page.** Price, structured outputs, function calling: the `chat` model.
  https://developers.openai.com/api/docs/models/gpt-6-luna
- **Microsoft Foundry catalogue: gpt-6-luna.** The same model for the Azure stage.
  https://ai.azure.com/catalog/models/gpt-6-luna
- **Azure blog: GPT-6 Astra, Sol and Luna in Microsoft Foundry.** Deployment types and regions.
  https://azure.microsoft.com/en-us/blog/gpt-6-astra-sol-and-luna-for-production-agents-in-microsoft-foundry/
- **Anthropic: Claude Haiku 5.5.** Price and prompt-length tiers: the `judge` model.
  https://anthropic.com/claude/haiku
- **Microsoft Foundry catalogue: claude-haiku-5-5.** Hosted on Azure, Global Standard and US Data Zone.
  https://ai.azure.com/catalog/models/claude-haiku-5-5
- **OpenRouter: GPT-6 Luna.** Providers serving it, routing and failover; pin the provider for evals.
  https://openrouter.ai/openai/gpt-6-luna
- **OpenRouter FAQ.** Pass-through pricing, credit fee, BYOK, credit expiry and refunds, logging policy.
  https://openrouter.ai/docs/faq
- **OpenRouter support: credits and refunds.** 24-hour refund window; platform fees non-refundable.
  https://openrouter.ai/support
- **Requesty: OpenRouter free model limits (Nov 2026).** 20 requests/minute, 50/day, 1,000/day after a credit purchase.
  https://www.requesty.ai/blog/openrouter-free-models
- **OpenCode Go docs.** Considered and rejected: monthly subscription for coding agents, usage windows, retention per model.
  https://opencode.ai/docs/go/
- **Vercel AI Gateway pricing.** The zero-markup alternative to OpenRouter.
  https://vercel.com/docs/ai-gateway/pricing
- **Microsoft Q&A: free trial LLM quota.** Free trials have zero Azure OpenAI quota; upgrade to pay-as-you-go.
  https://learn.microsoft.com/en-us/answers/a/12804121

## 4. Cost tracking

- **LangChain: How to track token usage.** `AIMessage.usage_metadata` and `UsageMetadataCallbackHandler`: the `UsageTracker` design.
  https://python.langchain.com/docs/how_to/chat_token_usage_tracking
- **LangChain reference: `UsageMetadataCallbackHandler`.**
  https://reference.langchain.com/python/langchain-core/callbacks/usage/UsageMetadataCallbackHandler
- **Azure Cost Management REST API: Query – Usage.** The optional "actual Azure cost" refresh.
  https://learn.microsoft.com/rest/api/cost-management/query/usage
- **Azure: Manage costs with automation.** Data refresh and how often to call the cost APIs.
  https://learn.microsoft.com/azure/cost-management-billing/costs/manage-automation

## 5. Homelab platform (Kubernetes)

- **CloudNativePG: image volume extensions.** Running Postgres with pgvector in the cluster (needs PostgreSQL 18+ for this method).
  https://cloudnative-pg.io/docs/1.30/imagevolume_extensions
- **CloudNativePG: creating a custom container image.** The alternative for Postgres 16/17: bake pgvector into the image.
  https://cloudnative-pg.io/blog/building-images-bake/
- **LiteLLM: Ollama provider.** How LiteLLM serves the local embedding model.
  https://docs.litellm.ai/docs/providers/ollama
- **Ollama.**
  https://github.com/ollama/ollama
- **Kustomize reference.**
  https://kubectl.docs.kubernetes.io/references/kustomize/

## 6. Azure stage

- **Azure Database for PostgreSQL: how to use pgvector.** Allow-list `vector` in `azure.extensions`, then `CREATE EXTENSION`.
  https://learn.microsoft.com/en-us/azure/postgresql/extensions/how-to-use-pgvector
- **Azure Database for PostgreSQL: allow and create extensions.**
  https://learn.microsoft.com/en-us/azure/postgresql/extensions/how-to-create-extensions
- **Azure Container Apps jobs.** Migrate, ingest, eval and scheduled cost-refresh jobs.
  https://learn.microsoft.com/en-us/azure/container-apps/jobs
- **Terraform AzureRM provider documentation.** `azurerm_container_app`, `azurerm_container_app_job`, `azurerm_postgresql_flexible_server_configuration`, `azurerm_cognitive_account` / `azurerm_cognitive_deployment`.
  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- **Terraform AzureRM provider (source and changelog).**
  https://github.com/hashicorp/terraform-provider-azurerm

## 7. Developer workflow

- **Claude Code: Hooks reference.** Events, matchers, exit code 2 and `permissionDecision`: the `.claude/hooks` scripts.
  https://code.claude.com/docs/en/hooks
- **Conventional Commits rules** (qoomon's gist). The rule numbers in `tools/check_commit_msg.py`.
  https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13
- **pre-commit.**
  https://pre-commit.com/
- **ruff pre-commit hooks.**
  https://github.com/astral-sh/ruff-pre-commit
- **gitleaks.** Secret scanning in pre-commit.
  https://github.com/gitleaks/gitleaks
- **FastAPI.**
  https://fastapi.tiangolo.com/
