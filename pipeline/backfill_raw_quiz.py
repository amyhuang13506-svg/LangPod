"""
存量原声理解题回填：给 master 里所有有 transcript 的条目补 quiz.json。
已有 quiz.json 的跳过（幂等，可中断重跑）。

2026-08-18 决策：理解题从「仅新内容」升级为「所有结算卡标配」（用户要求），
故回填全部存量。

用法：
  python3 backfill_raw_quiz.py            # 全量
  python3 backfill_raw_quiz.py --limit 5  # 试跑前 5 条
"""
from __future__ import annotations

import argparse
import time

from raw_podcast_processor import get_bucket, load_master
from generate_raw_quiz import generate_quiz_for_podcast


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="最多处理多少条（0=全量）")
    args = ap.parse_args()

    bucket = get_bucket()
    master = load_master(bucket)
    targets = [m for m in master if m.get("transcript_url")]
    print(f"master {len(master)} 条，其中有 transcript 的 {len(targets)} 条")

    done = skipped = failed = 0
    for i, m in enumerate(targets):
        if args.limit and done + failed >= args.limit:
            break
        pid = m["id"]
        if bucket.object_exists(f"raw_podcasts/{pid}/quiz.json"):
            skipped += 1
            continue
        try:
            url = generate_quiz_for_podcast(pid, bucket)
            if url:
                done += 1
            else:
                failed += 1
        except Exception as e:
            failed += 1
            print(f"  ✗ {pid}: {e}")
        time.sleep(1)   # 轻微限速，避免打满 GPT 代理
        if (done + failed) % 20 == 0 and (done + failed) > 0:
            print(f"—— 进度 {i+1}/{len(targets)}：新生成 {done}，失败 {failed}，已有跳过 {skipped}")

    print(f"\n完成：新生成 {done}，失败 {failed}，已有跳过 {skipped}")


if __name__ == "__main__":
    main()
