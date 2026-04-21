"""
Step 1: Generate dialogue script + translation + vocabulary using GPT API.
"""

import json
import os
import random
import sys
from datetime import datetime

import requests

# Name pairs: (male, female)
NAME_PAIRS = [
    ("Alex", "Lisa"),
    ("Ryan", "Emma"),
    ("James", "Sophie"),
    ("Daniel", "Olivia"),
    ("Michael", "Sarah"),
    ("David", "Rachel"),
    ("Kevin", "Amy"),
    ("Tom", "Nina"),
]

from config import (
    GPT_API_ENDPOINT,
    GPT_API_KEY,
    GPT_MODEL,
    BANNED_TOPICS,
    LEVELS,
    FORMAT_POOL,
    OUTPUT_DIR,
    RECYCLE_WORD_COUNT,
    RECYCLE_WINDOW_DAYS,
    RECYCLE_MAX_TIMES,
)
from news_fetcher import fetch_headlines_for_level

MANIFEST_PATH = os.path.join(OUTPUT_DIR, "vocabulary_manifest.json")


def load_vocabulary_manifest():
    """Load the vocabulary manifest tracking all generated words."""
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"easy": [], "medium": [], "hard": []}


def save_vocabulary_manifest(manifest):
    """Save the vocabulary manifest."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)


def select_recycle_words(manifest, level, count=RECYCLE_WORD_COUNT):
    """Pick words from recent episodes to recycle in new content."""
    words = manifest.get(level, [])
    if not words:
        return []

    today = datetime.now()
    candidates = []
    for w in words:
        try:
            word_date = datetime.strptime(w["date"], "%Y-%m-%d")
        except (ValueError, KeyError):
            continue
        days_ago = (today - word_date).days
        if 3 <= days_ago <= RECYCLE_WINDOW_DAYS and w.get("recycle_count", 0) < RECYCLE_MAX_TIMES:
            candidates.append((w, days_ago))

    # Prefer words from 3-7 days ago
    candidates.sort(key=lambda x: abs(x[1] - 5))
    selected = [c[0]["word"] for c in candidates[:count * 2]]
    random.shuffle(selected)
    return selected[:count]


def update_vocabulary_manifest(manifest, level, episode):
    """Add new vocabulary words from an episode to the manifest."""
    for vocab in episode.get("vocabulary", []):
        manifest.setdefault(level, []).append({
            "word": vocab["word"],
            "episode_id": episode["id"],
            "date": episode["date"],
            "recycle_count": 0,
        })

    # Mark recycled words
    recycled = episode.get("recycled_words", [])
    for entry in manifest.get(level, []):
        if entry["word"] in recycled:
            entry["recycle_count"] = entry.get("recycle_count", 0) + 1

    save_vocabulary_manifest(manifest)


def _build_name_gender_lookup():
    """Reverse-lookup: {name: gender} built from NAME_PAIRS. Covers all standard names."""
    result = {}
    for m, f in NAME_PAIRS:
        result[m] = "male"
        result[f] = "female"
    return result


NAME_GENDER_LOOKUP = _build_name_gender_lookup()


def _finalize_speakers(episode, is_solo, male_name, female_name, host_gender):
    """Resolve a {speaker_name: "male"|"female"} map covering every speaker in the script.

    Priority: (1) code-level known names — most authoritative; (2) GPT-provided
    `speakers` dict — catches variants like Mike/Sara that GPT chose itself;
    (3) NAME_PAIRS reverse lookup — catches GPT drifting to other pair members.
    Raises ValueError if any speaker can't be resolved — triggers outer retry.
    """
    script_speakers = []
    seen = set()
    for line in episode.get("script", []):
        name = (line.get("speaker") or "").strip()
        if name and name not in seen:
            seen.add(name)
            script_speakers.append(name)
    if not script_speakers:
        raise ValueError("script has no speakers")

    gpt_raw = episode.get("speakers") or {}
    gpt_map = {}
    if isinstance(gpt_raw, dict):
        for k, v in gpt_raw.items():
            if isinstance(k, str) and isinstance(v, str):
                gv = v.strip().lower()
                if gv in ("male", "female"):
                    gpt_map[k.strip()] = gv

    known = {}
    if is_solo:
        known["Host"] = host_gender
    else:
        known[male_name] = "male"
        known[female_name] = "female"

    resolved = {}
    unresolved = []
    for name in script_speakers:
        g = known.get(name) or gpt_map.get(name) or NAME_GENDER_LOOKUP.get(name)
        if g in ("male", "female"):
            resolved[name] = g
        else:
            unresolved.append(name)

    if unresolved:
        raise ValueError(
            "cannot resolve gender for speaker(s): %s (GPT speakers=%s)"
            % (", ".join(unresolved), gpt_map)
        )

    # Enforce solo contract: only "Host" allowed.
    if is_solo and set(resolved.keys()) != {"Host"}:
        raise ValueError(
            "solo format must use only 'Host', got: %s" % list(resolved.keys())
        )

    episode["speakers"] = resolved


def pick_format(level):
    """Weighted-random pick a format block for this episode."""
    pool = FORMAT_POOL.get(level, [])
    if not pool:
        return None, ""
    names = [item[0] for item in pool]
    weights = [item[1] for item in pool]
    descriptions = {item[0]: item[2] for item in pool}
    chosen = random.choices(names, weights=weights, k=1)[0]
    return chosen, descriptions[chosen]


def generate_episode_script(level, episode_num, topic=None, recycle_words=None, format_override=None):
    """Generate a complete episode script using GPT API."""
    level_config = LEVELS[level]
    date_str = datetime.now().strftime("%Y-%m-%d")
    ep_id = "ep-%s-%s-%03d" % (date_str.replace("-", ""), level, episode_num)

    # Pick random name pair for this episode
    male_name, female_name = random.choice(NAME_PAIRS)

    # Host gender for solo formats — stable from ep_id so reruns keep the same voice.
    # Must match generate_audio.py's fallback formula exactly.
    ep_seed = sum(ord(c) for c in ep_id)
    host_gender = "male" if (ep_seed % 2 == 0) else "female"

    # Pick a format (weighted) — strongly biased toward solo for Hard
    if format_override:
        format_name = format_override
        format_desc = dict((n, d) for n, _, d in FORMAT_POOL.get(level, [])).get(format_override, "")
    else:
        format_name, format_desc = pick_format(level)
    format_desc_filled = format_desc.replace("%(male)s", male_name).replace("%(female)s", female_name) if format_desc else ""
    is_solo = "SINGLE host" in format_desc or "Use 'Host' as the only speaker" in format_desc

    topic_line = ""
    if topic:
        topic_line = "TODAY'S TOPIC: %s\nBuild the entire conversation around this topic.\n\n" % topic
    else:
        # Inject today's real headlines (filtered) as inspiration. GPT picks one
        # and builds the episode around it. Falls back silently to TOPIC_POOL if
        # NewsAPI is down or all headlines were filtered.
        headlines = []
        try:
            headlines = fetch_headlines_for_level(level, max_count=5)
        except Exception as e:
            print("   ⚠️  News fetch errored (%s) — falling back to TOPIC_POOL" % e)
        if headlines:
            bullet_list = "\n".join("- %s" % h for h in headlines)
            topic_line = (
                "=== TODAY'S REAL-WORLD HEADLINES (inspiration — pick ONE) ===\n"
                "%s\n\n"
                "HOW TO USE:\n"
                "- Pick ONE headline that fits this level's audience and build the "
                "episode around it. Give your own angle, don't just paraphrase.\n"
                "- If a headline is too complex for this level, pick a simpler one OR "
                "generalize its topic (e.g. a specific EV launch → 'the rise of electric cars').\n"
                "- If NONE of the headlines fit (too niche, too sensitive, too hard to adapt), "
                "IGNORE this block and pick a topic from the TOPIC DOMAINS list below — that's fine.\n"
                "- Never mention the headline source or reporter. Never quote a headline verbatim in the script.\n\n"
            ) % bullet_list

    recycle_line = ""
    if recycle_words:
        recycle_line = (
            "WORD RECYCLING: Naturally weave these previously taught words into the dialogue: %s.\n"
            "These should appear organically in conversation. Do NOT add them to the vocabulary list.\n"
            "If a word doesn't fit the topic naturally, skip it. Topic takes priority.\n\n"
        ) % ", ".join(recycle_words)

    # Format the level prompt with BANNED_TOPICS
    level_prompt = level_config["prompt"]
    if "%s" in level_prompt:
        level_prompt = level_prompt % BANNED_TOPICS

    words_min = level_config.get("target_total_words_min")
    words_max = level_config.get("target_total_words_max")
    turns_min = level_config.get("turns_min")
    turns_max = level_config.get("turns_max")

    # Pick a specific target inside the range — GPT follows concrete numbers far better than ranges.
    target_words = random.randint(words_min, words_max)
    target_lines = random.randint(turns_min, turns_max)

    length_header = (
        "### HARD LENGTH TARGET (READ FIRST — THIS IS THE PRIMARY SUCCESS CRITERION) ###\n"
        "Produce EXACTLY %d script lines. Total English word count across all `text` fields "
        "must be AT LEAST %d words (ideal: around %d).\n"
        "A script with fewer than %d lines or fewer than %d total words will be REJECTED as a failure.\n"
        "Before outputting, count your lines and your total words. If either is below target, "
        "KEEP GOING — extend with follow-up questions, examples, tangents, reactions, deeper detail. "
        "Do NOT stop early.\n\n"
        % (target_lines, int(target_words * 0.95), target_words, target_lines - 3, int(target_words * 0.9))
    )

    if is_solo:
        speaker_hint = (
            "SPEAKERS: This is a SOLO broadcast. Every single line's `speaker` field MUST be exactly \"Host\". "
            "Do NOT use %s, %s, or any other name. No back-and-forth dialogue.\n"
            "The top-level `speakers` field MUST be exactly {\"Host\": \"%s\"}.\n\n"
            % (male_name, female_name, host_gender)
        )
    else:
        speaker_hint = (
            "SPEAKERS: Two-person dialogue. Use \"%s\" (male) and \"%s\" (female) alternating turns. "
            "Do NOT use \"Host\".\n"
            "The top-level `speakers` field MUST list every unique speaker name you use in `script`, "
            "mapped to \"male\" or \"female\". If you shorten or vary a name (e.g. Michael→Mike, Sarah→Sara), "
            "list the exact shortened form you used, with the correct gender. "
            "Required for THIS episode: {\"%s\": \"male\", \"%s\": \"female\"}.\n\n"
            % (male_name, female_name, male_name, female_name)
        )

    format_block = (
        "### FORMAT FOR THIS EPISODE (mandatory — do NOT switch format) ###\n"
        "Format: %s\n%s\n\n"
        % (format_name, format_desc_filled)
    )

    prompt = """%s%s%s
