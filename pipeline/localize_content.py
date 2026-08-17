# -*- coding: utf-8 -*-
"""
Generic content-layer localization: expressions / lessons / raw podcasts.

Walks OSS JSON structurally: every legacy zh field is renamed to its generic
key (plan's field-mapping table) and its value translated zh→ko; English
fields, URLs, numbers untouched. Raw-podcast transcripts are translated from
the ENGLISH segments (higher quality than zh relay).

zh originals are never modified — output is sidecar *_ko files only.

Usage:
  python3 localize_content.py expressions
  python3 localize_content.py lessons
  python3 localize_content.py raw --transcripts 20     # master for all, transcripts for recent N
"""

import argparse
import json
import re
import sys

from generate_script import _call_gpt
from languages import LANGUAGES, contains_han, lang_suffix
from upload_oss import get_bucket

# zh key → generic key（与 App CastlingoDecoder / docs 方案表一致）
LEGACY_MAP = {
    "translation_zh": "translation",
    "example_zh": "example_translation",
    "text_zh": "text_translation",
    "title_zh": "title_translation",
    "category_zh": "category_translation",
    "name_zh": "name_translation",
    "country_zh": "country_translation",
    "culture_tips_zh": "culture_tips",
    "setup_zh": "setup",
    "your_role_zh": "your_role",
    "other_role_zh": "other_role",
    "note_zh": "note",
    "meaning_zh": "meaning",
    "usage_zh": "usage",
    "country_note_zh": "country_note",
    "summary_zh": "summary",
    "group_zh": "group_translation",
    "zh": "translation",
    "chinese": "translation",
}
# generic-named keys whose zh VALUES still need translation (no rename)
# scene: zh pattern 的场景 tag 是中文字符串（表达库里的 scene 是对象，会正常递归，不受影响）
TRANSLATE_IN_PLACE = {"desc", "topic", "scene"}

BATCH = 50


# ---------- structural walk ----------

def collect_and_rename(obj, texts, path=""):
    """Deep-copy with legacy keys renamed; zh values registered in `texts`
    (id → source) and replaced by placeholder ids for later substitution."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            nk = LEGACY_MAP.get(k, k)
            p = "%s.%s" % (path, nk)
            if (k in LEGACY_MAP or k in TRANSLATE_IN_PLACE):
                if isinstance(v, str) and contains_han(v):
                    tid = "T%d" % len(texts)
                    texts[tid] = v
                    out[nk] = "\x00" + tid
                elif isinstance(v, list) and all(isinstance(i, str) for i in v):
                    items = []
                    for i in v:
                        if contains_han(i):
                            tid = "T%d" % len(texts)
                            texts[tid] = i
                            items.append("\x00" + tid)
                        else:
                            items.append(i)
                    out[nk] = items
                else:
                    out[nk] = collect_and_rename(v, texts, p)
            else:
                out[nk] = collect_and_rename(v, texts, p)
        return out
    if isinstance(obj, list):
        return [collect_and_rename(i, texts, path) for i in obj]
    return obj


def substitute(obj, translated):
    if isinstance(obj, dict):
        return {k: substitute(v, translated) for k, v in obj.items()}
    if isinstance(obj, list):
        return [substitute(i, translated) for i in obj]
    if isinstance(obj, str) and obj.startswith("\x00"):
        return translated[obj[1:]]
    return obj


# ---------- translation ----------

# 各语言语体规则（prompt 片段）。zh-Hant 不在此列 —— 走 OpenCC 机械转换。
LANG_STYLE = {
    "ko": {
        "name": "Korean",
        "sentence_rule": "sentences use 해요체",
        "audience": "KOREAN",
        "seg_rule": "해요체 where speech-like; proper nouns in standard Korean transliteration",
    },
    "ja": {
        "name": "Japanese",
        "sentence_rule": "sentences use natural です・ます体",
        "audience": "JAPANESE",
        "seg_rule": "natural spoken Japanese; proper nouns in standard katakana transliteration",
    },
    "es": {
        "name": "Spanish (neutral Latin American)",
        "sentence_rule": "sentences use natural spoken Spanish (tuteo)",
        "audience": "SPANISH-SPEAKING",
        "seg_rule": "natural spoken Spanish (tú); keep proper nouns as-is",
    },
    "pt-BR": {
        "name": "Brazilian Portuguese",
        "sentence_rule": "sentences use natural spoken Brazilian Portuguese (você)",
        "audience": "BRAZILIAN",
        "seg_rule": "natural spoken Brazilian Portuguese (você); keep proper nouns as-is",
    },
}

LOC_PROMPT = """You are localizing a language-learning app's content from Simplified
Chinese to natural {lang_name}, for {audience} learners of ENGLISH.

