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

import json
import logging
import os
import random
import sys
from datetime import datetime, timedelta

from generate_script import generate_episode_script, save_episode
from generate_audio import process_episode as process_audio
from generate_cover import process_episode as process_cover
from extract_patterns import process_episode as process_patterns, load_pattern_manifest, save_pattern_manifest
from upload_oss import get_bucket, upload_episode, update_episode_list
from enqueue_push import enqueue_episode
from news_fetcher import fetch_headlines_for_level
from config import (
    LEVELS,
    OUTPUT_DIR,
    TOPIC_POOL,
    TOPIC_COOLDOWN_DAYS,
    NEWS_PRIMARY_LEVELS,
)

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


TOPIC_MANIFEST_PATH = os.path.join(OUTPUT_DIR, "topic_manifest.json")


def load_topic_manifest():
    if os.path.exists(TOPIC_MANIFEST_PATH):
        try:
            with open(TOPIC_MANIFEST_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"easy": [], "medium": [], "hard": []}


def save_topic_manifest(manifest):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(TOPIC_MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)


def _recently_used_topics(manifest, level, days):
    """Topics (string equality) used within the last `days` for this level."""
    today = datetime.now().date()
    cutoff = today - timedelta(days=days)
    used = set()
    for entry in manifest.get(level, []):
        try:
            d = datetime.strptime(entry["date"], "%Y-%m-%d").date()
        except (KeyError, ValueError, TypeError):
            continue
        if d >= cutoff:
            used.add(entry.get("topic", ""))
    used.discard("")
    return used


def _last_used_dates(manifest, level):
    """{topic: latest_date_string}, used to rank stale topics by oldness."""
    last = {}
    for entry in manifest.get(level, []):
        t = entry.get("topic", "")
        d = entry.get("date", "")
        if not t or not d:
            continue
        if t not in last or d > last[t]:
            last[t] = d
    return last


def pick_topics_for_level(level, count, manifest):
    """Pick `count` topics for today, avoiding any used in the last
    TOPIC_COOLDOWN_DAYS for this level. For medium/hard, slot 1 is filled
    with a today's news headline (when available) for novelty.

    Mutates `manifest` in place — caller saves after the run completes
    (so failed episodes don't burn topics permanently).
    """
    today_str = datetime.now().strftime("%Y-%m-%d")
    used_recent = _recently_used_topics(manifest, level, TOPIC_COOLDOWN_DAYS)
    selected = []

    # Slot 1 (medium/hard only): today's news headline → novelty
    if level in NEWS_PRIMARY_LEVELS and count > 0:
        try:
            headlines = fetch_headlines_for_level(level, max_count=10)
        except Exception as e:
            log.warning(f"   ⚠️  News fetch failed: {e}")
            headlines = []
        for h in headlines:
            if h and h not in used_recent:
                selected.append(h)
                used_recent.add(h)
                break

    # Remaining slots: TOPIC_POOL filtered by cooldown
    pool = list(TOPIC_POOL.get(level, []))
    fresh = [t for t in pool if t not in used_recent]
    random.shuffle(fresh)

    needed = count - len(selected)
    if len(fresh) >= needed:
        selected.extend(fresh[:needed])
    else:
        # Fresh pool exhausted — top up with least-recently-used stale topics
        selected.extend(fresh)
        last_used = _last_used_dates(manifest, level)
        stale = [t for t in pool if t in used_recent]
        stale.sort(key=lambda t: last_used.get(t, ""))  # oldest first
        for t in stale:
            if len(selected) >= count:
                break
            if t not in selected:
                selected.append(t)

    # Pad with None if still short (shouldn't happen with non-empty pool)
    while len(selected) < count:
        selected.append(None)

    # Record picks (only real topics, not None)
    for t in selected:
        if t:
            manifest.setdefault(level, []).append({
                "topic": t,
                "date": today_str,
            })

    return selected


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
    topic_manifest = load_topic_manifest()

    for level, config in levels.items():
        count = config["daily_episodes"]
        topics = pick_topics_for_level(level, count, topic_manifest)
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

                # Step 6: Queue push for the 07:50 flush (deferred from
                # midnight upload time so users wake up to a single batch
                # instead of being buzzed at 00:03–00:20).
                try:
                    enqueue_episode(
                        episode_id=episode["id"],
                        level=level,
                        title=episode["title"],
                    )
                except Exception as e:
                    log.warning(f"   ⚠️ Failed to enqueue push (non-fatal): {e}")

            except Exception as e:
                errors += 1
                log.error(f"   ❌ Failed: {e}", exc_info=True)

        # Update level index
        if bucket:
            try:
                update_episode_list(bucket, level)
            except Exception as e:
                log.error(f"   ❌ Failed to update index: {e}")

    save_topic_manifest(topic_manifest)

    elapsed = (datetime.now() - start_time).total_seconds()
    log.info(f"\n{'=' * 50}")
    log.info(f"🏁 Pipeline complete: {generated} episodes, {errors} errors, {elapsed:.1f}s")
    log.info(f"{'=' * 50}")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else None
    run_pipeline(target)
