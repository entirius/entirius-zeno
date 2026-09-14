#!/usr/bin/env bash
# make e2e-accept — mode C of the leads funnel: one ux-tester session walks the CMS on phone and desktop and
# writes .runner/accept/<ts>/report.md + screenshots. Plan-free: no pick_plan, no scope snapshot, no commits;
# books its cost only. Exit 1 when the report is missing or its "## Blockers" section has a list item.
set -euo pipefail
RUNNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$RUNNER_DIR/lib.sh"
PLANS_DIR=${PLANS_DIR:-todo/leads-platform/dev-plans} load_env
API=http://localhost:$(sed -n 's/^SERVICE_PORT=//p' "$ZENO_ROOT/.env" 2>/dev/null | tail -1 | grep . || echo 8100)
CHANNEL=default-europe
ACCEPT_DOMAIN=example-shop-5.test

env_value() { # key default → value from the zeno .env (never sourced: it is not ours to execute)
  local v; v=$(sed -n "s/^$1=//p" "$ZENO_ROOT/.env" 2>/dev/null | tail -1)
  echo "${v:-$2}"
}

blockers_found() { # report → 0 when the Blockers section holds at least one list item
  awk '/^## /{on = ($0 ~ /^## Blockers/)} on && /^[[:space:]]*[-*] /{found=1} END{exit !found}' "$1"
}

api_token() { # → admin JWT for the zeno service
  curl -fsS "$API/api/token/" -H 'content-type: application/json' \
    -d "$(jq -n --arg u "$(env_value ADMIN_USERNAME admin)" --arg p "$(env_value ADMIN_PASSWORD admin123)" '{username: $u, password: $p}')" | jq -r .access
}

setup_draft() { # → company name; one review_required draft on the seeded funnel company (test endpoint)
  local token company body
  token=$(api_token)
  company=$(curl -fsS -H "Authorization: Bearer $token" "$API/api/leads/v2/admin/$CHANNEL/companies/?search=$ACCEPT_DOMAIN" | jq -c '.results[0]')
  body=$(jq -n --argjson c "$company" --arg email "accept-$(date +%s)@$ACCEPT_DOMAIN" '{template_key: "followup",
    recipient: {email: $email, first_name: "Anna", language: "pl", legal_footer: "Administrator danych: Example Seller."},
    context: {company_name: $c.name, body: "Acceptance run draft."}, subject_ref: "leads.Company:\($c.id)", requires_review: true}')
  curl -fsS -o /dev/null -H "Authorization: Bearer $token" -H 'content-type: application/json' \
    -d "$body" "$API/api/communicator/v2/admin/$CHANNEL/test/communicate/"
  jq -r .name <<<"$company"
}

build_accept_prompt() { # run-dir company → stdout
  cat "$RUNNER_DIR/roles/ux-tester.md"
  printf '\n'; cat "$RUNNER_DIR/prompts/accept/leads-funnel.md"
  printf '\n---\n## Run context\n- Run directory (report + screenshots): %s\n- Zeno root: %s\n- Setup company: %s\n' "$1" "$ZENO_ROOT" "$2"
  printf -- '- CMS login: %s / %s\n' "$(env_value ADMIN_USERNAME admin)" "$(env_value ADMIN_PASSWORD admin123)"
  untrusted "URLs (make urls)" "$(make -s -C "$ZENO_ROOT" urls 2>&1)"
  # shellcheck disable=SC2016
  printf '\n### When done\nLAST action: `touch %s/.runner-done` — only after report.md is written.\n' "$(role_workdir ux-tester)"
}

main() {
  local dir rc=0
  dir=$STATE_DIR/accept/$(date +%Y%m%d-%H%M%S)
  mkdir -p "$dir" "$(role_workdir ux-tester)"
  build_accept_prompt "$dir" "$(setup_draft)" > "$dir/ux-tester-prompt.md"
  run_role_live ux-tester "$dir" "$UX_CAP_USD" "" "$dir/ux-tester-prompt.md" || rc=$?
  record_cost ux-tester "$dir" "$UX_CAP_USD"
  [[ -f $dir/report.md ]] || { log "no report in $dir (role rc=$rc)"; exit 1; }
  if blockers_found "$dir/report.md"; then log "blockers in $dir/report.md"; exit 1; fi
  log "accepted: $dir/report.md"
}

main "$@"
