"""
entirius-zeno settings_local.py for the service under test.

Every environment must provide its own settings_local.py — this is zeno's.
It bridges compose env vars to Django settings; baked into the image at build
and refreshed on every dev-mode start. Change .env on the host, not this file.
"""

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
    "django_crm",
]

# django_crypt Fernet key (zeno dev-only value).
CRYPT_SALT = config("CRYPT_SALT", default="rBMA89uk1jFlCu-Z-c_0z2rFENZwx83hRCbIw53eZOg=")
