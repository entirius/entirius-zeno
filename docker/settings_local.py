"""
entirius-zeno settings_local.py for the service under test.

Every environment must provide its own settings_local.py — this is zeno's.
It bridges compose env vars to Django settings; baked into the image at build
and refreshed on every dev-mode start. Change .env on the host, not this file.
"""

import re
from pathlib import Path

import dj_database_url
from celery.schedules import crontab
from decouple import Csv, config

ENVIRONMENT = "development"

SECRET_KEY = config("SECRET_KEY", default="django-insecure-zeno-dev-only")
DEBUG = config("DEBUG", default=True, cast=bool)
# The OpenAPI schema and its UIs stay public here: the stack probes (stack-reload.sh, scripts/setup.py, smoke.sh, the
# Makefile) read them. The service serves them to staff only unless this is set (access delivery, plan 10b).
API_SCHEMA_PUBLIC = True
# No proxy in front of the service: per-IP throttles key on REMOTE_ADDR. Unset fails check --deploy (volkanos.E001).
DRF_NUM_PROXIES = 0
ALLOWED_HOSTS = config("ALLOWED_HOSTS", default="localhost,127.0.0.1,service", cast=Csv())

# The recipe (recipes/<name>/ in zeno, mounted by compose) names the modules this stack enables; unset = shop.
RECIPE = config("RECIPE", default="") or "shop"


def _recipe_apps() -> list[str]:
    """App labels of the recipe's apps.txt, in file order; `#` starts a comment, blank lines are dropped."""
    path = Path(config("ZENO_RECIPES_DIR", default="/entirius/recipes")) / RECIPE / "apps.txt"
    lines = (line.partition("#")[0].strip() for line in path.read_text().splitlines())
    return [line for line in lines if line]


# Volkanos modules adopted in this environment (entirius-django-* app labels), in the order of the service's
# module registry: every module after the modules it requires.
LOCAL_APPS = _recipe_apps()


def _enabled(*apps: str) -> bool:
    return set(apps) <= set(LOCAL_APPS)


# Compose passes DATABASE_URL pointing at the db container — no default, fail-closed.
DATABASES = {"default": dj_database_url.parse(config("DATABASE_URL"))}

# Celery — module workers (QMS quantities, PIM thumbnails); hostnames = compose services.
REDIS_URL = config("REDIS_URL", default="redis://redis:6379")
CELERY_BROKER_URL = config("CELERY_BROKER_URL", default="amqp://guest:guest@rabbitmq:5672//")
CELERY_RESULT_BACKEND = REDIS_URL + "/2"

# Dev harness: browser frontends (storefront :3100, CMS :8180) call the API cross-origin.
CORS_ALLOW_ALL_ORIGINS = True

# Dev-only: allow the in-network `fixtures` host for supplier feed downloads
# (the SSRF guard rightly blocks private hosts in production).
SUPPLIER_BLOCK_PRIVATE_HOSTS = False
# Same escape hatch for django_atlas source feeds (its own url_guard).
ATLAS_BLOCK_PRIVATE_HOSTS = False

# Lookup module (django_lookup): image embeddings from the in-network `embed` container
# (make embed). Model/dim mirror .env — the HalfVectorField dimension must match EMBED_DIM.
#
# `/embeddings_image`, NEVER `/embeddings`. Infinity exposes both, and the text route answers 200
# for an image data URL by embedding the *string* — every catalog photo shares the
# `data:image/jpeg;base64,` prefix, so they all collapse onto one vector and image blocking dies
# without a single error in the logs. Measured on this stack 2026-08-25: through `/embeddings` a
# black and a white square come back at cosine 1.0000 (identical), through `/embeddings_image` at
# 0.9264. `manage.py lookup_doctor` is the handshake that catches this.
LOOKUP_EMBEDDING = {
    "provider": "http",
    "url": "http://embed:7997/embeddings_image",
    "model": config("EMBED_MODEL", default="google/siglip-so400m-patch14-384"),
    "dim": config("EMBED_DIM", default=1152, cast=int),
    "timeout_s": 10,
}
LOOKUP_EMBED_ALLOWED_HOSTS = ["embed"]
LOOKUP_IMAGE_ENABLED = True
# Dev-only: atlas source images live on the in-network `fixtures` host, which django_lookup's own
# SSRF guard blocks by default (same escape hatch as ATLAS_BLOCK_PRIVATE_HOSTS above).
LOOKUP_BLOCK_PRIVATE_HOSTS = False
# kind -> provider module (plan 03). Each entry is imported lazily by django_lookup's registry,
# so a missing module only breaks that kind — the rest of the stack boots. A kind follows the recipe's apps.
LOOKUP_PROVIDERS: dict[str, str] = {}
if _enabled("django_lookup", "django_pim"):
    LOOKUP_PROVIDERS["pim_product"] = "django_pim.services.lookup_provider"
    if _enabled("django_atlas"):
        LOOKUP_PROVIDERS["atlas_source_product"] = "django_atlas.services.lookup_provider"

