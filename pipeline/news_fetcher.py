"""
Fetch current-day news headlines from NewsAPI, filter out politically sensitive
items (especially China-related), and return a small inspiration set for GPT
prompt injection.

Design:
- One fetch per pipeline run (cron runs daily), cached in /tmp/castlingo_news_cache.json
  for the calendar day so repeated script generations don't burn the 100/day quota.
- Failures are non-fatal: empty list → generate_script falls back to TOPIC_POOL.
- Filter is conservative: drop if ANY blocked keyword appears in title or description.
"""

import json
import os
import tempfile
from datetime import datetime

import requests

from config import (
    NEWS_API_KEY,
    NEWS_API_ENDPOINT,
    NEWS_CATEGORIES,
    NEWS_BLOCKED_KEYWORDS,
)

CACHE_PATH = os.path.join(tempfile.gettempdir(), "castlingo_news_cache.json")
CACHE_TTL_HOURS = 6  # refresh if older than this; daily cron won't hit this anyway


def _is_blocked(headline: dict) -> bool:
    """Return True if headline mentions any blocked keyword in title or description."""
    haystack = " ".join([
        (headline.get("title") or ""),
        (headline.get("description") or ""),
    ]).lower()
    return any(kw in haystack for kw in NEWS_BLOCKED_KEYWORDS)


def _fetch_category(category: str, country: str = "us", page_size: int = 20) -> list:
    """Fetch one category from NewsAPI. Returns list of articles (possibly empty)."""
    try:
        resp = requests.get(
            NEWS_API_ENDPOINT,
            params={
                "country": country,
                "category": category,
                "pageSize": page_size,
                "apiKey": NEWS_API_KEY,
            },
            timeout=10,
        )
        if resp.status_code != 200:
            print("   ⚠️  NewsAPI %s returned %d" % (category, resp.status_code))
            return []
        data = resp.json()
        if data.get("status") != "ok":
            print("   ⚠️  NewsAPI status=%s" % data.get("status"))
            return []
        return data.get("articles", [])
    except Exception as e:
        print("   ⚠️  NewsAPI fetch failed for %s: %s" % (category, e))
        return []


def _load_cache() -> dict:
    if not os.path.exists(CACHE_PATH):
        return {}
    try:
        with open(CACHE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_cache(cache: dict) -> None:
    try:
        with open(CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print("   ⚠️  News cache save failed: %s" % e)


def _cache_fresh(cache: dict) -> bool:
    ts = cache.get("fetched_at")
    if not ts:
        return False
    try:
        fetched = datetime.fromisoformat(ts)
    except Exception:
        return False
    age_hours = (datetime.now() - fetched).total_seconds() / 3600.0
    return age_hours < CACHE_TTL_HOURS


def fetch_headlines_for_level(level: str, max_count: int = 5) -> list:
    """Return up to `max_count` filtered headline strings for the given level.

    Each entry is a compact "Title — Description" string suitable for prompt
    injection. Empty list on any failure (caller falls back to TOPIC_POOL).
    """
    cache = _load_cache()
    if _cache_fresh(cache) and level in cache.get("by_level", {}):
        return cache["by_level"][level][:max_count]

    categories = NEWS_CATEGORIES.get(level, ["general"])
    raw = []
    for cat in categories:
        raw.extend(_fetch_category(cat))

    # Dedupe by title, filter, keep concise form
    seen_titles = set()
    filtered = []
    for art in raw:
        title = (art.get("title") or "").strip()
        if not title or title in seen_titles:
            continue
        if _is_blocked(art):
            continue
        seen_titles.add(title)
        desc = (art.get("description") or "").strip()
        # Trim " - SourceName" suffix NewsAPI appends to titles
        if " - " in title:
            title = title.rsplit(" - ", 1)[0]
        entry = title if not desc else "%s — %s" % (title, desc[:140])
        filtered.append(entry)

    # Persist across all levels we haven't fetched yet (shared cache)
    cache.setdefault("by_level", {})[level] = filtered
    cache["fetched_at"] = datetime.now().isoformat()
    _save_cache(cache)

    return filtered[:max_count]


if __name__ == "__main__":
    # Quick smoke test
    for lv in ("easy", "medium", "hard"):
        print("\n=== %s ===" % lv)
        for h in fetch_headlines_for_level(lv, max_count=5):
            print("•", h)
