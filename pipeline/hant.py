# -*- coding: utf-8 -*-
"""
zh-Hant special channel: OpenCC s2twp (Simplified → Traditional with Taiwan
wording: 视频→影片, 软件→軟體, 网络→網路...). No GPT, no TTS — audio reuses zh.

Used by translate_episode (episode derivation) and localize_content (walker).
"""

from opencc import OpenCC

_cc = OpenCC("s2twp")


def to_hant(text):
    """Simplified Chinese → Traditional (Taiwan wording). Non-str passes through."""
    if not isinstance(text, str) or not text:
        return text
    return _cc.convert(text)


def episode_to_hant(episode):
    """Derive (script_translations, vocab_translations) for build_localized_episode
    from a legacy zh episode's *_zh fields — same return shape as the GPT path."""
    script_tr = [
        {"i": i, "translation": to_hant(line.get("translation_zh", line.get("chinese", "")))}
        for i, line in enumerate(episode.get("script", []))
    ]
    vocab_tr = [
        {
            "word": v.get("word", ""),
            "translation": to_hant(v.get("translation_zh", "")),
            "example_translation": to_hant(v.get("example_zh", "")),
        }
        for v in episode.get("vocabulary", [])
    ]
    return script_tr, vocab_tr
