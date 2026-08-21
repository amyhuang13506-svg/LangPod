"""
存量每日播客听力测验回填：三个级别 index.json 里的所有集补 quiz.json。
已有的跳过（幂等，可中断重跑）。让听力测试页的"往期成绩单"有历史供给。

用法：
  python3 backfill_episode_quiz.py             # 全量（三级）
  python3 backfill_episode_quiz.py --limit 5   # 试跑
"""
from __future__ import annotations

import argparse
import json
import time

from upload_oss import get_bucket
from generate_episode_quiz import generate_quiz_for_episode

LEVELS = ["easy", "medium", "hard"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="最多新生成多少条（0=全量）")
    args = ap.parse_args()

    bucket = get_bucket()
    done = skipped = failed = 0

    for level in LEVELS:
        try:
            idx = json.loads(bucket.get_object(f"episodes/{level}/index.json").read())
        except Exception as e:
            print(f"✗ 拉 {level} index 失败：{e}")
            continue
        eps = idx.get("episodes") if isinstance(idx, dict) else idx
        print(f"\n== {level}: {len(eps)} 集 ==")
        for ep in eps:
            if args.limit and (done + failed) >= args.limit:
                break
            ep_id = ep["id"]
            if bucket.object_exists(f"episodes/{level}/{ep_id}/quiz.json"):
                skipped += 1
                continue
            try:
                if generate_quiz_for_episode(level, ep_id, bucket):
                    done += 1
                else:
                    failed += 1
            except Exception as e:
                failed += 1
                print(f"  ✗ {ep_id}: {e}")
            time.sleep(1)
            if (done + failed) % 25 == 0 and (done + failed) > 0:
                print(f"—— 进度：新生成 {done}，失败 {failed}，跳过 {skipped}")

    print(f"\n完成：新生成 {done}，失败 {failed}，已有跳过 {skipped}")


if __name__ == "__main__":
    main()
