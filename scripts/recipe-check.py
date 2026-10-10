#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Validates a recipe (recipes/<name>/) against the service's module registry.

    python3 scripts/recipe-check.py <name> <path to modules.yaml>      # make recipe-check RECIPE=<name>

Prints `recipe-check: <name> ok (<a> apps, <q> queues)`, or one line per problem and exits 1.
"""

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("recipe-check: PyYAML is missing — install it for python3 (pip install pyyaml, or your distro's package)")

RECIPES = Path(__file__).resolve().parent.parent / "recipes"
DEFAULT_QUEUE = "celery"
SEED_PROFILE = "full"
RECIPE_FILES = ("apps.txt", "queues.txt", "seed-profile", "README.md")


def entries(path: Path) -> list[str]:
    """Lines of a recipe list; `#` starts a comment, blank lines are dropped."""
    lines = (line.partition("#")[0].strip() for line in path.read_text().splitlines())
    return [line for line in lines if line]


def duplicates(items: list[str]) -> list[str]:
    return sorted({item for item in items if items.count(item) > 1})


def app_problems(apps: list[str], registry: dict) -> list[str]:
    known = {app for module in registry["modules"] for app in module["apps"]}
    platform = {app for module in registry.get("platform", []) for app in module["apps"]}
    return [
        *(f"{app} is enabled by the service itself" for app in apps if app in platform),
        *(f"{app} is not an app of modules.yaml" for app in apps if app not in known | platform),
        *(f"{app} is listed twice in apps.txt" for app in duplicates(apps)),
    ]


def needed_apps(module: dict, registry: dict) -> list[str]:
    """Apps that must come with the module: those of its `requires` (a platform dist counts as present), its own."""
    by_dist = {other["dist"]: other["apps"] for other in registry["modules"]}
    platform = {other["dist"] for other in registry.get("platform", [])}
    required = [app for dist in module["requires"] if dist not in platform for app in by_dist[dist]]
    return [*required, *module["also_enable"]]


def module_problems(module: dict, apps: list[str], registry: dict) -> list[str]:
    name, first = module["dist"], min(apps.index(app) for app in module["apps"] if app in apps)
    needed = needed_apps(module, registry)
    return [
        *(f"{name} needs {app}, which apps.txt does not list" for app in needed if app not in apps),
        *(f"{app} must come before {name} in apps.txt" for app in needed if app in apps and apps.index(app) > first),
    ]


def queue_problems(queues: list[str], enabled: list[dict]) -> list[str]:
    wanted = {DEFAULT_QUEUE, *(queue for module in enabled for queue in module["queues"])}
    return [
        *(f"queues.txt lacks {queue}" for queue in sorted(wanted - set(queues))),
        *(f"queues.txt lists {queue}, which no enabled module uses" for queue in sorted(set(queues) - wanted)),
        *(f"{queue} is listed twice in queues.txt" for queue in duplicates(queues)),
    ]


def file_problems(recipe: Path) -> list[str]:
    profile = (recipe / "seed-profile").read_text().split()
    readme = (recipe / "README.md").read_text()
    return [
        *([] if profile == [SEED_PROFILE] else [f"seed-profile must be {SEED_PROFILE}"]),
        *(["README.md is empty"] if not readme.strip() else []),
        *(["README.md must not have a heading"] if any(line.startswith("#") for line in readme.splitlines()) else []),
    ]


def problems(recipe: Path, registry: dict) -> list[str]:
    apps, queues = entries(recipe / "apps.txt"), entries(recipe / "queues.txt")
    enabled = [module for module in registry["modules"] if set(module["apps"]) & set(apps)]
    core = [module for module in registry["modules"] if module["core"] and module not in enabled]
    return [
        *app_problems(apps, registry),
        *(f"{module['dist']} is a core module: apps.txt must list it" for module in core),
        *(problem for module in enabled for problem in module_problems(module, apps, registry)),
        *queue_problems(queues, enabled),
        *file_problems(recipe),
    ]


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: recipe-check.py <recipe> <modules.yaml>")
    name, registry = sys.argv[1], Path(sys.argv[2])
    recipe = RECIPES / name
    files = (registry, *(recipe / file for file in RECIPE_FILES))
    if missing := [path for path in files if not path.is_file()]:
        sys.exit("\n".join(f"recipe-check: {path} not found" for path in missing))
    if found := problems(recipe, yaml.safe_load(registry.read_text())):
        sys.exit("\n".join(f"recipe-check: {name}: {problem}" for problem in found))
    apps, queues = entries(recipe / "apps.txt"), entries(recipe / "queues.txt")
    print(f"recipe-check: {name} ok ({len(apps)} apps, {len(queues)} queues)")


if __name__ == "__main__":
    main()
