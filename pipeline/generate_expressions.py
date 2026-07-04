# -*- coding: utf-8 -*-
"""
口语表达库生成：GPT 逐分类生成表达条目 + ElevenLabs 发音。

每分类 8-12 条表达，按实用频率排序（不分难度）。每条：
  english / meaning_zh / usage_zh（谁说·场合·语气）/ country_note_zh（可选，国家差异）
  examples（2 条，≤12 词）/ 发音 mp3（表达 + 例句，美音）

用法:
  python3 generate_expressions.py --category thanks     # 单分类
  python3 generate_expressions.py --group reactions     # 一个组
  python3 generate_expressions.py                       # 全量（跳过已存在）
  python3 generate_expressions.py --skip-audio          # 只生成文本（自检用）

输出: output/expressions/{category_id}.json + audio/
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time

import requests

from config import (
    ELEVENLABS_LESSON_API_KEY,
    ELEVENLABS_LESSON_MODEL,
    ELEVENLABS_LESSON_VOICES,
    GPT_API_ENDPOINT,
    GPT_API_KEY,
    GPT_MODEL,
    OUTPUT_DIR,
)
from expression_catalog import all_categories

EXPR_DIR = os.path.join(OUTPUT_DIR, "expressions")
TTS_ENDPOINT = "https://api.elevenlabs.io/v1/text-to-speech/%s"
VOICE_ID = ELEVENLABS_LESSON_VOICES["us"]  # 美音为主，国家差异在文字注释里

PROMPT_TEMPLATE = """You are building a spoken-English expression library for Chinese learners. The app's promise: everything is REAL spoken English that natives say daily — practical, casual-register accurate, immediately usable. NOT textbook English.

CATEGORY: {cat_zh} — {hint}

Produce 8-12 expressions for this category, ordered by how often natives actually use them (most common first).

Each expression:
- "english": the expression as actually spoken (a phrase, a fill-in pattern, or a short sentence).
  For any open slot / trailing "to be continued" gap, ALWAYS use exactly three underscores `___` — NEVER use "..." or the ellipsis character "…". (e.g. write "I guess ___" not "I guess...", "So you're saying ___" not "So you're saying ...")
- "meaning_zh": 中文意思（口语化，一句话）
- "usage_zh": 语感注释（1-2 句中文）：谁会说、什么场合、什么语气、和相近说法差在哪。这是本 app 和词典的区别，必须具体到"画面感"。
- "country_note_zh": 国家差异注释（可选）。只在美/英/澳等真的说法不同时才写（如"英国人更常说 Cheers；澳洲人张口就是 No worries"）。没有明显差异就输出空字符串。
- "examples": exactly 2, each {{"en": "... (MAX 12 words, real spoken register)", "zh": "自然中文翻译"}}
- "scene": 场景示例——一个具体的生活时刻里这句话怎么被用出来：
  {{"setup_zh": "1-2 句中文描述具体场景（谁、在哪、发生了什么，要有画面感）",
    "dialogue": [{{"speaker": "A", "en": "...", "zh": "..."}}, {{"speaker": "B", "en": "...", "zh": "..."}}]}}
  dialogue 恰好 2 句（一来一回），其中一句必须自然地用到本表达；每句 ≤14 words。

RULES:
- Real current usage only. If an expression sounds like a 1990s textbook (e.g. "How do you do"), skip it.
- Include how to RESPOND where natural (寒暄/感谢类尤其需要).
- usage_zh 必须口语化中文，禁止"该表达用于……的语境"这种论文腔。
- No political/religious/vulgar content (mild casual slang is fine).

Output STRICT JSON only:
{{"expressions": [{{"english": "...", "meaning_zh": "...", "usage_zh": "...", "country_note_zh": "", "examples": [{{"en": "...", "zh": "..."}}, {{"en": "...", "zh": "..."}}], "scene": {{"setup_zh": "...", "dialogue": [{{"speaker": "A", "en": "...", "zh": "..."}}, {{"speaker": "B", "en": "...", "zh": "..."}}]}}}}]}}"""

# 存量补充：给已生成的表达补 scene 字段（不动已有内容和音频）
AUGMENT_PROMPT = """You are adding "scene examples" to an existing spoken-English expression library for Chinese learners.

