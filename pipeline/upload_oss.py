"""
Step 3: Upload generated episodes (JSON + audio) to Aliyun OSS.
Updates JSON files with final OSS URLs.
"""

import json
import os
import sys
from pathlib import Path

from config import (
    OSS_ACCESS_KEY_ID,
    OSS_ACCESS_KEY_SECRET,
    OSS_BUCKET_NAME,
    OSS_CDN_DOMAIN,
    OSS_ENDPOINT,
    OUTPUT_DIR,
)

try:
    import oss2
except ImportError:
    print("❌ Please install oss2: pip install oss2")
    sys.exit(1)


def get_bucket():
    """Create OSS bucket connection."""
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    return oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)


def upload_file(bucket, local_path: str, oss_key: str) -> str:
    """Upload a file to OSS and return the CDN URL."""
    with open(local_path, "rb") as f:
        bucket.put_object(oss_key, f)
    url = f"{OSS_CDN_DOMAIN}/{oss_key}"
    print(f"   ☁️  Uploaded: {oss_key}")
    return url


def upload_episode(bucket, json_path: str, level: str) -> bool:
    """Upload a single episode's files to OSS."""
    with open(json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    ep_id = episode["id"]
    oss_prefix = f"episodes/{level}/{ep_id}"

    print(f"\n📤 Uploading: {episode['title']} ({ep_id})")

    # Upload English audio
    episode_dir = os.path.splitext(json_path)[0]
    en_local = os.path.join(episode_dir, "en.mp3")
    zh_local = os.path.join(episode_dir, "zh.mp3")

    if os.path.exists(en_local):
        episode["audio"]["english"] = upload_file(bucket, en_local, f"{oss_prefix}/en.mp3")
    else:
        print(f"   ⚠️  English audio not found: {en_local}")

    if os.path.exists(zh_local):
        episode["audio"]["translation_zh"] = upload_file(bucket, zh_local, f"{oss_prefix}/zh.mp3")
    else:
        print(f"   ⚠️  Chinese audio not found: {zh_local}")

    # Upload cover image
    cover_local = os.path.join(episode_dir, "cover.jpg")
    if os.path.exists(cover_local):
        episode["thumbnail"] = upload_file(bucket, cover_local, f"{oss_prefix}/cover.jpg")
    else:
        print(f"   ⚠️  Cover not found: {cover_local}")

    # Upload pattern explainer audios (if any) and rewrite audio_url to OSS URL.
    # Idempotent: skips patterns whose audio_url is already an http(s) URL.
    patterns = episode.get("patterns") or []
    for p in patterns:
        local = p.get("audio_url", "")
        if not local or local.startswith("http://") or local.startswith("https://"):
            continue
        if not os.path.exists(local):
            print(f"   ⚠️  Pattern audio missing: {local}")
            continue
        pattern_key = f"{oss_prefix}/patterns/{p['id']}.mp3"
        p["audio_url"] = upload_file(bucket, local, pattern_key)

    # Upload episode JSON
    episode_json_key = f"{oss_prefix}/episode.json"
    episode_json_bytes = json.dumps(episode, ensure_ascii=False, indent=2).encode("utf-8")
    bucket.put_object(episode_json_key, episode_json_bytes)
    print(f"   ☁️  Uploaded: {episode_json_key}")

    # Save updated JSON locally
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(episode, f, ensure_ascii=False, indent=2)

    print(f"   ✅ Upload complete")
    return True


def upload_localized_episode(bucket, json_path: str, level: str, lang: str) -> bool:
    """Upload one language's derivative files: {lang}.mp3 + episode_{lang}.json.
    English audio / cover are shared with the zh upload — URLs already baked
    into the localized JSON by translate_episode (copied from episode.json).
    zh legacy files are never touched here."""
    from languages import lang_suffix

    suffix = lang_suffix(lang)
    with open(json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    ep_id = episode["id"]
    oss_prefix = f"episodes/{level}/{ep_id}"
    print(f"\n📤 Uploading [{lang}]: {episode['title']} ({ep_id})")

    # Localized JSON sits next to episode.json as {ep_id}{suffix}.json;
    # its audio dir is the shared {ep_id}/ directory.
    episode_dir = os.path.join(os.path.dirname(json_path), ep_id)
    tr_local = os.path.join(episode_dir, f"{lang}.mp3")
    if os.path.exists(tr_local):
        episode["audio"]["translation"] = upload_file(bucket, tr_local, f"{oss_prefix}/{lang}.mp3")
    elif not episode["audio"].get("translation"):
        print(f"   ⚠️  Translation audio not found: {tr_local}")

    # Localized pattern explainer audios → patterns_{lang}/{pid}.mp3.
    # Idempotent: skips patterns whose audio_url is already an http(s) URL.
    for p in episode.get("patterns") or []:
        local = p.get("audio_url", "")
        if not local or local.startswith("http://") or local.startswith("https://"):
            continue
        if not os.path.exists(local):
            print(f"   ⚠️  Pattern audio missing: {local}")
            continue
        p["audio_url"] = upload_file(bucket, local, f"{oss_prefix}/patterns{suffix}/{p['id']}.mp3")

    episode_json_key = f"{oss_prefix}/episode{suffix}.json"
    bucket.put_object(episode_json_key, json.dumps(episode, ensure_ascii=False, indent=2).encode("utf-8"))
    print(f"   ☁️  Uploaded: {episode_json_key}")

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(episode, f, ensure_ascii=False, indent=2)

    print(f"   ✅ Upload complete [{lang}]")
    return True


def update_episode_list(bucket, level: str, lang: str = None):
    """Generate and upload the episode list index for a level (and language).
    Reads all episode{suffix}.json files from OSS to build a complete index.
    lang=None → legacy zh index.json (unchanged behavior). lang="ko" →
    index_ko.json built from episode_ko.json files only (partial coverage
    during backfill is expected and fine)."""
    from languages import lang_suffix

    suffix = lang_suffix(lang) if lang else ""
    prefix = f"episodes/{level}/"
    episodes = []

    for obj in oss2.ObjectIterator(bucket, prefix=prefix):
        # endswith("/episode.json") naturally excludes "/episode_ko.json" and vice versa
        if obj.key.endswith(f"/episode{suffix}.json"):
            if not suffix and obj.key.rsplit("/", 1)[-1] != "episode.json":
                continue  # belt & braces: legacy pass must not swallow language files
            try:
                data = bucket.get_object(obj.key).read()
                ep = json.loads(data)
                episodes.append({
                    "id": ep["id"],
                    "title": ep["title"],
                    "level": ep["level"],
                    "date": ep["date"],
                    "duration_seconds": ep["duration_seconds"],
                    "audio": ep["audio"],
                    "thumbnail": ep.get("thumbnail", ""),
                    "vocabulary_count": len(ep.get("vocabulary", [])),
                    # Include full patterns so HomeView/PatternHistoryView/混播 have them
                    # without a second fetch. Adds ~5KB per episode — acceptable for 51 eps.
                    "patterns": ep.get("patterns", []),
                })
            except Exception as e:
                print(f"   ⚠️  Error reading {obj.key}: {e}")

    episodes.sort(key=lambda x: x["date"])
    index = {"level": level, "episodes": episodes, "total": len(episodes)}
    if lang:
        index["lang"] = lang
    index_key = f"{prefix}index{suffix}.json"
    bucket.put_object(index_key, json.dumps(index, ensure_ascii=False, indent=2).encode("utf-8"))
    print(f"\n📋 Updated index: {index_key} ({len(episodes)} episodes)")


def main():
    """Upload all episodes to OSS."""
    target_level = sys.argv[1] if len(sys.argv) > 1 else None
    levels = [target_level] if target_level else ["easy", "medium", "hard"]

    bucket = get_bucket()

    for level in levels:
        level_dir = os.path.join(OUTPUT_DIR, level)
        if not os.path.exists(level_dir):
            print(f"⚠️  No episodes for [{level}]")
            continue

        json_files = sorted(Path(level_dir).glob("*.json"))
        print(f"\n📦 Uploading {len(json_files)} episodes for [{level}]...")

        for json_file in json_files:
            try:
                upload_episode(bucket, str(json_file), level)
            except Exception as e:
                print(f"   ❌ Error: {e}")

        update_episode_list(bucket, level)

    print("\n🎉 All uploads complete!")


if __name__ == "__main__":
    main()
