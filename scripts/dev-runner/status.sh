#!/usr/bin/env bash
# make runner-status — plans table, journal tail, today's spend.
set -euo pipefail
RUNNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$RUNNER_DIR/lib.sh"
PLANS_DIR=${1:?usage: status.sh <plans-dir>}
load_env
echo "== plans: $PLANS_DIR"
while IFS= read -r f; do
  [[ $(basename "$f") == 00-* ]] && continue
  printf '  %-34s %s\n' "$(basename "$f")" "$(plan_header "$f" STATUS)"
done < <(plan_list)
echo "== journal (last 5)"; tail -5 "$PLANS_DIR/JOURNAL.md" 2>/dev/null || echo "  (none)"
spend=$SPEND_DIR/spend-$(date +%F).log
echo "== spend today: \$$(awk '{s += $1} END {printf "%.2f", s}' "$spend" 2>/dev/null || echo 0.00) (cap $DAILY_CAP_USD)"
[[ -f $STOP_FILE ]] && echo "== STOP file present"
exit 0
