#!/usr/bin/env bash
# make runner-init — role profiles in ~/.claude-runner/<role> (coder, reviewer, triage). Idempotent.
# Copies nothing from ~/.claude except, on RUNNER_SHARE_LOGIN=1, the OAuth credentials file (roles need auth;
# alternative: ANTHROPIC_API_KEY in scripts/dev-runner/.env).
set -euo pipefail
RUNNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
if [[ -f $RUNNER_DIR/.env ]]; then source "$RUNNER_DIR/.env"; fi
: "${PROFILES_DIR:=$HOME/.claude-runner}" "${MARKETPLACE_PATH:=}"
[[ -n $MARKETPLACE_PATH ]] || MARKETPLACE_PATH=$(jq -r '.extraKnownMarketplaces["entirius-code"].source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
[[ -d $MARKETPLACE_PATH ]] || { echo "entirius-code marketplace path not found (set MARKETPLACE_PATH in .env)"; exit 1; }

plugins_for() { # role → JSON object of enabledPlugins
  case $1 in
    coder) echo '{"entirius-core@entirius-code": true, "entirius-backend@entirius-code": true, "entirius-pwa@entirius-code": true}' ;;
    *)     echo '{"entirius-core@entirius-code": true}' ;;
  esac
}

# Deny rules still apply under bypassPermissions — second layer behind the runner's post-hoc guards.
DENY='["Bash(git push:*)", "Bash(git remote:*)", "Bash(git config:*)", "Bash(git tag:*)", "Read(//home/**/.ssh/**)", "Read(//home/**/.claude/**)", "Read(//home/**/.claude-runner/**)", "Read(./.env)", "Write(./.env)", "Read(./scripts/dev-runner/.env)", "Write(./scripts/dev-runner/**)"]'

write_profile() { # role — merges over an existing settings.json (operator additions survive)
  local dir=$PROFILES_DIR/$1 gen
  mkdir -p "$dir" && chmod 700 "$dir"
  gen=$(jq -n --arg mp "$MARKETPLACE_PATH" --argjson plugins "$(plugins_for "$1")" --argjson deny "$DENY" '{
    permissions: {defaultMode: "bypassPermissions", deny: $deny},
    skipDangerousModePermissionPrompt: true,
    extraKnownMarketplaces: {"entirius-code": {source: {source: "directory", path: $mp}}},
    enabledPlugins: $plugins
  }')
  if [[ -f $dir/settings.json ]]; then jq -s '.[0] * .[1]' "$dir/settings.json" <(echo "$gen") > "$dir/settings.json.tmp" && mv "$dir/settings.json.tmp" "$dir/settings.json"
  else echo "$gen" > "$dir/settings.json"; fi
  if [[ ${RUNNER_SHARE_LOGIN:-0} == 1 && -f $HOME/.claude/.credentials.json ]]; then
    install -m 600 "$HOME/.claude/.credentials.json" "$dir/.credentials.json"
  fi
  echo "profile $1: $dir"
}

for role in coder reviewer triage; do write_profile "$role"; done
[[ ${1:-} == --logout ]] && { rm -f "$PROFILES_DIR"/*/.credentials.json; echo "role credentials removed"; exit 0; }
if [[ -z ${ANTHROPIC_API_KEY:-} && ! -f $PROFILES_DIR/coder/.credentials.json ]]; then
  echo "NOTE: no auth for roles — set ANTHROPIC_API_KEY in scripts/dev-runner/.env or run with RUNNER_SHARE_LOGIN=1"
fi
