"""
Step 2: Generate TTS audio per dialogue line using MiniMax API.
- Each speaker gets their own voice (Alex=male, Lisa=female)
- Lines are concatenated with pauses, real timestamps are calculated
- Chinese translation also uses matching male/female voices
"""

import json
import os
import sys
import tempfile
from pathlib import Path

import requests
from pydub import AudioSegment

from config import (
    MINIMAX_API_KEY,
    MINIMAX_API_ENDPOINT,
    MINIMAX_VOICE_ALEX,
    MINIMAX_VOICE_LISA,
    MINIMAX_VOICE_ZH,
    MINIMAX_VOICE_ZH_MALE,
    MINIMAX_VOICE_ZH_FEMALE,
    MINIMAX_MODEL,
    OUTPUT_DIR,
    LEVELS,
)

PAUSE_BETWEEN_LINES_MS = 800  # 0.8s pause between dialogue lines
MAX_CHARS_PER_CHUNK = 150     # MiniMax limit ~200 chars, keep margin
VALID_EMOTIONS = {"happy", "sad", "angry", "surprised", "neutral"}


def sanitize_emotion(emotion):
    """Map invalid emotion values to valid MiniMax ones."""
    if emotion in VALID_EMOTIONS:
        return emotion
    mapping = {
        "curious": "happy",
        "excited": "happy",
        "interested": "happy",
        "enthusiastic": "happy",
        "worried": "sad",
        "concerned": "sad",
        "frustrated": "angry",
        "disappointed": "angry",
        "amazed": "surprised",
        "intrigued": "surprised",
        "shocked": "surprised",
    }
    return mapping.get(emotion, "neutral")


def split_long_text(text):
    """Split long text into chunks that MiniMax can handle."""
    if len(text) <= MAX_CHARS_PER_CHUNK:
        return [text]

    chunks = []
    # Split by sentence-ending punctuation first
    import re
    sentences = re.split(r'(?<=[.!?;])\s+', text)

    current = ""
    for sentence in sentences:
        if len(current) + len(sentence) + 1 <= MAX_CHARS_PER_CHUNK:
            current = (current + " " + sentence).strip()
        else:
            if current:
                chunks.append(current)
            # If single sentence is still too long, split by comma
            if len(sentence) > MAX_CHARS_PER_CHUNK:
                parts = re.split(r'(?<=[,，;])\s*', sentence)
                sub = ""
                for part in parts:
                    if len(sub) + len(part) + 1 <= MAX_CHARS_PER_CHUNK:
                        sub = (sub + " " + part).strip()
                    else:
                        if sub:
                            chunks.append(sub)
                        sub = part
                if sub:
                    chunks.append(sub)
                current = ""
            else:
                current = sentence
    if current:
        chunks.append(current)

    return chunks if chunks else [text]


def synthesize_long_text(text, voice_id, speed=1.0, emotion=None):
    """Synthesize text that may be too long for one API call. Retries with neutral on failure."""
    emotion = sanitize_emotion(emotion)
    chunks = split_long_text(text)

    if len(chunks) == 1:
        result = synthesize_line(chunks[0], voice_id, speed, emotion)
        if result is None and emotion != "neutral":
            print("   ⟳ Retrying with neutral emotion...")
            result = synthesize_line(chunks[0], voice_id, speed, "neutral")
        return result

    combined = AudioSegment.empty()
    short_pause = AudioSegment.silent(duration=200)

    for chunk in chunks:
        segment = synthesize_line(chunk, voice_id, speed, emotion)
        if segment is None and emotion != "neutral":
            segment = synthesize_line(chunk, voice_id, speed, "neutral")
        if segment is None:
            continue
        if len(combined) > 0:
            combined += short_pause
        combined += segment

    return combined if len(combined) > 0 else None


def synthesize_line(text, voice_id, speed=1.0, emotion=None):
    """Call MiniMax TTS for a single line. Returns AudioSegment or None."""
    voice_setting = {"voice_id": voice_id, "speed": speed}
    if emotion and emotion != "neutral":
        voice_setting["emotion"] = emotion

    response = requests.post(
        MINIMAX_API_ENDPOINT,
        headers={
            "Authorization": "Bearer %s" % MINIMAX_API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "model": MINIMAX_MODEL,
            "text": text,
            "voice_setting": voice_setting,
            "audio_setting": {"format": "mp3", "sample_rate": 32000},
        },
        timeout=60,
    )

    if response.status_code != 200:
        print("   ❌ TTS error %d: %s" % (response.status_code, response.text[:200]))
        return None

    result = response.json()
    audio_hex = None
    if "data" in result and "audio" in result["data"]:
        audio_hex = result["data"]["audio"]
    elif "audio" in result:
        audio_hex = result["audio"]

    if not audio_hex:
        print("   ❌ No audio in response")
        return None

    # MiniMax returns hex-encoded audio
    audio_bytes = bytes.fromhex(audio_hex)

    # Write to temp file and load as AudioSegment
    tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
    tmp.write(audio_bytes)
    tmp.close()

    try:
        segment = AudioSegment.from_mp3(tmp.name)
        return segment
    finally:
        os.unlink(tmp.name)


