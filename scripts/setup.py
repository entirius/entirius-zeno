#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""One command from a bare checkout to a seeded, testable stack.

    make setup                      # release refs: modules at the service uv.lock tags
    make setup REFS=develop         # integration: every clean clone on develop
    make setup REFS="feature/x feature/y"   # a feature world: each clean clone (service and docs included) on the
                                    # first listed branch it has (local or origin), else develop; + the docs portal
    SETUP_DRY=1 make setup REFS=…   # print which ref every clone would land on; change nothing
    make setup EMBED=1              # also start the embedding service (lookup)
    make setup SEED=0               # stop before seeding
    SERVICE_BRANCH=<branch> python3 scripts/setup.py   # service branch other than .env for one run

Order matters: clones before the stack (bind mounts), mail + CMS before seed, toolbox checked before seed.
A missing toolbox is not fatal: the stack runs in degraded mode (AI drafts and intel fail visibly) and
recovers on its own once the toolbox is back (beat retries transient failures).
"""

import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLONE_GROUPS = ("repos/py", "repos/django", "repos/tests", "repos/pwa")
# A feature world also moves the service under test and the docs portal clone.
WORLD_GROUPS = (*CLONE_GROUPS, "repos/services", "repos/docs")


def step(title):
    print(f"\n=== {title} ===", flush=True)


def run(*cmd, env=None, check=True):
    result = subprocess.run(
        cmd, cwd=ROOT, env={**os.environ, **(env or {})}, check=False
    )
    if check and result.returncode:
        sys.exit(f"setup: `{' '.join(cmd)}` failed (exit {result.returncode})")
    return result.returncode


def git(repo, *args):
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=False
    )


def env_value(key, default):
    env_file = ROOT / ".env"
    for line in env_file.read_text().splitlines() if env_file.exists() else []:
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1].strip()
    return default


def preflight():
    step("1/7 preflight")
    if subprocess.run(["docker", "info"], capture_output=True, check=False).returncode:
        sys.exit("setup: docker is not reachable")
    if not (ROOT / ".env").exists():
        run("make", "init")
    print("docker ok, .env present")


def clones(refs):
    step(f"2/7 clones ({refs})")
    service = env_value("SERVICE", "entirius-service-volkanos")
    if not (ROOT / "repos/services" / service / "pyproject.toml").exists():
        run("make", "clone")
    run("make", "clone-tests")
    run(
        "make",
        "clone-repos",
        env={"CLONE_REF": "lock" if refs == "release" else "develop"},
    )
    if refs == "release":
        branch = os.environ.get("SERVICE_BRANCH") or env_value(
            "SERVICE_BRANCH", "develop"
        )
        run("make", "refresh-repos", f"SERVICE_BRANCH={branch}")
    elif refs == "develop":
        switch_to_develop()
    else:
        switch_to_world(refs.split())


def switch_to_develop():
    for group in CLONE_GROUPS:
        for repo in sorted((ROOT / group).glob("*/.git")):
            repo = repo.parent
            if git(
                repo, "status", "--porcelain", "--untracked-files=no"
            ).stdout.strip():
                print(f"  skip (dirty): {repo.relative_to(ROOT)}")
                continue
            git(repo, "fetch", "--quiet", "origin")
            if git(
                repo, "rev-parse", "--verify", "--quiet", "origin/develop"
            ).returncode:
                print(f"  skip (no develop): {repo.relative_to(ROOT)}")
                continue
            git(repo, "switch", "--quiet", "develop")
            pulled = (
                git(repo, "merge", "--ff-only", "--quiet", "origin/develop").returncode
                == 0
            )
            print(
                f"  develop{'' if pulled else ' (local commits, not fast-forwarded)'}: {repo.relative_to(ROOT)}"
            )


def world_ref(repo, branches):
    """The first listed branch the clone has (local first, then origin), else develop; None when neither exists."""
    for branch in branches:
        if not git(repo, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}").returncode:
            return branch, "local"
        if not git(repo, "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{branch}").returncode:
            return branch, "origin"
    if not git(repo, "rev-parse", "--verify", "--quiet", "origin/develop").returncode:
        return "develop", "origin"
    return None, None


def switch_to_world(branches, dry=False):
    """Every clean clone onto the first branch of `branches` it has, else develop — dirty clones are never touched."""
    rows = []
    for group in WORLD_GROUPS:
        for repo in sorted((ROOT / group).glob("*/.git")):
            repo = repo.parent
            name = str(repo.relative_to(ROOT))
            if (repo / ".git").is_file():  # a linked worktree (hotfix agent, stream 2): it owns its branch, never moved
                rows.append((name, git(repo, "branch", "--show-current").stdout.strip() or "detached", "skip: worktree"))
                continue
            if git(repo, "status", "--porcelain", "--untracked-files=no").stdout.strip():
                rows.append((name, git(repo, "branch", "--show-current").stdout.strip() or "detached", "skip: dirty"))
                continue
            git(repo, "fetch", "--quiet", "origin")
            branch, where = world_ref(repo, branches)
            if branch is None:
                rows.append((name, "-", "skip: no listed branch and no develop"))
                continue
            note = "" if branch in branches else "fallback"
            if not dry:
                if where == "local" or branch == "develop":
                    git(repo, "switch", "--quiet", branch)
                else:
                    git(repo, "switch", "--quiet", "--track", "-c", branch, f"origin/{branch}")
                if where == "origin":
                    git(repo, "merge", "--ff-only", "--quiet", f"origin/{branch}")
                if (git(repo, "branch", "--show-current").stdout.strip() or "detached") != branch:
                    note = "SWITCH FAILED"
            rows.append((name, branch, note))
    width = max(len(row[0]) for row in rows) if rows else 0
    for name, branch, note in rows:
        print(f"  {name:<{width}}  {branch}{('  (' + note + ')') if note else ''}")
    on_branch = sum(1 for _, branch, _ in rows if branch in branches)
    print(f"  {on_branch} clone(s) on {' / '.join(branches)}, the rest on develop or skipped")


def wait_http(url, seconds):
    for _ in range(seconds // 5):
        try:
            with urllib.request.urlopen(url, timeout=4) as response:
                if response.status == 200:
                    return True
        except OSError:
            pass
        time.sleep(5)
    return False


def stack(embed, docs=False):
    step("3/7 stack (dev mode, mail sandbox, CMS)")
    run("make", "dev")
    port = env_value("SERVICE_PORT", "8100")
    if not wait_http(f"http://localhost:{port}/api/schema/", 600):
        sys.exit(
            "setup: the service did not answer /api/schema/ — see `docker compose logs service`"
        )
    run("make", "mail")
    run("make", "cms-dev")
    if embed:
        run("make", "embed")
    if docs:
        run("make", "docs")


def toolbox():
    step("4/7 AI toolbox")
    if run("make", "toolbox-check", check=False) == 0:
        return "full"
    print("WARNING: toolbox unreachable or misconfigured — DEGRADED mode.")
    print(
        "  The stack works; AI drafts end `failed`, leads intel is skipped, munin reports toolbox unreachable."
    )
    print(
        "  Expect the AI scenarios (communicator drafts, @funnel) to fail in `make bdd`."
    )
    print(
        "  Recovery is automatic: once the toolbox answers, beat retries transiently failed drafts and intel"
    )
    print("  analyses every 10 min (at most 3 times each) — new drafts still wait for review.")
    return "degraded"


def seed():
    step("5/7 seed (fresh database, ~10 min)")
    run("make", "seed")


def summary(mode, seeded):
    step("6/7 URLs")
    run("make", "urls", check=False)
    step("7/7 next")
    print(f"toolbox mode: {mode} · seeded: {'yes' if seeded else 'no (SEED=0)'}")
    print("  make bdd          # full BDD (fresh seed; one-shot scenarios consume it)")
    print("  make e2e-funnel   # leads funnel e2e, phone + desktop")
    print("  make e2e-accept   # AI-tester acceptance (make runner-init once)")


def main():
    refs = os.environ.get("REFS", "release").strip() or "release"
    world = refs not in ("release", "develop")
    if os.environ.get("SETUP_DRY") == "1":
        if not world:
            sys.exit("setup: SETUP_DRY needs a feature world (REFS=<branch …>)")
        step(f"dry run: where each clone would land ({refs})")
        switch_to_world(refs.split(), dry=True)
        return
    preflight()
    clones(refs)
    stack(os.environ.get("EMBED") == "1", docs=world and (ROOT / "repos/docs/entirius-docs/.git").exists())
    mode = toolbox()
    seeded = os.environ.get("SEED", "1") != "0"
    if seeded:
        seed()
    summary(mode, seeded)


if __name__ == "__main__":
    main()
