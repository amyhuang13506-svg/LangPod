# -*- coding: utf-8 -*-
"""
Daily localization orchestrator. Drains the localize queue × NEW_LANGS:
for each queued episode, fetch the finalized zh episode.json from OSS,
derive the language layer (text → audio → patterns), upload, and rebuild
each touched level's index_{lang}.json.

Cron (after generate_daily's 03:00 run):
  30 4 * * * cd /opt/langpod/pipeline && python3 localize_daily.py >> logs/localize.log 2>&1
  0  6 * * * cd /opt/langpod/pipeline && python3 localize_daily.py >> logs/localize.log 2>&1

Failure isolation: every (episode, lang) is try/except'd; zh publishing is
never affected. Failed attempts stay queued (max 3 tries, 72h expiry).
Backfill reuses this path: enqueue old episode ids, run localize_daily.
"""

import json
import os
import sys
import traceback

from languages import LANGUAGES, NEW_LANGS, lang_suffix
from localize_queue import mark, pending_items
from upload_oss import get_bucket, update_episode_list, upload_localized_episode
from config import OUTPUT_DIR


def fetch_episode_json(bucket, level, episode_id):
    """Ensure the zh episode.json is available locally; fetch from OSS if not."""
    local = os.path.join(OUTPUT_DIR, level, "%s.json" % episode_id)
    if os.path.exists(local):
        return local
    key = "episodes/%s/%s/episode.json" % (level, episode_id)
    data = bucket.get_object(key).read()
    os.makedirs(os.path.dirname(local), exist_ok=True)
    with open(local, "wb") as f:
        f.write(data)
    return local


def localize_one(bucket, level, episode_id, lang):
    """Full language derivation for one episode. Raises on failure."""
    from translate_episode import process_episode as translate
    from localize_patterns import process_episode_patterns

    json_path = fetch_episode_json(bucket, level, episode_id)
    loc_path = os.path.splitext(json_path)[0] + lang_suffix(lang) + ".json"

    # 1. text + translation audio (skip if already produced by an earlier attempt)
    if not os.path.exists(loc_path):
        translate(json_path, lang, with_audio=True)
    else:
        print("   ⏭  %s text layer exists" % os.path.basename(loc_path))
        # audio may still be missing if a previous run died mid-way
        audio = os.path.join(os.path.splitext(json_path)[0], "%s.mp3" % lang)
        with open(loc_path) as f:
            has_remote_audio = bool(json.load(f).get("audio", {}).get("translation"))
        if not os.path.exists(audio) and not has_remote_audio and not LANGUAGES[lang].get("reuse_audio_from"):
            from translate_episode import synthesize_localized_audio
            with open(loc_path) as f:
                synthesize_localized_audio(json.load(f), json_path, lang)

    # 2. patterns (non-fatal per-pattern QC skips happen inside)
    # zh-Hant 走 OpenCC+音频复用；其余语言要求 prompts_{lang} 已注册
    if lang == "zh-Hant":
        process_episode_patterns(json_path, lang)
    else:
        from languages import prompt_module
        try:
            prompt_module(lang)
            process_episode_patterns(json_path, lang)
        except ImportError:
            print("   ⏭  no pattern prompts for %s — skipping patterns" % lang)

    # 3. upload
    upload_localized_episode(bucket, loc_path, level, lang)


def main():
    items = [it for it in pending_items() if it.get("type") == "episode"]
    if not items:
        print("📭 localize queue empty")
        return

    bucket = get_bucket()
    touched_levels = {lang: set() for lang in NEW_LANGS}

    for it in items:
        episode_id, level = it["episode_id"], it["level"]
        for lang in NEW_LANGS:
            if lang in it.get("langs_done", []):
                continue
            if it.get("attempts", {}).get(lang, 0) >= 3:
                continue
            print("\n══ %s [%s] ══" % (episode_id, lang))
            try:
                localize_one(bucket, level, episode_id, lang)
                mark(episode_id, lang, success=True)
                touched_levels[lang].add(level)
                # 每集完成立刻重建该语言 index —— 长回填（数天）期间内容边产边上线，
                # 也避免中途 kill/重启丢掉 touched 集合导致 index 永不更新
                update_episode_list(bucket, level, lang=lang)
            except Exception as e:
                print("   ❌ %s [%s] failed: %s" % (episode_id, lang, e))
                traceback.print_exc()
                mark(episode_id, lang, success=False)

    # 收尾兜底再刷一遍（幂等）
    for lang, levels in touched_levels.items():
        for level in sorted(levels):
            update_episode_list(bucket, level, lang=lang)

    print("\n🎉 localize_daily done")


if __name__ == "__main__":
    main()