For EACH expression below, create one vivid real-life scene showing the expression being used:
- "setup_zh": 1-2 句中文，描述具体场景（在哪、发生了什么），用"你"的视角写（"你刚点完咖啡，看到老同学走进来"），有画面感，禁止"小明/小红"式教材人名
- "dialogue": exactly 2 turns (A then B), one turn MUST naturally use the expression; each line ≤14 words, real spoken register; each turn {{"speaker": "A"|"B", "en": "...", "zh": "自然中文翻译"}}

EXPRESSIONS ({cat_zh}):
{expr_list}

Output STRICT JSON only:
{{"scenes": [{{"english": "<expression exactly as given>", "setup_zh": "...", "dialogue": [{{"speaker": "A", "en": "...", "zh": "..."}}, {{"speaker": "B", "en": "...", "zh": "..."}}]}}]}}"""

AUGMENT_EXAMPLES_PROMPT = """You are expanding an existing spoken-English expression library for Chinese learners.

For EACH expression below, write exactly 2 NEW example sentences:
- Different situations from the existing examples listed (no overlap in topic or wording)
- Each "en" MAX 12 words, real spoken register (how natives actually talk, contractions OK)
- Each has "zh": 自然中文翻译（不是直译腔）

EXPRESSIONS ({cat_zh}):
{expr_list}

