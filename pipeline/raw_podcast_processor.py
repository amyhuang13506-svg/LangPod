"""
Pipeline A — 第二阶段：候选 → 下载音频 → 上传 OSS → 写入 master 清单

输入：raw_podcast_pipeline.py --json 输出的 candidates 列表
输出：
  - 音频文件上传到 OSS：raw_podcasts/<id>/audio.m4a
  - 缩略图上传：raw_podcasts/<id>/thumbnail.jpg
  - master JSON 更新：raw_podcasts/raw_podcasts.json（App 直接 fetch 这个 URL）

ID 规则：
  - YouTube 视频：raw-yt-<video_id>
  - RSS 集：raw-rss-<sha1(guid)[:12]>

Master 列表在 OSS 上是单一真理源，每天 cron 增量更新（不重复下载已有 ID）。
"""
import hashlib
import json
import re
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import requests

try:
    import yt_dlp
except ImportError:
    print("❌ pip install yt-dlp")
    sys.exit(1)

from config import (
    OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET,
    OSS_BUCKET_NAME, OSS_ENDPOINT, OSS_CDN_DOMAIN,
)

try:
    import oss2
except ImportError:
    print("❌ pip install oss2")
    sys.exit(1)


OUTPUT_DIR = Path(__file__).resolve().parent / "output"
OUTPUT_DIR.mkdir(exist_ok=True)
LOCAL_MASTER = OUTPUT_DIR / "raw_podcasts_master.json"
OSS_MASTER_KEY = "raw_podcasts/raw_podcasts.json"


def get_bucket():
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    return oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)


# =============================================================
# Master state — 单一真理源，本地缓存 + OSS 同步
# =============================================================

def load_master(bucket=None) -> list[dict]:
    """从 OSS 拉 master，OSS 拉不到回到本地缓存，再不行返回空。"""
    if bucket:
        try:
            data = bucket.get_object(OSS_MASTER_KEY).read()
            items = json.loads(data)
            LOCAL_MASTER.write_text(json.dumps(items, ensure_ascii=False, indent=2))
            print(f"  📥 master 从 OSS 加载（{len(items)} 条）")
            return items
        except oss2.exceptions.NoSuchKey:
            print("  ℹ️  OSS master 不存在，从空开始")
        except Exception as e:
            print(f"  ⚠️  OSS master 加载失败：{e}（回到本地缓存）")
    if LOCAL_MASTER.exists():
        return json.loads(LOCAL_MASTER.read_text())
    return []


