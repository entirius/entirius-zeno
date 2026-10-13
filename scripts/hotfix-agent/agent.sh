#!/usr/bin/env bash
# CMS hotfix agent: cms-blueprint Redmine issues → dev-runner hotfix plan → patch release (release.sh).
#   agent.sh          loop: one tick every POLL_S (default 600) until .runner/hotfix/STOP exists
#   agent.sh --once   one tick
# One issue at a time; limits: MAX_RELEASES_PER_DAY (3), the runner's per-plan budget (the plan's BUDGET_USD) and
# DAILY_CAP_USD (runner.env). Everything a human should see goes to Redmine and to notify-send.
set -uo pipefail
ZENO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE=$ZENO/scripts/hotfix-agent
STATE=$ZENO/.runner/hotfix
PLANS=$ZENO/todo/hotfix/dev-plans
ISSUES=$ZENO/todo/hotfix/issues
CMS=$ZENO/repos/pwa/entirius-pwa-cms
W=$ZENO/repos/pwa/entirius-pwa-cms-hotfix
POLL_S=${POLL_S:-600}
MAX_RELEASES_PER_DAY=${MAX_RELEASES_PER_DAY:-3}
STATUS_IN_PROGRESS=2 STATUS_TODO=1
mkdir -p "$STATE" "$PLANS" "$ISSUES"
log() { echo "[agent $(date '+%F %T')] $*" | tee -a "$STATE/agent.log"; }
rm_py() { python3 "$HERE/redmine.py" "$@"; }
# After our own note the stored copy is refreshed, so only a later change by someone else re-triggers the issue.
refresh() { rm_py fetch "$1" "$ISSUES/$1" >/dev/null 2>&1 || true; }
header() { grep -m1 "^$2:" "$1" | sed "s/^$2: *//"; }
notify() { notify-send -a "CMS hotfix" "$1" "$2" 2>/dev/null || true; }

run_runner() {
  ENV_FILE=$HERE/runner.env "$ZENO/scripts/dev-runner/runner.sh" --once --plans "$PLANS" >>"$STATE/runner.log" 2>&1
}

# The worktree follows origin/master between issues; npm ci only when the lockfile changed.
prepare_worktree() {
  git -C "$CMS" fetch -q origin --tags || return 1
  [[ -e $W/.git ]] || git -C "$CMS" worktree add -q --detach "$W" origin/master || return 1
  [[ -z $(git -C "$W" status --porcelain) ]] || { log "hotfix worktree dirty — operator"; return 1; }
  git -C "$W" checkout -q --detach origin/master || return 1
  local h; h=$(sha256sum "$W/package-lock.json" | cut -c1-16)
  if [[ $(cat "$W/node_modules/.hotfix-lock" 2>/dev/null) != "$h" ]]; then
    (cd "$W" && npm ci --no-audit --no-fund >/dev/null 2>&1) || return 1
    echo "$h" > "$W/node_modules/.hotfix-lock"
  fi
}

# The main runner's push guard lives in the hooks dir the hotfix worktree shares; a ready hotfix waits until it is gone
# (the hotfix plan's own marker, stream 9, is removed when its claim ends).
cms_push_held() { compgen -G "$(git -C "$CMS" rev-parse --path-format=absolute --git-path hooks)/pre-push.runner-s*" >/dev/null; }

releases_today() { local n; n=$(grep -c "^$(date +%F) " "$STATE/releases.log" 2>/dev/null) || true; echo "${n:-0}"; }

# Plan id for an issue: the issue id, then <id>r2, <id>r3 … when the reporter answered and it came back.
next_plan_id() {
  local issue=$1 n=1 id=$1
  while [[ -e $PLANS/$id-hotfix.md ]]; do n=$((n + 1)); id=${issue}r$n; done
  echo "$id"
}

take() {
  local issue=$1 plan dir subj author desc
  dir=$ISSUES/$issue
  rm_py fetch "$issue" "$dir" >/dev/null || { log "#$issue: fetch failed"; return 1; }
  prepare_worktree || { log "#$issue: worktree not ready"; return 1; }
  plan=$(next_plan_id "$issue")
  rm -f "$dir/outcome.json" "$dir/.released" "$dir/.reported"
  subj=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['subject'])" "$dir/issue.json")
  author=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['author']['name'])" "$dir/issue.json")
  desc=$(python3 -c "import json,sys; print((json.load(open(sys.argv[1])).get('description') or '').replace('\n', ' ')[:600])" "$dir/issue.json")
  python3 - "$HERE/plan.template.md" "$PLANS/$plan-hotfix.md" "$plan" "$issue" "$subj" "$author" "$desc" <<'EOF'
import sys
src, dst, plan, issue, subj, author, desc = sys.argv[1:8]
text = open(src).read()
for key, val in {"@PLAN@": plan, "@ISSUE@": issue, "@SUBJECT@": subj, "@AUTHOR@": author, "@DESCRIPTION@": desc}.items():
    text = text.replace(key, val)
