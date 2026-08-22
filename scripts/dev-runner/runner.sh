#!/usr/bin/env bash
# dev-runner — executes dev-plans one per tick.
# pick plan → claim (STATUS: in-dev) → coder → GATE (script) → green: reviewer → ready
#                                                            → red: triage → retry (steer) | parked
# State: STATUS: lines in the plans folder + .runner/handoff/<topic>-<id>/attempt-N/. One run at a time (flock).
set -euo pipefail
RUNNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$RUNNER_DIR/lib.sh"
# shellcheck source=checkpoint.sh
source "$RUNNER_DIR/checkpoint.sh"

usage() { echo "usage: runner.sh --once --plans <dir> [--dry-run]" >&2; exit 2; }

main() {
  local once=0
  while (($#)); do
    case $1 in
      --once) once=1 ;;
      --dry-run) DRY=1 ;;
      --plans) PLANS_DIR=$2; shift ;;
      *) usage ;;
    esac
    shift
  done
  [[ $once == 1 ]] || usage
  load_env
  [[ -f $STOP_FILE ]] && { log "STOP file present — not starting (remove $STOP_FILE to resume)"; exit 0; }
  cli_pin_ok || exit 1
  daily_cap_ok || exit 0
  acquire_lock || { log "another run holds the lock — exiting (OK)"; exit 0; }
  PLAN_SRC=$(pick_plan) || { log "no actionable plan — sleeping"; exit 0; }
  PLAN_ID=$(plan_id "$PLAN_SRC")
  TOPIC=$(basename "$(dirname "$PLANS_DIR")")   # handoff is keyed per topic: plan 01 exists in every topic
  HAND=$HANDOFF_DIR/$TOPIC-$PLAN_ID
  log "picked: plan $PLAN_ID ($(basename "$PLAN_SRC")) dry=$DRY"
  process_plan
}

# The plan is agent-readable AND agent-writable (todo/ is gitignored): headers and the gate are read from
# a snapshot taken at claim ($PLAN_FILE), and the live file must hash the same before `ready`.
process_plan() {
  local st; st=$(plan_header "$PLAN_SRC" STATUS)
  [[ $st == in-dev ]] && log "stale claim — resuming after crash"
  if [[ $DRY == 1 ]]; then log "DRY-RUN: stop before work (next: claim → coder → gate → reviewer/triage)"; return 0; fi
  [[ $st == in-dev ]] || { rm -rf "$HAND"; plan_set_status "$PLAN_SRC" in-dev; }
  mkdir -p "$HAND"
  [[ -f $HAND/plan.md ]] || { cp "$PLAN_SRC" "$HAND/plan.md"; sha256sum "$PLAN_SRC" | cut -d' ' -f1 > "$HAND/plan.sha"; }
  PLAN_FILE=$HAND/plan.md
  local why; why=$(plan_lint "$PLAN_FILE") || { escalate "invalid header: $why"; return 0; }
  claim_repos || return 0
  trap release_repos EXIT INT TERM
  local cap; cap=$(plan_header "$PLAN_FILE" BUDGET_USD); PLAN_CAP_USD=${cap:-$CODER_CAP_USD}
  local tmo; tmo=$(plan_header "$PLAN_FILE" TIMEOUT_S); [[ -n $tmo ]] && ROLE_TIMEOUT=$tmo
  if [[ $(plan_header "$PLAN_FILE" KIND) == checkpoint ]]; then run_checkpoint; else attempt_loop; fi
}

plan_unchanged() { [[ $(sha256sum "$PLAN_SRC" | cut -d' ' -f1) == $(cat "$HAND/plan.sha") ]]; }

