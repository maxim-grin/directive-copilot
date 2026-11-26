# One place for every check command. Claude Code hooks, pre-commit and CI
# all call these targets, so a command changes here and nowhere else.
#
# Targets that need a tool the machine may not have (node, terraform,
# kubectl) say so and exit non-zero rather than silently passing.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

WEB := web
TF_DIRS := deploy/azure deploy/azure/bootstrap
K8S_OVERLAY := deploy/k8s/overlays/homelab

.PHONY: help
help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-18s %s\n", $$1, $$2}'

# --- Python -----------------------------------------------------------------

.PHONY: fmt
fmt: ## Format and auto-fix Python
	uv run ruff format .
	uv run ruff check --fix .

.PHONY: lint
lint: ## Lint + typecheck Python (no changes)
	uv run ruff format --check .
	uv run ruff check .
	uv run mypy

.PHONY: test
test: ## Unit tests: fake LLM + judge, no DB, no network (pytest's default markers)
	uv run pytest -q

.PHONY: test-integration
test-integration: ## Integration tests; needs DATABASE_URL pointing at Postgres + pgvector
	@# Without migrations there is no alembic to spawn, and CI failed on it.
	if [ -f alembic.ini ]; then uv run alembic upgrade head; fi
	@# Exit 5 means no integration tests were collected yet; that's not a failure.
	uv run pytest -q -m integration || [ $$? -eq 5 ]

.PHONY: eval
eval: ## Run the eval set against real models (costs money). JUDGE=llm|decision
	uv run pytest -q -m eval --allow-hosts=*

# --- Web ----------------------------------------------------------------------

.PHONY: lint-web
lint-web: require-node ## Prettier check, lint, typecheck (fast; no build)
	cd $(WEB) && npx prettier --check . && npm run lint && npm run typecheck

.PHONY: check-web
check-web: lint-web ## lint-web + build + API types up to date
	cd $(WEB) && npm run build
	$(MAKE) api-types
	git diff --exit-code -- $(WEB)/openapi.json $(WEB)/src/api/schema.d.ts \
	  || { echo "API types are stale: run 'make api-types' and commit the result" >&2; exit 1; }

.PHONY: api-types
api-types: require-node ## Regenerate the TS client from FastAPI's OpenAPI schema
	uv run python -c "import json; from copilot.api import app; print(json.dumps(app.openapi()))" > $(WEB)/openapi.json
	$(WEB)/node_modules/.bin/openapi-typescript $(WEB)/openapi.json -o $(WEB)/src/api/schema.d.ts

# --- Infra --------------------------------------------------------------------

.PHONY: check-infra
check-infra: ## Render Kustomize, terraform fmt + validate (no cluster or cloud access)
	@command -v kubectl >/dev/null || { echo "kubectl not installed" >&2; exit 1; }
	@command -v terraform >/dev/null || { echo "terraform not installed" >&2; exit 1; }
	kubectl kustomize $(K8S_OVERLAY) > /dev/null
	terraform fmt -check -recursive deploy/azure
	for dir in $(TF_DIRS); do \
	  terraform -chdir="$$dir" init -backend=false -input=false > /dev/null; \
	  terraform -chdir="$$dir" validate -no-color; \
	done

# --- Helpers ------------------------------------------------------------------

.PHONY: require-node
require-node:
	@[ -x $(WEB)/node_modules/.bin/prettier ] || { echo "web deps missing: run 'npm --prefix $(WEB) ci'" >&2; exit 1; }
