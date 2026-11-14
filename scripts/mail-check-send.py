# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Run inside the service (`manage.py shell < scripts/mail-check-send.py`, make mail-check): one sample of every
email type of django_email's `test-email` command, in every email language, to the GreenMail mailbox the HTML check
of `make mail-check` reads (RECIPIENT, also in the Makefile). A type that does not send fails the run: `test-email`
answers an unknown type with a message, not an error, so its output is checked for DONE."""

import io
import os

from django.conf import settings
from django.core.management import call_command

CHANNEL = os.environ.get("MAIL_CHECK_CHANNEL", "default-europe")
RECIPIENT = "mail-check@greenmail.test"
TYPES = [
    "new_account",
    "reset_password",
    "coupon_confirmation",
    "return_confirmation",
    "virtual_product",
    "newsletter_signup",
    "order_confirmation",
    "order_canceled",
    "invoice",
    "voucher_issued_by_admin",
    "voucher_issued_on_purchase",
    "voucher_resend",
    "booking_confirmation",
    "booking_admin_notification",
    "contact_form_client_copy",
    "contact_form_submission",
]
LANGUAGES = getattr(settings, "EMAIL_AVAILABLE_LANGUAGES", ["en", "pl"])

for language in LANGUAGES:
    for email_type in TYPES:
        output = io.StringIO()
        call_command("test-email", CHANNEL, RECIPIENT, email_type, lang=language, stdout=output)
        if "DONE" not in output.getvalue():
            raise SystemExit(f"mail-check-send: {email_type}/{language} not sent: {output.getvalue().strip()}")
print(f"mail-check-send: {len(TYPES) * len(LANGUAGES)} samples sent to {RECIPIENT}")
