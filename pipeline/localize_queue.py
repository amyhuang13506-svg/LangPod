# -*- coding: utf-8 -*-
"""
Localization work queue. generate_daily (and backfill) enqueue episodes after
the zh upload succeeds; localize_daily drains the queue per language.

File-locked JSON list (mirrors enqueue_push.py's pattern). Entry:
  {"type": "episode", "episode_id": "...", "level": "easy",
   "queued_at": iso, "langs_done": ["ko"], "attempts": {"ko": 1}}

Entries are removed once every NEW_LANGS language is done; stale entries
(>72h) are dropped with a warning at drain time.
"""

import fcntl
import json
import os
from datetime import datetime, timezone

QUEUE_FILE = os.environ.get(
    "LOCALIZE_QUEUE_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "output", "localize_queue.json"),
)
STALE_HOURS = 72
MAX_ATTEMPTS_PER_LANG = 3


def _load(f):
    try:
        f.seek(0)
        data = f.read()
        return json.loads(data) if data.strip() else []
    except (ValueError, OSError):
        return []


def _save(f, items):
    f.seek(0)
    f.truncate()
    f.write(json.dumps(items, ensure_ascii=False, indent=1))


def _locked(fn):
    os.makedirs(os.path.dirname(QUEUE_FILE), exist_ok=True)
    with open(QUEUE_FILE, "a+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            return fn(f)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def enqueue_episode(episode_id, level):
    """Idempotent enqueue. Called by generate_daily after zh upload."""
    def op(f):
        items = _load(f)
        for it in items:
            if it.get("type") == "episode" and it.get("episode_id") == episode_id:
                return False
        items.append({
            "type": "episode",
            "episode_id": episode_id,
            "level": level,
            "queued_at": datetime.now(timezone.utc).isoformat(),
            "langs_done": [],
            "attempts": {},
        })
        _save(f, items)
        return True
    added = _locked(op)
    if added:
        print("   📬 localize queue += %s" % episode_id)
    return added


def pending_items():
    """Snapshot of the queue (stale entries dropped and persisted)."""
    def op(f):
        items = _load(f)
        fresh = []
        now = datetime.now(timezone.utc)
        for it in items:
            try:
                age_h = (now - datetime.fromisoformat(it["queued_at"])).total_seconds() / 3600
            except (KeyError, ValueError):
                age_h = 0
            if age_h > STALE_HOURS:
                print("   ⚠️  dropping stale localize entry (%.0fh): %s" % (age_h, it.get("episode_id")))
                continue
            fresh.append(it)
        _save(f, fresh)
        return fresh
    return _locked(op)


def mark(episode_id, lang, success):
    """Record one language attempt; remove entry when all NEW_LANGS done."""
    from languages import NEW_LANGS

    def op(f):
        items = _load(f)
        kept = []
        for it in items:
            if it.get("type") == "episode" and it.get("episode_id") == episode_id:
                attempts = it.setdefault("attempts", {})
                attempts[lang] = attempts.get(lang, 0) + 1
                if success and lang not in it.setdefault("langs_done", []):
                    it["langs_done"].append(lang)
                done = set(it["langs_done"])
                exhausted = {l for l, n in attempts.items() if n >= MAX_ATTEMPTS_PER_LANG}
                if set(NEW_LANGS) <= (done | exhausted):
                    if done >= set(NEW_LANGS):
                        continue  # fully done → remove
                    print("   ⚠️  %s: attempts exhausted for %s — removing from queue"
                          % (episode_id, sorted(set(NEW_LANGS) - done)))
                    continue
            kept.append(it)
        _save(f, kept)
    _locked(op)