# Branches in every REPOS: repo; dirty tree = operator work → escalate, never stash.
# On resume a dirty tree is tolerated only when the repo already sits on BRANCH (a crashed coder's
# leftovers) — a branch switch never carries uncommitted changes. Zeno itself (`.`) is never switched:
# bash reads the running scripts by offset, so the runner must already be on BRANCH there.
claim_repos() {
  local r dir br cur; br=$(plan_header "$PLAN_FILE" BRANCH)
  [[ -n $br ]] || { escalate "plan has no BRANCH header"; return 1; }
  while IFS= read -r r; do
    dir=$(repo_dir "$r")
    [[ -d $dir/.git ]] || { escalate "REPOS entry is not a git repo: $r"; return 1; }
    cur=$(git -C "$dir" branch --show-current)
    if repo_dirty "$dir"; then
      [[ $cur == "$br" && -n $(ls -d "$HAND"/attempt-* 2>/dev/null) ]] || { escalate "dirty tree in $r at claim"; return 1; }
    fi
    [[ $r == . && $cur != "$br" ]] && { escalate "zeno is on '$cur', plan needs '$br' — switch it yourself"; return 1; }
    ensure_branch "$dir" "$br"
    record_base "$dir"
    install_push_guard "$dir"
  done < <(plan_repos "$PLAN_FILE")
  [[ -f $HAND/scope-base.txt ]] || scope_snapshot > "$HAND/scope-base.txt"
}

release_repos() {
  [[ -f ${PLAN_FILE:-} ]] || return 0   # also runs from the EXIT trap after the handoff was archived
  local r; while IFS= read -r r; do remove_push_guard "$(repo_dir "$r")"; done < <(plan_repos "$PLAN_FILE")
}

# After every role: any new dirt outside REPOS parks the plan (operator repos are sacred).
guard_scope() { # → 0 clean; escalates and returns 1
  local bad; bad=$(scope_check "$HAND/scope-base.txt") && return 0
  escalate "out-of-scope write: $(echo "$bad" | head -3 | tr '\t' ' ' | paste -sd';')"; return 1
}

attempt_count() { find "$HAND" -maxdepth 1 -name 'attempt-*' -type d 2>/dev/null | wc -l; }
attempt_n() { basename "$1" | cut -d- -f2; }

# A crashed attempt (dir without coder.rc) is resumed in place — no duplicate attempt dir.
next_attempt_dir() {
  local n; n=$(attempt_count)
  if (( n > 0 )) && [[ ! -f $HAND/attempt-$n/coder.rc ]]; then echo "$HAND/attempt-$n"; return 0; fi
  echo "$HAND/attempt-$((n + 1))"
}

attempt_loop() {
  local steer attempt
  steer=$(cat "$HAND/steer.txt" 2>/dev/null || true)
  while :; do
    attempt=$(next_attempt_dir)
    (( $(attempt_n "$attempt") <= MAX_ATTEMPTS )) || break
    mkdir -p "$attempt"
    coder_attempt "$attempt" "$steer" || return 0
    if run_gate "$PLAN_FILE" "$attempt"; then review_and_finish "$attempt"; return 0; fi
    steer=$(handle_red_gate "$attempt") || return 0
  done
  escalate "attempts exhausted ($MAX_ATTEMPTS) — gate red"
}

# 0 = coder OK (commits + budget); hard failure escalates and returns 1. Cost is always recorded.
coder_attempt() { # attempt-dir steer
  local rc=0
  run_role coder "$1" "$CODER_CAP_USD" "$2" || rc=$?
  echo "$rc" > "$1/coder.rc"
  record_cost coder "$1" "$CODER_CAP_USD"
  guard_scope || return 1
  budget_ok "$HAND" "$PLAN_CAP_USD" || { escalate "budget exceeded (cap \$$PLAN_CAP_USD) — work kept in repos"; return 1; }
  (( rc == 0 )) || { escalate "coder failed (rc=$rc/watchdog)"; return 1; }
  commit_discipline "$PLAN_FILE" || { escalate "coder left no commits (or a dirty tree) in a REPOS repo"; return 1; }
}

# stdout: steer for the next attempt; rc 1 = escalated.
handle_red_gate() { # attempt-dir
  local decision dfile=$1/triage-DECISION n rc=0
  n=$(attempt_n "$1")
  run_role triage "$1" "$TRIAGE_CAP_USD" || rc=$?
  record_cost triage "$1" "$TRIAGE_CAP_USD"
  guard_scope || return 1
  (( rc == 0 )) || { escalate "triage failed (rc=$rc/watchdog)"; return 1; }
  budget_ok "$HAND" "$PLAN_CAP_USD" || { escalate "budget exceeded (cap \$$PLAN_CAP_USD)"; return 1; }
  decision=$({ head -1 "$dfile" 2>/dev/null || true; } | tr -d '[:space:]')
  if [[ $decision == retry ]] && (( n < MAX_ATTEMPTS )); then
    tail -n +2 "$dfile" | head -c 4000 > "$HAND/steer.txt"
    journal "$PLAN_ID | STEER | $(tr '\n' ' ' < "$HAND/steer.txt")"
    cat "$HAND/steer.txt"; return 0
  fi
  if [[ $decision == retry ]]; then escalate "attempts exhausted ($MAX_ATTEMPTS) — gate red"
  else escalate "triage: escalate"; fi
  return 1
}

