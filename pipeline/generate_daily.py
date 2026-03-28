#!/usr/bin/env python3
"""
LangPod Daily Content Pipeline
Run via cron: 0 3 * * * cd /opt/langpod/pipeline && python3 generate_daily.py

Full pipeline:
1. (Optional) Fetch trending topics from NewsAPI
2. Generate dialogue scripts with GPT
3. Generate TTS audio with ElevenLabs
4. Upload to Aliyun OSS
"""

import logging
import sys
from datetime import datetime

from generate_script import generate_episode_script, save_episode
from generate_audio import process_episode
from upload_oss import get_bucket, upload_episode, update_episode_list
from config import LEVELS, OUTPUT_DIR

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(f"logs/pipeline-{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger(__name__)


def fetch_trending_topics():
    """Fetch trending topics for Hard level episodes.
    MVP: return hardcoded topics. Replace with NewsAPI later.
    """
    return [
        "AI regulation debate",
        "Remote work trends",
        "Climate change solutions",
        "Space exploration milestones",
        "Global supply chain challenges",
        "Mental health in the workplace",
        "Electric vehicle market growth",
        "Social media impact on youth",
    ]


def run_pipeline(target_level=None):
    """Run the full content generation pipeline."""
    start_time = datetime.now()
    log.info("=" * 50)
    log.info(f"🚀 LangPod Pipeline started at {start_time}")
    log.info("=" * 50)

    topics = fetch_trending_topics()
    levels = {target_level: LEVELS[target_level]} if target_level else LEVELS
    bucket = None
    generated = 0
    errors = 0

    for level, config in levels.items():
        count = config["daily_episodes"]
        log.info(f"\n📝 Level [{level}]: generating {count} episode(s)")

        for i in range(1, count + 1):
            try:
                # Step 1: Generate script
                topic = topics.pop(0) if level == "hard" and topics else None
                log.info(f"   Step 1/3: Generating script...")
                episode = generate_episode_script(level, i, topic)
                json_path = save_episode(episode, level)
                log.info(f"   → {episode['title']}")

                # Step 2: Generate audio
                log.info(f"   Step 2/3: Generating audio...")
                process_episode(json_path)

                # Step 3: Upload to OSS
                log.info(f"   Step 3/3: Uploading to OSS...")
                if bucket is None:
                    bucket = get_bucket()
                upload_episode(bucket, json_path, level)

                generated += 1
                log.info(f"   ✅ Episode complete!")

            except Exception as e:
                errors += 1
                log.error(f"   ❌ Failed: {e}", exc_info=True)

        # Update level index
        if bucket:
            try:
                update_episode_list(bucket, level)
            except Exception as e:
                log.error(f"   ❌ Failed to update index: {e}")

    elapsed = (datetime.now() - start_time).total_seconds()
    log.info(f"\n{'=' * 50}")
    log.info(f"🏁 Pipeline complete: {generated} episodes, {errors} errors, {elapsed:.1f}s")
    log.info(f"{'=' * 50}")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else None
    run_pipeline(target)
