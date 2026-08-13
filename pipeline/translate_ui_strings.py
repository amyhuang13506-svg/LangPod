# -*- coding: utf-8 -*-
"""
UI string translation for the App's String Catalog.

Input:  all_keys.json (compiler-harvested via SWIFT_EMIT_LOC_STRINGS)
Output: Localizable.xcstrings with ko + en translations

Safety: format specifiers (%@ / %lld / %%) must survive translation exactly
and in order — validated per key, failed keys retried once, then reported.

Usage:
  python3 translate_ui_strings.py <all_keys.json> <path/to/Localizable.xcstrings>
"""

import json
import re
import sys

from generate_script import _call_gpt

BATCH = 40

# 产品术语表 — 保证 405 个 key 全局一致
TERMS = """
TERMINOLOGY (use these consistently):
| zh | ko | en |
| 句型 | 문형 | pattern |
| 句型讲解 | 문형 해설 | pattern explainer |
| 生词 / 词汇 | 단어 / 어휘 | words / vocabulary |
| 词义配对 | 단어 매칭 | Word Match |
| 连词成句 | 문장 만들기 | Sentence Builder |
| 场景 / 情景 | 상황 | scene |
| 词汇小课堂 | 어휘 클래스 | vocab lesson |
| 原声播客 / 硅谷原声 | 원어민 팟캐스트 | raw podcasts |
| 连续 X 天 / streak | 연속 X일 | X-day streak |
| 第 X 遍 | X회차 | round X |
| 已掌握 / 复习中 / 新词 | 마스터함 / 복습 중 / 새 단어 | Mastered / Reviewing / New |
| 首页 | 홈 | Home |
| 我的 | 프로필 | Profile |
| 付费墙/会员 Pro | Pro | Pro |
| 打卡 | 체크인 | check-in |

CRITICAL CONTEXT: this app teaches ENGLISH to speakers of the UI language.
The "translation track" is in the USER'S language. So any reference to
中文/中文翻译 (as the content's translation language) becomes 한국어/한국어 번역
in ko and "translation" (language-neutral) in en. 中英双语字幕 → ko: 영한 자막,
en: bilingual subtitles.
"""

PROMPT = """You are localizing a language-learning iOS app's UI from Simplified Chinese
to Korean and English. Translate each string naturally and CONCISELY (UI labels must
not overflow buttons — Korean should be as short as the Chinese or shorter when possible).

{terms}

RULES:
1. Format specifiers (%@, %lld, %%, %1$@ ...) must appear EXACTLY as in the source,
   same count, same order. Never translate or drop them.
2. Keep: emoji, "Castlingo", "Pro", punctuation style (· stays ·), line breaks (\\n).
3. ko register: 해요체 for sentences, plain noun style for short labels (e.g. 재생 기록).
4. en: natural product English, Title Case for buttons/titles when short.
5. Do not add quotes or extra punctuation.

INPUT (JSON object key→source):
{payload}

OUTPUT: valid JSON only:
{{"<source key>": {{"ko": "...", "en": "..."}}, ...}}
Every input key must appear exactly once.
"""

SPEC_RE = re.compile(r"%(?:\d+\$)?(?:@|lld|d|.0f|f|%)")


def specs(s):
    return SPEC_RE.findall(s)


def validate(src, out):
    problems = []
    for lang in ("ko", "en"):
        t = out.get(lang, "")
        if not t.strip():
            problems.append("%s empty" % lang)
            continue
        if specs(t) != specs(src):
            problems.append("%s placeholder mismatch: %r vs %r" % (lang, specs(src), specs(t)))
        if lang == "ko" and any("一" <= c <= "鿿" for c in t):
            problems.append("ko contains CJK ideographs: %r" % t[:30])
    return problems


def translate_batch(batch):
    payload = json.dumps({k: k for k in batch}, ensure_ascii=False, indent=0)
    result = _call_gpt([{"role": "user", "content": PROMPT.format(terms=TERMS, payload=payload)}])
    ok, failed = {}, {}
    for k in batch:
        out = result.get(k) or {}
        problems = validate(k, out)
        if problems:
            failed[k] = problems
        else:
            ok[k] = out
    return ok, failed


def main():
    keys_path, xcstrings_path = sys.argv[1], sys.argv[2]
    all_keys = list(json.load(open(keys_path)).keys())
    existing = json.load(open(xcstrings_path)).get("strings", {})
    done = {k for k, v in existing.items() if v.get("localizations")}
    zh_keys = [k for k in all_keys
               if any("一" <= c <= "鿿" for c in k) and k not in done]
    print("keys: %d total, %d already translated, %d need translation"
          % (len(all_keys), len(done), len(zh_keys)))

    translated = {}
    pending = zh_keys
    for round_no in (1, 2):
        next_pending = []
        for i in range(0, len(pending), BATCH):
            batch = pending[i:i + BATCH]
            print("  round %d batch %d-%d..." % (round_no, i, i + len(batch)))
            try:
                ok, failed = translate_batch(batch)
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
        print("❌ untranslated after retry (%d): %s" % (len(pending), [k[:30] for k in pending[:10]]))

    catalog = json.load(open(xcstrings_path))
    strings = catalog.setdefault("strings", {})
    for k in all_keys:
        entry = strings.setdefault(k, {})
        if k in translated:
            entry["localizations"] = {
                "ko": {"stringUnit": {"state": "translated", "value": translated[k]["ko"]}},
                "en": {"stringUnit": {"state": "translated", "value": translated[k]["en"]}},
            }
        # non-Chinese keys (already English/symbols): no localization needed — key is the fallback
    json.dump(catalog, open(xcstrings_path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
    print("✅ %s: %d keys, %d translated" % (xcstrings_path, len(strings), len(translated)))


if __name__ == "__main__":
    main()
