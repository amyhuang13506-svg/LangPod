# -*- coding: utf-8 -*-
"""
词汇小课堂「模拟现场对话」：给每个课堂生成一段角色扮演对话（你 = 顾客视角）。

产出写进 lesson.json 的 roleplay 字段：
  {"setup_zh", "your_role_zh", "other_role_zh",
   "dialogue": [{"speaker": "you"|"other", "en", "zh", "audio"}]}
音频: audio/rp{i}_{文本hash8}.mp3 —— 台词重新生成时旧音频自动作废（防串音）。
对话双声：对方 = Chris 男声，你 = 课堂国家 voice（发音跟随口音）。

幂等：已有完整 roleplay（每句都有音频）的课堂跳过。

用法:
  python3 generate_lesson_roleplay.py --lesson lesson_us_bank_account
  python3 generate_lesson_roleplay.py --country us
  python3 generate_lesson_roleplay.py             # 全部
  python3 generate_lesson_roleplay.py --annotate --country us
      # 给每句「你」的台词补 GPT 教学解析 note_zh（场景模拟解析用），改完直传 OSS
"""

import argparse
import glob
import hashlib
import json
import os
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

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")
TTS_ENDPOINT = "https://api.elevenlabs.io/v1/text-to-speech/%s"
OUTPUT_FORMAT = "mp3_44100_64"
OTHER_VOICE = "iP95p4xoKVk53GoZ742B"  # Chris 男声（店员/柜员等对方角色）

ANNOTATE_PROMPT = """You are annotating a roleplay dialogue for Chinese learners of English.

Scene: {title_en}（{title_zh}）
Dialogue (numbered):
{dialogue_text}

For EACH line spoken by "you" listed above, write a "note_zh" — 1-2 句中文教学解析，让学习者看完能带走一个具体知识点。

要求：
- 每条只抓一个角度讲透：这句里的关键表达/固定搭配 OR 语气礼貌层级（为什么这么措辞）OR 母语者的文化习惯
- 必须具体（引用句中的英文短语），禁止"顺着语境这样回应很自然"这类空话套话
- 不同的行要用不同角度，全部解析读起来不能一个模子
- 每条 ≤60 个汉字

Output STRICT JSON only:
{{"notes": [{{"index": <行号>, "note_zh": "..."}}]}}"""

PROMPT = """You are writing a realistic roleplay dialogue for a Chinese learner practicing real-life English abroad.

Scene: {title_en} ({title_zh}), in {country_name}.
Key vocabulary the lesson taught (weave several in naturally): {words}
Useful sentences the lesson taught (reuse 1-2 naturally): {sentences}

Write ONE complete realistic conversation:
- "you" = the learner (customer/visitor perspective), "other" = the staff/local person
- 8-10 turns total, alternating, starting with "other" greeting the learner
- Real spoken register (contractions, natural fillers OK), each line MAX 16 words
- The learner's lines must be practical templates they can reuse verbatim in real life
- "setup_zh": 1-2 句中文场景设定，用"你"的视角（"你走进…要办…"），有画面感
- "your_role_zh"/"other_role_zh": 2-4 字角色名（顾客 / 银行柜员）
- Every line has "zh": 自然中文翻译

Output STRICT JSON only:
{{"setup_zh": "...", "your_role_zh": "...", "other_role_zh": "...",
  "dialogue": [{{"speaker": "other", "en": "...", "zh": "..."}}, {{"speaker": "you", "en": "...", "zh": "..."}}]}}"""


