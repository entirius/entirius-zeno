#!/bin/sh
# node_modules is a named volume (empty at first start) — install when the lockfile
# differs from the one last installed; a failed install is not stamped as done.
set -e
STAMP=node_modules/.pnpm-lock-hash
hash=$(sha256sum pnpm-lock.yaml | cut -d' ' -f1)
if [ "$hash" != "$(cat "$STAMP" 2>/dev/null)" ]; then
  echo "installing dependencies (pnpm)..."
  CI=true pnpm install --frozen-lockfile && echo "$hash" > "$STAMP"
fi
exec "$@"
