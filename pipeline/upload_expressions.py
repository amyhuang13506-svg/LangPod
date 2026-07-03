# -*- coding: utf-8 -*-
"""
口语表达库上传 OSS：expressions/{category_id}.json + 音频 + expressions/index.json。

用法: python3 upload_expressions.py
"""

import glob
import json
import os
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


def main():
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)

    counts = {}
    for path in sorted(glob.glob(os.path.join(EXPR_DIR, "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        cat_id = data["id"]
        print("📤 %s (%s)" % (cat_id, data["zh"]))

        # 上传音频并重写 URL
        def upload_audio(obj, field):
            rel = obj.get(field) or ""
            if not rel or rel.startswith("http"):
                return
            local = os.path.join(EXPR_DIR, rel)
            if os.path.exists(local):
                key = "expressions/%s" % rel
                with open(local, "rb") as fh:
                    bucket.put_object(key, fh)
                obj[field] = "%s/%s" % (OSS_CDN_DOMAIN, key)
            else:
                obj[field] = ""

        for e in data["expressions"]:
            upload_audio(e, "audio")
            for ex in e.get("examples", []):
                upload_audio(ex, "audio")

        bucket.put_object(
            "expressions/%s.json" % cat_id,
            json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8"),
        )
        # 本地写回（幂等）
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        counts[cat_id] = len(data["expressions"])
        print("   ✅ %d expressions" % counts[cat_id])

    # index.json：组 → 分类（含表达数、免费标记）
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
