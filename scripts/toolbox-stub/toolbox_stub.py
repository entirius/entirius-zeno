#!/usr/bin/env python3
"""A local stand-in for the AI toolbox, for e2e runs only. No AI, no network, no secrets.

It answers just enough for the CMS shell and the screens that probe the toolbox:
  GET  /api/ai-completion/v2/admin/<channel>/models/    one `fake` model (the status probe)
  POST /api/ai-completion/v2/admin/<channel>/complete/  an empty completion (parsed = null); for a reply intent request
                                                        (tag `communicator.reply_intent`) a deterministic
                                                        classification from `fake_intent.py` (T4)
  GET  /api/ai-tracker/v2/admin/<channel>/usage/        no usage rows
  GET  /api/ai-tracker/v2/admin/<channel>/billing/client/  404 (billing off)
Everything else answers 404. Run:  make toolbox-stub   (default port 8300; TOOLBOX_STUB_PORT=... to change)
Point zeno at it in .env: AI_TOOLBOX_ENABLED=1, AI_TOOLBOX_BASE_URL=http://host.docker.internal:8300, AI_TOOLBOX_API_KEY=stub.
For CMS e2e only: the empty completions are not meant for `@needs-toolbox` BDD scenarios (keep AI_TOOLBOX_ENABLED=0 for `make bdd`).
"""

import json
import sys
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fake_intent  # noqa: E402

MODEL = {
    "provider": "fake",
    "model_id": "fake-model",
    "display_name": "Fake model (stub)",
    "supports_structured_output": True,
    "max_input_tokens": 8192,
    "input_price_per_1k": "0",
    "output_price_per_1k": "0",
}
COMPLETION = {
    "output": "stub",
    "parsed": None,
    "usage": {"input_tokens": 0, "output_tokens": 0},
    "cost": "0",
    "model": "fake-model",
    "attempts": 1,
    "request_id": "stub",
}


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body) -> None:
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?")[0].rstrip("/")
        if path.endswith("/ai-completion/v2/admin/" + path.split("/")[-2] + "/models") or path.endswith("/models"):
            return self._send(200, [MODEL])
        if path.endswith("/ai-tracker/v2/admin/" + path.split("/")[-2] + "/usage") or path.endswith("/usage"):
            return self._send(200, {"breakdown": []})
        self._send(404, {"error": "NOT_FOUND"})

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        if self.path.split("?")[0].rstrip("/").endswith("/complete"):
            try:
                request = json.loads(raw or b"{}")
            except ValueError:
                request = {}
            if isinstance(request, dict) and fake_intent.is_intent_request(request):
                return self._send(200, fake_intent.completion(request))
            return self._send(200, COMPLETION)
        self._send(404, {"error": "NOT_FOUND"})

    def log_message(self, fmt, *args) -> None:  # quiet
        return


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8300
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()  # noqa: S104 — local stub, containers reach it
