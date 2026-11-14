# How to test the Leads CRM from `develop`

The Leads CRM landed on `develop` on 2026-11-14 in eight repositories. It is not released: no module version on
PyPI, no CMS release, no page on docs.entirius.com. This guide is the hand-over for the test round that comes
before all of that: how to stand the stack up from the `develop` branches, what changed, what to walk through and
in which order, and what happens with the findings. The product documentation is written after this round is
accepted, not before.

Testing the platform in general: [howto-test.md](howto-test.md). Dev mode and commands:
[howto-develop.md](howto-develop.md).

## For the agent session that guides the test

Do it in this order and do not skip ahead:

1. Read this file whole, then `AGENTS.md` (Commands, Green baselines, Where errors hide, Gotchas).
2. Stand the stack up ([Setup](#setup)) and run the checks at its end. Do not start the walk on a red check.
3. Tell the tester what changed ([What changed](#what-changed)) in a few sentences per area, in their language.
4. Walk the [Scenario](#scenario) part by part. For every step say what to do and what should happen, wait for the
   tester's result, and write down every deviation with the screen, the step and what was seen. Do not click for
   the tester; a step you check yourself (an API answer, a mail in the sandbox) is fine.
5. For a deviation: reproduce it, find the repository that owns the fix (`AGENTS.md` § Fix ownership), propose the
   fix and wait for the tester's word before changing code. A fix is a branch from `develop` and a pull request
   to `develop` in that repository; commit and push only when the tester says so.
6. Close with one list: steps accepted, findings, fixes with their pull requests, questions for the owner. When
   the tester accepts the panel, the next step is [After acceptance](#after-acceptance).

Dev logins are public defaults of the harness and only work on a local stack. Nothing in this stack sends mail
outside the machine.

## Setup

Requirements are those of the [README](../README.md#requirements): Docker with Compose v2, git, GNU make,
Python 3, curl, bash, `jq`, `uv`, and `gh` authenticated for the `entirius` organization. The stack with the CMS dev
server is memory-hungry: a worker killed for memory (`docker ps -a` shows exit 137) looks like failing BDD scenarios.

```bash
git clone https://github.com/entirius/entirius-zeno.git   # or: git switch develop && git pull
cd entirius-zeno
make setup DEV=1 REFS=develop     # every clone on develop, dev mounts, CMS with hot reload, seed
scripts/crm-walk-data.sh          # fresh seed, one @crm run, tasks for `manager`, send window open (~15 min)
```

`make setup DEV=1 REFS=develop` clones every platform repository, `entirius-django-todo` among them (new with
this work), puts each clean clone on `develop` and mounts the clones into the service, so the service runs the
module code of `develop` and not the versions of its lock. In an existing checkout the same command updates the
clones; a clone with local changes is left alone and named.

Checks, all must hold before the walk:

| Check | Expected |
|---|---|
| `make health` | `All services OK` |
| `scripts/crm-walk-data.sh` | `SEED OK`, `72 scenarios passed, 0 failed, 1 skipped`, six `201`, `All services OK` |
| CMS at http://localhost:8180/leads as `manager` / `manager123` | Today with five tasks under "Due now" |
| `grep -H __version__ repos/django/entirius-django-{leads,communicator,todo,notifications}/src/*/__init__.py` | leads 0.5.0, communicator 0.5.0, todo 0.1.0, notifications 0.3.0 |

If the Leads menu shows only the old screens, the module versions are below 0.5.0: a clone is not on `develop`
(`git -C repos/django/entirius-django-leads status`).

The AI toolbox is optional for this round. With `AI_TOOLBOX_ENABLED=0` (the default) every step of the scenario
works; "Rewrite" on a draft and drafts written by a rule are refused with a sentence that says so. With the fake
toolbox up (`make toolbox-check` green) they answer with placeholder text. Never point the stack at a real model
for this.

A clean start at any time: `scripts/crm-walk-data.sh` again. Tasks and the send window only, on the data that is
there: `SEED=0 scripts/crm-walk-data.sh`.

| What | Where |
|---|---|
| Panel | http://localhost:8180/leads |
| Salesperson | `manager` / `manager123` (Anna Kowalska, mailbox `sales1@greenmail.test`) |
| Second salesperson | `editor` / `editor123` (Piotr Lis, mailbox `sales2@greenmail.test`) |
| Administrator | `admin` / `admin123` |
| Read-only | `viewer` / `viewer123` |
| Sent mail | `make mail-look`, then http://localhost:8125 |
| Interface language | user menu, top right: English / Polski (the scenario uses the English labels) |
| Phone | the browser's device view at 390 × 844 |

## What changed

A small CRM on top of the leads and communicator modules: a salesperson gets a day to work through, a company
and its people to write to from their own mailbox, tasks, deals, and replies that are sorted for them. An
administrator sets the process up and watches the sending.

| Repository | What it brings |
|---|---|
| `entirius-django-leads` 0.5.0 | company owners and the company list, contacts with the outreach gate (who may be mailed and why not), deals with stages, a board and an archive, tasks created from replies, import with rules, funnel reports |
| `entirius-django-communicator` 0.5.0 | a mailbox per salesperson with warm-up, caps and an automatic pause, send windows, follow-up sequences, reply types with a plan each, approvals, the conversation timeline, the recipient check before every approval and delivery |
| `entirius-django-todo` 0.1.0 (new) | tasks about any object, with a due date, a today list and reminders |
| `entirius-django-notifications` 0.3.0 | the notification kinds and titles of the CRM alerts |
| `entirius-pwa-cms` | the Leads panel: Today, Inbox and Review, Companies, the company card, Deals with the board, Approvals, Reports, Settings |
| `entirius-service-volkanos` | the tasks module and the CRM settings in the registry |
| `entirius-test-package-emporium` | the CRM seed (two mailboxes, owners, stages), the `@crm` features, the e2e helpers |
| `entirius-zeno` | recipe, settings and beat entries for the CRM, the GreenMail SMTPS backend, this guide, `scripts/crm-walk-data.sh` |

Merged with it, from work that waited on local branches: the Mailpit viewer and mail checks, order confirmation
and cancellation e-mails (`entirius-django-checkout`, `entirius-django-email`), back-in-stock alerts (the new
`entirius-django-stock-alerts`, the storefront form, the CMS panel, scenarios). They are not part of this round;
a problem there is still worth a note.

What a salesperson can do now:

- **Today**: the tasks that are due, the drafts and replies that wait, one click to each.
- **Inbox and Review**: drafts one by one — Send or Skip, with the mailbox the mail leaves from; replies with
  their type and a "Next:" line that says what happens to the sequence.
- **Company card**: Overview, Contacts (who can be mailed, and "Why no mail?"), History (every conversation and
  event), Tasks, Deals; Write mail and Log call.
- **Deals**: a list and a board, won and lost with a reason, archive and restore of a closed deal.

What an administrator can do now: approve or skip drafts in bulk, import companies, read the funnel, and set up
stages, deal stages, company types, custom fields, scoring, rules, automatic moves, sequences, templates, reply
classification, mailboxes, sending health, send settings and the do-not-contact list.

Rules that hold everywhere and are worth trying to break:

- No screen and no API call approves or sends a mail to a contact the outreach gate refuses (opted out, flagged
  as the wrong person, company marked do-not-contact, no legal basis, address on the do-not-contact list).
- A draft that can no longer be sent leaves the queue by itself and stays visible in the conversation with the
  reason.
- The same thing has the same word and the same shape on every screen: Skip for leaving a draft unsent, Cancel
  for leaving a dialog, "Reply from <who> — <type>" for every reply in the bell.

## Scenario

About an hour. Texts of drafts and replies are test fixtures; judge the flow and the screen, not the wording of
a mail. Company names like "BDD 1794…" come from the test features. Some steps use data up (a sent draft does
not come back): for a second pass run `scripts/crm-walk-data.sh` again.

### A. A salesperson's day — desktop, `manager`, about 25 minutes

**A1. Morning**
1. Open `/leads` → **Today**. The side menu has seven entries: Today, Inbox, Companies, Deals, Approvals,
   Reports, Settings.
2. "Due now" holds five tasks, overdue before today's ("Overdue 2 days", "Today 23:30").
3. "Waiting" shows the number of drafts to approve and of replies that need review.
4. Click the task "Call back about the offer" → the card of Example Shop 4 on Tasks. Back → Today, same chip.

**A2. Drafts**
1. Inbox → Drafts → the first row → **Review**: "From sales1@greenmail.test", the recipient, "Draft 1 of N".
2. **Skip** → the next draft opens at once with the line "Skipped — this mail will not be sent" above it; nothing
   covers the buttons.
3. **Send** → the next draft with "Accepted — goes out within minutes".
4. `make mail-look` → within two minutes the mail is in the sandbox, from `sales1@greenmail.test`, with the legal
   footer and the unsubscribe headers.
5. The card of the skipped draft's company (Companies → All) → History: one closed line "Draft skipped by Anna
   Kowalska · <the time of the skip>".

**A3. Replies** (Inbox → Replies; a row carries the reply type)
1. **Out of office** → the bubble says "Back on 05/10/2026" and "Next: the sequence resumes on 06/10/2026".
2. **Wrong person** → "Next: the sequence is stopped", under it "Draft withdrawn · the contact is flagged as the
   wrong person". Contacts: "Blocked"; "Why no mail?" gives the same reason.
3. **Unsubscribe** with "Needs review" and two buttons, **Confirm opt-out** and **Not an opt-out** → "Next:
   nothing is sent until you confirm the opt-out or mark it as not one".
   - Confirm opt-out → a question that names the contact → "Next: no more mail to this contact"; the waiting
     draft leaves the queue ("Draft withdrawn · the recipient opted out"); Contacts shows "Blocked" without a
     reload.
4. **Interested** → **Reply** on the bubble: the form with the quote, the right recipient and one "Re:".
5. A company with "2 conversations" in the Inbox → on its card the newest conversation is open and the older
   one sits under "Earlier conversations (1)".
6. The bell (top right): every reply reads "Reply from … — <type>", "… — Possible opt-out" among them.

**A4. Tasks and a call** (card of Example Shop 4 → Tasks)
1. **Log call** → one field, "Outcome" → Log call. History: "Task done: … — <the text>"; Today gets no new open
   task.
2. **Add task** → no company field (it is known), owner = you, due today 17:00. The calendar starts on Monday;
   Escape closes the calendar, not the dialog.
3. On Today: **Mark done** with an outcome → the task leaves "Due now"; chip Done → **Reopen**.
4. Edit a task (the pencil) → **Cancel task** with a reason → "Keep task" / "Cancel task".

**A5. A mail by hand** (card of Example Shop 2 → **Write mail**)
1. "To" is the primary contact. Send → History shows the bubble "Mail written by hand" with "From sales1@…".
2. On the card of a company whose contact is blocked (A3) Write mail has Send greyed out and the reason under
   the field.

**A6. Deals**
1. Card of Example Shop 4 → Deals → **Open deal**: the title is the company's name, the currency PLN, no stage
   field → the deal card, in the first open stage.
2. **Mark won** → "Won". The ⋮ menu → **Archive** → "Archived", the only action is Restore, the details are
   read-only.
3. Deals → the **Archived** button beside "Open deal" (always there, also over an empty "Mine" list) → the
   archived deals; the status filter is gone. The button again → the usual list.
4. Open the archived deal → **Restore** → a won deal with Reopen again.
5. Deals → **Board** → "Show all deals": drag a card to the next stage, then to **Lost** → a question for the
   reason; Cancel puts the card back; with a reason it stays in Lost. Column totals are per currency.

### B. Phone — 390 × 844, `manager`, about 10 minutes

1. `/leads` → Today; the bottom bar: Today · Inbox · Companies · Deals. Nothing scrolls sideways.
2. A whole task row opens its company; "Mark done" is in reach.
3. Inbox → Drafts → Review: "Swipe right to send, left to skip". After **Skip** the next draft's **Send** works
   at once.
4. Company card → Tasks → Log call: one field.
5. Deals: a list grouped by stage with the value; `/leads/deals/board` shows the list and a sentence that the
   board is for a larger screen.

### C. Administrator — desktop, `admin`, about 15 minutes

1. **Approvals**: tick two drafts → Approve → a question → one message with the number approved. Tick a draft →
   **Skip** → a reason is required. The log button (top right) lists both calls.
2. A refusal in bulk: Settings → Mailboxes → **Pause** `sales1` with a reason → Approvals → tick a draft of
   `sales1` → Approve → "0 drafts approved. 1 not approved.", the reason in the Problem column, the row stays
   ticked. Then Mailboxes → **Resume**.
3. Settings → **Mailboxes** → `sales1@greenmail.test` → **Test login** → "Login works" for SMTP and IMAP.
4. Settings → **Sending health**: "Sent" and "Sent today" agree; the pause log fits its card.
5. Settings → **Do not contact** → **Add to the list**: "Reach" with "This channel" / "All channels". Add a
   domain → it is listed with that reach.
6. Settings → **Custom fields** → Add field → fill only Label → Save → "Give the key" on the field.
7. Settings → **Deal stages** → the bin of a stage that holds deals → "N deals stand in this stage. Move them
   first.", no Delete.
8. Settings → **Templates**: a line under the heading says where templates come from; no "Add" on purpose.
9. **Companies → Import**: a small CSV (`name,domain,email` and two companies) → the result in sentences, ignored
   columns named.
10. **Reports**: the period calendar opens; the funnel has "% of the first stage" in every row.
11. An address like `/leads/anything` → "Page not found" with a link to Today.

### D. Read-only — `viewer`, about 5 minutes

1. Today, Companies, a company card, Deals, Approvals: no action that writes, no checkboxes on Approvals.
2. Settings → any section: the read-only notice; a row action reads "View", not "Edit".

## Known limitations

Not findings of this round:

- Draft, reply and audit texts are placeholders. After an import the rule log ends with "Skipped — the audit
  found no hooks", so no draft comes from an import.
- Sending health shows rates above 100 % on this data: the test features date their sent mails in the past and
  the bounces count in the current window.
- In the bell a possible opt-out names the address, not the company, and the automatic pause of a mailbox has a
  title with raw numbers ("… of 6 sent in 2160 h"). Both are to be brought into the common shape.
- Custom field labels ("Company size") and stage names are data of the channel: one language.
- On the phone the grey "Actions" caption above the buttons and the place of toasts outside Review belong to the
  shell of every CMS panel.
- The deals board and Approvals are desktop screens.
- CMS visual baselines for the Leads screens are not approved yet; `npm run visual:ux` compares nothing for them.
- `make bdd`: the scenario SA-6 of `@stock-alerts` can fail when the beat's restock check (every five minutes)
  runs in the middle of it; alone it passes.
- Until the module releases, only the developer stack works on `develop`: `make setup` without `DEV=1` builds the
  service from its lock (leads 0.4.0, no tasks module, no stock alerts) while the recipe already enables the new
  modules, so it stops at `migrate` with `No module named 'django_todo'`. The `test` job of this repository's CI is
  red for the same reason, and so is the lint job of `entirius-service-volkanos` (it requires
  `entirius-django-stock-alerts`, which is not on PyPI yet). Dev mode installs the clones and does not care.
- CI of `entirius-django-checkout` and `entirius-django-stock-alerts` on `develop` fails on imports from
  `entirius-django-email`: they need its `develop`, PyPI has the last release.

## Open questions for the owner

- "95 % sure" beside every classified reply: does the number belong on the surface?
- Release versions: leads 0.5.0 or 1.0.0.

## After acceptance

1. Documentation on docs.entirius.com: a Concepts page on how the CRM works and CMS guides with screenshots
   (`make docs-screens`), written from the accepted screens.
2. Module releases: communicator, leads, todo (first release, PyPI publisher to set up), notifications; then the
   CMS; then the service lock. Procedure: the platform release procedure of the internal standards.
3. The first real configuration on a service: mailboxes, legal footer, sequences, templates.
4. Re-measure the baselines of `AGENTS.md` after the fixes of this round.
