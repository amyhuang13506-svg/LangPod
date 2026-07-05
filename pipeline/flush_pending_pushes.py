#!/usr/bin/env python3
"""
Drain the pending-push queue and fire APNs.

Two cron slots, one type each, so a given user gets at most TWO buzzes per day:

    30 7 * * *  flush_pending_pushes.py --type raw_podcast    # morning YouTube (07:30 CST)

Note: the afternoon GPT-episode flush is intentionally NOT scheduled — users get
exactly two buzzes a day: the 07:30 YouTube push (server) and the 20:00 evening
content push (on-device local arbiter: 今日句型 / 今日单词, alternating by date).

Behaviour with `--type`:
  - Only items of that type are flushed and removed from the queue.
  - Items of other types are LEFT in the queue for their own scheduled flush.
  - Stale items (>36h) are dropped regardless of type.

Episode flush dedups to ONE push per level. The pipeline normally writes 2
episodes per level per night (`*-001` and `*-002`); we send the user only the
earliest-queued one (= `*-001` = the day's primary). The other ~5 still appear
in the app's daily list — they just don't ring everyone's phone.

Raw-podcast flush also dedups to ONE push total (earliest queued wins). The
YouTube monitor may enqueue 1–3 videos per day; users still see all of them in
the app's video list, but only get one morning buzz.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from enqueue_push import peek_queue, remove_items  # noqa: E402
from push_new_episode import push_episode  # noqa: E402
from push_new_raw_podcast import push_raw_podcast  # noqa: E402

STALE_AFTER_SECONDS = 36 * 3600  # drop items older than 1.5 days

VALID_TYPES = {"episode", "raw_podcast"}


def _ts(it: dict) -> int:
    return int(it.get("queued_at", 0))


def _select_episode_winners(items: list[dict]) -> list[dict]:
    """One episode per level — earliest queued wins (= the day's primary)."""
    by_level: dict[str, dict] = {}
    for it in sorted(items, key=_ts):  # oldest first
        lvl = it.get("level", "easy")
        if lvl not in by_level:
            by_level[lvl] = it
    return list(by_level.values())


def _select_raw_podcast_winner(items: list[dict]) -> list[dict]:
    """At most one raw_podcast push — earliest queued wins."""
    if not items:
        return []
    return [sorted(items, key=_ts)[0]]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--type",
        choices=sorted(VALID_TYPES),
        help="If set, only flush items of this type; leave others in the queue. "
             "If omitted, flush everything (one-shot manual run).",
    )
    args = p.parse_args()

    items = peek_queue()
    now = int(time.time())
    print(f"[flush] {datetime.now().isoformat(timespec='seconds')} — queue size {len(items)}, type={args.type or 'all'}")

    if not items:
        print("[flush] nothing in queue")
        return

    fresh = [it for it in items if (now - _ts(it)) < STALE_AFTER_SECONDS]
    stale_count = len(items) - len(fresh)
    if stale_count:
        print(f"[flush] dropping {stale_count} stale items (>{STALE_AFTER_SECONDS//3600}h old)")

    if args.type:
        targets = [it for it in fresh if it.get("type") == args.type]
        print(f"[flush] {len(targets)}/{len(fresh)} items match type={args.type}")
    else:
        targets = fresh

    # Per-type post-processing: episodes get deduped to one-per-level, raw
    # podcasts to one-total, so a single morning/afternoon cron fires at most a
    # handful of notifications per user (not one per item enqueued that day).
    if args.type == "episode" or (args.type is None and any(t.get("type") == "episode" for t in targets)):
        episodes = [t for t in targets if t.get("type") == "episode"]
        winners = _select_episode_winners(episodes)
        dropped = len(episodes) - len(winners)
        if dropped:
            print(f"[flush] dedup: keeping 1 episode per level ({len(winners)} kept, {dropped} skipped)")
        non_episodes = [t for t in targets if t.get("type") != "episode"]
        targets = non_episodes + winners

    if args.type == "raw_podcast" or (args.type is None and any(t.get("type") == "raw_podcast" for t in targets)):
        raws = [t for t in targets if t.get("type") == "raw_podcast"]
        winners = _select_raw_podcast_winner(raws)
        dropped = len(raws) - len(winners)
        if dropped:
            print(f"[flush] dedup: keeping 1 raw_podcast total ({len(winners)} kept, {dropped} skipped)")
        non_raws = [t for t in targets if t.get("type") != "raw_podcast"]
        targets = non_raws + winners

    sent = 0
    failed = 0
    for it in targets:
        kind = it.get("type")
        try:
            if kind == "episode":
                push_episode(
                    episode_id=it["episode_id"],
                    level=it["level"],
                    title=it.get("title", ""),
                    sandbox=False,
                )
            elif kind == "raw_podcast":
                push_raw_podcast(
                    podcast_id=it["podcast_id"],
                    title=it.get("title", ""),
                    speaker=it.get("speaker", ""),
                    sandbox=False,
                )
            else:
                print(f"[flush] unknown item type: {kind!r} — skipping")
                failed += 1
                continue
            sent += 1
        except Exception as e:  # noqa: BLE001
            print(f"[flush] failed to push {it}: {type(e).__name__}: {e}")
            failed += 1

    # Remove processed items + stale items of the same type from the queue.
    # Items of OTHER types stay in the queue for their own flush.
    if args.type:
        removed = remove_items(lambda it: it.get("type") == args.type)
    else:
        # No filter — wipe everything we considered (fresh + stale).
        removed = remove_items(lambda _: True)

    print(f"[flush] done — sent={sent} failed={failed} removed_from_queue={removed}")


if __name__ == "__main__":
    main()