# Enrichment bus adapters (plan 06): target_module -> dotted module path, imported lazily by
# django_enrichment's registry. `atlas` serves the duplicate_in_pim acceptance queue (SpawnRule
# `atlas-duplicate-in-pim` -> proposal -> accepted link on SourceProduct.real_product); `pim` is the referential
# adapter (attribute values, pictures, classification). A target follows the recipe's apps.
_ENRICHMENT_TARGETS = {
    "atlas": "django_atlas.services.enrichment_adapter",
    "pim": "django_pim.services.enrichment_adapter",
}
ENRICHMENT_ADAPTERS: dict[str, str] = {
    target: path for target, path in _ENRICHMENT_TARGETS.items() if _enabled("django_enrichment", f"django_{target}")
}

# The demo carries 18 months of simulated history: price history and pricefighter decisions outlive the 365-day default.
PRICE_HISTORY_RETENTION_DAYS = 730
PRICEFIGHTER_DECISION_RETENTION_DAYS = 730

# Leads platform — mail goes to the in-network GreenMail sandbox (make mail), never out.
# django_email resolves SMTP per channel; the global EMAIL_HOST is the fallback for every sender except
# django_communicator, which sends nothing without the channel's entry (`communicator.smtp` check).
# ZENO_CHANNELS are the channel idxs the harness configures per channel: Emporium's and the Słoik Chwil ones.
ZENO_CHANNELS = ("default-europe", "sloik-pl", "sloik-eu", "sloik-firmy", "sloik-bdd")
EMAIL_HOST = "greenmail"
EMAIL_PORT = 3025
DEFAULT_FROM_EMAIL = "zeno@greenmail.test"
# OUTREACH_SMTP_* in .env point every channel at a real server (a "sandbox canary": the channels stay in sandbox
# mode, so every mail still goes to its sandbox mailbox). Unset = GreenMail, the BDD baseline.
_OUTREACH_SMTP = {
    "EMAIL_HOST": config("OUTREACH_SMTP_HOST", default="greenmail"),
    "EMAIL_PORT": config("OUTREACH_SMTP_PORT", default=3025, cast=int),
    "EMAIL_HOST_USER": config("OUTREACH_SMTP_USER", default="sandbox"),
    "EMAIL_HOST_PASSWORD": config("OUTREACH_SMTP_PASSWORD", default="sandbox"),
    "EMAIL_USE_SSL": config("OUTREACH_SMTP_USE_SSL", default=False, cast=bool),
    "EMAIL_USE_TLS": config("OUTREACH_SMTP_USE_TLS", default=False, cast=bool),
    "DEFAULT_FROM_EMAIL": config("OUTREACH_SMTP_FROM", default="outreach@greenmail.test"),
}
EMAIL_SMTP_CONFIGURATION_CHANNELS = {channel: _OUTREACH_SMTP for channel in ZENO_CHANNELS}
# A real server shares that entry with EVERY module on the channel (notifications, contact forms, accounts,
# checkout …) — the communicator's sandbox mode alone would not stop them. So with a real host, every recipient of
# every mail is rewritten to ZENO_MAIL_REDIRECT_TO at the transport; without it the service refuses to boot.
if _OUTREACH_SMTP["EMAIL_HOST"] != "greenmail":
    from django.core.exceptions import ImproperlyConfigured
    from django.core.mail.backends.smtp import EmailBackend as _SmtpBackend

    ZENO_MAIL_REDIRECT_TO = config("ZENO_MAIL_REDIRECT_TO", default="")
    if not ZENO_MAIL_REDIRECT_TO:
        raise ImproperlyConfigured("OUTREACH_SMTP_HOST is a real server: set ZENO_MAIL_REDIRECT_TO in .env")

    class RedirectAllBackend(_SmtpBackend):
        """Every recipient becomes ZENO_MAIL_REDIRECT_TO; the original ones travel in X-Zeno-Original-To."""

        def send_messages(self, email_messages):
            for message in email_messages:
                message.extra_headers["X-Zeno-Original-To"] = ", ".join(message.recipients())
                message.to, message.cc, message.bcc = [ZENO_MAIL_REDIRECT_TO], [], []
            return super().send_messages(email_messages)

    EMAIL_BACKEND = "main.settings_local.RedirectAllBackend"