Content types you'll see: word glosses, example-sentence translations, usage/nuance
notes, culture tips, category names, scene descriptions, topics.

RULES:
1. Natural {lang_name}; short labels stay short (category/topic names 2-6 words);
   {sentence_rule}.
2. {purity} Keep embedded English words/brand names as-is.
3. Culture tips or notes written from a Chinese-speaker perspective (e.g. comparing
   to Chinese habits/language) → rewrite for a {audience} audience (keep the English
   knowledge point, swap the frame of reference).
4. Word glosses stay dictionary-style concise.

INPUT (id → Chinese text):
{payload}

OUTPUT: valid JSON only: {{"<id>": "<{lang_name}>", ...}} — every id exactly once."""

SEGMENTS_PROMPT = """Translate these English video-subtitle segments into natural
{lang_name}. Rules: {seg_rule}; {purity_short} one translation per segment,
same count and order; concise — these are subtitles.

INPUT (JSON array of English segments):
{payload}

OUTPUT: valid JSON array of {lang_name} strings, same length."""


def _purity(lang):
    from languages import rejects_han
    if rejects_han(lang):
        return ("NEVER output Chinese characters.", "never output Chinese characters;")
    return ("The output must read as native %s, not Chinese glossed over." % LANG_STYLE[lang]["name"], "")


def _qc_out(text, lang):
    from languages import rejects_han
    if not (text and text.strip()):
        return False
    return not (rejects_han(lang) and contains_han(text))


def translate_texts(texts, lang):
    """zh→{lang} batch translation with QC + one retry per failed batch."""
    style = LANG_STYLE[lang]
    purity, _ = _purity(lang)
    out = {}
    ids = list(texts.keys())
    for i in range(0, len(ids), BATCH):
        chunk = ids[i:i + BATCH]
        payload = json.dumps({t: texts[t] for t in chunk}, ensure_ascii=False)
        prompt = LOC_PROMPT.format(lang_name=style["name"], audience=style["audience"],
                                   sentence_rule=style["sentence_rule"], purity=purity,
                                   payload=payload)
        for attempt in (1, 2):
            try:
                result = _call_gpt([{"role": "user", "content": prompt}])
                bad = [t for t in chunk if not _qc_out(result.get(t, ""), lang)]
                if not bad:
                    out.update({t: result[t].strip() for t in chunk})
                    break
                if attempt == 2:
                    raise RuntimeError("QC failed for %d items: %s" % (len(bad), bad[:3]))
            except Exception as e:
                if attempt == 2:
                    raise
                print("   ⟳ batch retry (%s)" % e)
        print("   🌐 translated %d/%d" % (min(i + BATCH, len(ids)), len(ids)))
    return out


def localize_json(doc, lang="ko"):
    texts = {}
    skeleton = collect_and_rename(doc, texts)
    if not texts:
        return skeleton
    if lang == "zh-Hant":
        from hant import to_hant
        translated = {t: to_hant(src) for t, src in texts.items()}
    else:
        translated = translate_texts(texts, lang)
    return substitute(skeleton, translated)


# ---------- OSS helpers ----------

def get_json(bucket, key):
    return json.loads(bucket.get_object(key).read())


def put_json(bucket, key, doc):
    bucket.put_object(key, json.dumps(doc, ensure_ascii=False, indent=2).encode("utf-8"))
    print("   ☁️  %s" % key)


def exists(bucket, key):
    return bucket.object_exists(key)


# ---------- expressions ----------

def run_expressions(bucket, lang, force=False):
    suffix = lang_suffix(lang)
    index = get_json(bucket, "expressions/index.json")
    print("== expressions index (%d groups) ==" % len(index.get("groups", [])))
    put_json(bucket, "expressions/index%s.json" % suffix, localize_json(index, lang))

    cat_ids = [c["id"] for g in index.get("groups", []) for c in g.get("categories", [])]
    for cid in cat_ids:
        out_key = "expressions/%s%s.json" % (cid, suffix)
        if not force and exists(bucket, out_key):
            print("   ⏭  %s" % out_key)
            continue
        try:
            doc = get_json(bucket, "expressions/%s.json" % cid)
        except Exception as e:
            print("   ⚠️  %s: %s" % (cid, e))
            continue
        print("== expressions/%s (%d items) ==" % (cid, len(doc.get("expressions", []))))
        put_json(bucket, out_key, localize_json(doc, lang))


# ---------- lessons ----------

def run_lessons(bucket, lang, force=False):
    suffix = lang_suffix(lang)
    countries = get_json(bucket, "lessons/countries.json")
    put_json(bucket, "lessons/countries%s.json" % suffix, localize_json(countries, lang))

    country_ids = [c["id"] for c in countries.get("countries", [])] + ["daily"]
    for c in country_ids:
        try:
            index = get_json(bucket, "lessons/%s/index.json" % c)
        except Exception:
            continue
        print("== lessons/%s (%d lessons) ==" % (c, len(index.get("lessons", []))))
        put_json(bucket, "lessons/%s/index%s.json" % (c, suffix), localize_json(index, lang))
        for item in index.get("lessons", []):
            lid = item["id"]
            out_key = "lessons/%s/%s/lesson%s.json" % (c, lid, suffix)
            if not force and exists(bucket, out_key):
                print("   ⏭  %s" % lid)
                continue
            try:
                doc = get_json(bucket, "lessons/%s/%s/lesson.json" % (c, lid))
            except Exception as e:
                print("   ⚠️  %s: %s" % (lid, e))
                continue
            put_json(bucket, out_key, localize_json(doc, lang))

    try:
        today = get_json(bucket, "lessons/today.json")
        put_json(bucket, "lessons/today%s.json" % suffix, localize_json(today, lang))
    except Exception as e:
        print("   ⚠️  today.json: %s" % e)


# ---------- raw podcasts ----------

# App 端探索分类的中文关键词逻辑（RawPodcast.exploreCategory 的服务器侧镜像）——
# master_ko 直接带 explore_category slug，App 不再依赖中文 topic 关键词。
def explore_slug(topic):
    t = topic or ""
    if any(k in t for k in ("娱乐", "时尚", "文化")): return "entertainment"
    if any(k in t for k in ("两性", "心理", "关系")): return "relationship"
    if any(k in t for k in ("科学", "数学", "科普")): return "science"
    if any(k in t for k in ("创业", "商业", "投资")): return "business"
    if "评测" in t: return "tech"
    if any(k in t for k in ("思想", "演讲", "学术", "访谈", "健康")): return "mind"
    return None


def translate_segments_en(en_list, lang):
    """en→{lang} subtitle segments, batched with count validation.
    A batch that fails twice degrades to per-segment translation; a segment
    that still fails yields None (App shows English-only for that line)."""
    style = LANG_STYLE[lang]
    _, purity_short = _purity(lang)

    def _prompt(payload):
        return SEGMENTS_PROMPT.format(lang_name=style["name"], seg_rule=style["seg_rule"],
                                      purity_short=purity_short,
                                      payload=json.dumps(payload, ensure_ascii=False))

    out = []
    B = 25
    for i in range(0, len(en_list), B):
        chunk = en_list[i:i + B]
        ok = False
        for attempt in (1, 2):
            try:
                result = _call_gpt([{"role": "user", "content": _prompt(chunk)}])
            except Exception:
                continue
            if isinstance(result, dict):  # GPT sometimes wraps the array
                for v in result.values():
                    if isinstance(v, list):
                        result = v
                        break
            if isinstance(result, list) and len(result) == len(chunk) and all(_qc_out(s, lang) for s in result):
                out.extend(s.strip() for s in result)
                ok = True
                break
        if not ok:
            print("   ⚠️  batch %d degraded to per-segment" % i)
            for seg in chunk:
                try:
                    r = _call_gpt([{"role": "user", "content": _prompt([seg])}])
                    if isinstance(r, list) and len(r) == 1 and _qc_out(r[0], lang):
                        out.append(r[0].strip())
                        continue
                except Exception:
                    pass
                out.append(None)  # English-only fallback for this line
    return out


def run_raw(bucket, lang, transcript_limit=20, force=False):
    suffix = lang_suffix(lang)
    master = get_json(bucket, "raw_podcasts/raw_podcasts.json")
    print("== raw master: %d items ==" % len(master))

    # 1. 全量：topic/summary 韩语化 + explore_category slug（从 zh topic 派生）
    for item in master:
        slug = explore_slug(item.get("topic"))
        if slug:
            item["explore_category"] = slug
    master_ko = localize_json(master, lang)

    # 2. 近 N 条：transcript_ko（从英文段直翻）
    by_date = sorted(master_ko, key=lambda x: x.get("crawled_at") or x.get("published_at") or "", reverse=True)
    done = 0
    for item in by_date:
        if done >= transcript_limit:
            break
        turl = item.get("transcript_url") or ""
        if not turl:
            continue
        pid = item["id"]
        t_key = "raw_podcasts/%s/transcript.json" % pid
        out_key = "raw_podcasts/%s/transcript%s.json" % (pid, suffix)
        if not force and exists(bucket, out_key):
            item["transcript_url"] = turl.replace("transcript.json", "transcript%s.json" % suffix)
            done += 1
            continue
        try:
            tr = get_json(bucket, t_key)
        except Exception as e:
            print("   ⚠️  %s transcript: %s" % (pid, e))
            continue
        segs = tr.get("segments", [])
        print("== transcript %s (%d segments) ==" % (pid, len(segs)))
        if lang == "zh-Hant":
            # 特殊通道：直接繁化已有中文字幕，零 GPT 成本
            from hant import to_hant
            tr_texts = [to_hant(s.get("zh")) if s.get("zh") else None for s in segs]
        else:
            try:
                tr_texts = translate_segments_en([s.get("en", "") for s in segs], lang)
            except Exception as e:
                print("   ❌ transcript %s failed (%s) — skipping" % (pid, e))
                continue
        out_segs = []
        for s, t in zip(segs, tr_texts):
            ns = {k: v for k, v in s.items() if k != "zh"}
            if t:
                ns["translation"] = t
            out_segs.append(ns)
        put_json(bucket, out_key, {"podcast_id": pid, "lang": lang, "segments": out_segs})
        item["transcript_url"] = turl.replace("transcript.json", "transcript%s.json" % suffix)
        done += 1

    put_json(bucket, "raw_podcasts/raw_podcasts%s.json" % suffix, master_ko)
    print("✅ raw master%s uploaded (%d transcripts localized)" % (suffix, done))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("type", choices=["expressions", "lessons", "raw"])
    ap.add_argument("--lang", default="ko")
    ap.add_argument("--transcripts", type=int, default=20)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    bucket = get_bucket()
    if args.type == "expressions":
        run_expressions(bucket, args.lang, args.force)
    elif args.type == "lessons":
        run_lessons(bucket, args.lang, args.force)
    else:
        run_raw(bucket, args.lang, args.transcripts, args.force)


if __name__ == "__main__":
    main()
