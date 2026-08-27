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
| `make module-test MODULE=x` | a mounted module's own pytest suite (`repos/django/x`) inside the service container |
| `make embed` | image-embedding service (Infinity, :8097, loopback only) for the lookup module; GPU auto-detected, `EMBED_GPU=0/1` forces; `make dev` keeps it in the stack when it is up |
| `make lookup-eval` | precision/recall of the lookup engine on the test package's labelled pairs (needs a fresh `make seed`) |
| `make clone-tests` / `seed` / `bdd` | Emporium test package: clone to `repos/tests/`, seed the DB (needs the `worker` container up), behave suite (`TAGS=@tag`) |
| `make pwa` / `cms` / `frontends` | storefront (:3100) and admin CMS (:8180), each built from its GitHub repo |
| `make cms-dev` | admin CMS served from `repos/pwa/entirius-pwa-cms` with hot reload |
| `make docs` / `clone-docs` | docs portal (:4421, Astro hot reload) from `repos/docs/entirius-docs` — private GitLab clone, not built from GitHub; `make docs-alt DOCS_ALT_BRANCH=x` runs a second branch on :4422 |
| `make www WWW_BRANCH=x` | marketing site entirius.com (:3200, Next.js hot reload) from `repos/www/entirius-react-www-<branch>` — private GitLab clone |
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
  every module repo found in `repos/py/` and `repos/django/`. The worker gets the same
  mounts with its own venv volume and additionally consumes the `atlas_*` Celery queues.
- Host ports are shifted +100 from standard (postgres 5532, redis 6479, rabbitmq 5772,
  service 8100, embed 8097) — developers run local instances on the standard ones.
- `repos/` is gitignored — group local clones: `py/`, `django/`, `services/`, `pwa/`
  (storefront + CMS), `docs/` (documentation portal), `www/` (entirius.com). Frontend containers build from GitHub, not from `repos/pwa/`.

## Green baselines

| Gate | Expected | Takes |
|---|---|---|
| `make seed` | `SEED OK` | ~8-15 min |
| `make bdd` (fresh seed) | 645 passed / 0 failed / 15 skipped | ~5 min |
| `make e2e` (frontends up) | 4 passed | ~10 s |
| `make lookup-eval` (fresh seed, embed up) | 240 pairs (positives = match) · P/R @45 = 0.74/0.98 · @75 = 1.00/0.31 · auto-linked true pairs 38/59, wrongly auto-linked 0 · recall@50 name-leg 0.99 · recall@20 image-leg 0.63 (SigLIP so400m; measured 2026-08-25 over three fresh seeds — every metric above, the image leg included, came back identical on all three) | ~1 min |

Suppliers-admin, atlas push, atlas merge and `@lookup-oneshot` scenarios are one-shot per database —
a BDD re-run needs a fresh `make seed`. The lookup numbers are measured, never derived: re-measure after
any change to scoring, fixtures or the embedding model, and keep the order `seed` → `bdd` → `lookup-eval` —
the `@lookup-oneshot` scenario links one fixture pair, so an eval run after BDD skips it by design.

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
- The dev-mode worker runs your mounts, but Celery has no autoreload — restart the
  worker after module changes that affect tasks.
- Feed URLs pointing at the `fixtures` container need the SSRF escape hatches in
  `docker/settings_local.py` (`SUPPLIER_BLOCK_PRIVATE_HOSTS` / `ATLAS_BLOCK_PRIVATE_HOSTS`).
- Standalone re-runs of `seed-atlas-e2e.py` wipe the pricefighter-calibrated
  observations — re-run `seed-atlas-workload.py` + `seed-pricefighter-e2e.py` after it.
- Storefront config is baked at image build — a changed `SERVICE_PORT`/`PWA_CHANNEL`
  needs `make pwa` again.
- First `make e2e` needs `uv run --extra e2e playwright install chromium` in the
  test-package clone (host side).
