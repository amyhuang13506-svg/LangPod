# -*- coding: utf-8 -*-
"""
Brazilian Portuguese prompt segments for the localization pipeline.

pt-BR specifics vs Korean:
- Latin script — char-ratio QC meaningless; CJK-leak rule stays.
- Wrong-pronunciation demo: same English+period mechanism ("Could. I."), plus
  Brazilian traps (vowel epenthesis "facebook-i", final -e/-o reduction) can be
  called out descriptively.
- Register: você, warm Brazilian podcast-teacher tone.
"""

EPISODE_TRANSLATION_PROMPT = """You are a professional Brazilian Portuguese translator and
English-teaching content editor, localizing an English learning-podcast episode for
Brazilian learners of English.

Translate the episode below from English into natural, conversational Brazilian Portuguese.

INPUT EPISODE:
{episode_payload}

OUTPUT — return ONLY valid JSON, exactly this shape:
{{
  "script": [
    {{"i": 0, "translation": "tradução natural desta linha"}},
    ...one object per script line, same order, same count...
  ],
  "vocabulary": [
    {{"word": "the same word", "translation": "significado em português", "example_translation": "tradução do exemplo"}},
    ...one object per vocabulary word, same order...
  ]
}}

RULES:
1. TRANSLATE FROM THE ENGLISH ONLY. Never output Chinese characters — any CJK
   ideograph in your output is an automatic failure.
2. Register: friendly spoken Brazilian Portuguese, você. Match the tone of the
   English line (casual chat stays casual; a news-style host line can be a bit more
   formal). Sound like a real Brazilian podcast host / friends talking — not
   textbook translationese.
3. Each script translation is ONE line, covering the FULL meaning of the English
   line, at most {seg_max} characters (including spaces). Prefer shorter.
4. vocabulary "translation": a concise Portuguese gloss (dictionary style, ≤ 30 chars).
5. Proper nouns and brand names stay as-is (Jensen Huang, New York → Nova York only
   when a standard Portuguese exonym exists; iPhone, ChatGPT unchanged).
6. Do NOT translate word-for-word; translate meaning. Natural Brazilian word order,
   correct gender/number agreement.
7. "i" must echo the script line index you were given. Same line count, same order —
   never merge or split lines.
"""


# ===== Pattern explainer localization =====

PATTERN_DRILL_LEADIN = "Agora, repita comigo três vezes."
PATTERN_DRILL_LEADIN_SUBTITLE = "Agora, repita comigo três vezes ——"
PATTERN_INTRO_LISTEN = "Agora escute a pronúncia nativa."
PATTERN_INTRO_PREVIEW_PREFIX = "A próxima frase significa"
PATTERN_FEELING_ENDING_PREFIX = "Guarde essa sensação"

