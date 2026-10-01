#!/usr/bin/env bash
# release.sh <plan-id> <issue-id> — release a `ready` hotfix plan as the next CMS patch version (of the newest release).
# Deterministic, no model: version bump + CHANGELOG, gitleaks, push the hotfix branch (SSH), PR → master, green checks,
# merge, tag, GitHub release, PR → develop, Redmine note (To Deploy, assigned to the reporter). Stops at the first failure.
set -euo pipefail
PLAN=$1 ISSUE=$2
ZENO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE=$ZENO/scripts/hotfix-agent
W=$ZENO/repos/pwa/entirius-pwa-cms-hotfix
R=entirius/entirius-pwa-cms
SSH=git@github.com:$R.git
STATE=$ZENO/.runner/hotfix
ISSUE_DIR=$ZENO/todo/hotfix/issues/$ISSUE
BRANCH=hotfix/$PLAN
STATUS_TO_DEPLOY=33
log() { echo "[release $(date +%T)] $*"; }
field() { python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or '')" "$ISSUE_DIR/outcome.json" "$1"; }

# Waits for every check of a PR: 0 green, 1 red, 2 timeout. `gh pr checks` exits 8 while pending.
wait_checks() {
  local n=$1 end=$((SECONDS + 2400)) rc
  sleep 20
  while :; do
    rc=0; gh pr checks "$n" --repo "$R" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 0 ]] && return 0
    [[ $rc -ne 8 ]] && return 1
    [[ $SECONDS -gt $end ]] && return 2
    sleep 20
  done
}

cd "$W"
[[ $(git branch --show-current) == "$BRANCH" ]] || { log "worktree is not on $BRANCH"; exit 1; }
[[ -z $(git status --porcelain) ]] || { log "worktree dirty"; exit 1; }
git fetch -q origin --tags
git merge-base --is-ancestor origin/master HEAD || { log "origin/master moved past the branch base — rebase by hand"; exit 1; }

