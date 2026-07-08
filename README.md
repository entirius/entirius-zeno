# entirius-zeno

Zeno — Docker harness for the Entirius platform.
It runs a full Entirius service with its infrastructure (PostgreSQL, Redis, RabbitMQ)
and gives you one interface — `make` — to test and develop against the running stack.

No application code lives in this repo.
The service image is built straight from its GitHub repo,
and in dev mode your local clones under `repos/` are mounted into the container.

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

Service is now at http://localhost:8000/ (Swagger UI: `/api/schema/swagger-ui/`).

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

To work on a module, clone it into the matching group directory:

```bash
git clone https://github.com/entirius/entirius-django-pim.git repos/django/entirius-django-pim
make dev       # entrypoint links every module repo found in repos/py/ and repos/django/
```

**Why linking?** The image installs locked versions from PyPI.
On dev startup the entrypoint runs `uv pip install --no-deps -e` for every mounted
module repo, so Python imports your local code instead.
Added a clone while containers run? `make link` re-links without a restart.

## Directory layout

```
entirius-zeno/
├── Makefile                 # developer interface
├── docker-compose.yml       # profiles: infra, service
├── docker-compose.dev.yml   # dev mode: repos/ bind mounts
├── docker/
│   ├── Dockerfile.service   # python:3.12-slim + uv
│   └── entrypoint-dev.sh    # dev mode: sync + link local repos
├── .env.example
└── repos/                   # local clones (gitignored)
    ├── py/                  # entirius-py-* modules
    ├── django/              # entirius-django-* modules
    └── services/            # entirius-service-* services
```

## Commands

| Command | Description |
|---------|-------------|
| `make init` | Create `.env` from template + `repos/` layout |
| `make clone` | Clone the service under test into `repos/services/` |
| `make build` | Build the service image |
| `make up` | Start infra + service (baked image) |
| `make up-infra` | Start infrastructure only |
| `make dev` | Start with `repos/` mounted (hot reload) |
| `make link` | Re-link mounted module repos without restart |
| `make down` | Stop everything |
| `make logs` | Tail logs |
| `make status` | Container status |
| `make shell` | Bash into the service container |
| `make health` | Verify all services respond |
| `make migrate` | Apply service migrations |
| `make test` | Migration drift check + service test suite |
| `make clean` | Remove containers and volumes |

## Configuration (.env)

| Variable | Default | Meaning |
|----------|---------|---------|
| `SERVICE` | `entirius-service-volkanos` | Service repo to build and run |
| `SERVICE_BRANCH` | `master` | Branch baked into the image |
| `SERVICE_PORT` | `8000` | Host port for the service |
| `POSTGRES_*`, `REDIS_PORT`, `RABBITMQ_*` | dev defaults | Infrastructure credentials and ports |

The service reads its configuration from environment variables —
compose passes `DATABASE_URL` pointing at the `db` container, so the whole stack
(including the test suite) runs against PostgreSQL.

## Dev credentials

| Service | User | Password |
|---------|------|----------|
| PostgreSQL | entirius | entirius-dev |
| RabbitMQ | guest | guest |

Dev defaults only — override in `.env` for anything non-local.

## License

MPL-2.0
