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
from theme_catalog import THEME_CATEGORIES

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
# 低于该置信度的点 → 整板进人工审阅队列（审阅页置顶 + 红框）。
# 82 课 ≈ 180 板无法全人工核验，靠这个把要看的收敛到 10-15%。
CONFIDENCE_THRESHOLD = 0.8

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
}

# 伪国家 daily（日常词汇主题板）的展示元数据（review 页用）
DAILY_META = {"zh": "日常词汇", "flag": "📖"}


def country_meta(cc):
    return COUNTRIES.get(cc, DAILY_META)


def is_vignette_board(board_type):
    """小图格板：一个词一格小图，而不是一张铺排图上摆物体。
    action = 动词（chop / fry），state = 形容词或状态（happy / under / heavy）。
    两者的生图、定位、回验都走同一套「找出演示这个词的那一格」逻辑，只有出词的
    prompt 不同（在 generate_lessons 里分流）。"""
    return board_type in ("action", "state")


def theme_palette(category):
    """主题图解板底色：一个大类一套色系（同生活场景「一国一色」），
    色系定义在 theme_catalog.THEME_CATEGORIES[category]["palette"]。
    ⚠️ 只染背景，物体保持真实自然色；且绝不能在 prompt 里写具体物体举例——
    生图模型会把例子画进图里（曾把 "a banana is yellow" 的香蕉画进身体部位板）。"""
    family = (THEME_CATEGORIES.get(category) or {}).get("palette") or "pale-aqua and soft teal"
    return ("light airy %s tinted background; every depicted item keeps its natural "
            "true-to-life colors — only the background is tinted, " % family) + _BRIGHT

HARD_RULES = (
    " ABSOLUTE RULES: Keep text in the image minimal. Any text that does appear MUST be a "
    "correctly spelled real English word relevant to the scene (e.g. PHARMACY, SALE) — "
    "never gibberish, never made-up letter sequences. NO real brand logos or trademarks. "
    "Every listed object must be drawn large enough to be clearly recognizable, fully "
    "visible, and NOT overlapping with other listed objects. Spread the listed objects "
    "across the scene."
)

# 主题图解板：App 会在热点坐标上叠加自己的可点词标签，图内不能再画「给物体命名的
# 文字」（否则双重标签，且图内词可能与 GPT 选词不一致）。
# ⚠️ 但物体自带的文字/数字是内容本身，必须允许：钟面数字、价签上的价格、门牌号、
# 出租车上的 TAXI —— 「数字与时间」「生活中的数字」这类课没有数字就废了。
DAILY_HARD_RULES = (
    " ABSOLUTE RULES: Do NOT write labels or captions naming the items — the app overlays "
    "its own interactive labels, so never print an item's name beside it, and no title. "
    "Text that is naturally part of an object is expected and welcome: numbers on a clock "
    "face or calendar, digits on a price tag or house number, a destination word on a sign. "
    "NO brand logos, trademarks, swooshes, stripes or any other mark resembling a real "
    "brand — draw every item plain and unbranded. Every listed item must be drawn large "
    "enough to be clearly recognizable, fully visible, and NOT overlapping with other "
    "listed items. Spread the listed items across the board."
)


