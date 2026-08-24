## Engineering standards (entirius) — apply to every code change

1. **The repo's `AGENTS.md`/`CLAUDE.md` wins** over general rules when they collide. Read it first.
2. **English only** in every entirius repo: code, docstrings, commits, docs.
3. **Python toolchain**: deps only in `pyproject.toml` (never `requirements.txt`/`setup.py`); `uv`, never bare
   `pip install`; lint/format = `ruff`; type hints on public functions; built-in generics and `X | None`.
4. **Task runner**: when the repo has a `Makefile`, use its canon (`make check`, `make test`, `make fix`).
5. **Django modules**: layered layout (models / schemas / services / api), `django_utils.BaseModel`, API v2 +
   Pydantic (no DRF serializers), `IsAdminUser` on admin endpoints, throttle public endpoints, field whitelist
   in services, no `str(e)` in 500 responses. Rules: `~/.claude/rules/entirius-backend/` (loaded by the plugins).
6. **Git**: Conventional Commits; the runner prepared the branch — never create/switch branches, never push;
   `master`/`main`/`develop` are untouchable.
7. **Secrets — zero tolerance**: no keys, tokens, passwords or client names in code, tests, fixtures, commits.
   Every commit is scanned (gitleaks) — a secret parks the plan.
8. **Licence**: keep MPL-2.0 headers; new files in a repo that uses headers get the same header (pre-commit
   `insert-license` adds them — run it).
9. **No generated artefacts** in commits (`__pycache__`, caches, build, `node_modules`); `uv.lock` IS committed.
10. **Harness**: `make dev` only (never `make up`); `docker compose logs service` is the truth; BDD gates need a
    fresh `make seed`; restart `worker` after Celery task changes; edit `docker/settings_local.py`, never the clone's.
