# How to test the platform with zeno

Zeno runs a full Entirius/Volkanos service with its infrastructure and hands you one
interface — `make`. This is the task-oriented walkthrough; command reference lives
in the [README](../README.md).

## I want to see the platform working (5 commands)

```bash
make init      # .env + repos/ layout
make build     # bake the service image (clones SERVICE@SERVICE_BRANCH from GitHub)
make up        # postgres + redis + rabbitmq + service + celery worker + fixtures http
make clone-tests
make seed      # Emporium demo dataset: products, prices, stock, discounts (~25 min)
```

Then look around:

| What | Where |
|---|---|
| Admin panel | http://localhost:8100/admin/ — `admin` / `admin123` |
| Swagger UI | http://localhost:8100/api/schema/swagger-ui/ |
| Products API | http://localhost:8100/api/matrix/v2/default-europe/products/?page_size=100 |
| A cart with a discount | POST `/api/checkout/1/default-europe/carts/` with header `X-API-KEY: entirius-docker-checkout-dev-key-2026` |

The seed prints step timers (`[65s] Step 2: Load Fixtures`) and ends with `SEED OK in Ns` —
if it dies it names the failed step (`SEED FAILED (exit N) during: ...`).

## I want to run the test suite

```bash
make bdd                      # ~590 behave scenarios over HTTP (~5 min)
make bdd TAGS=@matrix-v2      # one area only
make bdd TAGS=@checkout       # tag list: repos/tests/*/README.md
```

The suite is a black-box API consumer: it reads expectations from the dataset's CSV files,
so it verifies whatever the package actually seeded — no hardcoded values.

Two tags are excluded by default (see the test repo README):
`@spec-first` (scenarios written ahead of their module) and `@blocked-by-module`
(known module gaps, tracked internally).

**Fresh measurement = fresh database.** Some suites assume seed-order state
(e.g. supplier fixtures at fixed primary keys). The canonical gate run is always:

```bash
make seed
make bdd
```

## I want to develop a module or the service

```bash
make clone          # service under test -> repos/services/
make clone-repos    # or: every module repo, pinned to the service uv.lock versions
make dev            # containers with repos/ bind-mounted — Django reloads on save
```

Work on a branch inside the module clone; the container imports your local code
(editable installs). Added a clone while running? `make link`. Details: README
“Two modes” and “Dev workflow”.

Caveats worth knowing:

- **The celery worker runs the baked image** — module changes that affect tasks
  (QMS quantities, thumbnails, pricelists) need `make build` or an ad-hoc worker inside
  the service container:
  `docker compose exec -d service celery -A main worker -Q celery,quantities,fill_product_representation,pricemanager_create_pricelist`
- `make test` (service unit tests + migration drift) runs against postgres, not sqlite.
- `make smoke` is the 30-second boot proof: migrations, system check, HTTP, admin login.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `make seed` fails at the celery check | worker not up — `docker compose ps worker`, or start ad-hoc (see above) |
| Products have no stock/prices in carts | QMS chain didn't settle — check worker logs; reseed if in doubt |
| Feed download scenarios fail with “Internal host blocked” | dev-only `SUPPLIER_BLOCK_PRIVATE_HOSTS = False` missing from `docker/settings_local.py` |
| Suite red after incremental reruns | state drift — run the canonical `make seed && make bdd` |
| `make build` seems to ignore new commits | it doesn't (clone layer cache-busts on branch HEAD) — but check `SERVICE_BRANCH` in `.env` |
| Stack wedged beyond repair | `make clean` (drops volumes) → `make up` → `make seed` |

## What the Emporium dataset gives you

Two channels (`default-local` USD, `default-europe` EUR/PLN), 35 products
(simple / configurable / bundle / custom, incl. slash-SKU edge cases), nested categories,
attributes and PIM feature sets, prices + omnibus history, stock via QMS, 10 discount
rules, demo suppliers with an HTTP feed, accounts groups, CMS content.
Dataset details: `repos/tests/entirius-test-package-emporium/package/README.md`.
