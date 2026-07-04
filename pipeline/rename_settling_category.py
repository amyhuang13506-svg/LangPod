# -*- coding: utf-8 -*-
"""一次性迁移：把 settling 分类的中文名从「安顿下来」改为「生活必备」。
用 index.json 里的课 id 直接定位各课 lesson.json（避免列出全部音频对象），
只重写小 JSON 的 category_zh 并重建各国 index.json，不重传图片/音频。
OSS 和本地都更新。用后可删。"""

import glob
import json
import os

from config import OUTPUT_DIR
from upload_lessons import get_bucket, rebuild_country_index

NEW_ZH = "生活必备"
COUNTRIES = ["us", "uk", "au", "ca", "nz", "sg"]


def main():
    bucket = get_bucket()

    for cc in COUNTRIES:
        # 从 index.json 拿到该国所有 settling 课 id（避免遍历音频对象）
        idx = json.loads(bucket.get_object("lessons/%s/index.json" % cc).read())
        ids = [l["id"] for l in idx["lessons"] if l.get("category") == "settling"]
        changed = 0
        for lid in ids:
            key = "lessons/%s/%s/lesson.json" % (cc, lid)
            data = json.loads(bucket.get_object(key).read())
            if data.get("category_zh") != NEW_ZH:
                data["category_zh"] = NEW_ZH
                bucket.put_object(key, json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8"))
                changed += 1
        rebuild_country_index(bucket, cc)
        print("  %s: %d/%d settling 课更新 + 索引重建" % (cc, changed, len(ids)), flush=True)

    # 本地文件同步
    local = 0
    for f in glob.glob(os.path.join(OUTPUT_DIR, "lessons", "*", "*", "lesson.json")):
        data = json.load(open(f, encoding="utf-8"))
        if data.get("category") == "settling" and data.get("category_zh") != NEW_ZH:
            data["category_zh"] = NEW_ZH
            with open(f, "w", encoding="utf-8") as w:
                json.dump(data, w, ensure_ascii=False, indent=2)
            local += 1
    print("本地 %d 课同步" % local, flush=True)
    print("✅ 完成", flush=True)


if __name__ == "__main__":
    main()