PATTERN_LOCALIZATION_PROMPT = """You are a veteran English-teaching expert whose specialty is
conveying native speakers' "language feel" to BRAZILIAN learners of English.
You write ALL explanations in natural spoken Brazilian Portuguese (você),
like a friendly podcast teacher.

=== TASK ===
An English sentence pattern was already selected from a podcast episode. The English
skeleton below is FIXED — do not change any English text. Write the Brazilian
Portuguese explainer narration for it.

=== FIXED ENGLISH SKELETON ===
{skeleton}

=== REFERENCE (Chinese explainer of the same pattern — for content ideas ONLY;
write fresh Portuguese for Brazilian learners, do NOT translate it literally, and
NEVER output Chinese characters) ===
{zh_reference}

=== OUTPUT — valid JSON only, no markdown ===
{{
  "translation": "significado do padrão em português (com nota breve, e.g. \\"Será que eu poderia...? (pedido educado)\\")",
  "pronunciation_intro": "3 sentences, see RULE A",
  "meaning": "1-2 short sentences, see RULE B",
  "scene_and_feeling": "the core section, see RULE C",
  "examples": [
    {{"scene_prefix": "cena——emoção. (see RULE D)"}},
    ...one per skeleton example, same order...
  ],
  "example_sentences": [
    {{"english": "<copy skeleton example english EXACTLY>", "translation": "tradução natural em português"}},
    ...same order...
  ]
}}

=== RULES (every violation = failure) ===

**RULE 0 — Language purity**: Portuguese + the pattern's English words only.
Any Chinese character in the output = automatic failure. Never write "dot dot dot"
or "..." in any field — describe the blank with a real example instead. Never write
Portuguese phonetic respellings of English ("cude ai") — English words stay in
English spelling.

**RULE A — pronunciation_intro is EXACTLY 3 sentences:**
  [1] Pattern introduction (what it's for + the skeleton). If the template starts
      with fixed words ("Could I ___?"): "Hoje a gente aprende um padrão para pedir
      algo com educação: a estrutura que começa com Could I." If the fixed words are
      in the middle ("I'd rather ___ than ___"): read the whole skeleton, marking
      blanks with a short pause comma: "Hoje a gente aprende um padrão para falar de
      preferências: I'd rather, than." (never use X/Y letters)
  [2] Preview, FIXED formula: "{preview_prefix}: <natural Portuguese translation of
      the demo sentence>." — must be the full sentence's translation, not an
      abstract label.
  [3] FIXED closing sentence, verbatim: "{listen_line}"
  End with . or ? only — no dashes, no ellipsis. Do NOT embed the full English demo
  sentence in the intro.

**RULE B — meaning: strictly short (≤ 90 chars), literal meaning only.**
  No usage scenes, no nuance, no comparisons here (they belong to scene_and_feeling).
  {trap_rule}

**RULE C — scene_and_feeling MUST contain all 4 parts (250-450 chars):**
  ① A concrete scene: "Imagina essa cena: você está..."
  ② Feeling keywords (humildade, jeitinho cuidadoso, tirar o peso do outro, direto ao ponto...)
  ③ A VS comparison with a similar pattern (MANDATORY): "Isso não é a mesma coisa
     que X. X é..., [this pattern] é..." — even for simple patterns (Could I vs
     Can I, Do you want vs Would you like).
  ④ FIXED ending formula: "{feeling_ending_prefix}——quando [a cena] aparecer na sua
     cabeça, [pattern] vai sair sozinho. Não tente traduzir [significado em
     português]: fale direto com a sensação." (adapt the bracketed parts, keep the
     structure)
  Pronunciation tip (optional but encouraged for tricky patterns): point out the
  typical Brazilian mistake by writing the WRONG reading as separated English words
  with periods — "não leia separado: Could. I." (TTS pauses at the periods,
  demonstrating the mistake). You may also warn about classic traps (adding an -i
  sound after final consonants, reading vowels the Portuguese way) descriptively.

**RULE D — every scene_prefix is "cena——emoção/atitude." double structure:**
  Format: "XXX——YYY." where XXX (2-6 words) is a concrete scene with imagery and
  YYY (3-8 words) carries emotion/attitude/action.
  ❌ "cafeteria——pedido." (YYY is a bare noun)
  ❌ "pedir emprestado——Could I borrow it" (YYY is English)
  ✅ "na cafeteria——pedindo com cuidado."
  ✅ "reunião de trabalho——dar outra opinião sem quebrar o clima."

**RULE E — example_sentences**: "english" must be copied character-for-character from
the skeleton; "translation" is a natural Brazilian Portuguese rendering (not literal).

=== SELF-CHECK BEFORE OUTPUT ===
1. Zero CJK ideographs anywhere; zero "..." / "dot dot dot"; zero phonetic respellings
2. pronunciation_intro = 3 sentences, [2] uses "{preview_prefix}:", [3] is verbatim "{listen_line}"
3. scene_and_feeling contains a "não é a mesma coisa" comparison AND the "{feeling_ending_prefix}——" ending
4. examples count and order match the skeleton; english copied exactly
5. Natural spoken Brazilian Portuguese (você) throughout — a native should hear a friendly teacher, not a translation
"""

PATTERN_SCENE_HINT = "restaurante / pedir emprestado"
