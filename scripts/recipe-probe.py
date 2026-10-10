#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Boots the service with a recipe's app set inside the running service container; reads, never writes.

    make recipe-probe RECIPE=<name>      # feeds this file to `python - <comma list of apps>` in the container

Builds the settings the service would have with that LOCAL_APPS list, then runs Django's system check, imports
the URL conf and imports every module of every app (tests and migrations excluded). Exit 1 on a boot, check or URL
error, or when a model belongs to an app that is not enabled; other import errors are printed as `note:` (they
do not depend on the app set). Last line: `recipe-probe: <name> ok`.
"""

import importlib
import importlib.util
import os
import sys
import types
from pathlib import Path

ACCESS = "django_access"
ACCESS_MIDDLEWARE = "django_access.middleware.AccessGateMiddleware"
ACCESS_HOOK = "django_access.openapi.add_api_key_security"
DEFAULT_HOOKS = ["drf_spectacular.hooks.postprocess_schema_enums"]
SETTINGS_MODULE = "recipe_probe_settings"
SKIPPED_PARTS = ("tests", "migrations")
NOT_INSTALLED = "isn't in an application in INSTALLED_APPS"


def installed_apps(base: types.ModuleType, local_apps: list[str]) -> list[str]:
    """INSTALLED_APPS the way main/settings.py builds it: access joins wherever its package is importable."""
    access = [ACCESS] if importlib.util.find_spec(ACCESS) else []
    return [*base.DJANGO_APPS, *base.THIRD_PARTY_APPS, *local_apps, *access, "apps.platform"]


def access_settings(base: types.ModuleType, apps: list[str]) -> dict:
    """MIDDLEWARE and SPECTACULAR_SETTINGS as before the service's access block, then with it when access is in."""
    middleware = [entry for entry in base.MIDDLEWARE if entry != ACCESS_MIDDLEWARE]
    spectacular = dict(base.SPECTACULAR_SETTINGS)
    hooks = [hook for hook in spectacular.get("POSTPROCESSING_HOOKS", DEFAULT_HOOKS) if hook != ACCESS_HOOK]
    if ACCESS in apps:
        middleware, hooks = [*middleware, ACCESS_MIDDLEWARE], [*hooks, ACCESS_HOOK]
    return {"MIDDLEWARE": middleware, "SPECTACULAR_SETTINGS": {**spectacular, "POSTPROCESSING_HOOKS": hooks}}


def configure(local_apps: list[str]) -> None:
    """A settings module copied from main.settings with the recipe's app set; Django then boots on it."""
    import django
    from django.conf import settings
    from django.utils.functional import empty

    base = importlib.import_module("main.settings")
    module = types.ModuleType(SETTINGS_MODULE)
    module.__dict__.update({name: value for name, value in vars(base).items() if name.isupper()})
    module.LOCAL_APPS = local_apps
    module.INSTALLED_APPS = installed_apps(base, local_apps)
    module.__dict__.update(access_settings(base, module.INSTALLED_APPS))
    sys.modules[SETTINGS_MODULE] = module
    os.environ["DJANGO_SETTINGS_MODULE"] = SETTINGS_MODULE
    settings._wrapped = empty
    django.setup()


def skipped(parts: tuple[str, ...]) -> bool:
    return bool(set(parts) & set(SKIPPED_PARTS)) or parts[-1].startswith(("test_", "conftest"))


def app_modules(app: str) -> list[str]:
    """Dotted names of the app's modules, tests and migrations left out."""
    root = Path(importlib.import_module(app).__file__).parent
    files = (path.relative_to(root).with_suffix("") for path in sorted(root.rglob("*.py")))
    names = (file.parts[:-1] if file.name == "__init__" else file.parts for file in files)
    return [".".join((app, *parts)) for parts in names if parts and not skipped(parts)]


def import_failures(local_apps: list[str]) -> int:
    """Imports every module of every app; counts the failures that name an app missing from the set."""
    fatal = 0
    for name in dict.fromkeys(module for app in local_apps for module in app_modules(app)):
        try:
            importlib.import_module(name)
        except Exception as error:  # noqa: BLE001 - any import-time failure is reported, none stops the walk
            missing_app = isinstance(error, RuntimeError) and NOT_INSTALLED in str(error)
            fatal += missing_app
            print(f"{'ERROR' if missing_app else 'note'}: {name}: {type(error).__name__}: {error}")
    return fatal


def main() -> None:
    name = os.environ.get("RECIPE") or "shop"
    local_apps = [app for app in sys.argv[1].split(",") if app]
    configure(local_apps)
    from django.conf import settings
    from django.core.management import call_command
    from django.urls import get_resolver

    call_command("check")
    print(f"urls: {len(get_resolver(settings.ROOT_URLCONF).url_patterns)} top-level patterns")
    if fatal := import_failures(local_apps):
        sys.exit(f"recipe-probe: {name} FAILED ({fatal} module(s) need an app the recipe does not enable)")
    print(f"recipe-probe: {name} ok")


if __name__ == "__main__":
    main()