%s%s%s=== OUTPUT FORMAT ===
Generate valid JSON ONLY. No markdown, no explanation, no text outside the JSON.

{
  "id": "%s",
  "title": "Short Catchy English Title (2-5 words)",
  "level": "%s",
  "date": "%s",
  "duration_seconds": 0,
  "speakers": { "SpeakerName": "male" | "female", "...": "..." },
  "script": [
    {
      "speaker": "%s",
      "text": "EXACTLY ONE English sentence — max 20 words; if the idea needs more, split into multiple script lines.",
      "translation_zh": "对应的单句中文翻译（≤30 个汉字；长内容拆成下一条 script line）",
      "emotion": "neutral"
    },
    {
      "speaker": "%s",
      "text": "Another single sentence — don't pack 2-3 sentences into one script line.",
      "translation_zh": "对应的单句中文翻译",
      "emotion": "happy"
    }
  ],
  "vocabulary": [
    {
      "word": "target_word",
      "phonetic": "/fəˈnetɪk/",
      "translation_zh": "中文释义",
      "example": "Example sentence using the word",
      "example_zh": "例句的中文翻译"
    }
  ]
}

=== TIMESTAMPS ===
Do NOT include start/end timestamps — they will be calculated from audio.
Do NOT set duration_seconds — it will be calculated from audio.

