"""
Podcast RSS 监听层。
- parse_feed: 解析单个 RSS feed，返回近期集列表
- scan_feeds: 批量轮询所有 feed，返回最近 N 天的所有新集（按发布时间倒序）

每集元数据：title / audio_url / published_at / duration / description / thumbnail
"""
from datetime import datetime, timedelta, timezone
from typing import Optional
import time

import feedparser
import requests


def _parse_published(entry) -> Optional[datetime]:
    """RSS published 字段通常是 RFC 822 字符串，feedparser 已解析为 published_parsed."""
    if hasattr(entry, "published_parsed") and entry.published_parsed:
        try:
            return datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)
        except Exception:
            pass
    return None


def _enclosure_url(entry) -> Optional[str]:
    """podcast 的 mp3/m4a 在 enclosures 里。"""
    enc = getattr(entry, "enclosures", None) or []
    for e in enc:
        url = e.get("href") or e.get("url")
        if url and ("audio" in (e.get("type") or "") or url.lower().endswith((".mp3", ".m4a", ".aac"))):
            return url
        if url:
            return url
    return None


def _itunes_duration_seconds(entry) -> Optional[int]:
    """itunes:duration 字段，可能是 'HH:MM:SS' / 'MM:SS' / 秒数."""
    dur = getattr(entry, "itunes_duration", None)
    if not dur:
        return None
    parts = dur.split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        return int(parts[0])
    except (ValueError, IndexError):
        return None


def parse_feed(url: str, days_back: int = 14, max_entries: int = 10) -> list[dict]:
    """单个 feed → 近期 N 天的 episodes."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days_back)

    # feedparser 用 requests 拉一次更可控（RSS 服务器对 UA 敏感）
    try:
        r = requests.get(url, timeout=15, headers={"User-Agent": "Castlingo-Pipeline/1.0"})
        if r.status_code != 200:
            print(f"  ! feed fetch failed: {url} HTTP {r.status_code}")
            return []
        feed = feedparser.parse(r.content)
    except Exception as e:
        print(f"  ! feed fetch error: {url} — {e}")
        return []

    out = []
    for entry in feed.entries[:max_entries]:
        pub = _parse_published(entry)
        if pub and pub < cutoff:
            continue
        audio_url = _enclosure_url(entry)
        if not audio_url:
            continue
        out.append({
            "title": entry.get("title", "").strip(),
            "audio_url": audio_url,
            "published_at": pub.strftime("%Y-%m-%dT%H:%M:%SZ") if pub else "",
            "duration_seconds": _itunes_duration_seconds(entry) or 0,
            "description": (entry.get("summary") or entry.get("description") or "")[:500],
            "feed_title": feed.feed.get("title", ""),
            "guid": entry.get("id") or entry.get("guid") or audio_url,
            "thumbnail": _feed_thumbnail(entry, feed),
        })
    return out


def _feed_thumbnail(entry, feed) -> Optional[str]:
    # entry 自带 image，否则回到 feed-level image
    img = getattr(entry, "image", None)
    if img and isinstance(img, dict):
        return img.get("href")
    images = getattr(entry, "image_url", None)
    if images:
        return images
    feed_img = getattr(feed.feed, "image", None)
    if feed_img and isinstance(feed_img, dict):
        return feed_img.get("href")
    return None


def scan_feeds(feeds: list[dict], days_back: int = 14, max_per_feed: int = 5) -> list[dict]:
    """批量轮询所有 RSS feed，返回所有新集合并的列表."""
    all_episodes = []
    for f in feeds:
        url = f["url"]
        print(f"  · scanning RSS {f['label']}…")
        try:
            eps = parse_feed(url, days_back=days_back, max_entries=max_per_feed)
        except Exception as e:
            print(f"  ! parse error {url}: {e}")
            continue
        for ep in eps:
            ep["source_label"] = f["label"]
            ep["source_topic"] = f["topic"]
            ep["source_tier"] = f["tier"]
            ep["source_kind"] = "analysis"
        all_episodes.extend(eps)
        time.sleep(0.3)

    all_episodes.sort(key=lambda e: e.get("published_at", ""), reverse=True)
    return all_episodes


if __name__ == "__main__":
    from raw_podcast_sources import RSS_FEEDS
    print(f"Smoke test: scanning {len(RSS_FEEDS)} RSS feeds, 14-day window\n")
    eps = scan_feeds(RSS_FEEDS[:3], days_back=14, max_per_feed=3)
    print(f"\nFound {len(eps)} episodes:\n")
    for ep in eps[:10]:
        sec = ep["duration_seconds"]
        h, m = sec // 3600, (sec % 3600) // 60
        print(f"  [{ep['source_label']}] {ep['title'][:65]}")
        print(f"      {h}h{m}m · {ep['published_at'][:10]}")
        print(f"      audio: {ep['audio_url'][:80]}")
        print()
