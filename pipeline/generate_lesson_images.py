# -*- coding: utf-8 -*-
"""
词汇小课堂 Step 2: 生成分区场景图（DALL-E 3 扁平插画）+ 视觉模型自动标注单词坐标。

流程（每分区）:
  1. 场景蓝图 prompt（hotspot 词必须清晰出现、互不遮挡、无文字无商标）
  2. DALL-E 3 生成 1792x1024 横幅插画
  3. GPT-4o vision 定位每个 hotspot 词 → 归一化中心坐标 (x, y)
  4. 未识别到的词 → 重新生成整图（最多 2 次）；仍失败 → 该词降级进 extra_words
  5. 写回 lesson.json（坐标 + 图片相对路径），封面取第一分区图

用法:
  python3 generate_lesson_images.py --lesson lesson_us_otc_meds
  python3 generate_lesson_images.py --country us
  python3 generate_lesson_images.py --review-only   # 只重新生成 review 页

产出人工抽查页: output/lessons/review_{country}.html
"""

import argparse
import base64
import glob
import json
import os
import shutil
import sys
import time

import requests

from config import GPT_API_ENDPOINT, GPT_API_KEY, OUTPUT_DIR
from lesson_catalog import COUNTRIES

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")
IMAGE_ENDPOINT = "https://api.v3.cm/v1/images/generations"
# gpt-image-1（非 DALL-E 3）：指令服从性强、英文拼写正确。
# 英语学习场景图里出现"拼写正确"的标牌是加分项；DALL-E 3 会生成乱拼假单词，不可用。
IMAGE_MODEL = "gpt-image-1"
VISION_MODEL = "gpt-4o"
MAX_IMAGE_ATTEMPTS = 2  # 首次 + 重试 1 次（每次 ~¥0.5，控制成本）
# 标签最小间距：GPT-4o vision 偶尔把相邻物体标到同一处，App 里两个词标签会叠。
# 生成后做一遍松弛，把过近的点沿连线对称推开（点仍贴着物体，只是不再重叠）。
MIN_LABEL_SEP = 0.14
CLAMP_X = (0.04, 0.96)
CLAMP_Y = (0.06, 0.94)

STYLE_TEMPLATE = (
    "Flat vector illustration in a modern minimal style, {palette}, "
    "clean geometric shapes with subtle outlines, gentle shadows. "
    "Like a high-quality illustration from a design-forward app. Wide scene composition. "
)

# 每个国家一套色调，避免所有图看起来一模一样。
# 方向：清新明快、干净通透的柔和色（不是降饱和的灰调莫兰迪），底色明亮。
# 定稿：au=明媚草木绿, ca=珊瑚粉, nz=薰衣草紫, sg=金橙。us 沿用暖奶油（已上线）。
# uk 暂用天蓝占位（旧图是暖奶油，跑 uk 重跑图前需用户确认）。
_BRIGHT = "clean and cheerful, fresh and airy tones, bright but soft — NOT greyed, NOT muddy, NOT desaturated"
DEFAULT_PALETTE = "warm cream and soft honey color palette, " + _BRIGHT + ", light cream background"
COUNTRY_PALETTES = {
    "us": "warm cream and soft honey color palette, " + _BRIGHT + ", light cream background",
    "uk": "fresh sky-blue and cornflower color palette, " + _BRIGHT + ", light airy background",
    "au": "fresh sage-green and mint color palette, " + _BRIGHT + ", light cream background",
    "ca": "fresh blush-pink and rose color palette, " + _BRIGHT + ", light cream background",
    "nz": "fresh lavender and soft periwinkle color palette, " + _BRIGHT + ", light airy background",
    "sg": "warm golden-amber and coral color palette, " + _BRIGHT + ", light ivory background",
    # 日常词汇主题板（伪国家 daily）：软青绿，与 6 国色调都不同，区块有辨识度
    "daily": "fresh soft-teal and aqua color palette, " + _BRIGHT + ", light airy background",
}

# 伪国家 daily（日常词汇主题板）的展示元数据（review 页用）
DAILY_META = {"zh": "日常词汇", "flag": "📖"}


def country_meta(cc):
    return COUNTRIES.get(cc, DAILY_META)

HARD_RULES = (
    " ABSOLUTE RULES: Keep text in the image minimal. Any text that does appear MUST be a "
    "correctly spelled real English word relevant to the scene (e.g. PHARMACY, SALE) — "
    "never gibberish, never made-up letter sequences. NO real brand logos or trademarks. "
    "Every listed object must be drawn large enough to be clearly recognizable, fully "
    "visible, and NOT overlapping with other listed objects. Spread the listed objects "
    "across the scene."
)

