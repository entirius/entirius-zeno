#!/usr/bin/env bash
# Merge own fix branches straight into develop (operator 2026-11-04: no PRs between releases).
#   merge-direct.sh <clone> <owner/repo> "<one-line summary>" <branch> [<branch> ...]
# Per branch: worktree from origin/develop, merge --no-ff (CHANGELOG-only conflict joined by section, any other stops),
# module suite when develop moved past the branch's base, push HEAD:develop over https, verify origin/develop.
set -euo pipefail
export ZENO_PR_REVIEW="$(cd "$(dirname "$0")" && pwd)"
clone=$1 repo=$2 summary=$3; shift 3
W=~/.cache/pr-review/direct/$(basename "$repo")
for branch in "$@"; do
  git -C "$clone" fetch -q origin
  git -C "$clone" worktree remove --force "$W" 2>/dev/null || true
  git -C "$clone" worktree add -q --detach "$W" origin/develop
  cd "$W"
  if ! git -c user.name=klo-chi -c user.email=klo-chi@entirius.com merge -q --no-ff "$branch" \
       -m "Merge branch '$branch' into develop" -m "$summary"; then
    conflicted=$(git diff --name-only --diff-filter=U)
    [ "$conflicted" = "CHANGELOG.md" ] || { echo "STOP $branch: conflict in $conflicted (worktree $W)"; exit 1; }
    python3 - <<'EOF'
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("mt", pathlib.Path(__import__("os").environ["ZENO_PR_REVIEW"]) / "merge-train.py")
mt = importlib.util.module_from_spec(spec); spec.loader.exec_module(mt)
mt.join_changelog(pathlib.Path("CHANGELOG.md"))
EOF
    grep -q '^<<<<<<<\|^>>>>>>>' CHANGELOG.md && { echo "STOP $branch: CHANGELOG join left markers"; exit 1; }
    git add CHANGELOG.md
    git -c user.name=klo-chi -c user.email=klo-chi@entirius.com commit -q --no-edit
  fi
  if git -C "$clone" merge-base --is-ancestor origin/develop "$branch"; then
    echo "$branch: on top of develop, merged tree = branch tree (suite ran on the branch)"
  else
    echo "$branch: develop moved, running the suite on the merge"
    uv sync -q --all-extras
    DATABASE_URL=${DATABASE_URL:-postgres://entirius:entirius-dev@localhost:5532/zr_direct} .venv/bin/pytest -q -x | tail -3
  fi
  git push -q "${PUSH_URL:-https://github.com/$repo.git}" HEAD:develop 2>&1 | grep -i "error\|rejected" || true
  git fetch -q origin
  [ "$(git rev-parse origin/develop)" = "$(git rev-parse HEAD)" ] || { echo "STOP $branch: origin/develop != pushed"; exit 1; }
  echo "$repo develop = $(git rev-parse --short HEAD) ($branch)"
  cd "$clone"
  git worktree remove --force "$W"
done
