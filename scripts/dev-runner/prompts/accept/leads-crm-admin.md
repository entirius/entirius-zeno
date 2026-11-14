## Scenario — CRM: desk work and administration (Leads panel, flows 9–11, settings, read-only)

Channel `default-europe` is in sandbox mode and every mail lands in the local mail sandbox (GreenMail, URL in the
run context); nothing leaves the machine. The AI toolbox serves only `fake` models. Data comes from a fresh seed
plus one run of the CRM test suite: names may look artificial; that is not a finding.

**Logins.** Administrator from the run context for flows 9–11 and the settings. Read-only pass: `viewer` /
`viewer123`. The panel is Leads: `/leads` on the CMS URL of the run context.

**Budget of the session.** About 55 minutes. Create `report.md` with the three headings before the first flow and
rewrite it after every flow, so an interrupted session still leaves a report. This scenario is desk work: the
desktop pass (1280 × 800) is the main one. The phone pass (390 × 844) covers only the "Phone" column below — walk
it first, it is short. When time runs short, list what was not walked under Questions.

### Flows

**9. Import a list and start the automation**

| Phone | Desktop |
|---|---|
| `/leads/import` shows a "desktop only" wall; Companies has no Import action | Companies → Import; the column list names the custom-field columns of the channel (`attr.<key>`) |
| — | Owner is pre-set to me; the note about running the rules is visible without hovering |
| — | Upload a small CSV you write in the run directory (3 companies: name, domain, one contact e-mail at `example.test`) with "run rules" on → the report counts created rows and ignored columns and says for how many the automation started; drafts appear in Approvals |

Blocker: rules run with the box off (or not with it on); companies imported without the chosen owner.

**10. Add a mailbox**

| Phone | Desktop |
|---|---|
| A direct link to `/leads/settings/mailboxes` opens the list, usable at 390 px (the entry is not in the bottom bar) | Settings → Mailboxes → Add mailbox → fill the form (any address at `greenmail.test`, host `greenmail`) → Save → Test login → SMTP / IMAP results shown in plain words |
| — | the password field never shows the password after save (it says it is saved); Delete asks to confirm |
| — | the list shows a state badge and "sent / cap today" per mailbox |

Blocker: a password visible anywhere; saving the form again clears a stored password; Test login saves the form.
Delete the mailbox you added at the end; never delete or edit the two seeded mailboxes beyond pause / resume.

**11. Pause a mailbox**

| Phone | Desktop |
|---|---|
| Open the form of a paused mailbox from a direct link (no wall); Resume → reason → Active | Mailboxes: row Pause → reason required → Paused; Sending health shows the pause in its log with who did it |
| — | rates over a threshold carry a warning badge; Resume from Sending health works |
| — | while the mailbox is paused, open Approvals: its drafts show the problem in plain words and cannot be approved; after Resume the problem is gone |

Blocker: pause without a reason; a bell alert about a mailbox that opens nothing. Leave both seeded mailboxes
active at the end.

**Settings, one look each (desktop).** Settings hub → every section: Automatic moves (what happens after each
reply type, first send, finished sequence), Do not contact (add an address at `example.test`, see the reach, delete
it), Custom fields (company, contact, deal: add one text field, delete it), Scoring, Deal stages, Rules (a rule
with a condition), Reply classification, Sequences ("starts automatically"). For each: does an administrator who
opens it twice a year understand what it changes, is there one primary action, does it say what happens to
existing data? Then Reports → the funnel: does it answer "where do companies drop out" without explanation?

**Read-only pass (desktop, `viewer`).** Open Today, Companies, a company card, Deals, a deal card, Approvals,
Settings → Mailboxes. Expected: every screen says it is read-only, no primary action, no bulk bar, no drag on the
board. Blocker: a write that succeeds; a screen that offers an action and fails only after the click with a raw
error.

### Fourth walk: what the earlier walks found
The findings of the three earlier walks were fixed. Where each belongs, check it is gone; one that is still there goes
into the report at its old severity with the words "still there". Then judge everything else as new.
- Test login: every result is a sentence that says what to do; no code in brackets.
- Pause log: "By" names the person, or says the pause was automatic; no id.
- A rule's "Last runs": company names and results in words; no id, no doubled word.
- Reports: dates in the panel's format; a Funnel that shows where companies drop out.
- `viewer`: none of the thirteen settings sections offers a write (Add, Save, Delete, reorder) and each shows the
  read-only notice; no row checkboxes on Approvals.
- Import: an Owner field pre-set to the person importing; the report names the ignored columns and for how many
  companies the automation started; the column list names the channel's custom fields.
- Tables: no column clipped to two or three letters (Rules, pause log, Custom fields, Do not contact); the bulk
  bar of Approvals is visible as soon as a row is ticked; the Mailboxes row action is reachable at 390 px.
