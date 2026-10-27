#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# stranger-run.sh — proves the documented first run from zero, on an isolated second stack beside the main one.
#
# Phase 1: a clone of this tree in $STRANGER_DIR, a newcomer's shell (no SSH, no git credentials, no `gh`, no `uv`,
# nothing of the operator's environment), then `make setup`, checks, the update path and teardown — every step timed.
# Phase 2 (service-only): the service repo alone with `uv` and the SQLite fallback, no Docker.
# Result: one JSON file ($OUT). Exit 1 when any step failed; logs stay in $STRANGER_DIR/logs.
#
# Variables (all optional):
#   STRANGER_DIR      work directory (.runner/stranger) — keep it on a real disk, the images need room
#   STRANGER_BRANCH   branch to clone (the current one)
#   ZENO_STACK        stack suffix (s2): compose project entirius-zeno-<suffix>
#   ZENO_PORT_OFFSET  host port shift of the isolated stack (1000)
#   OUT               result file (todo/docs-launch/memo/stranger-run.json)
#   KEEP              1 = leave the stack running (0)
#   BUILD_ARGS        build flags of the first setup ("--no-cache --pull": a cold build)
#   RECIPE            recipe of the isolated stack (recipes/<name>/), written to its .env; unset = shop
#   TESTS_FROM        github = setup clones the test package (default); local = this tree's clone of it, at its
#                     current branch with its uncommitted work
#   BDD               1 = `make bdd` after the checks, with the real PATH (0); its verdict never fails the run
#   SERVICE_ONLY      0 = skip phase 2 (1)
#   STRANGER_SERVICE_BRANCH  service branch the isolated stack builds (its .env default, develop) — a release
#                     branch proves that branch's lock
#
# The isolated stack never shares a name with the main one: every compose call runs in the checkout with its own
# .env, and nothing is torn down unless that .env carries the isolated project name.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
STACK=${ZENO_STACK:-s2}
OFFSET=${ZENO_PORT_OFFSET:-1000}
PROJECT=entirius-zeno-$STACK
WORK=$(realpath -m "${STRANGER_DIR:-.runner/stranger}")
BRANCH=${STRANGER_BRANCH:-$(git branch --show-current)}
OUT=$(realpath -m "${OUT:-todo/docs-launch/memo/stranger-run.json}")
KEEP=${KEEP:-0}
BUILD_ARGS=${BUILD_ARGS---no-cache --pull}
RECIPE=${RECIPE:-}
TESTS_FROM=${TESTS_FROM:-github}
BDD=${BDD:-0}
SERVICE_ONLY=${SERVICE_ONLY:-1}
CHECKOUT=$WORK/entirius-zeno
LOGS=$WORK/logs
STEPS_FILE=$WORK/steps.tsv
TESTS_CLONE=repos/tests/entirius-test-package-emporium
BARE_PORT=8900
PROFILES=(--profile infra --profile service --profile pwa --profile cms)
STRANGER_ENV=()

record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$STEPS_FILE"; }