def call_gpt(prompt):
    for attempt in range(3):
        response = requests.post(
            GPT_API_ENDPOINT,
            headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
            json={
                "model": GPT_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.8,
                "max_tokens": 3000,
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


def synthesize(text, voice_id, output_path, max_retries=4):
    for attempt in range(max_retries):
        try:
            response = requests.post(
                TTS_ENDPOINT % voice_id,
                params={"output_format": OUTPUT_FORMAT},
                headers={"xi-api-key": ELEVENLABS_LESSON_API_KEY, "Content-Type": "application/json"},
                json={
                    "text": text,
                    "model_id": ELEVENLABS_LESSON_MODEL,
                    "voice_settings": {"stability": 0.6, "similarity_boost": 0.8, "speed": 0.95},
                },
                timeout=60,
            )
            if response.status_code == 200 and response.content:
                with open(output_path, "wb") as f:
                    f.write(response.content)
                return True
        except requests.exceptions.RequestException as e:
            print("      ⚠️ TTS retry %d: %s" % (attempt + 1, type(e).__name__))
        time.sleep(5 * (attempt + 1))
    return False


COUNTRY_NAMES = {
    "us": "the United States", "uk": "the United Kingdom", "au": "Australia",
    "ca": "Canada", "nz": "New Zealand", "sg": "Singapore",
}


def roleplay_complete(lesson):
    rp = lesson.get("roleplay") or {}
    dialogue = rp.get("dialogue") or []
    return bool(dialogue) and all(l.get("audio") for l in dialogue)


def process_lesson(lesson_dir):
    json_path = os.path.join(lesson_dir, "lesson.json")
    if not os.path.exists(json_path):
        return False
    with open(json_path, "r", encoding="utf-8") as f:
        lesson = json.load(f)
    if roleplay_complete(lesson):
        print("⏭  %s roleplay exists" % lesson["id"])
        return True

    print("🎭 %s (%s)" % (lesson["id"], lesson["title_zh"]))
    country = lesson.get("country", "us")

    # 1) 文本（已有对话文本则只补音频）
    rp = lesson.get("roleplay")
    if not (rp and rp.get("dialogue")):
        words = ", ".join(
            w["word"]
            for z in lesson["zones"]
            for w in (z["hotspots"] + z.get("extra_words", []))
        )[:600]
        sents = " / ".join(s["english"] for s in lesson.get("sentences", [])[:5])
        prompt = PROMPT.format(
            title_en=lesson["title_en"], title_zh=lesson["title_zh"],
            country_name=COUNTRY_NAMES.get(country, "the United States"),
            words=words, sentences=sents,
        )
        try:
            rp = call_gpt(prompt)
        except Exception as e:
            print("   ❌ GPT: %s" % e)
            return False
        dialogue = [
            l for l in rp.get("dialogue", [])
            if l.get("speaker") in ("you", "other") and l.get("en") and l.get("zh")
        ]
        if len(dialogue) < 6:
            print("   ❌ dialogue too short (%d turns)" % len(dialogue))
            return False
        lesson["roleplay"] = {
            "setup_zh": rp.get("setup_zh", ""),
            "your_role_zh": rp.get("your_role_zh", "顾客"),
            "other_role_zh": rp.get("other_role_zh", "工作人员"),
            "dialogue": dialogue,
        }
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=2)
        print("   ✅ %d turns" % len(dialogue))

    # 2) 音频（幂等：已有文件跳过；文件名带文本 hash 防串音）
    audio_dir = os.path.join(lesson_dir, "audio")
    os.makedirs(audio_dir, exist_ok=True)
    you_voice = ELEVENLABS_LESSON_VOICES.get(country, ELEVENLABS_LESSON_VOICES["us"])
    made = 0
    for i, line in enumerate(lesson["roleplay"]["dialogue"]):
        if (line.get("audio") or "").startswith("http"):
            continue
        text_hash = hashlib.md5(line["en"].encode()).hexdigest()[:8]
        filename = "rp%d_%s.mp3" % (i, text_hash)
        path = os.path.join(audio_dir, filename)
        rel = "audio/%s" % filename
        if os.path.exists(path) and os.path.getsize(path) > 0:
            line["audio"] = rel
            continue
        voice = you_voice if line["speaker"] == "you" else OTHER_VOICE
        if synthesize(line["en"], voice, path):
            line["audio"] = rel
            made += 1
        else:
            line["audio"] = ""
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(lesson, f, ensure_ascii=False, indent=2)
    if made:
        print("   🔊 %d clips synthesized" % made)
    return True


def annotate_lesson(lesson_dir, bucket):
    """给 roleplay 里每句「你」的台词补 GPT 教学解析 note_zh，改完直传 lesson.json。"""
    json_path = os.path.join(lesson_dir, "lesson.json")
    if not os.path.exists(json_path):
        return False
    with open(json_path, "r", encoding="utf-8") as f:
        lesson = json.load(f)
    rp = lesson.get("roleplay")
    dialogue = (rp or {}).get("dialogue") or []
    if not dialogue:
        return False
    you_missing = [
        i for i, l in enumerate(dialogue)
        if l.get("speaker") == "you" and not l.get("note_zh")
    ]
    if not you_missing:
        print("⏭  %s notes exist" % lesson["id"])
        return True

    print("💡 %s (%s) — %d 句待解析" % (lesson["id"], lesson["title_zh"], len(you_missing)))
    dialogue_text = "\n".join(
        "%d. [%s] %s" % (i, l["speaker"], l["en"]) for i, l in enumerate(dialogue)
    )
    prompt = ANNOTATE_PROMPT.format(
        title_en=lesson["title_en"], title_zh=lesson["title_zh"], dialogue_text=dialogue_text
    )
    try:
        result = call_gpt(prompt)
    except Exception as e:
        print("   ❌ GPT: %s" % e)
        return False
    added = 0
    for note in result.get("notes", []):
        idx = note.get("index")
        text = (note.get("note_zh") or "").strip()
        if isinstance(idx, int) and 0 <= idx < len(dialogue) and text \
                and dialogue[idx].get("speaker") == "you":
            dialogue[idx]["note_zh"] = text
            added += 1
    if not added:
        print("   ⚠️ no usable notes")
        return False
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(lesson, f, ensure_ascii=False, indent=2)
    # 直传 lesson.json（其余资源字段已是 OSS URL，无需全量 upload）
    bucket.put_object(
        "lessons/%s/%s/lesson.json" % (lesson.get("country", "us"), lesson["id"]),
        json.dumps(lesson, ensure_ascii=False, indent=2).encode("utf-8"),
    )
    print("   ✅ %d notes added + uploaded" % added)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson")
    parser.add_argument("--country")
    parser.add_argument("--annotate", action="store_true",
                        help="给已有 roleplay 的每句你方台词补教学解析 note_zh")
    args = parser.parse_args()

    dirs = sorted(glob.glob(os.path.join(LESSONS_DIR, "*", "*")))
    if args.lesson:
        dirs = [d for d in dirs if os.path.basename(d) == args.lesson]
    elif args.country:
        dirs = [d for d in dirs if os.path.basename(os.path.dirname(d)) == args.country]

    if args.annotate:
        import oss2
        from config import (
            OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, OSS_BUCKET_NAME, OSS_ENDPOINT,
        )
        auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
        bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)
        ok = sum(1 for d in dirs if os.path.isdir(d) and annotate_lesson(d, bucket))
    else:
        ok = sum(1 for d in dirs if os.path.isdir(d) and process_lesson(d))
    print("\n🎉 %d lessons done" % ok)


if __name__ == "__main__":
    main()