# No COMMUNICATOR_IMAP_* settings: the communicator reads its MailboxConfig row, which the
# communicator fixture points at greenmail:3143 (sandbox/sandbox, no SSL).
# Every notifications sink in zeno is a sandbox (GreenMail, blank webhook), so live sends are allowed
# outside production here only.
NOTIFICATIONS_ALLOW_LIVE_SENDS = True

# Site audits read recorded PSI/URLScan answers from the in-network `fixtures` host
# (siteintel maps `{base}/{domain}.{strategy}.json` — no trailing slash).
SITEINTEL_PSI_BASE_URL = "http://fixtures:8000/fixtures/siteintel/psi"
SITEINTEL_URLSCAN_BASE_URL = "http://fixtures:8000/fixtures/siteintel/urlscan"
# Dev-only: same SSRF escape hatch as the lookup/atlas ones above, narrowed to `fixtures`.
SITEINTEL_BLOCK_PRIVATE_HOSTS = False
SITEINTEL_ALLOWED_HOSTS = ["fixtures"]

# AI toolbox outside zeno (make toolbox-check); compose passes these from .env. AI_TOOLBOX_ENABLED=0 switches
# the AI features off on purpose (munin reports the toolbox as `disabled`); unset keeps it enabled.
AI_TOOLBOX_ENABLED = config("AI_TOOLBOX_ENABLED", default=True, cast=bool)
AI_TOOLBOX_BASE_URL = config("AI_TOOLBOX_BASE_URL", default="http://host.docker.internal:8300")
AI_TOOLBOX_API_KEY = config("AI_TOOLBOX_API_KEY", default="")
AI_TOOLBOX_CHANNEL = config("AI_TOOLBOX_CHANNEL", default="zeno-test")
# Dev-only outage switch (django_utils.toolbox.outage): communicator `test/toolbox-outage/` fails every toolbox
# call as a refused connection — `@toolbox-down` BDD simulates an outage without stopping the toolbox.
AI_TOOLBOX_TEST_SWITCH = True

# Leads platform: rotation, retention and form consent keys the funnel relies on.
LEADS_ROTATION_MAX = 2
LEADS_RETENTION_DAYS = 180
LEADS_FORM_CONSENT_KEYS = ["marketing_consent"]
# A queued CSV import is written by `service` and read by `worker`: the path is the `leads_import_tmp`
# volume mounted into both (docker-compose.yml and docker-compose.dev.yml).
LEADS_IMPORT_TMP_DIR = "/tmp/django_leads"

# Real cadence for the `beat` container (default file scheduler, no django-celery-beat).
# BDD drives the same tasks through the modules' test endpoints instead of waiting for beat.
CELERY_BEAT_SCHEDULE = {
    "communicator-send-due": {"task": "django_communicator.send_due", "schedule": 300},
    "communicator-poll-inbox": {"task": "django_communicator.poll_inbox", "schedule": 300},
    "communicator-schedule-follow-ups": {"task": "django_communicator.schedule_follow_ups", "schedule": 3600},
    # After a toolbox outage: transiently failed drafts / intel analyses retried once the toolbox answers.
    "communicator-retry-drafts": {"task": "django_communicator.retry_failed_drafts", "schedule": 600},
    "siteintel-expire-audits": {"task": "django_siteintel.expire_audits", "schedule": crontab(hour=3, minute=0)},
    "siteintel-sweep-stuck": {"task": "django_siteintel.sweep_stuck_audits", "schedule": crontab(minute="*/10")},
    "leads-fail-stale-imports": {"task": "django_leads.fail_stale_import_batches", "schedule": 600},
    "leads-retry-analyses": {"task": "django_leads.retry_failed_analyses", "schedule": 600},
    "leads-anonymise-inactive": {"task": "django_leads.anonymise_inactive", "schedule": crontab(hour=4, minute=0)},
    "leads-rotate-unresponsive": {"task": "django_leads.rotate_unresponsive", "schedule": crontab(hour=5, minute=0)},
    "notifications-escalate": {"task": "django_notifications.escalate", "schedule": 60},
}
# An entry stays only when the app of its task (`django_<x>.…`) is enabled.
CELERY_BEAT_SCHEDULE = {
    name: entry for name, entry in CELERY_BEAT_SCHEDULE.items() if _enabled(entry["task"].split(".")[0])
}

