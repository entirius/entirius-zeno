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

# Zeno owns the per-environment config of the mounted clone
cp -f /entirius/docker/settings_local.py "${SERVICE_DIR}/main/settings_local.py"

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
