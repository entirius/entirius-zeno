#!/usr/bin/env python3
# Generates the Zeno Suite dashboard (docker/dashboard/index.html) from the LIVE stack:
# real ports (docker compose port), package provenance (editable repos/ vs baked index),
# and repos/ branches. Regenerate any time with `make dashboard`; served by the `dashboard`
# compose service. No hand-maintained truth — everything here is introspected.
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docker" / "dashboard" / "index.html"
COMPOSE = ["docker", "compose"]

# (compose service, container port, label, path suffix for the browser link)
SERVICES = [
    ("service", 8000, "Volkanos API", "/api/schema/swagger-ui/"),
    ("pwa", 3000, "Storefront", "/"),
    ("cms", 8080, "Admin CMS", "/"),
    ("rabbitmq", 15672, "RabbitMQ", "/"),
]


def sh(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, cwd=ROOT, **kw).stdout.strip()


def host_port(service, cport):
    out = sh([*COMPOSE, "port", service, str(cport)])
    return out.rsplit(":", 1)[-1] if ":" in out else None


def provenance():
    """entirius-* dists as the service sees them: editable path (dev) or baked version."""
    code = (
        "import json;from importlib.metadata import distributions;"
        "o=[]\n"
        "for d in distributions():\n"
        " n=d.metadata['Name'] or ''\n"
        " if not n.startswith('entirius'): continue\n"
        " p=None\n"
        " try:\n"
        "  du=json.loads(d.read_text('direct_url.json') or '{}')\n"
        "  if du.get('dir_info',{}).get('editable'): p=du.get('url','').replace('file://','')\n"
        " except Exception: pass\n"
        " o.append([n,d.version,p])\n"
        "print(json.dumps(o))"
    )
    raw = sh([*COMPOSE, "exec", "-T", "service", "python", "-c", code])
    try:
        return json.loads(raw)
    except Exception:
        return []


def branch_of(path_in_container):
    # /entirius/django/entirius-django-x -> repos/django/entirius-django-x on host
    rel = path_in_container.replace("/entirius/", "repos/").split("/src")[0].rstrip("/")
    d = ROOT / rel
    if not (d / ".git").exists():
        return "?"
    b = sh(["git", "-C", str(d), "branch", "--show-current"]) or "detached"
    return b


def test_packages():
    tdir = ROOT / "repos" / "tests"
    return sorted(p.name for p in tdir.glob("*") if (p / ".git").exists()) if tdir.exists() else []


def build():
    ports = {s: host_port(s, c) for s, c, _, _ in SERVICES}
    dev_mode = any(p for _, _, p in provenance())
    prov = provenance()
    editable = sorted((n, v, branch_of(p)) for n, v, p in prov if p)
    baked = sorted((n, v) for n, v, p in prov if not p)
    pkgs = test_packages()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    def svc_rows():
        out = []
        for s, cport, label, suffix in SERVICES:
            hp = ports.get(s)
            if not hp:
                out.append(f'<tr class="down"><td>{label}</td><td>—</td><td>not running</td></tr>')
                continue
            url = f"http://localhost:{hp}{suffix}"
            out.append(
                f'<tr><td>{label}</td>'
                f'<td><a href="{url}" target="_blank">localhost:{hp}</a></td>'
                f'<td><span class="dot" data-url="http://localhost:{hp}{suffix}">…</span></td></tr>'
            )
        return "\n".join(out)

    ed_rows = "\n".join(
        f"<tr><td>{n}</td><td>{v}</td><td><code>{b}</code></td></tr>" for n, v, b in editable
    ) or '<tr><td colspan="3">none (image mode — all baked)</td></tr>'
    baked_rows = "\n".join(f"<tr><td>{n}</td><td>{v}</td></tr>" for n, v in baked)
    pkg_rows = "\n".join(f"<li><code>{p}</code></li>" for p in pkgs) or "<li>none cloned (make clone-tests)</li>"

    html = f"""<!doctype html><meta charset=utf-8>
<title>Entirius Zeno Suite</title>
<style>
 body{{font:15px/1.5 system-ui,sans-serif;margin:0;background:#0e1220;color:#e6e8ef}}
 header{{padding:20px 28px;background:#151a2c;border-bottom:1px solid #232a44}}
 h1{{margin:0;font-size:20px}} .sub{{color:#8b93ad;font-size:13px}}
 main{{max-width:900px;margin:0 auto;padding:24px 28px;display:grid;gap:24px}}
 section{{background:#151a2c;border:1px solid #232a44;border-radius:10px;padding:16px 20px}}
 h2{{margin:0 0 12px;font-size:15px;color:#aab2cc}}
 table{{width:100%;border-collapse:collapse}} td,th{{text-align:left;padding:5px 8px;border-bottom:1px solid #232a44}}
 th{{color:#8b93ad;font-weight:600;font-size:12px}} a{{color:#6ea8ff}} code{{color:#9ecbff}}
 .dot{{display:inline-block;width:10px;height:10px;border-radius:50%;background:#555}}
 .up .dot{{background:#3fb950}} .down td{{color:#8b93ad}} ul{{margin:0;padding-left:18px}}
 .mode{{padding:2px 8px;border-radius:6px;font-size:12px;background:#233;color:#6ea8ff}}
</style>
<header>
 <h1>Entirius Zeno Suite <span class="mode">{"dev — repos/ mounted" if dev_mode else "image — baked"}</span></h1>
 <div class="sub">generated {ts} · ports are configurable in <code>.env</code> · regenerate: <code>make dashboard</code></div>
</header>
<main>
 <section><h2>Services</h2>
  <table><tr><th>Service</th><th>URL</th><th>Status</th></tr>{svc_rows()}</table>
  <div class="sub" style="margin-top:8px">Status is live reachability from your browser.</div>
 </section>
 <section><h2>Volkanos packages from <code>repos/</code> (editable — your local code)</h2>
  <table><tr><th>Package</th><th>Version</th><th>Branch</th></tr>{ed_rows}</table>
 </section>
 <section><h2>Test packages in <code>repos/tests/</code></h2><ul>{pkg_rows}</ul>
  <div class="sub">Seed one with <code>make seed PACKAGE=&lt;name&gt;</code>; run <code>make bdd</code>.</div>
 </section>
 <section><h2>Baked packages ({len(baked)} from the index/lock)</h2>
  <details><summary class=sub>show</summary><table><tr><th>Package</th><th>Version</th></tr>{baked_rows}</table></details>
 </section>
</main>
<script>
 for (const el of document.querySelectorAll('.dot[data-url]')) {{
   fetch(el.dataset.url, {{mode:'no-cors'}}).then(()=>{{el.parentElement.parentElement.classList.add('up')}})
     .catch(()=>{{el.parentElement.parentElement.classList.add('down')}});
 }}
</script>
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html)
    print(f"dashboard: {OUT.relative_to(ROOT)} ({len(editable)} editable, {len(baked)} baked, {len(pkgs)} test pkg)")


if __name__ == "__main__":
    build()