# QMS strategy: the demo package channels are XRAY (CSV-driven quantities);
# without this the default (ZULU) runs the wrong chain and no catalog stock appears.
QMS_TYPE = "XRAY"

# django_matrix signal batching expects the django-redis client API on the default cache.
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": REDIS_URL + "/1",
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
        "KEY_PREFIX": "zeno",
    }
}

# Guard until the service release registers it itself: django_accounts customer views (@authenticate) call
# django.contrib.auth.authenticate(request), which only tries these backends. Without JWTAccessBackend the
# customer Bearer token is never read and customer/me, profile, addresses, wishlist, checkout are all 401.
# ModelBackend stays for the admin login.
AUTHENTICATION_BACKENDS = ["django.contrib.auth.backends.ModelBackend"]
if "django_accounts" in LOCAL_APPS:
    AUTHENTICATION_BACKENDS.insert(0, "django_accounts.backends.JWTAccessBackend")

# Access gate (django_access): enforce | observe | off; compose passes ACCESS_GATE_MODE from .env.
ACCESS_GATE_MODE = config("ACCESS_GATE_MODE", default="enforce")

# django_crypt Fernet key (zeno dev-only value).
CRYPT_SALT = config("CRYPT_SALT", default="rBMA89uk1jFlCu-Z-c_0z2rFENZwx83hRCbIw53eZOg=")

# Public OpenAPI specs (make schema): audience split, v2 filter, tag groups; used only through spectacular
# --custom-settings.
SCHEMA_AUTH_PATHS = ("/api/token/", "/api/token/refresh/")
SCHEMA_ADMIN_EXTRA_PREFIXES = ("/api/munin/v2/health/",)
# Development-only BDD routes (404 outside development): never published.
_SCHEMA_DEV_ROUTE = re.compile(r"^/api/[^/]+/v2/admin/\{channel_idx\}/test/")
_SCHEMA_CHANNEL = "{channel_idx}"
_SCHEMA_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")
_SCHEMA_UNSORTED = "Unsorted"
# Group -> module slugs (the path segment after /api/), in display order.
SCHEMA_TAG_GROUPS: dict[str, tuple[str, ...]] = {
    "Authentication": ("token",),
    "Catalog": ("pim", "pricemanager", "qms", "matrix", "lookup", "enrichment"),
    "Content and Translation": ("contentdb", "faq", "pim-translator", "contentdb-translator"),
    "Checkout": ("checkout", "deliverypoints"),
    "Customers and Consents": ("accounts", "agreements"),
    "Suppliers and Market Data": ("suppliers", "atlas", "pricefighter"),
    "Leads and Forms": ("leads", "communicator", "siteintel", "contact-forms"),
    "Platform": ("access", "munin", "regional", "email", "notifications"),
}


def _schema_keeps(path: str) -> bool:
    versioned = path.startswith("/api/") and "/v2/" in path
    return (versioned or path in SCHEMA_AUTH_PATHS) and not _SCHEMA_DEV_ROUTE.match(path)


def _schema_public(endpoints: list[tuple]) -> list[tuple]:
    """v2 routes plus the token pair; a global GET goes when its channel-scoped twin exists (writes stay)."""
    kept = [endpoint for endpoint in endpoints if _schema_keeps(endpoint[0])]
    splits = (endpoint[0].partition(_SCHEMA_CHANNEL) for endpoint in kept)
    twins = {before.rstrip("/") + after for before, found, after in splits if found}
    return [endpoint for endpoint in kept if not (endpoint[2] == "GET" and endpoint[0] in twins)]


