# -*- coding: utf-8 -*-
"""
一次性：把指定课堂的 is_free 置 true 并重传（只改 OSS 上的 JSON 字段，不重新生成内容）。

vocab_v2 免费策略（docs/vocab_v2_双区块_方案.md 第 5 节）：
  生活场景免费 3 课（仅美国版）：bank_account（原有）+ coffee_order + supermarket
  主题课 3 门免费由 theme_catalog.FREE_THEME_SLUGS 在生成时标记，不走本脚本。

用法:
  python3 set_free_lessons.py            # 应用默认 TARGETS
  python3 set_free_lessons.py --dry-run  # 只看不改
"""

import argparse
import json

from upload_lessons import get_bucket, rebuild_country_index

# (country, lesson_id, is_free)
# 注意含 False 项：OSS 上有历史遗留的 is_free=true（旧 App「第一国第一课」逻辑下
# 不生效，新 App 直接信任 is_free，必须清掉），精确对齐方案的免费 3 课。
TARGETS = [
    ("us", "lesson_us_bank_account", True),
    ("us", "lesson_us_coffee_order", True),
    ("us", "lesson_us_supermarket", True),
    ("us", "lesson_us_campus", False),
    ("us", "lesson_us_customs", False),
    ("us", "lesson_us_otc_meds", False),
]

# 场景免费课仅美国版：这些国家的 is_free 全部清零（历史遗留标记）
CLEAR_COUNTRIES = ["uk", "au", "ca", "nz", "sg"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    bucket = get_bucket()
    touched = set()

    targets = list(TARGETS)
    for cc in CLEAR_COUNTRIES:
        try:
            idx = json.loads(bucket.get_object("lessons/%s/index.json" % cc).read())
        except Exception as e:
            print("⚠️ index %s: %s" % (cc, e))
            continue
        for l in idx["lessons"]:
            if l.get("is_free"):
                targets.append((cc, l["id"], False))

    for country, lesson_id, is_free in targets:
        key = "lessons/%s/%s/lesson.json" % (country, lesson_id)
        try:
            lesson = json.loads(bucket.get_object(key).read())
        except Exception as e:
            print("❌ %s: %s" % (key, e))
            continue
        if lesson.get("is_free") == is_free:
            print("⏭  %s already is_free=%s" % (lesson_id, is_free))
            continue
        print("%s %s: is_free %s → %s" % ("🔍" if args.dry_run else "✏️ ",
                                          lesson_id, lesson.get("is_free"), is_free))
        if args.dry_run:
            continue
        lesson["is_free"] = is_free
        bucket.put_object(key, json.dumps(lesson, ensure_ascii=False, indent=2).encode("utf-8"))
        touched.add(country)

    for cc in sorted(touched):
        rebuild_country_index(bucket, cc)
    print("done")


if __name__ == "__main__":
    main()
