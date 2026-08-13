# -*- coding: utf-8 -*-
"""
Korean prompt segments for the localization pipeline.

Only episode translation for now (P2); pattern explainer prompts land with
localize_patterns (P3). Keep every Korean-specific rule here so the main
flow stays language-agnostic.
"""

# 播客翻译层：输入英文 script + vocabulary，输出对齐的韩语翻译。
# 从英文原文直翻（不经过中文转译），带全集上下文。
EPISODE_TRANSLATION_PROMPT = """You are a professional Korean translator and English-teaching
content editor, localizing an English learning-podcast episode for Korean learners of English.

Translate the episode below from English into natural, conversational Korean.

INPUT EPISODE:
{episode_payload}

OUTPUT — return ONLY valid JSON, exactly this shape:
{{
  "script": [
    {{"i": 0, "translation": "이 줄의 한국어 번역"}},
    ...one object per script line, same order, same count...
  ],
  "vocabulary": [
    {{"word": "the same word", "translation": "한국어 뜻", "example_translation": "예문의 한국어 번역"}},
    ...one object per vocabulary word, same order...
  ]
}}

RULES:
1. TRANSLATE FROM THE ENGLISH ONLY. Never output Chinese characters (한자 포함 금지) —
   any CJK ideograph in your output is an automatic failure.
2. Register: friendly spoken Korean, 해요체 as the default. Match the tone of the
   English line (casual chat stays casual; a news-style host line can use 합니다체).
   Sound like a real Korean podcast host / friends talking — not textbook translationese.
3. Each script translation is ONE sentence-per-line, covering the FULL meaning of the
   English line, at most {seg_max} characters (including spaces). Prefer shorter.
4. vocabulary "translation": a concise Korean gloss (dictionary style, ≤ 20 chars).
   Keep the English word itself out of the gloss unless it is a loanword Koreans
   actually use (e.g. 커피, 카페 are fine).
5. Proper nouns: use the standard Korean transliteration (Jensen Huang → 젠슨 황,
   New York → 뉴욕). Keep brand/product names commonly written in Latin script as-is
   (iPhone, ChatGPT).
6. Do NOT translate word-for-word; translate meaning. Avoid awkward particles from
   English word order.
7. "i" must echo the script line index you were given. Same line count, same order —
   never merge or split lines.
"""