open(dst, "w").write(text)
EOF
  printf '| %s | #%s %s | to-dev |\n' "$plan" "$issue" "$subj" >> "$PLANS/00-README.md"
  echo "$plan" > "$dir/.plan"
  local note; note=$(mktemp)
  printf 'Agent poprawek CMS przejął zgłoszenie: analiza, odtworzenie i poprawka na gałęzi hotfix/%s. Wynik (wydanie albo pytania) pojawi się tutaj.\n' "$plan" > "$note"
  rm_py note "$issue" "$note" --status "$STATUS_IN_PROGRESS" --assign me
  refresh "$issue"
  log "#$issue taken as plan $plan: $subj"
}

# After a runner tick: ready → release; parked → tell the reporter (or the operator).
post_process() {
  local f plan issue st dir outcome note
  for f in "$PLANS"/[0-9]*-hotfix.md; do
    [[ -f $f ]] || continue
    plan=$(basename "$f" -hotfix.md); issue=${plan%%r*}; dir=$ISSUES/$issue; st=$(header "$f" STATUS)
    if [[ $st == ready && ! -e $dir/.released && ! -e $dir/.release-failed ]]; then
      if (( $(releases_today) >= MAX_RELEASES_PER_DAY )); then log "#$issue ready — daily release cap reached, waits"; continue; fi
      if cms_push_held; then log "#$issue ready — the main runner holds the CMS clone, release waits"; continue; fi
      if "$HERE/release.sh" "$plan" "$issue" >>"$STATE/release.log" 2>&1; then
        log "#$issue released ($(tail -1 "$STATE/releases.log"))"
      else
        touch "$dir/.release-failed"
        note=$(mktemp)
        printf 'Poprawka jest gotowa (gałąź hotfix/%s), ale wydanie zatrzymało się — potrzebny człowiek. Log: .runner/hotfix/release.log w zeno.\n' "$plan" > "$note"
        rm_py note "$issue" "$note" --assign me; refresh "$issue"
        notify "CMS hotfix: wydanie zatrzymane" "Redmine #$issue — sprawdź release.log"
        log "#$issue release failed — operator"
      fi
    elif [[ $st == parked && ! -e $dir/.reported ]]; then
      outcome=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('outcome',''))" "$dir/outcome.json" 2>/dev/null || true)
      note=$(mktemp)
      case $outcome in
        needs-info|not-cms|cannot-reproduce)
          python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('note_pl',''))" "$dir/outcome.json" > "$note"
          printf '\n_(agent poprawek CMS — wynik: %s)_\n' "$outcome" >> "$note"
          rm_py note "$issue" "$note" --status "$STATUS_TODO" --assign author; refresh "$issue"
          notify "CMS hotfix: pytanie w #$issue" "$outcome"
          log "#$issue parked with $outcome — asked the reporter" ;;
        *)
          printf 'Agent poprawek CMS nie doprowadził zgłoszenia do wydania (plan %s zaparkowany) — przekazuję człowiekowi.\n' "$plan" > "$note"
          rm_py note "$issue" "$note" --status "$STATUS_TODO" --assign me; refresh "$issue"
          notify "CMS hotfix: zgłoszenie #$issue wymaga człowieka" "plan $plan parked"
          log "#$issue parked without an outcome — operator" ;;
      esac
      touch "$dir/.reported"
    fi
  done
}

active_plan() {
  local f st
  for f in "$PLANS"/[0-9]*-hotfix.md; do
    [[ -f $f ]] || continue
    st=$(header "$f" STATUS); [[ $st == to-dev || $st == in-dev ]] && { echo "$f"; return; }
  done
}

# An issue is taken again only when it is a candidate and changed after our last plan for it.
fresh_candidate() {
  local id dir
  for id in $(rm_py candidates 2>/dev/null); do
    dir=$ISSUES/$id
    if [[ ! -e $dir/.plan ]]; then echo "$id"; return; fi
    python3 - "$dir/issue.json" "$id" "$HERE" "$STATE" <<'EOF' && { echo "$id"; return; }
import json, subprocess, sys
old = json.load(open(sys.argv[1]))["updated_on"]
new = subprocess.run([sys.executable, sys.argv[3] + "/redmine.py", "fetch", sys.argv[2], sys.argv[4] + "/peek-" + sys.argv[2]],
                     capture_output=True, text=True)
cur = json.load(open(sys.argv[4] + "/peek-" + sys.argv[2] + "/issue.json"))["updated_on"]
sys.exit(0 if cur > old else 1)
EOF
  done
}

tick() {
  [[ -e $STATE/STOP ]] && { log "STOP present"; exit 0; }
  post_process
  if [[ -z $(active_plan) ]]; then
    local id; id=$(fresh_candidate)
    [[ -n $id ]] || return 0
    take "$id" || return 0
  fi
  run_runner
  post_process
}

[[ -f $PLANS/00-README.md ]] || printf '# CMS hotfix plans (generated by scripts/hotfix-agent)\n\n| Plan | Issue | Status |\n|---|---|---|\n' > "$PLANS/00-README.md"
exec 9>"$STATE/agent.lock"
flock -n 9 || { echo "another hotfix agent is running"; exit 1; }
if [[ ${1:-} == --once ]]; then tick; exit 0; fi
log "loop start (poll ${POLL_S}s)"
while :; do tick; sleep "$POLL_S"; done
