# -*- coding: utf-8 -*-
"""
口语表达库卡片封面：按句子含义生成视觉隐喻插画（区别于详情页的对话场景图）。

两步走：
  1) GPT 按分类批量为每条表达想一个"视觉概念"（一句英文画面描述，具象、幽默、零文字）
     概念写回分类 JSON 的 cover_concept_en（可复现，重跑不重复调 GPT）
  2) gpt-image-1 按 B 套色系（大组定色：蜜桃粉/天空蓝/薄荷绿/柠檬黄）出 1024x1024 图
     写回 expression 的 cover 字段（相对路径），upload_expressions.py 负责换 OSS URL

用法:
  python3 generate_expression_card_covers.py            # 全部分类（跳过已存在）
  python3 generate_expression_card_covers.py thanks     # 只跑一个分类
  SCENE_LIMIT=2 python3 ...                             # 每分类只跑前 N 条（出示例用）
输出: output/expressions/card_covers/{category}/{slug}_{hash}.png
"""

import base64
import glob
import hashlib
import json
import os
import sys
import time

import requests

from config import GPT_API_KEY, OUTPUT_DIR
import expression_catalog

EXPR_DIR = os.path.join(OUTPUT_DIR, "expressions")
COVERS_DIR = os.path.join(EXPR_DIR, "card_covers")
CHAT_ENDPOINT = "https://api.v3.cm/v1/chat/completions"
IMAGE_ENDPOINT = "https://api.v3.cm/v1/images/generations"
IMAGE_MODEL = "gpt-image-1"
CHAT_MODEL = "gpt-4o"

# 分类 id → 大组 id（色系按大组走）
CAT_TO_GROUP = {
    c["id"]: g["id"] for g in expression_catalog.GROUPS for c in g["categories"]
}

# 风格版本号：参与 hash，一改此值旧图自动作废重生成
STYLE_VERSION = "cover-v2-tricolor-rich"

STYLE = (
    "Flat vector illustration in a modern minimal style, "
    "clean geometric shapes with subtle outlines, gentle shadows. "
    "Like a high-quality illustration from a design-forward app. "
    "A RICH, DETAILED full scene: the focal subject sits inside a complete environment "
    "with layered background elements, furniture, plants, props and small decorative details "
    "filling the frame — cozy and lively, not empty, minimal blank space. "
    "ABSOLUTELY NO text, letters, numbers or signage anywhere. NO real brand logos. "
)

# 三色方案：每组主色 ~60%（背景+大面积）+ 两个点缀色（衣服/植物/小物件）
GROUP_PALETTE = {
    "daily": (
        "Color palette: dominant warm sunny gold and honey tones (about 60% of the image, "
        "background and large shapes), accented with soft coral pink and fresh mint green "
        "on clothing, plants and small props. Very light warm-cream background. "
    ),
    "reactions": (
        "Color palette: dominant sweet peach pink and blush tones (about 60% of the image, "
        "background and large shapes), accented with fresh mint green and soft butter yellow "
        "on clothing, plants and small props. Light pink-cream background. "
    ),
    "social": (
        "Color palette: dominant soft lavender and lilac purple tones (about 60% of the image, "
        "background and large shapes), accented with sweet peach pink and soft butter yellow "
        "on clothing, plants and small props. Very light lavender-cream background. "
    ),
    "express": (
        "Color palette: dominant bright sky blue and powder blue tones (about 60% of the image, "
        "background and large shapes), accented with warm coral pink and soft lemon yellow "
        "on clothing, plants and small props. Very light airy blue background. "
    ),
    "skills": (
        "Color palette: dominant fresh mint green and seafoam tones (about 60% of the image, "
        "background and large shapes), accented with soft peach pink and warm sandy yellow "
        "on clothing, plants and small props. Very light minty background. "
    ),
    "native": (
        "Color palette: dominant sunny lemon yellow and warm golden tones (about 60% of the image, "
        "background and large shapes), accented with coral pink and fresh teal green "
        "on clothing, plants and small props. Very light buttery-yellow background. "
    ),
}

CONCEPT_PROMPT = """You are an art director for an English-learning app. For each spoken expression below, invent ONE striking visual concept for its cover illustration card.

Rules:
- The image must instantly convey the FEELING / MEANING of the phrase (a visual metaphor, a vivid moment, or a humorous scene). It doubles as a memory hook for learners.
- Concrete and drawable: one focal subject (a person, animal or object), one clear action or state. No abstract diagrams.
- Place the focal subject inside a CONCRETE setting (a room, kitchen, park, cafe, street...) and name 3-5 supporting environment details/props, so the illustration is a rich full scene, not a lone subject on blank background.
- Prefer indoor or object-focused settings when possible (grass/sky-heavy outdoor scenes wash out the card's color theme).
- Prefer witty/warm ideas: e.g. "Hang in there" = a cute cat hanging onto a tree branch; "I'm broke" = an empty wallet turned upside down with a moth flying out, in a kitchen with an open empty fridge.
- The illustration will contain ZERO text, so never rely on words, letters, signs or logos.
- Vary subjects across the list (mix people of different ages/genders, animals, objects) so cards don't look repetitive side by side.
- One line of English per expression, max 60 words.

Expressions (with Chinese meaning for context):
%s

Return STRICT JSON: {"concepts": [{"english": "<expression exactly as given>", "concept": "<one-line visual description>"}, ...]} — one entry per expression, same order."""


