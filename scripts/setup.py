#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""One command from a bare checkout to a seeded, testable stack.

    make setup                      # baked stack: images built from GitHub, only the test package cloned
    make setup DEV=1                # developer stack: clones, dev mounts, CMS hot reload (REFS=release)
    make setup DEV=1 REFS=develop   # integration: every clean clone on develop
    make setup DEV=1 REFS="feature/x feature/y"   # a feature world: each clean clone (service and docs included)
                                    # on the first listed branch it has (local or origin), else develop; + docs portal
    SETUP_DRY=1 make setup DEV=1 REFS=…   # print which ref every clone would land on; change nothing
    make setup EMBED=1              # also start the embedding service (lookup)
    make setup SEED=0               # stop before seeding
    python3 scripts/setup.py --dry-run    # print the step plan; touch nothing
    SERVICE_BRANCH=<branch> python3 scripts/setup.py   # service branch other than .env for one run

Order matters: clones before the stack (bind mounts), mail + CMS before seed, toolbox checked before seed.
The toolbox never stops the run. Switched off (AI_TOOLBOX_ENABLED=0, the .env.example default) the mode is
`disabled`: AI features are refused on purpose. Enabled but not answering it is `degraded`: AI drafts and intel
fail visibly and recover on their own once the toolbox is back (beat retries transient failures).