def generate_scene_image(zone, lesson, hotspot_words, output_path, variation=0, palette=None):
    """DALL-E 生成一张分区场景插画。variation 用于重试时改变构图措辞。
    palette 可覆盖国家默认色调（预览/调色用）。
    主题课（country=daily）走图解词典板 prompt：词典式铺排而非环境场景，
    底色按所属大类取（一个 chip 分类一套色）。"""
    if not palette:
        if lesson["country"] == "daily":
            palette = theme_palette(lesson.get("category"))
        else:
            palette = COUNTRY_PALETTES.get(lesson["country"], DEFAULT_PALETTE)
    objects = ", ".join(w["word"] for w in hotspot_words)
    variation_hint = "" if variation == 0 else (
        " Alternative composition attempt %d: use a wider camera angle and place each object "
        "on its own clear surface or area so every object is unmistakable." % variation
    )
    if lesson["country"] == "daily" and is_vignette_board(lesson.get("board_type")):
        # 小图格板：每个词一格（动作=有人在做，状态=画面体现那个状态），
        # 格与格之间留白分开，这样每个词都能被视觉模型独立定位成热点。
        if lesson.get("board_type") == "state":
            kind, shows = "STATES", (
                "Each vignette makes that one word unmistakable from the picture alone — a "
                "feeling from a face and posture, a spatial word from where an object sits "
                "relative to another, a size or degree word from an obvious visual contrast. "
            )
        else:
            kind, shows = "ACTIONS", (
                "Each vignette shows hands or a person clearly performing that one action, "
                "drawn so the action is unmistakable at a glance. "
            )
        prompt = (
            STYLE_TEMPLATE.format(palette=palette)
            + "Visual dictionary board of %s: %s — %s. " % (kind, zone["name_en"], lesson["title_en"])
            + "Draw each one as its OWN separate vignette, laid out in a clean grid with "
            + "generous empty space between vignettes — never merge them into one scene. "
            + shows
            + "Every vignette must look obviously different from the others. "
            + "One vignette each, in this order: %s." % objects
            + variation_hint
            + DAILY_HARD_RULES
        )
    elif lesson["country"] == "daily":
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


def _vision_json(prompt, b64_image):
    """一次 GPT-4o vision 调用，返回解析后的 JSON（失败返回 None）。"""
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
                        {"type": "image_url", "image_url": {"url": "data:image/png;base64,%s" % b64_image}},
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
            return None
        content = response.json()["choices"][0]["message"]["content"].strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[1].rsplit("```", 1)[0]
        try:
            return json.loads(content.strip())
        except json.JSONDecodeError:
            print("      ⚠️ vision returned non-JSON, retrying")
            continue
    return None


def locate_words(image_path, words, board_type="object"):
    """GPT-4o vision 定位每个词，返回 {word: {found, x, y}}。坐标归一化 0-1。
    用紧致边界框取中心（比直接猜点准），对身体/五官这类"整体的局部"强调贴准部位。
    动作板（board_type="action"）定位的是"演示该动词的那格小图"而非物体。"""
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    word_list = "\n".join("- %s" % w for w in words)
    if is_vignette_board(board_type):
        match_on = (
            "Match by the state or relation the picture conveys, not by the objects present — "
            "'under' is the vignette where one thing sits beneath another, whatever the things "
            "are; 'tired' is the one whose face and posture show it."
            if board_type == "state" else
            "Match by what is being DONE, not by the objects present — 'chop' is the vignette "
            "where a knife is cutting, wherever it sits."
        )
        what = (
            "This illustration is a grid of vignettes, each conveying one word. "
            "For EACH word listed below, find the vignette that depicts it and give a "
            "TIGHT bounding box around that vignette in normalized coordinates "
            "(x_min, y_min, x_max, y_max; x from 0.0 left to 1.0 right, y from 0.0 top to 1.0 "
            "bottom). %s Mark found=false if no vignette clearly conveys that "
            "word.\n\nWords:\n%s\n\n" % (match_on, word_list)
        )
    else:
        what = (
            "This is a flat illustration. For EACH item listed below, decide if it is clearly "
            "visible in the image. If visible, give a TIGHT bounding box in normalized coordinates "
            "(x_min, y_min, x_max, y_max; x from 0.0 left to 1.0 right, y from 0.0 top to 1.0 bottom). "
            "The box must cover exactly that item and nothing else. "
            "If the items are parts of one whole (body parts, face features), anchor each box "
            "precisely ON that specific part: 'shoulder' is only the small joint area between neck "
            "and upper arm (NOT the torso), 'hand' is only the hand, 'chest' is the upper torso "
            "(NOT the belly).\n\nItems:\n%s\n\n" % word_list
        )
    prompt = (
        what
        + "Output STRICT JSON only:\n"
        '{"objects": [{"word": "...", "found": true, "x_min": 0.31, "y_min": 0.42, "x_max": 0.45, "y_max": 0.58}, '
        '{"word": "...", "found": false, "x_min": 0, "y_min": 0, "x_max": 0, "y_max": 0}]}'
    )
    parsed = _vision_json(prompt, b64)
    if not parsed:
        return {}
    result = {}
    for obj in parsed.get("objects", []):
        w = (obj.get("word") or "").lower()
        try:
            cx = (float(obj.get("x_min") or 0) + float(obj.get("x_max") or 0)) / 2
            cy = (float(obj.get("y_min") or 0) + float(obj.get("y_max") or 0)) / 2
        except (TypeError, ValueError):
            continue
        result[w] = {
            "found": bool(obj.get("found")),
            "x": min(max(cx, CLAMP_X[0]), CLAMP_X[1]),
            "y": min(max(cy, CLAMP_Y[0]), CLAMP_Y[1]),
        }
    return result


