#!/usr/bin/env python3
"""
Notify all subscribed users about a newly published raw podcast (硅谷原声).

Differs from `push_new_episode.py`:
  - No level filter: raw podcasts aren't categorized by Easy/Medium/Hard.
  - Push goes to every device in tokens.json.
  - Payload's `episode_id` carries the `raw-yt-…` / `raw-rss-…` namespaced ID,
    which the iOS deep-link handler routes to RawPodcastPlayerView (not the
    regular episode player).

Usage:
    python3 push_new_raw_podcast.py \\
        --podcast-id raw-yt-XYZ123 \\
        --title "Sam Altman Stanford Talk 2024" \\
        --speaker "Sam Altman" \\
        [--sandbox]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apns_push import send_push, make_client  # noqa: E402

TOKENS_FILE = "/opt/langpod/secrets/tokens.json"


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


def push_raw_podcast(
    *,
    podcast_id: str,
    title: str,
    speaker: str = "",
    intent: str = "new_raw_podcast",
    sandbox: bool = False,
    dry_run: bool = False,
) -> dict[str, int]:
    """
    Push a notification to every registered device.
    Returns counts: {sent, failed, pruned, total}.
    """
    tokens = load_tokens()
    if not tokens:
        print("[raw-push] no tokens registered")
        return {"sent": 0, "failed": 0, "pruned": 0, "total": 0}

    # Title hugs the speaker (better recognition than a generic "新一集"); body
    # is the talk title verbatim. If there's no speaker, drop in a default.
    # No "硅谷原声" prefix — the morning YouTube push isn't always Silicon
    # Valley content (could be TED, Huberman, MKBHD, etc.).
    push_title = f"今日视频 · {speaker}" if speaker.strip() else "今日视频"
    push_body = title or "打开看一看"

    extras: dict[str, Any] = {
        "episode_id": podcast_id,  # iOS deep-link uses the prefix to dispatch
        "intent": intent,
    }

    print(f"[raw-push] pushing to {len(tokens)} tokens — id={podcast_id} title={title!r}")

    if dry_run:
        for t in tokens[:5]:
            print(f"  [dry-run] would push to {t['token'][:16]}…")
        return {"sent": 0, "failed": 0, "pruned": 0, "total": len(tokens)}

    sent = failed = 0
    prune_set: set[str] = set()
    client = make_client()
    try:
        for row in tokens:
            token = row["token"]
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
            except Exception as e:  # noqa: BLE001
                print(f"  [error] {token[:16]}… {type(e).__name__}: {e}")
                failed += 1
                continue

            if code == 200:
                sent += 1
            elif code == 410:
                print(f"  [prune] 410 {token[:16]}…")
                prune_set.add(token)
                failed += 1
            elif code == 400 and "BadDeviceToken" in resp:
                print(f"  [prune] 400 BadDeviceToken {token[:16]}…")
                prune_set.add(token)
                failed += 1
            else:
                print(f"  [fail] {code} {resp[:120]} token={token[:16]}…")
                failed += 1
            time.sleep(0.02)
    finally:
        client.close()

    if prune_set:
        kept = [t for t in tokens if t["token"] not in prune_set]
        save_tokens(kept)
        print(f"[raw-push] pruned {len(prune_set)} dead tokens")

    counts = {"sent": sent, "failed": failed, "pruned": len(prune_set), "total": len(tokens)}
    print(f"[raw-push] {counts}")
    return counts


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--podcast-id", required=True, help="raw-yt-… or raw-rss-…")
    p.add_argument("--title", required=True)
    p.add_argument("--speaker", default="")
    p.add_argument("--sandbox", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    push_raw_podcast(
        podcast_id=args.podcast_id,
        title=args.title,
        speaker=args.speaker,
        sandbox=args.sandbox,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
