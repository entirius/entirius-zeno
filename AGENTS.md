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
| `make clone-tests` / `seed` / `bdd` | Emporium test package: clone to `repos/tests/`, seed the DB (needs the `worker` container up), behave suite (`TAGS=@tag`) |
| `make pwa` / `cms` / `frontends` | storefront (:3100) and admin CMS (:8180), each built from its GitHub repo |
| `make urls` / `dashboard` | ports/URLs of running services from live containers (auto after `up`/`dev`); regenerate the Zeno Suite page |
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
- `repos/` is gitignored — group local clones: `py/`, `django/`, `services/`, `pwa/`
  (storefront + CMS). Frontend containers build from GitHub, not from `repos/pwa/`.

## Green baselines

| Gate | Expected | Takes |
|---|---|---|
| `make seed` | `SEED OK` | ~15 min |
| `make bdd` (fresh seed) | 576 passed / 0 failed / 20 skipped | ~5 min |
| `make e2e` (frontends up) | 2 passed | ~15 s |

Suppliers-admin scenarios are one-shot per database — a BDD re-run needs a fresh `make seed`.

## Where errors hide

- `make dev` exits 0 even when the service failed to start — truth is in `docker compose logs service`.
- Seed names its failed phase at the end of output: `SEED FAILED (exit N) during: <step>`.
- Right after a dev start the dashboard may report baked mode — venv still syncing; rerun `make dashboard`.

## Fix ownership

Zeno is the harness — most bugs found here are fixed elsewhere:

| Symptom | Fix in |
|---|---|
| Storefront behavior/UI | `entirius-pwa-storefront` |
| Admin CMS behavior/UI | `entirius-pwa-cms` |
| API/service behavior | the service repo (`SERVICE` in `.env`) |
| BDD steps, fixtures, e2e, seed | `entirius-test-package-emporium` |
| Makefile, compose, images, docs | here |

## Gotchas

- Scripted `docker compose` here MUST pass profiles — without them `ps -q` resolves
  nothing (services depend on `db` from the `infra` profile).
- `make clone-tests` before `make up` — the test-package checkout is bind-mounted into
  three containers.
- Edit `docker/settings_local.py`, never `main/settings_local.py` in the clone — the
  entrypoint overwrites it on every dev start.
- The dev-mode worker runs the baked image, not your mounts — restart it after module
  changes that affect tasks.
- Storefront config is baked at image build — a changed `SERVICE_PORT`/`PWA_CHANNEL`
  needs `make pwa` again.
- First `make e2e` needs `uv run --extra e2e playwright install chromium` in the
  test-package clone (host side).

## Conventions

- English only: code, docs, commits, branches, PRs.
- MPL-2.0.
- Git flow: `master` (production) + `develop` (integration); changes land via PR.
- `.gitleaks.toml` is a local symlink to the canonical config (never committed);
  `make check` guards it.
- Default: do not commit — git is the user's call.

## Commit Message Format

**NEVER add `Co-Authored-By: Claude ...` (or any other Claude/Anthropic attribution) to commit messages.**

This overrides the default Claude Code behavior of appending a `Co-Authored-By` trailer. Commit messages MUST contain only the user's authored content — no robot footer, no "Generated with Claude Code" line, no co-author trailer.

Same rule applies to PR descriptions: no `Generated with [Claude Code]` footer.
