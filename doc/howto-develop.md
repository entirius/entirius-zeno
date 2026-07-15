# How to develop with zeno

This guide is for **changing code**: modules (`entirius-django-*`, `entirius-py-*`)
or the service itself, with the full stack running around it.
Just verifying the platform: [howto-test.md](howto-test.md).
Command reference: [README](../README.md).

## Dev mode (hot reload)

```bash
make clone          # service under test -> repos/services/
make clone-repos    # or: every module repo, pinned to the service uv.lock versions
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

Typical loop: edit → save (auto-reload) → `make bdd TAGS=@pim-admin` → before pushing,
the canonical `make seed && make bdd`.

## Caveats

- **The celery worker runs the baked image**, not your mounted clones. Module changes
  that affect tasks (QMS quantities, thumbnails, pricelists) need `make build`, or an
  ad-hoc worker inside the service container:

  ```bash
  docker compose exec -d service celery -A main worker \
    -Q celery,quantities,fill_product_representation,pricemanager_create_pricelist
  ```

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
| Module change has no effect | clone not linked — `make link`; task-side code — see the worker caveat |
| `ModuleNotFoundError` after switching branches | version drift between clones — `make refresh-repos`, restart |
| Migration drift in `make test` | your model change needs a migration — `makemigrations` in the module |
| Stack wedged beyond repair | `make clean` (drops volumes) → `make up` → `make seed` |
