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

# Volkanos modules adopted in this environment (entirius-django-* app labels).
# Order matters: regional before pim — FK targets first.
LOCAL_APPS = ["django_regional", "django_utils", "django_pim"]
