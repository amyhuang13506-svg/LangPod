"""
Step 3: Generate cover thumbnails for episodes using DALL-E API.

If DALL-E refuses (content_policy_violation on sensitive topics like
"Iran Conflict"), falls back to a locally-rendered gradient + title card
so every episode always has a cover.
"""

import json
import os
import sys
import base64
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont, ImageFilter

from config import GPT_API_KEY, OUTPUT_DIR

DALLE_ENDPOINT = "https://api.v3.cm/v1/images/generations"

# Level → (top color, bottom color) gradient palette for the fallback card.
LEVEL_GRADIENT = {
    "easy":   ((76, 175, 80),   (38, 95, 47)),    # green
    "medium": ((255, 152, 0),   (120, 70, 0)),    # amber
    "hard":   ((233, 30, 99),   (90, 20, 50)),    # crimson
}


def _render_fallback_cover(title: str, level: str, output_path: str) -> bool:
    """Build a 1024×1024 gradient card with the episode title centered.
    Used when DALL-E refuses the prompt — guarantees no episode ever ships
    without a cover."""
    W, H = 1024, 1024
    top, bot = LEVEL_GRADIENT.get(level.lower(), ((52, 85, 145), (15, 25, 55)))

    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        r = int(top[0] * (1 - t) + bot[0] * t)
        g = int(top[1] * (1 - t) + bot[1] * t)
        b = int(top[2] * (1 - t) + bot[2] * t)
        for x in range(W):
            px[x, y] = (r, g, b)

    # Soft vignette to make the gradient feel less flat
    overlay = Image.new("RGB", (W, H), (0, 0, 0))
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse((-200, -200, W + 200, H + 200), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(220))
    img = Image.composite(img, overlay, mask)

    draw = ImageDraw.Draw(img)
    # Pick a font that exists on the box; Linux has DejaVuSans.
    font_path = None
    for candidate in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]:
        if os.path.exists(candidate):
            font_path = candidate
            break

    # Word-wrap title to ~14 chars per line, max 4 lines.
    words = title.split()
    lines, cur = [], ""
    for w in words:
        candidate = (cur + " " + w).strip()
        if len(candidate) > 18 and cur:
            lines.append(cur)
            cur = w
        else:
            cur = candidate
    if cur:
        lines.append(cur)
    lines = lines[:4]

    font_size = 96 if len(lines) <= 2 else (76 if len(lines) == 3 else 60)
    try:
        font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()
    except Exception:
        font = ImageFont.load_default()

    total_h = sum(font.getbbox(l)[3] - font.getbbox(l)[1] for l in lines) + 24 * (len(lines) - 1)
    y = (H - total_h) // 2
    for ln in lines:
        bbox = font.getbbox(ln)
        line_w = bbox[2] - bbox[0]
        line_h = bbox[3] - bbox[1]
        x = (W - line_w) // 2
        # Drop shadow
        draw.text((x + 4, y + 4), ln, font=font, fill=(0, 0, 0, 160))
        draw.text((x, y), ln, font=font, fill=(255, 255, 255))
        y += line_h + 24

    # Encode as JPEG.
    img.save(output_path, "JPEG", quality=88)
    print("   🎨 Fallback cover (gradient): %s (%d KB)" % (output_path, os.path.getsize(output_path) // 1024))
    return True


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

    if not success:
        # DALL-E refused (typically content_policy on Iran / shooting / etc.).
        # Render a local gradient + title card so the episode still ships
        # with a thumbnail — no silent "missing image" in the app.
        print("   ⚠️  DALL-E unavailable for this title; using gradient fallback.")
        success = _render_fallback_cover(episode["title"], episode["level"], cover_path)

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
