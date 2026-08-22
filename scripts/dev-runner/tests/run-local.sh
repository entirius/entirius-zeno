#!/usr/bin/env bash
# Full runner mechanics on mocks — local, zero LLM. Each path ×2:
# green · red→triage→retry→escalate · steer-ok · triage-escalate · review-critical · crash-resume ·
# flock · budget · timeout · dry · headerless→wip.
# Scenarios run with `set +e`: an assertion failure is counted, never aborts the suite.
set -uo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER_DIR=$(dirname "$TESTS_DIR")
PASS=0 FAIL=0

setup() {
  TMP=$(mktemp -d)
  export ZENO_ROOT=$TMP/root PLANS_DIR=$TMP/root/todo/mock/dev-plans
  export STATE_DIR=$TMP/root/.runner STOP_FILE=$TMP/STOP ENV_FILE=/dev/null
  export MOCK_ROLES=1 MAX_ATTEMPTS=2 MAX_REVIEW_ROUNDS=1 SENTINEL_GRACE=1 POLL_STEP=1 ROLE_TIMEOUT=60
  export MOCK_CODER_MODE=good MOCK_REVIEWER_MODE=ok MOCK_TRIAGE_MODE=retry
  export MOCK_CODER_COST=0.01 MOCK_CODER_SLEEP=0 MOCK_STEER_FIXES=0
  unset MOCK_CODER_STRAY MOCK_CODER_LEAK MOCK_CODER_TAMPER
  mkdir -p "$PLANS_DIR" "$ZENO_ROOT/repo"
  cp "$RUNNER_DIR"/mocks/plans/*.md "$PLANS_DIR/"
  git init -q -b develop "$ZENO_ROOT/repo"
  ( cd "$ZENO_ROOT/repo" && echo base > README.md && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
}
teardown() { rm -rf "$TMP"; }
trap 'rm -rf "${TMP:-}"' EXIT

run_runner() { "$RUNNER_DIR/runner.sh" --once --plans "$PLANS_DIR" "$@" >>"$TMP/runner.log" 2>&1 || true; }
status_of() { head -12 "$PLANS_DIR/$1" | sed -n 's/^STATUS: *//p'; }
readme_status() { awk -F'|' -v id="$1" '$2 ~ "^ *"id" *$" {gsub(/ /,"",$4); print $4}' "$PLANS_DIR/00-README.md"; }
journal_count() { [[ -f $PLANS_DIR/JOURNAL.md ]] && grep -c "$1" "$PLANS_DIR/JOURNAL.md" || echo 0; }
attempts() { find "$STATE_DIR/handoff" -path "*/mock-$1/attempt-*" -maxdepth 3 -type d 2>/dev/null | wc -l; }
archived_attempts() { find "$STATE_DIR/handoff/archive" -path "*/mock-$1-*/attempt-*" -maxdepth 2 -type d 2>/dev/null | wc -l; }
branch_exists() { git -C "$ZENO_ROOT/repo" show-ref -q refs/heads/feature/mock; }
commits_over_develop() { git -C "$ZENO_ROOT/repo" rev-list --count develop..feature/mock; }

assert_eq() { # msg want got
  if [[ $2 == "$3" ]]; then PASS=$((PASS + 1))
  else FAIL=$((FAIL + 1)); echo "  FAIL: $1 (want '$2', got '$3')"; fi
}
assert_true() { local msg=$1; shift; if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "  FAIL: $msg"; fi; }

scenario_green() {
  setup
  run_runner
  assert_eq "green: 01 → ready" ready "$(status_of 01-a.md)"
  assert_eq "green: README row mirrors ready" ready "$(readme_status 01)"
  assert_true "green: branch feature/mock exists" git -C "$ZENO_ROOT/repo" show-ref -q refs/heads/feature/mock
  assert_eq "green: 1 attempt archived" 1 "$(archived_attempts 01)"
  assert_eq "green: journal OK line" 1 "$(journal_count '| 01 | OK |')"
  assert_eq "green: 02 still to-dev before 2nd tick" to-dev "$(status_of 02-b.md)"
  run_runner
  assert_eq "green: 02 → ready after 01 ready" ready "$(status_of 02-b.md)"
  teardown
}

scenario_red() {
  setup
  MOCK_CODER_MODE=bad run_runner
  assert_eq "red: parked after 2nd failure" parked "$(status_of 01-a.md)"
  assert_eq "red: 2 attempt dirs" 2 "$(attempts 01)"
  assert_eq "red: 1 steer line" 1 "$(journal_count '| 01 | STEER |')"
  assert_true "red: PARKED line with memo" grep -q '| 01 | PARKED | .*memo' "$PLANS_DIR/JOURNAL.md"
  assert_eq "red: 02 stays to-dev" to-dev "$(status_of 02-b.md)"
  assert_true "red: branch exists" branch_exists
  run_runner
  assert_eq "red: parked plan is not re-picked" parked "$(status_of 01-a.md)"
  teardown
}

scenario_crash() {
  setup
  MOCK_CODER_SLEEP=4 "$RUNNER_DIR/runner.sh" --once --plans "$PLANS_DIR" >>"$TMP/runner.log" 2>&1 & local pid=$!
  sleep 2 && kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  sleep 4   # orphaned stub finishes writing
  assert_eq "crash: plan stuck in-dev" in-dev "$(status_of 01-a.md)"
  run_runner   # restart: resumes the stale claim in the same attempt dir
  assert_eq "crash: ready after restart" ready "$(status_of 01-a.md)"
  assert_eq "crash: no duplicate attempt dir" 1 "$(archived_attempts 01)"
  assert_true "crash: resume logged" grep -q "stale claim" "$TMP/runner.log"
  assert_true "crash: no leaked .operator hook after resume" test ! -f "$ZENO_ROOT/repo/.git/hooks/pre-push.operator"
  assert_eq "crash: journal OK line" 1 "$(journal_count '| 01 | OK |')"
  assert_true "crash: branch exists" branch_exists
  teardown
}

scenario_flock() {
  setup
  MOCK_CODER_SLEEP=4 "$RUNNER_DIR/runner.sh" --once --plans "$PLANS_DIR" >>"$TMP/runner.log" 2>&1 & local pid=$!
  sleep 1
  run_runner   # second start must bounce off the lock
  assert_true "flock: bounce logged" grep -q "another run holds the lock" "$TMP/runner.log"
  wait "$pid" 2>/dev/null || true
  assert_eq "flock: first run finished" ready "$(status_of 01-a.md)"
  assert_eq "flock: single attempt" 1 "$(archived_attempts 01)"
  assert_eq "flock: single journal OK line" 1 "$(journal_count '| 01 | OK |')"
  assert_true "flock: branch exists" branch_exists
  teardown
}

scenario_budget() {
  setup
  MOCK_CODER_COST=20 run_runner   # 20 > BUDGET_USD 15
  assert_eq "budget: parked" parked "$(status_of 01-a.md)"
  assert_true "budget: reason in journal" grep -q "budget exceeded" "$PLANS_DIR/JOURNAL.md"
  assert_true "budget: no spend log for mocks" bash -c "! ls '$STATE_DIR'/spend-*.log >/dev/null 2>&1"
  assert_eq "budget: 1 attempt dir kept" 1 "$(attempts 01)"
  assert_eq "budget: journal PARKED line" 1 "$(journal_count '| 01 | PARKED |')"
  assert_true "budget: branch exists (work kept)" branch_exists
  teardown
}

scenario_dry() {
  setup
  run_runner --dry-run
  assert_eq "dry: status untouched" to-dev "$(status_of 01-a.md)"
  assert_true "dry: journal untouched" test ! -f "$PLANS_DIR/JOURNAL.md"
  assert_true "dry: no branch created" bash -c "! git -C '$ZENO_ROOT/repo' show-ref -q refs/heads/feature/mock"
  teardown
}

scenario_steer_ok() {
  setup
  MOCK_CODER_MODE=bad MOCK_STEER_FIXES=1 run_runner
  assert_eq "steer: ready after retry" ready "$(status_of 01-a.md)"
  assert_eq "steer: 2 attempts" 2 "$(archived_attempts 01)"
  assert_eq "steer: 1 STEER line" 1 "$(journal_count '| 01 | STEER |')"
  assert_eq "steer: OK line" 1 "$(journal_count '| 01 | OK |')"
  assert_eq "steer: 2 commits over develop" 2 "$(commits_over_develop)"
  teardown
}

scenario_triage_escalate() {
  setup
  MOCK_CODER_MODE=bad MOCK_TRIAGE_MODE=escalate run_runner
  assert_eq "triage-escalate: parked" parked "$(status_of 01-a.md)"
  assert_eq "triage-escalate: single attempt" 1 "$(attempts 01)"
  assert_true "triage-escalate: reason journaled" grep -q '| 01 | PARKED | triage: escalate' "$PLANS_DIR/JOURNAL.md"
  assert_true "triage-escalate: branch exists" branch_exists
  teardown
}

scenario_review_critical() {
  setup
  MOCK_REVIEWER_MODE=critical run_runner
  assert_eq "review-critical: parked after 1 fix round" parked "$(status_of 01-a.md)"
  assert_eq "review-critical: coder ran twice (2 commits)" 2 "$(commits_over_develop)"
  assert_eq "review-critical: still 1 attempt dir" 1 "$(attempts 01)"
  assert_true "review-critical: reason journaled" grep -q 'critical findings after 1 review round' "$PLANS_DIR/JOURNAL.md"
  teardown
}

scenario_timeout() {
  setup
  sed -i 's/^TIMEOUT_S:.*/TIMEOUT_S: 2/' "$PLANS_DIR/01-a.md"   # per-plan header wins over ROLE_TIMEOUT
  MOCK_CODER_SLEEP=10 run_runner
  assert_eq "timeout: parked" parked "$(status_of 01-a.md)"
  assert_true "timeout: watchdog fired" grep -q "watchdog: timeout" "$TMP/runner.log"
  assert_true "timeout: rc 124 journaled" grep -q 'coder failed (rc=124' "$PLANS_DIR/JOURNAL.md"
  assert_eq "timeout: no orphan stub" 0 "$(pgrep -fc "roles/coder.sh $TMP" || true)"
  teardown
}

scenario_wip_header() {
  setup
  printf '# headerless plan\n' > "$PLANS_DIR/00.5-x.md"; mv "$PLANS_DIR/00.5-x.md" "$PLANS_DIR/005-noheader.md"
  run_runner --dry-run
  assert_eq "wip: dry-run leaves header untouched" "" "$(status_of 005-noheader.md)"
  assert_true "wip: dry-run writes no journal" test ! -f "$PLANS_DIR/JOURNAL.md"
  run_runner
  assert_eq "wip: headerless → wip" wip "$(status_of 005-noheader.md)"
  assert_eq "wip: WIP journaled" 1 "$(journal_count '| 005 | WIP |')"
  assert_eq "wip: next valid plan still ran" ready "$(status_of 01-a.md)"
  teardown
}

scenario_scope_violation() {
  setup
  mkdir -p "$ZENO_ROOT/repos/django/other"; git init -q -b develop "$ZENO_ROOT/repos/django/other"
  ( cd "$ZENO_ROOT/repos/django/other" && echo x > a && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
  MOCK_CODER_STRAY=$ZENO_ROOT/repos/django/other/stray.txt run_runner
  assert_eq "scope: parked" parked "$(status_of 01-a.md)"
  assert_true "scope: offending path journaled" grep -q 'out-of-scope write: .*repos/django/other.*stray.txt' "$PLANS_DIR/JOURNAL.md"
  assert_true "scope: push guard removed after park" test ! -f "$ZENO_ROOT/repo/.git/hooks/pre-push"
  teardown
}

scenario_push_blocked() {
  setup
  git init -q --bare "$TMP/remote.git"; git -C "$ZENO_ROOT/repo" remote add origin "$TMP/remote.git"
  printf '#!/bin/sh\necho operator-hook\n' > "$ZENO_ROOT/repo/.git/hooks/pre-push"; chmod +x "$ZENO_ROOT/repo/.git/hooks/pre-push"
  MOCK_CODER_SLEEP=4 "$RUNNER_DIR/runner.sh" --once --plans "$PLANS_DIR" >>"$TMP/runner.log" 2>&1 & local pid=$!
  local i; for ((i = 0; i < 40; i++)); do grep -q 'dev-runner' "$ZENO_ROOT/repo/.git/hooks/pre-push" 2>/dev/null && break; sleep 0.1; done
  assert_true "push: refused while claimed" bash -c "! git -C '$ZENO_ROOT/repo' push -q origin feature/mock 2>/dev/null"
  wait "$pid" 2>/dev/null || true
  assert_eq "push: plan ready" ready "$(status_of 01-a.md)"
  assert_true "push: allowed after finalize" bash -c "git -C '$ZENO_ROOT/repo' push -q origin feature/mock >/dev/null 2>&1"
  assert_eq "push: operator hook restored" "operator-hook" "$(sh "$ZENO_ROOT/repo/.git/hooks/pre-push")"
  assert_true "push: no leaked .operator file" test ! -f "$ZENO_ROOT/repo/.git/hooks/pre-push.operator"
  teardown
}

scenario_secret_leak() {
  setup
  MOCK_CODER_LEAK=1 run_runner
  assert_eq "leak: parked" parked "$(status_of 01-a.md)"
  assert_true "leak: reason journaled" grep -q 'secret scan failed' "$PLANS_DIR/JOURNAL.md"
  assert_true "leak: finding recorded in gitleaks log" grep -qi 'leak' "$STATE_DIR/handoff/mock-01/attempt-1/gitleaks.log"
  teardown
}

scenario_reviewer_reprompt() {
  setup
  MOCK_REVIEWER_MODE=truncated run_runner
  assert_eq "reprompt: ready after re-prompt" ready "$(status_of 01-a.md)"
  assert_true "reprompt: logged" grep -q 'reviewer: no findings.json — re-prompting (try 1)' "$TMP/runner.log"
  assert_eq "reprompt: reviewer cost booked twice" 2 "$(grep -c '^reviewer' "$STATE_DIR"/handoff/archive/mock-01-*/costs.log)"
  teardown
}

scenario_reviewer_silent() {
  setup
  MOCK_REVIEWER_MODE=silent run_runner
  assert_eq "silent: parked, never clean" parked "$(status_of 01-a.md)"
  assert_true "silent: reason journaled" grep -q 'no findings section twice' "$PLANS_DIR/JOURNAL.md"
  teardown
}

scenario_reviewer_prose() {
  setup
  MOCK_REVIEWER_MODE=prose run_runner
  assert_eq "prose: JSON after prose accepted" ready "$(status_of 01-a.md)"
  teardown
}

scenario_plan_tamper() {
  setup
  MOCK_CODER_TAMPER=$PLANS_DIR/01-a.md run_runner   # coder edits its own plan file
  assert_eq "tamper: parked" parked "$(status_of 01-a.md)"
  assert_true "tamper: reason journaled" grep -q 'plan file changed during the run' "$PLANS_DIR/JOURNAL.md"
  teardown
}

scenario_dirty_resume() {
  setup
  MOCK_CODER_SLEEP=4 "$RUNNER_DIR/runner.sh" --once --plans "$PLANS_DIR" >>"$TMP/runner.log" 2>&1 & local pid=$!
  sleep 2 && kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  pkill -9 -f "roles/coder.sh $TMP" 2>/dev/null || true; sleep 0.5
  echo leftover > "$ZENO_ROOT/repo/leftover.txt"     # crashed coder's uncommitted work on BRANCH
  run_runner
  assert_eq "dirty-resume: tolerated on BRANCH" ready "$(status_of 01-a.md)"
  git -C "$ZENO_ROOT/repo" checkout -q develop; echo op > "$ZENO_ROOT/repo/op.txt"
  run_runner
  assert_true "dirty-resume: dirty develop at fresh claim parks 02" grep -q '| 02 | PARKED | dirty tree' "$PLANS_DIR/JOURNAL.md"
  teardown
}

scenario_zeno_scope() {
  setup
  git init -q -b feature/mock "$ZENO_ROOT"; ( cd "$ZENO_ROOT" && printf 'repo/\n.runner/\ntodo/\n' > .gitignore && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
  sed -i 's/^REPOS:.*/REPOS: ./' "$PLANS_DIR/01-a.md"; sed -i 's|^test -f repo/IMPL_OK|test -f IMPL_OK|' "$PLANS_DIR/01-a.md"
  run_runner
  assert_eq "zeno-scope: REPOS . on BRANCH → ready" ready "$(status_of 01-a.md)"
  sed -i 's/^REPOS:.*/REPOS: ./' "$PLANS_DIR/02-b.md"; sed -i 's|^test -f repo/IMPL_OK|test -f IMPL_OK|' "$PLANS_DIR/02-b.md"
  git -C "$ZENO_ROOT" checkout -qb other
  run_runner
  assert_true "zeno-scope: wrong zeno branch parks, never switches" grep -q "| 02 | PARKED | zeno is on 'other'" "$PLANS_DIR/JOURNAL.md"
  assert_eq "zeno-scope: zeno still on other" other "$(git -C "$ZENO_ROOT" branch --show-current)"
  teardown
}

main() {
  command -v jq >/dev/null || { echo "jq missing"; exit 1; }
  command -v flock >/dev/null || { echo "flock missing"; exit 1; }
  command -v gitleaks >/dev/null || { echo "gitleaks missing (secret_leak scenario)"; exit 1; }
  local s i
  set +e
  for s in "${SCENARIOS[@]}"; do
    for i in 1 2; do echo "— scenario_$s (run $i)"; "scenario_$s"; done
  done
  echo "==============================="
  echo "PASS=$PASS FAIL=$FAIL"
  (( FAIL == 0 ))
}

SCENARIOS=(green red steer_ok triage_escalate review_critical crash flock budget timeout dry wip_header scope_violation push_blocked secret_leak reviewer_reprompt reviewer_silent reviewer_prose plan_tamper dirty_resume zeno_scope)
main "$@"
