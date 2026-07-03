# -*- coding: utf-8 -*-
"""
口语表达库场景插画：每条表达的场景示例生成一张 gpt-image-1 插画。
图里只有场景 + 两个人物（A 在左、B 在右），无任何文字——对话气泡由 App 叠加渲染
（文字零拼写错误、可点击播放、可带中文翻译）。

文件名带内容 hash：场景文字重新生成时旧图不会被复用（同音频防串戏的教训）。

用法:
  python3 generate_expression_scenes.py                # 全部分类（跳过已存在）
  python3 generate_expression_scenes.py greetings      # 只跑一个分类
输出: output/expressions/scenes/{category}/{slug}_{hash}.png
并把相对路径写回 {category}.json 的 scene.image（upload_expressions.py 负责换成 URL）
"""

import base64
import glob
import hashlib
import json
import os
import sys

import requests

from config import GPT_API_KEY, OUTPUT_DIR

EXPR_DIR = os.path.join(OUTPUT_DIR, "expressions")
SCENES_DIR = os.path.join(EXPR_DIR, "scenes")
IMAGE_ENDPOINT = "https://api.v3.cm/v1/images/generations"
IMAGE_MODEL = "gpt-image-1"

STYLE = (
    "Flat vector illustration in a modern minimal style, soft warm color palette, "
    "clean geometric shapes with subtle outlines, gentle shadows, cream background tones. "
    "Like a high-quality illustration from a design-forward app. "
)

COMPOSITION = (
    " Composition requirements: EXACTLY TWO people, facing each other and clearly mid-conversation. "
    "Person A stands in the LEFT third of the frame, person B in the RIGHT third. "
    "Both drawn from roughly knee-up, heads in the lower two-thirds of the frame, "
    "leaving generous calm open space in the upper part of the image (sky, wall, background) "
    "where UI speech bubbles will be overlaid later. "
    "The two people must look different from each other (hair, clothing color). "
    "ABSOLUTELY NO text, letters, numbers, speech bubbles or signage anywhere in the image. "
    "NO real brand logos."
)


def slugify(text):
    import re
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")[:40]


def scene_hash(scene):
    src = (scene.get("setup_zh") or "") + "|".join(l.get("en", "") for l in scene.get("dialogue", []))
    return hashlib.md5(src.encode("utf-8")).hexdigest()[:8]


def generate_scene_image(expression, scene, output_path):
    dialogue_ctx = " ".join(
        "%s says: \"%s\"." % (l["speaker"], l["en"]) for l in scene.get("dialogue", [])
    )
    prompt = (
        STYLE
        + "Scene (described in Chinese): %s " % scene["setup_zh"]
        + "The moment being depicted: %s Their poses and expressions should match this exchange." % dialogue_ctx
        + COMPOSITION
    )
    response = requests.post(
        IMAGE_ENDPOINT,
        headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
        json={
            "model": IMAGE_MODEL,
            "prompt": prompt,
            "n": 1,
            "size": "1536x1024",
            "quality": "medium",
        },
        timeout=300,
    )
    if response.status_code != 200:
        print("      ❌ image API %d: %s" % (response.status_code, response.text[:200]))
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
        print("      ❌ image API returned no image")
        return False
    with open(output_path, "wb") as f:
        f.write(raw)
    print("      🎨 saved (%d KB)" % (len(raw) // 1024))
    return True


def process_category(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    cat_id = data["id"]
    cat_dir = os.path.join(SCENES_DIR, cat_id)
    os.makedirs(cat_dir, exist_ok=True)
    print("📂 %s (%s)" % (cat_id, data["zh"]))

    done = failed = skipped = 0
    changed = False
    for e in data["expressions"]:
        scene = e.get("scene")
        if not scene or not scene.get("dialogue"):
            continue
        filename = "%s_%s.png" % (slugify(e["english"]), scene_hash(scene))
        rel = "scenes/%s/%s" % (cat_id, filename)
        local = os.path.join(EXPR_DIR, rel)
        existing = scene.get("image") or ""
        # 已是正确 hash 的 URL 或本地文件 → 跳过
        if existing.startswith("http") and filename in existing:
            skipped += 1
            continue
        if os.path.exists(local) and os.path.getsize(local) > 10000:
            if existing != rel:
                scene["image"] = rel
                changed = True
            skipped += 1
            continue
        print("   🖼  %s" % e["english"])
        if generate_scene_image(e, scene, local):
            scene["image"] = rel
            changed = True
            done += 1
        else:
            failed += 1

    if changed:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    print("   ✅ %d new, %d skipped, %d failed" % (done, skipped, failed))
    return done, skipped, failed


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    paths = sorted(glob.glob(os.path.join(EXPR_DIR, "*.json")))
    if only:
        paths = [p for p in paths if os.path.basename(p) == "%s.json" % only]
    totals = [0, 0, 0]
    for path in paths:
        d, s, f = process_category(path)
        totals[0] += d
        totals[1] += s
        totals[2] += f
    print("\n=== scenes: %d new, %d skipped, %d failed ===" % tuple(totals))


if __name__ == "__main__":
    main()
