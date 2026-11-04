#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Inventory for a PR review across the `entirius` GitHub org.

    python3 scripts/pr-review/inventory.py [--sync]      # make pr-inventory [SYNC=1]

Prints Markdown: clone state, open PRs (author type, base, size, CI, mergeable, age) and the public docs drift
(docs.entirius.com spec, demo-api and the latest releases against the docs' platform.json). `--sync` first puts
every clean clone in repos/ on develop (or its only branch), level with origin; a dirty clone or one with commits
origin lacks is left alone and listed. Worktrees are never touched. Needs `gh` (authenticated) and `git`.
"""

import json
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

ORG = "entirius"
ROOT = Path(__file__).resolve().parent.parent.parent
CLONE_GLOBS = (
    "repos/django/*",
    "repos/py/*",
    "repos/services/*",
    "repos/tests/*",
    "repos/pwa/*",
)
DOCS = ROOT / "repos/docs/entirius-docs"
SPEC_URLS = {
    "docs spec (admin)": "https://docs.entirius.com/openapi/volkanos-api-admin.yaml",
    "docs spec (storefront)": "https://docs.entirius.com/openapi/volkanos-api-storefront.yaml",
    "demo-api": "https://demo-api.entirius.com/api/schema/",
}
PR_FIELDS = "author,baseRefName,additions,deletions,changedFiles,mergeable,isDraft,statusCheckRollup,createdAt,title"
GREEN = {"SUCCESS", "SKIPPED", "NEUTRAL"}
USER_AGENT = "entirius-zeno-pr-inventory"  # Cloudflare answers 403 to the default Python-urllib agent


def run(*cmd: str, cwd: Path = ROOT) -> str:
    """stdout of a command; raises CalledProcessError on a non-zero exit."""
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=True
    ).stdout.strip()


def git(repo: Path, *args: str) -> str:
    return run("git", "-C", str(repo), *args)


# --- clones ------------------------------------------------------------------------------------------------------


def main_clones() -> list[Path]:
    """Clones whose .git is a directory (worktrees have a .git file), plus the docs clone."""
    found = [
        p for g in CLONE_GLOBS for p in sorted(ROOT.glob(g)) if (p / ".git").is_dir()
    ]
    return found + ([DOCS] if (DOCS / ".git").is_dir() else [])


def target_branch(repo: Path) -> str:
    if (
        subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "-q", "--verify", "origin/develop"],
            capture_output=True,
            check=False,
        ).returncode
        == 0
    ):
        return "develop"
    return git(repo, "rev-parse", "--abbrev-ref", "origin/HEAD").removeprefix("origin/")


def sync_clone(repo: Path) -> str:
    """Puts one clone on its target branch level with origin; returns '' or the reason it was left alone."""
    git(repo, "fetch", "-q", "--all", "--prune")
    if git(repo, "status", "--porcelain"):
        return "dirty"
    target = target_branch(repo)
    if git(repo, "branch", "--show-current") != target:
        if not git(repo, "branch", "-r", "--contains", "HEAD"):
            return "commits origin lacks"
        git(repo, "checkout", "-q", target)
    git(repo, "branch", "-q", "--set-upstream-to", f"origin/{target}")
    git(repo, "merge", "-q", "--ff-only", f"origin/{target}")
    return ""


def clone_state(repo: Path, sync: bool) -> tuple[str, str]:
    """(branch, note) for one clone; note is empty when the clone is level with its upstream."""
    try:
        note = sync_clone(repo) if sync else ""
    except subprocess.CalledProcessError as exc:
        note = f"sync failed: {exc.stderr.strip().splitlines()[-1] if exc.stderr.strip() else exc}"
    branch = git(repo, "branch", "--show-current") or "(detached)"
    if not note:
        behind_ahead = subprocess.run(
            [
                "git",
                "-C",
                str(repo),
                "rev-list",
                "--left-right",
                "--count",
                "@{u}...HEAD",
            ],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.split()
        note = (
            ""
            if behind_ahead == ["0", "0"]
            else f"behind/ahead {'/'.join(behind_ahead) or 'no upstream'}"
        )
    return branch, note


def clones_section(sync: bool) -> list[str]:
    clones = main_clones()
    with ThreadPoolExecutor(max_workers=8) as pool:
        states = list(pool.map(lambda r: clone_state(r, sync), clones))
    off = [(r, b, n) for r, (b, n) in zip(clones, states, strict=True) if n]
    lines = [
        f"## Clones\n\n{len(clones)} main clones, {len(clones) - len(off)} level with origin.\n"
    ]
    if off:
        lines += ["| Clone | Branch | Note |", "|---|---|---|"]
        lines += [f"| `{r.relative_to(ROOT)}` | `{b}` | {n} |" for r, b, n in off]
    return lines


# --- pull requests -----------------------------------------------------------------------------------------------


@dataclass
class Pr:
    repo: str
    number: int
    data: dict


def open_prs() -> list[Pr]:
    found = json.loads(
        run(
            "gh",
            "search",
            "prs",
            "--owner",
            ORG,
            "--state",
            "open",
            "--limit",
            "200",
            "--json",
            "repository,number",
        )
    )
    refs = [(p["repository"]["name"], p["number"]) for p in found]
    with ThreadPoolExecutor(max_workers=8) as pool:
        views = pool.map(
            lambda r: run(
                "gh",
                "pr",
                "view",
                str(r[1]),
                "-R",
                f"{ORG}/{r[0]}",
                "--json",
                PR_FIELDS,
            ),
            refs,
        )
        return [
            Pr(repo, number, json.loads(view))
            for (repo, number), view in zip(refs, views, strict=True)
        ]


def author_type(author: dict, members: set[str]) -> str:
    login = author["login"]
    if author.get("is_bot") or login.endswith("[bot]") or login.startswith("app/"):
        return "bot"
    return "team" if login in members else "external"


def ci_state(checks: list[dict]) -> str:
    if not checks:
        return "none"
    red = sorted(
        {
            c.get("name") or c.get("context") or "?"
            for c in checks
            if (c.get("conclusion") or c.get("state")) not in GREEN
        }
    )
    return "green" if not red else "red/pending: " + ", ".join(red)


def pr_row(pr: Pr, members: set[str], today: datetime) -> str:
    d = pr.data
    age = (today - datetime.fromisoformat(d["createdAt"])).days
    kind = author_type(d["author"], members) + (" draft" if d["isDraft"] else "")
    return (
        f"| {pr.repo} | #{pr.number} | {d['author']['login']} ({kind}) | {d['baseRefName']} "
        f"| +{d['additions']}/-{d['deletions']} {d['changedFiles']}f | {d['mergeable']} "
        f"| {ci_state(d['statusCheckRollup'] or [])} | {age} d | {d['title']} |"
    )


def prs_section() -> list[str]:
    prs = sorted(open_prs(), key=lambda p: (p.repo, p.number))
    members = set(
        run("gh", "api", f"orgs/{ORG}/members", "--paginate", "-q", ".[].login").split()
    )
    today = datetime.now(UTC)
    return [
        f"## Open PRs ({len(prs)})\n",
        "| Repo | PR | Author | Base | Size | Mergeable | CI | Age | Title |",
        "|---|---|---|---|---|---|---|---|---|",
        *(pr_row(p, members, today) for p in prs),
    ]


# --- public docs drift -------------------------------------------------------------------------------------------


def spec_version(url: str) -> str:
    """`info.version` from the first lines of an OpenAPI YAML, without a YAML parser."""
    try:
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=20) as resp:
            head = resp.read(4096).decode(errors="replace")
    except OSError as exc:
        return f"unreachable ({exc})"
    versions = [
        ln.split(":", 1)[1].strip()
        for ln in head.splitlines()
        if ln.startswith("  version:")
    ]
    return versions[0] if versions else "no info.version"


def latest_release(repo: str) -> str:
    return run(
        "gh",
        "release",
        "view",
        "-R",
        f"{ORG}/{repo}",
        "--json",
        "tagName",
        "-q",
        ".tagName",
    ).lstrip("v")


def drift_section() -> list[str]:
    git(DOCS, "fetch", "-q", "origin")
    platform = json.loads(git(DOCS, "show", "origin/master:src/data/platform.json"))
    rows = [
        (name, spec_version(url), platform["service"])
        for name, url in SPEC_URLS.items()
    ]
    rows.append(
        (
            "service release",
            latest_release("entirius-service-volkanos"),
            platform["service"],
        )
    )
    rows.append(("CMS release", latest_release("entirius-pwa-cms"), platform["cms"]))
    lines = [
        (
            f"## Docs drift\n\n`platform.json` on docs master: platform {platform['platform']}, "
            f"service {platform['service']}, CMS {platform['cms']}.\n"
        ),
        "| What | Version | Expected | |",
        "|---|---|---|---|",
    ]
    lines += [
        f"| {n} | {v} | {e} | {'ok' if v == e else 'DRIFT'} |" for n, v, e in rows
    ]
    return lines


def main() -> None:
    sync = "--sync" in sys.argv[1:]
    sections = (clones_section(sync), prs_section(), drift_section())
    print("\n\n".join("\n".join(s) for s in sections))


if __name__ == "__main__":
    main()
