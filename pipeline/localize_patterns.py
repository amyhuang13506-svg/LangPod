# -*- coding: utf-8 -*-
"""
Pattern explainer localization: rewrite the native-language teaching layer of
existing patterns (English skeleton reused verbatim — all users learn the same
patterns) and synthesize the mixed-language explainer audio.

Flow per pattern:
  zh pattern (from episode.json) → extract English skeleton + zh reference
  → GPT writes Korean explainer (prompts_ko.PATTERN_LOCALIZATION_PROMPT)
  → QC L0 rules + L1 LLM judge → one critique-guided retry → fail = skip
  → synthesize audio (reusing extract_patterns TTS/atempo machinery)
  → append generic-schema pattern to episode_{lang}.json

Usage:
  python3 localize_patterns.py output/easy/ep-20260814-easy-002.json ko
"""

import hashlib
import json
import os
import re
import sys

from pydub import AudioSegment

from config import MINIMAX_VOICE_ALEX, MINIMAX_VOICE_LISA
from extract_patterns import (
    DRILL_SILENCE_MS,
    DRILL_SPEED,
    PATTERN_DEMO_SPEED,
    PATTERN_EXAMPLE_SPEED,
    SECTION_SILENCE_MS,
    WITHIN_SECTION_SILENCE_MS,
    minimax_tts,
    slowdown_segment,
)
from generate_script import _call_gpt
from languages import LANGUAGES, lang_suffix
from qc.judge import judge_pattern_localization
from qc.rules import check_pattern_localization


# ---------- language plumbing ----------

def _voice_pairs(lang):
    """Gender-matched (en voice, explainer voice) pairs, stable-hash picked —
    same mechanism as zh PATTERN_VOICE_PAIRS."""
    tts = LANGUAGES[lang].get("tts") or {}
    male = tts.get("voice_teacher_male")
    female = tts.get("voice_teacher_female")
    if not male or not female:
        raise RuntimeError("no teacher voices configured for lang=%s" % lang)
    return [
        {"en": MINIMAX_VOICE_ALEX, "tr": male},
        {"en": MINIMAX_VOICE_LISA, "tr": female},
    ]


def pick_voice_pair(pattern_id, lang):
    pairs = _voice_pairs(lang)
    h = hashlib.md5(pattern_id.encode("utf-8")).hexdigest()
    return pairs[int(h, 16) % len(pairs)]


def clean_for_tts_generic(text):
    """Non-Chinese variant of extract_patterns.clean_for_tts: ellipsis → comma
    pause, strip trailing dashes (TTS artifacts)."""
    if not text:
        return text
    text = text.replace("dot dot dot", ",").replace("...", ",").replace("…", ",")
    text = text.strip()
    while text and text[-1] in "——— ":
        text = text[:-1]
    return text.strip()


_ENDS_EN_WORD = re.compile(r"\b[A-Z][a-zA-Z]*\.\s*$")
_STARTS_EN_WORD = re.compile(r"^[A-Z][a-zA-Z]*\.")


def split_into_subtitles_generic(text, lang):
    """Subtitle chunking for space-delimited languages (ko/es/pt…).
    1. Split on sentence enders (western + CJK variants GPT may emit)
    2. Merge "Word." + "Word." error-demo fragments (same as zh rule-8 logic)
    3. Overlong chunks: split on commas, then merge on word boundaries up to cap
    """
    max_chars = LANGUAGES[lang].get("subtitle_max_chars", 44)
    text = (text or "").strip()
    if not text:
        return []

    sentences = re.split(r"(?<=[.!?。！？…])\s*", text)
    sentences = [s.strip() for s in sentences if s.strip() and any(c.isalnum() for c in s)]

    merged, i = [], 0
    while i < len(sentences):
        current = sentences[i]
        while (i + 1 < len(sentences)
               and _ENDS_EN_WORD.search(current)
               and _STARTS_EN_WORD.match(sentences[i + 1])):
            current = current + " " + sentences[i + 1]
            i += 1
        merged.append(current)
        i += 1

    result = []
    for s in merged:
        if len(s) <= max_chars:
            result.append(s)
            continue
        parts = re.split(r"(?<=[,，])\s*", s)
        parts = [p.strip() for p in parts if p.strip()]
        buf = ""
        for p in parts:
            # a comma part may itself be overlong → split on spaces
            words = p.split(" ") if len(p) > max_chars else [p]
            for w in words:
                candidate = (buf + " " + w).strip() if buf else w
                if len(candidate) <= max_chars:
                    buf = candidate
                else:
                    if buf:
                        result.append(buf)
                    buf = w
        if buf:
            result.append(buf)
    return result


