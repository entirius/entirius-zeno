#!/usr/bin/env bash
# make runner-loop — foreground loop: one tick, sleep, repeat; ends when the STOP file appears.
# Sleep inhibited via systemd-inhibit when available (overnight runs).
set -euo pipefail
RUNNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLANS=${1:?usage: loop.sh <plans-dir>}
: "${LOOP_SLEEP:=300}"
if [[ -z ${RUNNER_INHIBITED:-} ]] && command -v systemd-inhibit >/dev/null; then
  RUNNER_INHIBITED=1 exec systemd-inhibit --what=sleep:idle --who=dev-runner --why="dev-runner loop" "$0" "$PLANS"
fi
while [[ ! -f $RUNNER_DIR/STOP ]]; do
  "$RUNNER_DIR/runner.sh" --once --plans "$PLANS" || echo "[loop] tick failed (rc=$?) — continuing" >&2
  for ((i = 0; i < LOOP_SLEEP; i += 10)); do [[ -f $RUNNER_DIR/STOP ]] && break; sleep 10; done
done
echo "[loop] STOP present — loop ended"
