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
import random
import sys
from datetime import datetime

from generate_script import generate_episode_script, save_episode
from generate_audio import process_episode as process_audio
from generate_cover import process_episode as process_cover
from extract_patterns import process_episode as process_patterns, load_pattern_manifest, save_pattern_manifest
from upload_oss import get_bucket, upload_episode, update_episode_list
from config import LEVELS, OUTPUT_DIR, TOPIC_POOL

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


def pick_topics_for_level(level, count):
    """Sample `count` distinct topics from the level's pool, no repeats within a run."""
    pool = list(TOPIC_POOL.get(level, []))
    random.shuffle(pool)
    if len(pool) < count:
        # Pool smaller than needed — allow cycling
        return (pool * ((count // len(pool)) + 1))[:count] if pool else [None] * count
    return pool[:count]


def run_pipeline(target_level=None):
    """Run the full content generation pipeline."""
    start_time = datetime.now()
    log.info("=" * 50)
    log.info(f"🚀 LangPod Pipeline started at {start_time}")
    log.info("=" * 50)

    levels = {target_level: LEVELS[target_level]} if target_level else LEVELS
    bucket = None
    generated = 0
    errors = 0
    pattern_manifest = load_pattern_manifest()

    for level, config in levels.items():
        count = config["daily_episodes"]
        topics = pick_topics_for_level(level, count)
        log.info(f"\n📝 Level [{level}]: generating {count} episode(s)")
        log.info(f"   Topics: {topics}")

        for i in range(1, count + 1):
            try:
                topic = topics[i - 1] if i - 1 < len(topics) else None
                log.info(f"   Step 1/4: Generating script (topic: {topic})...")
                episode = generate_episode_script(level, i, topic)
                json_path = save_episode(episode, level)
                log.info(f"   → {episode['title']}")

                # Step 2: Generate audio
                log.info(f"   Step 2/4: Generating audio...")
                process_audio(json_path)

                # Step 3: Generate cover
                log.info(f"   Step 3/5: Generating cover...")
                try:
                    process_cover(json_path)
                except Exception as e:
                    log.warning(f"   ⚠️ Cover generation failed (non-fatal): {e}")

                # Step 4: Extract patterns + synthesize explainer audio
                log.info(f"   Step 4/5: Extracting patterns...")
                try:
                    process_patterns(json_path, pattern_manifest)
                except Exception as e:
                    log.warning(f"   ⚠️ Pattern extraction failed (non-fatal): {e}")

                # Step 5: Upload to OSS
                log.info(f"   Step 5/5: Uploading to OSS...")
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
