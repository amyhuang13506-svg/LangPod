"""
Step 1: Generate dialogue script + translation + vocabulary using GPT API.
"""

import json
import os
import random
import sys
from datetime import datetime

import requests

# Name pairs: (male, female)
NAME_PAIRS = [
    ("Alex", "Lisa"),
    ("Ryan", "Emma"),
    ("James", "Sophie"),
    ("Daniel", "Olivia"),
    ("Michael", "Sarah"),
    ("David", "Rachel"),
    ("Kevin", "Amy"),
    ("Tom", "Nina"),
]

from config import (
    GPT_API_ENDPOINT,
    GPT_API_KEY,
    GPT_MODEL,
    BANNED_TOPICS,
    LEVELS,
    OUTPUT_DIR,
)


def generate_episode_script(level, episode_num, topic=None):
    """Generate a complete episode script using GPT API."""
    level_config = LEVELS[level]
    date_str = datetime.now().strftime("%Y-%m-%d")
    ep_id = "ep-%s-%s-%03d" % (date_str.replace("-", ""), level, episode_num)

    # Pick random name pair for this episode
    male_name, female_name = random.choice(NAME_PAIRS)

    topic_line = ""
    if topic:
        topic_line = "TODAY'S TOPIC: %s\nBuild the entire conversation around this topic.\n\n" % topic

    # Format the level prompt with BANNED_TOPICS
    level_prompt = level_config["prompt"]
    if "%s" in level_prompt:
        level_prompt = level_prompt % BANNED_TOPICS

    prompt = """%s

SPEAKERS: Use "%s" (male) and "%s" (female) as the speaker names. For solo format, use "Host".

%sGenerate the dialogue as valid JSON ONLY (no markdown, no explanation):
{
  "id": "%s",
  "title": "Short Catchy English Title",
  "level": "%s",
  "date": "%s",
  "duration_seconds": 0,
  "script": [
    {
      "speaker": "%s",
      "text": "English dialogue line",
      "translation_zh": "自然中文翻译",
      "emotion": "neutral"
    }
  ],
  "vocabulary": [
    {
      "word": "target_word",
      "phonetic": "/fəˈnetɪk/",
      "translation_zh": "中文释义",
      "example": "Example sentence using the word",
      "example_zh": "例句的中文翻译"
    }
  ]
}

Pick %s vocabulary words that appear in the dialogue.
Do NOT include start/end timestamps — they will be calculated from audio.
Do NOT set duration_seconds — it will be calculated from audio.

IMPORTANT: For each script line, set "emotion" to EXACTLY ONE of these 5 values (no other values allowed):
- "happy" — excited, agreeing, positive, curious, interested, enthusiastic
- "sad" — serious, concerned, empathetic, worried
- "angry" — frustrated, critical, disappointed
- "surprised" — shocked, amazed, intrigued, disbelief
- "neutral" — normal statement, explaining facts, calm narration, asking questions
ONLY use these 5 exact strings. Do NOT invent other emotion values like "curious" or "excited".
""" % (
        level_prompt,
        male_name,
        female_name,
        topic_line,
        ep_id,
        level,
        date_str,
        male_name,
        level_config["vocab_count"],
    )

    response = requests.post(
        GPT_API_ENDPOINT,
        headers={
            "Authorization": "Bearer %s" % GPT_API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "model": GPT_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.85,
            "max_tokens": 4000,
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

    episode = json.loads(content)

    # Clean up — remove any GPT-added timestamps
    for line in episode.get("script", []):
        line.pop("start", None)
        line.pop("end", None)

    episode["audio"] = {"english": "", "translation_zh": ""}
    episode["duration_seconds"] = 0

    for word in episode.get("vocabulary", []):
        word["audio"] = ""

    return episode


def save_episode(episode, level):
    level_dir = os.path.join(OUTPUT_DIR, level)
    os.makedirs(level_dir, exist_ok=True)
    filename = "%s.json" % episode["id"]
    filepath = os.path.join(level_dir, filename)
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(episode, f, ensure_ascii=False, indent=2)
    print("✅ Saved: %s" % filepath)
    return filepath


def main():
    target_level = sys.argv[1] if len(sys.argv) > 1 else None
    topic = sys.argv[2] if len(sys.argv) > 2 else None

    levels_to_generate = {target_level: LEVELS[target_level]} if target_level else LEVELS

    for level, config in levels_to_generate.items():
        count = config["daily_episodes"]
        print("\n📝 Generating %d episode(s) for [%s]..." % (count, level))

        for i in range(1, count + 1):
            try:
                episode = generate_episode_script(level, i, topic)
                save_episode(episode, level)
                print("   Title: %s" % episode["title"])
                print("   Lines: %d" % len(episode["script"]))
                print("   Vocabulary: %d words" % len(episode["vocabulary"]))
            except Exception as e:
                print("❌ Error: %s" % e)

    print("\n🎉 Script generation complete!")


if __name__ == "__main__":
    main()
