#!/bin/sh
#
# Refreshes existing clones under repos/ to match the service under test:
# the service clone fast-forwards SERVICE_BRANCH, module clones check out the
# version tags pinned in the service uv.lock (detached HEAD, like clone-repos.sh).
# Dirty clones are skipped with a warning — local work is never touched.
# Complements clone-repos.sh, which leaves existing clones untouched.
#
# In dev mode restart the service afterwards - the entrypoint re-syncs the venv.
#
# Requires: git.
#
set -e

SERVICE="${1:-entirius-service-volkanos}"
BRANCH="${SERVICE_BRANCH:-master}"
LOCK="repos/services/${SERVICE}/uv.lock"

locked_version() {
    [ -f "$LOCK" ] || return 0
    awk -v pkg="$1" '
        $0 == "name = \"" pkg "\"" { found = 1; next }
        found && /^version = / { gsub(/"/, "", $3); print $3; exit }
    ' "$LOCK"
}

dirty() {
    [ -n "$(git -C "$1" status --porcelain)" ]
}

# Service first — module pinning below reads its (possibly updated) uv.lock
dir="repos/services/${SERVICE}"
if [ -d "${dir}/.git" ]; then
    if dirty "$dir"; then
        echo "  skip:  ${SERVICE} (dirty working tree)"
    else
        git -C "$dir" fetch --quiet --tags origin
        git -C "$dir" checkout --quiet "$BRANCH"
        git -C "$dir" pull --quiet --ff-only
        echo "  ok:    ${SERVICE} @ ${BRANCH} ($(git -C "$dir" rev-parse --short HEAD))"
    fi
else
    echo "  skip:  ${SERVICE} (not cloned — run 'make clone')"
fi

for dir in repos/py/*/ repos/django/*/; do
    [ -d "${dir}.git" ] || continue
    name=$(basename "$dir")
    if dirty "$dir"; then
        echo "  skip:  ${name} (dirty working tree)"
        continue
    fi
    version=$(locked_version "$name")
    if [ -z "$version" ]; then
        echo "  skip:  ${name} (not in service uv.lock)"
        continue
    fi
    current=$(git -C "$dir" describe --tags --exact-match 2>/dev/null || echo "")
    if [ "$current" = "v${version}" ]; then
        echo "  ok:    ${name} already @ v${version}"
        continue
    fi
    git -C "$dir" fetch --quiet --tags origin
    if git -C "$dir" rev-parse --verify --quiet "refs/tags/v${version}" >/dev/null; then
        git -C "$dir" checkout --quiet "v${version}"
        echo "  ok:    ${name} -> v${version}"
    else
        echo "  WARN:  ${name} — tag v${version} not found on origin"
    fi
done

echo "Done. Dev mode: restart the service so the entrypoint re-syncs the venv."
