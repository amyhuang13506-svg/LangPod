# -*- coding: utf-8 -*-
"""
Localization pass for podcast episodes: derive episode_{lang}.json from a
finalized episode.json (English layer reused verbatim; translation layer
regenerated in the target language, straight from the English source).

Usage:
  python3 translate_episode.py output/easy/easy_20260814_001.json ko           # text only
  python3 translate_episode.py output/easy/easy_20260814_001.json ko --audio   # + {lang}.mp3

Output:
  output/{level}/{ep_id}{suffix}.json   (generic field names: translation / example_translation)
  output/{level}/{ep_id}/{lang}.mp3     (with --audio)

The zh pipeline is untouched; this reads its final artifacts only.
"""

import json
import os
import sys

from generate_script import _call_gpt
from languages import LANGUAGES, contains_han, lang_suffix, target_char_ratio

SCHEMA_VERSION = 1


def _prompt_for(lang):
    from languages import prompt_module
    try:
        return prompt_module(lang).EPISODE_TRANSLATION_PROMPT
    except (ImportError, AttributeError):
        raise ValueError("no episode translation prompt registered for lang=%s" % lang)


def _build_payload(episode):
    """Compact English-only payload GPT translates from (with full context)."""
    return json.dumps(
        {
            "title": episode["title"],
            "level": episode["level"],
            "script": [
                {"i": i, "speaker": line["speaker"], "text": line["text"]}
                for i, line in enumerate(episode["script"])
            ],
            "vocabulary": [
                {"word": v["word"], "example": v.get("example", "")}
                for v in episode.get("vocabulary", [])
            ],
        },
        ensure_ascii=False,
        indent=1,
    )


def _qc_text(text, lang, max_chars=None):
    """Return a failure reason or None. Cheap layer-0 checks; full qc/ lands in P3."""
    if not text or not text.strip():
        return "empty"
    from languages import rejects_han
    if rejects_han(lang) and contains_han(text):
        return "contains CJK ideographs (untranslated leak): %r" % text[:40]
    alpha = [c for c in text if c.isalpha()]
    # 阈值 0.3：句里合法出现英文专有名词/术语（Deep Blue、AlphaGo…）时拉丁字母
    # 可能过半，0.5 会误杀；整句没翻的情况 ratio≈0 仍会被抓
    if len(alpha) >= 4 and target_char_ratio(text, lang) < 0.3:
        return "target-language char ratio too low: %r" % text[:40]
    if max_chars and len(text) > max_chars * 2:
        # hard ceiling only at 2× the soft limit — soft violations pass with a warning
        return "far over length limit (%d > 2×%d): %r" % (len(text), max_chars, text[:40])
    return None


def _validate(result, episode, lang):
    """Alignment + per-field QC. Returns list of failure strings (empty = pass)."""
    failures = []
    cfg = LANGUAGES[lang]
    seg_max = cfg.get("podcast_seg_max_chars")

    script_out = result.get("script") or []
    if len(script_out) != len(episode["script"]):
        failures.append("script line count %d != %d" % (len(script_out), len(episode["script"])))
    else:
        for i, item in enumerate(script_out):
            reason = _qc_text(item.get("translation", ""), lang, seg_max)
            if reason:
                failures.append("script[%d]: %s" % (i, reason))

    vocab_src = episode.get("vocabulary", [])
    vocab_out = result.get("vocabulary") or []
    if len(vocab_out) != len(vocab_src):
        failures.append("vocabulary count %d != %d" % (len(vocab_out), len(vocab_src)))
    else:
        for i, (src, out) in enumerate(zip(vocab_src, vocab_out)):
            if out.get("word", "").strip().lower() != src["word"].strip().lower():
                failures.append("vocabulary[%d] word mismatch: %r != %r" % (i, out.get("word"), src["word"]))
            for key in ("translation", "example_translation"):
                reason = _qc_text(out.get(key, ""), lang)
                if reason:
                    failures.append("vocabulary[%d].%s: %s" % (i, key, reason))
    return failures


def _normalize_result(result):
    """GPT 偶尔把 translation 字段输出成 list（分句数组）——拼回字符串，
    防止下游 .strip() 崩掉。缺失/None 归空串，交给 QC 判空。"""
    def _text(v):
        if isinstance(v, list):
            return " ".join(str(x) for x in v)
        return v if isinstance(v, str) else ("" if v is None else str(v))

    for item in result.get("script") or []:
        if isinstance(item, dict):
            item["translation"] = _text(item.get("translation"))
    for item in result.get("vocabulary") or []:
        if isinstance(item, dict):
            item["translation"] = _text(item.get("translation"))
            item["example_translation"] = _text(item.get("example_translation"))
    return result


