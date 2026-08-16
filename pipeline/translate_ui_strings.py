# -*- coding: utf-8 -*-
"""
UI string translation for the App's String Catalog — any target language.

Input:  all_keys.json (compiler-harvested via SWIFT_EMIT_LOC_STRINGS)
Output: Localizable.xcstrings with translations for the requested languages
        (incremental: keys already translated for a language are skipped)

Safety: format specifiers (%@ / %lld / %%) must survive translation exactly
and in order — validated per key, failed keys retried once, then reported.

Usage:
  python3 translate_ui_strings.py <all_keys.json> <Localizable.xcstrings> [langs]
  langs: comma-separated xcstrings locale codes, default "ko,en"
         e.g.  ja,zh-Hant,es,pt-BR
"""

import json
import re
import sys

from generate_script import _call_gpt

BATCH = 40

# ---------------------------------------------------------------------------
# Per-language config: xcstrings locale code → (name, terminology, register)
# CRITICAL CONTEXT shared by all: this app teaches ENGLISH to speakers of the
# UI language; the content's "translation track" is in the USER'S language.
# ---------------------------------------------------------------------------

SHARED_CONTEXT = """
CRITICAL CONTEXT: this app teaches ENGLISH to speakers of {lang_name}.
The content's "translation track" is in the USER'S language. So any reference
to 中文/中文翻译 (as the content's translation language) becomes "{lang_name}
translation" in the target language (e.g. ko 한국어 번역, ja 日本語訳,
zh-Hant 中文翻譯, es traducción al español, pt-BR tradução em português).
中英双语字幕 → bilingual subtitles in English + the user's language.
"""

LANG_CONFIG = {
    "ko": {
        "name": "Korean",
        "reject_han": True,
        "register": "해요체 for sentences, plain noun style for short labels (e.g. 재생 기록).",
        "terms": """
| zh | ko |
| 句型 | 문형 |
| 句型讲解 | 문형 해설 |
| 生词 / 词汇 | 단어 / 어휘 |
| 词义配对 | 단어 매칭 |
| 连词成句 | 문장 만들기 |
| 场景 / 情景 | 상황 |
| 词汇小课堂 | 어휘 클래스 |
| 原声播客 / 硅谷原声 | 원어민 팟캐스트 |
| 连续 X 天 | 연속 X일 |
| 第 X 遍 | X회차 |
| 已掌握 / 复习中 / 新词 | 마스터함 / 복습 중 / 새 단어 |
| 首页 / 我的 | 홈 / 프로필 |
| 打卡 | 체크인 |
""",
    },
    "ja": {
        "name": "Japanese",
        "reject_han": False,
        "register": "です・ます体 for sentences, plain noun style for short labels (e.g. 再生履歴). UI must stay concise — Japanese tends to run long.",
        "terms": """
| zh | ja |
| 句型 | 文型 |
| 句型讲解 | 文型解説 |
| 生词 / 词汇 | 単語 / 語彙 |
| 词义配对 | 単語マッチング |
| 连词成句 | 並べ替え |
| 场景 / 情景 | シーン |
| 词汇小课堂 | 語彙レッスン |
| 原声播客 / 硅谷原声 | ネイティブポッドキャスト |
| 连续 X 天 | 連続X日 |
| 第 X 遍 | X回目 |
| 已掌握 / 复习中 / 新词 | マスター済み / 復習中 / 新しい単語 |
| 首页 / 我的 | ホーム / プロフィール |
| 打卡 | チェックイン |
""",
    },
    "zh-Hant": {
        "name": "Traditional Chinese (Taiwan)",
        "reject_han": False,
        "register": "台灣慣用詞（影片 not 視頻, 網路 not 網絡, Podcast 直接用英文, 訂閱方案 not 套餐）。語氣與簡中原文一致。",
        "terms": """
| zh-Hans | zh-Hant (Taiwan) |
| 视频 | 影片 |
| 播客 | Podcast |
| 词汇 / 生词 | 單字 / 生字 |
| 词义配对 | 單字配對 |
| 连词成句 | 連詞成句 |
| 已掌握 / 复习中 / 新词 | 已掌握 / 複習中 / 新單字 |
| 中文翻译 | 中文翻譯 |
| 套餐 / 订阅 | 方案 / 訂閱 |
| 信息 | 訊息 |
""",
    },
    "es": {
        "name": "Spanish (neutral Latin American)",
        "reject_han": True,
        "register": "tuteo (tú), natural product Spanish; short labels as nouns (e.g. Historial). Sentence case for buttons.",
        "terms": """
| zh | es |
| 句型 | patrón |
| 句型讲解 | explicación del patrón |
| 生词 / 词汇 | palabras / vocabulario |
| 词义配对 | Emparejar palabras |
| 连词成句 | Ordenar la frase |
| 场景 / 情景 | escena |
| 词汇小课堂 | mini clase de vocabulario |
| 原声播客 / 硅谷原声 | pódcast nativo |
| 连续 X 天 | racha de X días |
| 第 X 遍 | ronda X |
| 已掌握 / 复习中 / 新词 | Dominadas / Repasando / Nuevas |
| 首页 / 我的 | Inicio / Perfil |
| 打卡 | check-in |
""",
    },
    "pt-BR": {
        "name": "Brazilian Portuguese",
        "reject_han": True,
        "register": "você form, natural product Portuguese; short labels as nouns (e.g. Histórico). Sentence case for buttons.",
        "terms": """
| zh | pt-BR |
| 句型 | padrão |
| 句型讲解 | explicação do padrão |
| 生词 / 词汇 | palavras / vocabulário |
| 词义配对 | Combinar palavras |
| 连词成句 | Montar a frase |
| 场景 / 情景 | cena |
| 词汇小课堂 | miniaula de vocabulário |
| 原声播客 / 硅谷原声 | podcast nativo |
| 连续 X 天 | sequência de X dias |
| 第 X 遍 | rodada X |
| 已掌握 / 复习中 / 新词 | Dominadas / Revisando / Novas |
| 首页 / 我的 | Início / Perfil |
| 打卡 | check-in |
""",
    },
    "en": {
        "name": "English (US)",
        "reject_han": True,
        "register": "natural product English, Title Case for short buttons/titles.",
        "terms": """
| zh | en |
| 句型 | pattern |
| 词义配对 | Word Match |
| 连词成句 | Sentence Builder |
| 原声播客 | raw podcasts |
| 已掌握 / 复习中 / 新词 | Mastered / Reviewing / New |
| 首页 / 我的 | Home / Profile |
""",
    },
}

