# -*- coding: utf-8 -*-
"""
模拟现场对话头像：gpt-image-1 生成真实人物画像当头像。
- 「你」：全局一张（output/lessons/avatars/you.png → OSS lessons/avatars/you.jpg）
- 「对方」：每课一张，按角色画（银行柜员/店员/医生…），存课堂目录 avatar_other.png

生成后直接上传 OSS（压成 512 JPEG）并把 URL 写进 lesson.json 的
roleplay.you_avatar / roleplay.other_avatar，同时重传 lesson.json —— 一步到位。

幂等：已有 URL 或本地文件的跳过。

用法:
  python3 generate_roleplay_avatars.py --country us
  python3 generate_roleplay_avatars.py --lesson lesson_us_bank_account
  python3 generate_roleplay_avatars.py            # 全部有 roleplay 的课
"""

import argparse
import base64
import glob
import json
import os
from io import BytesIO

import requests

from config import (
    GPT_API_KEY,
    OSS_ACCESS_KEY_ID,
    OSS_ACCESS_KEY_SECRET,
    OSS_BUCKET_NAME,
    OSS_CDN_DOMAIN,
    OSS_ENDPOINT,
    OUTPUT_DIR,
)

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")
IMAGE_ENDPOINT = "https://api.v3.cm/v1/images/generations"
IMAGE_MODEL = "gpt-image-1"

STYLE = (
    "Flat vector illustration avatar in a modern minimal style, soft warm color palette, "
    "clean geometric shapes with subtle outlines, cream background. "
    "Head-and-shoulders portrait, face centered, looking slightly toward the viewer, "
    "friendly warm smile, composed to look good cropped in a circle. "
    "ABSOLUTELY NO text, letters or logos."
)

YOU_PROMPT = STYLE + " Subject: a friendly young East Asian traveler in casual clothes."


def generate_image(prompt, output_path):
    response = requests.post(
        IMAGE_ENDPOINT,
        headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
        json={"model": IMAGE_MODEL, "prompt": prompt, "n": 1, "size": "1024x1024", "quality": "medium"},
        timeout=300,
    )
    if response.status_code != 200:
        print("   ❌ image API %d: %s" % (response.status_code, response.text[:200]))
        return False
    data = response.json().get("data") or []
    item = data[0] if data else {}
    raw = None
    if item.get("b64_json"):
        raw = base64.b64decode(item["b64_json"])
    elif item.get("url"):
        img = requests.get(item["url"], timeout=120)
        if img.status_code == 200:
            raw = img.content
    if not raw:
        print("   ❌ no image returned")
        return False
    with open(output_path, "wb") as f:
        f.write(raw)
    return True


def compress_avatar(local_path, size=512):
    from PIL import Image
    img = Image.open(local_path).convert("RGB")
    img = img.resize((size, size), Image.LANCZOS)
    buf = BytesIO()
    img.save(buf, "JPEG", quality=85)
    return buf.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson")
    parser.add_argument("--country")
    args = parser.parse_args()

    import oss2
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)

    # 1) 全局「你」头像
    avatars_dir = os.path.join(LESSONS_DIR, "avatars")
    os.makedirs(avatars_dir, exist_ok=True)
    you_local = os.path.join(avatars_dir, "you.png")
    if not (os.path.exists(you_local) and os.path.getsize(you_local) > 10000):
        print("🧑 generating YOU avatar")
        if not generate_image(YOU_PROMPT, you_local):
            print("❌ you avatar failed, abort")
            return
    you_key = "lessons/avatars/you.jpg"
    bucket.put_object(you_key, compress_avatar(you_local))
    you_url = "%s/%s" % (OSS_CDN_DOMAIN, you_key)
    print("   ✅ %s" % you_url)

    # 2) 每课「对方」头像
    dirs = sorted(glob.glob(os.path.join(LESSONS_DIR, "*", "*")))
    if args.lesson:
        dirs = [d for d in dirs if os.path.basename(d) == args.lesson]
    elif args.country:
        dirs = [d for d in dirs if os.path.basename(os.path.dirname(d)) == args.country]

    done = failed = skipped = 0
    for lesson_dir in dirs:
        json_path = os.path.join(lesson_dir, "lesson.json")
        if not os.path.exists(json_path):
            continue
        with open(json_path, "r", encoding="utf-8") as f:
            lesson = json.load(f)
        rp = lesson.get("roleplay")
        if not rp or not rp.get("dialogue"):
            continue
        if (rp.get("other_avatar") or "").startswith("http") and rp.get("you_avatar") == you_url:
            skipped += 1
            continue

        other_local = os.path.join(lesson_dir, "avatar_other.png")
        if not (os.path.exists(other_local) and os.path.getsize(other_local) > 10000):
            print("🎭 %s — 对方: %s" % (lesson["id"], rp["other_role_zh"]))
            prompt = STYLE + " Subject: a %s (职业/角色: %s), in the context of: %s." % (
                rp["other_role_zh"], rp["other_role_zh"], lesson["title_en"]
            )
            if not generate_image(prompt, other_local):
                failed += 1
                continue

        country = lesson.get("country", "us")
        other_key = "lessons/%s/%s/avatar_other.jpg" % (country, lesson["id"])
        bucket.put_object(other_key, compress_avatar(other_local))
        rp["you_avatar"] = you_url
        rp["other_avatar"] = "%s/%s" % (OSS_CDN_DOMAIN, other_key)

        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=2)
        # 直接重传 lesson.json，App 拉到即生效
        bucket.put_object(
            "lessons/%s/%s/lesson.json" % (country, lesson["id"]),
            json.dumps(lesson, ensure_ascii=False, indent=2).encode("utf-8"),
        )
        done += 1
        print("   ✅ avatar uploaded")

    print("\n=== avatars: %d done, %d skipped, %d failed ===" % (done, skipped, failed))


if __name__ == "__main__":
    main()
