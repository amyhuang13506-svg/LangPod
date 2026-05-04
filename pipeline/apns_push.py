#!/usr/bin/env python3
"""
Send a single APNs push to one device using token-based auth (.p8 + JWT).

Used by `push_new_episode.py` (which iterates over tokens.json). Kept as a
small library so it stays easy to test in isolation.

Endpoints:
  - production:  api.push.apple.com:443
  - development: api.sandbox.push.apple.com:443

We auto-pick based on `APNS_USE_SANDBOX` env var (1 = sandbox).
"""
from __future__ import annotations

import json
import os
import time
from typing import Any

import httpx
import jwt  # PyJWT

# === Config (override via env vars / CLI) ====================================
APNS_KEY_ID = os.environ.get("APNS_KEY_ID", "Q2345D3X35")
APNS_TEAM_ID = os.environ.get("APNS_TEAM_ID", "4SYQ773ULJ")
APNS_BUNDLE_ID = os.environ.get("APNS_BUNDLE_ID", "com.amyhuang.castlingo")
APNS_KEY_PATH = os.environ.get(
    "APNS_KEY_PATH", "/opt/langpod/secrets/AuthKey_Q2345D3X35.p8"
)
APNS_USE_SANDBOX = os.environ.get("APNS_USE_SANDBOX", "0") == "1"

PROD_HOST = "https://api.push.apple.com"
SANDBOX_HOST = "https://api.sandbox.push.apple.com"

# Tokens are valid up to 60 minutes. Reuse one within the window to avoid
# Apple's 401 TooManyProviderTokenUpdates throttle.
_jwt_cache: dict[str, Any] = {"value": None, "issued_at": 0}
_JWT_TTL = 50 * 60  # refresh just under the 60-min cap


def _read_key() -> str:
    with open(APNS_KEY_PATH, "r") as f:
        return f.read()


def _provider_token() -> str:
    now = int(time.time())
    if _jwt_cache["value"] and (now - _jwt_cache["issued_at"]) < _JWT_TTL:
        return _jwt_cache["value"]
    token = jwt.encode(
        {"iss": APNS_TEAM_ID, "iat": now},
        _read_key(),
        algorithm="ES256",
        headers={"kid": APNS_KEY_ID, "alg": "ES256"},
    )
    _jwt_cache["value"] = token
    _jwt_cache["issued_at"] = now
    return token


def send_push(
    *,
    device_token: str,
    title: str,
    body: str,
    payload_extras: dict[str, Any] | None = None,
    sandbox: bool | None = None,
    client: httpx.Client | None = None,
) -> tuple[int, str]:
    """
    Returns (status_code, response_body). 200 = delivered to APNs.
    Caller is responsible for retry / token cleanup on 410/400 errors.

    `client` lets the caller share a single httpx.Client across many sends
    (huge throughput win because of HTTP/2 stream multiplexing).
    """
    use_sandbox = APNS_USE_SANDBOX if sandbox is None else sandbox
    host = SANDBOX_HOST if use_sandbox else PROD_HOST
    url = f"{host}/3/device/{device_token}"

    payload: dict[str, Any] = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
        },
    }
    if payload_extras:
        payload.update(payload_extras)

    headers = {
        "authorization": f"bearer {_provider_token()}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
    }

    own_client = client is None
    c = client or httpx.Client(http2=True, timeout=10.0)
    try:
        r = c.post(url, headers=headers, content=json.dumps(payload))
        return r.status_code, r.text
    finally:
        if own_client:
            c.close()


def make_client() -> httpx.Client:
    return httpx.Client(http2=True, timeout=10.0)


# === CLI for one-off testing =================================================
def _cli() -> None:
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("--token", required=True, help="device token (hex)")
    p.add_argument("--title", default="Castlingo")
    p.add_argument("--body", default="测试推送")
    p.add_argument("--episode-id", default=None)
    p.add_argument("--level", default=None)
    p.add_argument("--sandbox", action="store_true")
    args = p.parse_args()

    extras: dict[str, Any] = {}
    if args.episode_id:
        extras["episode_id"] = args.episode_id
    if args.level:
        extras["level"] = args.level
    extras["intent"] = "remote_test"

    code, resp = send_push(
        device_token=args.token,
        title=args.title,
        body=args.body,
        payload_extras=extras,
        sandbox=args.sandbox,
    )
    print(f"status={code} body={resp!r}")


if __name__ == "__main__":
    _cli()