- No breadcrumb repeats a level.
- Sending health: a rate over its threshold carries a warning badge; thresholds have a unit.
- A disabled primary looks disabled and the screen says why.
- Settings: the hub says under each section what it changes; Deal stages has Save and one reorder control;
  Scoring says what a segment is; deleting a custom field says what happens to stored values.
- One word: Company (never "lead" for a company), Company type (never "Lead type"), Board (never "pipeline").
- Second walk: the calendar of Reports → Period and of the mailbox's "Warm-up from" opens; the import result has no
  machine text (every row reason is a sentence, the status a word); the read-only notice is drawn like the other
  notices; a read-only row action is "View" and its form is not headed "Edit"; Templates has no id column and
  names the language; a mailbox opens from a link on its address; every settings section saves from one Save in
  the header; Sending health fits 1280 px with a paused mailbox; the word is Company type · Typ firmy, never
  "Lead type".
- Third walk: a bulk Approve says how many drafts it approved and how many not, each refused row shows its reason;
  Test login of a mailbox that sends reads "Login works" for SMTP and IMAP; an unknown Leads address shows a
  not-found page with a way back and Company types lives at /leads/settings/company-types; Reports → Funnel
  counts created companies as entered and shows "% of the first stage"; Sending health's "Sent" and "Sent
  today" agree; the word beside a toggle follows it (Active / Off); a company without a type reads "Unknown" in
  the Company type column, not clipped; the approval log has no "0 drafts" entry.

Decided earlier, not findings: a company is its registrable domain, so three subdomains of one domain import as
one company; template and sequence keys are the names an administrator gave and are shown as stored; "Hook ·
Haczyk" is the word for a talking point of the audit; "mean time in stage" of hundreds of days comes from seeded
dates; the mailbox form opens for the `communicator.settings` area; the import counts a row that joins a company
created earlier in the same file as "matched"; custom field labels are one text per field, shown as stored; after the import the rule log reads
"Skipped — the audit found no hooks" (the test AI returns an audit without hooks, so no draft is written); the
dismiss button of a confirm dialog is "Cancel"; "AI this month" in the top bar is not part of this panel; the
switches of Sequences, Rules and Custom fields save on change (no Save for a list of switches).

### What to judge on every screen
- One primary action per view, right-aligned. One page heading. Breadcrumbs below the panel root.
- Human wording: no ids, internal keys, raw enum values, raw ISO dates, untranslated keys or JSON on the surface;
  refusal reasons in plain words with what to do next. A password is never shown.
- Every list has an empty state that says how it fills; every form error points to its field.
- A destructive change is confirmed, and the dialog names its buttons by the action ("Delete" / "Keep").
- The same thing looks the same everywhere: one badge per status, one word per concept.
- Nothing on a screen that its user does not need there: report every control, column or counter whose purpose
  you cannot name ("less is more"). Settings are where screens grow by themselves: be strict here.

### One word per concept (English · Polish; another word for the same thing is a finding)
Mailbox · Konto pocztowe — Paused · Wstrzymane — Pause / Resume · Wstrzymaj / Wznów — Sending health · Kondycja
wysyłki — Warm-up · Rozgrzewka — Daily cap · Dzienny limit — Do not contact · Nie kontaktować — This channel /
All channels · Ten kanał / Wszystkie kanały — Custom fields · Pola własne — Score · Ocena — Scoring · Ocenianie —
Rules · Reguły — Condition · Warunek — Automatic moves · Automatyczne przejścia — Sequence · Sekwencja — Starts
automatically · Startuje automatycznie — Reply classification · Klasyfikacja odpowiedzi — Import · Import —
Salesperson · Handlowiec — Opt-out · Rezygnacja — Bounce · Odbicie — Origin · Źródło — Funnel · Lejek — Owner ·
Opiekun — Stage · Etap — Deal stage · Etap transakcji — Approvals · Do zatwierdzenia.
Never on a screen: "suppression", "intent", "sender route", "autostart", "stage events", "subject_ref".

### Severity
`## Blockers` — the "Blocker" line of a flow, and also: a dead end; data written wrong; a raw ISO date, raw enum
value or untranslated key on screen; a page with no heading or two; a password shown.

Start every item of `## Remarks` with `Major:` or `Minor:` and name the flow or section and the width
(`Major: [settings · Scoring, 1280] …`).
- `Major:` — the task can be finished, but its user would hesitate or get it wrong: more than one primary action,
  wording that misleads or a word outside the list above, a missing empty, error or read-only state, Polish
  without diacritics, horizontal page scroll, a setting whose effect is not explained, a control with no purpose.
- `Minor:` — spacing, alignment, copy polish, a matter of taste.

### Viewport rules (do not report as blockers)
- Import, Reports, Approvals and Settings are desktop entries; they are absent from the phone bottom bar by
  design. Import and the deals board show a "desktop only" wall at 390 px; Settings sections open from a link.
- A list worked through by the earlier session may be empty: say so under Questions and judge what is there.
