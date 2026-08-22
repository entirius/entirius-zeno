#!/usr/bin/env bash
# Reviewer stub. $1 = workdir; writes findings.json (+cost.json). MOCK_REVIEWER_MODE=ok|critical
set -euo pipefail
dir=$1
if [[ ${MOCK_REVIEWER_MODE:-ok} == critical ]]; then
  echo '{"findings":[{"severity":"critical","file":"stub.py","note":"stub: critical finding"}]}' > "$dir/findings.json"
else
  echo '{"findings":[]}' > "$dir/findings.json"
fi
echo "{\"total_cost_usd\": ${MOCK_REVIEWER_COST:-0.01}}" > "$dir/cost.json"
echo "reviewer-stub: ${MOCK_REVIEWER_MODE:-ok}"
