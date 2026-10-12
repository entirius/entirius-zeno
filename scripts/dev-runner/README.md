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
| `make runner-init` | profiles `~/.claude-runner/{coder,reviewer,triage,ux-tester}` (plugins core+backend+pwa / core, updated to the marketplace version); global rules copied into each profile, on-demand rules into `.runner/rules-on-demand/`; idempotent — rerun after every entirius-code release |
| `make runner-test` | mock suite (zero tokens) — must be green before any live call |
| `make runner-dry PLANS=…` | which plan would run; changes nothing |
| `make runner-once PLANS=…` | one tick (default `PLANS=todo/product-lookup-dedup/dev-plans`) |
| `make runner-loop PLANS=…` | tick every minute (`LOOP_SLEEP`, default 60 s) under `systemd-inhibit`; ends when `STOP` exists |
| `make runner-status PLANS=…` | plans table, journal tail, today's spend |
| `make runner-stop` | `touch scripts/dev-runner/STOP` (the runner never removes it) |

## Streams (parallel loops)

`make runner-loop PLANS=… STREAM=2` runs a second loop over the same plans dir. A plan belongs to the stream in its
`STREAM:` header (default 1); a loop picks and resumes only its own plans. Each stream has its own lock
(`.runner/lock-s2`) and role workdirs (`.runner/work-s2`); spend, `DAILY_CAP_USD` and `STOP` are shared.

- Stream 2 works in a git worktree of stream 1's clone, on its own branch — its plans name it in `REPOS`
  (`pwa/entirius-pwa-cms-s2`), `BRANCH`, the gate paths and any port (its own CMS dev server). Create it once:
  `git -C repos/pwa/entirius-pwa-cms worktree add -b feature/<topic>-s2 ../entirius-pwa-cms-s2 feature/<topic>`,
  then `npm ci` in it.
- Stream sync: at a plan's first claim, every `DEPENDS` plan finished on another stream's branch is merged in
  (its recorded done commit), before the base SHA is taken — the review window never contains the merged work.
  A conflict aborts the merge and parks the plan (`stream sync: merging plan X conflicts`); merge by hand, then
  set the plan back to `to-dev`. `CHANGELOG.md merge=union` in the clone's `.git/info/attributes` keeps the
  usual changelog collision out of it.
- Scope: each stream ignores the `REPOS` of the other stream's plans. The `pre-push` guard lives in the shared
  hooks dir with one marker per stream; the last stream out removes it.
- Split plans so streams never share a file tree they both edit: disjoint views/panels per stream, shared
  components on one stream with the other depending on it.

## Setup

1. `cp scripts/dev-runner/.env.example scripts/dev-runner/.env` — models, caps, `CLAUDE_CLI_PIN`.
2. Auth for roles: `ANTHROPIC_API_KEY` in `.env`, or `RUNNER_SHARE_LOGIN=1 make runner-init` (symlinks the
   operator's OAuth credentials file into each profile — a copy goes stale when the refresh token rotates;
   nothing else is shared from `~/.claude`). Claude CLI ≥ 2.1.282 replaces that symlink with a file on refresh:
   run `scripts/dev-runner/creds-guard.sh &` next to an overnight loop (re-links, keeps the newest token).
3. `make runner-test` green → live smoke `scripts/dev-runner/tests/live-smoke.sh` (~$2: caps 1/0.5/0.5) → remove `STOP`.
4. Stack: `make dev` up, `make seed` baseline (gates run on the live stack).
5. Planning plans (they write plans, commit nothing): header `NO_COMMIT_OK: true`; the gate checks their output.

## Acceptance (ux-tester)

`make e2e-accept` → `accept.sh`: plan-free (no pick, no scope snapshot, no commits). It puts one draft for
`example-shop-5.test` into the review queue (communicator test endpoint), builds
`.runner/accept/<ts>/ux-tester-prompt.md` = `roles/ux-tester.md` + `prompts/accept/leads-funnel.md` + fenced
`make urls` + CMS login from the zeno `.env`, runs `run_role_live ux-tester` capped at `UX_CAP_USD` (model
`UX_MODEL`) and books the cost. Exit 1 when `report.md` is missing or `## Blockers` has a list item.
The profile gets a `playwright-firefox` MCP entry (`--headless`) in its own `.claude.json` and
`Write(./.runner/accept/**)` from `make runner-init`. Run after `make e2e-funnel` on a fresh seed.

## Plan contract

Header (first 12 lines, `KEY: value`): `STATUS`, `KIND`, `DEPENDS`, `REPOS` (comma list relative to zeno root,
`.` = zeno), `BRANCH`, `BUDGET_USD`, `TIMEOUT_S`, optional `STREAM` (default 1), `NO_COMMIT_OK: true` / `COMMIT_ANY: true` (≥1 repo with commits). One fenced ```` ```gate ````
block = acceptance, run from the zeno root with `set -euo pipefail` (missing → `gates/DEFAULT.sh`); a line starting
with `! ` is a must-not-match check (bash alone ignores `!` under `set -e`, so the runner rewrites it): exit 1 passes,
exit 0 (matched) or ≥ 2 (the check errored, e.g. a missing path) fails the gate. A
"## Prompt for the dev session" fenced block feeds the coder. Header lint at claim: numeric caps, safe branch/ids,
no `..`/absolute `REPOS`. `STATUS:` in the plan file is authoritative; the `00-README.md` table is mirrored.

## Guards (script + profile deny rules — detection and tripwires, not a sandbox)

- Push: `pre-push` hook exiting 1 in every `REPOS` repo while claimed (operator hook restored, also on
  crash via trap) + profile deny `Bash(git push:*)`/`git remote`/`git config`. The hard layer stays the
  operator's `remote.origin.pushurl=DISABLED` on every repo the runner may touch — keep it set.
- Scope: snapshot at claim (porcelain + HEAD of every `repos/*/*` and zeno root, hash of the gitignored zeno
  `.env`); any change outside `REPOS` after a role → `parked`; missing
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
- Checkpoint plans (`KIND: checkpoint`) get at least `CHECKPOINT_MIN_CAP_USD` (default 90): the panel reviews a whole
  phase in diff chunks and a lower `BUDGET_USD` parks on review cost alone.
- `PREFLIGHT_CMD` (runner `.env`, run from the zeno root, e.g. `make -s health && make -s toolbox-check`): red → the
  tick picks but never claims, so an infrastructure outage costs no attempt and parks nothing; one desktop notice per
  outage. Every park sends a desktop notice too (`notify-send`, best effort).
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

Prompts reach `claude -p` on stdin (a checkpoint diff exceeds the argv limit); the live smoke proves the path.

## State

`.runner/handoff/<topic>-<id>/attempt-N/` (prompts, out.json, stderr, gate.log, patches, findings, DECISION,
memo), `costs.log`, `steer.txt`, `plan.md`+`plan.sha` (claim snapshot), `scope-base.txt`; archive after finish.
`.runner/bases/<topic>-<id>-<repo>.sha` = diff anchor per plan (kept across re-runs). `.runner/lock` (flock).
`JOURNAL.md` in the plans folder: `<date> | <plan> | OK|PARKED|STEER|WIP | note`.

Steer a parked plan: fix/edit the plan, set `STATUS: to-dev`, next tick re-runs it (handoff is reset).
