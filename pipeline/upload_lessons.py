# -*- coding: utf-8 -*-
"""
词汇小课堂 Step 3: 上传课堂到阿里云 OSS + 更新各国 index.json 和全局 countries.json。

OSS 结构:
  lessons/countries.json
  lessons/{country}/index.json
  lessons/{country}/{lesson_id}/lesson.json
  lessons/{country}/{lesson_id}/cover.jpg + {zone_id}.jpg

用法:
  python3 upload_lessons.py --lesson lesson_us_otc_meds
  python3 upload_lessons.py --country us
  python3 upload_lessons.py            # 全部本地已生成的课堂
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime

from config import (
    OSS_ACCESS_KEY_ID,
    OSS_ACCESS_KEY_SECRET,
    OSS_BUCKET_NAME,
    OSS_CDN_DOMAIN,
    OSS_ENDPOINT,
    OUTPUT_DIR,
)
from lesson_catalog import COUNTRIES

try:
    import oss2
except ImportError:
    print("❌ Please install oss2: pip install oss2")
    sys.exit(1)

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")


def get_bucket():
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    return oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)


def upload_file(bucket, local_path, oss_key):
    with open(local_path, "rb") as f:
        bucket.put_object(oss_key, f)
    return "%s/%s" % (OSS_CDN_DOMAIN, oss_key)


def upload_lesson(bucket, json_path):
    """上传单个课堂（图片 + JSON），重写 JSON 内路径为完整 OSS URL。"""
    with open(json_path, "r", encoding="utf-8") as f:
        lesson = json.load(f)
    lesson_dir = os.path.dirname(json_path)
    prefix = "lessons/%s/%s" % (lesson["country"], lesson["id"])
    print("📤 %s — %s" % (lesson["id"], lesson["title_zh"]))

    incomplete = False
    for zone in lesson["zones"]:
        img_name = os.path.basename(zone.get("image") or "")
        local = os.path.join(lesson_dir, img_name) if img_name else ""
        if img_name and os.path.exists(local):
            zone["image"] = upload_file(bucket, local, "%s/%s" % (prefix, img_name))
            print("   ☁️  %s" % img_name)
        elif not (zone.get("image") or "").startswith("http"):
            print("   ⚠️  zone %s missing image" % zone["id"])
            incomplete = True

    cover_local = os.path.join(lesson_dir, "cover.jpg")
    if os.path.exists(cover_local):
        lesson["cover"] = upload_file(bucket, cover_local, "%s/cover.jpg" % prefix)
    elif not (lesson.get("cover") or "").startswith("http"):
        incomplete = True

    # 发音音频（ElevenLabs 预生成）：上传 audio/ 并把相对路径重写为 OSS URL。
    # 音频缺失不算 incomplete —— 没有音频 App 会回落系统 TTS。
    def upload_audio_field(obj, field):
        rel = obj.get(field) or ""
        if not rel or rel.startswith("http"):
            return
        local = os.path.join(lesson_dir, rel)
        if os.path.exists(local):
            obj[field] = upload_file(bucket, local, "%s/%s" % (prefix, rel))
        else:
            obj[field] = ""

    audio_count = 0
    for zone in lesson["zones"]:
        for word in zone["hotspots"] + zone["extra_words"]:
            upload_audio_field(word, "audio")
            upload_audio_field(word, "example_audio")
            audio_count += 2
    for sentence in lesson.get("sentences", []):
        upload_audio_field(sentence, "audio")
        audio_count += 1
    if audio_count:
        print("   🔊 audio fields processed: %d" % audio_count)

    if incomplete:
        print("   ❌ skipped (incomplete assets)")
        return None

    if not lesson.get("date"):
        lesson["date"] = datetime.now().strftime("%Y-%m-%d")

    bucket.put_object(
        "%s/lesson.json" % prefix,
        json.dumps(lesson, ensure_ascii=False, indent=2).encode("utf-8"),
    )
    # 本地也写回 OSS URL 版本，保持幂等
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(lesson, f, ensure_ascii=False, indent=2)
    print("   ✅ lesson.json uploaded")
    return lesson


def rebuild_country_index(bucket, country):
    """扫描 OSS 上该国全部 lesson.json → 重建 index.json。"""
    lessons = []
    prefix = "lessons/%s/" % country
    for obj in oss2.ObjectIterator(bucket, prefix=prefix):
        if not obj.key.endswith("/lesson.json"):
            continue
        data = json.loads(bucket.get_object(obj.key).read())
        lessons.append({
            "id": data["id"],
            "title_zh": data["title_zh"],
            "title_en": data["title_en"],
            "category": data["category"],
            "category_zh": data["category_zh"],
            "icon": data.get("icon", ""),
            "cover": data.get("cover", ""),
            "is_free": data.get("is_free", False),
            "is_daily": data.get("is_daily", False),
            "date": data.get("date", ""),
            "word_count": data.get("word_count", 0),
            "zone_count": len(data.get("zones", [])),
        })
    lessons.sort(key=lambda x: (x["is_daily"], x["date"]), reverse=True)
    index = {
        "country": country,
        "country_zh": COUNTRIES[country]["zh"],
        "flag": COUNTRIES[country]["flag"],
        "lessons": lessons,
        "total": len(lessons),
    }
    bucket.put_object(
        "lessons/%s/index.json" % country,
        json.dumps(index, ensure_ascii=False, indent=2).encode("utf-8"),
    )
    print("📇 lessons/%s/index.json (%d lessons)" % (country, len(lessons)))
    return len(lessons)


def rebuild_countries_json(bucket, counts):
    countries = [
        {
            "id": cc,
            "name_zh": meta["zh"],
            "flag": meta["flag"],
            "accent": meta["accent"],
            "lesson_count": counts.get(cc, 0),
        }
        for cc, meta in COUNTRIES.items()
    ]
    bucket.put_object(
        "lessons/countries.json",
        json.dumps({"countries": countries}, ensure_ascii=False, indent=2).encode("utf-8"),
    )
    print("🌍 lessons/countries.json")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", help="single lesson id")
    parser.add_argument("--country", help="single country")
    args = parser.parse_args()

    pattern = os.path.join(LESSONS_DIR, args.country or "*", args.lesson or "lesson_*", "lesson.json")
    files = sorted(glob.glob(pattern))
    if not files:
        print("❌ no lessons found: %s" % pattern)
        sys.exit(1)

    bucket = get_bucket()
    touched = set()
    for fp in files:
        try:
            lesson = upload_lesson(bucket, fp)
            if lesson:
                touched.add(lesson["country"])
        except Exception as e:
            print("   ❌ %s: %s" % (fp, e))

    counts = {}
    for cc in sorted(touched):
        counts[cc] = rebuild_country_index(bucket, cc)
    # countries.json 需要全部国家的数量：未 touched 的国家也扫一遍已有 index
    for cc in COUNTRIES:
        if cc in counts:
            continue
        try:
            idx = json.loads(bucket.get_object("lessons/%s/index.json" % cc).read())
            counts[cc] = idx.get("total", 0)
        except Exception:
            counts[cc] = 0
    rebuild_countries_json(bucket, counts)
    print("\n🎉 upload complete")


if __name__ == "__main__":
    main()
