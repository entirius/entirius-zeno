#!/usr/bin/env bash
# dev-runner lib — plan-seam (STATUS: lines in todo/<topic>/dev-plans), git, roles,
# watchdog, budgets, gate. State lives in the plan files + .runner/handoff (attempt dirs).

log() { printf '[runner %s] %s\n' "$(date +%T)" "$*" >&2; }
die() { log "FATAL: $*"; exit 1; }

load_env() {
  local f=${ENV_FILE:-$RUNNER_DIR/.env}
  # shellcheck source=/dev/null
  [[ -f $f ]] && source "$f"
  : "${ZENO_ROOT:=$(cd "$RUNNER_DIR/../.." && pwd)}"
  : "${STATE_DIR:=$ZENO_ROOT/.runner}" "${HANDOFF_DIR:=$STATE_DIR/handoff}"
  : "${WORK_DIR:=$STATE_DIR/work}" "${LOCK_FILE:=$STATE_DIR/lock}" "${SPEND_DIR:=$STATE_DIR}"
  : "${STOP_FILE:=$RUNNER_DIR/STOP}" "${GATES_DIR:=$RUNNER_DIR/gates}"
  : "${BASE_BRANCH:=develop}" "${MAX_ATTEMPTS:=3}" "${MAX_REVIEW_ROUNDS:=1}"
  : "${CODER_CAP_USD:=15}" "${REVIEWER_CAP_USD:=3}" "${TRIAGE_CAP_USD:=1}" "${DAILY_CAP_USD:=60}"
  : "${ROLE_TIMEOUT:=3600}" "${SENTINEL_GRACE:=20}" "${POLL_STEP:=2}"
  : "${MOCK_ROLES:=0}" "${DRY:=0}"
  [[ -n ${PLANS_DIR:-} ]] || die "PLANS_DIR required (--plans <dir>)"
  [[ -d $PLANS_DIR ]] || die "plans dir not found: $PLANS_DIR"
  mkdir -p "$HANDOFF_DIR" "$WORK_DIR"
}

acquire_lock() { exec 9>"$LOCK_FILE"; flock -n 9; }

# Every mutation goes through mutate() — --dry-run only logs.
mutate() { if [[ $DRY == 1 ]]; then log "DRY-RUN: $*"; else "$@"; fi; }

# --- Plan-seam ----------------------------------------------------------------

plan_id() { # file → id (01 | FIX-01 | BG-03)
  local b; b=$(basename "$1" .md)
  case $b in
    FIX-*|BG-*) echo "${b%%-*}-$(cut -d- -f2 <<<"$b")" ;;
    *) echo "${b%%-*}" ;;
  esac
}

plan_file() { # id → path (first match)
  local f
  for f in "$PLANS_DIR/$1-"*.md "$PLANS_DIR/$1.md"; do [[ -f $f ]] && { echo "$f"; return 0; }; done
  return 1
}

plan_header() { # file KEY → value (first 12 lines)
  head -12 "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]*$//'
}

plan_has_header() { head -12 "$1" | grep -q '^STATUS:'; }

plan_set_status() { # file status — in place + 00-README table row
  local f=$1 st=$2 id readme=$PLANS_DIR/00-README.md
  id=$(plan_id "$f")
  sed -i "1,12s/^STATUS:.*/STATUS: $st/" "$f"
  [[ -f $readme ]] || return 0
  grep -Eq "^\| *$id *\|" "$readme" || log "warning: no 00-README row for plan $id — table not mirrored"
  awk -v id="$id" -v st="$st" 'BEGIN{FS=OFS="|"}
    $0 ~ "^\\| *"id" *\\|" && NF >= 4 { $4 = " " st " " } { print }' "$readme" > "$readme.tmp" && mv "$readme.tmp" "$readme"
}

