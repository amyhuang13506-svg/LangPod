"""
Step 3: Generate cover thumbnails for episodes using DALL-E API.
"""

import json
import os
import sys
import base64
from pathlib import Path

import requests

from config import GPT_API_KEY, OUTPUT_DIR

DALLE_ENDPOINT = "https://api.v3.cm/v1/images/generations"


def generate_cover(title, level, output_path):
    """Generate a square cover image for an episode."""
    prompt = (
        "A photorealistic square thumbnail for a podcast episode titled '%s'. "
        "Style: editorial news photography, like a Bloomberg or BBC article header image. "
        "Real-world scene related to the topic, shot with shallow depth of field. "
        "Cinematic lighting, professional color grading. "
        "NO text, NO words, NO letters, NO watermarks on the image. "
        "The image should look like a high-quality stock photo that a news outlet would use."
    ) % title

    response = requests.post(
        DALLE_ENDPOINT,
        headers={
            "Authorization": "Bearer %s" % GPT_API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "model": "dall-e-3",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "response_format": "url",
        },
        timeout=180,
    )

    if response.status_code != 200:
        print("   ❌ DALL-E error %d: %s" % (response.status_code, response.text[:200]))
        return False

    result = response.json()
    if "data" not in result or len(result["data"]) == 0:
        print("   ❌ No image in response")
        return False

    img_url = result["data"][0].get("url", "")
    if not img_url:
        print("   ❌ No URL in response")
        return False

    # Download the image
    img_resp = requests.get(img_url, timeout=60)
    if img_resp.status_code != 200:
        print("   ❌ Failed to download image: %d" % img_resp.status_code)
        return False

    with open(output_path, "wb") as f:
        f.write(img_resp.content)
    print("   🎨 Cover: %s (%d KB)" % (output_path, len(img_resp.content) // 1024))
    return True


def process_episode(json_path):
    """Generate cover for a single episode."""
    with open(json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    episode_dir = os.path.splitext(json_path)[0]
    os.makedirs(episode_dir, exist_ok=True)

    cover_path = os.path.join(episode_dir, "cover.jpg")

    if os.path.exists(cover_path):
        print("   ⏭ Cover already exists: %s" % cover_path)
        return True

    print("   🎨 Generating cover for: %s" % episode["title"])
    success = generate_cover(episode["title"], episode["level"], cover_path)

    if success:
        episode["thumbnail"] = cover_path
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(episode, f, ensure_ascii=False, indent=2)

    return success


def main():
    target_level = sys.argv[1] if len(sys.argv) > 1 else None
    levels = [target_level] if target_level else ["easy", "medium", "hard"]

    for level in levels:
        level_dir = os.path.join(OUTPUT_DIR, level)
        if not os.path.exists(level_dir):
            print("⚠️  No episodes for [%s]" % level)
            continue

        json_files = sorted(Path(level_dir).glob("*.json"))
        print("\n🎨 Generating covers for %d episodes [%s]..." % (len(json_files), level))

        for json_file in json_files:
            try:
                process_episode(str(json_file))
            except Exception as e:
                print("   ❌ Error: %s" % e)

    print("\n🎉 Cover generation complete!")


if __name__ == "__main__":
    main()
