# entirius-zeno

Zeno — Docker harness for the Entirius platform.
It runs a full Entirius service with its infrastructure (PostgreSQL, Redis, RabbitMQ)
and gives you one interface — `make` — to test and develop against the running stack.

No application code lives in this repo.
The service image is built straight from its GitHub repo,
and in dev mode your local clones under `repos/` are mounted into the container.

Task-oriented guides: [doc/howto-test.md](doc/howto-test.md) (first run, seeding,
BDD suite) · [doc/howto-develop.md](doc/howto-develop.md) (dev mode, hot reload, feedback loop).

## Requirements

- Docker with Compose v2
- GNU make

## Quick start

```bash
git clone https://github.com/entirius/entirius-zeno.git
cd entirius-zeno
make init      # create .env — adjust SERVICE / SERVICE_BRANCH if needed
make build     # build the service image (clones from GitHub)
make up        # start infrastructure + service
make migrate   # apply migrations
make health    # verify all services respond
make test      # run the service test suite against postgres
```

Service is now at http://localhost:8100/ (Swagger UI: `/api/schema/swagger-ui/`).

To make the stack end-to-end testable, seed it with the Emporium demo dataset and run the BDD suite:

```bash
make clone-tests   # clone entirius-test-package-emporium into repos/tests/
make seed          # fixtures + full import pipeline (products, prices, stock, matrix)
make bdd           # behave suite against the running service (make bdd TAGS=@matrix-v2)
make e2e           # Playwright e2e (storefront + CMS) — needs `make frontends` up
```

Run `make clone-tests` before `make up` — the test-package checkout is bind-mounted
into the stack, so cloning it later needs a restart. `make e2e` runs Playwright on the
host; install its browser once:
`cd repos/tests/entirius-test-package-emporium && uv run --extra e2e playwright install chromium`.

A `worker` container (celery) runs alongside the service — the seed's stock import (QMS)
executes as tasks. In dev mode the worker runs the baked image, not your mounted clones —
restart it after module changes that affect tasks.
Every `make up` / `make dev` ends with a summary of running services and their
ports (read from the live containers); `make urls` prints it any time.

Host ports are shifted +100 from the standard ones (postgres 5532, redis 6479,
rabbitmq 5772, service 8100) — developers usually run local instances on the
standard ports. Override in `.env` if needed.

## Service configuration

Entirius services require a per-environment `main/settings_local.py` and refuse
to boot without one — zeno ships its own in `docker/settings_local.py`.
It bridges compose env vars to Django settings: baked into the image at build,
refreshed in the mounted clone on every dev-mode start.
Change `.env` on the host instead of editing it.

## Two modes

**`make up`** — runs the built image. Code is baked in at build time. Good for testing.

**`make dev`** — mounts your local `repos/` into the container.
You edit code on your machine, Django reloads on save. Good for coding.

### Dev workflow

```bash
make clone     # clone the service under test into repos/services/
make dev       # start with repos/ mounted
# ... edit code in your IDE — Django auto-restarts on save ...
make down      # stop
```

### Whole-platform workflow

```bash
make clone-repos   # clone EVERY entirius repo into its repos/ group;
                   # modules the service depends on land at the uv.lock-pinned version tag
make dev           # entrypoint links every module repo found in repos/py/ and repos/django/
```

Pinned clones sit on a detached HEAD — branch off in the module you develop:

```bash
cd repos/django/entirius-django-utils
git switch -c feature/xyz
# edit — Django reloads on save, the service now runs your module code
```

To work on a single module instead, clone just it into the matching group directory:

```bash
git clone https://github.com/entirius/entirius-django-pim.git repos/django/entirius-django-pim
```

Modules cloned while containers run are picked up by `make link` (no restart needed).

**Why linking?** The image installs locked versions from PyPI.
On dev startup the entrypoint runs `uv pip install --no-deps -e` for every mounted
module repo, so Python imports your local code instead.
Added a clone while containers run? `make link` re-links without a restart.