=== EMOTION VALUES (STRICT — only these 5 strings allowed) ===
- "happy" — excited, agreeing, positive, curious, interested, enthusiastic
- "sad" — serious, concerned, empathetic, worried
- "angry" — frustrated, critical, disappointed
- "surprised" — shocked, amazed, intrigued, disbelief
- "neutral" — normal statement, explaining facts, calm narration, asking questions

=== FINAL CHECKLIST (verify before outputting) ===
1. Total English word count is within the target range above
2. Line count is within the target range above
3. Every script line has a non-empty "translation_zh" covering the full English
4. Every sentence is within the word-per-sentence limit for this level
5. **SUBTITLE RULE**: Each script line's `text` is ONE sentence (≤20 words) and
   `translation_zh` is ONE sentence (≤30 Chinese chars). On phone screen this
   caps subtitles at ≤5 lines (3 EN + 2 ZH). If a thought is longer, SPLIT it
   across multiple script lines — don't cram 2-3 sentences into one line.
6. No parentheses or special punctuation that could confuse TTS
7. Vocabulary words actually appear in the script text
8. The top-level `speakers` field is present, covers every unique `speaker` used in
   `script`, and every value is exactly "male" or "female" (lowercase). For solo
   format, `speakers` is exactly {"Host": "<given_gender>"}. Mismatches are REJECTED.
