# -*- coding: utf-8 -*-
"""
一次性：把已生成的主题课对齐 theme_catalog 的 8 大类定稿。

背景：日常词汇初版是 6 大类（body/basics/home/grocery/clothing/outdoor），
扩容方案收敛为 8 大类，outdoor 退役 → 交通工具/街道设施并入 transport（出行与城市），
另有几个大类改中文名。同时按「每大类一门免费」重设 is_free。

只改 lesson.json 的 category / category_zh / is_free 字段，**不重新生成内容**。
本地和 OSS 都改，然后重建 index。

用法:
  python3 remap_theme_categories.py --dry-run
  python3 remap_theme_categories.py
"""

import argparse
import glob
import json
import os

from theme_catalog import FREE_THEME_SLUGS, THEME_CATEGORIES, all_theme_lessons
from upload_lessons import get_bucket, rebuild_country_index

LESSONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output", "lessons", "daily")


def desired_state():
    """catalog 定稿 → {lesson_id: (category, category_zh, is_free)}"""
    out = {}
    for l in all_theme_lessons():
        out[l["id"]] = (l["category"], l["category_zh"], l["is_free"])
    return out


def patch(lesson, want):
    """返回改动描述列表（空 = 无需改）。原地修改 lesson。"""
    cat, cat_zh, is_free = want
    changes = []
    if lesson.get("category") != cat:
        changes.append("category %s→%s" % (lesson.get("category"), cat))
        lesson["category"] = cat
    if lesson.get("category_zh") != cat_zh:
        changes.append("category_zh %s→%s" % (lesson.get("category_zh"), cat_zh))
        lesson["category_zh"] = cat_zh
    if lesson.get("is_free") != is_free:
        changes.append("is_free %s→%s" % (lesson.get("is_free"), is_free))
        lesson["is_free"] = is_free
    return changes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    want_all = desired_state()
    bucket = get_bucket()
    touched = False

    # 1. 本地 lesson.json
    for p in sorted(glob.glob(os.path.join(LESSONS_DIR, "lesson_*", "lesson.json"))):
        lesson = json.load(open(p, encoding="utf-8"))
        want = want_all.get(lesson["id"])
        if not want:
            print("⚠️  %s 不在 catalog 里，跳过" % lesson["id"])
            continue
        changes = patch(lesson, want)
        if not changes:
            continue
        print("%s local %-28s %s" % ("🔍" if args.dry_run else "✏️ ",
                                     lesson["id"].replace("lesson_daily_", ""), "; ".join(changes)))
        if not args.dry_run:
            json.dump(lesson, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    # 2. OSS lesson.json（线上以 OSS 为准，本地可能缺课）
    for key_id, want in sorted(want_all.items()):
        key = "lessons/daily/%s/lesson.json" % key_id
        try:
            lesson = json.loads(bucket.get_object(key).read())
        except Exception:
            continue  # 未上线的课（catalog 里有、OSS 上没有）
        changes = patch(lesson, want)
        if not changes:
            continue
        print("%s oss   %-28s %s" % ("🔍" if args.dry_run else "☁️ ",
                                     key_id.replace("lesson_daily_", ""), "; ".join(changes)))
        if not args.dry_run:
            bucket.put_object(key, json.dumps(lesson, ensure_ascii=False, indent=2).encode("utf-8"))
            touched = True

    if touched:
        rebuild_country_index(bucket, "daily")

    if args.dry_run:
        print("\n(dry-run，未改动)")
    else:
        print("\n✅ 完成。8 大类:", " / ".join(
            "%s%s" % (m["icon_emoji"], m["zh"]) for m in THEME_CATEGORIES.values()))
        print("   免费课:", ", ".join(sorted(FREE_THEME_SLUGS)))


if __name__ == "__main__":
    main()
