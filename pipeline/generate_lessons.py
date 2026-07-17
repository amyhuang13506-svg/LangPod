# -*- coding: utf-8 -*-
"""
词汇小课堂 Step 1: GPT 生成课堂内容 JSON（词表 + 例句 + 句型 + 文化贴士）。

用法:
  python3 generate_lessons.py --lesson lesson_us_otc_meds   # 单个课堂
  python3 generate_lessons.py --country us                  # 一个国家
  python3 generate_lessons.py --country daily               # 日常词汇主题课（theme_catalog）
  python3 generate_lessons.py                               # 全量（跳过已存在）

输出: output/lessons/{country}/{lesson_id}/lesson.json（中间态，无坐标无图）
主题课走 output/lessons/daily/…，culture_tips_zh 定位为「用法小贴士」。
"""

import argparse
import json
import os
import re
import sys
import time

import requests

from config import GPT_API_ENDPOINT, GPT_API_KEY, GPT_MODEL, OUTPUT_DIR
from lesson_catalog import COUNTRIES, all_lessons
from theme_catalog import all_theme_lessons

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")

PROMPT_TEMPLATE = """You are creating content for a "scene vocabulary mini-lesson" in an English-learning app for Chinese speakers. The lesson teaches REAL survival English for a specific moment of life in {country_context}

LESSON: {title_en} ({title_zh})
Scene anchor: {anchor}

The lesson has {zone_count} zones. For each zone you must produce:
1. "hotspots": 5-8 CONCRETE PHYSICAL OBJECTS that would be clearly visible in an illustration of this zone (things an artist can draw and a viewer can point at: passport, shopping cart, pill bottle). NOT actions, NOT abstract concepts.
2. "extra_words": 3-6 verbs, phrases, or abstract expressions used in this zone that CANNOT be drawn (check in, out of stock, for here or to go).

ZONES:
{zones_block}

Also produce for the whole lesson:
- "sentences": 5 sentences the learner will actually SAY or HEAR in this scene. Real spoken register, not textbook style.
- "culture_tips_zh": 2-3 survival tips in Chinese. Practical "insider knowledge" (how much to tip, what NOT to do, what locals actually say) — never encyclopedia facts.

RULES (all mandatory):
- Spelling/vocabulary: use {spelling}. Use the words locals ACTUALLY use in this country (e.g. trolley vs cart, chemist vs pharmacy).
- Every word entry: "word" (lowercase unless proper noun), "phonetic" (IPA with slashes like /ˈpæspɔːrt/), "translation_zh" (1-2 个中文释义), "example" (one natural sentence a real person would say in THIS scene, MUST contain the word, MAX 12 words), "example_zh" (自然的中文翻译), "difficulty" ("easy"|"medium"|"hard" by real-world frequency).
- Brand-specific or local words (venti, paracetamol, EFTPOS) are ENCOURAGED — they are the point of this app. Mark them medium/hard.
- Order words within each zone from easy to hard.
- No word may repeat across zones in this lesson.
- Chinese translations must be natural spoken Chinese, not dictionary-stiff.
- sentences: each is {{"english": "...", "chinese": "..."}}.
- Do NOT include any political, religious or sensitive content.

Output STRICT JSON only (no markdown fences, no commentary):
{{
  "zones": [
    {{
      "id": "<zone id exactly as given>",
      "hotspots": [ {{"word": "...", "phonetic": "...", "translation_zh": "...", "example": "...", "example_zh": "...", "difficulty": "easy"}} ],
      "extra_words": [ {{...same fields...}} ]
    }}
  ],
  "sentences": [ {{"english": "...", "chinese": "..."}} ],
  "culture_tips_zh": ["...", "..."]
}}"""


