#!/usr/bin/env bash
# Live smoke: the mock topic executed by REAL claude -p roles (spends tokens). Caps: coder 1, reviewer/triage 0.5.
# Usage: scripts/dev-runner/tests/live-smoke.sh  (needs make runner-init + auth; STOP is bypassed for this one tick;
# pass CLAUDE_CLI_PIN/ANTHROPIC_API_KEY/RUNNER_SHARE_LOGIN via the environment, .env is NOT read)
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER_DIR=$(dirname "$TESTS_DIR")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export ZENO_ROOT=$TMP/root PLANS_DIR=$TMP/root/todo/smoke/dev-plans STATE_DIR=$TMP/root/.runner
export MOCK_ROLES=0 ENV_FILE=/dev/null   # never the operator's .env: the caps below are the whole point
export CODER_CAP_USD=${CODER_CAP_USD:-1} REVIEWER_CAP_USD=${REVIEWER_CAP_USD:-0.5} TRIAGE_CAP_USD=${TRIAGE_CAP_USD:-0.5}
mkdir -p "$PLANS_DIR" "$ZENO_ROOT/repo"
cp "$RUNNER_DIR"/mocks/plans/00-README.md "$RUNNER_DIR"/mocks/plans/01-a.md "$PLANS_DIR/"
sed -i 's/^TIMEOUT_S:.*/TIMEOUT_S: 900/' "$PLANS_DIR/01-a.md"   # real sessions need minutes, not the mock's 60 s
git init -q -b develop "$ZENO_ROOT/repo"
( cd "$ZENO_ROOT/repo" && echo base > README.md && git add -A && git -c user.name=t -c user.email=t@t commit -qm init )
echo "== live smoke in $TMP (coder $CODER_CAP_USD / reviewer $REVIEWER_CAP_USD / triage $TRIAGE_CAP_USD USD)"
STOP_FILE=/nonexistent "$RUNNER_DIR/runner.sh" --once --plans "$PLANS_DIR"
st=$(head -12 "$PLANS_DIR/01-a.md" | sed -n 's/^STATUS: *//p')
echo "== status: $st"; cat "$PLANS_DIR/JOURNAL.md"
echo "== spend today:"; cat "$STATE_DIR"/spend-*.log
if [[ $st == ready ]] && awk '{s += $1} END {exit !(s > 0)}' "$STATE_DIR"/spend-*.log; then
  echo "LIVE SMOKE OK"
else
  echo "LIVE SMOKE FAILED — handoff kept in $STATE_DIR/handoff"; trap - EXIT; exit 1
fi
