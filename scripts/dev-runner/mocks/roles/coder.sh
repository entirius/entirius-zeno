#!/usr/bin/env bash
# Coder stub (MOCK_ROLES=1, zero tokens). $1 = role workdir; RUNNER_REPO_DIRS = ':'-separated REPOS dirs.
# MOCK_CODER_MODE=good|bad · MOCK_STEER_FIXES=1 (steer fixes the code) · MOCK_CODER_SLEEP=N
# MOCK_CODER_COST=x · MOCK_CODER_STRAY=<path> (write outside REPOS → scope violation) · MOCK_CODER_LEAK=1 · MOCK_CODER_TAMPER=<file> (append to it)
set -euo pipefail
dir=$1
sleep "${MOCK_CODER_SLEEP:-0}"
marker=IMPL_BAD
[[ ${MOCK_CODER_MODE:-good} == good ]] && marker=IMPL_OK
[[ -n ${MOCK_STEER:-} && ${MOCK_STEER_FIXES:-0} == 1 ]] && marker=IMPL_OK
IFS=: read -ra repos <<<"${RUNNER_REPO_DIRS:?}"
for r in "${repos[@]}"; do
  rm -f "$r/IMPL_OK" "$r/IMPL_BAD"
  date +%s%N > "$r/$marker"
  git -C "$r" add -A
  git -C "$r" -c user.name=coder-stub -c user.email=coder@dev-runner commit -qm "feat: coder stub ($marker)"
done
[[ -n ${MOCK_CODER_STRAY:-} ]] && echo stray > "$MOCK_CODER_STRAY"
[[ -n ${MOCK_CODER_TAMPER:-} ]] && echo "# tampered by the coder" >> "$MOCK_CODER_TAMPER"
if [[ ${MOCK_CODER_LEAK:-0} == 1 ]]; then   # fake GitHub PAT (strict regex rule) → gitleaks must park the plan
  echo "token = ghp_GENERATED_AT_RUNTIME_NOT_A_SECRET" > "${repos[0]}/leak.cfg"
  git -C "${repos[0]}" add -A && git -C "${repos[0]}" -c user.name=coder-stub -c user.email=coder@dev-runner commit -qm "chore: config"
fi
echo "{\"total_cost_usd\": ${MOCK_CODER_COST:-0.01}}" > "$dir/cost.json"
echo "coder-stub: $marker (steer='${MOCK_STEER:-}')"