THEME_PROMPT_TEMPLATE = """You are creating content for a "visual dictionary board" in an English-learning app for Chinese speakers. The lesson teaches CORE everyday vocabulary by theme (like a picture dictionary spread) — not tied to any country or situation.

LESSON: {title_en} ({title_zh})

The lesson has {zone_count} boards. For each board you must produce:
1. "hotspots": 6-8 CONCRETE items that would be clearly visible in a picture-dictionary illustration of this board (things an artist can draw and a viewer can point at). For body/face boards the items are parts of one drawn figure. NOT actions, NOT abstract concepts.
2. "extra_words": 3-6 verbs, phrases, or expressions that belong to this theme but CANNOT be drawn (stretch, half past, a pair of).

BOARDS:
{zones_block}

Also produce for the whole lesson:
- "sentences": 5 short sentences a learner would actually SAY in daily life using these words. Real spoken register, not textbook style.
- "culture_tips_zh": 2-3 用法小贴士 in Chinese. EVERY tip must be about a word that actually appears in THIS lesson's word list, and must name that word. Useful angles: where English splits a word that Chinese doesn't (or the reverse), the collocation or measure word a Chinese learner gets wrong, a false friend, a word pair that looks interchangeable but isn't. NEVER encyclopedia facts. NEVER reuse an example word from these instructions — write tips about this lesson's own words only.

RULES (all mandatory):
- Spelling/vocabulary: American English. Pick the HIGHEST-FREQUENCY everyday word for each item (pants not trousers).
- Every word entry: "word" (lowercase unless proper noun), "phonetic" (IPA with slashes like /ˈfɪŋɡɚ/), "translation_zh" (1-2 个中文释义), "example" (one natural sentence a real person would say in daily life, MUST contain the word, MAX 12 words), "example_zh" (自然的中文翻译), "difficulty" ("easy"|"medium"|"hard" by real-world frequency).
- Order words within each board from easy to hard.
- No word may repeat across boards in this lesson.
- Chinese translations must be natural spoken Chinese, not dictionary-stiff.
- sentences: each is {{"english": "...", "chinese": "..."}}.
- Do NOT include any political, religious or sensitive content.

Output STRICT JSON only (no markdown fences, no commentary):
{{
  "zones": [
    {{
      "id": "<zone id exactly as given>",
      "hotspots": [ {{"word": "...", "phonetic": "...", "translation_zh": "...", "example": "...", "example_zh": "...", "difficulty": "easy"}} ],
      "extra_words": [ {{...same fields...}} ]
    }}
  ],
  "sentences": [ {{"english": "...", "chinese": "..."}} ],
  "culture_tips_zh": ["...", "..."]
}}"""


def _call_gpt(messages, temperature=0.7):
    """GPT call with retry for transient errors, parses JSON (same pattern as generate_script.py)."""
    max_retries = 3
    for attempt in range(max_retries):
        response = requests.post(
            GPT_API_ENDPOINT,
            headers={
                "Authorization": "Bearer %s" % GPT_API_KEY,
                "Content-Type": "application/json",
            },
            json={
                "model": GPT_MODEL,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": 8000,
            },
            timeout=300,
        )
        if response.status_code in (403, 429, 500, 502, 503):
            wait = 30 * (2 ** attempt)
            print("   ⟳ GPT %d, retrying in %ds (attempt %d/%d)..." % (response.status_code, wait, attempt + 1, max_retries))
            time.sleep(wait)
            continue
        response.raise_for_status()
        break
    else:
        response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1]
    if content.endswith("```"):
        content = content.rsplit("```", 1)[0]
    return json.loads(content.strip())


def build_prompt(lesson):
    zones_block = "\n".join(
        '- id "%s" — %s (%s): %s' % (z["id"], z["en"], z["zh"], z["hint"])
        for z in lesson["zones"]
    )
    if lesson.get("is_theme"):
        return THEME_PROMPT_TEMPLATE.format(
            title_en=lesson["title_en"],
            title_zh=lesson["title_zh"],
            zone_count=len(lesson["zones"]),
            zones_block=zones_block,
        )
    country = COUNTRIES[lesson["country"]]
    return PROMPT_TEMPLATE.format(
        country_context=country["context"],
        title_en=lesson["title_en"],
        title_zh=lesson["title_zh"],
        anchor=lesson["anchor"],
        zone_count=len(lesson["zones"]),
        zones_block=zones_block,
        spelling=country["spelling"],
    )


