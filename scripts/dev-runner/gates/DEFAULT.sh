#!/usr/bin/env bash
# Default gate when a plan has no ```gate block: migrations + service suite.
set -euo pipefail
set -x
make migrate
make test
