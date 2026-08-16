# -*- coding: utf-8 -*-
"""
Spanish (neutral Latin American) prompt segments for the localization pipeline.

Spanish specifics vs Korean:
- Latin script shares the alphabet with English — char-ratio QC is meaningless;
  CJK-leak rule stays (any ideograph = leak).
- Wrong-pronunciation demo: same English+period mechanism ("Could. I."), plus the
  classic Spanish-speaker traps (epenthetic e- before s+consonant: "espeak",
  reading vowels the Spanish way) can be called out descriptively.
- Register: tuteo (tú), warm podcast-teacher tone.
"""

EPISODE_TRANSLATION_PROMPT = """You are a professional Spanish translator and English-teaching
content editor, localizing an English learning-podcast episode for Latin American Spanish
speakers learning English.

Translate the episode below from English into natural, conversational Spanish
(neutral Latin American — no regional slang that only works in one country).

INPUT EPISODE:
{episode_payload}

OUTPUT — return ONLY valid JSON, exactly this shape:
{{
  "script": [
    {{"i": 0, "translation": "traducción natural de esta línea"}},
    ...one object per script line, same order, same count...
  ],
  "vocabulary": [
    {{"word": "the same word", "translation": "significado en español", "example_translation": "traducción del ejemplo"}},
    ...one object per vocabulary word, same order...
  ]
}}

RULES:
1. TRANSLATE FROM THE ENGLISH ONLY. Never output Chinese characters — any CJK
   ideograph in your output is an automatic failure.
2. Register: friendly spoken Spanish, tuteo (tú). Match the tone of the English
   line (casual chat stays casual; a news-style host line can be a bit more formal).
   Sound like a real Spanish-language podcast host / friends talking — not textbook
   translationese.
3. Each script translation is ONE line, covering the FULL meaning of the English
   line, at most {seg_max} characters (including spaces). Prefer shorter.
4. vocabulary "translation": a concise Spanish gloss (dictionary style, ≤ 30 chars).
5. Proper nouns and brand names stay as-is (Jensen Huang, New York → Nueva York only
   when a standard Spanish exonym exists; iPhone, ChatGPT unchanged).
6. Do NOT translate word-for-word; translate meaning. Natural Spanish word order,
   correct gender/number agreement.
7. "i" must echo the script line index you were given. Same line count, same order —
   never merge or split lines.
"""


# ===== Pattern explainer localization =====

PATTERN_DRILL_LEADIN = "Ahora, repite conmigo tres veces."
PATTERN_DRILL_LEADIN_SUBTITLE = "Ahora, repite conmigo tres veces ——"
PATTERN_INTRO_LISTEN = "Ahora escucha la pronunciación nativa."
PATTERN_INTRO_PREVIEW_PREFIX = "La siguiente frase significa"
PATTERN_FEELING_ENDING_PREFIX = "Recuerda esta sensación"

