# -*- coding: utf-8 -*-
"""
模拟现场对话头像：固定两张，性别与配音一致（用户定稿：不按课生成、不批量画像）。
- 「你」  = 女（对话配音是 Bella 女声）→ lessons/avatars/you.jpg
- 「对方」= 男（对话配音是 Chris 男声）→ lessons/avatars/other.jpg

生成一次后，把这两个 URL 写进所有含 roleplay 的 lesson.json（覆盖旧的按课头像）
并重传 lesson.json。幂等：头像文件已存在则只做回写。

用法: python3 generate_roleplay_avatars.py
"""

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

# 性别与配音固定对应：你 = Bella 女声 → 女头像；对方 = Chris 男声 → 男头像
AVATARS = {
    "you": STYLE + " Subject: a friendly young East Asian WOMAN traveler in casual clothes.",
    "other": STYLE + " Subject: a friendly adult MAN in smart-casual work attire (universal service staff look).",
}


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
    import oss2
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)

    avatars_dir = os.path.join(LESSONS_DIR, "avatars")
    os.makedirs(avatars_dir, exist_ok=True)

    urls = {}
    for who, prompt in AVATARS.items():
        local = os.path.join(avatars_dir, "%s.png" % who)
        if not (os.path.exists(local) and os.path.getsize(local) > 10000):
            print("🧑 generating %s avatar" % who)
            if not generate_image(prompt, local):
                print("❌ %s avatar failed, abort" % who)
                return
        key = "lessons/avatars/%s.jpg" % who
        bucket.put_object(key, compress_avatar(local))
        urls[who] = "%s/%s" % (OSS_CDN_DOMAIN, key)
        print("   ✅ %s" % urls[who])

    # 写进所有含 roleplay 的课并重传 lesson.json（覆盖旧的按课头像）
    updated = 0
    for json_path in sorted(glob.glob(os.path.join(LESSONS_DIR, "*", "*", "lesson.json"))):
        with open(json_path, "r", encoding="utf-8") as f:
            lesson = json.load(f)
        rp = lesson.get("roleplay")
        if not rp or not rp.get("dialogue"):
            continue
        if rp.get("you_avatar") == urls["you"] and rp.get("other_avatar") == urls["other"]:
            continue
        rp["you_avatar"] = urls["you"]
        rp["other_avatar"] = urls["other"]
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=2)
        bucket.put_object(
            "lessons/%s/%s/lesson.json" % (lesson.get("country", "us"), lesson["id"]),
            json.dumps(lesson, ensure_ascii=False, indent=2).encode("utf-8"),
        )
        updated += 1
        print("   📝 %s" % lesson["id"])

    print("\n=== fixed avatars written to %d lessons ===" % updated)


if __name__ == "__main__":
    main()