def slugify(text):
    import re
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")[:40]


def cover_hash(concept):
    src = STYLE_VERSION + "|" + concept
    return hashlib.md5(src.encode("utf-8")).hexdigest()[:8]


CONCEPT_CHUNK = 12  # 单次 GPT 最多几条 —— 太多会返回超长/截断 JSON 解析失败


def _gpt_concepts_chunk(expressions):
    listing = "\n".join(
        "%d. %s — %s" % (i + 1, e["english"], e.get("meaning_zh", ""))
        for i, e in enumerate(expressions)
    )
    for attempt in range(3):
        r = requests.post(
            CHAT_ENDPOINT,
            headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
            json={
                "model": CHAT_MODEL,
                "messages": [{"role": "user", "content": CONCEPT_PROMPT % listing}],
                "temperature": 0.9,
                "response_format": {"type": "json_object"},
            },
            timeout=120,
        )
        if r.status_code != 200:
            time.sleep(5 * (attempt + 1))
            continue
        try:
            content = r.json()["choices"][0]["message"]["content"]
            items = json.loads(content)["concepts"]
            return {it["english"].strip(): it["concept"].strip() for it in items}
        except (KeyError, ValueError, json.JSONDecodeError):
            time.sleep(3)
    return {}


def gpt_concepts(expressions):
    """为一个分类的表达生成视觉概念，分块调用（防大批量返回超长 JSON 解析失败）。"""
    out = {}
    for i in range(0, len(expressions), CONCEPT_CHUNK):
        out.update(_gpt_concepts_chunk(expressions[i:i + CONCEPT_CHUNK]))
    return out


def generate_cover_image(concept, group_id, output_path):
    prompt = STYLE + GROUP_PALETTE.get(group_id, "") + "Concept: " + concept
    response = requests.post(
        IMAGE_ENDPOINT,
        headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
        json={
            "model": IMAGE_MODEL,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
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
    group_id = CAT_TO_GROUP.get(cat_id, "")
    cat_dir = os.path.join(COVERS_DIR, cat_id)
    os.makedirs(cat_dir, exist_ok=True)
    print("📂 %s (%s) [%s]" % (cat_id, data["zh"], group_id))
    limit = int(os.environ.get("SCENE_LIMIT", "0"))

    # 第 1 步：补齐缺失的视觉概念（一次 GPT 调用/分类）
    missing = [e for e in data["expressions"] if not e.get("cover_concept_en")]
    changed = False
    if missing:
        print("   💡 generating %d concepts..." % len(missing))
        concepts = gpt_concepts(missing)
        for e in missing:
            c = concepts.get(e["english"].strip())
            if c:
                e["cover_concept_en"] = c
                changed = True
        if changed:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    # 第 2 步：出图（跳过已存在）
    done = failed = skipped = 0
    for e in data["expressions"]:
        concept = e.get("cover_concept_en")
        if not concept:
            failed += 1
            print("   ⚠️  no concept: %s" % e["english"])
            continue
        filename = "%s_%s.png" % (slugify(e["english"]), cover_hash(concept))
        rel = "card_covers/%s/%s" % (cat_id, filename)
        local = os.path.join(EXPR_DIR, rel)
        existing = e.get("cover") or ""
        if existing.startswith("http") and filename in existing:
            skipped += 1
            continue
        if os.path.exists(local) and os.path.getsize(local) > 10000:
            if existing != rel:
                e["cover"] = rel
                changed = True
            skipped += 1
            continue
        if limit and done >= limit:
            break
        print("   🖼  %s" % e["english"])
        if generate_cover_image(concept, group_id, local):
            e["cover"] = rel
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
    # index.json / verify_ckpt.json 不是分类文件，排除
    skip_files = {"index.json", "verify_ckpt.json", "today.json", "daily_state.json"}
    paths = sorted(
        p for p in glob.glob(os.path.join(EXPR_DIR, "*.json"))
        if os.path.basename(p) not in skip_files
    )
    if only:
        paths = [p for p in paths if os.path.basename(p) == "%s.json" % only]
    totals = [0, 0, 0]
    for path in paths:
        d, s, f = process_category(path)
        totals[0] += d
        totals[1] += s
        totals[2] += f
    print("\n=== card covers: %d new, %d skipped, %d failed ===" % tuple(totals))
    if totals[2]:
        sys.exit(1)


if __name__ == "__main__":
    main()