# ---------- skeleton extraction from zh pattern ----------

def extract_skeleton(zh_pattern):
    """Recover the fixed English skeleton from a stored zh pattern object.
    Works on both local (pre-upload) and OSS (post-upload) pattern JSON."""
    lines = zh_pattern.get("explainer_script", [])

    def en_lines(section_prefix):
        return [l["text_en"] for l in lines
                if l.get("section", "").startswith(section_prefix) and l.get("text_en")]

    demo_list = en_lines("pronunciation")
    demo_text = demo_list[0] if demo_list else ""

    examples = []
    for i in (1, 2, 3):
        ens = en_lines("example%d" % i)
        if ens:
            examples.append({"en_text": ens[0]})

    return {
        "id": zh_pattern["id"],
        "episode_id": zh_pattern.get("episode_id", ""),
        "template": zh_pattern["template"],
        "demo_en": demo_text,
        "examples": examples,
        "example_sentences": zh_pattern.get("example_sentences", []),
        "thumbnail_color": zh_pattern.get("thumbnail_color", "#E8DCC4"),
    }


def build_zh_reference(zh_pattern):
    """Group the zh explainer text by section — content reference for GPT."""
    ref = {}
    for l in zh_pattern.get("explainer_script", []):
        # stored zh patterns use text_zh; be tolerant of generic key too
        t = l.get("text_zh") or l.get("text_translation") or ""
        if t:
            ref.setdefault(l.get("section", ""), []).append(t)
    ref_text = {k: " ".join(v) for k, v in ref.items()}
    ref_text["translation_zh"] = zh_pattern.get("translation_zh") or zh_pattern.get("translation", "")
    ref_text["scene_zh"] = zh_pattern.get("scene", "")
    return json.dumps(ref_text, ensure_ascii=False, indent=1)


# ---------- GPT localization + QC ----------

def localize_pattern_text(zh_pattern, lang, level):
    """GPT-write the localized explainer fields. Returns dict or None (skip)."""
    if lang != "ko":
        raise ValueError("no pattern localization prompt for lang=%s" % lang)
    from prompts_ko import (
        PATTERN_INTRO_LISTEN,
        PATTERN_INTRO_PREVIEW_PREFIX,
        PATTERN_FEELING_ENDING_PREFIX,
        PATTERN_LOCALIZATION_PROMPT,
    )

    skeleton = extract_skeleton(zh_pattern)
    trap_rule = ("If the pattern's literal meaning is a trap (idiom), START meaning with a "
                 "warning that the literal reading is wrong."
                 if level == "hard" else "")
    prompt = PATTERN_LOCALIZATION_PROMPT.format(
        skeleton=json.dumps({k: skeleton[k] for k in
                             ("template", "demo_en", "examples", "example_sentences")},
                            ensure_ascii=False, indent=1),
        zh_reference=build_zh_reference(zh_pattern),
        preview_prefix=PATTERN_INTRO_PREVIEW_PREFIX,
        listen_line=PATTERN_INTRO_LISTEN,
        feeling_ending_prefix=PATTERN_FEELING_ENDING_PREFIX,
        trap_rule=trap_rule,
    ) + '\n\nAlso include "scene": a short Korean scene tag (2-5 words, e.g. "식당 / 물건 빌리기") in the JSON.'

    messages = [{"role": "user", "content": prompt}]
    loc = None
    max_attempts = 3  # initial + 2 critique-guided retries
    for attempt in range(max_attempts):
        loc = _call_gpt(messages)
        failures = check_pattern_localization(loc, skeleton, lang)
        if not failures:
            passed, issues = judge_pattern_localization(loc, skeleton["template"], lang)
            if not passed:
                failures = ["judge: %s" % i for i in issues]
        if not failures:
            return loc
        if attempt < max_attempts - 1:
            print("   ⟳ pattern QC failed (%d issues), retry %d/%d..."
                  % (len(failures), attempt + 1, max_attempts - 1))
            messages.append({"role": "assistant", "content": json.dumps(loc, ensure_ascii=False)})
            messages.append({"role": "user", "content":
                             "Your output failed native-speaker review:\n- "
                             + "\n- ".join(failures[:15])
                             + "\nWhere the reviewer suggested a specific rephrasing, apply it "
                               "EXACTLY. Rewrite any sentence flagged as translationese from "
                               "scratch as a Korean native would say it — do not lightly edit. "
                               "Return the corrected FULL JSON (same shape)."})
        else:
            print("   ❌ pattern %s rejected after %d attempts: %s"
                  % (skeleton["id"], max_attempts, failures[:5]))
            return None
    return None