- Postgres is `pgvector/pgvector:pg16` — ships `vector`, `pg_trgm`, `unaccent`; module migrations
  create them. Data volume is shared with the old `postgres:16-alpine` (same major, but musl→glibc
  collation: run `REINDEX DATABASE entirius` once after the switch).
- The lookup image layer MUST point at Infinity's `/embeddings_image`, never `/embeddings`
  (`docker/settings_local.py`). Both exist and both answer 200; the text route embeds an image
  data URL as a *string*, and since every photo shares the `data:image/jpeg;base64,` prefix they
  all collapse onto one vector — image blocking dies silently, with nothing in the logs. Measured
  here 2026-08-25: black vs white square came back at cosine 1.0000 through `/embeddings` and
  0.9264 through `/embeddings_image`; fixing the route moved `recall@20` from 0.25 to 0.63.
  It also explains a symptom that used to be blamed on HNSW being approximate: near-identical
  vectors left the search resolving ties by traversal order, so the image leg looked random. With
  real vectors it is deterministic — three fresh seeds returned the same number.
  `manage.py lookup_doctor` is the handshake that catches it.
- `make embed` GPU variant needs the GPU visible to Docker via CDI (`/etc/cdi/nvidia.yaml`,
  generated with `nvidia-ctk cdi generate`; regenerate after a driver update). Without the spec `make embed`
  falls back to CPU. First start downloads `EMBED_MODEL` (minutes) into the `hf_cache` volume — `make clean`
  deletes it; the healthcheck allows 5 min.

## Dev-runner

`scripts/dev-runner/` executes `todo/<topic>/dev-plans/` plan-by-plan with fresh `claude -p` roles in
`~/.claude-runner/<role>` profiles (models per role in `scripts/dev-runner/.env`; all Opus since 2026-08-24): `make runner-init` · `runner-test`
(mocks, zero tokens) · `runner-once` / `runner-loop` / `runner-status` / `runner-stop` (`PLANS=<dir>`).
Script-enforced: no push (hook), write scope = `REPOS:` of the plan, gitleaks before `ready`, per-role/plan/daily
budgets, watchdog. Local commits only — the operator pushes. Runbook: `scripts/dev-runner/README.md`.

## Roadmap & Todo (local only)

`roadmap/` (functional analyses) and `todo/` (dev-plans, punch lists) are gitignored — operator's local
planning and execution layers, not part of the harness. Conventions live inside those folders.

## Development Standards

Two tiers, split by the knowledge contract — never duplicate a rule across them:

| Tier | Where | Holds |
|---|---|---|
| Public engineering canon | `repos/docs/entirius-docs/src/content/docs/handbook/` (`make clone-docs`, served by `make docs`) | how to write code: `django-module.md` (module layout: models/schemas/services/api), `api-v2/*`, `python-toolchain.md`, `git-flow.md`, `releases.md`, `repo-naming.md`, `makefile.md`, `ci-cd.md`, `language.md`, `licensing.md`, `secret-scanning.md`, `agents-md.md` |
| Internal additions | `~/kloczi_pc/coding/ecomhouse/standardy-rozwoju-oprogramowania/` — the canonical clone, **not** under `repos/`; every `.gitleaks.toml` symlink in this repo and in the module clones resolves into it | registries (`rejestr-*`), gitleaks blocklists + repo templates (`02-workflow/templates/`), agent working convention, migration/cutover procedures, `03-entirius-zeno/` (this harness's program folder), `04-kontrakt-wiedzy/` (the contract itself) |

Product architecture decisions are ADRs in `entirius-docs/src/content/docs/architecture/` — not in either list above.
The standards repo is Polish and private (client names); the handbook is English and public.

Never clone a second copy of the standards repo — the client-name blocklist it carries is security-critical
and a duplicate drifts silently. Procedures that reference it expect
`ECOMHOUSE_STANDARDS=~/kloczi_pc/coding/ecomhouse/standardy-rozwoju-oprogramowania` in the environment.

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
