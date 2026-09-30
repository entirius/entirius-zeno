#!/usr/bin/env bash
# Run next to an overnight `make runner-loop`: `scripts/dev-runner/creds-guard.sh &` (CLI >= 2.1.282 replaces the
# profile symlink on token refresh and strands the other roles on a rotated refresh token).
# Keep dev-runner role profiles on ONE OAuth state: when a role's CLI replaces its credentials symlink with a
# file (token refresh), move the newer token into the shared file and restore the symlink.
set -uo pipefail
SHARED=$HOME/.claude/.credentials.json
LOG=${CREDS_GUARD_LOG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.runner/creds-guard.log}
expires() { jq -r '.claudeAiOauth.expiresAt // 0' "$1" 2>/dev/null || echo 0; }
while true; do
  for role in coder reviewer triage ux-tester; do
    f=$HOME/.claude-runner/$role/.credentials.json
    [[ -e $f && ! -L $f ]] || continue
    if (( $(expires "$f") > $(expires "$SHARED") )); then
      cp "$f" "$SHARED.tmp" && chmod 600 "$SHARED.tmp" && mv "$SHARED.tmp" "$SHARED"
      what="newer token moved to shared"
    else
      what="stale copy dropped"
    fi
    mv "$f" "$f.replaced-$(date +%H%M%S)" && ln -s "$SHARED" "$f"
    echo "$(date +%T) creds-guard: $role replaced its symlink — $what, symlink restored" | tee -a "$LOG"
  done
  sleep 15
done
