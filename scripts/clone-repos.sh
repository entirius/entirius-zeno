#!/bin/sh
#
# Clones every entirius org repo into its repos/ group dir (py/, django/, services/).
# Modules pinned in the service uv.lock are checked out at the locked version tag
# (detached HEAD — branch off in the module to develop it); everything else stays
# on the default branch. Existing clones are left untouched.
#
# Requires: gh (authenticated), git.
#
set -e

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
    git clone --quiet "https://github.com/entirius/${SERVICE}.git" "repos/services/${SERVICE}"
    echo "  clone: ${SERVICE} (service under test)"
fi

gh repo list entirius --limit 200 --no-archived --json name -q '.[].name' | sort | while read -r name; do
    case "$name" in
        entirius-zeno)      continue ;;
        entirius-py-*)      group=py ;;
        entirius-django-*)  group=django ;;
        entirius-service-*) group=services ;;
        *)  echo "  skip:  ${name} (no repos/ group)"; continue ;;
    esac
    dir="repos/${group}/${name}"
    if [ -d "${dir}/.git" ]; then
        echo "  skip:  ${name} (already cloned)"
        continue
    fi
    mkdir -p "repos/${group}"
    if ! git clone --quiet "https://github.com/entirius/${name}.git" "$dir"; then
        echo "  FAIL:  ${name}"
        continue
    fi
    version=$(locked_version "$name")
    if [ -n "$version" ] && git -C "$dir" checkout --quiet "v${version}" 2>/dev/null; then
        echo "  clone: ${name} @ v${version} (service lock)"
    else
        echo "  clone: ${name} @ $(git -C "$dir" branch --show-current)"
    fi
done