def verify_and_fix_locations(image_path, placed, max_rounds=2, board_type="object"):
    """标注回验：把已定位的点画到图上编号，让视觉模型逐个检查是否落在正确物体上，
    错的按返回坐标修正。直接消灭"肩膀的点标到肚子上"这类偏移。placed 原地修改。

    每个点带回 confidence（写入 w["_conf"]，上传前由 strip 掉）：最后一轮里任一点
    < CONFIDENCE_THRESHOLD 的板会进人工审阅队列 —— 82 课 ≈ 180 板没法全人工核验，
    靠置信度把要看的收敛到 10-15%。返回 (min_conf, low_conf_words)。"""
    from PIL import Image, ImageDraw, ImageFont

    min_conf, low_words = 1.0, []
    for round_i in range(max_rounds):
        img = Image.open(image_path).convert("RGB")
        draw = ImageDraw.Draw(img)
        W, H = img.size
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", max(22, W // 60))
        except OSError:
            try:
                font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", max(22, W // 60))
            except OSError:
                font = ImageFont.load_default()
        r = max(7, W // 160)
        for i, w in enumerate(placed, 1):
            cx, cy = w["x"] * W, w["y"] * H
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(230, 30, 30), outline="white", width=3)
            draw.text((cx + r + 4, cy - r - 4), str(i), fill=(230, 30, 30), font=font)
        import io
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=88)
        b64 = base64.b64encode(buf.getvalue()).decode()

        legend = "\n".join("%d = %s" % (i, w["word"]) for i, w in enumerate(placed, 1))
        if is_vignette_board(board_type):
            rule = (
                "This illustration is a grid of vignettes, each conveying one word. Every "
                "numbered red marker must sit on the vignette that depicts the word it labels "
                "(legend below). Judge by what the picture conveys, not by the objects present "
                + ("— a 'tired' marker on the vignette showing an excited face is wrong, an "
                   "'under' marker on the one where the ball sits on top is wrong.\n\n"
                   if board_type == "state" else
                   "— a 'chop' marker on the vignette where something is being peeled is "
                   "wrong.\n\n")
            )
        else:
            rule = (
                "This illustration has numbered red dot markers. Each marker must sit exactly ON "
                "the item it labels (legend below). Judge STRICTLY — for body/face parts the dot "
                "must be on that specific anatomical part (a 'shoulder' dot on the belly is wrong; "
                "a 'nail' dot floating next to the fingertip is wrong).\n\n"
            )
        prompt = (
            rule
            + "Legend:\n%s\n\n"
            "For EACH marker: ok=true if it clearly sits on the correct item; otherwise ok=false "
            "with the corrected normalized center (x, y) of the correct item. If the image shows "
            "several instances of the item (e.g. multiple hands), you may point to whichever "
            "instance is furthest from other markers.\n"
            "Also give confidence 0.0-1.0 that the marker (after your correction, if any) sits "
            "on the correct item. Be honest — low confidence flags the board for human review.\n"
            "Output STRICT JSON only:\n"
            '{"markers": [{"index": 1, "ok": true, "x": 0, "y": 0, "confidence": 0.95}, '
            '{"index": 2, "ok": false, "x": 0.62, "y": 0.31, "confidence": 0.7}]}' % legend
        )
        parsed = _vision_json(prompt, b64)
        if not parsed:
            return min_conf, low_words
        fixes = 0
        min_conf, low_words = 1.0, []
        for m in parsed.get("markers", []):
            try:
                idx = int(m.get("index")) - 1
            except (TypeError, ValueError):
                continue
            if not (0 <= idx < len(placed)):
                continue
            try:
                conf = float(m.get("confidence"))
            except (TypeError, ValueError):
                conf = 1.0
            placed[idx]["_conf"] = round(conf, 2)
            min_conf = min(min_conf, conf)
            if conf < CONFIDENCE_THRESHOLD:
                low_words.append("%s(%.2f)" % (placed[idx]["word"], conf))
            if m.get("ok"):
                continue
            try:
                nx, ny = float(m.get("x")), float(m.get("y"))
            except (TypeError, ValueError):
                continue
            placed[idx]["x"] = round(min(max(nx, CLAMP_X[0]), CLAMP_X[1]), 4)
            placed[idx]["y"] = round(min(max(ny, CLAMP_Y[0]), CLAMP_Y[1]), 4)
            fixes += 1
        if fixes:
            print("      🎯 verify round %d: fixed %d marker(s)" % (round_i + 1, fixes))
        if not fixes:
            break
    return min_conf, low_words


