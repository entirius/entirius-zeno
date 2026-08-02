#!/bin/sh
#
# Clones every entirius org repo into its repos/ group dir (py/, django/, services/).
# Default: every repo on `master` (latest stable). Existing clones are left untouched.
# Groups: py/ django/ services/ pwa/.
#
# CLONE_REF override (per run):
#   CLONE_REF=develop → integration mode: latest unreleased code (picks up module fixes)
#   CLONE_REF=lock    → reproducible: modules at the service uv.lock version tags
#   CLONE_REF=<ref>   → any branch/tag for every repo
# A developer can always `git switch` an individual module afterwards.
#
# Requires: gh (authenticated), git.
#
set -e

command -v gh >/dev/null 2>&1 || {
    echo "ERROR: gh not found - clone-repos needs it to list the org's repos."
    echo "Install and authenticate first: brew install gh && gh auth login"
    exit 1
}

SERVICE="${1:-entirius-service-volkanos}"
LOCK="repos/services/${SERVICE}/uv.lock"

locked_version() {
    [ -f "$LOCK" ] || return 0
    awk -v pkg="$1" '
        $0 == "name = \"" pkg "\"" { found = 1; next }
        found && /^version = / { gsub(/"/, "", $3); print $3; exit }
    ' "$LOCK"
}

# Service first — module pinning below reads its uv.lock
if [ ! -d "repos/services/${SERVICE}/.git" ]; then
    git clone --quiet "git@github.com:entirius/${SERVICE}.git" "repos/services/${SERVICE}"
    echo "  clone: ${SERVICE} (service under test)"
fi

# Captured before the loop — a failure inside `gh | while` would be masked by the pipe
# even under `set -e`, silently cloning nothing.
repos=$(gh repo list entirius --limit 200 --no-archived --json name -q '.[].name') || {
    echo "ERROR: 'gh repo list' failed - is gh authenticated? (gh auth status)"
    exit 1
}

echo "$repos" | sort | while read -r name; do
    case "$name" in
        entirius-zeno)      continue ;;
        entirius-py-*)      group=py ;;
        entirius-django-*)  group=django ;;
        entirius-service-*) group=services ;;
        entirius-pwa-*)     group=pwa ;;
        *)  echo "  skip:  ${name} (no repos/ group)"; continue ;;
    esac
    dir="repos/${group}/${name}"
    if [ -d "${dir}/.git" ]; then
        echo "  skip:  ${name} (already cloned)"
        continue
    fi
    mkdir -p "repos/${group}"
    if ! git clone --quiet "git@github.com:entirius/${name}.git" "$dir"; then
        echo "  FAIL:  ${name}"
        continue
    fi
    if [ "$CLONE_REF" = "lock" ]; then
        version=$(locked_version "$name")
        if [ -n "$version" ] && git -C "$dir" checkout --quiet "v${version}" 2>/dev/null; then
            echo "  clone: ${name} @ v${version} (service lock)"; continue
        fi
    elif [ -n "$CLONE_REF" ]; then
        if git -C "$dir" checkout --quiet "$CLONE_REF" 2>/dev/null; then
            echo "  clone: ${name} @ ${CLONE_REF}"; continue
        fi
    fi
    # default: master (stable) — fall back to the repo's default branch if absent
    if git -C "$dir" checkout --quiet master 2>/dev/null; then
        echo "  clone: ${name} @ master"
    else
        echo "  clone: ${name} @ $(git -C "$dir" branch --show-current)"
    fi
done
