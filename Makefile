.PHONY: help init clone build up up-infra dev link down logs status shell health migrate test check clean
.DEFAULT_GOAL := help

-include .env
export

COMPOSE = docker compose
COMPOSE_DEV = $(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml
PROFILES = --profile infra --profile service
SERVICE ?= entirius-service-volkanos

help:  ## List targets
	@grep -E '^[a-z-]+:.*##' $(firstword $(MAKEFILE_LIST)) | awk -F':.*##' '{printf "  %-12s %s\n", $$1, $$2}'

init:  ## Create .env from template + repos/ layout
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@mkdir -p repos/py repos/django repos/services

clone:  ## Clone the service under test into repos/services/ (dev mode prerequisite)
	@test -d repos/services/$(SERVICE)/.git || \
		git clone https://github.com/entirius/$(SERVICE).git repos/services/$(SERVICE)

build:  ## Build the service image (clones SERVICE@SERVICE_BRANCH from GitHub)
	$(COMPOSE) $(PROFILES) build

up:  ## Start infra + service (code baked into the image)
	$(COMPOSE) $(PROFILES) up -d

up-infra:  ## Start infra only (postgres, redis, rabbitmq)
	$(COMPOSE) --profile infra up -d

dev:  ## Start with repos/ mounted for hot reload (run `make clone` first)
	$(COMPOSE_DEV) $(PROFILES) up -d

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

health:  ## Verify infra healthchecks + service HTTP
	@fail=0; \
	for svc in db redis rabbitmq; do \
		s=$$(docker inspect --format='{{.State.Health.Status}}' $${COMPOSE_PROJECT_NAME:-entirius-zeno}-$$svc-1 2>/dev/null); \
		if [ "$$s" = "healthy" ]; then echo "  $$svc: healthy"; else echo "  $$svc: $${s:-not running}"; fail=1; fi; \
	done; \
	code=$$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:$${SERVICE_PORT:-8000}/api/schema/ 2>/dev/null); \
	if [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ] 2>/dev/null; then echo "  service: HTTP $$code"; \
	else echo "  service: FAIL (HTTP $$code)"; fail=1; fi; \
	if [ $$fail -eq 0 ]; then echo "All services OK"; else echo "Some services unhealthy"; exit 1; fi

migrate:  ## Apply service migrations
	$(COMPOSE) exec service python manage.py migrate

test:  ## Migration drift check + service test suite (against postgres)
	$(COMPOSE) exec service python manage.py makemigrations --check --dry-run
	$(COMPOSE) exec service pytest -x -q

check:  ## Verify canonical .gitleaks.toml is linked
	@grep -q "forbidden-names" .gitleaks.toml 2>/dev/null || { echo "Missing or non-canonical .gitleaks.toml - symlink the config per the internal secret-scanning standard"; exit 1; }

clean:  ## Remove containers and volumes
	$(COMPOSE_DEV) $(PROFILES) down -v
