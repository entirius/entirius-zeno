#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""mail-look.py — copy the newest GreenMail messages into Mailpit to look at them; --check runs Mailpit's HTML check.

GreenMail stays the sandbox of the stack and of BDD; Mailpit is emptied and receives copies only (SMTP, no auth).
--check exits 1 when a copied message whose subject matches --subject (a regex, empty = every message) has a
warning with unsupported clients that is not in mail-check-allowlist.txt. Standard library only (runs on the host).
"""

import argparse
import email
import json
import os
import re
import smtplib
import sys
import urllib.error
import urllib.request
from email.utils import getaddresses, parsedate_to_datetime
from pathlib import Path

GREENMAIL = os.environ.get("GREENMAIL_API_URL", "http://localhost:8380")
MAILPIT = os.environ.get("MAILPIT_URL", "http://localhost:8125")
MAILPIT_SMTP_PORT = int(os.environ.get("MAILPIT_SMTP_PORT", "1125"))
ALLOWLIST = Path(__file__).with_name("mail-check-allowlist.txt")
COPY_SENDER = "mail-look@greenmail.test"


def api(url: str, method: str = "GET") -> object:
    """JSON of a GET; the body of any other method is not read (Mailpit's DELETE answers plain `ok`)."""
    with urllib.request.urlopen(urllib.request.Request(url, method=method), timeout=10) as resp:
        return json.load(resp) if method == "GET" else None


def greenmail_messages(limit: int, user: str | None) -> list[tuple[email.message.Message, str]]:
    """The newest `limit` messages of `user` (None = every GreenMail user), oldest first, as (headers, raw); one per
    Message-ID."""
    unique = {}
    logins = [user] if user else [each["login"] for each in api(f"{GREENMAIL}/api/user")]
    for login in logins:
        for item in api(f"{GREENMAIL}/api/user/{login}/messages/INBOX"):
            message = email.message_from_string(item["mimeMessage"])
            unique.setdefault(message["Message-ID"] or item["mimeMessage"], (message, item["mimeMessage"]))
    return sorted(unique.values(), key=lambda pair: _sent_at(pair[0]))[-limit:] if limit > 0 else []


def _sent_at(message: email.message.Message) -> float:
    try:
        return parsedate_to_datetime(message["Date"]).timestamp()
    except (TypeError, ValueError):
        return 0.0


def copy_to_mailpit(messages: list[tuple[email.message.Message, str]]) -> None:
    """The raw bytes travel unchanged: re-serialising a parsed message breaks 8-bit bodies."""
    api(f"{MAILPIT}/api/v1/messages", method="DELETE")
    with smtplib.SMTP("localhost", MAILPIT_SMTP_PORT, timeout=10) as smtp:
        for message, raw in messages:
            recipients = [address for _, address in getaddresses(message.get_all("To", []))] or [COPY_SENDER]
            smtp.sendmail(COPY_SENDER, recipients, raw.encode())


def allowlist() -> set[str]:
    """Slugs, one per line; `#` starts the reason."""
    lines = (line.split("#", 1)[0].strip() for line in ALLOWLIST.read_text().splitlines())
    return {line for line in lines if line}


def html_check(message_id: str) -> dict | None:
    """Mailpit's HTML check of a message; None for a text-only one (404), any other error is raised."""
    try:
        return api(f"{MAILPIT}/api/v1/message/{message_id}/html-check")
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise
        return None


def unsupported(report: dict, allowed: set[str]) -> list[str]:
    """Warnings with clients that do not support the feature, minus the allowlist."""
    return [
        f"{warning['Slug']} ({warning['Title']}, unsupported {warning['Score']['Unsupported']:.0f}%)"
        for warning in report["Warnings"]
        if warning["Score"]["Unsupported"] > 0 and warning["Slug"] not in allowed
    ]


def check(subject: str) -> int:
    allowed, pattern, failed, checked = allowlist(), re.compile(subject), 0, 0
    for item in api(f"{MAILPIT}/api/v1/messages?limit=500")["messages"]:
        if not pattern.search(item["Subject"]) or (report := html_check(item["ID"])) is None:
            continue
        checked += 1
        if problems := unsupported(report, allowed):
            failed += 1
            print(f"FAIL {item['Subject']}: " + "; ".join(problems))
    print(f"mail-check: {checked} HTML message(s) checked, {failed} with an unsupported feature outside the allowlist")
    return 1 if failed or not checked else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--limit", type=int, default=50, help="newest GreenMail messages to copy")
    parser.add_argument("--check", action="store_true", help="run the HTML check after the copy")
    parser.add_argument("--subject", default="", help="regex: check only messages whose subject matches")
    parser.add_argument("--user", help="copy only this GreenMail user's messages (default: every user)")
    args = parser.parse_args()
    messages = greenmail_messages(args.limit, args.user)
    copy_to_mailpit(messages)
    print(f"mail-look: {len(messages)} message(s) copied from GreenMail — open {MAILPIT}")
    return check(args.subject) if args.check else 0


if __name__ == "__main__":
    sys.exit(main())
