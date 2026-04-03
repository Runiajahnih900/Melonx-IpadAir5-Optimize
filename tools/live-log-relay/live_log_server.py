#!/usr/bin/env python3
"""Simple HTTP live log receiver for MeloNX iPad builds.

Run this script on your development machine, then set the iPad app Remote Log Endpoint
setting to http://<your-pc-ip>:8787/log.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


class LiveLogServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], out_file: Path | None):
        super().__init__(server_address, LiveLogHandler)
        self.out_file = out_file


class LiveLogHandler(BaseHTTPRequestHandler):
    server: LiveLogServer

    def do_GET(self) -> None:
        if self.path in ("/", "/health"):
            self._send_json(200, {"status": "ok"})
            return

        self._send_json(404, {"error": "not-found"})

    def do_POST(self) -> None:
        if self.path != "/log":
            self._send_json(404, {"error": "not-found"})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length)

        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json(400, {"error": "invalid-json"})
            return

        logs = payload.get("logs", [])
        if isinstance(logs, str):
            logs = [logs]

        if not isinstance(logs, list):
            self._send_json(400, {"error": "logs-must-be-array"})
            return

        source = str(payload.get("source", "unknown"))
        dropped = int(payload.get("dropped", 0) or 0)

        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

        if dropped > 0:
            self._emit_line(f"[{now}] [{source}] [drop] dropped={dropped}")

        for line in logs:
            self._emit_line(f"[{now}] [{source}] {line}")

        self._send_json(200, {"accepted": len(logs), "dropped": dropped})

    def log_message(self, format: str, *args: Any) -> None:
        # Silence default HTTP request logs to keep output focused on emulator logs.
        return

    def _emit_line(self, line: str) -> None:
        print(line, flush=True)

        if self.server.out_file is None:
            return

        self.server.out_file.parent.mkdir(parents=True, exist_ok=True)
        with self.server.out_file.open("a", encoding="utf-8") as out:
            out.write(line + "\n")

    def _send_json(self, status_code: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload).encode("utf-8")

        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a local receiver for MeloNX remote live logs.")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host. Default: 0.0.0.0")
    parser.add_argument("--port", type=int, default=8787, help="Bind port. Default: 8787")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("logs/live-relay.log"),
        help="Optional output file path. Use --out '' to disable file output.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    out_file: Path | None = args.out
    if str(args.out).strip() == "":
        out_file = None

    server = LiveLogServer((args.host, args.port), out_file)

    print(f"[live-log] Listening on http://{args.host}:{args.port}/log", flush=True)
    if out_file:
        print(f"[live-log] Writing copy to: {out_file}", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print("[live-log] Stopped", flush=True)


if __name__ == "__main__":
    main()
