# -*- coding: utf-8 -*-
"""
口语表达库分类封面图：24 个功能分类各生成一张 gpt-image-1 场景插画。
风格与词汇小课堂封面一致（flat vector / 暖色 / cream 底），封面不含任何文字。

用法:
  python3 generate_expression_covers.py            # 全部（跳过已存在）
  python3 generate_expression_covers.py greetings  # 只跑指定分类
输出: output/expressions/covers/{category_id}.png
"""

import base64
import os
import sys

import requests

from config import GPT_API_KEY, OUTPUT_DIR
from expression_catalog import all_categories

COVERS_DIR = os.path.join(OUTPUT_DIR, "expressions", "covers")
IMAGE_ENDPOINT = "https://api.v3.cm/v1/images/generations"
IMAGE_MODEL = "gpt-image-1"

STYLE = (
    "Flat vector illustration in a modern minimal style, soft warm color palette, "
    "clean geometric shapes with subtle outlines, gentle shadows, cream background tones. "
    "Like a high-quality illustration from a design-forward app. Wide scene composition. "
    "ABSOLUTELY NO text, letters, numbers or signage anywhere in the image. "
    "NO real brand logos."
)

# 每个分类一句场景描述：画“这个功能正在发生的瞬间”，人物表情/动作要能一眼看懂主题
COVER_SCENES = {
    # 日常反应
    "greetings": "Two friends happily waving hello to each other outside a cozy coffee shop on a sunny morning, one holding a takeaway cup.",
    "thanks": "A person with both hands on their chest smiling gratefully at a friend who just handed them a small gift box.",
    "apologies": "A person with an apologetic sheepish smile and raised palms after knocking over a coffee cup, while the other person waves it off kindly.",
    "surprise": "A person with wide eyes and hands on cheeks reacting to exciting news on their phone, small sparkles around their head.",
    "backchannel": "Two people chatting on a park bench, one leaning in and nodding attentively while the other talks with animated hands.",
    "goodbyes": "Two friends waving goodbye to each other at a doorstep at dusk, one walking away with a backpack, warm porch light.",
    # 表达自己
    "opinions": "A confident person at a casual cafe table gesturing with one open palm while sharing thoughts with two engaged listeners.",
    "feelings": "A person sprawled on a sofa with a relatable tired-but-content expression, a cat beside them, soft evening light.",
    "suggestions": "A person pointing at an open map on a table, suggesting a route to an interested friend, travel mugs nearby.",
    "agree_disagree": "Two colleagues at a table, one nodding in agreement while the other tilts their head with a thoughtful raised finger.",
    "preferences": "A person in a shop aisle happily weighing two different items, one in each hand, deciding between them.",
    "hedging": "A person shrugging with palms up and an uncertain but friendly expression, a question-mark-free thought cloud above.",
    # 会话技能
    "requests": "A person politely asking a neighbor for help carrying a large moving box, the neighbor stepping in with a smile.",
    "refusing": "A person with a warm smile politely declining an offered pastry with a gentle raised hand at a kitchen counter.",
    "interrupting": "A small casual meeting where one person leans forward with an index finger raised, politely jumping into the conversation.",
    "clarifying": "A person leaning forward cupping a hand behind their ear, asking a friend to repeat something, both smiling.",
    "transitions": "Two friends strolling and chatting along a winding park path that curves toward a new scenic direction.",
    "encouragement": "A person warmly patting a discouraged friend's shoulder on a bench, offering comfort, soft sunset colors.",
    # 进阶地道
    "slang": "Three stylish young friends laughing together outside a retro diner, one holding a skateboard, streetwear vibes.",
    "fillers": "A relaxed person talking casually with several small empty speech bubbles of different sizes floating around them.",
    "idioms": "A whimsical collage scene: a slice of cake on a plate, a tiny umbrella, and a winding road, playfully arranged together.",
    "phrasal_verbs": "A focused person at a desk fitting two large puzzle pieces together, scattered pieces around, warm lamp light.",
    "workplace": "A friendly modern office stand-up: three coworkers around a laptop with sticky notes on a board behind them.",
    "formal": "A person in a smart blazer politely presenting an envelope with both hands at an elegant reception desk.",
}


def generate_cover(cat, output_path):
    prompt = STYLE + " Scene: " + COVER_SCENES[cat["id"]]
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
        print("   ❌ image API returned no image")
        return False
    with open(output_path, "wb") as f:
        f.write(raw)
    print("   🎨 saved (%d KB)" % (len(raw) // 1024))
    return True


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    os.makedirs(COVERS_DIR, exist_ok=True)
    cats = [c for c in all_categories() if not only or c["id"] == only]
    done = failed = skipped = 0
    for cat in cats:
        path = os.path.join(COVERS_DIR, "%s.png" % cat["id"])
        if os.path.exists(path) and os.path.getsize(path) > 10000:
            skipped += 1
            continue
        print("🖼  %s (%s)" % (cat["id"], cat["zh"]))
        if generate_cover(cat, path):
            done += 1
        else:
            failed += 1
    print("\n=== covers: %d new, %d skipped, %d failed ===" % (done, skipped, failed))


if __name__ == "__main__":
    main()
