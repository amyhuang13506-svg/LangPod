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


def update_episode_list(bucket, level: str):
    """Generate and upload the episode list index for a level.
    Reads all episode.json files from OSS to build a complete index."""
    prefix = f"episodes/{level}/"
    episodes = []

    for obj in oss2.ObjectIterator(bucket, prefix=prefix):
        if obj.key.endswith("/episode.json"):
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
                })
            except Exception as e:
                print(f"   ⚠️  Error reading {obj.key}: {e}")

    episodes.sort(key=lambda x: x["date"])
    index = {"level": level, "episodes": episodes, "total": len(episodes)}
    index_key = f"{prefix}index.json"
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
