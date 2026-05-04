#!/usr/bin/env python3
"""
Notify all subscribed users about a newly published episode.

Filtering: each user only gets push for their own selected level (Easy/Medium/Hard).
A 410 Unregistered response from APNs prunes the token from tokens.json.

Usage from the pipeline:
    python3 push_new_episode.py --episode-id easy_20260504_001 \\
        --level easy --title "Coffee Culture" [--sandbox]

The push payload includes `episode_id` + `level` so the iOS app can deep-link
into the matching episode when the notification is tapped.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any

# Allow running both via `python3 push_new_episode.py` and as an importable module.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apns_push import send_push, make_client  # noqa: E402

TOKENS_FILE = "/opt/langpod/secrets/tokens.json"

# Push copy per level. Body is overridden with the episode title at runtime;
# the title field is the static channel banner.
COPY_BY_LEVEL = {
    "easy": "今天的新一集（初级）",
    "medium": "今天的新一集（中级）",
    "hard": "今天的新一集（高级）",
}


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


def push_episode(
    *,
    episode_id: str,
    level: str,
    title: str,
    intent: str = "new_episode_remote",
    sandbox: bool = False,
    dry_run: bool = False,
) -> dict[str, int]:
    """
    Push a notification to every device subscribed to `level`.
    Returns a counts dict: {sent, failed, pruned, skipped}.
    """
    level = level.lower()
    if level not in COPY_BY_LEVEL:
        raise ValueError(f"unknown level: {level}")

    tokens = load_tokens()
    targets = [t for t in tokens if t.get("level") == level]
    print(f"[push] {len(targets)}/{len(tokens)} tokens match level={level}")

    if not targets:
        return {"sent": 0, "failed": 0, "pruned": 0, "skipped": len(tokens) - 0}

    sent = failed = 0
    prune_set: set[str] = set()
    push_title = COPY_BY_LEVEL[level]
    push_body = title or "打开听一听"

    extras: dict[str, Any] = {
        "episode_id": episode_id,
        "level": level,
        "intent": intent,
    }

    if dry_run:
        for t in targets[:5]:
            print(f"  [dry-run] would push to {t['token'][:16]}…")
        return {"sent": 0, "failed": 0, "pruned": 0, "skipped": len(targets)}

    client = make_client()
    try:
        for row in targets:
            token = row["token"]
            # Per-row environment: sandbox tokens (debug builds) must hit the
            # sandbox endpoint, otherwise APNs returns BadDeviceToken and we'd
            # prune a perfectly valid dev token. The CLI --sandbox flag still
            # acts as a global override for testing.
            row_sandbox = sandbox or bool(row.get("is_sandbox", False))
            try:
                code, resp = send_push(
                    device_token=token,
                    title=push_title,
                    body=push_body,
                    payload_extras=extras,
                    sandbox=row_sandbox,
                    client=client,
                )
            except Exception as e:  # noqa: BLE001 — log + continue
                print(f"  [error] {token[:16]}… {type(e).__name__}: {e}")
                failed += 1
                continue

            if code == 200:
                sent += 1
            elif code == 410:
                # Unregistered — token no longer valid (uninstall / restore).
                print(f"  [prune] 410 {token[:16]}…")
                prune_set.add(token)
                failed += 1
            elif code == 400 and "BadDeviceToken" in resp:
                # Wrong environment (e.g. dev token sent to prod). Drop too —
                # next app launch will re-register cleanly.
                print(f"  [prune] 400 BadDeviceToken {token[:16]}…")
                prune_set.add(token)
                failed += 1
            else:
                print(f"  [fail] {code} {resp[:120]} token={token[:16]}…")
                failed += 1
            # Be polite — APNs allows huge fan-out but we don't have many tokens
            # yet, so a tiny delay is harmless and keeps logs readable.
            time.sleep(0.02)
    finally:
        client.close()

    if prune_set:
        kept = [t for t in tokens if t["token"] not in prune_set]
        save_tokens(kept)
        print(f"[push] pruned {len(prune_set)} dead tokens")

    counts = {
        "sent": sent,
        "failed": failed,
        "pruned": len(prune_set),
        "skipped": len(tokens) - len(targets),
    }
    print(f"[push] {counts}")
    return counts


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--episode-id", required=True)
    p.add_argument("--level", required=True, choices=["easy", "medium", "hard"])
    p.add_argument("--title", required=True, help="episode title to use as push body")
    p.add_argument("--sandbox", action="store_true", help="use APNs sandbox endpoint")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    push_episode(
        episode_id=args.episode_id,
        level=args.level,
        title=args.title,
        sandbox=args.sandbox,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