# ---------- audio synthesis ----------

def synthesize_localized_pattern_audio(loc, skeleton, output_dir, lang, level):
    """Mixed-language explainer audio, mirroring extract_patterns'
    synthesize_pattern_audio structure. Returns (path, script_lines, duration)."""
    if lang == "ko":
        from prompts_ko import PATTERN_DRILL_LEADIN, PATTERN_DRILL_LEADIN_SUBTITLE
        drill_leadin, drill_leadin_sub = PATTERN_DRILL_LEADIN, PATTERN_DRILL_LEADIN_SUBTITLE
    else:
        raise ValueError("no fixed lines for lang=%s" % lang)

    demo_speed = PATTERN_DEMO_SPEED.get(level, 1.0)
    example_speed = PATTERN_EXAMPLE_SPEED.get(level, 1.0)
    combined = AudioSegment.empty()
    script_lines = []
    silence_short = AudioSegment.silent(duration=WITHIN_SECTION_SILENCE_MS)
    silence_section = AudioSegment.silent(duration=SECTION_SILENCE_MS)
    silence_drill = AudioSegment.silent(duration=DRILL_SILENCE_MS)

    voices = pick_voice_pair(skeleton["id"], lang)
    en_voice, tr_voice = voices["en"], voices["tr"]

    def append_tr(combined, text, section):
        """Append localized narration, chunked into subtitle rows."""
        for sub in split_into_subtitles_generic(text, lang):
            s_ms = len(combined)
            seg = minimax_tts(clean_for_tts_generic(sub), tr_voice)
            if seg is None:
                continue
            combined += seg
            script_lines.append({
                "section": section, "text_translation": sub, "text_en": "",
                "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
            })
            combined += silence_short
        return combined

    demo_text = skeleton["demo_en"]
    demo_natural = minimax_tts(demo_text, en_voice) if demo_text else None
    drill_slow = slowdown_segment(demo_natural, tempo=DRILL_SPEED) if demo_natural is not None else None
    demo_segment = (slowdown_segment(demo_natural, tempo=demo_speed)
                    if demo_natural is not None and demo_speed < 1.0 else demo_natural)

    # 1. pronunciation: localized intro → en demo
    combined = append_tr(combined, loc["pronunciation_intro"], "pronunciation")
    if demo_segment is not None:
        s_ms = len(combined)
        combined += demo_segment
        script_lines.append({
            "section": "pronunciation", "text_translation": "", "text_en": demo_text,
            "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
        })
        combined += silence_short
    combined += silence_section

    # 2. drill: fixed lead-in + 3× slowed demo
    s_ms = len(combined)
    seg = minimax_tts(drill_leadin, tr_voice)
    if seg is not None:
        combined += seg
        script_lines.append({
            "section": "pronunciation_drill", "text_translation": drill_leadin_sub, "text_en": "",
            "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
        })
    combined += silence_short
    if drill_slow is not None:
        for _ in range(3):
            s_ms = len(combined)
            combined += drill_slow
            script_lines.append({
                "section": "pronunciation_drill", "text_translation": "", "text_en": demo_text,
                "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
            })
            combined += silence_drill
    combined += silence_section

    # 3-4. meaning + scene_and_feeling
    combined = append_tr(combined, loc["meaning"], "meaning")
    combined += silence_section
    combined = append_tr(combined, loc["scene_and_feeling"], "scene_and_feeling")
    combined += silence_section

    # 5-7. examples: localized scene prefix → en sentence (slowed per level)
    loc_examples = loc.get("examples", [])
    for i, (sk_ex, loc_ex) in enumerate(zip(skeleton["examples"], loc_examples), 1):
        section = "example%d" % i
        combined = append_tr(combined, loc_ex.get("scene_prefix", ""), section)
        en_text = sk_ex["en_text"]
        if en_text:
            s_ms = len(combined)
            ex_natural = minimax_tts(clean_for_tts_generic(en_text), en_voice)
            if ex_natural is not None:
                ex_seg = (slowdown_segment(ex_natural, tempo=example_speed)
                          if example_speed < 1.0 else ex_natural)
                combined += ex_seg
                script_lines.append({
                    "section": section, "text_translation": "", "text_en": en_text,
                    "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
                })
        if i < len(skeleton["examples"]):
            combined += silence_section

    audio_path = os.path.join(output_dir, "%s.mp3" % skeleton["id"])
    combined.export(audio_path, format="mp3", bitrate="128k")
    return audio_path, script_lines, len(combined) / 1000.0