review_and_finish() { # attempt-dir
  local round=0 critical
  while :; do
    make_review_patches "$1"
    review_once "$1" || return 0
    critical=$(count_critical "$1")
    (( critical == 0 )) && { finalize "$1"; return 0; }
    (( round >= MAX_REVIEW_ROUNDS )) && { escalate "critical findings after $MAX_REVIEW_ROUNDS review round"; return 0; }
    round=$((round + 1))
    review_fix_round "$1" || return 0
  done
}

# Reviewer run + contract check: no parsable findings.json → one re-prompt, then escalate (never "clean").
review_once() { # attempt-dir → 0 findings valid; escalates otherwise
  local try steer=""
  for try in 1 2; do
    local rc=0; run_role reviewer "$1" "$REVIEWER_CAP_USD" "$steer" || rc=$?
    record_cost reviewer "$1" "$REVIEWER_CAP_USD"
    guard_scope || return 1
    (( rc == 0 )) || { escalate "reviewer failed (rc=$rc/watchdog)"; return 1; }
    budget_ok "$HAND" "$PLAN_CAP_USD" || { escalate "budget exceeded (cap \$$PLAN_CAP_USD)"; return 1; }
    findings_valid "$1" && return 0
    log "reviewer: no findings.json — re-prompting (try $try)"
    steer="Your previous run ended WITHOUT writing findings.json. Finish the review now and write the file (empty list if clean)."
  done
  escalate "reviewer returned no findings section twice — not counted as clean"; return 1
}

review_fix_round() { # attempt-dir
  local findings
  findings=$(jq -c '.findings' "$1/reviewer-findings.json" 2>/dev/null || echo '[]')
  log "review: critical findings — one fix round for the coder"
  rm -f "$1/coder.rc"
  coder_attempt "$1" "Fix the critical findings from code review (do not widen the scope): $findings" || return 1
  run_gate "$PLAN_FILE" "$1" || { escalate "gate red after the review fix"; return 1; }
}

count_critical() { jq '[.findings[]? | select(.severity == "critical")] | length' "$1/reviewer-findings.json" 2>/dev/null || echo 0; }

make_review_patches() { # attempt-dir — one patch per REPOS repo
  local r dir name
  while IFS= read -r r; do
    dir=$(repo_dir "$r"); name=$(basename "$dir")
    git -C "$dir" log --oneline "$(repo_base "$dir")..HEAD" > "$1/review-$name-commits.txt"
    git -C "$dir" diff "$(repo_base "$dir")..HEAD" > "$1/review-$name.patch"
  done < <(plan_repos "$PLAN_FILE")
}

finalize() { # attempt-dir
  local cost; cost=$(plan_spent "$HAND")
  plan_unchanged || { escalate "plan file changed during the run — not trusting the gate"; return 0; }
  scan_secrets "$1" || { escalate "secret scan failed (gitleaks) — see $1/gitleaks.log"; return 0; }
  tag_done
  release_repos
  mutate plan_set_status "$PLAN_SRC" ready
  journal "$PLAN_ID | OK | \$$cost · $(attempt_count) attempt(s) · $(plan_repos "$PLAN_FILE" | paste -sd,)"
  log "SUCCESS: $PLAN_ID → ready (\$$cost)"
  archive_handoff
}

archive_handoff() {
  mkdir -p "$HANDOFF_DIR/archive"
  mv "$HAND" "$HANDOFF_DIR/archive/$TOPIC-$PLAN_ID-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
}

escalate() {
  local reason=$1 memo
  memo=$(find "$HAND" -maxdepth 2 -name triage-memo.md -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  release_repos
  mutate plan_set_status "$PLAN_SRC" parked
  journal "$PLAN_ID | PARKED | $reason${memo:+ · memo: $memo}"
  log "ESCALATION: $reason"
}

main "$@"
