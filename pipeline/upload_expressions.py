# -*- coding: utf-8 -*-
"""
口语表达库上传 OSS：expressions/{category_id}.json + 音频 + expressions/index.json。

用法: python3 upload_expressions.py
"""

import glob
import json
import os
import re
import sys

from config import (
    OSS_ACCESS_KEY_ID,
    OSS_ACCESS_KEY_SECRET,
    OSS_BUCKET_NAME,
    OSS_CDN_DOMAIN,
    OSS_ENDPOINT,
    OUTPUT_DIR,
)
from expression_catalog import GROUPS

try:
    import oss2
except ImportError:
    print("❌ pip install oss2")
    sys.exit(1)

EXPR_DIR = os.path.join(OUTPUT_DIR, "expressions")

# gpt-image-1 原图 ~2MB PNG，App 卡片用不到 → 上传前压成 1024 宽 JPEG（~150KB）
IMAGE_MAX_WIDTH = 1024
IMAGE_JPEG_QUALITY = 82


def compress_image(local_path):
    from io import BytesIO
    from PIL import Image
    img = Image.open(local_path).convert("RGB")
    if img.width > IMAGE_MAX_WIDTH:
        img = img.resize(
            (IMAGE_MAX_WIDTH, int(img.height * IMAGE_MAX_WIDTH / img.width)),
            Image.LANCZOS,
        )
    buf = BytesIO()
    img.save(buf, "JPEG", quality=IMAGE_JPEG_QUALITY)
    return buf.getvalue()


def main():
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)

    counts = {}
    scene_covers = {}  # 分类 → 第一条表达的场景插画（封面即内容）
    # index.json / verify_ckpt.json 不是分类文件（无 id 字段），排除
    skip_files = {"index.json", "verify_ckpt.json"}
    for path in sorted(glob.glob(os.path.join(EXPR_DIR, "*.json"))):
        if os.path.basename(path) in skip_files:
            continue
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        cat_id = data["id"]
        print("📤 %s (%s)" % (cat_id, data["zh"]))

        # 占位符统一为下划线 ___（禁止 ... / …）。放在上传前做，
        # 无论 JSON 里是什么（含其他脚本写回的旧文本），发到 OSS 的一定是下划线。
        for e in data["expressions"]:
            en = e.get("english", "")
            if "..." in en or "…" in en:
                t = en.replace("…", "...").replace("...", "___")
                e["english"] = re.sub(r"\s*___", " ___", t).strip()

        # 上传音频/图片等资源并重写 URL（rel 已是 http 则跳过）
        def upload_asset(obj, field, clear_if_missing=True):
            rel = obj.get(field) or ""
            if not rel or rel.startswith("http"):
                return
            local = os.path.join(EXPR_DIR, rel)
            if os.path.exists(local):
                if rel.endswith(".png"):
                    key = "expressions/%s" % rel[:-4] + ".jpg"
                    bucket.put_object(key, compress_image(local))
                else:
                    key = "expressions/%s" % rel
                    with open(local, "rb") as fh:
                        bucket.put_object(key, fh)
                obj[field] = "%s/%s" % (OSS_CDN_DOMAIN, key)
            elif clear_if_missing:
                obj[field] = ""

        for e in data["expressions"]:
            upload_asset(e, "audio")
            # 卡片封面（generate_expression_card_covers.py 产出，按句意的隐喻图）
            if e.get("cover"):
                upload_asset(e, "cover", clear_if_missing=False)
            for ex in e.get("examples", []):
                upload_asset(ex, "audio")
            scene = e.get("scene") or {}
            for line in scene.get("dialogue", []):
                upload_asset(line, "audio")
            # 场景插画（generate_expression_scenes.py 产出，可能还没生成 → 保留空缺不清空）
            if scene.get("image"):
                upload_asset(scene, "image", clear_if_missing=False)

        bucket.put_object(
            "expressions/%s.json" % cat_id,
            json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8"),
        )
        # 本地写回（幂等）
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        counts[cat_id] = len(data["expressions"])
        for e in data["expressions"]:
            # 分类封面优先用第一条表达的卡片封面（隐喻图），其次场景插画
            img = e.get("cover") or (e.get("scene") or {}).get("image") or ""
            if img.startswith("http"):
                scene_covers[cat_id] = img
                break
        print("   ✅ %d expressions" % counts[cat_id])

    # 分类封面（generate_expression_covers.py 产出）
    covers = {}
    covers_dir = os.path.join(EXPR_DIR, "covers")
    for path in sorted(glob.glob(os.path.join(covers_dir, "*.png"))):
        cat_id = os.path.splitext(os.path.basename(path))[0]
        key = "expressions/covers/%s.jpg" % cat_id
        bucket.put_object(key, compress_image(path))
        covers[cat_id] = "%s/%s" % (OSS_CDN_DOMAIN, key)
    if covers:
        print("🖼  %d covers uploaded" % len(covers))

    # index.json：组 → 分类（含表达数、免费标记、封面）
    index = {"groups": []}
    from expression_catalog import FREE_CATEGORY_IDS
    for g in GROUPS:
        index["groups"].append({
            "id": g["id"],
            "zh": g["zh"],
            "icon": g["icon"],
            "desc": g["desc"],
            "categories": [
                {
                    "id": c["id"],
                    "zh": c["zh"],
                    "count": counts.get(c["id"], 0),
                    "is_free": c["id"] in FREE_CATEGORY_IDS,
                    # 封面优先用第一条表达的场景插画（封面即内容），无场景图时兜底通用封面
                    "cover": scene_covers.get(c["id"]) or covers.get(c["id"], ""),
                }
                for c in g["categories"]
            ],
        })
    bucket.put_object(
        "expressions/index.json",
        json.dumps(index, ensure_ascii=False, indent=2).encode("utf-8"),
    )
    print("📇 expressions/index.json (%d categories)" % len(counts))
    print("\n🎉 upload complete")


if __name__ == "__main__":
    main()
