"""
entirius-zeno settings_local.py for the service under test.

Every environment must provide its own settings_local.py — this is zeno's.
It bridges compose env vars to Django settings; baked into the image at build
and refreshed on every dev-mode start. Change .env on the host, not this file.
"""

import importlib.util

import dj_database_url
from celery.schedules import crontab
from decouple import Csv, config

ENVIRONMENT = "development"

SECRET_KEY = config("SECRET_KEY", default="django-insecure-zeno-dev-only")
DEBUG = config("DEBUG", default=True, cast=bool)
ALLOWED_HOSTS = config("ALLOWED_HOSTS", default="localhost,127.0.0.1,service", cast=Csv())

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
# so a missing module only breaks that kind — the rest of the stack boots.
LOOKUP_PROVIDERS: dict[str, str] = {
    "pim_product": "django_pim.services.lookup_provider",
    "atlas_source_product": "django_atlas.services.lookup_provider",
}

# Enrichment bus adapters (plan 06): target_module -> dotted module path, imported lazily by
# django_enrichment's registry. `atlas` serves the duplicate_in_pim acceptance queue (SpawnRule
# `atlas-duplicate-in-pim` -> proposal -> accepted link on SourceProduct.real_product).
ENRICHMENT_ADAPTERS: dict[str, str] = {
    "atlas": "django_atlas.services.enrichment_adapter",
}

# Leads platform — mail goes to the in-network GreenMail sandbox (make mail), never out.
# django_email resolves SMTP per channel, so the global EMAIL_HOST is only the fallback;
# the programme's channel idx is `default-europe` everywhere.
EMAIL_HOST = "greenmail"
EMAIL_PORT = 3025
DEFAULT_FROM_EMAIL = "zeno@greenmail.test"
EMAIL_SMTP_CONFIGURATION_CHANNELS = {
    "default-europe": {
        "EMAIL_HOST": "greenmail",
        "EMAIL_PORT": 3025,
        "EMAIL_HOST_USER": "sandbox",
        "EMAIL_HOST_PASSWORD": "sandbox",
        "EMAIL_USE_SSL": False,
        "EMAIL_USE_TLS": False,
        "DEFAULT_FROM_EMAIL": "outreach@greenmail.test",
    }
}
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

# AI toolbox outside zeno (make toolbox-check); compose passes these from .env.
AI_TOOLBOX_BASE_URL = config("AI_TOOLBOX_BASE_URL", default="http://host.docker.internal:8300")
AI_TOOLBOX_API_KEY = config("AI_TOOLBOX_API_KEY", default="")
AI_TOOLBOX_CHANNEL = config("AI_TOOLBOX_CHANNEL", default="zeno-test")

# Leads platform: rotation, retention and form consent keys the funnel relies on.
LEADS_ROTATION_MAX = 2
LEADS_RETENTION_DAYS = 180
LEADS_FORM_CONSENT_KEYS = ["marketing_consent"]

# Real cadence for the `beat` container (default file scheduler, no django-celery-beat).
# BDD drives the same tasks through the modules' test endpoints instead of waiting for beat.
CELERY_BEAT_SCHEDULE = {
    "communicator-send-due": {"task": "django_communicator.send_due", "schedule": 300},
    "communicator-poll-inbox": {"task": "django_communicator.poll_inbox", "schedule": 300},
    "communicator-schedule-follow-ups": {"task": "django_communicator.schedule_follow_ups", "schedule": 3600},
    "siteintel-expire-audits": {"task": "django_siteintel.expire_audits", "schedule": crontab(hour=3, minute=0)},
    "leads-anonymise-inactive": {"task": "django_leads.anonymise_inactive", "schedule": crontab(hour=4, minute=0)},
    "leads-rotate-unresponsive": {"task": "django_leads.rotate_unresponsive", "schedule": crontab(hour=5, minute=0)},
    "notifications-escalate": {"task": "django_notifications.escalate", "schedule": 60},
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

# Volkanos modules adopted in this environment (entirius-django-* app labels).
# Order matters: FK targets first — regional/utils before pim, pim/pricemanager
# before the pim satellites; leaves last.
LOCAL_APPS = [
    "django_regional",
    "django_utils",
    "django_utils_translator",
    "django_pim",
    "django_pricemanager",
    # Private modules — no PyPI release, absent from the service uv.lock; dev mode
    # editable-installs the repos/django/ clones. Guarded by importability so baked
    # mode (make up) and dev without the private clones still boot instead of
    # crash-looping on ModuleNotFoundError.
    # atlas before pricefighter: pricefighter services import django_atlas.
    *(m for m in ("django_atlas", "django_pricefighter") if importlib.util.find_spec(m)),
    # lookup (private, plan 02): fingerprints over PIM + atlas; providers wired by plan 03.
    *(m for m in ("django_lookup",) if importlib.util.find_spec(m)),
    # leads platform (private until their 0.1.0aN pre-releases): toolbox client, then the leaves —
    # leads depends on siteintel + communicator, communicator on notifications.
    *(
        m
        for m in ("django_utils.toolbox", "django_notifications", "django_siteintel", "django_communicator", "django_leads")
        if importlib.util.find_spec(m)
    ),
    "django_pim_csv",
    "django_pim_translator",
    "django_pim_export_to_magento_api",
    "django_faq",
    "django_munin",
    "django_captcha",
    "django_agreements",
    "django_deliverypoints",
    "django_qms",
    "django_email",
    "django_contact_forms",
    "django_regon_api",
    "django_baselinker",
    "django_crypt",
    "django_enrichment",
    "django_contentdb",
    "django_accounts",
    "django_suppliers",
    "django_contentdb_translator",
    "django_sitemap",
    "django_accounts_export_to_magento_api",
    "django_vault",
    "django_reviews",
    "django_matrix",
    "django_checkout",
    "django_checkout_export_to_magento_api",
    "django_checkout_import_from_magento_api",
    "django_getresponse",
    "django_returns",
    "django_omnibus",
]

# django_crypt Fernet key (zeno dev-only value).
CRYPT_SALT = config("CRYPT_SALT", default="rBMA89uk1jFlCu-Z-c_0z2rFENZwx83hRCbIw53eZOg=")
