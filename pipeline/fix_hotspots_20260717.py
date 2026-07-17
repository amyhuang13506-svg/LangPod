# -*- coding: utf-8 -*-
"""一次性：2026-07-17 全量人工核验后的点位修正（5 处）。
运行后需重跑 upload_lessons.py --lesson <id> 重传对应课。"""

import json
import os

# (lesson_id, zone_id, word, x, y) — 归一化坐标，人工从核验图定的
FIXES = [
    ("lesson_daily_accessories",  "accessories",   "necktie",     0.625, 0.58),
    ("lesson_daily_face",         "face_features", "lip",         0.255, 0.72),
    ("lesson_daily_kitchen",      "cooking_area",  "kettle",      0.475, 0.62),
    ("lesson_daily_kitchen",      "sink_prep",     "sponge",      0.290, 0.85),
    ("lesson_daily_numbers_time", "telling_time",  "minute hand", 0.270, 0.27),
    ("lesson_daily_numbers_time", "telling_time",  "hour hand",   0.170, 0.28),
]


def main():
    touched = set()
    for lesson_id, zone_id, word, x, y in FIXES:
        p = os.path.join("output/lessons/daily", lesson_id, "lesson.json")
        lesson = json.load(open(p))
        hit = False
        for z in lesson["zones"]:
            if z["id"] != zone_id:
                continue
            for w in z["hotspots"]:
                if w["word"].lower() == word:
                    print("✏️  %s/%s %s: (%.3f, %.3f) → (%.3f, %.3f)" % (
                        lesson_id, zone_id, word, w.get("x", -1), w.get("y", -1), x, y))
                    w["x"], w["y"] = x, y
                    hit = True
        if not hit:
            print("⚠️  not found: %s/%s %s" % (lesson_id, zone_id, word))
            continue
        json.dump(lesson, open(p, "w"), ensure_ascii=False, indent=2)
        touched.add(lesson_id)
    print("touched:", sorted(touched))


if __name__ == "__main__":
    main()
