#!/usr/bin/env bash
# Triage stub. $1 = workdir; writes DECISION (line 1: retry|escalate, then steer) + memo.md (+cost.json).
# MOCK_TRIAGE_MODE=retry|escalate
set -euo pipefail
dir=$1
if [[ ${MOCK_TRIAGE_MODE:-retry} == escalate ]]; then
  printf 'escalate\n' > "$dir/DECISION"
else
  printf 'retry\nStub steer: fix the implementation per gate.log.\n' > "$dir/DECISION"
fi
cat > "$dir/memo.md" <<'MEMO'
# Triage memo (stub)
Context: gate red (mechanics test). Options: retry with steer / escalate. Recommendation: see DECISION.
MEMO
echo "{\"total_cost_usd\": ${MOCK_TRIAGE_COST:-0.01}}" > "$dir/cost.json"
echo "triage-stub: ${MOCK_TRIAGE_MODE:-retry}"
