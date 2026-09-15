## Scenario — leads funnel, steps 1–7 (test-strategy §5)

Log in to the admin CMS with the credentials below. Channel `default-europe` is in sandbox mode; nothing
leaves the machine. Before this session the harness put one fresh draft for the company in "Setup" into the
review queue; that company already has a replied thread from `make e2e-funnel` (run it first on a fresh seed).

| Step | Do | Expected |
|---|---|---|
| 3 | Open the panel switcher → Leads (or `/leads/inbox`) | Inbox lists at least one draft to review; the bell shows the unread count |
| 4 | Open the draft; read it as a salesperson; open "More actions" → try "Rewrite with a note" (cancel is fine), "Edit" (then Cancel); then Send | ≤ 3 taps from Inbox to sent; after Send "Scheduled HH:MM" for ~2 s, then the next draft or the empty Inbox saying how many are scheduled and when the next goes out |
| 5 | From the draft header open the company thread | Timeline shows the outbound mail with a status badge; intel & hooks card collapsed above it |
| 6 | Open the thread of the Setup company from the bell or the draft header | The reply is a left bubble under the sent mail, readable |
| 7 | Tap the bell → tap the "Reply from …" row | One tap marks it read and opens that company's thread; the count drops |

| 1-2 | At 1280x800 open Leads -> Import, upload nothing, read the screen; then Board and Stages | Import explains what a CSV needs and what happens next; Board shows the stages with companies; Stages lists the configured stages |
| L-15 | At 1280x800 open a company card of a company that is also a shop customer | The card says the company is a known customer and links to it |
| Send now | At 1280x800 open a draft in Review and use Send now | The mail goes out at once; the timeline shows it without the scheduled badge |

Also judge: the empty Inbox, the back buttons on Review and Thread, and the same flow at 1280x800 where the
Inbox is the left column and Review/Thread the right one.

### Viewport rules (do not report as blockers)
- Screens for 1280x800 only, by design: Board, Import, Stages, and the thread actions (stage picker, Communicate,
  Re-audit, do-not-contact). At 390 px the thread says they live on desktop; judge that hint, not their absence.
- The company thread opens the newest thread, closed or not; older threads sit behind an "Earlier threads" expander.
  Open it once and check that an older thread keeps its own header and that its messages are not mixed into the newest one.
- The phone pass consumes the seeded draft. If the desktop pass finds an empty queue, say so under Questions and
  judge desktop Review from the sent draft's thread; do not call it a blocker.