def save_master(items: list[dict], bucket=None) -> None:
    """写本地 + 上传 OSS。"""
    LOCAL_MASTER.write_text(json.dumps(items, ensure_ascii=False, indent=2))
    print(f"  💾 master 本地写入 {LOCAL_MASTER.name}（{len(items)} 条）")
    if bucket:
        bucket.put_object(
            OSS_MASTER_KEY,
            json.dumps(items, ensure_ascii=False, indent=2).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        print(f"  ☁️  master 上传 OSS：{OSS_CDN_DOMAIN}/{OSS_MASTER_KEY}")


# =============================================================
# 候选 → master 条目转换
# =============================================================

def candidate_id(c: dict) -> str:
    """候选 → 稳定 ID。"""
    if c["media_type"] == "video":
        # YouTube video ID 已经是稳定的
        m = re.search(r"v=([\w-]+)", c["source_url"])
        vid = m.group(1) if m else c["source_id"]
        return f"raw-yt-{vid}"
    # RSS：guid 可能是 URL，hash 后取前 12 位
    h = hashlib.sha1((c.get("source_id") or c["source_url"]).encode()).hexdigest()[:12]
    return f"raw-rss-{h}"


def candidate_to_master_entry(
    c: dict,
    audio_oss_url: str,
    thumbnail_oss_url: Optional[str],
    has_video: bool,
    transcript_oss_url: Optional[str] = None,
) -> dict:
    """转成 App 的 RawPodcast Codable schema。"""
    return {
        "id":                  candidate_id(c),
        "title":               c["title"],
        "speaker":             c["speaker"],
        "event":               c.get("event") or c["speaker"],
        "media_type":          c["media_type"],
        "youtube_id":          _extract_youtube_id(c["source_url"]) if c["media_type"] == "video" else None,
        "audio_url":           audio_oss_url,
        "thumbnail":           thumbnail_oss_url,
        "has_video":           has_video,
        "transcript_url":      transcript_oss_url,
        "published_at":        c.get("published_at", ""),
        "duration_seconds":    c.get("duration_seconds", 0),
        "topic":               c.get("topic", ""),
        "category":            c.get("category", "tech_keynote"),  # tech_keynote | explore
        "thumbnail_color":     None,
        "summary_zh":          None,        # 留给 Pipeline B 填
        "related_episode_ids": [],          # 留给 Pipeline B 填
        # 内部字段（App 不读）
        "_source_url":         c["source_url"],
        "_score":              c.get("score", 0),
        "_view_count":         c.get("view_count", 0),
        "_like_count":         c.get("like_count", 0),
    }


def _extract_youtube_id(url: str) -> Optional[str]:
    m = re.search(r"(?:v=|youtu\.be/)([\w-]{11})", url)
    return m.group(1) if m else None


# =============================================================
# 下载（YouTube → yt-dlp 取 audio；RSS → 直接 GET）
# =============================================================

def download_video_youtube(youtube_url: str, out_path: Path) -> bool:
    """yt-dlp 下载 YouTube 视频（mp4，含 video + audio 两个轨道）。

    YouTube 2024 后强推 SABR 流，纯 audio 格式（itag 140）需要 PO Token 才能拉。
    workaround：tv_embedded / web_creator / android 客户端能拿到 format 18（mp4
    360p with audio）。我们保留这个 mp4 整体上传，App 端可以同时显示视频画面 +
    用 AVPlayer 播放音轨。
    """
    out_stem = out_path.with_suffix("")
    ydl_opts = {
        "format": "best[ext=mp4]/best",
        "outtmpl": str(out_stem) + ".%(ext)s",
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 60,
        # 网络抖动恢复：分片重试 + 断点续传 + 总重试
        "retries": 10,
        "fragment_retries": 10,
        "concurrent_fragment_downloads": 1,
        "continuedl": True,
        "extractor_args": {
            "youtube": {
                "player_client": ["tv_embedded", "web_creator", "android"],
            },
        },
        # YouTube 2026-05 起对所有视频流 URL 加 n challenge JS 加密
        # （SABR streaming experiment）。yt-dlp 需要显式开启 JS runtime 才能解。
        # Node ≥20.0.0 必装：sudo apt install -y nodejs (NodeSource setup_20.x)
        "js_runtimes": {"node": {}},
    }
    # 代理优先：阿里云新加坡 IP 被 YouTube 硬封，需要住宅代理。
    # 配置方式：编辑 config.py 设 YOUTUBE_PROXY_URL = "http://user:pass@host:port"
    proxy_url = ""
    try:
        from config import YOUTUBE_PROXY_URL as _proxy
        proxy_url = _proxy or ""
    except ImportError:
        pass

    if proxy_url:
        # IPRoyal sticky session 默认 lifetime-30m，跑批量时第 2-3 条就会过期 → 504。
        # 每次调用替换 session-XXX 为新的 random token，保证当前下载窗口内 IP 稳定。
        import re, uuid
        fresh_session = uuid.uuid4().hex[:10]
        proxy_url = re.sub(r"session-[a-zA-Z0-9]+", f"session-{fresh_session}", proxy_url)
        ydl_opts["proxy"] = proxy_url
    # YouTube 2026-05 起对无 cookie 请求统一要求"Sign in to confirm you're not a bot"
    # （即使来自住宅 IP）。代理 + cookies 组合是当前最稳的反反爬。
    cookies_path = Path(__file__).resolve().parent / "youtube_cookies.txt"
    if cookies_path.exists():
        ydl_opts["cookiefile"] = str(cookies_path)
    # 硬超时保护：yt-dlp 偶尔会在 SABR/n-challenge 路径上无限挂起（socket_timeout 不覆盖所有路径）。
    # 用 SIGALRM 强制超时，每个视频最多 15 分钟。
    import signal
    class _YdlTimeout(Exception): pass
    def _alarm_handler(signum, frame): raise _YdlTimeout()
    old_handler = signal.signal(signal.SIGALRM, _alarm_handler)
    signal.alarm(900)
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.extract_info(youtube_url, download=True)
        # 找下载下来的文件（任何视频扩展名）
        for f in out_stem.parent.iterdir():
            if f.stem == out_stem.name and f.is_file():
                if f.suffix in (".mp4", ".webm", ".mkv", ".mov", ".m4v"):
                    if f != out_path.with_suffix(f.suffix):
                        shutil.move(str(f), str(out_path.with_suffix(f.suffix)))
                    return True
        return False
    except _YdlTimeout:
        print(f"  ✗ yt-dlp 硬超时（>15min），跳过")
        return False
    except Exception as e:
        print(f"  ✗ yt-dlp 失败：{e}")
        return False
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)