# ---------- per-episode driver ----------

def process_episode_patterns(episode_json_path, lang, force=False):
    """Localize all patterns of one episode and append them to the episode's
    localized JSON (episode_{lang}.json must exist — run translate_episode first)."""
    with open(episode_json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    loc_json_path = os.path.splitext(episode_json_path)[0] + lang_suffix(lang) + ".json"
    if not os.path.exists(loc_json_path):
        raise RuntimeError("localized episode not found (run translate_episode first): %s" % loc_json_path)
    with open(loc_json_path, "r", encoding="utf-8") as f:
        localized_episode = json.load(f)

    if localized_episode.get("patterns") and not force:
        print("   ⏭  Skip %s [%s]: already has localized patterns" % (episode["id"], lang))
        return loc_json_path

    zh_patterns = episode.get("patterns") or []
    if not zh_patterns:
        print("   ⏭  %s has no patterns to localize" % episode["id"])
        return loc_json_path

    level = episode.get("level", "medium")
    out_dir = os.path.join(os.path.splitext(episode_json_path)[0], "patterns%s" % lang_suffix(lang))
    os.makedirs(out_dir, exist_ok=True)

    localized_patterns = []
    for zh_pattern in zh_patterns:
        skeleton = extract_skeleton(zh_pattern)
        print("\n🌐 Localizing pattern %s (%s) → %s" % (skeleton["id"], skeleton["template"], lang))
        if not skeleton["demo_en"]:
            print("   ⚠️  no demo_en recoverable — skipping")
            continue
        loc = localize_pattern_text(zh_pattern, lang, level)
        if loc is None:
            continue  # QC-rejected; episode ships without this pattern

        audio_path, script_lines, duration = synthesize_localized_pattern_audio(
            loc, skeleton, out_dir, lang, level)
        localized_patterns.append({
            "id": skeleton["id"],
            "episode_id": skeleton["episode_id"] or episode["id"],
            "template": skeleton["template"],
            "translation": loc["translation"].strip(),
            "scene": (loc.get("scene") or "").strip(),
            "audio_url": audio_path,  # local path; upload step rewrites to OSS URL
            "duration_seconds": int(duration),
            "explainer_script": script_lines,
            "example_sentences": loc.get("example_sentences", []),
            "thumbnail_color": skeleton["thumbnail_color"],
        })
        print("   ✅ %s (%.0fs, %d subtitle rows)" % (skeleton["id"], duration, len(script_lines)))

    localized_episode["patterns"] = localized_patterns
    with open(loc_json_path, "w", encoding="utf-8") as f:
        json.dump(localized_episode, f, ensure_ascii=False, indent=2)
    print("\n✅ %s: %d/%d patterns localized → %s"
          % (episode["id"], len(localized_patterns), len(zh_patterns), loc_json_path))
    return loc_json_path


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    process_episode_patterns(sys.argv[1], sys.argv[2], force="--force" in sys.argv)
