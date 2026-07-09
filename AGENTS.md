# AGENTS.md

entirius-zeno — Docker harness for Entirius services: full stack
(service + PostgreSQL/Redis/RabbitMQ) for testing and development.
No application code lives here — compose + Makefile + Dockerfile only.

## Commands

| Command | Meaning |
|---|---|
| `make init` / `clone` | bootstrap `.env` + local clone of the service under test |
| `make clone-repos` | clone all entirius repos into `repos/` groups, modules at uv.lock versions |
| `make build` / `up` / `down` | build image, start/stop the stack |
| `make dev` / `link` | dev mode: mount `repos/`, editable-install module clones |
| `make migrate` / `test` / `health` | migrations, service test suite (postgres), stack health |
| `make urls` | ports/URLs of running services from live containers (auto after `up`/`dev`) |
| `make shell` / `logs` / `status` | debugging |
| `make check` | guard: canonical `.gitleaks.toml` symlink present |
| `make clean` | remove containers and volumes |

## How it works

- Entirius services REQUIRE a per-environment `main/settings_local.py` (fail-closed boot);
  zeno's lives in `docker/settings_local.py` — baked into the image at build, copied into
  the mounted clone on every dev-mode start. It reads compose env vars (`DATABASE_URL`, …).
- `make up`: image built from GitHub (`SERVICE` / `SERVICE_BRANCH` in `.env`);
  `uv sync --frozen` into the project-dir `.venv` (standard layout).
- `make dev`: bind-mounts `repos/` over the image; a named volume shadows the service
  `.venv` (host clone's venv untouched); the entrypoint re-syncs and editable-installs
  every module repo found in `repos/py/` and `repos/django/`.
- Host ports are shifted +100 from standard (postgres 5532, redis 6479, rabbitmq 5772,
  service 8100) — developers run local instances on the standard ones.
- `repos/` is gitignored — group local clones: `py/`, `django/`, `services/`
  (`pwa/` arrives when frontend joins the stack).

## Conventions

- English only: code, docs, commits, branches, PRs.
- MPL-2.0.
- Git flow: `master` (production) + `develop` (integration); changes land via PR.
- `.gitleaks.toml` is a local symlink to the canonical config (never committed);
  `make check` guards it.
- Default: do not commit — git is the user's call.