def download_audio_rss(audio_url: str, out_path: Path) -> bool:
    """直接 GET，跟随 redirect。"""
    try:
        r = requests.get(audio_url, stream=True, timeout=120, allow_redirects=True,
                         headers={"User-Agent": "Castlingo-Pipeline/1.0"})
        if r.status_code != 200:
            print(f"  ✗ HTTP {r.status_code}")
            return False
        with out_path.open("wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
        return True
    except Exception as e:
        print(f"  ✗ download 失败：{e}")
        return False


def download_thumbnail(url: Optional[str], out_path: Path) -> bool:
    if not url:
        return False
    try:
        r = requests.get(url, timeout=30, allow_redirects=True)
        if r.status_code != 200:
            return False
        out_path.write_bytes(r.content)
        return True
    except Exception:
        return False


# =============================================================
# 处理一条候选：下载 + 上传 + 返回 master entry
# =============================================================

def process_candidate(c: dict, bucket) -> Optional[dict]:
    cid = candidate_id(c)
    print(f"\n→ 处理 {cid}")
    print(f"   {c['title'][:70]}")

    # 1) 下载到临时目录
    with tempfile.TemporaryDirectory() as tmp:
        tmpd = Path(tmp)
        # 视频源默认下成 mp4（含视频轨），RSS 源就是 mp3
        media_local = tmpd / "media.mp4" if c["media_type"] == "video" else tmpd / "media.mp3"
        thumb_local = tmpd / "thumbnail.jpg"

        if c["media_type"] == "video":
            ok = download_video_youtube(c["source_url"], media_local)
            # yt-dlp 实际写出的扩展名可能是 webm 等，找一下
            if ok and not media_local.exists():
                for f in tmpd.iterdir():
                    if f.stem == "media" and f.is_file():
                        media_local = f
                        break
        else:
            ok = download_audio_rss(c["source_url"], media_local)
        if not ok or not media_local.exists():
            return None

        size_mb = media_local.stat().st_size / 1024 / 1024
        print(f"   ✓ 媒体 {size_mb:.1f}MB ({media_local.suffix})")

        download_thumbnail(c.get("thumbnail"), thumb_local)

        # 2) 上传到 OSS
        ext = media_local.suffix.lstrip(".")
        content_type = {
            "mp4": "video/mp4",
            "m4v": "video/mp4",
            "mov": "video/quicktime",
            "webm": "video/webm",
            "mkv": "video/x-matroska",
            "m4a": "audio/mp4",
            "mp3": "audio/mpeg",
        }.get(ext, "application/octet-stream")
        # OSS key 命名仍叫 media（兼容音视频），向后兼容下原 audio_url 字段名
        media_oss_key = f"raw_podcasts/{cid}/media.{ext}"
        bucket.put_object(media_oss_key, media_local.read_bytes(),
                          headers={"Content-Type": content_type})
        media_oss_url = f"{OSS_CDN_DOMAIN}/{media_oss_key}"
        has_video = content_type.startswith("video/")
        print(f"   ☁️  {'video' if has_video else 'audio'}: {media_oss_url}")

        thumb_oss_url = None
        if thumb_local.exists():
            thumb_oss_key = f"raw_podcasts/{cid}/thumbnail.jpg"
            bucket.put_object(thumb_oss_key, thumb_local.read_bytes(),
                              headers={"Content-Type": "image/jpeg"})
            thumb_oss_url = f"{OSS_CDN_DOMAIN}/{thumb_oss_key}"
            print(f"   ☁️  thumb: {thumb_oss_url}")

        # 3) Whisper 转写 + 中文翻译，输出 transcript.json 上 OSS
        transcript_oss_url = None
        try:
            from transcribe import generate_transcript
            podcast_meta = {
                "title": c["title"],
                "speaker": c["speaker"],
                "topic": c.get("topic", ""),
                "event": c.get("event") or c["speaker"],
            }
            transcript_oss_url = generate_transcript(
                media_local, cid, bucket, podcast_meta=podcast_meta
            )
        except Exception as e:
            print(f"  ⚠️  transcript 失败（不影响主流程）：{e}")

        # 4) 预翻译所有单词，输出 words.json，让 App 端点词查询零延迟
        if transcript_oss_url:
            try:
                from pretranslate_words import pretranslate_for_podcast
                pretranslate_for_podcast(cid, bucket)
            except Exception as e:
                print(f"  ⚠️  pretranslate_words 失败（不影响主流程）：{e}")

    return candidate_to_master_entry(c, media_oss_url, thumb_oss_url, has_video, transcript_oss_url)


# =============================================================
# 主入口：candidates → 增量入库
# =============================================================

def process_candidates(candidates: list[dict], top_n: int = 3) -> list[dict]:
    """处理 top N 新候选（已在 master 的跳过）。"""
    bucket = get_bucket()
    master = load_master(bucket)
    existing_ids = {m["id"] for m in master}

    new_entries: list[dict] = []
    processed = 0
    for c in candidates:
        if processed >= top_n:
            break
        cid = candidate_id(c)
        if cid in existing_ids:
            continue
        entry = process_candidate(c, bucket)
        if entry:
            master.insert(0, entry)
            existing_ids.add(cid)
            new_entries.append(entry)
            processed += 1

    if processed > 0:
        save_master(master, bucket)
        # Push first — only after master is saved on OSS, otherwise users
        # tapping the deep link race ahead of an empty master list.
        notify_users(new_entries)
    print(f"\n✅ 本次新增 {processed} 条，master 总计 {len(master)} 条")
    return master


PUSH_HISTORY_FILE = Path(__file__).resolve().parent / "last_pushed_topics.json"
PUSH_TOPIC_COOLDOWN_DAYS = 3  # 同一 topic 前缀近 N 天推过则降权


def _load_push_history() -> list[dict]:
    """Read recent push log: list of {topic, pushed_at_iso}."""
    if not PUSH_HISTORY_FILE.exists():
        return []
    try:
        with open(PUSH_HISTORY_FILE, "r") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, OSError):
        return []


