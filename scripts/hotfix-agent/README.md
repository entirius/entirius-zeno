# CMS hotfix agent

Takes bug reports from the internal Redmine project **cms-blueprint** (URL in `~/.claude/redmine/credentials.yaml`) and releases CMS patch versions on GitHub
without a human in the loop — within the limits below.

```
Redmine issue (New / To Do, unassigned or ours)
  → take: note + status In Progress, fetch issue + attachments to todo/hotfix/issues/<id>/
  → plan todo/hotfix/dev-plans/<id>-hotfix.md (from plan.template.md)
  → dev-runner (coder → gate → reviewer) on branch hotfix/<id> in repos/pwa/entirius-pwa-cms-hotfix (from origin/master)
  → ready  → release.sh: next patch of the newest release, CHANGELOG, gitleaks, PR → master, green checks, merge, tag, GitHub release,
             PR → develop, Redmine note + To Deploy + assigned to the reporter, notify-send
  → parked → outcome needs-info / not-cms / cannot-reproduce: the coder's Polish note to the reporter (To Do, assigned
             to the reporter); anything else: handed to the operator (To Do, assigned to us)
```

| Command | Meaning |
|---|---|
| `make hotfix-agent` | loop in the background (tick every 10 min) |
| `make hotfix-once` | one tick in the foreground |
| `make hotfix-status` | plans, releases, last log lines |
| `make hotfix-stop` | stop after the current tick (`.runner/hotfix/STOP`) |

## Limits and rules

- One issue at a time; max **3 releases a day** (`MAX_RELEASES_PER_DAY`), **$25 per issue** (plan `BUDGET_USD`),
  $75 a day for the agent's runner (`runner.env`, own state in `.runner/hotfix`, separate from the main runner).
- Patch versions of the newest release only (after `v3.1.0` the next is `3.1.1`); a failing-first test and every PR check green before a merge.
- The coder never pushes; `release.sh` pushes over SSH (the gh token has no `workflow` scope) to
  `entirius/entirius-pwa-cms` only. Never GitLab cms-blueprint (a tag there deploys production).
- An issue is taken again only after someone else changes it (the stored copy is refreshed after each of our notes).
- Runs beside the main runner loop as runner stream 9 (`runner.env`): the hotfix worktree shares the CMS clone's hooks
  dir, so its push-guard marker must differ from the main runner's; a `ready` hotfix waits (logged each tick) while the
  main runner holds the CMS clone. Its scope check ignores every clone except its worktree; the zeno root stays watched.
- Operator authority for this pipeline: decided 2026-09-30 (autonomous hotfix releases on GitHub, To Deploy in Redmine).

## Files

| File | Role |
|---|---|
| `agent.sh` | loop, take, post-processing, Redmine notes |
| `redmine.py` | Redmine API (key from `~/.claude/redmine/credentials.yaml`, instance `redmine`) |
| `plan.template.md` | the hotfix plan the coder executes (triage → reproduce → fix → outcome.json) |
| `serve-and-test.sh` | the hotfix worktree on :8183 against the zeno stack + e2e specs |
| `release.sh` | deterministic release after `ready` |
| `runner.env` | the agent's runner settings on top of `scripts/dev-runner/.env` |

Logs: `.runner/hotfix/{agent,runner,release}.log`, releases `.runner/hotfix/releases.log`.
