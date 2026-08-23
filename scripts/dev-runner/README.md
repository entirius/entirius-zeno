# dev-runner — operator runbook

Executes `todo/<topic>/dev-plans/` one plan per tick with fresh `claude -p` roles. No application code here.
Design: `roadmap/00002-dev-runner/v1/notes.md`. Plans of the runner itself: `todo/dev-runner/dev-plans/`.

## Loop

```
pick plan (first in-dev = stale claim, else lowest to-dev with DEPENDS ready)
→ claim: STATUS in-dev, BRANCH in every REPOS repo (from develop), base SHA + scope snapshot, push hook
→ coder (Opus) → gate block (script, zero LLM)
   green → reviewer (Fable 5) → findings.json → critical? one fix round → gitleaks → STATUS ready, JOURNAL OK
   red   → triage (Fable 5) → DECISION retry+steer | escalate → next attempt ≤ MAX_ATTEMPTS → STATUS parked
```

## Targets

| Target | Meaning |
|---|---|
| `make runner-init` | profiles `~/.claude-runner/{coder,reviewer,triage}` (plugins core+backend+pwa / core); idempotent |
| `make runner-test` | mock suite (zero tokens) — must be green before any live call |
| `make runner-dry PLANS=…` | which plan would run; changes nothing |
| `make runner-once PLANS=…` | one tick (default `PLANS=todo/product-lookup-dedup/dev-plans`) |
| `make runner-loop PLANS=…` | tick every 5 min under `systemd-inhibit`; ends when `STOP` exists |
| `make runner-status PLANS=…` | plans table, journal tail, today's spend |
| `make runner-stop` | `touch scripts/dev-runner/STOP` (the runner never removes it) |

## Setup

1. `cp scripts/dev-runner/.env.example scripts/dev-runner/.env` — models, caps, `CLAUDE_CLI_PIN`.
2. Auth for roles: `ANTHROPIC_API_KEY` in `.env`, or `RUNNER_SHARE_LOGIN=1 make runner-init` (symlinks the
   operator's OAuth credentials file into each profile — a copy goes stale when the refresh token rotates;
   nothing else is shared from `~/.claude`).
3. `make runner-test` green → live smoke `scripts/dev-runner/tests/live-smoke.sh` (~$2: caps 1/0.5/0.5) → remove `STOP`.
4. Stack: `make dev` up, `make seed` baseline (gates run on the live stack).

## Plan contract

Header (first 12 lines, `KEY: value`): `STATUS`, `KIND`, `DEPENDS`, `REPOS` (comma list relative to zeno root,
`.` = zeno), `BRANCH`, `BUDGET_USD`, `TIMEOUT_S`, optional `NO_COMMIT_OK: true` / `COMMIT_ANY: true` (≥1 repo with commits). One fenced ```` ```gate ````
block = acceptance, run from the zeno root with `set -euo pipefail` (missing → `gates/DEFAULT.sh`). A
"## Prompt for the dev session" fenced block feeds the coder. Header lint at claim: numeric caps, safe branch/ids,
no `..`/absolute `REPOS`. `STATUS:` in the plan file is authoritative; the `00-README.md` table is mirrored.

## Guards (script + profile deny rules — detection and tripwires, not a sandbox)

- Push: `pre-push` hook exiting 1 in every `REPOS` repo while claimed (operator hook restored, also on
  crash via trap) + profile deny `Bash(git push:*)`/`git remote`/`git config`. The hard layer stays the
  operator's `remote.origin.pushurl=DISABLED` on every repo the runner may touch — keep it set.
- Scope: snapshot at claim (porcelain + HEAD of every `repos/*/*` and zeno root, hashes of the gitignored
  `.env` and runner `.env`); any change outside `REPOS` after a role → `parked`; missing
  snapshot = fail closed. Invisible: paths outside those repos (`$HOME`, `/tmp`, `todo/`, `.runner/`) —
  profile deny covers `~/.ssh`, `~/.claude*`, `.env`, `scripts/dev-runner/`.
- Plan integrity: headers + gate are read from a copy taken at claim; the live plan must hash the same
  before `ready` (a coder cannot rewrite its own gate).
- Dirty tree at claim → `parked` (never stash; on resume only leftovers on `BRANCH` are tolerated);
  zeno itself is never switched — be on `BRANCH` already.
- gitleaks before `ready` on `<first base>..HEAD` per repo with zeno's canonical `.gitleaks.toml`
  (never the reviewed repo's config); gitleaks missing = no `ready`.
- Budgets: `--max-budget-usd` per role call, `BUDGET_USD` per plan, `DAILY_CAP_USD` per day
  (`.runner/spend-<date>.log`); a role without a parsable result books its cap, never $0.
- Watchdog: `TIMEOUT_S` per role/gate, process-group kill; `CLAUDE_CLI_PIN` mismatch → `STOP` + exit 1.
- Reviewer without a parsable `findings.json` → one re-prompt, then `parked` (never counted as clean).
- Untrusted text (gate.log, steer, findings) is nonce-fenced in prompts and labelled as data.
- `scripts/dev-runner/init.sh --logout` removes copied role credentials (`RUNNER_SHARE_LOGIN=1`).

## Checkpoints

A plan with `KIND: checkpoint` + `FROM: <id>` reviews `runner/done-<FROM>..HEAD` in every `REPOS` repo
(tags are set locally at each plan's finalize and verified against the SHA recorded in `.runner/bases/` — a
moved tag parks the checkpoint). The panel runs in the reviewer profile with `guard_scope`, budget and
"no commits during the review" checks. Three independent reviewer calls (contract / tests /
regressions, `prompts/cr/panel-base.md`); a reviewer failing twice = inconclusive → `parked`. Criticals →
`FIX-<id>-checkpoint.md` seeded (`to-dev`, default gate, no gate block — panel text never reaches bash) and the
checkpoint's `DEPENDS` gains it (the checkpoint re-runs after the FIX is `ready`); majors → `BG-<id>-checkpoint.md`
(no dependency). `FIX-`/`BG-` plans run after numbered plans, ordered by creation. Checkpoints need no commits.

## State

`.runner/handoff/<topic>-<id>/attempt-N/` (prompts, out.json, stderr, gate.log, patches, findings, DECISION,
memo), `costs.log`, `steer.txt`, `plan.md`+`plan.sha` (claim snapshot), `scope-base.txt`; archive after finish.
`.runner/bases/<topic>-<id>-<repo>.sha` = diff anchor per plan (kept across re-runs). `.runner/lock` (flock).
`JOURNAL.md` in the plans folder: `<date> | <plan> | OK|PARKED|STEER|WIP | note`.

Steer a parked plan: fix/edit the plan, set `STATUS: to-dev`, next tick re-runs it (handoff is reset).
