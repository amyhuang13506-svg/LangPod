# -*- coding: utf-8 -*-
"""
词汇小课堂 Step 2.5: ElevenLabs 合成发音音频（单词 + 例句 + 句型）。

每个课堂产出 audio/ 目录：
  audio/{word_slug}.mp3       单词发音
  audio/{word_slug}_ex.mp3    例句发音
  audio/sentence_{i}.mp3      句型发音
并把相对路径写进 lesson.json（word.audio / word.example_audio / sentence.audio），
upload_lessons.py 上传后重写为 OSS URL。

幂等：已存在的 mp3 跳过。voice 按国家选（config.ELEVENLABS_LESSON_VOICES）。

用法:
  python3 generate_lesson_audio.py --lesson lesson_us_otc_meds
  python3 generate_lesson_audio.py --country us
"""

import argparse
import glob
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
    OUTPUT_DIR,
)

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")
TTS_ENDPOINT = "https://api.elevenlabs.io/v1/text-to-speech/%s"
OUTPUT_FORMAT = "mp3_44100_64"  # 64kbps 对短语音足够，文件小


def slugify(word):
    return re.sub(r"[^a-z0-9]+", "_", word.lower()).strip("_")


def synthesize(text, voice_id, output_path, max_retries=3):
    """合成一段文本到 mp3。返回 True/False。"""
    for attempt in range(max_retries):
        response = requests.post(
            TTS_ENDPOINT % voice_id,
            params={"output_format": OUTPUT_FORMAT},
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
        print("      ❌ TTS %d: %s" % (response.status_code, response.text[:150]))
        return False
    return False


def process_lesson(json_path):
    with open(json_path, "r", encoding="utf-8") as f:
        lesson = json.load(f)
    country = lesson["country"]
    voice_id = ELEVENLABS_LESSON_VOICES.get(country)
    if not voice_id:
        print("   ❌ no voice for country %s" % country)
        return False

    lesson_dir = os.path.dirname(json_path)
    audio_dir = os.path.join(lesson_dir, "audio")
    os.makedirs(audio_dir, exist_ok=True)

    print("\n🔊 %s — %s (voice %s)" % (lesson["id"], lesson["title_zh"], country))
    made, skipped, failed = 0, 0, 0

    def ensure(text, filename):
        nonlocal made, skipped, failed
        path = os.path.join(audio_dir, filename)
        rel = "audio/%s" % filename
        if os.path.exists(path) and os.path.getsize(path) > 0:
            skipped += 1
            return rel
        if synthesize(text, voice_id, path):
            made += 1
            return rel
        failed += 1
        return ""

    for zone in lesson["zones"]:
        for word in zone["hotspots"] + zone["extra_words"]:
            slug = slugify(word["word"])
            # 已是 OSS URL 的字段不动（幂等重跑）
            if not (word.get("audio") or "").startswith("http"):
                word["audio"] = ensure(word["word"], "%s.mp3" % slug)
            if word.get("example") and not (word.get("example_audio") or "").startswith("http"):
                word["example_audio"] = ensure(word["example"], "%s_ex.mp3" % slug)

    for i, sentence in enumerate(lesson.get("sentences", [])):
        if not (sentence.get("audio") or "").startswith("http"):
            sentence["audio"] = ensure(sentence["english"], "sentence_%d.mp3" % i)

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(lesson, f, ensure_ascii=False, indent=2)
    print("   ✅ %d synthesized, %d cached, %d failed" % (made, skipped, failed))
    return failed == 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", help="single lesson id")
    parser.add_argument("--country", help="single country")
    args = parser.parse_args()

    pattern = os.path.join(LESSONS_DIR, args.country or "*", args.lesson or "lesson_*", "lesson.json")
    files = sorted(glob.glob(pattern))
    if not files:
        print("❌ no lessons found: %s" % pattern)
        sys.exit(1)

    ok = 0
    for fp in files:
        try:
            if process_lesson(fp):
                ok += 1
        except Exception as e:
            print("   ❌ %s: %s" % (fp, e))
    print("\n🎉 audio done: %d/%d lessons clean" % (ok, len(files)))


if __name__ == "__main__":
    main()
