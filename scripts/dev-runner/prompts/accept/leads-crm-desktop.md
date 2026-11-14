## Scenario — CRM: a salesperson's day (Leads panel, flows 1–8), desktop

Channel `default-europe` is in sandbox mode and every mail lands in the local mail sandbox (GreenMail, URL in the
run context); nothing leaves the machine. The AI toolbox serves only `fake` models: draft and reply texts are
placeholders; judge the flow and the presentation, never the wording quality of a generated mail. Data comes from a
fresh seed plus one run of the CRM test suite and one earlier acceptance session (administration): companies with owners, tasks, drafts to approve, replies of every
type, deals in several stages, two mailboxes. Company, deal and task names come from tests and may look
artificial; that is not a finding.

**Logins.** Walk as the salesperson `manager` / `manager123` (owner of the seeded companies; the default mailbox
is theirs). If a screen refuses that user, say so under Questions and continue as the administrator from the run
context. The panel is Leads: `/leads` on the CMS URL of the run context.

**Budget of the session.** About 55 minutes. Create `report.md` with the three headings before the first flow and
rewrite it after every flow, so an interrupted session still leaves a report. This scenario is the desktop half
of the walk: walk at 1280 × 800 only, using the Desktop column of every table; the phone half is a separate
session (scenario `leads-crm`), so do not resize to 390. Order: flows 3, 4, 5, 6, 7, then 8 (the board: drag to
Won, drag to Lost and Cancel, column totals per currency, the stage select of the deal card by keyboard), then 1
and 2. List the flows not walked under Questions.

The send window of the channel is open all day in this run: a mail you send should reach the mail sandbox within
about two minutes; check its sender, its legal footer and the bubble in History.

Check the dark and the light theme once on a company card and on the deals board, and the other interface
language once on the same two screens. Everything else in the theme and language the CMS opens in.

### Flows

**1. Morning check**

| Phone (390 × 844) | Desktop (1280 × 800) |
|---|---|
| Open `/leads` → Today is shown; bottom bar Today · Inbox · Companies · Deals | Open `/leads` → Today; the sidebar shows 7 entries: Today, Inbox, Companies, Deals, Approvals, Reports, Settings |
| The "waiting" counters match the Inbox Drafts count and the replies that need review | same |
| Chip Due lists overdue before today; due badges read "Overdue N days" / "Today HH:MM" | same, plus Company / deal and Kind columns |
| Tap a task text → company card on Tasks (or the deal card); back → Today, chip kept | same |
| Tap "drafts to approve" → Inbox Drafts | same |

Blocker: Today is not the root; a task row opens nothing or the wrong record; counters missing.

**2. Approve drafts**

| Phone | Desktop |
|---|---|
| Inbox → Drafts → Review; a draft with a problem shows it and Send is disabled with the reason | Approvals: filters, problem column, select rows, Approve → one toast with done / failed |
| Send → next draft; Skip → next draft | Skip → reason required → the draft is skipped; the log drawer lists the call |
| Approvals is not in the bottom bar | a row of another channel (if any) opens a drawer, never Review |

Blocker: a draft with a problem can be sent; a row of another channel opens Review.

**3. Read a reply and act on its type**

| Phone | Desktop |
|---|---|
| Bell → the company card on History (the card, not the thread alone) | Bell → card on History, the company list in the left column |
| The reply bubble shows the type badge, "Needs review" when set, a "Next:" line, "Back on" for out of office | same |
| Interested: Reply → the mail form with the quote → Send; Deals → Open deal | same |
| Wrong person: Contacts → Blocked, and "Why no mail?" lists "wrong person" | same |
| Unsubscribe: Confirm opt-out → the contact is Blocked | same |

Blocker: no type on a classified reply; "Next" contradicts what happened (task not there, stage not moved); Reply
answers the wrong contact.

**4. Log a call**

| Phone | Desktop |
|---|---|
| Card → Tasks → Log call → kind Phone, "Already done" on → title + outcome → Log call | same |
| History shows "Task done: … — outcome"; nothing new in Today's open list | same |

Blocker: the call stays an open task; the outcome is lost.

**5. Write a mail by hand**

| Phone | Desktop |
|---|---|
| Card → Write mail (the primary action) → bottom sheet; To is pre-set to the primary contact | a modal |
| Blocked contact: Send disabled, "Why no mail?" opens the reasons | same |
| Send → a toast that the mail is queued; the mail sandbox receives it from the owner's mailbox; History shows the bubble and that the sequence stopped | same |

