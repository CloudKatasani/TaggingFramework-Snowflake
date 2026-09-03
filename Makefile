# =============================================================================
# Enterprise Snowflake Tagging Framework
# =============================================================================
# The catalog is the source of truth. Everything else is generated or validated
# against it. `make check` is exactly what CI runs.
# =============================================================================

PY      := python3
SCRIPTS := scripts

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	 | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: validate
validate: ## Validate config/tag_catalog.yaml against structural + governance rules
	@cd $(SCRIPTS) && $(PY) validate_catalog.py

.PHONY: build
build: validate ## Regenerate SQL and reference docs from the catalog
	@cd $(SCRIPTS) && $(PY) generate_sql.py
	@cd $(SCRIPTS) && $(PY) generate_docs.py
	@cd $(SCRIPTS) && $(PY) generate_tfvars.py

.PHONY: check
check: validate ## Verify generated artifacts are in sync with the catalog (CI gate)
	@cd $(SCRIPTS) && $(PY) generate_sql.py --check
	@cd $(SCRIPTS) && $(PY) generate_docs.py --check
	@cd $(SCRIPTS) && $(PY) generate_tfvars.py --check
	@cd $(SCRIPTS) && $(PY) lint_sql.py

.PHONY: test
test: ## Run the unit test suite
	@$(PY) -m pytest tests -q

.PHONY: all
all: build test check ## Full local build

.PHONY: deploy-plan
deploy-plan: ## Print the deployment order for a fresh Snowflake account
	@$(PY) $(SCRIPTS)/deploy.py --plan

.PHONY: clean
clean: ## Remove Python caches
	@find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -name '.pytest_cache' -type d -prune -exec rm -rf {} + 2>/dev/null || true
