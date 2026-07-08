#!/bin/sh
#
# Dev entrypoint — syncs deps and editable-installs mounted module repos
# before starting the service, so local code overrides locked versions.
#
set -e

if [ ! -f "${SERVICE_DIR}/pyproject.toml" ]; then
    echo "ERROR: ${SERVICE_DIR} is empty — run 'make clone' on the host first."
    exit 1
fi

cd "${SERVICE_DIR}"
uv sync --frozen

# uv sync is exact (drops previous editable links) — re-link after every sync
linked=0
for dir in /entirius/py/*/ /entirius/django/*/; do
    [ -f "${dir}pyproject.toml" ] || continue
    uv pip install --no-deps --quiet -e "${dir}"
    echo "  linked: ${dir}"
    linked=$((linked + 1))
done
echo "=== Dev mode: ${linked} local module(s) linked ==="

exec "$@"