def validate_content(lesson, content):
    """自动质检：结构、词数、例句含词。返回问题列表（空 = 通过）。"""
    problems = []
    zones = content.get("zones", [])
    expected_ids = [z["id"] for z in lesson["zones"]]
    got_ids = [z.get("id") for z in zones]
    if got_ids != expected_ids:
        problems.append("zone ids mismatch: expected %s got %s" % (expected_ids, got_ids))
        return problems

    seen_words = set()
    for z in zones:
        hs = z.get("hotspots", [])
        if not (4 <= len(hs) <= 9):
            problems.append("zone %s: %d hotspots (want 5-8)" % (z["id"], len(hs)))
        for w in hs + z.get("extra_words", []):
            for field in ("word", "phonetic", "translation_zh", "example", "example_zh", "difficulty"):
                if not w.get(field):
                    problems.append("zone %s word %s missing %s" % (z["id"], w.get("word"), field))
            word = (w.get("word") or "").lower()
            if word in seen_words:
                problems.append("duplicate word across zones: %s" % word)
            seen_words.add(word)
            # 例句必须含目标词（宽松匹配：词干前 4 个字符）
            example = (w.get("example") or "").lower()
            stem = word.split()[0][:4] if word else ""
            if stem and stem not in example:
                problems.append("zone %s: example for '%s' doesn't contain the word" % (z["id"], word))
            if w.get("difficulty") not in ("easy", "medium", "hard"):
                problems.append("zone %s: bad difficulty for '%s'" % (z["id"], word))

    if len(content.get("sentences", [])) < 4:
        problems.append("only %d sentences (want 5)" % len(content.get("sentences", [])))
    tips = content.get("culture_tips_zh", [])
    if len(tips) < 2:
        problems.append("only %d culture tips (want 2-3)" % len(tips))
    # 贴士必须讲本课的词。GPT 会把 prompt 里的举例照抄进无关课（厨房课讲 hand vs arm、
    # 到处都是 a pair of jeans）—— 同「香蕉画进身体部位板」一类的举例泄漏。
    # 判据：贴士里的英文词至少有一个出现在本课词表（逐词比 + 去复数尾，
    # 'a cup of tea' 能匹配 'tea bag'、'apples' 能匹配 'apple'）。
    def _norm(w):
        for suf in ("ies", "es", "s"):
            if w.endswith(suf) and len(w) - len(suf) >= 3:
                return w[:-len(suf)] + ("y" if suf == "ies" else "")
        return w

    vocab = set()
    for w in seen_words:
        vocab.update(_norm(t) for t in re.findall(r"[a-zA-Z]{3,}", w.lower()))
    for tip in tips:
        tokens = {_norm(t) for t in re.findall(r"[a-zA-Z]{3,}", tip.lower())}
        if tokens and not (tokens & vocab):
            problems.append("tip cites no word from this lesson (prompt example leak?): %s" % tip[:40])
    return problems


def generate_lesson_content(lesson, max_attempts=2):
    """生成一个课堂的内容 JSON。返回完整 lesson dict 或 None。"""
    prompt = build_prompt(lesson)
    for attempt in range(max_attempts):
        try:
            content = _call_gpt([{"role": "user", "content": prompt}])
        except Exception as e:
            print("   ❌ GPT error: %s" % e)
            continue
        problems = validate_content(lesson, content)
        if not problems:
            zones_out = []
            zone_meta = {z["id"]: z for z in lesson["zones"]}
            for z in content["zones"]:
                meta = zone_meta[z["id"]]
                zones_out.append({
                    "id": z["id"],
                    "name_zh": meta["zh"],
                    "name_en": meta["en"],
                    "image": "",  # 生图步骤填充
                    "hotspots": z["hotspots"],
                    "extra_words": z["extra_words"],
                })
            word_count = sum(len(z["hotspots"]) + len(z["extra_words"]) for z in zones_out)
            return {
                "id": lesson["id"],
                "country": lesson["country"],
                "title_zh": lesson["title_zh"],
                "title_en": lesson["title_en"],
                "category": lesson["category"],
                "category_zh": lesson["category_zh"],
                "icon": lesson["icon"],
                "cover": "",
                "is_free": lesson["is_free"],
                "is_daily": False,
                "date": "",
                "word_count": word_count,
                "zones": zones_out,
                "sentences": content["sentences"][:5],
                "culture_tips_zh": content["culture_tips_zh"][:3],
            }
        print("   ⚠️  Validation failed (attempt %d): %s" % (attempt + 1, "; ".join(problems[:5])))
    return None


def lesson_dir(lesson_id, country):
    return os.path.join(LESSONS_DIR, country, lesson_id)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", help="single lesson id, e.g. lesson_us_otc_meds")
    parser.add_argument("--country", help="single country, e.g. us")
    parser.add_argument("--force", action="store_true", help="regenerate even if exists")
    args = parser.parse_args()

    targets = all_lessons() + all_theme_lessons()
    if args.lesson:
        targets = [l for l in targets if l["id"] == args.lesson]
        if not targets:
            print("❌ Unknown lesson id: %s" % args.lesson)
            sys.exit(1)
    elif args.country:
        targets = [l for l in targets if l["country"] == args.country]

    print("📚 Generating content for %d lesson(s)..." % len(targets))
    ok, fail = 0, 0
    for lesson in targets:
        out_dir = lesson_dir(lesson["id"], lesson["country"])
        out_path = os.path.join(out_dir, "lesson.json")
        if os.path.exists(out_path) and not args.force:
            print("⏭  %s (exists)" % lesson["id"])
            continue
        print("\n📝 %s — %s" % (lesson["id"], lesson["title_zh"]))
        result = generate_lesson_content(lesson)
        if result is None:
            print("   ❌ Failed after retries")
            fail += 1
            continue
        os.makedirs(out_dir, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print("   ✅ %d words → %s" % (result["word_count"], out_path))
        ok += 1

    print("\n🎉 Done: %d ok, %d failed" % (ok, fail))


if __name__ == "__main__":
    main()
