#!/usr/bin/env python3
"""
Batch generate first 10 episodes per level (30 total).
"""

import json
import os
import sys
from datetime import datetime, timedelta

from generate_script import generate_episode_script, save_episode
from generate_audio import process_episode
from generate_cover import generate_cover

from config import LEVELS, OUTPUT_DIR

# Topics for each level — 10 per level
EASY_TOPICS = [
    "Ordering coffee at a café",
    "Asking for directions to the train station",
    "Buying fruit at a market",
    "Making plans to meet a friend",
    "Checking in at a hotel",
    "Ordering food at a restaurant",
    "Talking about the weather",
    "Introducing yourself to a new neighbor",
    "Buying a train ticket",
    "Shopping for clothes",
]

MEDIUM_TOPICS = [
    "Why remote work is changing city life",
    "The rise of plant-based food",
    "How social media affects sleep quality",
    "Electric cars are getting cheaper",
    "The four-day work week experiment",
    "Why people are learning languages with AI",
    "Digital nomads living in Southeast Asia",
    "The trend of solo traveling",
    "How streaming changed the music industry",
    "Why cold plunge therapy is trending",
]

HARD_TOPICS = [
    "OpenAI releases a new AI model that changes the industry",
    "Global inflation trends and central bank responses in 2026",
    "Tesla's new affordable EV disrupts the auto market",
    "The future of space tourism after recent breakthroughs",
    "How climate tech startups are attracting record investment",
    "The global chip shortage and its impact on tech supply chains",
    "Apple Vision Pro's impact on the future of computing",
    "The rise of AI in drug discovery and healthcare",
    "How the creator economy is reshaping traditional employment",
    "The debate over AI regulation in the tech industry",
]

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else None

    levels_to_run = {
        "easy": EASY_TOPICS,
        "medium": MEDIUM_TOPICS,
        "hard": HARD_TOPICS,
    }

    if target:
        levels_to_run = {target: levels_to_run[target]}

    total = sum(len(v) for v in levels_to_run.values())
    done = 0
    errors = 0

    for level, topics in levels_to_run.items():
        print("\n" + "=" * 50)
        print("LEVEL: %s (%d episodes)" % (level.upper(), len(topics)))
        print("=" * 50)

        for i, topic in enumerate(topics):
            ep_num = i + 1
            print("\n--- [%s] Episode %d/%d: %s ---" % (level, ep_num, len(topics), topic))

            try:
                # Step 1: Generate script
                print("  1/3 Script...")
                episode = generate_episode_script(level, ep_num, topic)

                # Fake different dates for variety
                days_ago = len(topics) - i
                fake_date = (datetime.now() - timedelta(days=days_ago)).strftime("%Y-%m-%d")
                episode["date"] = fake_date
                episode["id"] = "ep-%s-%s-%03d" % (fake_date.replace("-", ""), level, ep_num)

                json_path = save_episode(episode, level)
                print("  Title: %s (%d lines)" % (episode["title"], len(episode["script"])))

                # Step 2: Generate audio
                print("  2/3 Audio...")
                process_episode(json_path)

                # Step 3: Generate cover
                print("  3/3 Cover...")
                episode_dir = os.path.splitext(json_path)[0]
                cover_path = os.path.join(episode_dir, "cover.jpg")
                generate_cover(episode["title"], level, cover_path)

                # Update JSON with cover
                with open(json_path, "r", encoding="utf-8") as f:
                    episode = json.load(f)
                episode["thumbnail"] = cover_path
                with open(json_path, "w", encoding="utf-8") as f:
                    json.dump(episode, f, ensure_ascii=False, indent=2)

                done += 1
                print("  ✅ Done! (%d/%d total)" % (done, total))

            except Exception as e:
                errors += 1
                print("  ❌ FAILED: %s" % e)

    print("\n" + "=" * 50)
    print("BATCH COMPLETE: %d success, %d errors, %d total" % (done, errors, total))
    print("=" * 50)


if __name__ == "__main__":
    main()
