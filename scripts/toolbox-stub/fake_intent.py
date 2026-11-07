#!/usr/bin/env python3
"""A deterministic stand-in for the AI toolbox's reply intent classification (T4). Stdlib only, no network, no AI.

It reads the same request the communicator sends (`tags` contain `communicator.reply_intent`, the last user message is
`Subject: ...` + `Reply:` + text) and answers the same JSON the real toolbox would put in `parsed`:
`{"intent", "confidence", "return_date"}`. Keyword rules for Polish and English, fixed priority:
unsubscribe > out_of_office > wrong_person > not_interested > not_now > interested; no rule = `unclear` at 0.35.
Its only job is to make the whole path (HTTP client, parsing, thresholds, mapping) testable without a model; it
says nothing about how well a real model classifies. `outbound/checks/toolbox_stub.py` serves it over HTTP and a copy
lives in the communicator tests as `tests/fake_toolbox.py` (keep them equal).
"""

from __future__ import annotations

import re
import unicodedata
from datetime import date

TAG = "communicator.reply_intent"

# (intent, confidence, stems) in priority order; stems are matched on folded text (lower case, no diacritics).
RULES = [
    (
        "unsubscribe",
        0.95,
        [
            "unsubscribe", "wypisz", "wypisa", "wypis ", "usun mnie", "usunac mnie", "usuniecie mnie", "usun nas",
            "usunac nas", "remove me", "take me off", "stop emailing", "stop sending", "nie kontaktowa",
            "nie kontaktuj", "prosze nie pisac", "nie piszcie", "do not contact", "don t contact",
            "z listy mailingowej", "opt out",
        ],
    ),  # fmt: skip
    (
        "out_of_office",
        0.9,
        [
            "poza biurem", "nieobecn", "urlop", "out of office", "on leave", "on holiday", "away until",
            "wracam", "wroce", "i am away", "jestem poza",
        ],
    ),  # fmt: skip
    (
        "wrong_person",
        0.85,
        [
            "nie jestem wlasciwa", "nie jestem wlasciw", "nie zajmuje sie", "wrong person", "not the right person",
            "nie ta osoba", "prosze skontaktowac sie z", "please contact my colleague", "please reach out to",
            "ktos inny", "i don t handle", "not my area", "nie do mnie",
        ],
    ),  # fmt: skip
    (
        "not_interested",
        0.9,
        [
            "nie jestem zainteresowan", "nie jestesmy zainteresowan", "not interested", "no thanks",
            "nie dziekuje", "nie potrzebujemy", "nie interesuje nas", "we will pass", "not a fit for us",
        ],
    ),  # fmt: skip
    (
        "not_now",
        0.85,
        [
            "nie teraz", "nie w tym momencie", "w przyszlym kwartale", "w przyszlym roku", "not right now",
            "not now", "next quarter", "next year", "maybe later", "odezwij sie za", "wroc do tematu",
            "contact me again in",
        ],
    ),  # fmt: skip
    (
        "interested",
        0.9,
        [
            "zainteresowan", "chetnie", "umowmy", "prosze o wiecej", "prosze o kontakt", "cennik", "wycen",
            "przesl", "spotkanie", "rozmow", "tell me more", "send me", "let s talk", "interested",
            "book a call", "schedule a call", "demo", "how much", "sounds good", "brzmi ciekawie",
        ],
    ),  # fmt: skip
]
UNCLEAR = ("unclear", 0.35)

MONTHS = {
    "stycznia": 1, "lutego": 2, "marca": 3, "kwietnia": 4, "maja": 5, "czerwca": 6, "lipca": 7, "sierpnia": 8,
    "wrzesnia": 9, "pazdziernika": 10, "listopada": 11, "grudnia": 12,
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
    "september": 9, "october": 10, "november": 11, "december": 12,
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}  # fmt: skip


def fold(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text.casefold().replace("ł", "l"))
    letters = "".join(char for char in decomposed if not unicodedata.combining(char))
    return " ".join(re.sub(r"[^a-z0-9]+", " ", letters).split()) + " "


def find_date(text: str, today: date) -> date | None:
    """ISO `2026-11-20`, `20.11.2026`, `20 listopada`, `20 November`, `Nov 20` — the first one found."""
    if match := re.search(r"\b(\d{4})-(\d{2})-(\d{2})\b", text):
        return _safe(int(match[1]), int(match[2]), int(match[3]))
    if match := re.search(r"\b(\d{1,2})[./](\d{1,2})[./](\d{4})\b", text):
        return _safe(int(match[3]), int(match[2]), int(match[1]))
    lowered = fold(text)
    if match := re.search(r"\b(\d{1,2}) ([a-z]+)\b", lowered):
        if match[2] in MONTHS:
            return _next(MONTHS[match[2]], int(match[1]), today)
    if match := re.search(r"\b([a-z]+) (\d{1,2})\b", lowered):
        if match[1] in MONTHS:
            return _next(MONTHS[match[1]], int(match[2]), today)
    return None


def _safe(year: int, month: int, day: int) -> date | None:
    try:
        return date(year, month, day)
    except ValueError:
        return None


def _next(month: int, day: int, today: date) -> date | None:
    candidate = _safe(today.year, month, day)
    if candidate is not None and candidate <= today:
        candidate = _safe(today.year + 1, month, day)
    return candidate


def classify_text(subject: str, body: str, today: date | None = None) -> dict:
    today = today or date.today()
    text = fold(f"{subject} {body}")
    for intent, confidence, stems in RULES:
        if any(stem in text for stem in stems):
            found = find_date(f"{subject} {body}", today) if intent == "out_of_office" else None
            return {"intent": intent, "confidence": confidence, "return_date": found.isoformat() if found else None}
    return {"intent": UNCLEAR[0], "confidence": UNCLEAR[1], "return_date": None}


def reply_text(request: dict) -> tuple[str, str]:
    """(subject, body) from the communicator's user message."""
    user = next((m["content"] for m in reversed(request.get("messages", [])) if m.get("role") == "user"), "")
    head, _, body = user.partition("\n\nReply:\n")
    return head.removeprefix("Subject: "), body


def is_intent_request(request: dict) -> bool:
    return TAG in (request.get("tags") or [])


def completion(request: dict, today: date | None = None) -> dict:
    """A complete `POST complete/` answer for an intent request."""
    subject, body = reply_text(request)
    parsed = classify_text(subject, body, today)
    return {
        "output": str(parsed),
        "parsed": parsed,
        "usage": {"input_tokens": len(body) // 4, "output_tokens": 12},
        "cost": "0",
        "model": "fake-model",
        "attempts": 1,
        "request_id": "fake-intent",
    }


if __name__ == "__main__":  # a quick look: python3 fake_intent.py "Nie jestem zainteresowany"
    import sys

    print(classify_text("", " ".join(sys.argv[1:])))
