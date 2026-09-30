#!/usr/bin/env bash
# make runner-init — role profiles in ~/.claude-runner/<role> (coder, reviewer, triage, ux-tester). Idempotent.
# Copies nothing from ~/.claude; on RUNNER_SHARE_LOGIN=1 the OAuth credentials file is SYMLINKED into each
# profile (roles need auth; alternative: ANTHROPIC_API_KEY in scripts/dev-runner/.env).
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
# File protection needs Edit(path): the CLI ignores Write(path) in file permission checks (it warns on start).
DENY='["Bash(git push:*)", "Bash(git remote:*)", "Bash(git config:*)", "Bash(git tag:*)", "Read(//home/**/.ssh/**)", "Read(//home/**/.claude/**)", "Read(//home/**/.claude-runner/**)", "Read(./.env)", "Edit(./.env)", "Read(./scripts/dev-runner/.env)", "Edit(./scripts/dev-runner/**)"]'

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
  # Symlink, not copy: OAuth refresh tokens rotate — a stale copy cannot refresh (seen on the first night).
  if [[ ${RUNNER_SHARE_LOGIN:-0} == 1 && -f $HOME/.claude/.credentials.json ]]; then
    ln -sf "$HOME/.claude/.credentials.json" "$dir/.credentials.json"
  fi
  echo "profile $1: $dir"
}

# ux-tester drives a browser (MCP pinned at 0.0.81: `@latest` drifts to a Firefox build the host cache lacks;
# after a bump run `npx -y @playwright/mcp@<v> install-browser firefox`): profiles carry no MCP servers and deny ~/.claude/**, so the entry lives in the
# profile itself; --headless because the runner has no display. Its only write target is .runner/accept/.
# Deny rules are best-effort (a pattern cannot say "outside .runner/accept/", a shell finds other ways to write);
# the guarantee is accept.sh's scope check, which fails the run on any repo change. Playwright MCP tools and
# read-only Bash stay allowed. Never deny `./*`: rules match with gitignore semantics, so it covers `.runner/` and
# with it the report (deny beats allow).
UX_DENY='["Write(./repos/**)", "Edit(./repos/**)", "Write(./scripts/**)", "Edit(./scripts/**)",
  "Write(./docker/**)", "Edit(./docker/**)", "Write(./todo/**)", "Edit(./todo/**)", "Write(./roadmap/**)", "Edit(./roadmap/**)",
  "Write(./.runner/handoff/**)", "Edit(./.runner/handoff/**)", "NotebookEdit",
  "Bash(git commit:*)", "Bash(git add:*)", "Bash(git reset:*)", "Bash(git checkout:*)", "Bash(git restore:*)",
  "Bash(git stash:*)", "Bash(git rm:*)", "Bash(git mv:*)", "Bash(git apply:*)", "Bash(git merge:*)", "Bash(git rebase:*)",
  "Bash(rm:*)", "Bash(sed -i:*)", "Bash(tee:*)", "Bash(npm:*)", "Bash(uv:*)", "Bash(make:*)",
  "Bash(*> repos/*)", "Bash(*>repos/*)", "Bash(*>> repos/*)", "Bash(*> ./repos/*)", "Bash(*>./repos/*)"]'
ux_tester_extras() {
  local dir=$PROFILES_DIR/ux-tester mcp
  mcp='{"mcpServers": {"playwright-firefox": {"command": "npx", "args": ["-y", "@playwright/mcp@0.0.81", "--browser", "firefox", "--headless"]}}}'
  if [[ -f $dir/.claude.json ]]; then jq -s '.[0] * .[1]' "$dir/.claude.json" <(echo "$mcp") > "$dir/.claude.json.tmp" && mv "$dir/.claude.json.tmp" "$dir/.claude.json"
  else echo "$mcp" > "$dir/.claude.json"; fi
  jq --argjson deny "$UX_DENY" '.permissions.deny = ((.permissions.deny // []) + $deny | unique)
    | .permissions.allow = ((.permissions.allow // []) + ["Write(./.runner/accept/**)"] | unique)' "$dir/settings.json" > "$dir/settings.json.tmp" \
    && mv "$dir/settings.json.tmp" "$dir/settings.json"
}

# Plugins and rules follow the marketplace source. The entirius-core SessionStart hook syncs rules into
# $HOME/.claude only, which role profiles (CLAUDE_CONFIG_DIR) never see, and profiles never update their
# plugins on their own (coder sat on 3.0.0 entries with no files behind them). Skipped when the marketplace
# has no plugins/ dir (mock test copy).
plugin_names() { plugins_for "$1" | jq -r 'keys[] | sub("@entirius-code$"; "")'; }

update_plugins() { # role — install or update the role's plugins to the marketplace's current version
  local dir=$PROFILES_DIR/$1 p verb
  CLAUDE_CONFIG_DIR=$dir claude plugin marketplace update entirius-code >/dev/null
  for p in $(plugin_names "$1"); do
    verb=install
    jq -e --arg k "$p@entirius-code" '.plugins[$k]' "$dir/plugins/installed_plugins.json" >/dev/null 2>&1 && verb=update
    CLAUDE_CONFIG_DIR=$dir claude plugin "$verb" "$p@entirius-code" >/dev/null
  done
}

sync_rules() { # role — rules/global of the role's plugins → <profile>/rules/<plugin>/ (auto-loaded, Read deny does not apply)
  local dir=$PROFILES_DIR/$1 p
  for p in $(plugin_names "$1"); do
    rm -rf "$dir/rules/$p"
    [[ -d $MARKETPLACE_PATH/plugins/$p/rules/global ]] || continue
    mkdir -p "$dir/rules" && cp -r "$MARKETPLACE_PATH/plugins/$p/rules/global" "$dir/rules/$p"
  done
}

# rules/specific (on-demand) → .runner/rules-on-demand/<plugin>/: roles cannot Read ~/.claude/** or
# ~/.claude-runner/**, so skills' `~/.claude/rules-on-demand/…` references resolve here (roles/standards.md).
sync_rules_on_demand() {
  local target p
  target=$(cd "$RUNNER_DIR/../.." && pwd)/.runner/rules-on-demand
  rm -rf "$target" && mkdir -p "$target"
  for p in $(plugin_names coder); do
    [[ -d $MARKETPLACE_PATH/plugins/$p/rules/specific ]] && cp -r "$MARKETPLACE_PATH/plugins/$p/rules/specific" "$target/$p"
  done
  echo "on-demand rules: $target"
}

for role in coder reviewer triage ux-tester; do write_profile "$role"; done
ux_tester_extras
if [[ -d $MARKETPLACE_PATH/plugins ]]; then
  for role in coder reviewer triage ux-tester; do update_plugins "$role"; sync_rules "$role"; done
  sync_rules_on_demand
fi
[[ ${1:-} == --logout ]] && { rm -f "$PROFILES_DIR"/*/.credentials.json; echo "role credentials removed"; exit 0; }
if [[ -z ${ANTHROPIC_API_KEY:-} && ! -f $PROFILES_DIR/coder/.credentials.json ]]; then
  echo "NOTE: no auth for roles — set ANTHROPIC_API_KEY in scripts/dev-runner/.env or run with RUNNER_SHARE_LOGIN=1"
fi