fact() { # dotted key, text value → one line of the result
  local value=${2//$'\r'/}
  printf '%s\ttext\t%s\n' "$1" "${value//[$'\t\n']/ }" >>"$WORK/facts.tsv"
}

fact_json() { printf '%s\tjson\t%s\n' "$1" "$2" >>"$WORK/facts.tsv"; }

step() { # name, command… → runs it with output in logs/<name>.log, appends name, seconds and status
  local name=$1 started=$SECONDS rc errexit=$- log
  shift
  log=$LOGS/${name//\//-}.log
  echo "== $name"
  set +e
  ( set -e; "$@" ) >"$log" 2>&1
  rc=$?
  if [[ $errexit == *e* ]]; then set -e; fi
  record "$name" $((SECONDS - started)) "$( ((rc)) && echo failed || echo ok)"
  echo "   $((SECONDS - started))s $( ((rc)) && echo "FAILED — $log" || echo ok)"
  if ((rc)); then tail -20 "$log"; fi
  return "$rc"
}

stranger_env() { # PATH → a newcomer's shell: nothing of the operator's environment, no SSH, no git credentials
  local name
  STRANGER_ENV=(PATH="$1" GIT_SSH_COMMAND=false GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false)
  # HOME stays: the Docker CLI needs ~/.docker (contexts, credential store).
  for name in HOME USER LOGNAME LANG TERM XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG; do
    if [[ -v $name ]]; then STRANGER_ENV+=("$name=${!name}"); fi
  done
}

stranger() { env -i "${STRANGER_ENV[@]}" "$@"; }

in_checkout() { (cd "$CHECKOUT" && stranger "$@"); }

in_service() { (cd "$WORK/service" && stranger "$@"); }

stubs() { # gh and uv are developer tools: the documented path must not need them
  local tool
  mkdir -p "$WORK/bin"
  for tool in gh uv; do
    printf '#!/bin/sh\necho "%s: not available in the stranger run" >&2\nexit 127\n' "$tool" >"$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
  done
}

isolated() { grep -qx "COMPOSE_PROJECT_NAME=$PROJECT" "$CHECKOUT/.env" 2>/dev/null; }

env_value() { sed -n "s/^$1=//p" "$2" | tail -1; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" || true; }

remove_stack() { # containers, volumes, images and the checkout of the isolated stack; compose only with its own .env
  if [[ -f $CHECKOUT/.env ]]; then
    isolated || { echo "$CHECKOUT/.env is not the .env of $PROJECT — remove that stack by hand"; return 1; }
    in_checkout make clean || return 1 # the checkout stays: its .env is the only handle on a stack still up
  fi
  docker image ls --format '{{.Repository}}' | { grep "^$PROJECT-" || true; } | sort -u | xargs -r docker image rm || return 1
  rm -rf "$CHECKOUT"
}

copy_dirty() { # source tree, its clone → the uncommitted state: tracked changes as a patch, untracked files copied
  git -C "$1" diff HEAD --binary >"$WORK/dirty.patch"
  if [[ -s $WORK/dirty.patch ]]; then git -C "$2" apply "$WORK/dirty.patch"; fi
  (cd "$1" && git ls-files -o --exclude-standard -z | xargs -0 -r cp -p --parents -t "$2")
}

do_clone() { # leftovers of an earlier run first; the .env, recipe included, is written here so no later command can miss it
  remove_stack
  stranger git clone --branch "$BRANCH" "file://$ROOT" "$CHECKOUT"
  if [[ $DIRTY == true ]]; then copy_dirty "$ROOT" "$CHECKOUT"; fi
  in_checkout ZENO_STACK="$STACK" ZENO_PORT_OFFSET="$OFFSET" RECIPE="$RECIPE" make init
  if [[ -n ${STRANGER_SERVICE_BRANCH:-} ]]; then echo "SERVICE_BRANCH=$STRANGER_SERVICE_BRANCH" >>"$CHECKOUT/.env"; fi
  isolated
}

do_clone_tests() { # this tree's test package where `make clone-tests` looks for it: setup then clones nothing from GitHub
  local source=$ROOT/$TESTS_CLONE branch
  branch=$(git -C "$source" branch --show-current)
  [[ -n $branch ]] || { echo "$TESTS_CLONE is on a detached HEAD"; return 1; }
  stranger git clone --branch "$branch" "file://$source" "$CHECKOUT/$TESTS_CLONE"
  copy_dirty "$source" "$CHECKOUT/$TESTS_CLONE"
}

has_matrix() { # the storefront and the product API read the read model
  RECIPE=$RECIPE sh "$CHECKOUT/recipes/resolve.sh" apps | grep -qx django_matrix
}

do_setup() { # make setup on the isolated stack; its `setup: step` lines become the setup/<slug> rows
  local started=$SECONDS rc
  echo "== setup (log: $LOGS/setup.log)"
  set +e
  in_checkout ZENO_STACK="$STACK" ZENO_PORT_OFFSET="$OFFSET" BUILD_ARGS="$BUILD_ARGS" make setup \
    >"$LOGS/setup.log" 2>&1
  rc=$?
  set -e
  sed -nE 's#^setup: step ([a-z-]+) ([a-z]+) ([0-9]+)s$#setup/\1\t\3\t\2#p' "$LOGS/setup.log" >>"$STEPS_FILE"
  if ((rc)) && ! grep -q $'^setup/.*\tfailed$' "$STEPS_FILE"; then record setup $((SECONDS - started)) failed; fi
  echo "   $((SECONDS - started))s $( ((rc)) && echo FAILED || echo ok)"
  if ((rc)); then tail -20 "$LOGS/setup.log"; fi
  return "$rc"
}

make_result() { # result key, make target → the target's last output line; fails with the target
  local rc=0 out
  out=$(in_checkout make "$2" 2>&1) || rc=$?
  echo "$out"
  fact "result.$1" "$(tail -1 <<<"$out")"
  return "$rc"
}

seed_result() { # seed prints `SEED OK in <N>s`; a failed seed names its phase
  if grep -q '^SEED OK' "$LOGS/setup.log"; then echo "SEED OK"; else grep -m1 '^SEED FAILED' "$LOGS/setup.log" || true; fi
}

frontend() { # result key, port variable → HTTP code of GET /; dev servers compile on the first request
  local url code i
  url=http://localhost:$(env_value "$2" "$CHECKOUT/.env")/
  for i in $(seq 24); do
    code=$(http_code "$url")
    if [[ $code == 200 ]]; then break; fi
    sleep 5
  done
  fact_json "result.${1}_http" "$((10#$code))"
  [[ $code == 200 ]]
}

api_url() { echo "http://localhost:$(env_value SERVICE_PORT "$CHECKOUT/.env")/api"; }

products() { # products of the seeded channel in the read model
  local products
  products=$(curl -fsS "$(api_url)/matrix/v2/$(env_value PWA_CHANNEL "$CHECKOUT/.env")/products/?page_size=100" \
    | python3 -c 'import json, sys; print(len(json.load(sys.stdin)["results"]))')
  fact_json result.products "$products"
  ((products > 0))
}

munin_platform() { # the platform object of the module registry
  local platform
  platform=$(curl -fsS "$(api_url)/munin/v2/" | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["platform"]))')
  fact_json result.munin_platform "$platform"
}

access_installed() { # whether the booted service runs access: its INSTALLED_APPS, not the package alone
  local installed
  installed=$(in_checkout docker compose "${PROFILES[@]}" exec -T service python manage.py shell -c \
    'from django.conf import settings; print("access_installed", "django_access" in settings.INSTALLED_APPS)')
  fact_json isolation.access_installed "$(grep -q '^access_installed True' <<<"$installed" && echo true || echo false)"
}

toolbox_facts() { # the toolbox state setup met, and what a stack without it cannot do
  local reason
  reason=$(in_checkout make -s toolbox-check 2>&1 | head -1) || true
  fact toolbox.mode "$(sed -nE 's/^setup: done .* toolbox=([a-z]+) .*/\1/p' "$LOGS/setup.log")"
  fact toolbox.reason "$reason"
  if grep -q $'^setup/toolbox\t.*\tdegraded$' "$STEPS_FILE"; then
    echo "ai-toolbox: enabled but not answering — AI drafts fail, lead intel analyses fail and are retried," \
      "@needs-toolbox scenarios skipped" >>"$WORK/degraded.txt"
  fi
  if grep -q $'^setup/embed\t.*\tskipped$' "$STEPS_FILE"; then
    echo "embed: not started (EMBED=1 opts in) — image search falls back to text" >>"$WORK/degraded.txt"
  fi
}

do_verify() {
  toolbox_facts
  fact result.seed "$(seed_result)"
  if in_checkout docker compose "${PROFILES[@]}" exec -T service python -c 'import django_access'; then
    fact_json result.access true
  else
    fact_json result.access false
  fi
  access_installed
  make_result health health
  make_result smoke smoke
  frontend cms CMS_PORT
  munin_platform
  if ! has_matrix; then record verify/storefront 0 skipped; return 0; fi # the recipe has no read model
  frontend storefront PWA_PORT
  products
}

bdd_summary() { # behave log → {"features": {passed, failed, skipped}, "scenarios": {…}} or null; exit 0 = no scenario failed
  python3 - "$1" <<'PY'
import json
import re
import sys

counts = {}
for passed, kind, rest in re.findall(r"^(\d+) (feature|scenario)s? passed, (.*)$", open(sys.argv[1], errors="replace").read(), re.M):
    other = {name: int(number) for number, name in re.findall(r"(\d+) (\w+)", rest)}
    failed = sum(number for name, number in other.items() if name != "skipped")  # failed, error, hook_error
    counts[f"{kind}s"] = {"passed": int(passed), "failed": failed, "skipped": other.get("skipped", 0)}
print(json.dumps(counts if len(counts) == 2 else None))
sys.exit(len(counts) != 2 or counts["scenarios"]["failed"] > 0)
PY
}

do_bdd() { # the suite needs uv, so it gets the real PATH; a red suite is `degraded`, never a failed run
  local started=$SECONDS status=ok log=$LOGS/bdd.log summary
  echo "== bdd (log: $log)"
  in_checkout PATH="$PATH" make bdd >"$log" 2>&1 || true
  summary=$(bdd_summary "$log") || status=degraded
  fact_json result.bdd "$summary"
  record bdd $((SECONDS - started)) "$status"
  echo "   $((SECONDS - started))s $status"
}

git_version() { # versions key, git command prefix… → branch and short commit of a clone
  local key=$1 branch commit
  shift
  branch=$("$@" rev-parse --abbrev-ref HEAD)
  commit=$("$@" rev-parse --short HEAD)
  fact "versions.$key.branch" "$branch"
  fact "versions.$key.commit" "$commit"
}

do_versions() { # what the run actually built: the clones baked into the images, the test package, image sizes
  local pair size
  for pair in service:service cms:cms storefront:pwa; do
    if [[ $pair == storefront:* ]] && ! has_matrix; then continue; fi # no read model, no storefront container
    git_version "${pair%%:*}" in_checkout docker compose "${PROFILES[@]}" exec -T "${pair##*:}" git
    size=$(docker image ls --format '{{.Size}}' "$PROJECT-${pair##*:}" | head -1)
    fact "versions.images.${pair%%:*}" "$size"
  done
  git_version test_package git -C "$CHECKOUT/repos/tests/entirius-test-package-emporium"
}

do_rerun() { # the documented update path: pull, then setup again on warm caches, without reseeding
  in_checkout git pull --ff-only
  in_checkout ZENO_STACK="$STACK" ZENO_PORT_OFFSET="$OFFSET" BUILD_ARGS= make setup SEED=0
}

do_down() { # the containers' last words first: after a failed run they are the only trace of the cause
  if ! isolated; then return 0; fi
  in_checkout docker compose "${PROFILES[@]}" logs --no-color --tail 200 >"$LOGS/containers.log" 2>&1 || true
  in_checkout make down
}

phase_one() {
  step clone do_clone
  if [[ $TESTS_FROM == local ]]; then step clone-tests-local do_clone_tests; fi
  do_setup
  step verify do_verify
  if [[ $BDD == 1 ]]; then do_bdd; fi
  step versions do_versions
  step rerun do_rerun
}

teardown() { # both steps always run: a failed `down` must not leave the stack behind
  local rc=0
  step teardown/down do_down
  ((rc |= $?))
  step teardown/clean remove_stack
  ((rc |= $?))
  return "$rc"
}

module_probe() { # recorded, not required: the example settings enable no module, so a module endpoint may answer 404
  local code
  code=$(http_code "$1/api/munin/v2/")
  fact_json service_only.module_http "$((10#$code))"
  if [[ $code != 200 ]]; then fact service_only.reason "GET /api/munin/v2/ answered $code with the example settings"; fi
}

runserver() { # seconds to the first 200 on the admin login (60 s cap); the server stops with the step's subshell
  local url=http://127.0.0.1:$BARE_PORT rc=1 pid i
  if curl -s -o /dev/null --max-time 5 "$url/"; then echo "port $BARE_PORT is already in use"; return 1; fi
  (cd "$WORK/service" && exec setsid env -i "${STRANGER_ENV[@]}" uv run python manage.py runserver "127.0.0.1:$BARE_PORT") &
  pid=$!
  trap "kill -- -$pid 2>/dev/null" EXIT # expanded now: pid is gone when the subshell exits
  for i in $(seq 60); do
    if [[ $(http_code "$url/admin/login/") == 200 ]]; then rc=0; break; fi
    sleep 1
  done
  if ((rc == 0)); then module_probe "$url"; fi
  return "$rc"
}

service_only() { # the service repo alone, as its README documents it: uv, the example settings, SQLite
  local python
  rm -rf "$WORK/service"
  step service-only/clone stranger git clone --branch "$(env_value SERVICE_BRANCH .env.example)" \
    "https://github.com/entirius/$(env_value SERVICE .env.example).git" "$WORK/service"
  step service-only/uv-sync in_service uv sync --frozen
  step service-only/settings in_service cp main/settings_example.py main/settings_local.py
  step service-only/migrate in_service uv run python manage.py migrate
  step service-only/runserver runserver
  python=$(in_service uv run python --version)
  fact service_only.python "$python"
}

phase_two() { # phase 1 exit code → service_only.{status,reason}; uv comes from the real PATH here
  local reason="" rc=0
  if [[ $SERVICE_ONLY != 1 ]]; then reason="SERVICE_ONLY=$SERVICE_ONLY"; fi
  if (($1)); then reason="phase 1 failed"; fi
  if ! command -v uv >/dev/null; then reason="uv is not installed"; fi
  if [[ -z $reason ]]; then
    stranger_env "$PATH"
    ( set -e; STEPS_FILE=$WORK/service-steps.tsv; service_only )
    rc=$?
    if [[ $KEEP != 1 ]]; then rm -rf "$WORK/service"; fi
    fact service_only.status "$( ((rc)) && echo failed || echo ok)"
  else
    fact service_only.status skipped
    fact service_only.reason "$reason"
  fi
  return "$rc"
}

host_facts() {
  fact host.os "$(sed -n 's/^PRETTY_NAME="\(.*\)"$/\1/p' /etc/os-release 2>/dev/null) ($(uname -sr))"
  fact_json host.cpus "$(nproc)"
  fact_json host.mem_gb "$(awk '/MemTotal/ {printf "%d", $2 / 1048576 + 0.5}' /proc/meminfo)"
  fact host.docker "$(docker version --format '{{.Server.Version}}')"
  fact host.compose "$(docker compose version --short)"
  fact host.git "$(git --version | awk '{print $3}')"
}

run_facts() { # fixed keys first: a run that fails early still writes every one of them
  local key
  for key in result.{health,seed,smoke,cms_http,storefront_http,products,munin_platform,access,bdd} \
    isolation.access_installed toolbox.{mode,reason} \
    versions.{service,cms,storefront,test_package,images} service_only.{status,reason,python,module_http}; do
    fact_json "$key" null
  done
  fact run_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fact zeno_commit "$(git rev-parse --short "$BRANCH")"
  fact zeno_branch "$BRANCH"
  fact_json dirty "$DIRTY"
  fact source "file://$ROOT"
  fact isolation.stack "$STACK"
  fact_json isolation.port_offset "$OFFSET"
  fact isolation.project "$PROJECT"
  fact isolation.gh hidden
  fact isolation.uv hidden
  fact isolation.ssh disabled
  fact isolation.build_args "$BUILD_ARGS"
  fact isolation.recipe "$RECIPE"
  fact isolation.tests_from "$TESTS_FROM"
  fact_json service_only.port "$BARE_PORT"
}

prepare() {
  [[ $STACK =~ ^[a-z0-9]+$ ]] || { echo "stranger-run: ZENO_STACK must match [a-z0-9]+ (got '$STACK')"; exit 1; }
  [[ $OFFSET =~ ^[1-9][0-9]*$ ]] || { echo "stranger-run: ZENO_PORT_OFFSET must be a positive number"; exit 1; }
  [[ -n $BRANCH ]] || { echo "stranger-run: detached HEAD — set STRANGER_BRANCH"; exit 1; }
  [[ $TESTS_FROM == github || $TESTS_FROM == local ]] || { echo "stranger-run: TESTS_FROM must be github or local"; exit 1; }
  [[ $WORK != / && $CHECKOUT != "$ROOT" && $ROOT/ != "$CHECKOUT"/* ]] \
    || { echo "stranger-run: STRANGER_DIR must not hold this tree (got '$WORK')"; exit 1; }
  mkdir -p "$WORK" "$(dirname "$OUT")"
  rm -rf "$LOGS" "${WORK:?}/bin" "$WORK"/*.tsv "$WORK/degraded.txt" "$WORK/dirty.patch"
  mkdir -p "$LOGS"
  # Uncommitted work travels only with the branch it sits on.
  DIRTY=$([[ $BRANCH == "$(git branch --show-current)" && -n $(git status --porcelain) ]] && echo true || echo false)
  stubs
  stranger_env "$WORK/bin:$PATH"
  run_facts
  host_facts
}

write_json() {
  python3 - "$WORK" "$OUT" <<'EOF'
import json
import sys
from pathlib import Path

work, out = Path(sys.argv[1]), Path(sys.argv[2])


def rows(name, columns):
    path = work / name
    lines = path.read_text().split("\n") if path.exists() else []
    return [line.split("\t", columns - 1) for line in lines if line]


def steps(name):
    return [{"name": step, "seconds": int(seconds), "status": status} for step, seconds, status in rows(name, 3)]


doc = {}
for key, kind, value in rows("facts.tsv", 3):
    node = doc
    *parents, leaf = key.split(".")
    for part in parents:
        if not isinstance(node.get(part), dict):
            node[part] = {}
        node = node[part]
    node[leaf] = json.loads(value) if kind == "json" else value
doc["steps"] = steps("steps.tsv")
doc["service_only"]["steps"] = steps("service-steps.tsv")
doc["degraded"] = [line for (line,) in rows("degraded.txt", 1)]
out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
EOF
}

main() {
  local failed=0
  prepare
  set +e
  ( set -e; phase_one )
  local phase_one_rc=$?
  ((failed |= phase_one_rc))
  if [[ $KEEP == 1 ]]; then
    echo "KEEP=1 — the stack stays up: make -C $CHECKOUT urls"
  else
    teardown
    ((failed |= $?))
  fi
  phase_two "$phase_one_rc"
  ((failed |= $?))
  fact_json total_seconds "$SECONDS"
  write_json || failed=1
  if ((failed)); then echo "stranger-run: FAILED after ${SECONDS}s — $OUT, logs in $LOGS"; exit 1; fi
  echo "stranger-run: OK in ${SECONDS}s — $OUT"
}

main
