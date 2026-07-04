# -*- coding: utf-8 -*-
"""
口语表达库 每日新增：cron 每天轮换 31 个分类，用 GPT 新生成 1 条「今日句型」。

对标 generate_daily_lesson.py（词汇课每日 backlog 扩展）：
  1. 按 state 游标选下一个分类（31 个分类顺序轮换）
  2. GPT 为该分类新造 1 条表达（避开该分类已有的所有 english）
  3. 标 is_daily=true、date=今天，追加进分类 JSON
  4. 复用现有脚本补全：音频 → 详情场景图 → 隐喻封面 → 上传 OSS（全链路幂等，只补新的这条）
  5. 从回写的分类 JSON（已是 OSS URL）取该条，写全局 expressions/today.json 指针
  6. 记录 state，下次接着轮

App 顶部「今日句型」置顶卡读 today.json；分类内该条带 NEW 角标 + 当天免费。

用法:
  python3 generate_daily_expression.py            # 产出今天这一条（跑完整链路）
  python3 generate_daily_expression.py --dry-run  # 只打印会选哪个分类
  python3 generate_daily_expression.py --content-only  # 只生成内容 JSON，不跑音/图/传
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime

from config import OUTPUT_DIR
import expression_catalog
from generate_expressions import _call_gpt

EXPR_DIR = os.path.join(OUTPUT_DIR, "expressions")
STATE_PATH = os.path.join(EXPR_DIR, "daily_state.json")
HERE = os.path.dirname(os.path.abspath(__file__))

# 分类轮换顺序 = catalog 平铺顺序（31 个）
CATEGORIES = expression_catalog.all_categories()

DAILY_PROMPT = """You are expanding a spoken-English expression library for Chinese learners. The app's promise: everything is REAL spoken English natives say daily — practical, casual-register accurate, immediately usable. NOT textbook English.

CATEGORY: {cat_zh} — {hint}

Invent exactly ONE NEW expression for this category, ordered-by-usefulness mindset (pick something genuinely common and useful that fits the category).

MUST NOT duplicate or paraphrase any of these already-covered expressions:
{avoid}

The new expression:
- "english": the expression as actually spoken (a phrase, a fill-in pattern, or a short sentence).
  For any open slot, ALWAYS use exactly three underscores `___` — NEVER "..." or "…".
- "meaning_zh": 中文意思（口语化，一句话）
- "usage_zh": 语感注释（1-2 句中文）：谁会说、什么场合、什么语气、和相近说法差在哪。要有画面感。
- "country_note_zh": 国家差异注释（可选，没有明显差异就输出空字符串）。
- "examples": exactly 3, each {{"en": "... (MAX 12 words, real spoken register)", "zh": "自然中文翻译"}}
- "scene": 场景示例：{{"setup_zh": "1-2 句中文描述具体场景（谁、在哪、发生了什么，有画面感，用'你'的视角）",
    "dialogue": [{{"speaker": "A", "en": "...", "zh": "..."}}, {{"speaker": "B", "en": "...", "zh": "..."}}]}}
  dialogue 恰好 2 句（一来一回），其中一句必须自然用到本表达；每句 ≤14 words。

RULES:
- Real current usage only. No 1990s-textbook phrases.
- usage_zh 必须口语化中文，禁止论文腔。
- No political/religious/vulgar content (mild casual slang is fine).

