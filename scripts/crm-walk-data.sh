#!/usr/bin/env bash
# Data for a walk through the Leads CRM on the dev stack: a fresh seed, one run of the @crm features (replies of
# every type, drafts to approve, deals, two mailboxes), six tasks for the salesperson `manager` and a send window
# that is open all day. Dev credentials only. Takes about 15 minutes; run it again for a clean start.
#
#   scripts/crm-walk-data.sh            # seed + @crm + tasks + send window
#   SEED=0 scripts/crm-walk-data.sh     # keep the database: tasks and send window only
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=$(grep -E "^SERVICE_PORT=" .env 2>/dev/null | tail -1 | cut -d= -f2)
API=http://localhost:${PORT:-8100}
CHANNEL=default-europe

if [ "${SEED:-1}" = 1 ]; then
  echo "== seed $(date +%T)"
  mkdir -p build
  make seed > build/crm-walk-seed.log 2>&1
  tail -1 build/crm-walk-seed.log
  grep -q "SEED OK" build/crm-walk-seed.log || { echo "seed failed: see build/crm-walk-seed.log"; exit 1; }
  echo "== bdd @crm $(date +%T)"
  make bdd TAGS=@crm > build/crm-walk-bdd.log 2>&1
  grep -E "scenarios passed" build/crm-walk-bdd.log | tail -1
fi

token() {
  curl -fsS "$API/api/token/" -H 'content-type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$2\"}" | jq -r .access
}
MANAGER=$(token manager manager123) || { echo "no token for manager: is the stack up and seeded?"; exit 1; }
ADMIN=$(token admin admin123)
AUTH="Authorization: Bearer $MANAGER"

company_id() {
  curl -s -H "$AUTH" "$API/api/leads/v2/admin/$CHANNEL/companies/?search=$(jq -rn --arg s "$1" '$s|@uri')" |
    jq -r --arg n "$1" '[.results[] | select(.name == $n)][0].id'
}
C2=$(company_id "Example Shop 2"); C3=$(company_id "Example Shop 3"); C4=$(company_id "Example Shop 4")
DEAL=$(curl -s -H "$AUTH" "$API/api/leads/v2/admin/$CHANNEL/deals/?kind=open" | jq -c '.results[0] // {}')
DEAL_ID=$(echo "$DEAL" | jq -r '.id // empty'); DEAL_TITLE=$(echo "$DEAL" | jq -r '.subject_label // .title // empty')

TODAY=$(date +%F); TZ_OFFSET=$(date +%:z)
task() { # title kind due subject_ref subject_label note
  curl -s -o /dev/null -w "%{http_code} " -H "$AUTH" -H 'content-type: application/json' \
    -d "$(jq -n --arg t "$1" --arg k "$2" --arg d "$3" --arg s "$4" --arg l "$5" --arg n "$6" \
      '{title: $t, kind: $k, due_at: $d, subject_ref: $s, subject_label: $l, note: $n}')" \
    "$API/api/todo/v2/admin/$CHANNEL/tasks/"
}
echo "== tasks for manager"
task "Call back about the offer" phone "$(date -d '2 days ago' +%F)T10:00:00$TZ_OFFSET" "leads.Company:$C4" "Example Shop 4" "Asked for a call after the trade fair."
task "Send the price list" mail "$(date -d yesterday +%F)T15:00:00$TZ_OFFSET" "leads.Company:$C3" "Example Shop 3" ""
task "Check the shop's new catalogue" todo "${TODAY}T09:00:00$TZ_OFFSET" "leads.Company:$C2" "Example Shop 2" ""
task "Confirm the meeting time" phone "${TODAY}T23:30:00$TZ_OFFSET" "leads.Company:$C4" "Example Shop 4" ""
task "Demo meeting" meeting "$(date -d '+3 days' +%F)T10:00:00$TZ_OFFSET" "leads.Company:$C2" "Example Shop 2" ""
[ -n "$DEAL_ID" ] && task "Send the contract draft" mail "${TODAY}T23:45:00$TZ_OFFSET" "leads.Deal:$DEAL_ID" "$DEAL_TITLE" ""
echo

echo "== send window open all day"
curl -s -X PUT -H "Authorization: Bearer $ADMIN" -H 'content-type: application/json' \
  -d '{"business_days_only":false,"daily_cap":60,"spread":false,"windows":[{"order":0,"start_time":"00:00:00","end_time":"23:59:00"}]}' \
  "$API/api/communicator/v2/admin/$CHANNEL/policy/" | jq -c '{business_days_only, daily_cap, windows}'

make -s health | tail -1
echo "== done $(date +%T): log in to the CMS as manager / manager123 and open /leads"
