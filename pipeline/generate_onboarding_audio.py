"""
Generate onboarding audio files for Castlingo.

Produces 5 audio files (~750KB total):
1. onboarding_demo_en.mp3  — Method demo English (3-4 sentence dialogue, ~15s)
2. onboarding_demo_zh.mp3  — Method demo Chinese translation (~15s)
3. onboarding_trial_easy.mp3   — Easy level trial (~15s, slow)
4. onboarding_trial_medium.mp3 — Medium level trial (~15s, natural)
5. onboarding_trial_hard.mp3   — Hard level trial (~15s, fast)

Usage: python3 generate_onboarding_audio.py
Output: pipeline/output/onboarding/
"""

import json
import os
import sys

from generate_audio import (
    synthesize_long_text,
    PAUSE_BETWEEN_LINES_MS,
)
from pydub import AudioSegment

from config import (
    GPT_API_ENDPOINT,
    GPT_API_KEY,
    GPT_MODEL,
    MINIMAX_VOICE_ALEX,
    MINIMAX_VOICE_LISA,
    MINIMAX_VOICE_ZH_MALE,
    MINIMAX_VOICE_ZH_FEMALE,
)

import requests

OUTPUT_DIR = os.path.join("output", "onboarding")


def generate_scripts():
    """Use GPT to generate all onboarding audio scripts in one call."""

    prompt = """Generate onboarding audio scripts for an English learning podcast app called Castlingo.

I need 4 SHORT dialogues. Output valid JSON ONLY (no markdown).

{
  "demo": {
    "description": "Method demo: A very short, catchy dialogue for first-time users to experience the listen-repeat method. Must be immediately engaging. 3-4 lines, ~15 seconds.",
    "script": [
      {"speaker": "Alex", "text": "English line", "translation_zh": "中文翻译", "emotion": "neutral"}
    ]
  },
  "trial_easy": {
    "description": "Easy level sample: Simple daily conversation, slow and clear. 3-4 lines, ~15 seconds. Use only 800 most common words. Short sentences (5-10 words each).",
    "script": [...]
  },
  "trial_medium": {
    "description": "Medium level sample: Natural chatty conversation about a fun topic. 3-4 lines, ~15 seconds. Conversational with filler words.",
    "script": [...]
  },
  "trial_hard": {
    "description": "Hard level sample: News/professional style, complex vocabulary. 2-3 lines, ~15 seconds. Sounds like BBC or NPR.",
    "script": [...]
  }
}

IMPORTANT RULES:
- Each dialogue should be DIFFERENT topics to showcase variety
- demo: Something universally relatable (e.g. coffee, weekend plans, food)
- trial_easy: Super simple daily life (e.g. weather, shopping)
- trial_medium: Interesting lifestyle topic (e.g. travel, food culture)
- trial_hard: News/business topic with advanced vocabulary
- Speakers: "Alex" (male) and "Lisa" (female). For hard solo format use "Host".
- emotion: ONLY use "happy", "sad", "angry", "surprised", "neutral"
- Keep each dialogue SHORT — 15 seconds when spoken aloud
- demo dialogue must be especially polished — it's the user's first impression
"""

    response = requests.post(
        GPT_API_ENDPOINT,
        headers={
            "Authorization": "Bearer %s" % GPT_API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "model": GPT_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.8,
            "max_tokens": 2000,
        },
        timeout=60,
    )
    response.raise_for_status()

    content = response.json()["choices"][0]["message"]["content"]
    content = content.strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1]
    if content.endswith("```"):
        content = content.rsplit("```", 1)[0]
    content = content.strip()

    return json.loads(content)


def generate_audio_pair(script_lines, output_prefix, speed=1.0):
    """Generate English + Chinese audio from script lines."""
    pause = AudioSegment.silent(duration=PAUSE_BETWEEN_LINES_MS)

    # English audio
    en_combined = AudioSegment.empty()
    for i, line in enumerate(script_lines):
        speaker = line["speaker"]
        voice = MINIMAX_VOICE_ALEX if speaker in ("Alex", "Host") else MINIMAX_VOICE_LISA
        emotion = line.get("emotion", "neutral")

        print("   🎤 EN [%s] (%s) %s" % (speaker, emotion, line["text"][:50]))
        segment = synthesize_long_text(line["text"], voice, speed=speed, emotion=emotion)
        if segment is None:
            print("   ⚠️  Skipping line")
            continue

        en_combined += segment
        if i < len(script_lines) - 1:
            en_combined += pause

    en_path = os.path.join(OUTPUT_DIR, "%s_en.mp3" % output_prefix)
    en_combined.export(en_path, format="mp3", bitrate="128k")
    print("   ✅ %s (%.1fs)" % (en_path, len(en_combined) / 1000.0))

    # Chinese audio (only for demo)
    if output_prefix == "onboarding_demo":
        zh_combined = AudioSegment.empty()
        for i, line in enumerate(script_lines):
            speaker = line["speaker"]
            voice = MINIMAX_VOICE_ZH_MALE if speaker in ("Alex", "Host") else MINIMAX_VOICE_ZH_FEMALE
            text = line.get("translation_zh", "")
            if not text:
                continue

            emotion = line.get("emotion", "neutral")
            print("   🎤 ZH [%s] (%s) %s" % (speaker, emotion, text[:30]))
            segment = synthesize_long_text(text, voice, emotion=emotion)
            if segment is None:
                continue

            zh_combined += segment
            if i < len(script_lines) - 1:
                zh_combined += pause

        zh_path = os.path.join(OUTPUT_DIR, "%s_zh.mp3" % output_prefix)
        zh_combined.export(zh_path, format="mp3", bitrate="128k")
        print("   ✅ %s (%.1fs)" % (zh_path, len(zh_combined) / 1000.0))


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("📝 Generating onboarding scripts with GPT...")
    scripts = generate_scripts()

    # Save scripts for reference
    with open(os.path.join(OUTPUT_DIR, "scripts.json"), "w", encoding="utf-8") as f:
        json.dump(scripts, f, ensure_ascii=False, indent=2)
    print("📄 Scripts saved to output/onboarding/scripts.json\n")

    # 1. Demo audio (English + Chinese)
    print("🎙️  Generating demo audio (method experience)...")
    generate_audio_pair(scripts["demo"]["script"], "onboarding_demo", speed=0.9)

    # 2. Trial Easy (English only, slow)
    print("\n🎙️  Generating Easy trial audio...")
    generate_audio_pair(scripts["trial_easy"]["script"], "onboarding_trial_easy", speed=0.8)

    # 3. Trial Medium (English only, normal)
    print("\n🎙️  Generating Medium trial audio...")
    generate_audio_pair(scripts["trial_medium"]["script"], "onboarding_trial_medium", speed=1.0)

    # 4. Trial Hard (English only, fast)
    print("\n🎙️  Generating Hard trial audio...")
    generate_audio_pair(scripts["trial_hard"]["script"], "onboarding_trial_hard", speed=1.1)

    # Summary
    print("\n" + "=" * 50)
    print("🎉 Onboarding audio generation complete!")
    print("Files in: %s/" % OUTPUT_DIR)
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith(".mp3"):
            size = os.path.getsize(os.path.join(OUTPUT_DIR, f))
            print("   📁 %s (%.0f KB)" % (f, size / 1024))


if __name__ == "__main__":
    main()
