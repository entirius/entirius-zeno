#!/bin/sh
#
# Smoke test — proves the stack actually boots and serves:
#   1. migrations consistent (no pending, no drift),
#   2. Django system check clean,
#   3. HTTP: admin login page, OpenAPI schema (imports every registered router),
#      Swagger UI, a real module API endpoint (munin) hitting the DB,
#   4. admin end-to-end: session login with a dev-only superuser.
#
# Works in both image mode (make up) and dev mode (make dev).
# Dev-only credentials, created/reset on every run: zeno-admin / zeno-admin-dev.
#
# Requires: docker compose stack running, curl.
#
set -e

PORT="${SERVICE_PORT:-8100}"
BASE="http://localhost:${PORT}"
COMPOSE="docker compose"
JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT
fail=0

say() { printf '  %-28s %s\n' "$1" "$2"; }

expect_http() {
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE$1")
    if [ "$code" = "$2" ]; then say "$1" "HTTP $code"; else say "$1" "FAIL (HTTP $code, expected $2)"; fail=1; fi
}

echo "== migrations =="
if $COMPOSE exec -T service python manage.py migrate --check >/dev/null 2>&1; then
    say "migrate --check" "no pending migrations"
else
    say "migrate --check" "FAIL (pending migrations — run 'make migrate')"; fail=1
fi
if $COMPOSE exec -T service python manage.py makemigrations --check --dry-run >/dev/null 2>&1; then
    say "makemigrations --check" "no model drift"
else
    say "makemigrations --check" "FAIL (model drift)"; fail=1
fi

echo "== system check =="
if $COMPOSE exec -T service python manage.py check >/dev/null 2>&1; then
    say "manage.py check" "no issues"
else
    say "manage.py check" "FAIL"; fail=1
fi

echo "== HTTP =="
expect_http "/admin/login/" 200
expect_http "/api/schema/" 200
expect_http "/api/schema/swagger-ui/" 200
expect_http "/api/munin/v2/" 200

echo "== admin login (session end-to-end) =="
$COMPOSE exec -T service python manage.py shell -c "
from django.contrib.auth import get_user_model
U = get_user_model()
u, _ = U.objects.update_or_create(username='zeno-admin', defaults={'is_staff': True, 'is_superuser': True})
u.set_password('zeno-admin-dev')
u.save()
" >/dev/null 2>&1 || { say "ensure superuser" "FAIL"; fail=1; }

curl -s -c "$JAR" -o /dev/null "$BASE/admin/login/"
CSRF=$(awk '$6 == "csrftoken" {print $7}' "$JAR")
code=$(curl -s -b "$JAR" -c "$JAR" -o /dev/null -w '%{http_code}' \
    -H "Referer: $BASE/admin/login/" \
    --data-urlencode "username=zeno-admin" \
    --data-urlencode "password=zeno-admin-dev" \
    --data-urlencode "csrfmiddlewaretoken=$CSRF" \
    "$BASE/admin/login/?next=/admin/")
if [ "$code" = "302" ]; then say "POST /admin/login/" "HTTP 302 (authenticated)"; else say "POST /admin/login/" "FAIL (HTTP $code)"; fail=1; fi
code=$(curl -s -b "$JAR" -o /dev/null -w '%{http_code}' "$BASE/admin/")
if [ "$code" = "200" ]; then say "GET /admin/ (session)" "HTTP 200"; else say "GET /admin/ (session)" "FAIL (HTTP $code)"; fail=1; fi

if [ "$fail" -eq 0 ]; then echo "Smoke OK"; else echo "Smoke FAILED"; exit 1; fi
