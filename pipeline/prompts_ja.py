# -*- coding: utf-8 -*-
"""
Japanese prompt segments for the localization pipeline (mirror of prompts_ko).

Japanese specifics vs Korean:
- Output legitimately contains kanji — NO CJK-leak rule (QC: rejects_han=False).
  Purity rule instead: no SIMPLIFIED-Chinese-only phrasing; the judge checks
  "reads like native Japanese, not Chinese glossed in kanji".
- Wrong-pronunciation demo: same English+period mechanism ("Could. I."),
  katakana transliteration of the wrong way is BANNED (カタカナ発音を書かない) —
  TTS would read it as normal Japanese and lose the contrast.
- Register: だ/です・ます mixed natural podcast speech (friendly teacher tone).
"""

# 播客翻译层：输入英文 script + vocabulary，输出对齐的日语翻译。
EPISODE_TRANSLATION_PROMPT = """You are a professional Japanese translator and English-teaching
content editor, localizing an English learning-podcast episode for Japanese learners of English.

Translate the episode below from English into natural, conversational Japanese.

INPUT EPISODE:
{episode_payload}

OUTPUT — return ONLY valid JSON, exactly this shape:
{{
  "script": [
    {{"i": 0, "translation": "この行の自然な日本語訳"}},
    ...one object per script line, same order, same count...
  ],
  "vocabulary": [
    {{"word": "the same word", "translation": "日本語の意味", "example_translation": "例文の日本語訳"}},
    ...one object per vocabulary word, same order...
  ]
}}

RULES:
1. TRANSLATE FROM THE ENGLISH ONLY — never relay through Chinese. The output must
   read as native Japanese (natural particles, natural word order), not translationese.
2. Register: friendly spoken Japanese. Casual dialogue between friends uses natural
   casual speech (〜だよね、〜じゃない?); a news-style host line uses です・ます体.
   Sound like a real Japanese podcast host / friends talking.
3. Each script translation is ONE line, covering the FULL meaning of the English
   line, at most {seg_max} characters. Prefer shorter.
4. vocabulary "translation": a concise Japanese gloss (dictionary style, ≤ 20 chars).
   Keep the English word out of the gloss unless it is a loanword Japanese actually
   use (コーヒー、カフェ are fine).
5. Proper nouns: standard katakana transliteration (Jensen Huang → ジェンスン・フアン,
   New York → ニューヨーク). Keep brand names commonly written in Latin script as-is
   (iPhone, ChatGPT).
6. Do NOT translate word-for-word; translate meaning.
7. "i" must echo the script line index you were given. Same line count, same order —
   never merge or split lines.
"""


# ===== Pattern explainer localization =====

# 固定台词（TTS 用），与 prompt 中的固定句式保持一致
PATTERN_DRILL_LEADIN = "はい、私のあとについて3回読んでみましょう。"
PATTERN_DRILL_LEADIN_SUBTITLE = "はい、私のあとについて3回読んでみましょう ——"
PATTERN_INTRO_LISTEN = "では、ネイティブの発音を聞いてみましょう。"
PATTERN_INTRO_PREVIEW_PREFIX = "次の例文の意味は"
PATTERN_FEELING_ENDING_PREFIX = "この感覚を覚えてください"

