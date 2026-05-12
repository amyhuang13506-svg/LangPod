"""
YouTube Data API v3 监听层。
- resolve_channel_id: @handle → channel ID（每个 handle 跑一次缓存即可）
- fetch_recent_videos: 拉指定频道近期 N 条视频（按发布时间倒序）
- video_details: 单视频完整元数据（含 ISO 8601 时长、观看数）

配额预算（参考）：
- channels.list (forHandle): 1u
- search.list (channelId+date): 100u
- videos.list (id, batched up to 50): 1u

监听 17 个频道每天一次：channel resolve 缓存后 ≈ 17 × 100 = 1700u/day。
配额 10000u/day，富余空间足够加事件类查询。
"""
import json
import re
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import requests

from config import YOUTUBE_API_KEY, YOUTUBE_API_BASE

CACHE_DIR = Path(__file__).resolve().parent / "output" / "youtube_cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
CHANNEL_ID_CACHE = CACHE_DIR / "channel_ids.json"


def _load_channel_id_cache() -> dict:
    if CHANNEL_ID_CACHE.exists():
        try:
            return json.loads(CHANNEL_ID_CACHE.read_text())
        except Exception:
            return {}
    return {}


def _save_channel_id_cache(cache: dict) -> None:
    CHANNEL_ID_CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2))


def resolve_channel_id(handle: str, api_key: str = YOUTUBE_API_KEY) -> Optional[str]:
    """@NVIDIA → 'UCHuiy8bXnmK5nisYHUd1J5g' 形式的 channel ID."""
    cache = _load_channel_id_cache()
    if handle in cache:
        return cache[handle]

    handle_clean = handle.lstrip("@")
    r = requests.get(
        f"{YOUTUBE_API_BASE}/channels",
        params={"part": "id", "forHandle": handle_clean, "key": api_key},
        timeout=15,
    )
    if r.status_code != 200:
        print(f"  ! channels.list failed for {handle}: HTTP {r.status_code} — {r.text[:200]}")
        return None
    items = r.json().get("items", [])
    if not items:
        print(f"  ! channel not found: {handle}")
        return None

    cid = items[0]["id"]
    cache[handle] = cid
    _save_channel_id_cache(cache)
    return cid


def fetch_recent_videos(
    channel_id: str,
    api_key: str = YOUTUBE_API_KEY,
    max_results: int = 5,
    published_after: Optional[datetime] = None,
) -> list[dict]:
    """从 YouTube 频道拉近期视频列表。**完全免费、不消耗 Data API 配额**。

    实现：yt-dlp 走 IPRoyal 住宅代理 list channel /videos 页面（替代 YouTube RSS feed —
    后者 2026-05 起对 channel_id 大面积返回 404/500，已不可用）。

    返回字段简化（只有 video_id + title + channel_title），其余 published_at /
    duration / view_count / like_count 由下游 fetch_video_details 通过 Data API 补全。
    `published_after` 过滤交给下游的 score_item 时新度处理（避免 flat playlist 没日期的尴尬）。
    """
    import yt_dlp
    proxy = ""
    try:
        from config import YOUTUBE_PROXY_URL as _proxy
        proxy = _proxy or ""
    except ImportError:
        pass

    opts = {
        "extract_flat": True,
        "quiet": True,
        "no_warnings": True,
        "playlistend": max_results,
        "skip_download": True,
    }
    if proxy:
        opts["proxy"] = proxy

    url = f"https://www.youtube.com/channel/{channel_id}/videos"
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
    except Exception as e:
        print(f"  ! channel scan failed: {e}")
        return []

    entries = info.get("entries") or []
    channel_title = info.get("channel") or info.get("uploader") or ""

    out = []
    for e in entries[:max_results]:
        vid = e.get("id")
        if not vid:
            continue
        thumb = f"https://i.ytimg.com/vi/{vid}/maxresdefault.jpg"
        out.append({
            "video_id":      vid,
            "title":         (e.get("title") or "").strip(),
            "channel_title": channel_title,
            "published_at":  "",     # 由 fetch_video_details (Data API) 补
            "description":   "",     # 同上
            "thumbnail":     thumb,
        })
    return out


