#!/usr/bin/env python3
"""Redmine helper of the CMS hotfix agent (project cms-blueprint).

URL and API key are read from ~/.claude/redmine/credentials.yaml (instance "redmine"); the key is never printed.

  candidates                 issue ids to take: open, status New/To Do, unassigned or assigned to the API user
  fetch <id> <dir>           issue.json + attachments into <dir>; prints the directory
  note <id> <file> [--status N] [--assign ID|author|me]   add a note (textile), optionally change status/assignee
  author <id>                the reporter's user id
"""
import json
import os
import sys
import urllib.request

import yaml

PROJECT = "cms-blueprint"
STATUS_NEW, STATUS_TODO = 31, 1


def _conf():
    return yaml.safe_load(open(os.path.expanduser("~/.claude/redmine/credentials.yaml")))["redmine"]


def _call(method, path, body=None, raw=False):
    c = _conf()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(c["url"] + path, data=data, method=method,
                                 headers={"X-Redmine-API-Key": c["api_key"], "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = resp.read()
    if raw:
        return payload
    return json.loads(payload) if payload.strip() else {}


def me():
    return _call("GET", "/users/current.json")["user"]["id"]


def candidates():
    uid = me()
    out = []
    for status in (STATUS_NEW, STATUS_TODO):
        res = _call("GET", f"/issues.json?project_id={PROJECT}&status_id={status}&limit=100&sort=created_on:asc")
        for issue in res["issues"]:
            assignee = issue.get("assigned_to", {}).get("id")
            if assignee in (None, uid):
                out.append((issue["created_on"], issue["id"]))
    for _, issue_id in sorted(out):
        print(issue_id)


def fetch(issue_id, directory):
    os.makedirs(directory, exist_ok=True)
    issue = _call("GET", f"/issues/{issue_id}.json?include=attachments,journals")["issue"]
    with open(os.path.join(directory, "issue.json"), "w") as fh:
        json.dump(issue, fh, indent=2, ensure_ascii=False)
    for att in issue.get("attachments", []):
        name = os.path.basename(att["filename"])
        req = urllib.request.Request(att["content_url"], headers={"X-Redmine-API-Key": _conf()["api_key"]})
        with urllib.request.urlopen(req, timeout=60) as resp, open(os.path.join(directory, name), "wb") as fh:
            fh.write(resp.read())
    print(directory)


def author(issue_id):
    print(_call("GET", f"/issues/{issue_id}.json")["issue"]["author"]["id"])


def note(issue_id, path, status=None, assign=None):
    body = {"issue": {"notes": open(path).read()}}
    if status:
        body["issue"]["status_id"] = int(status)
    if assign == "author":
        body["issue"]["assigned_to_id"] = _call("GET", f"/issues/{issue_id}.json")["issue"]["author"]["id"]
    elif assign == "me":
        body["issue"]["assigned_to_id"] = me()
    elif assign:
        body["issue"]["assigned_to_id"] = int(assign)
    _call("PUT", f"/issues/{issue_id}.json", body)


def main(argv):
    if not argv:
        sys.exit(__doc__)
    cmd, args = argv[0], argv[1:]
    if cmd == "candidates":
        candidates()
    elif cmd == "fetch" and len(args) == 2:
        fetch(int(args[0]), args[1])
    elif cmd == "author" and len(args) == 1:
        author(int(args[0]))
    elif cmd == "note" and len(args) >= 2:
        opts = dict(zip(args[2::2], args[3::2]))
        note(int(args[0]), args[1], opts.get("--status"), opts.get("--assign"))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
