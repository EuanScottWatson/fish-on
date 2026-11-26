"""
Serve disposable synthetic records to the iOS simulator during UI tests.
"""

import http.server
import json
import os
import pathlib


class Handler(http.server.BaseHTTPRequestHandler):
    """
    Return minimal test data and persist submitted catches in a temporary directory.
    """

    def do_GET(self):
        """
        Serve health and synthetic journal endpoints.
        """
        path = pathlib.Path(os.environ["FISH_TEST_DATA"]) / "catches.json"
        if self.path == "/health":
            self.reply({"ok": True})
        elif self.path == "/api/catches":
            self.reply(json.loads(path.read_text()) if path.exists() else [])
        elif self.path == "/surveys.json":
            self.reply([{"lat": 53.0, "lon": -2.0, "name": "Test survey", "water": "Test river", "latest": 2025, "species": {"Perch": 2025}}])
        elif self.path in ("/api/trips", "/fishbase.json"):
            self.reply([])
        elif self.path == "/guide-images.json":
            self.reply({})
        else:
            self.send_error(404)

    def do_POST(self):
        """
        Accept only a test catch and save it to the isolated fixture.
        """
        if self.path != "/api/catches":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if b"Test perch" not in body or b'name="species"' not in body:
            self.send_error(400)
            return
        path = pathlib.Path(os.environ["FISH_TEST_DATA"]) / "catches.json"
        path.write_text(json.dumps([{"id": "0123456789abcdef0123456789abcdef", "species": "Test perch", "date": "2026-05-17"}]))
        self.reply({"id": "0123456789abcdef0123456789abcdef"})

    def reply(self, value: object):
        """
        Return a JSON fixture.
        """
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", 18782), Handler).serve_forever()
