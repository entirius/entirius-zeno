.PHONY: lookup-eval runner-init runner-once runner-loop runner-status runner-stop runner-test runner-dry help init clone clone-repos clone-tests clone-docs refresh-repos build up up-infra dev link embed module-test down logs status shell health urls migrate test smoke seed bdd e2e pwa cms cms-dev frontends docs docs-alt www check clean
.DEFAULT_GOAL := help

-include .env
export

COMPOSE = docker compose
COMPOSE_DEV = $(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml
PROFILES = --profile infra --profile service
# pwa/cms are opt-in (started by their own targets), but teardown and introspection
# must always see the whole stack — otherwise frontends outlive `down`/`clean`.
ALL_PROFILES = $(PROFILES) --profile pwa --profile cms --profile docs --profile www --profile embed
# Embedding service: EMBED_GPU=1 layers the CUDA + GPU (CDI) override on the dev compose.
# Auto-detected from the CDI spec; .env or the command line override it.
EMBED_GPU ?= $(shell test -f /etc/cdi/nvidia.yaml && echo 1 || echo 0)
EMBED_COMPOSE = $(COMPOSE_DEV) $(if $(filter 1,$(EMBED_GPU)),-f docker-compose.gpu.yml)
SERVICE ?= entirius-service-volkanos
TESTS_PATH ?= ./repos/tests
DOCS_PATH ?= ./repos/docs
DOCS_REPO = ssh://git@gitlab.lazelab.com:4227/entirius/entirius-docs.git
WWW_PATH ?= ./repos/www
WWW_BRANCH ?= master
WWW_REPO = ssh://git@gitlab.lazelab.com:4227/entirius/entirius-react-www.git
TESTS_REPO = entirius-test-package-emporium

help:  ## List targets
	@grep -E '^[a-z0-9-]+:.*##' $(firstword $(MAKEFILE_LIST)) | awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

init:  ## Create .env from template + repos/ layout
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@mkdir -p repos/py repos/django repos/services repos/tests repos/pwa repos/docs repos/www

clone:  ## Clone the service under test into repos/services/ (dev mode prerequisite)
	@test -d repos/services/$(SERVICE)/.git || \
		git clone git@github.com:entirius/$(SERVICE).git repos/services/$(SERVICE)

clone-repos:  ## Clone ALL entirius repos into repos/ groups; modules pinned to service uv.lock versions
	@sh scripts/clone-repos.sh $(SERVICE)

clone-tests:  ## Clone the Emporium test package (data + BDD) into repos/tests/
	@test -d $(TESTS_PATH)/$(TESTS_REPO)/.git || \
		git clone git@github.com:entirius/$(TESTS_REPO).git $(TESTS_PATH)/$(TESTS_REPO)

refresh-repos:  ## Update existing repos/ clones: service to SERVICE_BRANCH, modules to uv.lock tags
	@sh scripts/refresh-repos.sh $(SERVICE)

# Compose builds a missing image implicitly — without the REF build arg, so with no
# cache busting on HEAD change. Require an explicit `make build` instead.
define REQUIRE_IMAGE
docker image inspect $${COMPOSE_PROJECT_NAME:-entirius-zeno}-service >/dev/null 2>&1 || \
{ echo "service image not built yet - run 'make build' first"; exit 1; }
endef

# Resolves the remote branch SHA into $$ref — passed as a build arg so the clone layer
# cache busts exactly on HEAD change. Empty means repo or branch does not exist: fail
# here instead of misleadingly deep inside `git clone` in the Dockerfile.
define REF
ref=$$(GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/entirius/$(1).git refs/heads/$(2) 2>/dev/null | cut -f1); \
[ -n "$$ref" ] || { echo "cannot resolve entirius/$(1)@$(2) - missing repo, branch, or not public?"; exit 1; }
endef

build:  ## Build the service image (clones SERVICE@SERVICE_BRANCH from GitHub)
	@$(call REF,$(SERVICE),$${SERVICE_BRANCH:-master}); \
	SERVICE_REF=$$ref $(COMPOSE) $(PROFILES) build

up:  ## Start infra + service (code baked into the image)
	@$(call REQUIRE_IMAGE)
	$(COMPOSE) $(PROFILES) up -d
	@$(MAKE) --no-print-directory urls

docs-alt:  ## Start a second docs portal from a feature branch: make docs-alt DOCS_ALT_BRANCH=<branch>
	@test -n "$(DOCS_ALT_BRANCH)" || { echo "ERROR: DOCS_ALT_BRANCH is required (e.g. make docs-alt DOCS_ALT_BRANCH=rafaldev)"; exit 1; }
	@test -d $(DOCS_PATH)/entirius-docs-$(DOCS_ALT_BRANCH)/.git || \
		git clone -b $(DOCS_ALT_BRANCH) $(DOCS_REPO) $(DOCS_PATH)/entirius-docs-$(DOCS_ALT_BRANCH)
	@DOCS_ALT_BRANCH=$(DOCS_ALT_BRANCH) $(COMPOSE) $(PROFILES) --profile docs up -d --build docs-alt
	@$(MAKE) --no-print-directory urls

www:  ## Start the marketing site (Next.js, hot reload) from repos/www/entirius-react-www-$(WWW_BRANCH)
	@test -d $(WWW_PATH)/entirius-react-www-$(WWW_BRANCH)/.git || \
		git clone -b $(WWW_BRANCH) $(WWW_REPO) $(WWW_PATH)/entirius-react-www-$(WWW_BRANCH)
	@WWW_BRANCH=$(WWW_BRANCH) $(COMPOSE) $(PROFILES) --profile www up -d --build www
	@$(MAKE) --no-print-directory urls

up-infra:  ## Start infra only (postgres, redis, rabbitmq)
	$(COMPOSE) --profile infra up -d
	@$(MAKE) --no-print-directory urls

dev:  ## Start with repos/ mounted for hot reload (run `make clone` first)
	@test -f repos/services/$(SERVICE)/pyproject.toml || \
		{ echo "repos/services/$(SERVICE) is empty - run 'make clone' first"; exit 1; }
	@$(call REQUIRE_IMAGE)
	$(COMPOSE_DEV) $(PROFILES) up -d
# `up` without the embed profile would leave an already-running embed orphaned/stopped on
# the next recreate — keep it in the stack when it is up (the lookup module needs it).
	@docker ps --format '{{.Names}}' | grep -q -- '-embed-1$$' && $(MAKE) --no-print-directory embed >/dev/null || true
# Best-effort: right after start the venv may still be syncing, so the dashboard can
# report stale provenance — rerun `make dashboard` once the stack settles.
	@python3 scripts/dashboard.py 2>/dev/null || true
	@$(MAKE) --no-print-directory urls

link:  ## Re-link mounted module repos in service AND worker without restarting (dev mode)
	@for svc in service worker; do \
		echo "== $$svc =="; \
		$(COMPOSE) exec $$svc sh -c '\
			for dir in /entirius/py/*/ /entirius/django/*/; do \
				[ -f "$$dir/pyproject.toml" ] || continue; \
				uv pip install --no-deps -e "$$dir"; \
			done'; \
	done
	@echo "NOTE: celery does not autoreload — restart the worker to pick up task-code changes"

embed:  ## Start the embedding service (profile embed; EMBED_GPU=0 for CPU) — first start downloads the model
	@$(EMBED_COMPOSE) $(PROFILES) --profile embed up -d embed
	@$(MAKE) --no-print-directory urls

# Runs the module's own suite with the service venv (dev mode: repos/django/ is mounted at
# /entirius/django). -p no:cacheprovider: container is root, the repo is a bind mount.
lookup-eval:  ## Measure lookup precision/recall on the labelled pairs of the test package (fresh `make seed` first)
	@$(COMPOSE) $(PROFILES) exec -T service python manage.py lookup_eval \
		--pairs /entirius/test-package/fixtures/lookup/labelled_pairs.csv $(LOOKUP_EVAL_ARGS)

module-test:  ## Run a mounted module's tests in the service container: make module-test MODULE=entirius-django-x
	@echo "$(MODULE)" | grep -Eq '^[A-Za-z0-9._-]+$$' || { echo "ERROR: MODULE is required (e.g. make module-test MODULE=entirius-django-lookup)"; exit 1; }
	@$(COMPOSE) exec service sh -c 'test -d "/entirius/django/$$1" || { echo "/entirius/django/$$1 not mounted - clone it under repos/django/ and run make dev"; exit 1; }; cd "/entirius/django/$$1" && python -m pytest tests -q -p no:cacheprovider' _ '$(MODULE)'

down:  ## Stop everything
	$(COMPOSE_DEV) $(ALL_PROFILES) down

logs:  ## Tail logs
	$(COMPOSE) $(ALL_PROFILES) logs -f

status:  ## Container status
	$(COMPOSE) $(ALL_PROFILES) ps

shell:  ## Shell into the service container
	$(COMPOSE) exec service bash

# Ports read from the live containers (docker compose port), not from .env — never lies.
urls:  ## URLs and ports of running services
	@up=0; \
	p=$$($(COMPOSE) port service 8000 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  service      http://localhost:$$p  (Swagger UI: /api/schema/swagger-ui/)"; up=1; }; \
	p=$$($(COMPOSE) port dashboard 8080 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  zeno suite   http://localhost:$$p  (dashboard)"; up=1; }; \
	p=$$($(COMPOSE) --profile pwa port pwa 3000 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  storefront   http://localhost:$$p"; up=1; }; \
	p=$$($(COMPOSE) --profile cms port cms 8080 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  cms          http://localhost:$$p  (admin / admin123)"; up=1; }; \
	p=$$($(COMPOSE) --profile docs port docs 4321 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  docs         http://localhost:$$p"; up=1; }; \
	p=$$($(COMPOSE) --profile docs port docs-alt 4321 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  docs-alt     http://localhost:$$p  (branch: $${DOCS_ALT_BRANCH:-?})"; up=1; }; \
	p=$$($(COMPOSE) --profile www port www 3000 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  www          http://localhost:$$p  (branch: $(WWW_BRANCH))"; up=1; }; \
	p=$$($(COMPOSE) --profile embed port embed 7997 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  embed        http://localhost:$$p  (embeddings; /docs, /models)"; up=1; }; \
	p=$$($(COMPOSE) port db 5432 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  postgres     localhost:$$p  ($${POSTGRES_USER:-entirius}/$${POSTGRES_PASSWORD:-entirius-dev}, db: $${POSTGRES_DB:-entirius})"; up=1; }; \
	p=$$($(COMPOSE) port redis 6379 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  redis        localhost:$$p"; up=1; }; \
	p=$$($(COMPOSE) port rabbitmq 5672 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  rabbitmq     amqp://localhost:$$p"; up=1; }; \
	p=$$($(COMPOSE) port rabbitmq 15672 2>/dev/null | cut -d: -f2); \
	[ -n "$$p" ] && { echo "  rabbitmq-ui  http://localhost:$$p  ($${RABBITMQ_DEFAULT_USER:-guest}/$${RABBITMQ_DEFAULT_PASS:-guest})"; up=1; }; \
	[ "$$up" = "1" ] || echo "  (nothing running — make up)"

health:  ## Verify infra healthchecks + service HTTP
	@fail=0; \
	for svc in db redis rabbitmq; do \
		s=$$(docker inspect --format='{{.State.Health.Status}}' $${COMPOSE_PROJECT_NAME:-entirius-zeno}-$$svc-1 2>/dev/null); \
		if [ "$$s" = "healthy" ]; then echo "  $$svc: healthy"; else echo "  $$svc: $${s:-not running}"; fail=1; fi; \
	done; \
	code=$$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:$${SERVICE_PORT:-8100}/api/schema/ 2>/dev/null); \
	if [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ] 2>/dev/null; then echo "  service: HTTP $$code"; \
	else echo "  service: FAIL (HTTP $$code)"; fail=1; fi; \
	if [ $$fail -eq 0 ]; then echo "All services OK"; else echo "Some services unhealthy"; exit 1; fi

migrate:  ## Apply service migrations
	$(COMPOSE) exec service python manage.py migrate

# -p no:cacheprovider: container runs as root — a cache dir would land root-owned
# on the bind-mounted repo in dev mode
test:  ## Migration drift check + service test suite (against postgres)
	$(COMPOSE) exec service python manage.py makemigrations --check --dry-run
	$(COMPOSE) exec service pytest -x -q -p no:cacheprovider

smoke:  ## Boot proof: migrations, system check, admin + API over HTTP, session login
	@$(MAKE) --no-print-directory health
	@sh scripts/smoke.sh

pwa:  ## Start the storefront (build from GitHub on first run)
	@$(call REF,entirius-pwa-storefront,$${PWA_BRANCH:-develop}); \
	PWA_REF=$$ref $(COMPOSE) $(PROFILES) --profile pwa up -d --build pwa
	@$(MAKE) --no-print-directory urls

cms:  ## Start the admin CMS (build from GitHub on first run)
	@$(call REF,entirius-pwa-cms,$${CMS_BRANCH:-develop}); \
	CMS_REF=$$ref $(COMPOSE) $(PROFILES) --profile cms up -d --build cms
	@$(MAKE) --no-print-directory urls

cms-dev:  ## Start the admin CMS from repos/pwa/entirius-pwa-cms (hot reload)
	@test -d repos/pwa/entirius-pwa-cms/.git || \
		{ echo "ERROR: repos/pwa/entirius-pwa-cms not cloned — run:"; \
		  echo "  git clone git@github.com:entirius/entirius-pwa-cms.git repos/pwa/entirius-pwa-cms"; exit 1; }
	@$(MAKE) --no-print-directory cms COMPOSE="$(COMPOSE_DEV)"

frontends: pwa cms  ## Start both frontends

clone-docs:  ## Clone the documentation portal (private GitLab) into repos/docs/
	@test -d $(DOCS_PATH)/entirius-docs/.git || git clone $(DOCS_REPO) $(DOCS_PATH)/entirius-docs

docs: clone-docs  ## Start the docs portal from repos/docs/entirius-docs (hot reload)
	@$(COMPOSE) $(PROFILES) --profile docs up -d --build docs
	@$(MAKE) --no-print-directory urls

dashboard:  ## Regenerate the Zeno Suite dashboard from the live stack
	@python3 scripts/dashboard.py

seed:  ## Seed the service with the Emporium test package (fixtures + full import pipeline)
	@CONTAINER=$$($(COMPOSE) $(PROFILES) ps -q service) \
	DB_CONTAINER=$$($(COMPOSE) $(PROFILES) ps -q db) \
	SVC_DIR=/entirius/services/$(SERVICE) \
	DB_USER=$${POSTGRES_USER:-entirius} \
	DB_NAME=$${POSTGRES_DB:-entirius} \
	bash $(TESTS_PATH)/$(TESTS_REPO)/scripts/seed.sh

# -@spec-first: scenarios ahead of their module; -@blocked-by-module: known module gaps (registry)
bdd:  ## Run the BDD suite against the running service (TAGS=@tag optional)
	@API_BASE_URL=http://localhost:$${SERVICE_PORT:-8100} \
	$(MAKE) --no-print-directory -C $(TESTS_PATH)/$(TESTS_REPO) bdd TAGS=$(TAGS)

e2e:  ## Run Playwright e2e (storefront + CMS) against the running frontends
	@API_BASE_URL=http://localhost:$${SERVICE_PORT:-8100} \
	CMS_BASE_URL=http://localhost:$${CMS_PORT:-8180} \
	$(MAKE) --no-print-directory -C $(TESTS_PATH)/$(TESTS_REPO) e2e E2E_BASE_URL=http://localhost:$${PWA_PORT:-3100}

# --- dev-runner (scripts/dev-runner): executes todo/<topic>/dev-plans one plan per tick ---
PLANS ?= todo/product-lookup-dedup/dev-plans

runner-once:  ## One runner tick on PLANS (default: lookup dev-plans)
	@scripts/dev-runner/runner.sh --once --plans $(PLANS)

runner-dry:  ## Dry run: pick the next plan, change nothing
	@scripts/dev-runner/runner.sh --once --dry-run --plans $(PLANS)

runner-test:  ## Runner mock suite (zero tokens)
	@scripts/dev-runner/tests/run-local.sh

runner-init:  ## Create role profiles ~/.claude-runner/{coder,reviewer,triage} (idempotent)
	@scripts/dev-runner/init.sh

runner-loop:  ## Tick every 5 min until scripts/dev-runner/STOP exists (sleep inhibited)
	@scripts/dev-runner/loop.sh $(PLANS)

runner-status:  ## Plans table, journal tail, today's spend
	@scripts/dev-runner/status.sh $(PLANS)

runner-stop:  ## Stop the runner after the current tick
	@touch scripts/dev-runner/STOP && echo "STOP set — remove scripts/dev-runner/STOP to resume"

check:  ## Verify the canonical .gitleaks.toml is linked here and in every mounted clone
	@sh scripts/check-gitleaks-links.sh

clean:  ## Remove containers and volumes
	$(COMPOSE_DEV) $(ALL_PROFILES) down -v
