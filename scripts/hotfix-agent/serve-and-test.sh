#!/usr/bin/env bash
# Serve the CMS hotfix worktree on :8183 against the zeno stack and run e2e specs on it.
#   serve-and-test.sh --serve                     dev server in the foreground (Ctrl-C to stop)
#   serve-and-test.sh tests/e2e/a.spec.js …       start, run the specs, stop
#   serve-and-test.sh --from-outcome <file>       the specs listed in outcome.json (`e2e_specs`), or the smoke spec
set -euo pipefail
ZENO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
W=$ZENO/repos/pwa/entirius-pwa-cms-hotfix
PORT=${HOTFIX_PORT:-8183}
export VUE_APP_API_URL=http://localhost:8100 VUE_APP_CHANNEL=default-europe VUE_APP_PANELS=pages,pim,points VUE_APP_LANG=EN

serve() { cd "$W" && exec npm run serve -- --port "$PORT"; }

[[ ${1:-} == --serve ]] && serve

specs=("$@")
if [[ ${1:-} == --from-outcome ]]; then
  mapfile -t specs < <(python3 -c "import json,sys; print('\n'.join(json.load(open(sys.argv[1])).get('e2e_specs') or []))" "$2" | sed '/^$/d')
fi
(( ${#specs[@]} )) || specs=(tests/e2e/01-smoke.spec.js)

cd "$W"
log=$(mktemp)
# own process group, so the whole npm → vue-cli-service tree stops with it
setsid npm run serve -- --port "$PORT" >"$log" 2>&1 &
pid=$!
trap 'kill -- -"$pid" 2>/dev/null; rm -f "$log"' EXIT
for _ in $(seq 1 90); do
  curl -s -o /dev/null "http://localhost:$PORT/" && break
  kill -0 "$pid" 2>/dev/null || { cat "$log"; echo "dev server died"; exit 1; }
  sleep 2
done
CMS_BASE_URL=http://localhost:$PORT VOLKANOS_API_BASE=http://localhost:8100 VUE_APP_USERNAME=admin VUE_APP_PASSWORD=admin123 \
  VUE_APP_CHANNEL=default-europe npx playwright test "${specs[@]}"