PATTERN_LOCALIZATION_PROMPT = """You are a veteran English-teaching expert whose specialty is
conveying native speakers' "language feel" to SPANISH-SPEAKING learners of English
(Latin America). You write ALL explanations in natural spoken Spanish (tuteo),
like a friendly podcast teacher.

=== TASK ===
An English sentence pattern was already selected from a podcast episode. The English
skeleton below is FIXED — do not change any English text. Write the Spanish explainer
narration for it.

=== FIXED ENGLISH SKELETON ===
{skeleton}

=== REFERENCE (Chinese explainer of the same pattern — for content ideas ONLY;
write fresh Spanish for Spanish speakers, do NOT translate it literally, and NEVER
output Chinese characters) ===
{zh_reference}

=== OUTPUT — valid JSON only, no markdown ===
{{
  "translation": "significado del patrón en español — mark the blank with ___ , NEVER with ... (e.g. \\"¿Podría ___? (petición cortés)\\")",
  "pronunciation_intro": "3 sentences, see RULE A",
  "meaning": "1-2 short sentences, see RULE B",
  "scene_and_feeling": "the core section, see RULE C",
  "examples": [
    {{"scene_prefix": "escena——emoción. (see RULE D)"}},
    ...one per skeleton example, same order...
  ],
  "example_sentences": [
    {{"english": "<copy skeleton example english EXACTLY>", "translation": "traducción natural al español"}},
    ...same order...
  ]
}}

=== RULES (every violation = failure) ===

**RULE 0 — Language purity**: Spanish + the pattern's English words only.
Any Chinese character in the output = automatic failure. Never write "dot dot dot"
or "..." in any field — describe the blank with a real example instead. Never write
Spanish phonetic respellings of English ("cud ái") — English words stay in English
spelling.

**RULE A — pronunciation_intro is EXACTLY 3 sentences:**
  [1] Pattern introduction (what it's for + the skeleton). If the template starts
      with fixed words ("Could I ___?"): "Hoy aprendemos un patrón para pedir algo
      con cortesía: la estructura que empieza con Could I." If the fixed words are
      in the middle ("I'd rather ___ than ___"): read the whole skeleton, marking
      blanks with a short pause comma: "Hoy aprendemos un patrón para expresar
      preferencias: I'd rather, than." (never use X/Y letters)
  [2] Preview, FIXED formula: "{preview_prefix}: <natural Spanish translation of the
      demo sentence>." — must be the full sentence's translation, not an abstract label.
  [3] FIXED closing sentence, verbatim: "{listen_line}"
  End with . or ? only — no dashes, no ellipsis. Do NOT embed the full English demo
  sentence in the intro.

**RULE B — meaning: strictly short (≤ 90 chars), literal meaning only.**
  No usage scenes, no nuance, no comparisons here (they belong to scene_and_feeling).
  {trap_rule}

**RULE C — scene_and_feeling MUST contain all 4 parts (250-450 chars):**
  ① A concrete scene: "Imagina esta escena: estás..."
  ② Feeling keywords (humildad, delicadeza, quitarle presión al otro, directo al grano...)
  ③ A VS comparison with a similar pattern (MANDATORY): "Esto no es lo mismo que X.
     X es..., [this pattern] es..." — even for simple patterns (Could I vs Can I,
     Do you want vs Would you like).
  ④ FIXED ending formula: "{feeling_ending_prefix}——cuando [la escena] aparezca en tu
     cabeza, [pattern] te va a salir solo. No intentes traducir [significado en
     español]: dilo directamente con la sensación." (adapt the bracketed parts,
     keep the structure)
  Pronunciation tip (optional but encouraged for tricky patterns): point out the
  typical Spanish-speaker mistake by writing the WRONG reading as separated English
  words with periods — "no lo leas separado: Could. I." (TTS pauses at the periods,
  demonstrating the mistake). You may also warn about classic traps (adding an
  'e' before s+consonant, reading vowels the Spanish way) descriptively.

**RULE D — every scene_prefix is "escena——emoción/actitud." double structure:**
  Format: "XXX——YYY." where XXX (2-6 words) is a concrete scene with imagery and
  YYY (3-8 words) carries emotion/attitude/action.
  ❌ "café——pedido." (YYY is a bare noun)
  ❌ "pedir prestado——Could I borrow it" (YYY is English)
  ✅ "en la cafetería——pidiendo con delicadeza."
  ✅ "reunión de trabajo——dar otra opinión sin romper el ambiente."

**RULE E — example_sentences**: "english" must be copied character-for-character from
the skeleton; "translation" is a natural Spanish rendering (not literal).

=== SELF-CHECK BEFORE OUTPUT ===
1. Zero CJK ideographs anywhere; zero "..." / "dot dot dot"; zero phonetic respellings
2. pronunciation_intro = 3 sentences, [2] uses "{preview_prefix}:", [3] is verbatim "{listen_line}"
3. scene_and_feeling contains a "no es lo mismo que" comparison AND the "{feeling_ending_prefix}——" ending
4. examples count and order match the skeleton; english copied exactly
5. Natural spoken Spanish (tú) throughout — a native should hear a friendly teacher, not a translation
"""

PATTERN_SCENE_HINT = "restaurante / pedir prestado"
