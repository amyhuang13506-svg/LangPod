"""
一次性脚本：把指定 YouTube 视频走完整 raw_podcast 流程
用法：python3 process_one_video.py <video_id> [category] [topic] [speaker] [event]

示例：python3 process_one_video.py NCKQL0op30E tech_keynote "AI · 访谈" "Core Memory" "Core Memory Podcast"
"""
import sys

from raw_podcast_processor import process_candidates
from youtube_monitor import fetch_video_details


def fetch_video_meta(video_id: str) -> dict:
    """Pull title/duration/views via YouTube Data API.

    Avoids yt-dlp entirely for metadata — yt-dlp hits the SABR/n-challenge
    wall on many videos ("Requested format is not available") even with
    proxy + cookies. The Data API key auth has no such restriction. The
    actual mp4 download still happens later through yt-dlp with proxy +
    cookies + js_runtimes in raw_podcast_processor.download_video_youtube.
    """
    details = fetch_video_details([video_id])
    if not details:
        raise RuntimeError(
            f"YouTube Data API returned no details for {video_id}. "
            "Check the video ID is correct + the API key in config.py."
        )
    d = details[0]
    return {
        "video_id":         video_id,
        "title":            d.get("title", ""),
        "channel_title":    d.get("channel_title", ""),
        "published_at":     (d.get("published_at") or "")[:10],
        "description":      (d.get("description") or "")[:500],
        "duration_seconds": int(d.get("duration_seconds") or 0),
        "view_count":       int(d.get("view_count") or 0),
        "like_count":       int(d.get("like_count") or 0),
        "thumbnail":        d.get("thumbnail") or f"https://i.ytimg.com/vi/{video_id}/maxresdefault.jpg",
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    vid = sys.argv[1]
    category = sys.argv[2] if len(sys.argv) > 2 else "tech_keynote"
    topic = sys.argv[3] if len(sys.argv) > 3 else "AI · 访谈"
    speaker_override = sys.argv[4] if len(sys.argv) > 4 else None
    event_override = sys.argv[5] if len(sys.argv) > 5 else None

    print(f"=== 抓取 YouTube 元数据：{vid} ===")
    meta = fetch_video_meta(vid)
    print(f"  title:    {meta['title']}")
    print(f"  channel:  {meta['channel_title']}")
    print(f"  date:     {meta['published_at']}")
    print(f"  duration: {meta['duration_seconds']}s ({meta['duration_seconds']//60}min)")
    print(f"  views:    {meta['view_count']:,}")

    speaker = speaker_override or meta["channel_title"] or "Unknown"
    event = event_override or speaker

    candidate = {
        "media_type":       "video",
        "source_id":        vid,
        "source_url":       f"https://youtube.com/watch?v={vid}",
        "title":            meta["title"],
        "speaker":          speaker,
        "event":            event,
        "published_at":     meta["published_at"],
        "duration_seconds": meta["duration_seconds"],
        "topic":            topic,
        "category":         category,
        "thumbnail":        meta["thumbnail"],
        "description":      meta["description"],
        "score":            100,
        "kind":             "video",
        "view_count":       meta["view_count"],
        "like_count":       meta["like_count"],
    }

    print(f"\n=== 进入 process_candidates（下载 → 上传 OSS → 转写） ===")
    process_candidates([candidate], top_n=1)


if __name__ == "__main__":
    main()
