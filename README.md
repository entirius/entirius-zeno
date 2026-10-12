# entirius-zeno

entirius-zeno runs Entirius, the open-source modular ecommerce platform, on one machine with Docker, seeded with a
demo shop. It is a test and development harness: compose files, a Makefile and Dockerfiles. The application code comes
from the platform repositories on GitHub.

## What it does

- Builds the backend, the storefront and the admin CMS from their GitHub repositories over https: no SSH key, no `gh`.
- Starts the backend with PostgreSQL, Redis, RabbitMQ, a Celery worker and beat, and a mail sandbox that catches
  every mail the stack sends.
- Seeds the Słoik Chwil demo shop from the test package `entirius-test-package-1` and runs its BDD and Playwright suites against the live stack.
- Runs a developer stack that mounts local clones of the service and its modules, with hot reload.
- Prints the URL and port of every running service, read from the live containers.

## Installation

Install the tools listed under Requirements, then clone the harness:

```bash
git clone https://github.com/entirius/entirius-zeno.git
cd entirius-zeno
```

## Quick start

```bash
make setup
```

`make setup` checks the prerequisites, clones the test package, builds the service image, starts the stack, the mail
sandbox and both frontends, checks the AI toolbox, seeds the database and prints the URLs and logins:

| What | URL | Login |
|---|---|---|
| Backend API, Django admin (`/admin/`), Swagger UI (`/api/schema/swagger-ui/`) | http://localhost:8100/ | `admin` / `admin123` |
| Storefront | http://localhost:3100/ | — |
| Admin CMS | http://localhost:8180/ | `admin` / `admin123` |
| Zeno Suite dashboard | http://localhost:8200/ | — |
| Mail sandbox (REST) | http://localhost:8380/ | `sandbox` / `sandbox` |

Options, combinable:

- `make setup DEV=1`: the developer stack: clones every platform repo, mounts the clones, serves the CMS with hot
  reload (`REFS=release`, `REFS=develop` or `REFS="<feature branches>"`).
- `make setup SEED=0`: stop before seeding.
- `make setup EMBED=1`: also start the image-embedding service for product lookup.
- `python3 scripts/setup.py --dry-run`: print the steps and change nothing.

The AI toolbox runs outside the harness and is switched off by default (`AI_TOOLBOX_ENABLED=0` in `.env.example`):
`make setup` reports it as disabled, AI drafts and translations are refused, and `make bdd` skips the scenarios
tagged `@needs-toolbox`. With the toolbox enabled but not answering, `make setup` reports DEGRADED mode and seeds
anyway. The access gate runs in dev mode until access ships in
the service lock.

## Requirements

- Docker with Compose v2, git, GNU make, Python 3, curl and bash.
- `uv` on the host for `make bdd` and `make e2e`.
- `gh`, authenticated, for `make clone-repos` (developer stack only).
- Free host ports: the standard ones shifted by +100 (PostgreSQL 5532, Redis 6479, RabbitMQ 5772, backend 8100), so
  local instances on the standard ports keep running. Override them in `.env`.

## Documentation

- [Testing the platform: first run, seeding, BDD and e2e](https://github.com/entirius/entirius-zeno/blob/develop/doc/howto-test.md)
- [Developing with the harness: dev mode, commands, configuration](https://github.com/entirius/entirius-zeno/blob/develop/doc/howto-develop.md)
- [All guides](https://github.com/entirius/entirius-zeno/tree/develop/doc)
- [Entirius documentation](https://docs.entirius.com/)

## Part of Entirius

The harness runs the backend service with the test package's demo data, and the two frontends next to it:
[entirius-service-volkanos](https://github.com/entirius/entirius-service-volkanos) ·
`entirius-test-package-1` (not public yet) ·
[entirius-pwa-cms](https://github.com/entirius/entirius-pwa-cms) ·
[entirius-pwa-storefront](https://github.com/entirius/entirius-pwa-storefront)

## Development

```bash
make clone clone-tests  # the service under test and the test package into repos/
make clone-repos        # every platform repo, modules pinned to the service lock
make build              # the service image (dev mode mounts the clones over it)
make dev                # the stack with repos/ mounted: Django reloads on save
make link               # link module clones added while the stack runs
```

`make check` verifies the gitleaks configuration link; `make test` runs the service test suite against PostgreSQL.
Agent and contributor conventions: [AGENTS.md](https://github.com/entirius/entirius-zeno/blob/develop/AGENTS.md).
Dev mode in detail: [doc/howto-develop.md](https://github.com/entirius/entirius-zeno/blob/develop/doc/howto-develop.md).

## License

MPL-2.0 — see [LICENSE](https://github.com/entirius/entirius-zeno/blob/develop/LICENSE).