def _save_push_history(entries: list[dict]) -> None:
    tmp = PUSH_HISTORY_FILE.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(entries, f, ensure_ascii=False, indent=2)
    tmp.replace(PUSH_HISTORY_FILE)


def _topic_prefix(entry: dict) -> str:
    """Extract '娱乐' from '娱乐 · 名人访谈'."""
    t = (entry.get("topic") or "").strip()
    return t.split("·")[0].strip() if t else ""


def notify_users(new_entries: list[dict]) -> None:
    """
    Queue exactly ONE notification per pipeline run — the highest-ranked new
    raw podcast — for the next 07:50 flush. The other top_n entries still get
    downloaded and listed in the app, they just don't ring everyone's phone.

    Topic-rotation: any topic that was already pushed within the last
    `PUSH_TOPIC_COOLDOWN_DAYS` days gets a -50 penalty for tonight's selection,
    so the user doesn't see "娱乐...娱乐...娱乐" three days in a row.
    Best-effort; never raises.
    """
    if not new_entries:
        return
    try:
        from enqueue_push import enqueue_raw_podcast
    except ImportError as e:
        print(f"  ⚠️ enqueue module missing — skipping notifications: {e}")
        return

    # Build the set of "recently pushed" topic prefixes
    history = _load_push_history()
    cutoff = datetime.now(timezone.utc) - timedelta(days=PUSH_TOPIC_COOLDOWN_DAYS)
    recent_topics: set[str] = set()
    for h in history:
        try:
            ts = datetime.fromisoformat(h["pushed_at"])
            if ts.tzinfo is None:
                ts = ts.replace(tzinfo=timezone.utc)
            if ts >= cutoff and h.get("topic"):
                recent_topics.add(h["topic"])
        except (KeyError, ValueError):
            continue

    def adjusted_score(e: dict) -> int:
        s = e.get("_score", 0)
        if _topic_prefix(e) in recent_topics:
            s -= 50
        return s

    # Pick the most popular new entry. `_score` is computed upstream from view
    # count + recency + signal-source weighting; `_view_count` is the tiebreaker
    # for the rare case scores collide. Cooldown penalty rotates topics.
    top = max(
        new_entries,
        key=lambda e: (adjusted_score(e), e.get("_view_count", 0)),
    )
    top_topic = _topic_prefix(top)
    print(
        f"  📣 picked top of {len(new_entries)}: {top['id']} "
        f"(score={top.get('_score')}→{adjusted_score(top)}, topic={top_topic!r}, "
        f"views={top.get('_view_count')}, cooled_topics={sorted(recent_topics)})"
    )
    try:
        enqueue_raw_podcast(
            podcast_id=top["id"],
            title=top.get("title", ""),
            speaker=top.get("speaker", ""),
        )
        # Record this push so the next 3 days won't rotate back to the same topic.
        history.append({
            "topic": top_topic,
            "podcast_id": top["id"],
            "pushed_at": datetime.now(timezone.utc).isoformat(),
        })
        # Keep only entries within cooldown window + a safety margin
        keep_cutoff = datetime.now(timezone.utc) - timedelta(days=PUSH_TOPIC_COOLDOWN_DAYS + 4)
        kept = []
        for h in history:
            try:
                ts = datetime.fromisoformat(h["pushed_at"])
                if ts.tzinfo is None:
                    ts = ts.replace(tzinfo=timezone.utc)
                if ts >= keep_cutoff:
                    kept.append(h)
            except (KeyError, ValueError):
                continue
        _save_push_history(kept)
    except Exception as e:  # noqa: BLE001 — logging only
        print(f"  ⚠️ enqueue failed for {top.get('id')}: {e}")


if __name__ == "__main__":
    # 用法：python3 raw_podcast_processor.py [top_n]
    candidates_path = OUTPUT_DIR / "raw_candidates.json"
    if not candidates_path.exists():
        print(f"❌ 先跑 raw_podcast_pipeline.py --json 生成 {candidates_path.name}")
        sys.exit(1)
    candidates = json.loads(candidates_path.read_text())
    top_n = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    process_candidates(candidates, top_n=top_n)
