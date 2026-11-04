#!/usr/bin/env bash
# Release one Python package (Handbook releases.md), operator "tak" 2026-11-04.
#   release-module.sh <clone> <owner/repo> <version> [<dist> for PyPI check]
# chore: release on develop -> PR develop->master (merge --admin) -> tag -> gh release -> publish.yml -> PyPI.
set -euo pipefail
clone=$1 repo=$2 V=$3 dist=${4:-$(basename "$repo")}
D=$(date +%F) W=~/.cache/pr-review/release/$(basename "$repo") N=~/.cache/pr-review/release/notes-$(basename "$repo").md
mkdir -p ~/.cache/pr-review/release
git -C "$clone" fetch -q origin
git -C "$clone" worktree remove --force "$W" 2>/dev/null || true
git -C "$clone" worktree add -q --detach "$W" origin/develop
cd "$W"
grep -q '^## Unreleased' CHANGELOG.md || { echo "STOP: no ## Unreleased"; exit 1; }
sed -i "0,/^version = \".*\"/s//version = \"$V\"/" pyproject.toml
sed -i "0,/^## Unreleased.*/s//## $V — $D/" CHANGELOG.md
awk -v h="## $V — $D" '$0==h{f=1;next} f&&/^## /{exit} f' CHANGELOG.md > "$N"
[ -s "$N" ] || { echo "STOP: empty notes"; exit 1; }
uv lock -q
uv sync -q --all-extras
DATABASE_URL=${DATABASE_URL:-postgres://entirius:entirius-dev@localhost:5532/zr_release} .venv/bin/pytest -q -x 2>&1 | tail -1
git add pyproject.toml CHANGELOG.md uv.lock
git -c user.name=klo-chi -c user.email=klo-chi@entirius.com commit -q -m "chore: release $V"
git push -q "https://github.com/$repo.git" HEAD:develop 2>&1 | grep -i "error\|rejected" && exit 1 || true
pr=$(gh pr create -R "$repo" --base master --head develop --title "release: $V" --body-file "$N" | grep -o '[0-9]*$')
echo "PR #$pr"
sleep 30
for i in $(seq 60); do
  rc=0; gh pr checks "$pr" -R "$repo" >/dev/null 2>&1 || rc=$?
  c=$(gh pr checks "$pr" -R "$repo" 2>/dev/null || true)
  [ $rc -eq 0 ] && echo "$c" | grep -qP "^lint\tpass" && echo "$c" | grep -qP "^test\tpass" && break
  [ $rc -eq 0 ] || [ $rc -eq 8 ] || { echo "STOP: checks red on #$pr"; exit 1; }; sleep 20
done
{ c=$(gh pr checks "$pr" -R "$repo"); echo "$c" | grep -qP "^lint\tpass" && echo "$c" | grep -qP "^test\tpass"; } || { echo "STOP: lint/test missing on #$pr"; exit 1; }
for i in 1 2 3 4; do
  [ "$(gh pr view "$pr" -R "$repo" --json state -q .state)" = MERGED ] && break
  gh pr merge "$pr" -R "$repo" --merge --admin >/dev/null 2>&1 || sleep 20
done
[ "$(gh pr view "$pr" -R "$repo" --json state -q .state)" = MERGED ] || { echo "STOP: #$pr not merged"; exit 1; }
git fetch -q origin
git show origin/master:pyproject.toml | grep -q "^version = \"$V\"" || { echo "STOP: master version"; exit 1; }
git tag -a "v$V" -m "v$V" origin/master
git push -q "https://github.com/$repo.git" "v$V"
gh release create "v$V" -R "$repo" --verify-tag --title "v$V" --notes-file "$N" >/dev/null
echo "released v$V, waiting for PyPI $dist"
for i in $(seq 40); do
  [ "$(curl -s "https://pypi.org/pypi/$dist/json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null)" = "$V" ] && { echo "PyPI $dist $V"; break; }
  sleep 15
done
cd "$clone"; git worktree remove --force "$W"
