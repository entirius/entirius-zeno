## Scenario — AI studio (enricher): product AI, corrections, profile, Studio article

Log in to the admin CMS with the credentials below. The AI toolbox behind this stack serves only `fake` models:
texts are placeholder Latin ("Lorem ipsum …"); judge the flow and the presentation, never the wording quality.
Data comes from the seed (product ENT-S001 "Orion Command Sofa", channel Default Europe, the seeded test
company profile, the "Meta opisy" / "Opis produktu" / "Otaguj produkt" templates and the "Article" workflow).

| Step | Do | Expected |
|---|---|---|
| 1 | Products → ENT-S001; tap the Enricher (wand) icon in the header | A drawer opens: "Run AI" templates first, recent tasks, proposals to review; the icon shows a badge or dots that match what the drawer says |
| 2 | Run "Meta opisy" (all languages) | The dialog closes at once with a toast; the icon pulses while it runs; cards appear per field and language with a cost, a readable field name and a language chip — no internal ids or worker names on the surface |
| 3 | On one card use "Shorter", then restore the first version, then Apply | A new version appears with a visible diff; restore makes it current again; Apply writes the field and the product form shows it without losing other unsaved edits |
| 4 | Products list: select 3 products → AI → "Meta opisy"; then Enricher → Review | Review list is compact (one line per row, excerpt, counters); a row opens a detail panel with the full card; "Correct all" applies one instruction to all pending proposals |
| 5 | Enricher → Profile: add a fact and a rule ("e-commerce" → "ecommerce"), save with a note | The save creates a new version in the history; completeness updates; validation errors (if you try an invalid row) point to the field |
| 6 | Back on a proposal that contains "e-commerce" or a number (generate one if needed) | The card lists warnings in plain words; "Fix warnings" produces a new version; "Add to facts" leads to a suggestion in Memory |
| 7 | Enricher → Studio → New → Article: fill the brief, answer the questions, approve step by step (pick keywords, approve outline and draft, approve meta, approve compose) | The steps rail always says what is waiting for you; each step's output is readable (form for questions, table for keywords, card for text, SERP preview for meta); the run shows its cost; the last step links to an unpublished ContentDB draft |

Presentation rubric (report deviations as Remarks, Blockers only when the scenario cannot be finished or a primary
action is unreachable on the phone): human wording (no ids, kinds, worker keys, JSON on the surface unless the
user asked for "Edit JSON"); plain-language statuses and failure reasons; every empty, loading and error state says
what to do next; costs readable ("$0.04", "—" with a hint when unknown); one primary action per view; long text
readable (no tiny scroll boxes); list rows compact (no inline previews); counters and icons consistent between the
header badge, the drawer and Review; every change reversible (versions, restore, undo) or confirmed.

### Viewport rules (do not report as blockers)
- The profile editor's tables and the Studio steps rail may switch to stacked layouts at 390 px; judge that they
  stay usable, not that they look like desktop.
- Fake answers are placeholder text by design; length counters may show red for them.