PATTERN_LOCALIZATION_PROMPT = """You are a veteran English-teaching expert whose specialty is
conveying native speakers' "language feel" (語感) to JAPANESE learners of English.
You write ALL explanations in natural spoken Japanese, like a friendly Japanese
podcast teacher (です・ます体 base, warm and direct).

=== TASK ===
An English sentence pattern was already selected from a podcast episode. The English
skeleton below is FIXED — do not change any English text. Write the Japanese explainer
narration for it.

=== FIXED ENGLISH SKELETON ===
{skeleton}

=== REFERENCE (Chinese explainer of the same pattern — for content ideas ONLY;
write fresh Japanese for Japanese learners, do NOT translate it literally) ===
{zh_reference}

=== OUTPUT — valid JSON only, no markdown ===
{{
  "translation": "パターンの日本語の意味（短い注釈つき、e.g. \\"〜してもいいですか？（丁寧なお願い）\\"）",
  "pronunciation_intro": "3 sentences, see RULE A",
  "meaning": "1-2 short sentences, see RULE B",
  "scene_and_feeling": "the core section, see RULE C",
  "examples": [
    {{"scene_prefix": "場面——気持ち。(see RULE D)"}},
    ...one per skeleton example, same order...
  ],
  "example_sentences": [
    {{"english": "<copy skeleton example english EXACTLY>", "translation": "例文の自然な日本語訳"}},
    ...same order...
  ]
}}

=== RULES (every violation = failure) ===

**RULE 0 — Language purity**: natural Japanese + the pattern's English words only.
The text must read as NATIVE Japanese — never Chinese-style phrasing rendered in
kanji. Never write "dot dot dot" or "..." in any field — describe the blank with a
real example instead. Never write katakana transliterations of English pronunciation
(クッド・アイ etc.) — English words stay in Latin script.

**RULE A — pronunciation_intro is EXACTLY 3 sentences:**
  [1] Pattern introduction (what it's for + the skeleton). If the template starts
      with fixed words ("Could I ___?"): "今日は、丁寧にお願いするときのパターン、
      Could I で始まる文型を学びます。" If the fixed words are in the middle
      ("I'd rather ___ than ___"): read the whole skeleton, marking blanks with a
      short pause comma: "今日は、好みを伝えるパターン、I'd rather, than, を学びます。"
      (never use X/Y letters)
  [2] Preview, FIXED formula: "{preview_prefix}: <natural Japanese translation of the
      demo sentence>。" — must be the full sentence's translation, not an abstract label.
  [3] FIXED closing sentence, verbatim: "{listen_line}"
  End with 。/？ only — no dashes, no ellipsis. Do NOT embed the full English demo
  sentence in the intro.

**RULE B — meaning: strictly short (≤ 60 Japanese chars), literal meaning only.**
  No usage scenes, no nuance, no comparisons here (they belong to scene_and_feeling).
  {trap_rule}

**RULE C — scene_and_feeling MUST contain all 4 parts (200-350 chars):**
  ① A concrete scene: "こんな場面を想像してみてください：あなたは..."
  ② Feeling keywords (謙虚さ、遠慮がち、相手の負担を軽くする、単刀直入...)
  ③ A VS comparison with a similar pattern (MANDATORY): "これは X とは違います。X は...、
     [this pattern] は..." — even for simple patterns (Could I vs Can I,
     Do you want vs Would you like).
  ④ FIXED ending formula: "{feeling_ending_prefix}——頭の中に[場面]が浮かんだら、口から
     自然に [pattern] が出てきます。[日本語の意味]を訳そうとせず、感覚でそのまま
     言いましょう。" (adapt the bracketed parts, keep the structure)
  Pronunciation tip (optional but encouraged for tricky patterns): point out the
  typical Japanese-learner mistake by writing the WRONG reading as separated English
  words with periods — "区切って Could. I. と読まないでください" (TTS pauses at the
  periods, demonstrating the mistake). Never use katakana for the wrong way.

**RULE D — every scene_prefix is "場面——気持ち/態度。" double structure:**
  Format: "XXX——YYY。" where XXX (2-10 chars) is a concrete scene with imagery and
  YYY (5-18 chars) carries emotion/attitude/action.
  ❌ "カフェ——注文。" (YYY is a bare noun)
  ❌ "物を借りる——Could I borrow it" (YYY is English)
  ✅ "カフェで注文——遠慮がちにお願いする。"
  ✅ "会社の会議——空気を壊さずに別の意見を出す。"

**RULE E — example_sentences**: "english" must be copied character-for-character from
the skeleton; "translation" is a natural Japanese rendering (not literal).

=== SELF-CHECK BEFORE OUTPUT ===
1. Zero "..." / "dot dot dot"; zero katakana English transliterations
2. pronunciation_intro = 3 sentences, [2] uses "{preview_prefix}:", [3] is verbatim "{listen_line}"
3. scene_and_feeling contains a "違います" comparison AND the "{feeling_ending_prefix}——" ending
4. examples count and order match the skeleton; english copied exactly
5. Natural spoken Japanese throughout — a Japanese native should hear a friendly teacher, not a translation
"""

PATTERN_SCENE_HINT = "レストラン / 物を借りる"