9. The JSON is valid and parseable
""" % (
        level_prompt,
        length_header,
        format_block,
        speaker_hint,
        topic_line,
        recycle_line,
        ep_id,
        level,
        date_str,
        "Host" if is_solo else male_name,
        "Host" if is_solo else female_name,
    )

    messages = [{"role": "user", "content": prompt}]
    episode = _call_gpt(messages)

    # Length-enforcement loop: GPT-4o often undershoots. Ask it to extend up to 3 times.
    # Key: keep the PREVIOUS full episode cached so we can restore vocab/title if GPT drops them.
    min_words = int(target_words * 0.88)
    min_lines = int(target_lines * 0.85)
    max_extensions = 3
    for attempt in range(max_extensions):
        current_words = sum(len(l.get("text", "").split()) for l in episode.get("script", []))
        current_lines = len(episode.get("script", []))
        if current_words >= min_words and current_lines >= min_lines:
            break
        # If words already exceed the max target, stop — don't over-extend
        if current_words >= int(words_max * 1.1):
            break
        print(
            "   ⚠️  Script too short (%d lines, %d words). Target: %d lines, %d words. Extending (attempt %d)..."
            % (current_lines, current_words, target_lines, target_words, attempt + 1)
        )
        prev_episode = episode
        messages.append({"role": "assistant", "content": json.dumps(episode, ensure_ascii=False)})
        needed_words = target_words - current_words
        needed_lines = target_lines - current_lines
        messages.append({
            "role": "user",
            "content": (
                "Your previous response has %d lines and %d words. That is too short.\n"
                "You must ADD approximately %d more lines (~%d more words) to the SAME script.\n\n"
                "RULES FOR THE EXTENDED VERSION:\n"
                "1. Keep ALL existing lines exactly as they were. Do NOT rewrite, summarize, or shorten them.\n"
                "2. APPEND new lines in the middle and near the end — deeper analysis, examples, counterpoints, anecdotes.\n"
                "3. Keep the SAME format, same speakers, same style.\n"
                "4. PRESERVE the `vocabulary` array from your previous response. Add 1-2 more words if natural, "
                "but do NOT remove any.\n"
                "5. PRESERVE `id`, `title`, `level`, `date` fields exactly.\n\n"
                "Return the FULL extended episode as a single valid JSON object. No markdown, no explanation."
            ) % (current_lines, current_words, needed_lines, needed_words),
        })
        try:
            new_episode = _call_gpt(messages)
            # Sanity check: if GPT returned something shorter, discard and keep previous.
            new_words = sum(len(l.get("text", "").split()) for l in new_episode.get("script", []))
            if new_words < current_words:
                print("   ⚠️  Extension returned SHORTER (%d words). Keeping previous version." % new_words)
                episode = prev_episode
                break
            # Merge missing fields back if GPT dropped them
            for key in ("id", "title", "level", "date", "vocabulary"):
                if key not in new_episode and key in prev_episode:
                    new_episode[key] = prev_episode[key]
            episode = new_episode
        except Exception as e:
            print("   ⚠️  Extension failed (%s). Keeping previous version." % e)
            episode = prev_episode
            break

    # Clean up — remove any GPT-added timestamps
    for line in episode.get("script", []):
        line.pop("start", None)
        line.pop("end", None)

    # Resolve authoritative speakers map. Raises on unresolvable speakers —
    # generate_daily.py catches and skips the episode.
    _finalize_speakers(episode, is_solo, male_name, female_name, host_gender)

    episode["audio"] = {"english": "", "translation_zh": ""}
    episode["duration_seconds"] = 0
    episode["format"] = format_name
    if recycle_words:
        episode["recycled_words"] = recycle_words

    for word in episode.get("vocabulary", []):
        word["audio"] = ""

    return episode


def _call_gpt(messages):
    """Single GPT call with retry for transient errors (403/429/5xx). Parses JSON out of the response."""
    import time as _time
    max_retries = 3
    for attempt in range(max_retries):
        response = requests.post(
            GPT_API_ENDPOINT,
            headers={
                "Authorization": "Bearer %s" % GPT_API_KEY,
                "Content-Type": "application/json",
            },
            json={
                "model": GPT_MODEL,
                "messages": messages,
                "temperature": 0.9,
                "max_tokens": 16000,
            },
            timeout=300,
        )
        if response.status_code in (403, 429, 500, 502, 503):
            wait = 30 * (2 ** attempt)
            print("   ⟳ GPT %d, retrying in %ds (attempt %d/%d)..." % (response.status_code, wait, attempt + 1, max_retries))
            _time.sleep(wait)
            continue
        response.raise_for_status()
        break
    else:
        response.raise_for_status()  # final failure
    content = response.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1]
    if content.endswith("```"):
        content = content.rsplit("```", 1)[0]
    return json.loads(content.strip())


def save_episode(episode, level):
    level_dir = os.path.join(OUTPUT_DIR, level)
    os.makedirs(level_dir, exist_ok=True)
    filename = "%s.json" % episode["id"]
    filepath = os.path.join(level_dir, filename)
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(episode, f, ensure_ascii=False, indent=2)
    print("✅ Saved: %s" % filepath)
    return filepath


def main():
    target_level = sys.argv[1] if len(sys.argv) > 1 else None
    topic = sys.argv[2] if len(sys.argv) > 2 else None

    levels_to_generate = {target_level: LEVELS[target_level]} if target_level else LEVELS
    manifest = load_vocabulary_manifest()

    for level, config in levels_to_generate.items():
        count = config["daily_episodes"]
        print("\n📝 Generating %d episode(s) for [%s]..." % (count, level))

        # Select recycle words for this level
        recycle = select_recycle_words(manifest, level)
        if recycle:
            print("   🔄 Recycling words: %s" % ", ".join(recycle))

        for i in range(1, count + 1):
            try:
                episode = generate_episode_script(level, i, topic, recycle_words=recycle)
                save_episode(episode, level)
                update_vocabulary_manifest(manifest, level, episode)
                print("   Title: %s" % episode["title"])
                print("   Lines: %d" % len(episode["script"]))
                print("   Vocabulary: %d words" % len(episode["vocabulary"]))
                if recycle:
                    print("   Recycled: %s" % ", ".join(recycle))
            except Exception as e:
                print("❌ Error: %s" % e)

    print("\n🎉 Script generation complete!")


if __name__ == "__main__":
    main()