**Venv:** the service venv lives in the project dir (`.venv`, standard layout).
In dev mode a named volume shadows it, so the container never touches the venv
of your host clone. The container also overwrites `main/settings_local.py`
in the mounted clone with zeno's version — the clone under `repos/` belongs to zeno.

## Frontends

```bash
make frontends   # storefront http://localhost:3100 · admin CMS http://localhost:8180
```

Both are built straight from their GitHub repos (`entirius-pwa-storefront`,
`entirius-pwa-cms`) — clones under `repos/pwa/` are for reading code, not for running it.
They serve `PWA_CHANNEL` (the storefront sells it, the CMS edits it) and talk to the
service on `SERVICE_PORT`. The storefront takes no runtime configuration: its `_CONFIG/`
JSON is written from `.env` values at image build, so a changed port or channel needs
`make pwa` again.

## Directory layout

```
entirius-zeno/
├── Makefile                 # developer interface
├── docker-compose.yml       # profiles: infra, service
├── docker-compose.dev.yml   # dev mode: repos/ bind mounts
├── docker/
│   ├── Dockerfile.service   # python:3.12-slim + uv
│   ├── Dockerfile.pwa       # storefront (Next.js + pnpm)
│   ├── Dockerfile.cms       # admin CMS (Vue CLI)
│   ├── entrypoint-dev.sh    # dev mode: settings_local + sync + link local repos
│   └── settings_local.py    # zeno's per-environment config for the service
├── scripts/                 # repo cloning, smoke test, dashboard generator
├── .env.example
└── repos/                   # local clones (gitignored)
    ├── py/                  # entirius-py-* modules
    ├── django/              # entirius-django-* modules
    ├── services/            # entirius-service-* services
    └── pwa/                 # entirius-pwa-* frontends
```

## Commands

| Command | Description |
|---------|-------------|
| `make init` | Create `.env` from template + `repos/` layout |
| `make clone` | Clone the service under test into `repos/services/` |
| `make clone-repos` | Clone all entirius repos into `repos/` groups (modules at service-locked versions) |
| `make build` | Build the service image |
| `make up` | Start infra + service (baked image) |
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
| `make pwa` | Start the storefront (built from GitHub on first run) |
| `make cms` | Start the admin CMS (built from GitHub on first run) |
| `make frontends` | Start both frontends |
| `make clone-tests` | Clone the Emporium test package (data + BDD) into `repos/tests/` |
| `make seed` | Seed the service with the Emporium test package (fixtures + import pipeline) |
| `make bdd` | Run the BDD suite against the running service (`TAGS=@tag` optional) |
| `make e2e` | Run Playwright e2e (storefront + CMS) against the running frontends |
| `make clean` | Remove containers and volumes |

## Configuration (.env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `SERVICE` | `entirius-service-volkanos` | Service repo to build and run |
| `SERVICE_BRANCH` | `master` | Branch baked into the image |
| `SERVICE_PORT` | `8100` | Host port for the service |
| `POSTGRES_*`, `REDIS_PORT`, `RABBITMQ_*` | dev defaults, ports +100 | Infrastructure credentials and host ports |
| `PWA_PORT` / `CMS_PORT` / `DASHBOARD_PORT` | `3100` / `8180` / `8200` | Host ports for storefront, CMS, Zeno Suite |
| `PWA_CHANNEL` | `default-europe` | Channel the storefront serves and the CMS edits (Emporium seeds it) |

Compose passes `DATABASE_URL` pointing at the `db` container, so the whole stack
(including the test suite) runs against PostgreSQL.

## Dev credentials

| Service | User | Password |
|---------|------|----------|
| PostgreSQL | entirius | entirius-dev |
| RabbitMQ | guest | guest |

Dev defaults only — override in `.env` for anything non-local.

## License

MPL-2.0