# Header lint at claim: ids/branch/numbers are interpolated into awk, git and arithmetic.
plan_lint() { # file → 0 ok; message on stdout when invalid
  local f=$1 v r
  [[ $(plan_id "$f") =~ ^[A-Za-z0-9-]+$ ]] || { echo "plan id"; return 1; }
  v=$(plan_header "$f" BRANCH); [[ $v =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || { echo "BRANCH '$v'"; return 1; }
  for k in BUDGET_USD TIMEOUT_S; do
    v=$(plan_header "$f" $k); [[ -z $v || $v =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "$k '$v' not numeric"; return 1; }
  done
  for v in $(plan_header "$f" DEPENDS | tr ',' ' '); do
    [[ $v =~ ^[A-Za-z0-9-]+$ ]] || { echo "DEPENDS '$v'"; return 1; }
  done
  while IFS= read -r r; do
    [[ $r == . || ( $r =~ ^[A-Za-z0-9._/-]+$ && $r != *..* && $r != /* ) ]] || { echo "REPOS '$r'"; return 1; }
  done < <(plan_repos "$f")
}

plan_deps_ready() { # file → 0 when every DEPENDS id is ready
  local d df
  for d in $(plan_header "$1" DEPENDS | tr ',' ' '); do
    df=$(plan_file "$d") || { log "warning: $(plan_id "$1") depends on unknown plan '$d'"; return 1; }
    [[ $(plan_header "$df" STATUS) == ready ]] || return 1
  done
}

plan_list() { # numbered plans first, then FIX-/BG- by creation (mtime)
  find "$PLANS_DIR" -maxdepth 1 -name '[0-9]*.md' | sort
  find "$PLANS_DIR" -maxdepth 1 \( -name 'FIX-*.md' -o -name 'BG-*.md' \) -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-
}

# First in-dev (stale claim — we hold the only lock), else lowest to-dev with deps ready.
pick_plan() {
  local f st
  while IFS= read -r f; do
    [[ $(basename "$f") == 00-* ]] && continue
    if ! plan_has_header "$f"; then
      mutate sed -i '1i STATUS: wip' "$f"; journal "$(plan_id "$f") | WIP | missing machine header"; continue
    fi
    [[ $(plan_header "$f" STATUS) == in-dev ]] && { echo "$f"; return 0; }
  done < <(plan_list)
  while IFS= read -r f; do
    st=$(plan_header "$f" STATUS)
    [[ $st == to-dev ]] && plan_deps_ready "$f" && { echo "$f"; return 0; }
  done < <(plan_list)
  return 1
}

journal() {
  [[ $DRY == 1 ]] && { log "DRY-RUN: journal $*"; return 0; }
  echo "$(date +%F) | $*" >> "$PLANS_DIR/JOURNAL.md"
}

# --- Repos / git ---------------------------------------------------------------

plan_repos() { plan_header "$1" REPOS | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'; }
repo_dir() { [[ $1 == . ]] && echo "$ZENO_ROOT" || echo "$ZENO_ROOT/$1"; }

ensure_branch() { # dir branch — checkout, create from BASE_BRANCH when missing
  local dir=$1 br=$2
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $dir"
  if git -C "$dir" show-ref -q --verify "refs/heads/$br"; then
    [[ $(git -C "$dir" branch --show-current) == "$br" ]] || mutate git -C "$dir" checkout -q "$br"
  else
    mutate git -C "$dir" checkout -qb "$br" "$BASE_BRANCH"
  fi
}

repo_dirty() { [[ -n $(git -C "$1" status --porcelain --untracked-files=all | grep -v '^?? .runner/' | head -1) ]]; }

# Per-plan diff anchor: HEAD of each REPOS repo recorded at claim (BRANCH is shared by a whole topic,
# so BASE_BRANCH..HEAD would contain every earlier plan). Falls back to BASE_BRANCH.
base_file() { echo "${HAND:?}/base-$(basename "$1").sha"; }   # HAND = plan handoff dir (runner.sh)
repo_base() { local f; f=$(base_file "$1"); if [[ -f $f ]]; then cat "$f"; else echo "$BASE_BRANCH"; fi; }
record_base() { local f; f=$(base_file "$1"); [[ -f $f ]] || git -C "$1" rev-parse HEAD > "$f"; }

# 0 = every REPOS repo has commits over its claim baseline (or the plan allows none). Never auto-commits.
commit_discipline() { # plan-file → 0 ok; 1 = a REPOS repo has no commits / dirty tree
  local f=$1 r dir
  [[ $(plan_header "$f" NO_COMMIT_OK) == true ]] && return 0
  while IFS= read -r r; do
    dir=$(repo_dir "$r")
    repo_dirty "$dir" && { log "commit discipline: dirty tree in $r"; return 1; }
    [[ $(git -C "$dir" rev-list --count "$(repo_base "$dir")..HEAD") -gt 0 ]] || { log "commit discipline: no commits in $r"; return 1; }
  done < <(plan_repos "$f")
}

# --- Watchdog ------------------------------------------------------------------

# Child runs in its own session (setsid) so a kill takes the whole process group — a timed-out
# `claude -p` must not leave tool children writing into the repos.
run_with_watchdog() { # timeout sentinel outfile cmd...
  local timeout=$1 sentinel=$2 out=$3 rc=0 t=0 pid; shift 3
  setsid "$@" </dev/null >"$out" 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -n $sentinel && -e $sentinel ]]; then
      sleep "$SENTINEL_GRACE"
      kill -0 "$pid" 2>/dev/null || break
      log "watchdog: sentinel present, process hangs — kill"
      kill_group "$pid"; return 0
    fi
    sleep "$POLL_STEP"; t=$((t + POLL_STEP))
    if (( t >= timeout )); then
      log "watchdog: timeout ${timeout}s — kill"
      kill_group "$pid"; return 124
    fi
  done
  wait "$pid" || rc=$?
  return "$rc"
}

kill_group() { kill -9 -- "-$1" 2>/dev/null || kill -9 "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }

# --- Roles (mock = stub script, live = claude -p in a role profile; plan 02) ----

role_workdir() { echo "$WORK_DIR/$1"; }

run_role() { # role attempt-dir cap steer?  (cap = --max-budget-usd of the live role, plan 02)
  local role=$1 hand=$2 cap=$3 steer=${4:-} rc=0 dir repos
  dir=$(role_workdir "$role"); rm -rf "$dir"; mkdir -p "$dir" "$hand"
  if [[ $MOCK_ROLES == 1 ]]; then
    repos=$(plan_repos "$PLAN_FILE" | while read -r r; do repo_dir "$r"; done | paste -sd:)
    run_with_watchdog "$ROLE_TIMEOUT" "" "$hand/$role-out.log" \
      env MOCK_STEER="$steer" RUNNER_REPO_DIRS="$repos" "$RUNNER_DIR/mocks/roles/$role.sh" "$dir" || rc=$?
  else
    # shellcheck disable=SC2317  # live path lands with plan 02
    run_role_live "$role" "$hand" "$cap" "$steer" || rc=$?
  fi
  collect_outputs "$role" "$hand"
  return "$rc"
}

run_role_live() { die "live roles arrive with plan 02 (MOCK_ROLES=1 for now)"; }

# Role artefacts → handoff (runner moves them; roles never write to handoff).
collect_outputs() { # role attempt-dir
  local dir f; dir=$(role_workdir "$1")
  for f in cost.json findings.json memo.md DECISION; do
    [[ -f $dir/$f && ! -L $dir/$f ]] && mv "$dir/$f" "$2/$1-$f"
  done
  return 0
}

# --- Budget --------------------------------------------------------------------

record_cost() { # role attempt-dir — plan ledger + daily counter (live only)
  local hand=$2 cost=0
  [[ -f $hand/$1-cost.json ]] && cost=$(jq -r '.total_cost_usd // 0' "$hand/$1-cost.json")
  echo "$1 $cost" >> "$(dirname "$hand")/costs.log"
  [[ $MOCK_ROLES == 1 ]] || echo "$cost" >> "$SPEND_DIR/spend-$(date +%F).log"
}

plan_spent() { awk '{s += $2} END {printf "%.2f", s}' "$1/costs.log" 2>/dev/null || echo 0; }

budget_ok() { # plan-handoff-dir cap → 0 when ledger ≤ cap
  [[ -f $1/costs.log ]] || return 0
  awk -v cap="$2" '{s += $2} END {exit (s > cap + 0)}' "$1/costs.log"
}

daily_cap_ok() {
  local f spent; f=$SPEND_DIR/spend-$(date +%F).log
  [[ -f $f ]] || return 0
  spent=$(awk '{s += $1} END {printf "%.2f", s}' "$f")
  if awk -v s="$spent" -v c="$DAILY_CAP_USD" 'BEGIN {exit !(s + 0 > c + 0)}'; then
    log "daily cap \$$DAILY_CAP_USD exhausted (\$$spent) — pausing"; return 1
  fi
}

# --- Gate (deterministic script, zero LLM) ------------------------------------

run_gate() { # plan-file attempt-dir → exit code = verdict
  local rc=0
  run_with_watchdog "$ROLE_TIMEOUT" "" "$2/gate.log" "$GATES_DIR/run.sh" "$1" || rc=$?
  log "gate $(plan_id "$1"): $([[ $rc == 0 ]] && echo GREEN || echo "RED (rc=$rc)")"
  return "$rc"
}
