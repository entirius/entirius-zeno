#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# isolated-env.sh <suffix> [offset] — prints the .env of a second zeno stack that runs beside the main one:
# .env.example with COMPOSE_PROJECT_NAME=entirius-zeno-<suffix> and every *_PORT shifted by <offset> (1000).
# One .env per checkout: used by `ZENO_STACK=<suffix> make init` in a separate checkout, never in this one.
set -eu

suffix=${1:?usage: isolated-env.sh <suffix> [offset]}
offset=${2:-1000}
echo "$suffix" | grep -Eq '^[a-z0-9]+$' || { echo "isolated-env: suffix must match [a-z0-9]+ (got '$suffix')" >&2; exit 1; }
echo "$offset" | grep -Eq '^[1-9][0-9]*$' || { echo "isolated-env: offset must be a positive number (got '$offset')" >&2; exit 1; }

awk -v suffix="$suffix" -v offset="$offset" '
  /^COMPOSE_PROJECT_NAME=/ { print "COMPOSE_PROJECT_NAME=entirius-zeno-" suffix; next }
  /^[A-Z0-9_]+_PORT=[0-9]+$/ { split($0, pair, "="); print pair[1] "=" pair[2] + offset; next }
  { print }
' "$(dirname "$0")/../.env.example"
