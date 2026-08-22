#!/usr/bin/env bash
# Runs a plan's fenced ```gate block from zeno root with set -euo pipefail. No block → DEFAULT.sh.
set -euo pipefail
RUNNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plan=$1
root=${ZENO_ROOT:-$(cd "$RUNNER_DIR/../.." && pwd)}
block=$("$RUNNER_DIR/gates/block.sh" "$plan")
script=$(mktemp "${TMPDIR:-/tmp}/gate-XXXXXX.sh")
trap 'rm -f "$script"' EXIT
if [[ -z ${block//[[:space:]]/} ]]; then
  echo "gate: no block in $(basename "$plan") — using DEFAULT.sh"
  cp "$RUNNER_DIR/gates/DEFAULT.sh" "$script"
else
  printf '#!/usr/bin/env bash\nset -euo pipefail\nset -x\n%s\n' "$block" > "$script"
fi
# set -x traces expanded values into gate.log (triage input, archived) — drop secret-bearing env first;
# make re-reads .env itself, so the gate loses nothing.
for v in $(env | cut -d= -f1 | grep -Ei 'PASSWORD|SECRET|TOKEN|API_KEY|PRIVATE'); do unset "$v"; done
cd "$root" && bash "$script"
