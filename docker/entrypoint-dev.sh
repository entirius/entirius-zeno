#!/bin/sh
#
# Dev entrypoint — provisions zeno's settings_local, syncs deps and
# editable-installs mounted module repos before starting the service,
# so local code overrides locked versions.
#
set -e

if [ ! -f "${SERVICE_DIR}/pyproject.toml" ]; then
    echo "ERROR: ${SERVICE_DIR} is empty — run 'make clone' on the host first."
    exit 1
fi

# Zeno owns the per-environment config of the mounted clone. The settings read the recipes mount: a container
# created before that mount existed keeps the settings it has until `make dev` recreates it.
if [ -d /entirius/recipes ] || [ ! -f "${SERVICE_DIR}/main/settings_local.py" ]; then
    cp -f /entirius/docker/settings_local.py "${SERVICE_DIR}/main/settings_local.py"
else
    echo "WARNING: /entirius/recipes is not mounted - settings_local.py not refreshed; run 'make dev' on the host"
fi

cd "${SERVICE_DIR}"
uv sync --frozen

# uv sync is exact (drops previous editable links) — re-link after every sync
linked=0
# One module failing to build must not abort linking the rest (set -e is on).
for dir in /entirius/py/*/ /entirius/django/*/; do
    [ -f "${dir}pyproject.toml" ] || continue
    if uv pip install --no-deps --quiet -e "${dir}"; then
        linked=$((linked + 1))
    else
        echo "  link FAILED: ${dir}"
    fi
done
echo "=== Dev mode: ${linked} local module(s) linked ==="

exec "$@"