PROMPT = """You are localizing a language-learning iOS app's UI from Simplified Chinese
to {lang_name}. Translate each string naturally and CONCISELY (UI labels must not
overflow buttons — keep translations as short as the Chinese or shorter when possible).

TERMINOLOGY (use these consistently):
{terms}
{shared}

RULES:
1. Format specifiers (%@, %lld, %%, %1$@ ...) must appear EXACTLY as in the source,
   same count. Reorder with positional forms (%1$@) ONLY if word order requires it.
2. Keep: emoji, "Castlingo", "Pro", punctuation style (· stays ·), line breaks (\\n).
3. Register: {register}
4. Do not add quotes or extra punctuation.

INPUT (JSON object key→source):
{payload}

OUTPUT: valid JSON only:
{{"<source key>": "<{lang_name} translation>", ...}}
Every input key must appear exactly once.
"""

SPEC_RE = re.compile(r"%(?:\d+\$)?(?:@|lld|d|.0f|f|%)")


def specs(s):
    return SPEC_RE.findall(s)


def validate(src, t, cfg):
    if not (t or "").strip():
        return ["empty"]
    problems = []
    src_specs, out_specs = specs(src), specs(t)
    if sorted(src_specs) != sorted([re.sub(r"^%\d+\$", "%", x) if False else x for x in out_specs]):
        # 允许位置化重排：把 %1$@ 归一成 %@ 后 multiset 相等即可
        norm = lambda xs: sorted(re.sub(r"(?<=%)\d+\$", "", x) for x in xs)
        if norm(src_specs) != norm(out_specs):
            problems.append("placeholder mismatch: %r vs %r" % (src_specs, out_specs))
    if cfg["reject_han"] and any("一" <= c <= "鿿" for c in t):
        problems.append("contains CJK ideographs: %r" % t[:30])
    return problems


def translate_batch(batch, lang, cfg):
    payload = json.dumps({k: k for k in batch}, ensure_ascii=False, indent=0)
    result = _call_gpt([{"role": "user", "content": PROMPT.format(
        lang_name=cfg["name"], terms=cfg["terms"],
        shared=SHARED_CONTEXT.format(lang_name=cfg["name"]),
        register=cfg["register"], payload=payload)}])
    ok, failed = {}, {}
    for k in batch:
        t = result.get(k)
        if isinstance(t, dict):  # 老格式 {"ko":..,"en":..} 防御
            t = t.get(lang)
        problems = validate(k, t, cfg)
        if problems:
            failed[k] = problems
        else:
            ok[k] = t
    return ok, failed


def run_lang(all_keys, strings, lang):
    cfg = LANG_CONFIG[lang]
    zh_keys = [k for k in all_keys
               if any("一" <= c <= "鿿" for c in k)
               and lang not in (strings.get(k, {}).get("localizations") or {})]
    print("[%s] %d keys need translation" % (lang, len(zh_keys)))
    translated, pending = {}, zh_keys
    for round_no in (1, 2):
        next_pending = []
        for i in range(0, len(pending), BATCH):
            batch = pending[i:i + BATCH]
            print("  [%s] round %d batch %d-%d..." % (lang, round_no, i, i + len(batch)))
            try:
                ok, failed = translate_batch(batch, lang, cfg)
            except Exception as e:
                print("   ⚠️ batch failed (%s), requeueing" % e)
                next_pending += batch
                continue
            translated.update(ok)
            for k, why in failed.items():
                print("   ⚠️ %r: %s" % (k[:40], why))
                next_pending.append(k)
        pending = next_pending
        if not pending:
            break
    if pending:
        print("❌ [%s] untranslated after retry (%d): %s"
              % (lang, len(pending), [k[:30] for k in pending[:10]]))
    for k, t in translated.items():
        entry = strings.setdefault(k, {})
        locs = entry.setdefault("localizations", {})
        locs[lang] = {"stringUnit": {"state": "translated", "value": t}}
    return len(translated)


def main():
    keys_path, xcstrings_path = sys.argv[1], sys.argv[2]
    langs = (sys.argv[3] if len(sys.argv) > 3 else "ko,en").split(",")
    for lang in langs:
        if lang not in LANG_CONFIG:
            sys.exit("unknown lang %r (known: %s)" % (lang, ",".join(LANG_CONFIG)))
    all_keys = list(json.load(open(keys_path)).keys())
    catalog = json.load(open(xcstrings_path))
    strings = catalog.setdefault("strings", {})
    for k in all_keys:
        strings.setdefault(k, {})
    total = 0
    for lang in langs:
        total += run_lang(all_keys, strings, lang)
    json.dump(catalog, open(xcstrings_path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
    print("✅ %s: %d keys, %d units translated (%s)"
          % (xcstrings_path, len(strings), total, ",".join(langs)))


if __name__ == "__main__":
    main()
