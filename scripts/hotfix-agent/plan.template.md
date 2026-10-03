STATUS: to-dev
STREAM: 9
REPOS: pwa/entirius-pwa-cms-hotfix
BRANCH: hotfix/@PLAN@
BUDGET_USD: 25
TIMEOUT_S: 5400

# Hotfix @PLAN@ — Redmine #@ISSUE@: @SUBJECT@

**Repo:** `repos/pwa/entirius-pwa-cms-hotfix` (a worktree of the CMS; this branch starts at `origin/master`, the last
release) · **Issue:** Redmine #@ISSUE@ · **Reporter:** @AUTHOR@

## Goal

The bug reported in Redmine #@ISSUE@ is fixed in the CMS with the smallest change that removes its cause, proven by a
test that fails before the fix. The agent's release script turns a `fixed` outcome into a patch release — you only fix,
test and describe.

## The report

`todo/hotfix/issues/@ISSUE@/issue.json` (subject, description in Polish, journals) and its attachments in the same
folder — open every screenshot with the Read tool before you decide anything.

> @DESCRIPTION@

## Steps

1. **Triage first.** Is this a bug of the admin CMS front end (`entirius-pwa-cms`) that you can reproduce? Look at the
   screenshots, find the screen and the code. If the cause is in a backend module, in data, in configuration, or the report
   is too vague to reproduce, stop: write the outcome file (below) with `needs-info`, `not-cms` or `cannot-reproduce` and
   a short Polish note for the reporter (what you checked, what exactly you need or where the fix belongs). No commits.
2. **Reproduce.** The zeno stack is up (service :8100, admin/admin123, channel `default-europe`). `:8180` serves
   `develop`; this worktree is `master` — run your own dev server of this worktree with
   `scripts/hotfix-agent/serve-and-test.sh --serve` (port 8183, Ctrl-C / kill when done) or run specs against it with
   `scripts/hotfix-agent/serve-and-test.sh tests/e2e/<spec>`. Never write data you did not create for the test; never
   change the admin password; never save, publish or delete real content.
3. **Fix** with a failing-first unit test (a mounted component, not a method called on a plain object). Smallest change;
   no refactor, no restyle, no dependency change, no version bump, no CHANGELOG edit (the release script writes both).
4. **Verify:** `npm run test:unit`, `npm run build`, `npm run lint:ui`, and the e2e spec(s) closest to the screen through
   `serve-and-test.sh`.
5. **Commit** on this branch; every message starts with `#@ISSUE@` (`#@ISSUE@ fix(<area>): …`); no Claude/Anthropic
   attribution.
6. **Outcome file** `todo/hotfix/issues/@ISSUE@/outcome.json` (UTF-8), always, as the last step:

```json
{
  "outcome": "fixed | needs-info | not-cms | cannot-reproduce",
  "cause_pl": "one or two Polish sentences: what was wrong (for the reporter)",
  "fix_pl": "one or two Polish sentences: what works now and how to check it",
  "changelog_en": "one English CHANGELOG line (### Fixed), user-facing, no file paths",
  "e2e_specs": ["tests/e2e/…spec.js"],
  "note_pl": "only for needs-info / not-cms / cannot-reproduce: the question or where the fix belongs"
}
```

## Basic rules & gotchas

- Work only in `repos/pwa/entirius-pwa-cms-hotfix`; never touch `repos/pwa/entirius-pwa-cms` (develop, served on :8180),
  other repos, zeno files or `.env`.
- No push, no PR, no tag, no release — the agent's release script does those after the gate and the review.
- If the fix needs a backend change, it is `not-cms` — say which module in `note_pl`.
- An outcome other than `fixed` fails the gate on purpose: it is a stop for the agent (it answers in Redmine), not a
  failure to retry — triage escalates, never steers a retry.

## Gate

```gate
python3 -c "import json,sys; o=json.load(open('todo/hotfix/issues/@ISSUE@/outcome.json')); sys.exit(0 if o.get('outcome')=='fixed' else 1)"
cd repos/pwa/entirius-pwa-cms-hotfix
npm run test:unit
npx vue-cli-service build --dest /tmp/cms-hotfix-gate-build
npm run lint:ui
../../../scripts/hotfix-agent/serve-and-test.sh --from-outcome ../../../todo/hotfix/issues/@ISSUE@/outcome.json
```

Then: `/code-review` on the plan diff → fix findings → re-run the gate → green.

## Prompt for the dev session

```
Execute hotfix plan @PLAN@ from todo/hotfix/dev-plans/@PLAN@-hotfix.md (Redmine #@ISSUE@).

Read the plan fully, then todo/hotfix/issues/@ISSUE@/issue.json and every attachment in that folder (open images with
the Read tool). Triage first — a report you cannot tie to CMS front-end code gets an outcome file and no commits.
Work in repos/pwa/entirius-pwa-cms-hotfix only. Failing-first test, smallest fix, the gate commands green, then the
outcome file. Commits start with #@ISSUE@. No push, no tag, no version bump, no CHANGELOG edit; no Claude attribution.
```
