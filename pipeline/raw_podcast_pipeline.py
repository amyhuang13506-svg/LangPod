"""
Pipeline A — 硅谷原声 采集主入口（MVP 版本）

目前流程：
  1. YouTube 频道列表 → 拉近 7 天新视频
  2. RSS feed 列表 → 拉近 14 天新播客集
  3. 合并 + 打分 + 排序，输出每天 top N 候选清单
  4. （下一阶段）yt-dlp 下载 → 上传 OSS → 写 raw_podcasts.json

本文件只跑前 3 步（采集 + 排序）。下载和上传放到 raw_podcast_processor.py。

用法：
  python3 raw_podcast_pipeline.py            # 跑一次，打印 top 候选
  python3 raw_podcast_pipeline.py --json     # 输出 JSON 到 output/raw_candidates.json
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from raw_podcast_sources import (
    YOUTUBE_CHANNELS, RSS_FEEDS,
    TIER_BONUS, KIND_BONUS, TOPIC_BONUS, STAR_KEYWORDS,
)
from youtube_monitor import scan_channels
from rss_monitor import scan_feeds

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
OUTPUT_DIR.mkdir(exist_ok=True)


def score_item(item: dict) -> int:
    """打分：综合 tier + 长度 + 时新度 + 浏览量 + 点赞数。
    重点：偏好近 7 天 + 高点赞 + 30-90min 内容。"""
    from datetime import datetime, timezone, timedelta

    score = 0
    score += TIER_BONUS.get(item.get("source_tier", 3), 0)
    score += KIND_BONUS.get(item.get("source_kind", "news"), 0)

    # Topic 加权 —— "娱乐 · 名人访谈" 这类带前缀的 topic，按前缀（"娱乐"）查表。
    # 让娱乐/两性/心理/美食/旅游能盖过 company(20)，AI/商业相对降权。
    topic = (item.get("source_topic") or "").strip()
    topic_prefix = topic.split("·")[0].strip() if topic else ""
    if topic_prefix:
        score += TOPIC_BONUS.get(topic_prefix, 0)

    # ⭐ 明星关键词加分 —— 标题或描述命中 STAR_KEYWORDS 时大幅加分，让华人
    # 观众熟悉的脸（Taylor Swift / Ali Wong / BTS / Zendaya 等）优先冒头。
    # 单个候选最多累加 50 分，避免标题硬塞多个名字打爆分数榜。
    # 关键：用 regex word-boundary 匹配，避免 "iu" 误中 "studio"、"rose"
    # 误中 "verbose" 这种子串噪声。
    import re as _re
    haystack = ((item.get("title") or "") + " " + (item.get("description") or ""))[:500].lower()
    star_score = 0
    matched_stars: list[str] = []
    for kw, bonus in STAR_KEYWORDS.items():
        # \b 词边界：英文 word boundary 在 ASCII 字母数字字符两侧。
        # 对含特殊字符（é、空格、句点）的关键词需要稍灵活：先用 \b 包裹
        # 再 escape 内部内容。
        pattern = r"\b" + _re.escape(kw) + r"\b"
        if _re.search(pattern, haystack):
            star_score += bonus
            matched_stars.append(kw)
            if star_score >= 50:
                break
    if star_score > 0:
        score += min(star_score, 50)
        # 印日志方便观察哪些名人在出现
        print(f"      ⭐ star match: {matched_stars} (+{min(star_score,50)}) — {(item.get('title') or '')[:60]}")

    dur = item.get("duration_seconds", 0)
    if dur > 0 and dur < 120:                     # < 2min — short / 广告
        score -= 50
    elif dur < 300:                                # < 5min — promo
        score -= 25
    elif dur < 600:                                # 5-10min — 短分析，可接受
        score -= 5
    elif 600 <= dur <= 1800:                       # 10-30min — 标准
        score += 8
    elif 1800 < dur <= 3600:                       # 30-60min — 主播客时长
        score += 18
    elif 3600 < dur <= 7200:                       # 1-2hr — keynote / 深度访谈
        score += 22
    elif 7200 < dur <= 10800:                      # 2-3hr — 长访谈
        score += 8
    else:
        score += 0

    # 标题关键词过滤
    title_lower = (item.get("title") or "").lower()
    desc_lower = (item.get("description") or "").lower()
    if "#shorts" in title_lower or "#shorts" in desc_lower:
        score -= 80
    if "doodle" in title_lower:
        score -= 40

    # 硬性广告/促销过滤（标题级 — 高置信度）
    # 标题里直接说"赞助/广告/促销码/折扣/抽奖"的整集，全部踢出候选池
    ad_title_signals = [
        "sponsored", "#sponsored", "[ad]", "(ad)", "#ad",
        " ad:", "advertisement",
        "promo code", "use code", "discount code", "coupon code",
        "% off", "deal alert", "limited offer", "limited time",
        "giveaway", "unboxing", "official trailer",
    ]
    if any(sig in title_lower for sig in ad_title_signals):
        return -999  # sentinel: collect_candidates 会过滤掉

    # 政治内容硬过滤 —— 用户偏好纯娱乐 / 知识 / 关系内容，不要政治
    # （特朗普 / 拜登 / 选举 / 国会等关键词直接踢出，即使来自信任频道也不要）
    political_signals = [
        "trump", "biden", "obama", "kamala", "harris", "vance",
        "election", "senate", "congress", "republican", "democrat",
        "political", "politics", "white house", "capitol",
        "putin", "zelensky", "netanyahu",
        "maga", "gop", "dnc", "rnc", "impeach",
    ]
    if any(sig in title_lower for sig in political_signals):
        return -999
    # 描述前 200 字硬指标（整集就是广告 / 付费推广）
    desc_head = desc_lower[:200]
    ad_desc_signals = [
        "this video is sponsored",
        "this episode is sponsored",
        "this is a paid promotion",
        "this is a paid partnership",
        "paid promotion by",
        "in paid partnership with",
    ]
    if any(sig in desc_head for sig in ad_desc_signals):
        return -999

    keynote_keywords = ["keynote", "announces", "introducing", "demo", "interview",
                        "podcast", "presentation", "earnings"]
    for kw in keynote_keywords:
        if kw in title_lower:
            score += 6
            break

    # 偏好：两性 / 娱乐 / 明星访谈 / 大众传播性内容
    entertainment_keywords = [
        # 明星访谈格式
        "interview with", "sits down with", "tells", "opens up",
        "73 questions", "hot ones", "first we feast",
        "diary of", "joe rogan", "fallon", "kimmel",
        # 两性 / 关系
        "relationship", "dating", "love", "couple",
        "marriage", "breakup", "ex-", "boyfriend", "girlfriend",
        "single", "soulmate", "chemistry",
        # 娱乐 / 流行文化
        "celebrity", "actress", "actor", "singer", "model",
        "drama", "gossip", "viral", "trending", "scandal",
        "secrets", "confessions", "behind the scenes",
        "first time", "the truth about", "what really happened",
        "reaction", "react to",
        # 心理 / 通俗成长
        "psychology of", "why we", "self-improvement",
        "mindset", "habits", "anxiety", "confidence",
    ]
    for kw in entertainment_keywords:
        if kw in title_lower:
            score += 15
            break

    # 时新度：近 3 天 / 7 天大幅加权（用户要「近一周最热」）
    pub_str = (item.get("published_at") or "")[:19]
    if pub_str:
        try:
            pub = datetime.fromisoformat(pub_str.replace("Z", "+00:00"))
            now = datetime.now(timezone.utc)
            days_old = (now - pub).total_seconds() / 86400
            if days_old <= 1:
                score += 20
            elif days_old <= 3:
                score += 14
            elif days_old <= 7:
                score += 8
            elif days_old <= 14:
                score += 2
            elif days_old > 30:
                score -= 6   # 老内容降权
        except Exception:
            pass

    # 浏览量
    views = item.get("view_count", 0)
    if views > 5_000_000:
        score += 28
    elif views > 1_000_000:
        score += 20
    elif views > 100_000:
        score += 12
    elif views > 10_000:
        score += 5
    elif views > 1000:
        score += 1

    # 点赞（互动信号，YouTube 热门 = 高赞）
    likes = item.get("like_count", 0)
    if likes > 100_000:
        score += 18
    elif likes > 10_000:
        score += 10
    elif likes > 1000:
        score += 4

    return score


def normalize_item(item: dict, kind_hint: str) -> dict:
    """统一两种源（YouTube / RSS）的字段格式，给后续 processor 用。"""
    is_yt = "video_id" in item
    return {
        "media_type":   "video" if is_yt else "audio",
        "source_id":    item.get("video_id") or item.get("guid"),
        "source_url":   (
            f"https://youtube.com/watch?v={item['video_id']}"
            if is_yt else item.get("audio_url")
        ),
        "title":        item.get("title", ""),
        "speaker":      item.get("source_label") or item.get("channel_title", ""),
        "event":        item.get("source_label") or item.get("feed_title", ""),
        "published_at": (item.get("published_at") or "")[:10],
        "duration_seconds": item.get("duration_seconds", 0),
        "topic":        item.get("source_topic", ""),
        "category":     item.get("source_category", "tech_keynote"),
        "thumbnail":    item.get("thumbnail"),
        "description":  item.get("description", ""),
        "score":        score_item(item),
        "kind":         kind_hint,
        "view_count":   item.get("view_count", 0),
        "like_count":   item.get("like_count", 0),
    }


def collect_candidates(yt_days: int = 7, rss_days: int = 14, top_n: int = 30) -> list[dict]:
    """采集 + 打分 + 排序，返回 top N 候选。"""
    print(f"=== Pipeline A 启动 · {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")
    print(f"[1/2] YouTube 监听 ({len(YOUTUBE_CHANNELS)} 个频道，过去 {yt_days} 天)…")
    yt_videos = scan_channels(YOUTUBE_CHANNELS, days_back=yt_days, max_per_channel=5)
    yt_normalized = [normalize_item(v, "video") for v in yt_videos]
    print(f"  → {len(yt_normalized)} 条 YouTube 视频\n")

    print(f"[2/2] RSS 监听 ({len(RSS_FEEDS)} 个 feed，过去 {rss_days} 天)…")
    rss_eps = scan_feeds(RSS_FEEDS, days_back=rss_days, max_per_feed=5)
    rss_normalized = [normalize_item(e, "audio") for e in rss_eps]
    print(f"  → {len(rss_normalized)} 条 RSS 播客集\n")

    all_items = yt_normalized + rss_normalized
    rejected = [x for x in all_items if x["score"] <= -999]
    all_items = [x for x in all_items if x["score"] > -999]
    if rejected:
        print(f"  ⛔  过滤 {len(rejected)} 条广告/促销内容")
        for r in rejected[:5]:
            print(f"      · {r.get('title','')[:60]}")
    all_items.sort(key=lambda x: x["score"], reverse=True)
    return all_items[:top_n]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="输出 JSON 到 output/raw_candidates.json")
    parser.add_argument("--top", type=int, default=30, help="采集时返回 top N 候选")
    parser.add_argument("--yt-days", type=int, default=7)
    parser.add_argument("--rss-days", type=int, default=14)
    parser.add_argument("--process", type=int, default=0,
                        help="采集后立即处理 top N 个新候选（下载 + 上传 OSS）。0 = 只采集不处理")
    parser.add_argument("--all", type=int, default=0,
                        help="一键模式：采集 + 处理 N 条新增 + 写入 master 上传 OSS")
    args = parser.parse_args()

    process_n = args.all or args.process

    candidates = collect_candidates(
        yt_days=args.yt_days,
        rss_days=args.rss_days,
        top_n=args.top,
    )

    out_path = OUTPUT_DIR / "raw_candidates.json"
    out_path.write_text(json.dumps(candidates, ensure_ascii=False, indent=2))
    if args.json or process_n > 0:
        print(f"\n→ JSON 写入 {out_path}")

    if process_n > 0:
        from raw_podcast_processor import process_candidates
        print(f"\n=== 处理阶段：top {process_n} 个新候选 ===\n")
        process_candidates(candidates, top_n=process_n)
        return

    print(f"\n=== Top {len(candidates)} 候选 ===\n")
    for i, c in enumerate(candidates, 1):
        sec = c["duration_seconds"]
        h, m = sec // 3600, (sec % 3600) // 60
        dur_str = f"{h}h{m}m" if h else f"{m}min"
        media_icon = "📹" if c["media_type"] == "video" else "🎙️"
        print(f"{i:>3}. {media_icon} [{c['speaker']}] {c['title'][:58]}")
        print(f"      score={c['score']} · {dur_str} · {c['published_at']}")
        print(f"      {c['source_url'][:80]}")
        print()


if __name__ == "__main__":
    main()