def audit_image_content(image_path):
    """图内合规审计，只拦两类硬伤：
      1. 给物体命名的标签/标题 —— App 自己叠可点标签，图内再写词会双重标注
      2. 商标/近似商标 —— 曾生成出带 Nike 勾的运动鞋
    ⚠️ 物体自带的文字数字（钟面数字、价签、门牌号、TAXI 字样）是内容本身，不算违规
    —— 一刀切禁文字会把「数字与时间」这类课的核心内容误杀。
    返回 (clean: bool, reason: str)。"""
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    prompt = (
        "Audit this illustration for two problems:\n"
        "1. LABEL TEXT: a word printed next to an object that NAMES it (like 'apple' written "
        "under an apple), or a title/caption/heading for the whole image.\n"
        "   IMPORTANT — these are NOT label text, report them as false: numbers on a clock "
        "face or calendar, digits on a price tag, receipt or house number, a word naturally "
        "printed on a real object (TAXI on a taxi, EXIT on a door), squiggles that aren't "
        "readable words.\n"
        "2. BRANDING: a real-brand logo, or a mark that resembles one (swoosh, three stripes, "
        "bitten apple, golden arches). A plain unbranded object is fine.\n"
        'Output STRICT JSON only:\n{"has_label_text": false, "has_brand": false, "detail": ""}'
    )
    parsed = _vision_json(prompt, b64)
    if not parsed:
        return True, ""  # 审计失败不阻断生成
    problems = []
    if parsed.get("has_label_text"):
        problems.append("label")
    if parsed.get("has_brand"):
        problems.append("brand")
    if not problems:
        return True, ""
    return False, "%s: %s" % ("+".join(problems), (parsed.get("detail") or "")[:80])