Blocker: mail sent to a blocked contact; mail sent from another mailbox than the owner's (or the default one); no
legal footer in the received mail.

**6. Add and close a task**

| Phone | Desktop |
|---|---|
| Today → Add task → company picker, owner = me, due today 17:00 pre-set → Add | same, in a modal |
| Card → Tasks → Add task: no company field (it is known) | same |
| Mark done with an outcome → the task leaves Due; History shows it; chip Done → Reopen | same |
| Edit → Cancel task → reason → confirm | same |

Blocker: the dialog asks for the company on a card; a task created by a person has no owner.

**7. Open a deal**

| Phone | Desktop |
|---|---|
| Card → Deals → Open deal: title = company name, currency = the channel default, no stage or owner field → Open deal → the deal card | same, and from Deals with a company picker |
| The deal is in the first open stage; owner = the company owner or me; the company History says "Deal opened" | same |

Blocker: a value saved without a currency; a deal in a won / lost stage at creation.

**8. Move a deal to won or lost**

| Phone | Desktop |
|---|---|
| Deals list: the stage select of a row moves it; a lost stage asks for the reason first | Board: drag to Won moves; drag to Lost asks for the reason, Cancel snaps the card back |
| Deal card: Mark won → badge Won; Mark lost → reason → Lost; Reopen → the first open stage | the stage select of the card works by keyboard; column totals per currency update |
| No board on the phone (no switch; the board URL shows a "desktop only" wall) | totals never add two currencies |

Blocker: lost without a reason; a refused move that does not snap back; totals mixed across currencies.

### Fourth walk: what the earlier walks found
The findings of the three earlier walks were fixed. In the flow where each belongs, check it is gone; one that is still
there goes into the report at its old severity with the words "still there". Then judge everything else as new.
- Approvals: a row names the company (a link to its card), the channel by its name and the template key in full;
  no internal reference.
- Bell: one entry per reply, titled "Reply from <company> — <reply type in words>".
- History: stage names and reply types in words, one language per interface language; message statuses look like
  the badges elsewhere.
- Task dialogs: the due date in the panel's date format.
- A reply can be answered: Reply on the inbound bubble opens the form with the quote, the recipient and "Re:".
- A task can be edited and cancelled with a reason, from Today and from the company card.
- Deals board: all columns fit 1280 px without a horizontal scroll, a drop lands in the column under the pointer,
  an empty column has a drop area; no label is drawn over another text on a card or the company header.
- Company card: every tab is reachable; Back returns to where the card was opened from (Today keeps its chip).
- The result of Log call and Send shows without a reload; a hand-written mail is not labelled as a follow-up.
- Confirm opt-out asks before it blocks; Contacts show "Can be mailed" / "Blocked".
- Approving several drafts asks first; a task created from Today names its company.
- Second walk: a contact flagged by a wrong-person or opt-out reply reads "Blocked" in Contacts, in one colour,
  and agrees with "Why no mail?"; the calendar of every date field opens; no "thread" on screen (the word is
  Conversation · Rozmowa); Reply gives one "Re:"; after Send the
  next draft opens, not the last; Edit task shows the stored owner and kind; on the
  phone a task row and the chips fit the screen; below 1440 px a company card, a deal card and a conversation take
  the full width (no column of conversations beside them); a board card's stage select is readable; three drops in
  a row land, also into an empty column and into Lost; Deals under "Mine" with nothing says so and offers "Show
  all"; the deal card has one primary (Mark won) and Delete deal in the more menu; every label of the card is
  translated in Polish.
