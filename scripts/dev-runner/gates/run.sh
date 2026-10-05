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
  # bash never exits on a failed `! cmd` under set -e, so a "must not match" line would always pass: every line that
  # starts with `! ` becomes an explicit check (set -x still traces the command and prints what matched). Exit 1 = no
  # match = pass; 0 = matched and ≥ 2 = the check itself failed (a missing path) — both fail the gate.
  block=$(sed -E 's/^! (.+)$/rc=0; \1 || rc=$?; [ "$rc" -eq 1 ] || { echo "gate: must-not-match check rc=$rc (0 = matched, >1 = error)" >\&2; exit 1; }/' <<<"$block")
  # Every statement is its own check: set -e ignores a failure left of `&&` (`test -f a && grep -q x a` passes when a is
  # missing), but the statement's status is still non-zero — so a `[ $? = 0 ]` check follows each one. Lines are grouped
  # until the group parses cleanly (a multi-line `node -e '…'`, a loop, a heredoc or a `\` continuation stays one
  # statement). An `|| exit` wrapper would not do: bash turns set -e off inside it. An unparseable tail stays as written.
  strict="" buf=""
  while IFS= read -r line || [[ -n $line ]]; do
    buf+="$line"$'\n'
    [[ $line =~ (^|[^\\])(\\\\)*\\$ ]] && continue
    out=$(bash -n -c "$buf" 2>&1) && [[ -z $out ]] || continue
    strict+=$buf
    grep -qvE '^[[:space:]]*(#.*)?$' <<<"$buf" && strict+=$'[ $? = 0 ] || { echo "gate: the statement above failed" >&2; exit 1; }\n'
    buf=""
  done <<<"$block"
  block=$strict$buf
  printf '#!/usr/bin/env bash\nset -euo pipefail\nset -x\n%s\n' "$block" > "$script"
fi
# set -x traces expanded values into gate.log (triage input, archived) — drop secret-bearing env first;
# make re-reads .env itself, so the gate loses nothing.
for v in $(env | cut -d= -f1 | grep -Ei 'PASSWORD|SECRET|TOKEN|API_KEY|PRIVATE'); do unset "$v"; done
cd "$root" && bash "$script"
