# -*- coding: utf-8 -*-
"""
一次性：重生成「用法小贴士」（culture_tips_zh），修 prompt 举例泄漏。

背景：generate_lessons 的贴士指令里举了 hand vs arm / a pair of jeans 两个例子，
GPT 把它们照抄进了无关课程（厨房课在讲手和手臂的区别）。同「香蕉画进身体部位板」
一类的举例泄漏。prompt 已修（不再给可复用的具体例子 + 加了校验），本脚本把已生成
的课就地补救。

只重写 culture_tips_zh 一个字段 —— 图片、热点坐标、发音音频全部保留（重跑整课
会连图带音频一起作废，代价太大）。

用法:
  python3 refresh_lesson_tips.py --check              # 只列出有问题的课
  python3 refresh_lesson_tips.py --country daily      # 修 + 重传
  python3 refresh_lesson_tips.py --lesson lesson_daily_kitchen
"""

import argparse
import glob
import json
import os
import re

from generate_lessons import _call_gpt
from upload_lessons import get_bucket, rebuild_country_index

LESSONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output", "lessons")

PROMPT = """You are writing 用法小贴士 (usage tips in Chinese) for one page of a picture dictionary aimed at Chinese speakers learning English.

LESSON: {title_zh} ({title_en})
THIS LESSON'S WORDS: {words}

Write 2-3 tips in Chinese. RULES:
- EVERY tip must be about a word from THIS LESSON'S WORDS above, and must name that word.
- Useful angles: where English splits a word Chinese doesn't (or the reverse), the collocation or measure word a Chinese learner gets wrong, a false friend, two words that look interchangeable but aren't, a word Chinese speakers routinely misuse.
- Practical only — never encyclopedia facts, never travel advice.
- Each tip is one sentence, natural spoken Chinese, max 45 字.

Output STRICT JSON only:
{{"culture_tips_zh": ["...", "..."]}}"""


def lesson_words(lesson):
    out = []
    for z in lesson["zones"]:
        out += [w["word"] for w in z["hotspots"] + z["extra_words"]]
    return out


def _norm(w):
    """粗归一：去复数尾。贴士说 apples，词表写 apple，得算同一个词。"""
    for suf in ("ies", "es", "s"):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            return w[:-len(suf)] + ("y" if suf == "ies" else "")
    return w


def tip_is_bad(tip, words):
    """贴士里的英文词没有一个是本课的 → 判为举例泄漏。
    逐词比对（不是整串）：贴士里的 'a cup of tea' 要能匹配上词表里的 'tea bag'。"""
    vocab = set()
    for w in words:
        vocab.update(_norm(t) for t in re.findall(r"[a-zA-Z]{3,}", w.lower()))
    tokens = {_norm(t) for t in re.findall(r"[a-zA-Z]{3,}", tip.lower())}
    if not tokens:
        return False  # 纯中文贴士，放行
    return not (tokens & vocab)


def bad_tips(lesson):
    words = lesson_words(lesson)
    return [t for t in lesson.get("culture_tips_zh", []) if tip_is_bad(t, words)]


def refresh(lesson):
    words = lesson_words(lesson)
    prompt = PROMPT.format(
        title_zh=lesson["title_zh"], title_en=lesson["title_en"], words=", ".join(words))
    for attempt in range(3):
        try:
            got = _call_gpt([{"role": "user", "content": prompt}])
        except Exception as e:
            print("      ❌ GPT: %s" % e)
            continue
        tips = got.get("culture_tips_zh") or []
        if len(tips) < 2:
            continue
        still_bad = [t for t in tips if tip_is_bad(t, words)]
        if still_bad:
            print("      ⚠️  仍有泄漏，重试: %s" % still_bad[0][:36])
            continue
        return tips[:3]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--country", default="daily")
    ap.add_argument("--lesson")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    pattern = os.path.join(LESSONS_DIR, args.country, args.lesson or "lesson_*", "lesson.json")
    files = sorted(glob.glob(pattern))
    targets = []
    for p in files:
        lesson = json.load(open(p, encoding="utf-8"))
        bad = bad_tips(lesson)
        if bad:
            targets.append((p, lesson, bad))

    print("扫描 %d 课，%d 课贴士有问题\n" % (len(files), len(targets)))
    for _, lesson, bad in targets:
        print("  %-14s %s" % (lesson["title_zh"], bad[0][:50]))
    if args.check or not targets:
        return

    bucket = get_bucket()
    fixed = 0
    for p, lesson, _ in targets:
        print("\n📝 %s" % lesson["title_zh"])
        tips = refresh(lesson)
        if not tips:
            print("   ❌ 放弃")
            continue
        lesson["culture_tips_zh"] = tips
        json.dump(lesson, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        for t in tips:
            print("   ✅ %s" % t)
        # OSS 上只补这个字段（图片/音频 URL 已在线上，别整包覆盖）
        key = "lessons/%s/%s/lesson.json" % (lesson["country"], lesson["id"])
        try:
            live = json.loads(bucket.get_object(key).read())
            live["culture_tips_zh"] = tips
            bucket.put_object(key, json.dumps(live, ensure_ascii=False, indent=2).encode("utf-8"))
            fixed += 1
        except Exception as e:
            print("   ⚠️  OSS: %s" % e)

    if fixed:
        rebuild_country_index(bucket, args.country)
    print("\n🎉 修好 %d 课" % fixed)


if __name__ == "__main__":
    main()