def fetch_video_details(video_ids: list[str], api_key: str = YOUTUBE_API_KEY) -> list[dict]:
    """批量拉视频详情（一次最多 50 个）。返回顺序与输入对应。"""
    if not video_ids:
        return []
    out = []
    for i in range(0, len(video_ids), 50):
        chunk = video_ids[i:i + 50]
        r = requests.get(
            f"{YOUTUBE_API_BASE}/videos",
            params={
                "part": "snippet,contentDetails,statistics",
                "id": ",".join(chunk),
                "key": api_key,
            },
            timeout=15,
        )
        if r.status_code != 200:
            print(f"  ! videos.list failed: HTTP {r.status_code} — {r.text[:200]}")
            continue
        for it in r.json().get("items", []):
            # Defensive: live streams, premieres, and removed/age-gated videos
            # sometimes lack contentDetails.duration or even contentDetails
            # entirely. The 2026-05-12 cron crashed on KeyError 'duration' and
            # produced zero output for the day — must not let one bad item
            # take down the entire scan. Skip if essential fields missing.
            try:
                snippet = it.get("snippet", {})
                stats = it.get("statistics", {}) or {}
                content = it.get("contentDetails", {}) or {}
                duration_iso = content.get("duration") or "PT0S"
                out.append({
                    "video_id": it.get("id", ""),
                    "title": snippet.get("title", ""),
                    "channel_title": snippet.get("channelTitle", ""),
                    "channel_id": snippet.get("channelId", ""),
                    "published_at": snippet.get("publishedAt", ""),
                    "description": snippet.get("description", ""),
                    "duration": duration_iso,
                    "duration_seconds": _parse_iso_duration(duration_iso),
                    "view_count": int(stats.get("viewCount", 0) or 0),
                    "like_count": int(stats.get("likeCount", 0) or 0),
                    "thumbnail": snippet.get("thumbnails", {}).get("high", {}).get("url"),
                })
            except Exception as e:  # noqa: BLE001 — never let one bad item kill the run
                print(f"  ! skip malformed item {it.get('id','?')}: {type(e).__name__}: {e}")
                continue
    return out


def _parse_iso_duration(iso: str) -> int:
    """ISO 8601 'PT2H30M5S' → 秒。"""
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso or "")
    if not m:
        return 0
    h, mn, s = (int(x) if x else 0 for x in m.groups())
    return h * 3600 + mn * 60 + s


def scan_channels(
    channels: list[dict],
    days_back: int = 7,
    max_per_channel: int = 5,
) -> list[dict]:
    """轮询频道列表，返回近 N 天上传的视频（已含详情，按时间倒序）。"""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days_back)
    all_video_ids: list[tuple[str, dict]] = []  # (video_id, source_meta)

    for ch in channels:
        handle = ch["handle"]
        print(f"  · scanning {handle} ({ch['label']})…")
        cid = resolve_channel_id(handle)
        if not cid:
            continue
        recent = fetch_recent_videos(cid, max_results=max_per_channel, published_after=cutoff)
        for v in recent:
            all_video_ids.append((v["video_id"], ch))
        time.sleep(0.2)  # gentle rate limit

    # Batch enrich
    ids = [vid for vid, _ in all_video_ids]
    src_by_id = {vid: ch for vid, ch in all_video_ids}
    rss_by_id = {}  # 备份 RSS 元数据，配额耗尽时兜底
    for vid, _ in all_video_ids:
        for ch_handle, channel_meta in [(s.get("handle"), s) for _, s in all_video_ids]:
            pass  # 用下面的方式填
    # 收集 RSS 原始信息
    rss_meta_map: dict[str, dict] = {}
    for ch in channels:
        cid = resolve_channel_id(ch["handle"])
        if not cid: continue
        recent_for_meta = fetch_recent_videos(cid, max_results=max_per_channel, published_after=cutoff)
        for v in recent_for_meta:
            rss_meta_map[v["video_id"]] = v

    details = fetch_video_details(ids)
    enriched_ids = {d["video_id"] for d in details}

    # 没拉到 videos.list 详情的视频，用 RSS 元数据兜底（duration=0, view=0, like=0）
    for vid, ch in all_video_ids:
        if vid in enriched_ids: continue
        rss = rss_meta_map.get(vid, {})
        details.append({
            "video_id":         vid,
            "title":            rss.get("title", ""),
            "channel_title":    rss.get("channel_title", ch.get("label", "")),
            "channel_id":       resolve_channel_id(ch["handle"]) or "",
            "published_at":     rss.get("published_at", ""),
            "description":      rss.get("description", ""),
            "duration":         "PT0S",
            "duration_seconds": 0,
            "view_count":       0,
            "like_count":       0,
            "thumbnail":        rss.get("thumbnail"),
        })

    for d in details:
        src = src_by_id.get(d["video_id"], {})
        d["source_label"] = src.get("label", d["channel_title"])
        d["source_topic"] = src.get("topic", "")
        d["source_tier"] = src.get("tier", 3)
        d["source_kind"] = src.get("kind", "company")
        d["source_category"] = src.get("category", "tech_keynote")

    # Sort by published_at desc
    details.sort(key=lambda d: d["published_at"], reverse=True)
    return details


if __name__ == "__main__":
    # Smoke test: scan top 3 channels, last 30 days
    from raw_podcast_sources import YOUTUBE_CHANNELS
    pick = [c for c in YOUTUBE_CHANNELS if c["tier"] == 1][:3]
    print(f"Smoke test: {len(pick)} channels, 30-day window")
    videos = scan_channels(pick, days_back=30, max_per_channel=3)
    print(f"\nFound {len(videos)} videos:\n")
    for v in videos[:10]:
        h = v["duration_seconds"] // 3600
        m = (v["duration_seconds"] % 3600) // 60
        print(f"  [{v['source_label']}] {v['title'][:60]}")
        print(f"      {h}h{m}m · {v['view_count']:,} views · {v['published_at'][:10]}")
        print(f"      https://youtube.com/watch?v={v['video_id']}")
        print()
