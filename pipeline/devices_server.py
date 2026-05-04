#!/usr/bin/env python3
"""
Tiny HTTP service that records device tokens for Castlingo push targeting.

Listens on 127.0.0.1:8765 (proxied by nginx at /castlingo/devices/register).
Stores tokens in /opt/langpod/secrets/tokens.json — one entry per token, upserted
on (token) so the same device can update its level/language without piling up.

Run as systemd unit `castlingo-devices.service`.
"""
from __future__ import annotations

import json
import os
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKENS_FILE = "/opt/langpod/secrets/tokens.json"
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8765

VALID_LEVELS = {"easy", "medium", "hard"}

_lock = threading.Lock()


def load_tokens() -> list[dict]:
    if not os.path.exists(TOKENS_FILE):
        return []
    try:
        with open(TOKENS_FILE, "r") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError):
        return []


def save_tokens(tokens: list[dict]) -> None:
    tmp = TOKENS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(tokens, f, indent=2, ensure_ascii=False)
    os.replace(tmp, TOKENS_FILE)
    os.chmod(TOKENS_FILE, 0o600)


def upsert(payload: dict) -> dict:
    """Insert or update by token. Returns the stored row."""
    token = (payload.get("token") or "").strip()
    if not token or len(token) < 32:
        raise ValueError("invalid token")

    level = (payload.get("level") or "easy").lower()
    if level not in VALID_LEVELS:
        level = "easy"

    row = {
        "token": token,
        "level": level,
        "language": (payload.get("language") or "zh"),
        "bundle_id": payload.get("bundle_id") or "com.amyhuang.castlingo",
        "app_version": payload.get("app_version") or "",
        "platform": payload.get("platform") or "ios",
        # Debug builds register sandbox tokens; release builds register prod.
        # Defaults to False so legacy rows from earlier registrations behave as prod.
        "is_sandbox": bool(payload.get("is_sandbox", False)),
        "updated_at": int(time.time()),
    }

    with _lock:
        tokens = load_tokens()
        idx = next((i for i, t in enumerate(tokens) if t.get("token") == token), -1)
        if idx >= 0:
            tokens[idx] = row | {"created_at": tokens[idx].get("created_at", row["updated_at"])}
        else:
            row["created_at"] = row["updated_at"]
            tokens.append(row)
        save_tokens(tokens)
    return row


def remove_token(token: str) -> bool:
    with _lock:
        tokens = load_tokens()
        new = [t for t in tokens if t.get("token") != token]
        if len(new) == len(tokens):
            return False
        save_tokens(new)
        return True


class Handler(BaseHTTPRequestHandler):
    def _json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self) -> None:
        if self.path not in ("/register", "/unregister"):
            self._json(404, {"error": "not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length > 4096:
            self._json(413, {"error": "payload too large"})
            return
        try:
            raw = self.rfile.read(length).decode("utf-8") if length > 0 else "{}"
            payload = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._json(400, {"error": "bad json"})
            return

        try:
            if self.path == "/register":
                row = upsert(payload)
                self._json(200, {"ok": True, "level": row["level"]})
            else:
                token = (payload.get("token") or "").strip()
                if not token:
                    self._json(400, {"error": "missing token"})
                    return
                removed = remove_token(token)
                self._json(200, {"ok": True, "removed": removed})
        except ValueError as e:
            self._json(400, {"error": str(e)})

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self._json(200, {"ok": True, "tokens": len(load_tokens())})
            return
        self._json(404, {"error": "not found"})

    def log_message(self, fmt: str, *args) -> None:
        # Quiet — systemd journal already captures stderr if needed.
        pass


def main() -> None:
    os.makedirs(os.path.dirname(TOKENS_FILE), exist_ok=True)
    if not os.path.exists(TOKENS_FILE):
        save_tokens([])
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"castlingo-devices listening on {LISTEN_HOST}:{LISTEN_PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
