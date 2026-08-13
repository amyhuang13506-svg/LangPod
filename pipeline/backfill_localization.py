# -*- coding: utf-8 -*-
"""
Backfill entry: enqueue existing OSS episodes for localization, newest first.
Consumption is localize_daily.py — same code path as the daily flow, fully
idempotent (episodes whose episode_{lang}.json already exists are re-derived
cheaply: text layer skipped, upload overwrites in place).

Usage:
  python3 backfill_localization.py --type episodes [--level easy] [--since 2026-07-15] [--limit 30]
  python3 localize_daily.py     # drain (run repeatedly / nightly until empty)

raw/lessons/expressions backfill lands with their localization passes (P5).
"""

import argparse
import json

from localize_queue import enqueue_episode
from upload_oss import get_bucket

import oss2


def list_episode_ids(bucket, level):
    """(date, episode_id) list from the legacy index (source of truth for zh)."""
    data = bucket.get_object("episodes/%s/index.json" % level).read()
    index = json.loads(data)
    return [(ep["date"], ep["id"]) for ep in index.get("episodes", [])]


def existing_localized(bucket, level, lang):
    """episode_ids that already have episode_{lang}.json on OSS."""
    from languages import lang_suffix
    suffix = lang_suffix(lang)
    found = set()
    for obj in oss2.ObjectIterator(bucket, prefix="episodes/%s/" % level):
        if obj.key.endswith("/episode%s.json" % suffix):
            found.add(obj.key.split("/")[-2])
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", default="episodes", choices=["episodes"])
    ap.add_argument("--level", choices=["easy", "medium", "hard"])
    ap.add_argument("--since", help="only episodes with date >= YYYY-MM-DD")
    ap.add_argument("--limit", type=int, help="max episodes to enqueue (newest first)")
    ap.add_argument("--lang", default="ko", help="skip episodes already localized in this lang")
    args = ap.parse_args()

    bucket = get_bucket()
    levels = [args.level] if args.level else ["easy", "medium", "hard"]

    candidates = []
    for level in levels:
        done = existing_localized(bucket, level, args.lang)
        for date, ep_id in list_episode_ids(bucket, level):
            if ep_id in done:
                continue
            if args.since and date < args.since:
                continue
            candidates.append((date, ep_id, level))

    candidates.sort(reverse=True)  # newest first
    if args.limit:
        candidates = candidates[: args.limit]

    added = 0
    for _, ep_id, level in candidates:
        if enqueue_episode(ep_id, level):
            added += 1
    print("\n📬 enqueued %d episodes (%d already queued/localized skipped)"
          % (added, len(candidates) - added))
    print("Run: python3 localize_daily.py")


if __name__ == "__main__":
    main()
