#!/usr/bin/env python3
"""
Defer push delivery: instead of firing APNs the moment content lands on OSS
(which can happen at midnight or 4 AM and wakes users up), the pipelines call
`enqueue_episode()` / `enqueue_raw_podcast()` here.

A separate cron (`flush_pending_pushes.py` at 07:50 CST) drains the queue and
fires the actual APNs requests, so users get notified at a polite hour even
though the content has been sitting on OSS for hours.

Queue file: /opt/langpod/secrets/pending_pushes.json
Schema: list of dicts with shape:
  {"type": "episode" | "raw_podcast", ..., "queued_at": <unix ts>}
"""
from __future__ import annotations

import json
import os
import threading
import time
from typing import Any

QUEUE_FILE = "/opt/langpod/secrets/pending_pushes.json"
_lock = threading.Lock()


def _read() -> list[dict[str, Any]]:
    if not os.path.exists(QUEUE_FILE):
        return []
    try:
        with open(QUEUE_FILE, "r") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError):
        return []


def _write(items: list[dict[str, Any]]) -> None:
    os.makedirs(os.path.dirname(QUEUE_FILE), exist_ok=True)
    tmp = QUEUE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)
    os.replace(tmp, QUEUE_FILE)
    os.chmod(QUEUE_FILE, 0o600)


def _append(entry: dict[str, Any]) -> None:
    with _lock:
        items = _read()
        # Dedupe on (type, primary_id) so a re-run of the pipeline doesn't
        # double-queue the same content.
        ident_key = "episode_id" if entry["type"] == "episode" else "podcast_id"
        ident = entry[ident_key]
        existing_idx = next(
            (i for i, x in enumerate(items)
             if x.get("type") == entry["type"] and x.get(ident_key) == ident),
            -1,
        )
        if existing_idx >= 0:
            items[existing_idx] = entry  # refresh title/etc
        else:
            items.append(entry)
        _write(items)


def enqueue_episode(*, episode_id: str, level: str, title: str) -> None:
    """Queue a GPT-generated podcast episode for the next push flush."""
    _append({
        "type": "episode",
        "episode_id": episode_id,
        "level": level.lower(),
        "title": title,
        "queued_at": int(time.time()),
    })
    print(f"  📮 enqueued episode push: {episode_id} ({level})")


def enqueue_raw_podcast(*, podcast_id: str, title: str, speaker: str = "") -> None:
    """Queue a raw YouTube podcast for the next push flush."""
    _append({
        "type": "raw_podcast",
        "podcast_id": podcast_id,
        "title": title,
        "speaker": speaker,
        "queued_at": int(time.time()),
    })
    print(f"  📮 enqueued raw_podcast push: {podcast_id} ({speaker})")


def peek_queue() -> list[dict[str, Any]]:
    """Read-only view of queued items, used by the flush job + status checks."""
    return _read()


def clear_queue() -> int:
    """Wipe the queue. Returns the number of items removed."""
    with _lock:
        items = _read()
        n = len(items)
        _write([])
    return n


def remove_items(predicate) -> int:
    """
    Remove every queued item where `predicate(item)` is True; keep the rest.
    Used by the per-type flush so the 07:50 cron only consumes raw_podcast
    entries and leaves episodes alone for the 17:00 cron (and vice versa).
    Returns the number of removed items.
    """
    with _lock:
        items = _read()
        before = len(items)
        kept = [it for it in items if not predicate(it)]
        if len(kept) != before:
            _write(kept)
        return before - len(kept)


if __name__ == "__main__":
    # CLI: dump current queue
    items = peek_queue()
    print(f"queue size: {len(items)}")
    for it in items:
        print(f"  {it}")
