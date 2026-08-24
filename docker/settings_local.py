"""
entirius-zeno settings_local.py for the service under test.

Every environment must provide its own settings_local.py — this is zeno's.
It bridges compose env vars to Django settings; baked into the image at build
and refreshed on every dev-mode start. Change .env on the host, not this file.
"""

import importlib.util

import dj_database_url
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
LOOKUP_EMBEDDING = {
    "provider": "http",
    "url": "http://embed:7997/embeddings",
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
# The PIM create hook is opt-in per deployment (django_pim defaults it to False); the harness wants it on so
# the @lookup BDD scenarios exercise `possible_duplicates`.
PIM_LOOKUP_ON_CREATE = True

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