def _schema_is_admin(path: str) -> bool:
    return "/v2/admin/" in path or path.startswith(SCHEMA_ADMIN_EXTRA_PREFIXES) or path in SCHEMA_AUTH_PATHS


def schema_admin_endpoints(endpoints: list[tuple]) -> list[tuple]:
    return [endpoint for endpoint in _schema_public(endpoints) if _schema_is_admin(endpoint[0])]


def schema_storefront_endpoints(endpoints: list[tuple]) -> list[tuple]:
    return [endpoint for endpoint in _schema_public(endpoints) if not _schema_is_admin(endpoint[0])]


def _schema_groups_by_tag(result: dict) -> dict[str, set[str]]:
    """Tag -> the groups of the modules whose operations carry it."""
    module_group = {module: group for group, modules in SCHEMA_TAG_GROUPS.items() for module in modules}
    groups: dict[str, set[str]] = {}
    for path, item in result["paths"].items():
        group = module_group.get(path.split("/")[2], _SCHEMA_UNSORTED)
        operations = (operation for method, operation in item.items() if method in _SCHEMA_METHODS)
        for tag in (tag for operation in operations for tag in operation.get("tags", [])):
            groups.setdefault(tag, set()).add(group)
    return groups


def _schema_tag_groups(result: dict) -> dict:
    """Declare every used tag and group it; a tag over two groups or of an unmapped module is Unsorted."""
    tags: dict[str, list[str]] = {group: [] for group in (*SCHEMA_TAG_GROUPS, _SCHEMA_UNSORTED)}
    for tag, groups in sorted(_schema_groups_by_tag(result).items()):
        tags[next(iter(groups)) if len(groups) == 1 else _SCHEMA_UNSORTED].append(tag)
    result["tags"] = [{"name": tag} for names in tags.values() for tag in names]
    result["x-tagGroups"] = [{"name": group, "tags": names} for group, names in tags.items() if names]
    return result


def schema_postprocess(result: dict, generator: object, **kwargs: object) -> dict:
    """The service's own post-processing hooks first (read at call time), then the tag groups."""
    from django.conf import settings
    from django.utils.module_loading import import_string
    from drf_spectacular.settings import SPECTACULAR_DEFAULTS

    hooks = settings.SPECTACULAR_SETTINGS.get("POSTPROCESSING_HOOKS", SPECTACULAR_DEFAULTS["POSTPROCESSING_HOOKS"])
    for hook in hooks:
        hook = import_string(hook) if isinstance(hook, str) else hook
        result = hook(result=result, generator=generator, **kwargs)
    return _schema_tag_groups(result)


SCHEMA_ADMIN = {
    "SCHEMA_PATH_PREFIX": r"/api/",
    "PREPROCESSING_HOOKS": ["main.settings_local.schema_admin_endpoints"],
    "POSTPROCESSING_HOOKS": ["main.settings_local.schema_postprocess"],
    "TITLE": "Entirius Admin API",
    "DESCRIPTION": (
        "Admin REST API of the Entirius backend: the endpoints the admin CMS uses for catalog, content, checkout, "
        "customers, suppliers, leads and platform settings. Admin endpoints require a staff user: get a JWT pair "
        "from `POST /api/token/` and send `Authorization: Bearer <access>`. Guides: https://docs.entirius.com/api/"
    ),
}
SCHEMA_STOREFRONT = {
    "SCHEMA_PATH_PREFIX": r"/api/",
    "PREPROCESSING_HOOKS": ["main.settings_local.schema_storefront_endpoints"],
    "POSTPROCESSING_HOOKS": ["main.settings_local.schema_postprocess"],
    "TITLE": "Entirius Storefront API",
    "DESCRIPTION": (
        "Storefront REST API of the Entirius backend: catalog and search, cart and checkout, content, forms, consents "
        "and delivery points, scoped to a sales channel (`channel_idx` in the path). Authentication differs per "
        "endpoint: each operation lists the schemes it accepts, and https://docs.entirius.com/api/authentication/ "
        "explains them."
    ),
}