Every step ends with `setup: step <slug> <ok|degraded|skipped|failed> <N>s`; the run ends with
`setup: done <N>s toolbox=<full|degraded|disabled> seeded=<yes|no>`.
"""

import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLONE_GROUPS = ("repos/py", "repos/django", "repos/tests", "repos/pwa")
# A feature world also moves the service under test and the docs portal clone.
WORLD_GROUPS = (*CLONE_GROUPS, "repos/services", "repos/docs")
PREREQUISITES = ("docker", "git", "make", "curl", "bash")
PROFILES = ("--profile", "infra", "--profile", "service")
# Key of the toolbox mode (full | degraded | disabled) next to the step statuses.
TOOLBOX_MODE = "toolbox-mode"


class StepFailed(Exception):
    """A step command failed; the message is the final `setup: …` line."""


@dataclass(frozen=True)
class Config:
    dev: bool
    refs: str
    embed: bool
    seed: bool

    @property
    def world(self):
        return self.refs not in ("release", "develop")


@dataclass(frozen=True)
class Step:
    slug: str
    plan: str
    action: Callable[[], object]
    enabled: bool = True


def run(*cmd, env=None, check=True):
    result = subprocess.run(
        cmd, cwd=ROOT, env={**os.environ, **(env or {})}, check=False
    )
    if check and result.returncode:
        raise StepFailed(f"setup: `{' '.join(cmd)}` failed (exit {result.returncode})")
    return result.returncode


def quiet(*cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, check=False).returncode


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


def service_branch():
    return os.environ.get("SERVICE_BRANCH") or env_value("SERVICE_BRANCH", "develop")


def preflight():
    if missing := [tool for tool in PREREQUISITES if not shutil.which(tool)]:
        raise StepFailed(
            f"setup: missing prerequisites: {', '.join(missing)} — see README § Requirements"
        )
    if quiet("docker", "info"):
        raise StepFailed("setup: docker is not reachable")
    if quiet("docker", "compose", "version"):
        raise StepFailed("setup: `docker compose` (Compose v2) is missing — see README § Requirements")
    if not (ROOT / ".env").exists():
        run("make", "init")
    print("prerequisites ok, docker ok, .env present")


def clones(refs):
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
        run("make", "refresh-repos", f"SERVICE_BRANCH={service_branch()}")
    elif refs == "develop":
        switch_to_develop()
    else:
        switch_to_world(refs.split())


def clean_clones(groups):
    """(repo, skip reason) for every clone in `groups`; the reason is None for a clean, movable clone."""
    for group in groups:
        for repo in sorted((ROOT / group).glob("*/.git")):
            repo = repo.parent
            if (repo / ".git").is_file():  # a linked worktree (hotfix agent, stream 2): it owns its branch
                yield repo, "worktree"
            elif git(repo, "status", "--porcelain", "--untracked-files=no").stdout.strip():
                yield repo, "dirty"
            else:
                yield repo, None


def switch_to_develop():
    for repo, skip in clean_clones(CLONE_GROUPS):
        name = repo.relative_to(ROOT)
        if skip:
            print(f"  skip ({skip}): {name}")
            continue
        git(repo, "fetch", "--quiet", "origin")
        if git(repo, "rev-parse", "--verify", "--quiet", "origin/develop").returncode:
            print(f"  skip (no develop): {name}")
            continue
        git(repo, "switch", "--quiet", "develop")
        pulled = git(repo, "merge", "--ff-only", "--quiet", "origin/develop").returncode == 0
        print(f"  develop{'' if pulled else ' (local commits, not fast-forwarded)'}: {name}")


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


def current_branch(repo):
    return git(repo, "branch", "--show-current").stdout.strip() or "detached"


def switch_to(repo, branch, where):
    if where == "local" or branch == "develop":
        git(repo, "switch", "--quiet", branch)
    else:
        git(repo, "switch", "--quiet", "--track", "-c", branch, f"origin/{branch}")
    if where == "origin":
        git(repo, "merge", "--ff-only", "--quiet", f"origin/{branch}")
    return "" if current_branch(repo) == branch else "SWITCH FAILED"


def world_row(repo, skip, branches, dry):
    """(branch, note) for one clone; fetches and moves it unless `dry`."""
    if skip:
        return current_branch(repo), f"skip: {skip}"
    if not dry:
        git(repo, "fetch", "--quiet", "origin")
    branch, where = world_ref(repo, branches)
    if branch is None:
        return "-", "skip: no listed branch and no develop"
    note = "" if branch in branches else "fallback"
    return branch, (note if dry else switch_to(repo, branch, where) or note)


def switch_to_world(branches, dry=False):
    """Every clean clone onto the first branch of `branches` it has, else develop — dirty clones are never touched."""
    rows = [
        (str(repo.relative_to(ROOT)), *world_row(repo, skip, branches, dry))
        for repo, skip in clean_clones(WORLD_GROUPS)
    ]
    width = max(len(row[0]) for row in rows) if rows else 0
    for name, branch, note in rows:
        print(f"  {name:<{width}}  {branch}{('  (' + note + ')') if note else ''}")
    on_branch = sum(1 for _, branch, _ in rows if branch in branches)
    print(f"  {on_branch} clone(s) on {' / '.join(branches)}, the rest on develop or skipped")


def wait_http(url, seconds):
    """True once the server answers at all: before the first migrate (seed runs it) every database-backed
    route, the schema included, answers 500."""
    for _ in range(seconds // 5):
        try:
            with urllib.request.urlopen(url, timeout=4):
                return True
        except urllib.error.HTTPError:
            return True
        except OSError:
            pass
        time.sleep(5)
    return False


def start(target):
    run("make", target)
    port = env_value("SERVICE_PORT", "8100")
    if not wait_http(f"http://localhost:{port}/api/schema/", 600):
        raise StepFailed(
            "setup: the service did not answer on /api/schema/ — see `docker compose logs service`"
        )


def frontends(dev):
    if not dev:
        run("make", "frontends")
        return
    run("make", "pwa")
    run("make", "cms-dev")


def docs():
    run("make", "docs")
    # A running Astro dev server does not survive a branch switch of its clone ("collection does not exist").
    run("docker", "compose", "--profile", "docs", "restart", "docs")


def toolbox_mode(returncode: int, output: str) -> str:
    if returncode:
        return "degraded"
    return "disabled" if output.startswith("toolbox-check: disabled") else "full"


def toolbox(statuses):
    check = subprocess.run(
        ("make", "--no-print-directory", "toolbox-check"), cwd=ROOT, capture_output=True, text=True, check=False
    )
    print(check.stdout + check.stderr, end="", flush=True)
    statuses[TOOLBOX_MODE] = mode = toolbox_mode(check.returncode, check.stdout)
    if mode == "degraded":
        print("WARNING: toolbox enabled but unreachable or misconfigured — DEGRADED mode (details in the summary).")
    return "degraded" if mode == "degraded" else "ok"


TOOLBOX_NOTES = {
    "disabled": (
        "AI features are switched off (AI_TOOLBOX_ENABLED=0): AI drafts and rewrites are refused, lead intel is",
        "skipped and runs once enabled, translations answer 503, `make bdd` skips @needs-toolbox scenarios.",
        "To use the toolbox set AI_TOOLBOX_ENABLED=1 and the AI_TOOLBOX_* values in .env, then `make dev`.",
    ),
    "degraded": (
        "the toolbox is enabled but does not answer or exposes a real model: AI drafts end `failed`, lead intel",
        "analyses fail and beat retries them every 10 min once it answers, `make bdd` skips @needs-toolbox",
        "scenarios while munin reports it unreachable.",
    ),
}


def has_access():
    probe = ("python", "-c", "import django_access")
    return quiet("docker", "compose", *PROFILES, "exec", "-T", "service", *probe) == 0


def summary(config, statuses):
    run("make", "dashboard", check=False)
    run("make", "urls", check=False)
    print("CMS and Django admin: admin / admin123")
    print("mail sandbox: sandbox / sandbox")
    mode = statuses.get(TOOLBOX_MODE, "full")
    print(f"toolbox mode: {mode}")
    for line in TOOLBOX_NOTES.get(mode, ()):
        print(f"  {line}")
    if not config.seed:
        print("database not migrated — `make migrate`, or `make seed`")
    elif config.dev and has_access():
        print("staff role users: viewer, editor, manager, accessadmin, norole (password <user>123)")
    print("next:")
    print("  make bdd          # full BDD (fresh seed; one-shot scenarios consume it) — needs uv on the host")
    print("  make e2e-funnel   # leads funnel e2e, phone + desktop — needs uv on the host")


def clones_plan(refs):
    tail = {
        "release": "make refresh-repos",
        "develop": "switch clean clones to develop",
    }.get(refs, f"switch clean clones to {refs}")
    lock = "lock" if refs == "release" else "develop"
    return f"make clone (if missing); make clone-tests; make clone-repos CLONE_REF={lock}; {tail}"


def checkout_steps(config):
    if not config.dev:
        return [Step("clone-tests", "make clone-tests", lambda: run("make", "clone-tests"))]
    return [Step("clones", clones_plan(config.refs), lambda: clones(config.refs))]


def stack_steps(config):
    target = "dev" if config.dev else "up"
    front = "make pwa; make cms-dev" if config.dev else "make frontends"
    has_docs = config.world and (ROOT / "repos/docs/entirius-docs/.git").exists()
    return [
        Step("build", f"make build SERVICE_BRANCH={service_branch()}",
             lambda: run("make", "build", f"SERVICE_BRANCH={service_branch()}")),
        Step(target, f"make {target}; wait until the service answers", lambda: start(target)),
        Step("mail", "make mail", lambda: run("make", "mail")),
        Step("frontends", front, lambda: frontends(config.dev)),
        Step("embed", "make embed", lambda: run("make", "embed"), config.embed),
    ] + ([Step("docs", "make docs; restart docs", docs, has_docs)] if config.world else [])


def steps(config, statuses):
    return [
        Step("preflight", "prerequisites; docker info; docker compose version; make init (if .env is missing)",
             preflight),
        *checkout_steps(config),
        *stack_steps(config),
        Step("toolbox", "make toolbox-check", lambda: toolbox(statuses)),
        Step("seed", "make seed", lambda: run("make", "seed"), config.seed),
        Step("summary", "make dashboard; make urls; logins; toolbox mode", lambda: summary(config, statuses)),
    ]


def execute(step):
    print(f"\n=== {step.slug} ===", flush=True)
    started = time.monotonic()
    status = "skipped"
    try:
        if step.enabled:
            status = "degraded" if step.action() == "degraded" else "ok"
    except StepFailed as failure:
        print(f"setup: step {step.slug} failed {elapsed(started)}s", flush=True)
        sys.exit(str(failure))
    print(f"setup: step {step.slug} {status} {elapsed(started)}s", flush=True)
    return status


def elapsed(started):
    return round(time.monotonic() - started)


def read_config():
    dev = os.environ.get("DEV") == "1"
    refs = os.environ.get("REFS", "release").strip() or "release"
    if not dev and (refs != "release" or os.environ.get("SETUP_DRY") == "1"):
        sys.exit(f"setup: REFS={refs} and SETUP_DRY need DEV=1 (the baked stack builds from GitHub)")
    return Config(dev, refs, os.environ.get("EMBED") == "1", os.environ.get("SEED", "1") != "0")


def ref_landings(config, offline):
    """SETUP_DRY: where each clone would land; fetches first unless --dry-run promised no network."""
    if not config.world:
        sys.exit("setup: SETUP_DRY needs a feature world (REFS=<branch …>)")
    print(f"\n=== dry run: where each clone would land ({config.refs}) ===", flush=True)
    for repo, skip in [] if offline else clean_clones(WORLD_GROUPS):
        if not skip:
            git(repo, "fetch", "--quiet", "origin")
    switch_to_world(config.refs.split(), dry=True)


def main():
    config = read_config()
    dry_run = "--dry-run" in sys.argv[1:]
    if os.environ.get("SETUP_DRY") == "1":
        ref_landings(config, offline=dry_run)
        if not dry_run:
            return
    statuses = {}
    plan = steps(config, statuses)
    if dry_run:
        for step in (step for step in plan if step.enabled):
            print(f"setup: plan {step.slug}: {step.plan}")
        return
    started = time.monotonic()
    for step in plan:
        statuses[step.slug] = execute(step)
    seeded = "yes" if config.seed else "no"
    mode = statuses.get(TOOLBOX_MODE, "full")
    print(f"setup: done {elapsed(started)}s toolbox={mode} seeded={seeded}")


if __name__ == "__main__":
    main()
