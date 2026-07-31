.PHONY: help init clone clone-repos clone-tests refresh-repos build up up-infra dev link down logs status shell health urls migrate test smoke seed bdd e2e pwa cms frontends check clean
.DEFAULT_GOAL := help

-include .env
export

COMPOSE = docker compose
COMPOSE_DEV = $(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml
PROFILES = --profile infra --profile service
SERVICE ?= entirius-service-volkanos
TESTS_PATH ?= ./repos/tests
TESTS_REPO = entirius-test-package-emporium

help:  ## List targets
	@grep -E '^[a-z0-9-]+:.*##' $(firstword $(MAKEFILE_LIST)) | awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

init:  ## Create .env from template + repos/ layout
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@mkdir -p repos/py repos/django repos/services repos/tests

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
	$(COMPOSE) $(PROFILES) up -d
	@$(MAKE) --no-print-directory urls

up-infra:  ## Start infra only (postgres, redis, rabbitmq)
	$(COMPOSE) --profile infra up -d
	@$(MAKE) --no-print-directory urls

dev:  ## Start with repos/ mounted for hot reload (run `make clone` first)
	$(COMPOSE_DEV) $(PROFILES) up -d
	@python3 scripts/dashboard.py 2>/dev/null || true
	@$(MAKE) --no-print-directory urls

link:  ## Re-link mounted module repos without restarting (dev mode)
	$(COMPOSE) exec service sh -c '\
		for dir in /entirius/py/*/ /entirius/django/*/; do \
			[ -f "$$dir/pyproject.toml" ] || continue; \
			uv pip install --no-deps -e "$$dir"; \
		done'

down:  ## Stop everything
	$(COMPOSE_DEV) $(PROFILES) down

logs:  ## Tail logs
	$(COMPOSE) $(PROFILES) logs -f

status:  ## Container status
	$(COMPOSE) $(PROFILES) ps

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

frontends: pwa cms  ## Start both frontends

dashboard:  ## Regenerate the Zeno Suite dashboard from the live stack
	@python3 scripts/dashboard.py

seed:  ## Seed the service with the Emporium test package (fixtures + full import pipeline)
	@CONTAINER=$$($(COMPOSE) ps -q service) \
	DB_CONTAINER=$$($(COMPOSE) ps -q db) \
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

check:  ## Verify canonical .gitleaks.toml is linked
	@grep -q "forbidden-names" .gitleaks.toml 2>/dev/null || { echo "Missing or non-canonical .gitleaks.toml - symlink the config per the internal secret-scanning standard"; exit 1; }

clean:  ## Remove containers and volumes
	$(COMPOSE_DEV) $(PROFILES) down -v