# The next patch of the newest final release (rc tags left out): 3.1.1 after 3.1.0 — never a patch of an older line.
last=$(git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
[[ $last =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { log "no release tag found"; exit 1; }
VERSION=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))
log "issue #$ISSUE → $VERSION"

npm version "$VERSION" --no-git-tag-version >/dev/null
python3 - "$VERSION" "$(field changelog_en)" "$ISSUE" <<'EOF'
import datetime, sys
version, line, issue = sys.argv[1:4]
path = "CHANGELOG.md"
text = open(path).read()
head = "## [Unreleased]\n"
assert text.count(head) == 1, "CHANGELOG needs one [Unreleased] heading"
entry = f"## [Unreleased]\n\n## [{version}] ({datetime.date.today().isoformat()})\n\n### Fixed\n\n- {line} (Redmine #{issue})\n"
open(path, "w").write(text.replace(head, entry, 1).replace(entry + "\n\n", entry + "\n", 1))
EOF
npm run test:unit >/dev/null
git add package.json package-lock.json CHANGELOG.md
git commit -q -m "#$ISSUE release: $VERSION"
gitleaks git --no-banner --exit-code 1 -c "$ZENO/.gitleaks.toml" --log-opts "origin/master..HEAD" . >/dev/null \
  || { log "gitleaks found something — stop"; exit 1; }

git push -q "$SSH" "$BRANCH:$BRANCH"
subject=$(python3 -c "import json; print(json.load(open('$ISSUE_DIR/issue.json'))['subject'])")
body=$(mktemp)
{ echo "Hotfix $VERSION for Redmine #$ISSUE — $subject"; echo; echo "$(field changelog_en)"; echo;
  echo "Cause: $(field cause_pl)"; echo "Fix: $(field fix_pl)"; } > "$body"
url=$(gh pr create --repo "$R" --base master --head "$BRANCH" --title "#$ISSUE hotfix $VERSION: $subject" --body-file "$body")
n=${url##*/}
log "PR $url"
wait_checks "$n" || { log "checks of #$n not green — stop (PR stays open)"; exit 1; }
gh pr merge "$n" --repo "$R" --merge --admin >/dev/null
git fetch -q origin
got=$(git show origin/master:package.json | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
[[ $got == "$VERSION" ]] || { log "origin/master has $got, not $VERSION — stop before tagging"; exit 1; }
git tag -a "v$VERSION" -m "v$VERSION" origin/master
git push -q "$SSH" "v$VERSION"
notes=$(mktemp)
awk -v v="$VERSION" 'index($0, "## [" v "]") == 1 {on=1; next} on && /^## \[/ {exit} on {print}' CHANGELOG.md > "$notes"
rel=$(gh release create "v$VERSION" --repo "$R" --verify-tag --title "v$VERSION" --notes-file "$notes")
echo "$(date +%F) $VERSION $ISSUE $rel" >> "$STATE/releases.log"
log "released $rel"

# back into develop (git flow hotfix): develop first merged into the branch. A conflict only in the version files keeps
# develop's version (it may already carry the next minor); CHANGELOG sections are put back newest first. Anything
# else is the operator's — the release already stands.
backnote="Scalenie do develop wymaga ręcznej uwagi."
if back_ready=$(
  git fetch -q origin develop
  if ! git merge --no-ff --no-commit origin/develop >/dev/null 2>&1; then
    conflicted=$(git diff --name-only --diff-filter=U | sort | tr '\n' ' ')
    [[ $conflicted == "package-lock.json package.json " ]] || { git merge --abort; echo "conflict: $conflicted"; exit 1; }
    git checkout --theirs package.json package-lock.json && git add package.json package-lock.json
  fi
  python3 - <<'PY'
import re
path = "CHANGELOG.md"
text = open(path).read()
head, sep, body = text.partition("## [Unreleased]\n")
parts = re.split(r"(?m)^(?=## \[\d+\.\d+\.\d+\])", body)
intro, sections = parts[0], parts[1:]
key = lambda s: tuple(int(x) for x in re.match(r"## \[(\d+)\.(\d+)\.(\d+)\]", s).groups())
fixed = [s if s.endswith("\n\n") else s.rstrip("\n") + "\n\n" for s in sorted(sections, key=key, reverse=True)]
open(path, "w").write(head + sep + intro + "".join(fixed).rstrip("\n") + "\n")
PY
  git add CHANGELOG.md
  if [[ -f $(git rev-parse --git-path MERGE_HEAD) ]] || ! git diff --cached --quiet; then
    git commit -q -m "#$ISSUE merge develop into $BRANCH (develop keeps its version)"
  fi
  npm run test:unit >/dev/null || { echo "unit tests red after merging develop"; exit 1; }
  git push -q "$SSH" "$BRANCH:$BRANCH"
); then
  back=$(gh pr create --repo "$R" --base develop --head "$BRANCH" --title "#$ISSUE merge hotfix $VERSION into develop" \
    --body "Hotfix $VERSION back into develop." 2>&1) || true
  bn=${back##*/}
  if [[ $bn =~ ^[0-9]+$ ]] && wait_checks "$bn" && gh pr merge "$bn" --repo "$R" --merge --admin >/dev/null 2>&1; then
    backnote="Scalone też do develop."
  else
    backnote="Scalenie do develop wymaga ręcznej uwagi: $back"
  fi
else
  backnote="Scalenie do develop wymaga ręcznej uwagi: $back_ready"
fi
log "back-merge: $backnote"

note=$(mktemp)
cat > "$note" <<EOF
Poprawione i wydane w CMS **$VERSION**: $rel

*Przyczyna:* $(field cause_pl)

*Co działa teraz:* $(field fix_pl)

$backnote Status *To Deploy* — wydanie na GitHubie to nie wdrożenie; po wdrożeniu proszę o sprawdzenie i zamknięcie.

_(agent poprawek CMS)_
EOF
python3 "$HERE/redmine.py" note "$ISSUE" "$note" --status "$STATUS_TO_DEPLOY" --assign author
touch "$ISSUE_DIR/.released"
notify-send -a "CMS hotfix" "CMS $VERSION wydany" "Redmine #$ISSUE: $subject" 2>/dev/null || true
log "done"