# 主题图解板：App 会在热点坐标上叠加自己的可点词标签，图内绝不能再画文字
# （否则双重标签；且图内词可能与 GPT 选词不一致）。
DAILY_HARD_RULES = (
    " ABSOLUTE RULES: NO text anywhere in the image — no labels, no captions, no title, "
    "no letters at all. The app overlays its own interactive labels. NO real brand logos "
    "or trademarks. Every listed item must be drawn large enough to be clearly "
    "recognizable, fully visible, and NOT overlapping with other listed items. Spread "
    "the listed items across the board."
)


def generate_scene_image(zone, lesson, hotspot_words, output_path, variation=0, palette=None):
    """DALL-E 生成一张分区场景插画。variation 用于重试时改变构图措辞。
    palette 可覆盖国家默认色调（预览/调色用）。
    主题课（country=daily）走图解词典板 prompt：词典式铺排而非环境场景。"""
    palette = palette or COUNTRY_PALETTES.get(lesson["country"], DEFAULT_PALETTE)
    objects = ", ".join(w["word"] for w in hotspot_words)
    variation_hint = "" if variation == 0 else (
        " Alternative composition attempt %d: use a wider camera angle and place each object "
        "on its own clear surface or area so every object is unmistakable." % variation
    )
    if lesson["country"] == "daily":
        prompt = (
            STYLE_TEMPLATE.format(palette=palette)
            + "Visual dictionary board: %s — %s. " % (zone["name_en"], lesson["title_en"])
            + "Arrange the items like a picture-dictionary spread on a clean simple background, "
            + "generously spaced. If the items are parts of a whole (like body parts or a face), "
            + "draw ONE large clear subject and make each listed part distinctly visible. "
            + "The board must prominently contain each of these, one of each, clearly recognizable: %s." % objects
            + variation_hint
            + DAILY_HARD_RULES
        )
    else:
        country = COUNTRIES[lesson["country"]]
        prompt = (
            STYLE_TEMPLATE.format(palette=palette)
            + "Scene: %s — %s, in %s. " % (zone["name_en"], lesson["title_en"], country["context"].split(".")[0])
            + "The scene must prominently contain each of these objects, one of each, clearly recognizable: %s." % objects
            + variation_hint
            + HARD_RULES
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
    print("      🎨 image saved (%d KB)" % (len(raw) // 1024))
    return True


def locate_words(image_path, words):
    """GPT-4o vision 定位每个词的物体，返回 {word: {found, x, y}}。坐标归一化 0-1。"""
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    word_list = "\n".join("- %s" % w for w in words)
    prompt = (
        "This is a flat illustration. For EACH object listed below, decide if it is clearly "
        "visible in the image, and if so give the normalized center coordinates of that object "
        "(x from 0.0 left to 1.0 right, y from 0.0 top to 1.0 bottom). Be precise — the point "
        "should land ON the object itself.\n\nObjects:\n%s\n\n"
        "Output STRICT JSON only:\n"
        '{"objects": [{"word": "...", "found": true, "x": 0.42, "y": 0.55}, '
        '{"word": "...", "found": false, "x": 0, "y": 0}]}' % word_list
    )
    for attempt in range(3):
        response = requests.post(
            GPT_API_ENDPOINT,
            headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
            json={
                "model": VISION_MODEL,
                "messages": [{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": "data:image/png;base64,%s" % b64}},
                    ],
                }],
                "temperature": 0,
                "max_tokens": 2000,
            },
            timeout=180,
        )
        if response.status_code in (429, 500, 502, 503):
            time.sleep(20 * (attempt + 1))
            continue
        if response.status_code != 200:
            print("      ❌ vision %d: %s" % (response.status_code, response.text[:200]))
            return {}
        content = response.json()["choices"][0]["message"]["content"].strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[1].rsplit("```", 1)[0]
        try:
            parsed = json.loads(content.strip())
        except json.JSONDecodeError:
            print("      ⚠️ vision returned non-JSON, retrying")
            continue
        result = {}
        for obj in parsed.get("objects", []):
            w = (obj.get("word") or "").lower()
            result[w] = {
                "found": bool(obj.get("found")),
                "x": min(max(float(obj.get("x") or 0), 0.04), 0.96),
                "y": min(max(float(obj.get("y") or 0), 0.06), 0.94),
            }
        return result
    return {}


def spread_close_labels(words, min_sep=MIN_LABEL_SEP, iterations=60):
    """把坐标过近的标签沿连线对称推开，避免 App 里两个词叠在一起。
    words: 含 x/y 的 dict 列表（原地修改）。点仍会贴着原物体，只是彼此错开。"""
    if len(words) < 2:
        return 0
    moved = False
    for _ in range(iterations):
        overlap = False
        for i in range(len(words)):
            for j in range(i + 1, len(words)):
                a, b = words[i], words[j]
                dx, dy = b["x"] - a["x"], b["y"] - a["y"]
                dist = (dx * dx + dy * dy) ** 0.5
                if dist >= min_sep:
                    continue
                overlap = True
                push = (min_sep - dist) / 2 + 1e-4
                if dist < 1e-6:  # 完全重合：给一个确定的错开方向
                    dx, dy, dist = 0.6, 0.8, 1.0
                ux, uy = dx / dist, dy / dist
                a["x"] = min(max(a["x"] - ux * push, CLAMP_X[0]), CLAMP_X[1])
                a["y"] = min(max(a["y"] - uy * push, CLAMP_Y[0]), CLAMP_Y[1])
                b["x"] = min(max(b["x"] + ux * push, CLAMP_X[0]), CLAMP_X[1])
                b["y"] = min(max(b["y"] + uy * push, CLAMP_Y[0]), CLAMP_Y[1])
        if not overlap:
            break
        moved = True
    if moved:
        for w in words:
            w["x"], w["y"] = round(w["x"], 4), round(w["y"], 4)
    return sum(
        1
        for i in range(len(words))
        for j in range(i + 1, len(words))
        if ((words[i]["x"] - words[j]["x"]) ** 2 + (words[i]["y"] - words[j]["y"]) ** 2) ** 0.5 < min_sep
    )


def process_zone(lesson, zone, zone_dir_rel, lesson_dir_abs):
    """一个分区的 生图→标注→重试→降级 闭环。直接修改 zone dict。"""
    image_name = "%s.jpg" % zone["id"]
    image_path = os.path.join(lesson_dir_abs, image_name)
    hotspots = zone["hotspots"]

    best = None  # (located_count, located_map)
    for attempt in range(MAX_IMAGE_ATTEMPTS):
        if attempt > 0 or not os.path.exists(image_path):
            print("      🖼  generating image (attempt %d)..." % (attempt + 1))
            if not generate_scene_image(zone, lesson, hotspots, image_path, variation=attempt):
                continue
        located = locate_words(image_path, [w["word"] for w in hotspots])
        found = [w for w in hotspots if located.get(w["word"].lower(), {}).get("found")]
        print("      📍 located %d/%d hotspots" % (len(found), len(hotspots)))
        if best is None or len(found) > best[0]:
            best = (len(found), located)
            shutil.copyfile(image_path, image_path + ".best")
        if len(found) == len(hotspots):
            break
        # 未全中 → 下一轮重新生成（换构图措辞）
        if attempt < MAX_IMAGE_ATTEMPTS - 1:
            os.remove(image_path)

    if best is None:
        print("      ❌ zone failed entirely")
        return False
    # 用效果最好的一版图
    if os.path.exists(image_path + ".best"):
        shutil.move(image_path + ".best", image_path)
    located = best[1]

    kept, demoted = [], []
    for w in hotspots:
        info = located.get(w["word"].lower())
        if info and info["found"]:
            w["x"], w["y"] = round(info["x"], 4), round(info["y"], 4)
            kept.append(w)
        else:
            w.pop("x", None); w.pop("y", None)
            demoted.append(w)
    if demoted:
        print("      ↓ demoted to extra_words: %s" % ", ".join(w["word"] for w in demoted))
    remaining = spread_close_labels(kept)
    if remaining:
        print("      ⚠️  %d label pair(s) still under %.2f after spreading" % (remaining, MIN_LABEL_SEP))
    zone["hotspots"] = kept
    zone["extra_words"] = demoted + zone["extra_words"]
    zone["image"] = "%s/%s" % (zone_dir_rel, image_name)
    return len(kept) >= 3  # 少于 3 个可点的词就算这个分区不合格


def process_lesson(lesson_json_path):
    with open(lesson_json_path, "r", encoding="utf-8") as f:
        lesson = json.load(f)
    lesson_dir_abs = os.path.dirname(lesson_json_path)
    zone_dir_rel = "lessons/%s/%s" % (lesson["country"], lesson["id"])

    print("\n🎨 %s — %s" % (lesson["id"], lesson["title_zh"]))
    all_ok = True
    for zone in lesson["zones"]:
        if zone.get("image") and os.path.exists(os.path.join(lesson_dir_abs, os.path.basename(zone["image"]))):
            print("   ⏭ zone %s (image exists)" % zone["id"])
            continue
        print("   ▸ zone: %s (%s)" % (zone["id"], zone["name_zh"]))
        ok = process_zone(lesson, zone, zone_dir_rel, lesson_dir_abs)
        all_ok = all_ok and ok

    # 封面 = 第一分区图（零成本）
    first_img = lesson["zones"][0].get("image", "")
    if first_img:
        cover_path = os.path.join(lesson_dir_abs, "cover.jpg")
        src = os.path.join(lesson_dir_abs, os.path.basename(first_img))
        if os.path.exists(src) and not os.path.exists(cover_path):
            shutil.copyfile(src, cover_path)
        lesson["cover"] = "%s/cover.jpg" % zone_dir_rel

    lesson["word_count"] = sum(len(z["hotspots"]) + len(z["extra_words"]) for z in lesson["zones"])
    with open(lesson_json_path, "w", encoding="utf-8") as f:
        json.dump(lesson, f, ensure_ascii=False, indent=2)
    print("   %s saved" % ("✅" if all_ok else "⚠️ (some zones weak)"))
    return all_ok


# ---------- Review page ----------

REVIEW_CSS = """
body{font-family:-apple-system,sans-serif;background:#f5f2ea;margin:0;padding:24px}
h1{font-size:22px} h2{font-size:17px;margin:32px 0 4px} .zh{color:#666;font-size:13px}
.zone{position:relative;display:inline-block;margin:8px 0;max-width:900px}
.zone img{width:100%;border-radius:12px;display:block}
.dot{position:absolute;transform:translate(-50%,-50%);background:rgba(255,255,255,.95);
border:2px solid #2563eb;border-radius:14px;padding:2px 8px;font-size:12px;font-weight:600;
color:#1e3a5f;box-shadow:0 1px 4px rgba(0,0,0,.25);white-space:nowrap}
.dot::before{content:'';position:absolute;left:50%;top:100%;transform:translateX(-50%);
border:5px solid transparent;border-top-color:#2563eb}
.extras{font-size:13px;color:#444;margin:4px 0 16px} .extras b{color:#b45309}
.meta{font-size:12px;color:#999}
"""


def build_review_page(country):
    files = sorted(glob.glob(os.path.join(LESSONS_DIR, country, "lesson_*", "lesson.json")))
    if not files:
        print("no lessons for %s" % country)
        return
    parts = ["<html><head><meta charset='utf-8'><style>%s</style></head><body>" % REVIEW_CSS]
    meta = country_meta(country)
    parts.append("<h1>%s %s — 词汇小课堂标注审阅（%d 课）</h1>" % (
        meta["flag"], meta["zh"], len(files)))
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            lesson = json.load(f)
        rel_dir = os.path.relpath(os.path.dirname(fp), LESSONS_DIR)
        parts.append("<h2>%s <span class='zh'>%s · %d 词 · %s</span></h2>" % (
            lesson["title_zh"], lesson["title_en"], lesson.get("word_count", 0), lesson["id"]))
        for z in lesson["zones"]:
            img_file = os.path.basename(z.get("image") or "")
            if not img_file:
                parts.append("<p class='meta'>zone %s: ❌ 无图</p>" % z["id"])
                continue
            parts.append("<div class='meta'>%s %s</div>" % (z["name_zh"], z["name_en"]))
            parts.append("<div class='zone'><img src='%s/%s'>" % (rel_dir, img_file))
            for w in z["hotspots"]:
                parts.append("<span class='dot' style='left:%.1f%%;top:%.1f%%'>%s</span>" % (
                    w["x"] * 100, w["y"] * 100, w["word"]))
            parts.append("</div>")
            if z["extra_words"]:
                parts.append("<div class='extras'><b>更多表达:</b> %s</div>" % ", ".join(
                    w["word"] for w in z["extra_words"]))
        sents = " / ".join(s["english"] for s in lesson.get("sentences", []))
        tips = " ｜ ".join(lesson.get("culture_tips_zh", []))
        parts.append("<div class='extras'><b>句型:</b> %s</div>" % sents)
        parts.append("<div class='extras'><b>贴士:</b> %s</div>" % tips)
    parts.append("</body></html>")
    out = os.path.join(LESSONS_DIR, "review_%s.html" % country)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print("📄 review page: %s" % out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", help="single lesson id")
    parser.add_argument("--country", help="single country")
    parser.add_argument("--review-only", action="store_true")
    args = parser.parse_args()

    if args.review_only:
        for cc in ([args.country] if args.country else COUNTRIES):
            build_review_page(cc)
        return

    pattern = os.path.join(LESSONS_DIR, args.country or "*", args.lesson or "lesson_*", "lesson.json")
    files = sorted(glob.glob(pattern))
    if not files:
        print("❌ no lesson.json found for %s" % pattern)
        sys.exit(1)

    countries_touched = set()
    for fp in files:
        try:
            process_lesson(fp)
            with open(fp, "r", encoding="utf-8") as f:
                countries_touched.add(json.load(f)["country"])
        except Exception as e:
            print("   ❌ error: %s" % e)

    for cc in countries_touched:
        build_review_page(cc)
    print("\n🎉 image generation complete")


if __name__ == "__main__":
    main()
