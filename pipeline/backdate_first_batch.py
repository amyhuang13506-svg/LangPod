# -*- coding: utf-8 -*-
"""
一次性：把首批 12 门主题课的 date 回拨一天，让免费闸门选对课。

背景：App 端免费闸门是「每个分类里 date 最早的 2 课免费」（LessonStore.computeFreeIds），
靠 date 表达「先有的课先免费，新课永不挤掉老课」。但首批 12 课和 B1 的 18 课是同一天
灌进去的，date 全等 → 排序退化到 id 字母序兜底 → 食物分类免费的成了「乳制品」和
「烹饪动作」，最该当免费橱窗的「水果」反而锁着。

首批 12 课本来就是先创作的，把它们的 date 回拨到前一天，闸门即按设计工作：
  食物→水果/蔬菜  家居→厨房/随身物品  身体→身体部位/脸与五官
  穿着→衣物/鞋帽配饰  出行→交通工具/街道设施  基础→数字与时间/颜色与形状

以后每批内容各自落在不同日期，date 天然有序，不需要再回拨。

用法:
  python3 backdate_first_batch.py --dry-run
  python3 backdate_first_batch.py
"""

import argparse
import glob
import json
import os

from upload_lessons import get_bucket, rebuild_country_index

LESSONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output", "lessons", "daily")

# 首批 12 课（B1 之前就存在的），按大类分组 —— 正好是每类最该免费的那两门
FIRST_BATCH = [
    "lesson_daily_fruits", "lesson_daily_vegetables",          # 食物
    "lesson_daily_kitchen", "lesson_daily_everyday_items",     # 家居
    "lesson_daily_body_parts", "lesson_daily_face",            # 身体与健康
    "lesson_daily_clothes", "lesson_daily_accessories",        # 穿着
    "lesson_daily_vehicles", "lesson_daily_street",            # 出行与城市
    "lesson_daily_numbers_time", "lesson_daily_colors_shapes", # 基础概念
]
BACKDATED = "2026-07-16"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    bucket = get_bucket()
    touched = False

    for lesson_id in FIRST_BATCH:
        # 本地
        p = os.path.join(LESSONS_DIR, lesson_id, "lesson.json")
        if os.path.exists(p):
            l = json.load(open(p, encoding="utf-8"))
            if l.get("date") != BACKDATED:
                print("%s local %-22s date %s → %s" % (
                    "🔍" if args.dry_run else "✏️ ",
                    lesson_id.replace("lesson_daily_", ""), l.get("date"), BACKDATED))
                if not args.dry_run:
                    l["date"] = BACKDATED
                    json.dump(l, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        # OSS
        key = "lessons/daily/%s/lesson.json" % lesson_id
        try:
            live = json.loads(bucket.get_object(key).read())
        except Exception as e:
            print("⚠️  %s: %s" % (key, e))
            continue
        if live.get("date") == BACKDATED:
            continue
        print("%s oss   %-22s date %s → %s" % (
            "🔍" if args.dry_run else "☁️ ",
            lesson_id.replace("lesson_daily_", ""), live.get("date"), BACKDATED))
        if not args.dry_run:
            live["date"] = BACKDATED
            bucket.put_object(key, json.dumps(live, ensure_ascii=False, indent=2).encode("utf-8"))
            touched = True

    if touched:
        rebuild_country_index(bucket, "daily")
        # 免费闸门是客户端按 date 派生的，这里回读 index 复算一遍做验收
        idx = json.loads(bucket.get_object("lessons/daily/index.json").read())
        from collections import defaultdict
        g = defaultdict(list)
        for l in idx["lessons"]:
            if not l.get("is_daily"):
                g[l["category"]].append(l)
        print("\n免费课（App 端按 date 最早 2 课派生）:")
        for cat, items in g.items():
            ranked = sorted(items, key=lambda x: (x["date"], x["id"]))[:2]
            print("  %-10s %s" % (cat, "、".join(i["title_zh"] for i in ranked)))
    elif args.dry_run:
        print("\n(dry-run，未改动)")


if __name__ == "__main__":
    main()