def generate_english_audio(episode, output_dir):
    """Generate English audio with alternating male/female voices. Returns timestamps."""
    level = episode.get("level", "medium")
    speed = LEVELS[level]["speed"] if level in LEVELS else 1.0

    combined = AudioSegment.empty()
    timestamps = []
    pause = AudioSegment.silent(duration=PAUSE_BETWEEN_LINES_MS)

    for i, line in enumerate(episode["script"]):
        voice = MINIMAX_VOICE_ALEX if line["speaker"] in ("Alex", "Host") else MINIMAX_VOICE_LISA
        emotion = line.get("emotion", "neutral")
        print("   🎤 [%s] (%s) %s..." % (line["speaker"], emotion, line["text"][:35]))

        segment = synthesize_long_text(line["text"], voice, speed=speed, emotion=emotion)
        if segment is None:
            print("   ⚠️  Skipping line %d" % (i + 1))
            continue

        start_ms = len(combined)
        combined += segment

        if i < len(episode["script"]) - 1:
            combined += pause

        end_ms = start_ms + len(segment)
        timestamps.append({
            "start": round(start_ms / 1000.0, 2),
            "end": round(end_ms / 1000.0, 2),
        })

    audio_path = os.path.join(output_dir, "en.mp3")
    combined.export(audio_path, format="mp3", bitrate="128k")
    print("   🔊 English audio: %s (%.1fs)" % (audio_path, len(combined) / 1000.0))
    return audio_path, timestamps


def generate_chinese_audio(episode, output_dir):
    """Generate Chinese translation audio with matching male/female voices."""
    combined = AudioSegment.empty()
    pause = AudioSegment.silent(duration=PAUSE_BETWEEN_LINES_MS)

    for i, line in enumerate(episode["script"]):
        # Match voice gender to speaker
        voice = MINIMAX_VOICE_ZH_MALE if line["speaker"] in ("Alex", "Host") else MINIMAX_VOICE_ZH_FEMALE
        text = line.get("translation_zh", "")
        if not text:
            continue

        emotion = line.get("emotion", "neutral")
        print("   🎤 [%s 中文] (%s) %s..." % (line["speaker"], emotion, text[:25]))
        segment = synthesize_long_text(text, voice, emotion=emotion)
        if segment is None:
            continue

        combined += segment
        if i < len(episode["script"]) - 1:
            combined += pause

    audio_path = os.path.join(output_dir, "zh.mp3")
    combined.export(audio_path, format="mp3", bitrate="128k")
    print("   🔊 Chinese audio: %s (%.1fs)" % (audio_path, len(combined) / 1000.0))
    return audio_path


def process_episode(json_path):
    """Generate audio for a single episode and update timestamps."""
    with open(json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    episode_dir = os.path.splitext(json_path)[0]
    os.makedirs(episode_dir, exist_ok=True)

    print("\n🎙️  Generating audio for: %s (%s)" % (episode["title"], episode["id"]))

    # Generate English audio and get real timestamps
    en_path, timestamps = generate_english_audio(episode, episode_dir)

    # Update script with real timestamps
    for i, ts in enumerate(timestamps):
        if i < len(episode["script"]):
            episode["script"][i]["start"] = ts["start"]
            episode["script"][i]["end"] = ts["end"]

    # Calculate real duration from audio
    episode["duration_seconds"] = int(timestamps[-1]["end"]) if timestamps else episode.get("duration_seconds", 180)

    # Generate Chinese audio
    zh_path = generate_chinese_audio(episode, episode_dir)

    if en_path and zh_path:
        episode["audio"]["english"] = en_path
        episode["audio"]["translation_zh"] = zh_path

        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(episode, f, ensure_ascii=False, indent=2)

        print("   ✅ Complete! Duration: %ds, %d lines" % (episode["duration_seconds"], len(timestamps)))
        return True

    return False


def main():
    target_level = sys.argv[1] if len(sys.argv) > 1 else None
    levels = [target_level] if target_level else ["easy", "medium", "hard"]

    for level in levels:
        level_dir = os.path.join(OUTPUT_DIR, level)
        if not os.path.exists(level_dir):
            print("⚠️  No episodes found for [%s]" % level)
            continue

        json_files = sorted(Path(level_dir).glob("*.json"))
        print("\n📦 Processing %d episodes for [%s]..." % (len(json_files), level))

        for json_file in json_files:
            try:
                process_episode(str(json_file))
            except Exception as e:
                print("   ❌ Error: %s" % e)

    print("\n🎉 Audio generation complete!")


if __name__ == "__main__":
    main()
