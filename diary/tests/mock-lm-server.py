#!/usr/bin/env python3
"""Mock LM Studio server for tests/test-synthesize-local.sh.

Test-only dependency (python3 stdlib). Serves the two endpoints
synthesize-local.sh touches:

  GET  /v1/models            -> fixed model list
  POST /v1/chat/completions  -> canned assistant message

Configuration via environment:
  MOCK_CONTENT  assistant message content to return
                (default: a valid SLUG + entry)
  MOCK_STATUS   HTTP status for chat/completions (default 200)
  MOCK_LOG      file path; every chat/completions request body is appended
                as one line of JSON for assertions
  MOCK_MODELS   comma-separated model ids for the /models list
                (default: one embedding model + mock-chat-model)

Binds 127.0.0.1 on an ephemeral port and prints the port on stdout, then
serves until killed.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

CONTENT = os.environ.get(
    "MOCK_CONTENT",
    "SLUG: mock-entry\n\nStarted on the mock work. I tried things and learned things.",
)
STATUS = int(os.environ.get("MOCK_STATUS", "200"))
LOG = os.environ.get("MOCK_LOG", "")
MODELS = [
    m for m in os.environ.get(
        "MOCK_MODELS", "text-embedding-nomic-embed-text-v1.5,mock-chat-model"
    ).split(",") if m
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep test output clean
        pass

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._send(200, {
                "object": "list",
                "data": [{"id": m, "object": "model"} for m in MODELS],
            })
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        if LOG:
            with open(LOG, "ab") as f:
                f.write(body.replace(b"\n", b" ") + b"\n")
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self._send(404, {"error": "not found"})
            return
        if STATUS != 200:
            self._send(STATUS, {"error": "mock failure"})
            return
        self._send(200, {
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "model": "mock-chat-model",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": CONTENT},
                "finish_reason": "stop",
            }],
        })


def main():
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
