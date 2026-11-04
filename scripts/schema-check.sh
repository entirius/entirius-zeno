#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Drift check of the generated OpenAPI specs (make schema) against a published copy.
#   bash scripts/schema-check.sh <dir>     # <dir> holds volkanos-api-{admin,storefront}.yaml
# Exit 0 = all equal, 1 = drift (diff in build/openapi/drift-<audience>.diff) or a published `info.version` other
# than `service` in the docs' src/data/platform.json (checked when <dir> is a docs clone's public/openapi),
# 2 = missing argument or file. Writes only in build/openapi/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ $# -eq 1 ]] || { echo "usage: schema-check.sh <dir>" >&2; exit 2; }
out=build/openapi
rc=0
for audience in admin storefront; do
  file=volkanos-api-$audience.yaml
  for path in "$out/$file" "$1/$file"; do
    [[ -f $path ]] || { echo "schema-check: $path missing" >&2; exit 2; }
  done
  drift=$out/drift-$audience.diff
  if diff -u "$1/$file" "$out/$file" > "$drift"; then
    rm -f "$drift"
    echo "schema-check: $file up to date"
  else
    echo "schema-check: $file drifts ($(wc -l < "$drift") diff lines, $drift)"
    rc=1
  fi
done

platform=$1/../../src/data/platform.json
if [[ -f $platform ]]; then
  want=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["service"])' "$platform")
  for audience in admin storefront; do
    have=$(sed -n 's/^  version: //p' "$1/volkanos-api-$audience.yaml" | head -1)
    if [[ $have == "$want" ]]; then
      echo "schema-check: volkanos-api-$audience.yaml is version $have, as platform.json"
    else
      echo "schema-check: volkanos-api-$audience.yaml is version $have, platform.json says service $want"
      rc=1
    fi
  done
fi
exit $rc
