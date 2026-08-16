# -*- coding: utf-8 -*-
"""
QC Layer 0 — mechanical rules for localized content. Free and instant.
Catches the failure modes LLM translation actually produces: untranslated
Chinese leaking through, wrong-language output, runaway length, missing
fixed formulas, broken alignment.

Every check returns a list of failure-reason strings (empty = pass), so
callers can feed them straight back into a critique-guided retry.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from languages import LANGUAGES, contains_han, prompt_module, rejects_han, target_char_ratio


def check_text(text, lang, field="text", max_chars=None, allow_empty=False):
    """Generic per-field checks: emptiness, CJK leak, target-char ratio, length."""
    failures = []
    text = (text or "").strip()
    if not text:
        if not allow_empty:
            failures.append("%s: empty" % field)
        return failures
    if rejects_han(lang) and contains_han(text):
        failures.append("%s: contains CJK ideographs (untranslated leak): %r" % (field, text[:40]))
    if "dot dot dot" in text or "..." in text:
        failures.append("%s: contains ellipsis placeholder: %r" % (field, text[:40]))
    alpha = [c for c in text if c.isalpha()]
    if len(alpha) >= 4 and target_char_ratio(text, lang) < 0.5:
        failures.append("%s: target-language char ratio too low: %r" % (field, text[:40]))
    if max_chars and len(text) > max_chars * 2:
        failures.append("%s: far over length limit (%d > 2x%d)" % (field, len(text), max_chars))
    return failures


def check_pattern_localization(loc, skeleton, lang):
    """L0 checks for a localized pattern explainer (output of the pattern
    localization prompt). `skeleton` is the fixed English skeleton dict."""
    failures = []
    try:
        pm = prompt_module(lang)
        fixed = {
            "preview": pm.PATTERN_INTRO_PREVIEW_PREFIX,
            "listen": pm.PATTERN_INTRO_LISTEN,
            "ending": pm.PATTERN_FEELING_ENDING_PREFIX,
        }
    except (ImportError, AttributeError):
        fixed = None

    failures += check_text(loc.get("translation"), lang, "translation", max_chars=60)
    failures += check_text(loc.get("pronunciation_intro"), lang, "pronunciation_intro", max_chars=120)
    failures += check_text(loc.get("meaning"), lang, "meaning", max_chars=80)
    failures += check_text(loc.get("scene_and_feeling"), lang, "scene_and_feeling", max_chars=400)

    intro = loc.get("pronunciation_intro") or ""
    feeling = loc.get("scene_and_feeling") or ""
    if fixed:
        if fixed["preview"] not in intro:
            failures.append("pronunciation_intro: missing fixed preview formula %r" % fixed["preview"])
        if fixed["listen"] not in intro:
            failures.append("pronunciation_intro: missing fixed closing line %r" % fixed["listen"])
        if fixed["ending"] not in feeling:
            failures.append("scene_and_feeling: missing fixed ending formula %r" % fixed["ending"])

    # examples alignment
    skeleton_examples = skeleton.get("examples", [])
    loc_examples = loc.get("examples") or []
    if len(loc_examples) != len(skeleton_examples):
        failures.append("examples count %d != skeleton %d" % (len(loc_examples), len(skeleton_examples)))
    else:
        for i, ex in enumerate(loc_examples):
            failures += check_text(ex.get("scene_prefix"), lang, "examples[%d].scene_prefix" % i, max_chars=40)

    # example_sentences: english must match skeleton exactly
    skeleton_sents = skeleton.get("example_sentences", [])
    loc_sents = loc.get("example_sentences") or []
    if len(loc_sents) != len(skeleton_sents):
        failures.append("example_sentences count %d != skeleton %d" % (len(loc_sents), len(skeleton_sents)))
    else:
        for i, (src, out) in enumerate(zip(skeleton_sents, loc_sents)):
            if (out.get("english") or "").strip() != (src.get("english") or "").strip():
                failures.append("example_sentences[%d].english altered: %r" % (i, out.get("english", "")[:40]))
            failures += check_text(out.get("translation"), lang, "example_sentences[%d].translation" % i, max_chars=60)

    return failures
