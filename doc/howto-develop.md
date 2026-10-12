# How to develop with zeno

This guide is for **changing code**: modules (`entirius-django-*`, `entirius-py-*`)
or the service itself, with the full stack running around it.
Just verifying the platform: [howto-test.md](howto-test.md).
Quick start: [README](../README.md).

## Dev mode (hot reload)

`make setup DEV=1` does all of this in one command (clones, build, `make dev`, mail sandbox, CMS
with hot reload, toolbox check, seed). By hand:

```bash
make clone          # service under test -> repos/services/
make clone-tests    # test package — bind-mounted into the stack
make clone-repos    # or: every module repo, pinned to the service uv.lock versions
make build          # service image — dev mode mounts the clones over it
make dev            # containers with repos/ bind-mounted — Django reloads on save
```

Work on a branch inside the module clone; the container editable-installs your local
code, so the service runs it immediately. Pinned clones sit on a detached HEAD —
branch off in the module you touch.

```bash
cd repos/django/entirius-django-pim
git switch -c feature/xyz
# edit — Django reloads on save
```

Added a clone while containers run? `make link` re-links without a restart.

## The feedback loop

| Command | What it proves |
|---|---|
| `make smoke` | 30-second boot proof: migrations, system check, HTTP, admin login |
| `make test` | service unit tests + migration drift check — **against postgres**, like CI |
| `make bdd TAGS=@your-area` | black-box API behavior on seeded data |
| `make dashboard` | regenerate the Zeno Suite dashboard (live ports, which packages are editable from repos/) |

Typical loop: edit → save (auto-reload) → `make bdd TAGS=@pim-admin` → before pushing,
the canonical `make seed && make bdd`.

## Caveats

- **The dev worker runs your mounted clones**, but Celery has no autoreload: restart it
  after task-code changes (QMS quantities, thumbnails, pricelists):
  `docker compose restart worker`.
- `main/settings_local.py` in the mounted clone **belongs to zeno** — it is overwritten
  from `docker/settings_local.py` on every dev-mode start. Change `.env` on the host,
  not the file in the clone.
- The container shadows your clone's `.venv` with a named volume — your host venv is
  never touched.
- `make build` cache-busts the service clone when the branch HEAD moves; check
  `SERVICE_BRANCH` in `.env` if the image looks stale.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Module change has no effect | clone not linked — `make link`; task-side code — restart the worker |
| `ModuleNotFoundError` after switching branches | version drift between clones — `make refresh-repos`, restart |
| Migration drift in `make test` | your model change needs a migration — `makemigrations` in the module |
| Stack wedged beyond repair | `make clean` (drops volumes) → `make up` → `make seed` |

## Two modes

**`make up`** — runs the built image. Code is baked in at build time. Good for testing.

**`make dev`** — mounts your local `repos/` into the containers (service, worker, beat).
You edit code on your machine, Django reloads on save. Good for coding.

**Why linking?** The image installs the locked versions from the service `uv.lock`.
On dev startup the entrypoint runs `uv pip install --no-deps -e` for every mounted
module repo, so Python imports your local code instead.

**Venv:** the service venv lives in the project dir (`.venv`, standard layout).
In dev mode a named volume shadows it, so the container never touches the venv
of your host clone.

## Service configuration

Entirius services require a per-environment `main/settings_local.py` and refuse
to boot without one — zeno ships its own in `docker/settings_local.py`.
It bridges compose env vars to Django settings: baked into the image at build,
refreshed in the mounted clone on every dev-mode start.
Change `.env` on the host instead of editing it.

## Frontends

```bash
make frontends   # storefront http://localhost:3100 · admin CMS http://localhost:8180
make cms-dev     # the CMS from repos/pwa/entirius-pwa-cms, hot reload
```

`make pwa` and `make cms` build straight from their GitHub repos (`entirius-pwa-storefront`,
`entirius-pwa-cms`); `make cms-dev` mounts the local CMS clone instead.
They serve `PWA_CHANNEL` (the storefront sells it, the CMS edits it) and talk to the
service on `SERVICE_PORT`. The storefront takes no runtime configuration: its `_CONFIG/`
JSON is written from `.env` values at image build, so a changed port or channel needs
`make pwa` again. `BUILD_ARGS="--no-cache --pull"` on `make build`, `make pwa` or `make cms`
forces a cold build.