def translate_episode(episode, lang):
    """GPT-translate the episode's translation layer. Returns (script_translations,
    vocab_translations). Raises RuntimeError after one critique-guided retry.

    zh-Hant is the special channel: OpenCC conversion of the existing zh fields —
    no GPT, deterministic, free."""
    if lang == "zh-Hant":
        from hant import episode_to_hant
        return episode_to_hant(episode)
    cfg = LANGUAGES[lang]
    prompt = _prompt_for(lang).format(
        episode_payload=_build_payload(episode),
        seg_max=cfg.get("podcast_seg_max_chars", 60),
    )
    messages = [{"role": "user", "content": prompt}]

    result = _normalize_result(_call_gpt(messages))
    failures = _validate(result, episode, lang)
    if failures:
        print("   ⟳ QC failed (%d issues), retrying with critique..." % len(failures))
        critique = (
            "Your previous output failed validation:\n- "
            + "\n- ".join(failures[:20])
            + "\nReturn the corrected FULL JSON (same shape), fixing every issue."
        )
        messages.append({"role": "assistant", "content": json.dumps(result, ensure_ascii=False)})
        messages.append({"role": "user", "content": critique})
        result = _normalize_result(_call_gpt(messages))
        failures = _validate(result, episode, lang)
        if failures:
            raise RuntimeError("translation QC failed after retry: %s" % failures[:10])

    return result["script"], result["vocabulary"]


def build_localized_episode(episode, script_tr, vocab_tr, lang):
    """Assemble episode_{lang} object. English fields + timestamps copied verbatim;
    translation fields use generic names. Patterns land in P3 (omitted here)."""
    script = []
    for line, tr in zip(episode["script"], script_tr):
        item = {
            "speaker": line["speaker"],
            "text": line["text"],
            "translation": tr["translation"].strip(),
        }
        for key in ("emotion", "start", "end"):
            if key in line:
                item[key] = line[key]
        script.append(item)

    vocabulary = []
    for src, tr in zip(episode.get("vocabulary", []), vocab_tr):
        vocabulary.append({
            "word": src["word"],
            "phonetic": src.get("phonetic", ""),
            "translation": tr["translation"].strip(),
            "example": src.get("example", ""),
            "example_translation": tr.get("example_translation", "").strip(),
            "audio": src.get("audio", ""),
        })

    return {
        "id": episode["id"],
        "lang": lang,
        "schema_version": SCHEMA_VERSION,
        "title": episode["title"],
        "level": episode["level"],
        "date": episode["date"],
        "duration_seconds": episode["duration_seconds"],
        "speakers": episode.get("speakers", {}),
        "thumbnail": episode.get("thumbnail", ""),
        "audio": {
            "english": episode.get("audio", {}).get("english", ""),
            # reuse_audio_from（zh-Hant）：直接指向 zh 翻译音轨；其余语言留空，
            # 由 upload 步骤在 {lang}.mp3 上传后回填
            "translation": (
                episode.get("audio", {}).get("chinese", "")
                or episode.get("audio", {}).get("translation", "")
            ) if LANGUAGES[lang].get("reuse_audio_from") else "",
        },
        "script": script,
        "vocabulary": vocabulary,
    }


def synthesize_localized_audio(localized, json_path, lang):
    """Generate {lang}.mp3 next to the episode's other audio files."""
    import generate_audio as ga

    cfg = LANGUAGES[lang]
    tts = cfg.get("tts") or {}
    if cfg.get("reuse_audio_from"):
        print("   ♻️ %s reuses %s audio — no synthesis" % (lang, cfg["reuse_audio_from"]))
        return None
    if not tts.get("voice_male") or not tts.get("voice_female"):
        raise RuntimeError("no TTS voices configured for lang=%s" % lang)

    episode_dir = os.path.splitext(json_path)[0]
    os.makedirs(episode_dir, exist_ok=True)
    ga.detect_speakers(localized)
    audio_path, skipped, total = ga.synthesize_translation_track(
        localized,
        episode_dir,
        voice_male=tts["voice_male"],
        voice_female=tts["voice_female"],
        text_key="translation",
        filename="%s.mp3" % lang,
    )
    if total and skipped / total > 0.1:
        raise RuntimeError("%s audio: %d/%d lines failed (>10%%), episode rejected" % (lang, skipped, total))
    return audio_path


def process_episode(json_path, lang, with_audio=False):
    with open(json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    print("\n🌐 Localizing %s → %s" % (episode["id"], lang))
    script_tr, vocab_tr = translate_episode(episode, lang)
    localized = build_localized_episode(episode, script_tr, vocab_tr, lang)

    out_path = os.path.splitext(json_path)[0] + lang_suffix(lang) + ".json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(localized, f, ensure_ascii=False, indent=2)
    print("   ✅ %s (%d lines, %d words)" % (out_path, len(localized["script"]), len(localized["vocabulary"])))

    if with_audio:
        synthesize_localized_audio(localized, json_path, lang)
    return out_path


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    process_episode(sys.argv[1], sys.argv[2], with_audio="--audio" in sys.argv)