Output STRICT JSON only:
{{"expressions": [{{"english": "...", "meaning_zh": "...", "usage_zh": "...", "country_note_zh": "", "examples": [{{"en": "...", "zh": "..."}}, {{"en": "...", "zh": "..."}}, {{"en": "...", "zh": "..."}}], "scene": {{"setup_zh": "...", "dialogue": [{{"speaker": "A", "en": "...", "zh": "..."}}, {{"speaker": "B", "en": "...", "zh": "..."}}]}}}}]}}"""


def load_state():
    if os.path.exists(STATE_PATH):
        try:
            return json.load(open(STATE_PATH, encoding="utf-8"))
        except Exception:
            pass
    return {"produced": [], "cursor": 0}


def save_state(state):
    os.makedirs(EXPR_DIR, exist_ok=True)
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def norm_en(s):
    return "".join(c for c in s.lower().strip() if c.isalnum())


def validate_one(e):
    """单条表达的最小校验（generate_expressions.validate 是按整分类 8-12 条设计的，不适用）。"""
    problems = []
    for field in ("english", "meaning_zh", "usage_zh"):
        if not e.get(field):
            problems.append("missing %s" % field)
    examples = e.get("examples") or []
    if len(examples) < 2:
        problems.append("need ≥2 examples")
    for ex in examples:
        if len((ex.get("en") or "").split()) > 14:
            problems.append("example too long")
    scene = e.get("scene") or {}
    if len(scene.get("dialogue") or []) < 2:
        problems.append("scene needs 2 dialogue lines")
    return problems


def gpt_new_expression(cat, existing_englishes):
    """为分类生成 1 条不与已有重复的新表达。最多 3 次尝试。"""
    avoid = "\n".join("- %s" % e for e in existing_englishes) or "- (none yet)"
    prompt = DAILY_PROMPT.format(cat_zh=cat["zh"], hint=cat["hint"], avoid=avoid)
    existing_norm = {norm_en(e) for e in existing_englishes}
    for attempt in range(3):
        try:
            data = _call_gpt(prompt)
        except Exception as e:
            print("   ❌ GPT: %s" % e)
            continue
        exprs = (data or {}).get("expressions") or []
        if not exprs:
            continue
        e = exprs[0]
        problems = validate_one(e)
        if problems:
            print("   ⚠️ validation (attempt %d): %s" % (attempt + 1, "; ".join(problems[:3])))
            continue
        if norm_en(e["english"]) in existing_norm:
            print("   ⚠️ duplicate '%s'，重试" % e["english"])
            continue
        return e
    return None


def run_step(argv):
    print("   $ %s" % " ".join(argv))
    r = subprocess.run([sys.executable] + argv, cwd=HERE)
    if r.returncode != 0:
        raise RuntimeError("step failed: %s" % " ".join(argv))


def write_today_pointer(cat, english, today):
    """从回写后的分类 JSON（已是 OSS URL）取该条，写 expressions/today.json 并上传。"""
    from config import (
        OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, OSS_BUCKET_NAME, OSS_ENDPOINT,
    )
    import oss2

    path = os.path.join(EXPR_DIR, "%s.json" % cat["id"])
    data = json.load(open(path, encoding="utf-8"))
    expr = next((e for e in data["expressions"] if e.get("english") == english), None)
    if expr is None:
        print("   ⚠️  today.json: 未在分类里找到 '%s'，跳过" % english)
        return
    today_obj = {
        "date": today,
        "group_id": cat["group_id"],
        "group_zh": cat["group_zh"],
        "category_id": cat["id"],
        "category_zh": cat["zh"],
        "expression": expr,
    }
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    bucket = oss2.Bucket(auth, OSS_ENDPOINT, OSS_BUCKET_NAME)
    bucket.put_object(
        "expressions/today.json",
        json.dumps(today_obj, ensure_ascii=False, indent=2).encode("utf-8"),
    )
    print("   📌 expressions/today.json → %s / %s" % (cat["id"], english))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只打印会选哪个分类")
    parser.add_argument("--content-only", action="store_true", help="只生成内容 JSON，不跑音/图/传")
    args = parser.parse_args()

    state = load_state()
    cursor = state.get("cursor", 0) % len(CATEGORIES)
    cat = CATEGORIES[cursor]
    today = datetime.now().strftime("%Y-%m-%d")
    print("📅 今日句型: 分类 [%s] %s（第 %d/%d 个，已产出 %d 条）" % (
        cat["id"], cat["zh"], cursor + 1, len(CATEGORIES), len(state.get("produced", []))))
    if args.dry_run:
        print("   (dry-run，不生成)")
        return

    path = os.path.join(EXPR_DIR, "%s.json" % cat["id"])
    if not os.path.exists(path):
        print("❌ 分类文件不存在: %s" % path)
        sys.exit(1)
    data = json.load(open(path, encoding="utf-8"))
    existing = [e["english"] for e in data["expressions"]]

    # 1. 生成新表达
    print("📝 生成新表达（避开 %d 条已有）..." % len(existing))
    expr = gpt_new_expression(cat, existing)
    if expr is None:
        print("❌ 新表达生成失败（重试后仍不达标），今日跳过，不推进游标。")
        sys.exit(1)
    expr["is_daily"] = True
    expr["date"] = today
    print("   ✅ 新句型: %s — %s" % (expr["english"], expr.get("meaning_zh", "")))

    # 2. 追加进分类 JSON
    data["expressions"].append(expr)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    if args.content_only:
        print("   (content-only，跳过音/图/传；不写 state)")
        return

    # 3. 补全音频 / 场景图 / 封面（复用现有脚本，均幂等只补新的这条）
    print("🔊 音频...")
    run_step(["generate_expressions.py", "--category", cat["id"]])
    print("🖼  详情场景图...")
    run_step(["generate_expression_scenes.py", cat["id"]])
    print("🎨 卡片封面...")
    run_step(["generate_expression_card_covers.py", cat["id"]])
    print("☁️  上传 + 重建索引...")
    run_step(["upload_expressions.py"])

    # 4. 写全局今日指针
    print("📌 更新今日句型指针...")
    try:
        write_today_pointer(cat, expr["english"], today)
    except Exception as e:
        print("   ⚠️  today.json 写入失败（不影响表达本身）: %s" % e)

    # 5. 记录 state（成功后才记）
    state.setdefault("produced", []).append("%s|%s" % (cat["id"], expr["english"]))
    state["cursor"] = (cursor + 1) % len(CATEGORIES)
    state["last_date"] = today
    save_state(state)
    print("✅ 今日句型完成: %s（累计 %d 条）" % (expr["english"], len(state["produced"])))


if __name__ == "__main__":
    main()