## Directory layout

```
entirius-zeno/
├── Makefile                 # developer interface
├── docker-compose.yml       # profiles: infra, service, pwa, cms, docs, www
├── docker-compose.dev.yml   # dev mode: repos/ bind mounts
├── docker/
│   ├── Dockerfile.service   # python + uv, the service cloned from GitHub
│   ├── Dockerfile.pwa       # storefront
│   ├── Dockerfile.cms       # admin CMS
│   ├── entrypoint-dev.sh    # dev mode: settings_local + sync + link local repos
│   └── settings_local.py    # zeno's per-environment config for the service
├── scripts/                 # setup, repo cloning, smoke test, dashboard generator
├── .env.example
└── repos/                   # local clones (gitignored)
    ├── py/                  # entirius-py-* modules
    ├── django/              # entirius-django-* modules
    ├── services/            # entirius-service-* services
    ├── tests/               # entirius-test-package-* test packages
    └── pwa/                 # entirius-pwa-* frontends
```

## Commands

| Command | Description |
|---------|-------------|
| `make setup` | One command to a seeded stack (`DEV=1`, `SEED=0`, `EMBED=1`) |
| `make init` | Create `.env` from template + `repos/` layout |
| `make clone` | Clone the service under test into `repos/services/` (https) |
| `make clone-repos` | Clone all entirius repos into `repos/` groups (modules at service-locked versions; needs `gh`) |
| `make build` | Build the service image (`BUILD_ARGS` passed to `docker compose build`) |
| `make up` | Start infra + service, worker, beat (baked image) |
| `make up-infra` | Start infrastructure only |
| `make dev` | Start with `repos/` mounted (hot reload) |
| `make link` | Re-link mounted module repos without restart |
| `make down` | Stop everything |
| `make logs` | Tail logs |
| `make status` | Container status |
| `make shell` | Bash into the service container |
| `make urls` | URLs and ports of running services (also printed after `up`/`dev`) |
| `make health` | Verify all services respond |
| `make migrate` | Apply service migrations |
| `make test` | Migration drift check + service test suite |
| `make dashboard` | Regenerate the Zeno Suite dashboard (live stack: ports, editable vs baked packages) |
| `make pwa` / `make cms` / `make frontends` | Start the storefront, the admin CMS, or both (built from GitHub) |
| `make mail` | Start the GreenMail mail sandbox and wait until it is ready |
| `make clone-tests` | Clone the selected test package (`TEST_PACKAGE`, default `entirius-test-package-1`: data + BDD) into `repos/tests/` |
| `make seed` | Seed the service with the test package, the Słoik Chwil demo (fixtures + import pipeline) |
| `make bdd` | Run the BDD suite against the running service (`TAGS=@tag` optional) |
| `make e2e` | Run Playwright e2e (storefront + CMS) against the running frontends |
| `make clean` | Remove containers and volumes |

## Configuration (.env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `SERVICE` | `entirius-service-volkanos` | Service repo to build and run |
| `SERVICE_BRANCH` | `develop` | Branch or tag baked into the image |
| `SERVICE_PORT` | `8100` | Host port for the service |
| `POSTGRES_*`, `REDIS_PORT`, `RABBITMQ_*` | dev defaults, ports +100 | Infrastructure credentials and host ports |
| `PWA_PORT` / `CMS_PORT` / `DASHBOARD_PORT` | `3100` / `8180` / `8200` | Host ports for storefront, CMS, Zeno Suite |
| `PWA_CHANNEL` | `sloik-pl` | Channel the storefront serves and the CMS edits (the seed creates it) |

Compose passes `DATABASE_URL` pointing at the `db` container, so the whole stack
(including the test suite) runs against PostgreSQL. Dev credentials: PostgreSQL
`entirius` / `entirius-dev`, RabbitMQ `guest` / `guest` — dev defaults only, override
in `.env` for anything non-local.
