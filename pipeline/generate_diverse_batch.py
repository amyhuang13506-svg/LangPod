"""
一次性脚本：跨 6 个 ExploreCategory 批量生成 raw_podcast，确保每个分类都有内容。

用法：
    python3 generate_diverse_batch.py [--count 10] [--per-category 2]

策略：
1. 扫描全部频道 → score → 按 ExploreCategory 分桶
2. 每桶取 top {per-category}，凑齐 count
3. 已在 OSS master 的跳过
4. 跑完整 pipeline（下载 → 上传 → 转写 → 词典）
"""
import argparse
import json
import sys

from raw_podcast_pipeline import collect_candidates


# 与 iOS RawPodcast.exploreCategory 完全一致的映射
def explore_category(topic: str) -> str | None:
    if any(k in topic for k in ["娱乐", "时尚", "文化"]):
        return "entertainment"
    if any(k in topic for k in ["两性", "心理", "关系"]):
        return "relationship"
    if any(k in topic for k in ["科学", "数学", "科普"]):
        return "science"
    if any(k in topic for k in ["创业", "商业", "投资"]):
        return "business"
    if "评测" in topic:
        return "tech"
    if any(k in topic for k in ["思想", "演讲", "学术", "访谈", "健康"]):
        return "mind"
    return None


CATEGORY_ORDER = ["entertainment", "relationship", "mind", "science", "business", "tech"]


def existing_master_ids() -> set:
    try:
        from raw_podcast_processor import get_bucket, OSS_MASTER_KEY
        bucket = get_bucket()
        data = bucket.get_object(OSS_MASTER_KEY).read()
        master = json.loads(data)
        items = master if isinstance(master, list) else master.get("items", [])
        return {it.get("id") for it in items if it.get("id")}
    except Exception as e:
        print(f"  ⚠️  master 加载失败：{e}（视为空）")
        return set()


def candidate_full_id(c: dict) -> str:
    prefix = "raw-yt" if c.get("media_type") == "video" else "raw-rss"
    return f"{prefix}-{c['source_id']}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=10, help="目标总条数")
    ap.add_argument("--per-category", type=int, default=2, help="每个分类最多取几条")
    ap.add_argument("--yt-days", type=int, default=14, help="扫描多少天内的视频")
    args = ap.parse_args()

    print(f"\n=== 跨分类批量生成 · 目标 {args.count} 条 · 每分类最多 {args.per_category} 条 ===\n")

    # 1. 扫描候选池（拉大 top_n，扩天数）
    candidates = collect_candidates(yt_days=args.yt_days, rss_days=14, top_n=300)

    # 2. 已 master 的跳过
    skip_ids = existing_master_ids()
    print(f"\n  📥 现有 master：{len(skip_ids)} 条；候选池：{len(candidates)} 条")

    # 3. 按 ExploreCategory 分桶
    buckets: dict[str, list] = {c: [] for c in CATEGORY_ORDER}
    uncategorized = []
    for cand in candidates:
        if candidate_full_id(cand) in skip_ids:
            continue
        cat = explore_category(cand.get("topic", ""))
        if cat:
            buckets[cat].append(cand)
        else:
            uncategorized.append(cand)

    # 每桶按 score 排序
    for cat in CATEGORY_ORDER:
        buckets[cat].sort(key=lambda x: x["score"], reverse=True)

    print(f"\n  📦 分桶结果：")
    for cat in CATEGORY_ORDER:
        print(f"     [{cat}] {len(buckets[cat])} 条")
    print(f"     [uncategorized] {len(uncategorized)} 条")

    # 4. 选取：每桶 top per-category
    selected: list = []
    for cat in CATEGORY_ORDER:
        for c in buckets[cat][:args.per_category]:
            selected.append(c)

    # 5. 不足 count 时，从未选中的高分候选里补（不限分类）
    selected_keys = {candidate_full_id(s) for s in selected}
    if len(selected) < args.count:
        remaining = [
            c for c in candidates
            if candidate_full_id(c) not in skip_ids
            and candidate_full_id(c) not in selected_keys
        ]
        remaining.sort(key=lambda x: x["score"], reverse=True)
        while len(selected) < args.count and remaining:
            selected.append(remaining.pop(0))

    # 6. 截断到 count
    selected = selected[:args.count]

    if not selected:
        print("\n  ⚠️  没有可处理的新候选，退出")
        sys.exit(0)

    print(f"\n=== 最终选中 {len(selected)} 条 ===\n")
    for i, c in enumerate(selected, 1):
        cat = explore_category(c.get("topic", "")) or "?"
        title = c.get("title", "")[:60]
        spk = c.get("speaker", "")[:25]
        score = c.get("score", 0)
        print(f"  {i:2}. [{cat:>13}] [{spk}] score={score} · {title}")

    print(f"\n=== 进入 process_candidates（总耗时 ≈ {len(selected) * 8} min）===\n")

    from raw_podcast_processor import process_candidates
    process_candidates(selected, top_n=len(selected))

    print(f"\n✅ 批量完成")


if __name__ == "__main__":
    main()
