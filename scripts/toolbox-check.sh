#!/bin/sh
# toolbox-check.sh — the AI toolbox zeno points at must answer for the test channel and expose
# ONLY `fake` models: a real model visible to that channel means BDD spends real money.
# Every AI_TOOLBOX_* value comes from the environment first, then .env (plain values), then the default;
# host.docker.internal is the containers' name for the host, so it becomes localhost here.
# AI_TOOLBOX_ENABLED = 0 / false / no / off (any case): one line "toolbox-check: disabled …", exit 0 —
# the toolbox is switched off on purpose and nothing is probed. Enabled: exit 1 on an empty key, on an
# HTTP answer other than 200 and on any model that is not `fake`.
set -eu

env_value() { # key → value from .env (last assignment wins), empty when absent
  [ -f .env ] || return 0
  sed -n "s/^$1=//p" .env | tail -1
}

setting() { # key, default → environment, then .env, then the default
  value=$(printenv "$1" || true)
  [ -n "$value" ] || value=$(env_value "$1")
  printf '%s' "${value:-$2}"
}

enabled=$(setting AI_TOOLBOX_ENABLED 1)
case $(printf '%s' "$enabled" | tr '[:upper:]' '[:lower:]') in
  0 | false | no | off)
    echo "toolbox-check: disabled (AI_TOOLBOX_ENABLED=$enabled) — AI features are switched off on purpose"
    exit 0
    ;;
esac

base=$(setting AI_TOOLBOX_BASE_URL http://host.docker.internal:8300 | sed 's#host\.docker\.internal#localhost#')
key=$(setting AI_TOOLBOX_API_KEY "")
channel=$(setting AI_TOOLBOX_CHANNEL zeno-test)
[ -n "$key" ] || { echo "toolbox-check: AI_TOOLBOX_API_KEY is empty in .env"; exit 1; }

url="$base/api/ai-completion/v2/admin/$channel/models/"
body=$(mktemp)
trap 'rm -f "$body"' EXIT
code=$(curl -sS -o "$body" -w '%{http_code}' --max-time 10 -H "X-API-Key: $key" "$url" 2>/dev/null) || code=000
[ "$code" = "200" ] || { echo "toolbox-check: GET $url -> HTTP $code (toolbox down or key rejected)"; exit 1; }

python3 - "$body" <<'EOF'
import json
import sys

try:
    with open(sys.argv[1]) as body:
        models = json.load(body)
except json.JSONDecodeError:
    sys.exit("toolbox-check: response is not JSON")
if not isinstance(models, list) or not models:
    sys.exit("toolbox-check: no models visible to the channel")
for model in models:
    print(f"  {model.get('provider')}/{model.get('model_id')}")
real = [m.get("model_id") for m in models if m.get("provider") != "fake"]
if real:
    sys.exit(f"toolbox-check: non-fake models visible to the test channel: {real}")
print("toolbox-check OK: fake models only")
EOF