- Third walk: a draft whose recipient may not be mailed (opted out, flagged as the wrong person, company marked
  do not contact) cannot be sent — Review and Approvals name the problem and Send is disabled, or the draft has
  left the queue by itself and the conversation shows it as withdrawn with the reason; the action of Review that
  leaves a draft unsent is "Skip · Pomiń" (never "Later" or "Not now"), says the mail will not be sent, and the
  skipped draft stays visible in the conversation as one closed line; after Confirm opt-out the Contacts tab
  reads "Blocked" without a reload; an out-of-office reply names two dates in two phrases ("Back on …", "The
  sequence resumes on …"), the same in the bubble and in History; on the phone the whole task row of Today opens
  it and no status badge is cut; in Polish the List / Board switch and every History line are Polish; Escape with
  the calendar open closes the calendar only, the week starts on Monday; an Inbox row carries one "Replied"; an
  unknown Leads address shows a not-found page with a way back.
- New since the third walk: a won or lost deal can be archived from its card (more menu → Archive) and
  restored from the archived card; archived deals are shown only by the "Archived" button of the Deals list (never as a value of the status
  filter) and on no board; an open
  deal cannot be archived (it has Delete deal).

Decided earlier, not findings: the panel is "Leads · Leady" and the kind of a company is "Company type · Typ
firmy"; a user without a first and last name is shown by login (`admin` has none); a conversation that belongs to
no company shows the other side's address; a logged call writes two History lines (added, done); a task can be
cancelled without a reason; the bell's own date format; stage names, deal stage names, custom field labels and template keys are the channel's own data
and are shown as stored, also under the Polish interface; a Polish legal footer under an English body is the
seeded channel; "AI this month" in the top bar is not part of this panel; toasts, the "Actions" caption above the
primary button and the Filters panel are the shell of every CMS panel, not of Leads (a minor at most); "drafts to approve" on Today opens Approvals on the desktop and Inbox →
Drafts on the phone; a contact's role ("Owner", "Warehouse") is the contact's job title as stored; a reply
without a type and without the review flag reads "Reply from <company>" in the bell; the dismiss button of a
confirm dialog is "Cancel".

### What to judge on every screen
- "What do I do now" is answered within five seconds of opening Today, without a manual.
- One primary action per view, right-aligned; a salesperson reaches it with a thumb at 390 px. One page heading.
- Human wording: no ids, internal keys, raw enum values, raw ISO dates, untranslated keys or JSON on the surface;
  statuses and refusal reasons in plain words, each with what to do next. A password is never shown.
- Every list has an empty state that says how it fills; every form error points to its field.
- A change is reversible or confirmed (a task outcome, a deal moved, a do-not-contact flag); a confirm dialog
  names its buttons by the action ("Delete" / "Keep"), never a generic OK.
- The same thing looks the same everywhere: one badge per status, one word per concept.
- Nothing on a screen that a salesperson does not need there: report every control, column or counter whose
  purpose you cannot name ("less is more").
- The system does not ask for what it knows (owner, currency, the company on a company card).

### One word per concept (English · Polish; another word for the same thing is a finding)
Company · Firma — Contact · Kontakt — Owner · Opiekun — Mine · Moje — Stage · Etap — Deal · Transakcja —
Won · Wygrana — Lost · Przegrana — Task · Zadanie — Due · Termin — Overdue · Po terminie — Mark done · Oznacz jako
zrobione — Outcome · Wynik — Log call · Zapisz rozmowę — Today · Dziś — History · Historia — Draft · Szkic —
Approve · Zatwierdź — Skip · Pomiń (leave a draft unsent) — Approvals · Do zatwierdzenia — Reply · Odpowiedź — Reply type · Rodzaj
odpowiedzi — Needs review · Do sprawdzenia — Write mail · Napisz wiadomość — Mailbox · Konto pocztowe —
Do not contact · Nie kontaktować — Why no mail? · Dlaczego bez poczty? — Can be mailed / Blocked · Można pisać /
Zablokowany. Reply types: Interested · Zainteresowany, Not now · Nie teraz, Not interested · Niezainteresowany,
Out of office · Poza biurem, Wrong person · Niewłaściwa osoba, Unsubscribe · Wypisanie, Unclear · Niejasna.
Never on a screen: "thread", "suppression", "intent", "subject_ref", "preflight", "lead" for a company.

### Severity
`## Blockers` — the "Blocker" line of a flow, and also: a dead end; data written wrong (stage, owner, currency,
recipient); a control unreachable on the phone (off-screen, under the bottom bar); a raw ISO date, raw enum value
or untranslated key on screen; a page with no heading or two.

Start every item of `## Remarks` with `Major:` or `Minor:` and name the flow and the width
(`Major: [flow 3, 390] …`).
- `Major:` — the flow can be finished, but a salesperson would stop using the screen: more than one primary
  action, a step that takes more than twice the taps it needs, a result that is not shown, wording that misleads
  or a word outside the list above, a missing empty or error state, Polish without diacritics, horizontal page
  scroll, a default the system knows asked again, content cut off at 390 px.
- `Minor:` — spacing, alignment, copy polish, an extra tap a shortcut would save, a matter of taste.

### Viewport rules (do not report as blockers)
- Deals are a list grouped by stage on the phone and a board on the desktop; no drag and drop at 390 px is by
  design when every row has a visible stage select.
- Approvals, Reports, Import and Settings are desktop entries; they are absent from the phone bottom bar by design.
- A flow that consumed its data on the phone pass (an approved draft, a closed task) may meet an empty list on the
  desktop pass: say so under Questions and judge the screen from what is there.
