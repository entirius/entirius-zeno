#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# resolve.sh apps|queues — prints a list of the active recipe (RECIPE, default shop) from recipes/<name>/:
# apps one per line (the LOCAL_APPS order), queues joined with commas (the worker's -Q). `#` starts a comment,
# blank lines are dropped. A missing recipe exits 2.
set -eu

name=${RECIPE:-shop}
dir=$(dirname "$0")/$name
[ -f "$dir/apps.txt" ] && [ -f "$dir/queues.txt" ] || { echo "recipe '$name' not found" >&2; exit 2; }

list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$dir/$1"; }

case ${1:-} in
    apps) list apps.txt ;;
    queues) list queues.txt | paste -sd, - ;;
    *) echo "usage: resolve.sh apps|queues" >&2; exit 2 ;;
esac
