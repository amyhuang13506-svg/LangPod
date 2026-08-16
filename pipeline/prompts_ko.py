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


# ===== Pattern explainer localization =====
#
# 韩语版不重新提取句型 —— 英语骨架（template / demo / examples 英文）来自已有
# zh pattern，GPT 只重写母语讲解层。规则从中文版 extract_patterns prompt 移植：
# 规则 1(无省略号)/4(场景+VS对比+固定结尾)/5·10(场景前缀双段)/8(intro 三段)/9(meaning 短)。
# 错误发音示范机制与中文版相同：英文原词 + 句号断开（"Could. I." TTS 自然停顿）。

# 固定台词（TTS 用），与 prompt 中的固定句式保持一致
PATTERN_DRILL_LEADIN = "자, 저를 따라 세 번 읽어 보세요."
PATTERN_DRILL_LEADIN_SUBTITLE = "자, 저를 따라 세 번 읽어 보세요 ——"
PATTERN_INTRO_LISTEN = "이제 원어민 발음을 들어 보세요."
PATTERN_INTRO_PREVIEW_PREFIX = "다음 예문의 뜻은"
PATTERN_FEELING_ENDING_PREFIX = "이 느낌을 기억하세요"

PATTERN_LOCALIZATION_PROMPT = """You are a veteran English-teaching expert whose specialty is
conveying native speakers' "language feel" (语感 / 어감) to KOREAN learners of English.
You write ALL explanations in natural spoken Korean (해요체), like a friendly Korean
podcast teacher.

=== TASK ===
An English sentence pattern was already selected from a podcast episode. The English
skeleton below is FIXED — do not change any English text. Write the Korean explainer
narration for it.

=== FIXED ENGLISH SKELETON ===
{skeleton}

=== REFERENCE (Chinese explainer of the same pattern — for content ideas ONLY;
write fresh Korean for Korean learners, do NOT translate it literally, and NEVER
output Chinese characters) ===
{zh_reference}

=== OUTPUT — valid JSON only, no markdown ===
{{
  "translation": "패턴의 한국어 뜻 (짧은 주석 포함, e.g. \\"~해도 될까요? (정중한 요청)\\")",
  "pronunciation_intro": "3 sentences, see RULE A",
  "meaning": "1-2 short sentences, see RULE B",
  "scene_and_feeling": "the core section, see RULE C",
  "examples": [
    {{"scene_prefix": "장면——감정. (see RULE D)"}},
    ...one per skeleton example, same order...
  ],
  "example_sentences": [
    {{"english": "<copy skeleton example english EXACTLY>", "translation": "예문의 자연스러운 한국어 번역"}},
    ...same order...
  ]
}}

=== RULES (every violation = failure) ===

**RULE 0 — Language purity**: Korean + the pattern's English words only.
Any Chinese character (한자 스타일 CJK ideograph) in the output = automatic failure.
Never write "dot dot dot" or "..." in any field — describe the blank with a real
example instead.

**RULE A — pronunciation_intro is EXACTLY 3 sentences:**
  [1] Pattern introduction (what it's for + the skeleton). If the template starts
      with fixed words ("Could I ___?"): "오늘은 정중하게 부탁할 때 쓰는 패턴, Could I 로
      시작하는 문형을 배워요." If the fixed words are in the middle ("I'd rather ___
      than ___"): read the whole skeleton, marking blanks with a short pause comma:
      "오늘은 선호를 나타내는 패턴, I'd rather, than, 을 배워요." (never use X/Y letters)
  [2] Preview, FIXED formula: "{preview_prefix}: <natural Korean translation of the
      demo sentence>." — must be the full sentence's translation, not an abstract label.
  [3] FIXED closing sentence, verbatim: "{listen_line}"
  End with 。/./? only — no dashes, no ellipsis. Do NOT embed the full English demo
  sentence in the intro.

**RULE B — meaning: strictly short (≤ 60 Korean chars), literal meaning only.**
  No usage scenes, no nuance, no comparisons here (they belong to scene_and_feeling).
  {trap_rule}

**RULE C — scene_and_feeling MUST contain all 4 parts (200-350 chars):**
  ① A concrete scene: "자, 이런 장면을 상상해 보세요: 당신은 ..."
  ② Feeling keywords (겸손함, 조심스러움, 부담을 덜어주는, 단도직입적인...)
  ③ A VS comparison with a similar pattern (MANDATORY): "이건 X 와 달라요. X 는 ...,
     [this pattern] 은 ..." — even for simple patterns (Could I vs Can I,
     Do you want vs Would you like).
  ④ FIXED ending formula: "{feeling_ending_prefix}——머릿속에 [장면] 이 떠오르면 입에서
     자동으로 [pattern] 이 나와요. [한국어 뜻] 을 번역하려 하지 말고, 느낌으로 바로
     말하세요." (adapt the bracketed parts, keep the structure)
  Konglish tip (optional but encouraged for pronunciation-tricky patterns): point out
  the typical Korean-learner mistake by writing the WRONG reading as separated English
  words with periods — "따로 끊어서 Could. I. 라고 읽지 마세요" (TTS pauses at the
  periods, demonstrating the mistake). Never use 한글 transliteration for the wrong way.

**RULE D — every scene_prefix is "장면——감정/태도." double structure:**
  Format: "XXX——YYY." where XXX (2-10 chars) is a concrete scene with imagery and
  YYY (5-18 chars) carries emotion/attitude/action.
  ❌ "카페——주문." (YYY is a bare noun)
  ❌ "물건 빌리기——Could I borrow it" (YYY is English)
  ✅ "카페에서 주문——조심스럽게 부탁하기."
  ✅ "회사 회의——분위기 안 깨고 다른 의견 내기."

**RULE E — example_sentences**: "english" must be copied character-for-character from
the skeleton; "translation" is a natural Korean rendering (not literal).

=== SELF-CHECK BEFORE OUTPUT ===
1. Zero CJK ideographs anywhere; zero "..." / "dot dot dot"
2. pronunciation_intro = 3 sentences, [2] uses "{preview_prefix}:", [3] is verbatim "{listen_line}"
3. scene_and_feeling contains a "달라요" comparison AND the "{feeling_ending_prefix}——" ending
4. examples count and order match the skeleton; english copied exactly
5. Natural spoken 해요체 throughout — a Korean native should hear a friendly teacher, not a translation
"""

PATTERN_SCENE_HINT = "식당 / 물건 빌리기"
