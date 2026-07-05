# -*- coding: utf-8 -*-
"""
今日句型：把每日播客自动提取的句型（patterns）加工成句型 tab 的卡片格式。

数据流：
  episodes/{level}/index.json（含 patterns）→ 取最近 15 天 →
  每条 pattern 转成 expression（模板→english、翻译→meaning_zh、
  GPT 补 usage_zh 语感 + A/B 场景对话、例句直接映射）→
  写 expressions/daily_{level}.json（daily_easy/medium/hard，各按级别，保留最近 15 天）→
  复用 generate_expressions(音频)/scenes(场景图)/card_covers(封面) 补全媒体 → upload。

幂等：已有卡片（按 pattern id 匹配）保留其媒体 URL，只有新 pattern 才生成媒体。

用法:
  python3 build_pattern_expressions.py                 # 三级全跑（含媒体+上传）
  python3 build_pattern_expressions.py --level easy    # 只跑一个级别
  python3 build_pattern_expressions.py --limit 2       # 每级只保留最近 N 条（出示例/试跑）
  python3 build_pattern_expressions.py --content-only  # 只写 JSON，不跑媒体/上传
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta

from config import OSS_CDN_DOMAIN, OUTPUT_DIR
from generate_expressions import _call_gpt

EXPR_DIR = os.path.join(OUTPUT_DIR, "expressions")
HERE = os.path.dirname(os.path.abspath(__file__))
RETAIN_DAYS = 15

LEVELS = [
    ("easy", "daily_easy", "初级"),
    ("medium", "daily_medium", "中级"),
    ("hard", "daily_hard", "高级"),
]

SCENE_PROMPT = """You are turning podcast "sentence patterns" into cards for a spoken-English app (Chinese learners).

For EACH pattern below, produce:
- "usage_zh": 语感注释（1-2 句中文）：这个句型什么场合用、什么语气、母语者的感觉。口语化，有画面感，禁止论文腔。
- "setup_zh": 1-2 句中文，描述一个具体生活场景（在哪、发生了什么），用"你"的视角，有画面感。
- "dialogue": exactly 2 turns (A then B). ONE turn MUST naturally USE the pattern (fill in the ___ blanks with natural words to form a real sentence). Each line ≤14 words, real spoken register.
  each turn = {{"speaker": "A"|"B", "en": "...", "zh": "自然中文翻译"}}

PATTERNS:
{listing}