Output STRICT JSON only:
{{"expressions": [{{"english": "<expression exactly as given>", "examples": [{{"en": "...", "zh": "..."}}, {{"en": "...", "zh": "..."}}]}}]}}"""

# 对话双声：A 男声 / B 女声（B 是表达使用者时也自然）
DIALOGUE_VOICES = {"A": "iP95p4xoKVk53GoZ742B", "B": ELEVENLABS_LESSON_VOICES["us"]}  # Chris / Bella


def _call_gpt(prompt):
    for attempt in range(3):
        response = requests.post(
            GPT_API_ENDPOINT,
            headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
            json={
                "model": GPT_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.8,
                "max_tokens": 6000,
            },
            timeout=300,
        )
        if response.status_code in (403, 429, 500, 502, 503):
            time.sleep(30 * (2 ** attempt))
            continue
        response.raise_for_status()
        break
    else:
        response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(content.strip())


def validate(data):
    problems = []
    exprs = data.get("expressions", [])
    if not (6 <= len(exprs) <= 14):
        problems.append("%d expressions (want 8-12)" % len(exprs))
    seen = set()
    for e in exprs:
        for field in ("english", "meaning_zh", "usage_zh"):
            if not e.get(field):
                problems.append("missing %s on %r" % (field, e.get("english")))
        key = (e.get("english") or "").lower()
        if key in seen:
            problems.append("duplicate: %s" % key)
        seen.add(key)
        examples = e.get("examples") or []
        if len(examples) < 1:
            problems.append("%s: no examples" % e.get("english"))
        for ex in examples:
            if len((ex.get("en") or "").split()) > 14:  # 宽容到 14，硬限连词成句在 App 端
                problems.append("%s: example too long" % e.get("english"))
    return problems


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")[:40]


def synthesize(text, output_path, voice_id=None):
    for attempt in range(3):
        response = requests.post(
            TTS_ENDPOINT % (voice_id or VOICE_ID),
            params={"output_format": "mp3_44100_64"},
            headers={"xi-api-key": ELEVENLABS_LESSON_API_KEY, "Content-Type": "application/json"},
            json={
                "text": text,
                "model_id": ELEVENLABS_LESSON_MODEL,
                "voice_settings": {"stability": 0.6, "similarity_boost": 0.8, "speed": 0.9},
            },
            timeout=60,
        )
        if response.status_code == 200 and response.content:
            with open(output_path, "wb") as f:
                f.write(response.content)
            return True
        if response.status_code in (429, 500, 502, 503):
            time.sleep(5 * (attempt + 1))
            continue
        print("      ❌ TTS %d: %s" % (response.status_code, response.text[:120]))
        return False
    return False


# 网络缩写：TTS 直接念缩写会瞎读（ngl→"and Mel"、lowkey→"Loki"）。
# 表达本体音频 = 先读字母再读完整口语版；例句/对话里出现时 = 直接读完整口语版。
TTS_SPOKEN = {
    "ngl": "not gonna lie",
    "tbh": "to be honest",
    "fr": "for real",
    "lowkey": "low-key",
    "highkey": "high-key",
}
TTS_EXPR_OVERRIDE = {
    "ngl": "N G L — not gonna lie",
    "tbh": "T B H — to be honest",
    "fr": "F R — for real",
    "lowkey": "low-key",
    "highkey": "high-key",
}


def tts_text(english):
    """挖空模板的 ___ 读成 something，别让 TTS 念下划线；缩写读完整口语版。"""
    t = english.replace("___", "something")
    override = TTS_EXPR_OVERRIDE.get(t.strip().lower())
    if override:
        return override
    for abbr, spoken in TTS_SPOKEN.items():
        t = re.sub(r"\b%s\b" % abbr, spoken, t, flags=re.IGNORECASE)
    return t


def process_category(cat, skip_audio=False):
    out_path = os.path.join(EXPR_DIR, "%s.json" % cat["id"])
    if os.path.exists(out_path):
        with open(out_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        print("⏭  %s (%s) exists, %d expressions" % (cat["id"], cat["zh"], len(data.get("expressions", []))))
    else:
        print("\n📝 %s — %s" % (cat["id"], cat["zh"]))
        prompt = PROMPT_TEMPLATE.format(cat_zh=cat["zh"], hint=cat["hint"])
        data = None
        for attempt in range(2):
            try:
                candidate = _call_gpt(prompt)
            except Exception as e:
                print("   ❌ GPT: %s" % e)
                continue
            problems = validate(candidate)
            if not problems:
                data = candidate
                break
            print("   ⚠️ validation (attempt %d): %s" % (attempt + 1, "; ".join(problems[:4])))
        if data is None:
            print("   ❌ failed")
            return False
        data = {
            "id": cat["id"],
            "zh": cat["zh"],
            "group_id": cat["group_id"],
            "group_zh": cat["group_zh"],
            "is_free": cat["is_free"],
            "expressions": data["expressions"],
        }
        os.makedirs(EXPR_DIR, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("   ✅ %d expressions" % len(data["expressions"]))

    if skip_audio:
        return True

    # 音频（幂等）
    audio_dir = os.path.join(EXPR_DIR, "audio", cat["id"])
    os.makedirs(audio_dir, exist_ok=True)
    made = 0

    def ensure(text, filename, obj, field):
        nonlocal made
        if (obj.get(field) or "").startswith("http"):
            return
        path = os.path.join(audio_dir, filename)
        rel = "audio/%s/%s" % (cat["id"], filename)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            obj[field] = rel
            return
        if synthesize(tts_text(text), path):
            obj[field] = rel
            made += 1
        else:
            obj[field] = ""

    def ensure_voiced(text, filename, obj, field, voice_id):
        nonlocal made
        if (obj.get(field) or "").startswith("http"):
            return
        path = os.path.join(audio_dir, filename)
        rel = "audio/%s/%s" % (cat["id"], filename)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            obj[field] = rel
            return
        if synthesize(tts_text(text), path, voice_id=voice_id):
            obj[field] = rel
            made += 1
        else:
            obj[field] = ""

    for e in data["expressions"]:
        slug = slugify(e["english"])
        ensure(e["english"], "%s.mp3" % slug, e, "audio")
        for i, ex in enumerate(e.get("examples", [])):
            ensure(ex["en"], "%s_ex%d.mp3" % (slug, i), ex, "audio")
        # 场景对话：A 男声 / B 女声。文件名带文本哈希——
        # 场景文字重新生成时哈希变化，旧音频不会被误复用（否则文字和录音会对不上）。
        for i, line in enumerate((e.get("scene") or {}).get("dialogue", [])):
            voice = DIALOGUE_VOICES.get(line.get("speaker", "A"), VOICE_ID)
            text_hash = hashlib.md5(line["en"].encode()).hexdigest()[:8]
            ensure_voiced(line["en"], "%s_sc%d_%s.mp3" % (slug, i, text_hash), line, "audio", voice)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    if made:
        print("   🔊 %d clips synthesized" % made)
    return True


def augment_scenes(cat, skip_audio=False):
    """给已生成的分类补 scene 字段（不重新生成表达本体，已有音频不动）。"""
    out_path = os.path.join(EXPR_DIR, "%s.json" % cat["id"])
    if not os.path.exists(out_path):
        return False
    with open(out_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    missing = [e for e in data["expressions"] if not e.get("scene")]
    if missing:
        print("\n🎬 %s — %s (%d 条待补场景)" % (cat["id"], cat["zh"], len(missing)))
        expr_list = "\n".join(
            "- %s (%s)" % (e["english"], e["meaning_zh"]) for e in missing
        )
        prompt = AUGMENT_PROMPT.format(cat_zh=cat["zh"], expr_list=expr_list)
        try:
            result = _call_gpt(prompt)
        except Exception as e:
            print("   ❌ GPT: %s" % e)
            return False
        by_english = {s.get("english"): s for s in result.get("scenes", [])}
        added = 0
        for e in missing:
            scene = by_english.get(e["english"])
            if not scene or len(scene.get("dialogue", [])) < 2:
                print("   ⚠️ no scene for: %s" % e["english"])
                continue
            e["scene"] = {
                "setup_zh": scene["setup_zh"],
                "dialogue": scene["dialogue"][:2],
            }
            added += 1
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("   ✅ %d scenes added" % added)
    # 补音频（幂等，复用 process_category 的音频闭环）
    return process_category(cat, skip_audio=skip_audio)


def augment_examples(cat, skip_audio=False):
    """给已生成的分类每条表达补到 4 个例句（已有 2 个不动，新增走 ex2/ex3 音频）。"""
    out_path = os.path.join(EXPR_DIR, "%s.json" % cat["id"])
    if not os.path.exists(out_path):
        return False
    with open(out_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    todo = [e for e in data["expressions"] if len(e.get("examples") or []) < 4]
    if todo:
        print("\n✏️ %s — %s (%d 条待补例句)" % (cat["id"], cat["zh"], len(todo)))
        expr_list = "\n".join(
            "- %s (%s) | existing examples: %s" % (
                e["english"], e["meaning_zh"],
                " / ".join(x["en"] for x in e.get("examples") or []) or "none",
            )
            for e in todo
        )
        prompt = AUGMENT_EXAMPLES_PROMPT.format(cat_zh=cat["zh"], expr_list=expr_list)
        try:
            result = _call_gpt(prompt)
        except Exception as e:
            print("   ❌ GPT: %s" % e)
            return False
        by_english = {s.get("english"): s for s in result.get("expressions", [])}
        added = 0
        for e in todo:
            extra = by_english.get(e["english"])
            if not extra:
                print("   ⚠️ no new examples for: %s" % e["english"])
                continue
            existing_en = {(x.get("en") or "").lower() for x in e.get("examples") or []}
            fresh = [
                x for x in extra.get("examples", [])
                if x.get("en") and x.get("zh")
                and len(x["en"].split()) <= 14
                and x["en"].lower() not in existing_en
            ]
            need = 4 - len(e.get("examples") or [])
            for x in fresh[:need]:
                e.setdefault("examples", []).append({"en": x["en"], "zh": x["zh"]})
                added += 1
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print("   ✅ %d examples added" % added)
    # 补音频（幂等：只合成缺音频的 ex2/ex3）
    return process_category(cat, skip_audio=skip_audio)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--category")
    parser.add_argument("--group")
    parser.add_argument("--skip-audio", action="store_true")
    parser.add_argument("--augment-scenes", action="store_true",
                        help="给已有分类补 scene 场景示例（不重新生成表达本体）")
    parser.add_argument("--augment-examples", action="store_true",
                        help="给已有分类每条表达补到 4 个例句")
    args = parser.parse_args()

    cats = all_categories()
    if args.category:
        cats = [c for c in cats if c["id"] == args.category]
    elif args.group:
        cats = [c for c in cats if c["group_id"] == args.group]
    if not cats:
        print("❌ no matching categories")
        sys.exit(1)

    if args.augment_scenes:
        fn = augment_scenes
    elif args.augment_examples:
        fn = augment_examples
    else:
        fn = process_category
    ok = sum(1 for c in cats if fn(c, skip_audio=args.skip_audio))
    print("\n🎉 %d/%d categories done" % (ok, len(cats)))


if __name__ == "__main__":
    main()
