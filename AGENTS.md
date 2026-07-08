# AGENTS.md

entirius-zeno — Docker harness for Entirius services: full stack
(service + PostgreSQL/Redis/RabbitMQ) for testing and development.
No application code lives here — compose + Makefile + Dockerfile only.

## Commands

| Command | Meaning |
|---|---|
| `make init` / `clone` | bootstrap `.env` + local clone of the service under test |
| `make build` / `up` / `down` | build image, start/stop the stack |
| `make dev` / `link` | dev mode: mount `repos/`, editable-install module clones |
| `make migrate` / `test` / `health` | migrations, service test suite (postgres), stack health |
| `make shell` / `logs` / `status` | debugging |
| `make check` | guard: canonical `.gitleaks.toml` symlink present |
| `make clean` | remove containers and volumes |

## How it works

- `make up`: image built from GitHub (`SERVICE` / `SERVICE_BRANCH` in `.env`);
  `uv sync --frozen` into `/opt/venv` (outside the project dir, so dev mounts don't hide it).
- `make dev`: bind-mounts `repos/` over the image; the entrypoint re-syncs and
  editable-installs every module repo found in `repos/py/` and `repos/django/`.
- The service reads config from env (python-decouple) — compose passes `DATABASE_URL`
  pointing at the `db` container; no settings files are copied around.
- `repos/` is gitignored — group local clones: `py/`, `django/`, `services/`
  (`pwa/` arrives when frontend joins the stack).

## Conventions

- English only: code, docs, commits, branches, PRs.
- MPL-2.0.
- Git flow: `master` (production) + `develop` (integration); changes land via PR.
- `.gitleaks.toml` is a local symlink to the canonical config (never committed);
  `make check` guards it.
- Default: do not commit — git is the user's call.