Output STRICT JSON only:
{{"items": [{{"template": "<pattern template exactly as given>", "usage_zh": "...", "setup_zh": "...", "dialogue": [{{"speaker": "A", "en": "...", "zh": "..."}}, {{"speaker": "B", "en": "...", "zh": "..."}}]}}]}}"""


def fetch_patterns(level):
    """从 OSS episode index 取该级别最近 RETAIN_DAYS 天的 patterns（新→旧）。"""
    url = "%s/episodes/%s/index.json" % (OSS_CDN_DOMAIN, level)
    data = json.load(urllib.request.urlopen(url, timeout=60))
    cutoff = (datetime.now() - timedelta(days=RETAIN_DAYS)).strftime("%Y-%m-%d")
    out = []
    for e in data.get("episodes") or []:
        date = e.get("date", "")
        if date < cutoff:
            continue
        for p in e.get("patterns") or []:
            p["_date"] = date
            out.append(p)
    # 新→旧；同日按 pattern id 稳定
    out.sort(key=lambda p: (p.get("_date", ""), p.get("id", "")), reverse=True)
    return out


def usage_from_explainer(pattern):
    """兜底 usage_zh：从讲解脚本的 meaning + scene_and_feeling 段拼中文（GPT 失败时用）。"""
    parts = []
    for s in pattern.get("explainer_script") or []:
        if s.get("section") in ("meaning", "scene_and_feeling"):
            t = (s.get("text_zh") or "").strip()
            if t:
                parts.append(t)
    return " ".join(parts)[:140] or pattern.get("scene", "")


SCENE_CHUNK = 10  # 单次 GPT 最多几条 —— 太多会返回超长/截断 JSON 解析失败


def _gpt_scenes_chunk(patterns):
    listing = "\n".join(
        "%d. template: %s | 翻译: %s | 场景: %s | 例句: %s" % (
            i + 1, p["template"], p.get("translation_zh", ""), p.get("scene", ""),
            "; ".join(ex.get("english", "") for ex in (p.get("example_sentences") or [])[:2]),
        )
        for i, p in enumerate(patterns)
    )
    for _ in range(3):
        try:
            data = _call_gpt(SCENE_PROMPT.format(listing=listing))
            items = (data or {}).get("items") or []
            if items:
                return {it["template"].strip(): it for it in items if it.get("template")}
        except Exception as e:
            print("   ⚠️ scene GPT: %s" % e)
    return {}


def gpt_scenes(patterns):
    """为新 pattern 生成 usage_zh + 场景对话，分块调用（防大批量 JSON 解析失败）。"""
    out = {}
    for i in range(0, len(patterns), SCENE_CHUNK):
        chunk = patterns[i:i + SCENE_CHUNK]
        out.update(_gpt_scenes_chunk(chunk))
        print("   💬 %d/%d 条场景已生成" % (min(i + SCENE_CHUNK, len(patterns)), len(patterns)))
    return out


def build_expression(pattern, gpt_item):
    examples = [
        {"en": ex.get("english", ""), "zh": ex.get("chinese", "")}
        for ex in (pattern.get("example_sentences") or [])[:3]
        if ex.get("english")
    ]
    scene = None
    if gpt_item and gpt_item.get("dialogue"):
        scene = {
            "setup_zh": gpt_item.get("setup_zh", ""),
            "dialogue": [
                {"speaker": d.get("speaker", "A"), "en": d.get("en", ""), "zh": d.get("zh", "")}
                for d in gpt_item["dialogue"][:2]
            ],
        }
    return {
        "english": pattern["template"],
        "meaning_zh": pattern.get("translation_zh", ""),
        "usage_zh": (gpt_item or {}).get("usage_zh") or usage_from_explainer(pattern),
        "country_note_zh": "",
        "examples": examples,
        "scene": scene,
        "is_daily": True,
        "date": pattern.get("_date", ""),
        "_pattern_id": pattern.get("id", ""),
    }


def process_level(level, cat_id, cat_zh, limit):
    path = os.path.join(EXPR_DIR, "%s.json" % cat_id)
    existing = {}
    if os.path.exists(path):
        old = json.load(open(path, encoding="utf-8"))
        for e in old.get("expressions", []):
            key = e.get("_pattern_id") or e.get("english")
            existing[key] = e

    patterns = fetch_patterns(level)
    if limit:
        patterns = patterns[:limit]
    print("📥 %s (%s): %d patterns（最近 %d 天）" % (cat_id, cat_zh, len(patterns), RETAIN_DAYS))

    # 需要新生成场景/语感的 pattern（已有卡片直接复用，保媒体）
    new_patterns = [p for p in patterns if (p.get("id") or p["template"]) not in existing]
    gpt_map = {}
    if new_patterns:
        print("   💬 GPT 生成 %d 条语感+场景..." % len(new_patterns))
        gpt_map = gpt_scenes(new_patterns)

    expressions = []
    seen_en = set()
    for p in patterns:
        key = p.get("id") or p["template"]
        if key in existing:
            expr = existing[key]
        else:
            expr = build_expression(p, gpt_map.get(p["template"].strip()))
        # 同一天同模板可能重复，去重（保第一条=最新）
        if expr["english"] in seen_en:
            continue
        seen_en.add(expr["english"])
        expressions.append(expr)

    data = {
        "id": cat_id,
        "zh": cat_zh,
        "group_id": "daily",
        "group_zh": "今天",
        "is_free": cat_id == "daily_easy",
        "expressions": expressions,
    }
    os.makedirs(EXPR_DIR, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("   ✅ 写入 %d 条 → %s" % (len(expressions), path))
    return len(new_patterns)


def run_step(argv):
    print("   $ %s" % " ".join(argv))
    r = subprocess.run([sys.executable] + argv, cwd=HERE)
    if r.returncode != 0:
        raise RuntimeError("step failed: %s" % " ".join(argv))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--level", choices=["easy", "medium", "hard"])
    parser.add_argument("--limit", type=int, default=0, help="每级只保留最近 N 条（试跑）")
    parser.add_argument("--content-only", action="store_true", help="只写 JSON，不跑媒体/上传")
    args = parser.parse_args()

    levels = [x for x in LEVELS if not args.level or x[0] == args.level]
    total_new = 0
    cat_ids = []
    for level, cat_id, cat_zh in levels:
        total_new += process_level(level, cat_id, cat_zh, args.limit)
        cat_ids.append(cat_id)

    if args.content_only:
        print("（content-only，跳过媒体/上传）")
        return

    # 媒体补全（幂等，只补新卡）+ 上传
    for cat_id in cat_ids:
        print("🔊 音频 %s..." % cat_id)
        run_step(["generate_expressions.py", "--category", cat_id])
        print("🖼  场景图 %s..." % cat_id)
        run_step(["generate_expression_scenes.py", cat_id])
        print("🎨 封面 %s..." % cat_id)
        run_step(["generate_expression_card_covers.py", cat_id])
    print("☁️  上传 + 重建索引...")
    run_step(["upload_expressions.py"])
    print("✅ 今日句型完成（新增 %d 条）" % total_new)


if __name__ == "__main__":
    main()
