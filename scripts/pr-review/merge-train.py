#!/usr/bin/env python3
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Merge a list of reviewed PRs of one repo into develop, in order (phase 6 of the PR review procedure).

    python3 scripts/pr-review/merge-train.py <clone> <owner/repo> <pr>[:team] ...
    PR_TRAIN_NOTE="..." overrides the approval text of team PRs.

Per PR: a worktree on disk (~/.cache/pr-review/train/) at the PR head, merge origin/develop (a CHANGELOG.md conflict
is resolved by joining both sides under one set of headings; any other conflict stops the train for a manual
resolution), push over https, wait until the PR head is the pushed commit and its checks are green, approve a team
member's PR (`:team`), merge with a merge commit, verify MERGED. A merge call that errors is re-checked before a
retry: GitHub can report a failure for a merge it made.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

WORK = Path.home() / ".cache/pr-review/train"
APPROVE = os.environ.get(
    "PR_TRAIN_NOTE", "Approved after the PR sweep: reviewed, and the integration run with every sweep PR is green."
)
CONFLICT = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.DOTALL)


def run(*cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)


def join_changelog(path: Path) -> None:
    """Both sides of each conflict, headings once, blank lines collapsed."""

    def joined(match):
        out, seen, skipped = [], set(), False
        for line in (match.group(1) + match.group(2)).splitlines():
            if line.startswith("#") and line in seen:
                skipped = True
                continue
            if skipped and not line.strip():
                continue
            skipped = False
            if line.startswith("#"):
                seen.add(line)
            if line.startswith("- ") and out and not out[-1].strip() and len(out) > 1 and out[-2].startswith("- "):
                out.pop()
            if line.strip() or (out and out[-1].strip()):
                out.append(line)
        return "\n".join(out).rstrip("\n") + "\n\n"

    path.write_text(CONFLICT.sub(joined, path.read_text()))


def update_branch(wt: Path) -> bool:
    """Merge origin/develop into the PR head; True when a merge commit was made."""
    before = run("git", "rev-parse", "HEAD", cwd=wt).stdout.strip()
    merged = run("git", "merge", "--no-edit", "origin/develop", cwd=wt, check=False)
    if merged.returncode:
        files = run("git", "diff", "--name-only", "--diff-filter=U", cwd=wt).stdout.split()
        if set(files) - {"CHANGELOG.md"}:
            raise SystemExit(f"conflict outside CHANGELOG.md: {files}")
        join_changelog(wt / "CHANGELOG.md")
        run("git", "add", "CHANGELOG.md", cwd=wt)
        run("git", "commit", "--no-edit", cwd=wt)
    return run("git", "rev-parse", "HEAD", cwd=wt).stdout.strip() != before


def wait_checks(repo: str, pr: str) -> None:
    time.sleep(25)
    for _ in range(60):
        rc = run("gh", "pr", "checks", pr, "-R", repo, check=False).returncode
        if rc == 0:
            return
        if rc != 8:
            raise SystemExit(f"{repo}#{pr}: checks red")
        time.sleep(20)
    raise SystemExit(f"{repo}#{pr}: checks still pending")


def merge_one(clone: str, repo: str, spec: str) -> None:
    pr, _, who = spec.partition(":")
    info = json.loads(run("gh", "pr", "view", pr, "-R", repo, "--json", "headRefName,state").stdout)
    if info["state"] == "MERGED":
        print(f"{repo}#{pr} already merged", flush=True)
        return
    head, wt = info["headRefName"], WORK / f"{repo.split('/')[1]}-{pr}"
    run("git", "-C", clone, "fetch", "-q", "origin")
    run("git", "-C", clone, "worktree", "add", "-q", "-B", f"train/{pr}", str(wt), f"origin/{head}")
    try:
        if who == "team":
            run("gh", "pr", "review", pr, "-R", repo, "--approve", "--body", APPROVE)
        for attempt in range(4):
            if json.loads(run("gh", "pr", "view", pr, "-R", repo, "--json", "state").stdout)["state"] == "MERGED":
                break  # a merge call that reported an error can still have merged
            run("git", "fetch", "-q", "origin", cwd=wt)
            if update_branch(wt):
                run("git", "push", f"https://github.com/{repo}.git", f"HEAD:{head}", cwd=wt)
            local = run("git", "rev-parse", "HEAD", cwd=wt).stdout.strip()
            for _ in range(20):  # the PR must point at what was pushed before its checks mean anything
                pr_head = json.loads(run("gh", "pr", "view", pr, "-R", repo, "--json", "headRefOid").stdout)["headRefOid"]
                if pr_head == local:
                    break
                time.sleep(15)
            else:
                raise SystemExit(f"{repo}#{pr}: PR head {pr_head[:8]} never became {local[:8]} (close/reopen the PR)")
            wait_checks(repo, pr)
            if run("gh", "pr", "merge", pr, "-R", repo, "--merge", "--admin", check=False).returncode == 0:
                break
            time.sleep(30)  # GitHub still computing mergeability, or a transient 502
        else:
            raise SystemExit(f"{repo}#{pr}: merge refused 4 times")
        state = json.loads(run("gh", "pr", "view", pr, "-R", repo, "--json", "state").stdout)["state"]
        print(f"{repo}#{pr} {state}", flush=True)
    finally:
        run("git", "-C", clone, "worktree", "remove", "--force", str(wt), check=False)
        run("git", "-C", clone, "branch", "-D", f"train/{pr}", check=False)


def main() -> None:
    clone, repo, *specs = sys.argv[1:]
    WORK.mkdir(parents=True, exist_ok=True)
    for spec in specs:
        merge_one(clone, repo, spec)


if __name__ == "__main__":
    main()