def spread_close_labels(words, min_sep=MIN_LABEL_SEP, iterations=60, max_shift=None):
    """把坐标过近的标签沿连线对称推开，避免 App 里两个词叠在一起。
    words: 含 x/y 的 dict 列表（原地修改）。
    max_shift: 每个点离初始位置的最大位移（归一化距离）。人体/五官这类热点密集的
    图解板必须限制位移，否则"肩膀"会被推到肚子上——准确性优先于标签不重叠。"""
    if len(words) < 2:
        return 0
    orig = [(w["x"], w["y"]) for w in words]

    def clamp_shift(idx):
        if max_shift is None:
            return
        w = words[idx]
        ox, oy = orig[idx]
        dx, dy = w["x"] - ox, w["y"] - oy
        d = (dx * dx + dy * dy) ** 0.5
        if d > max_shift:
            scale = max_shift / d
            w["x"] = min(max(ox + dx * scale, CLAMP_X[0]), CLAMP_X[1])
            w["y"] = min(max(oy + dy * scale, CLAMP_Y[0]), CLAMP_Y[1])

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
                clamp_shift(i)
                clamp_shift(j)
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

    # 选图排序：先看合规（审计过没过），再看定位命中数。
    # 早先版本是「最后一次尝试的图直接用」—— 带 BOIL/FRY 标签的板就这么漏上线了。
    # 但审计本身会误报（干净的动作板被说成有标签），所以不硬失败：
    # 有干净的版本就绝不用被拒的版本，全被拒才退而求其次并标记待人工核验。
    best = None  # ((clean, located_count), located_map)
    for attempt in range(MAX_IMAGE_ATTEMPTS):
        if attempt > 0 or not os.path.exists(image_path):
            print("      🖼  generating image (attempt %d)..." % (attempt + 1))
            if not generate_scene_image(zone, lesson, hotspots, image_path, variation=attempt):
                continue
        clean = True
        if lesson["country"] == "daily":
            clean, reason = audit_image_content(image_path)
            if not clean:
                print("      🚫 rejected (%s)" % reason)
        located = locate_words(image_path, [w["word"] for w in hotspots],
                               board_type=lesson.get("board_type", "object"))
        found = [w for w in hotspots if located.get(w["word"].lower(), {}).get("found")]
        print("      📍 located %d/%d hotspots%s" % (
            len(found), len(hotspots), "" if clean else " (审计未过)"))
        score = (1 if clean else 0, len(found))
        if best is None or score > best[0]:
            best = (score, located)
            shutil.copyfile(image_path, image_path + ".best")
        if clean and len(found) == len(hotspots):
            break
        # 不合规或未全中 → 下一轮重新生成（换构图措辞）
        if attempt < MAX_IMAGE_ATTEMPTS - 1:
            os.remove(image_path)

    if best is None:
        print("      ❌ zone failed entirely")
        return False
    # 用最优的一版图
    if os.path.exists(image_path + ".best"):
        shutil.move(image_path + ".best", image_path)
    if not best[0][0]:
        print("      ⚠️  所有版本都没过审计，已用命中最多的一版 —— 需人工核验")
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
    # 主题图解板（daily）热点密集：更小的目标间距 + 更紧的位移上限，准确性优先
    # （标签重叠是小瑕疵，点标错部位是硬伤）
    dense = lesson["country"] == "daily"
    min_sep = 0.07 if dense else MIN_LABEL_SEP
    max_shift = 0.03 if dense else 0.05
    spread_close_labels(kept, min_sep=min_sep, max_shift=max_shift)
    # 标注回验：让视觉模型检查每个点是否落在正确物体/部位上，错的修正 + 打置信度
    try:
        _, low_words = verify_and_fix_locations(
            image_path, kept, board_type=lesson.get("board_type", "object"))
    except Exception as e:
        print("      ⚠️  verify pass failed: %s" % e)
        low_words = []
    if low_words:
        print("      🔍 needs review: %s" % ", ".join(low_words))
    # 修正后再轻推一次（更小位移上限），避免修正点重新叠上其它标签
    remaining = spread_close_labels(kept, min_sep=min_sep, max_shift=0.02)
    if remaining:
        print("      ⚠️  %d label pair(s) still under %.2f after spreading" % (remaining, min_sep))
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
        # 本地文件名固定 {zone_id}.jpg（OSS 端文件名带内容哈希，basename 对不上本地）
        if zone.get("image") and os.path.exists(os.path.join(lesson_dir_abs, "%s.jpg" % zone["id"])):
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
.dot.low{border-color:#dc2626;background:#fee2e2;color:#991b1b;border-width:3px}
.dot.low::before{border-top-color:#dc2626}
.extras{font-size:13px;color:#444;margin:4px 0 16px} .extras b{color:#b45309}
.meta{font-size:12px;color:#999}
.banner{background:#fef3c7;border-left:4px solid #f59e0b;padding:10px 14px;margin:16px 0;
border-radius:6px;font-size:14px}
.flag{background:#fee2e2;border-left:4px solid #dc2626;padding:6px 12px;margin:4px 0;
border-radius:6px;font-size:13px;color:#991b1b;display:inline-block}
"""


def _zone_low_words(zone):
    """该板中置信度低于阈值的词（verify 打的 _conf）。"""
    return [w for w in zone["hotspots"]
            if w.get("_conf") is not None and w["_conf"] < CONFIDENCE_THRESHOLD]


def build_review_page(country):
    files = sorted(glob.glob(os.path.join(LESSONS_DIR, country, "lesson_*", "lesson.json")))
    if not files:
        print("no lessons for %s" % country)
        return

    # 待审阅（有低置信度点）的课排在最前 —— 规模化后人工只看这批
    lessons = []
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            lessons.append((fp, json.load(f)))

    def low_count(lesson):
        return sum(len(_zone_low_words(z)) for z in lesson["zones"])

    lessons.sort(key=lambda t: (-low_count(t[1]), t[1]["id"]))
    flagged = sum(1 for _, l in lessons if low_count(l))

    parts = ["<html><head><meta charset='utf-8'><style>%s</style></head><body>" % REVIEW_CSS]
    meta = country_meta(country)
    parts.append("<h1>%s %s — 词汇小课堂标注审阅（%d 课）</h1>" % (
        meta["flag"], meta["zh"], len(files)))
    if flagged:
        parts.append("<div class='banner'>⚠️ <b>%d 课</b>有低置信度标注（&lt; %.2f），已置顶，"
                     "红框即问题点 —— 只需人工核验这些。</div>" % (flagged, CONFIDENCE_THRESHOLD))
    else:
        parts.append("<div class='banner'>✅ 全部标注置信度达标，无需人工核验。</div>")

    for fp, lesson in lessons:
        rel_dir = os.path.relpath(os.path.dirname(fp), LESSONS_DIR)
        n_low = low_count(lesson)
        parts.append("<h2>%s%s <span class='zh'>%s · %d 词 · %s</span></h2>" % (
            "🔍 " if n_low else "", lesson["title_zh"], lesson["title_en"],
            lesson.get("word_count", 0), lesson["id"]))
        for z in lesson["zones"]:
            img_file = os.path.basename(z.get("image") or "")
            if not img_file:
                parts.append("<p class='meta'>zone %s: ❌ 无图</p>" % z["id"])
                continue
            parts.append("<div class='meta'>%s %s</div>" % (z["name_zh"], z["name_en"]))
            low = _zone_low_words(z)
            if low:
                parts.append("<div class='flag'>待核验: %s</div>" % ", ".join(
                    "%s (%.2f)" % (w["word"], w["_conf"]) for w in low))
            parts.append("<div class='zone'><img src='%s/%s'>" % (rel_dir, img_file))
            for w in z["hotspots"]:
                is_low = w.get("_conf") is not None and w["_conf"] < CONFIDENCE_THRESHOLD
                parts.append("<span class='dot%s' style='left:%.1f%%;top:%.1f%%'>%s</span>" % (
                    " low" if is_low else "", w["x"] * 100, w["y"] * 100, w["word"]))
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
    print("📄 review page: %s  (%d/%d 课待核验)" % (out, flagged, len(files)))


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
