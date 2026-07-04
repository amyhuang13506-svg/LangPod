# -*- coding: utf-8 -*-
"""
词汇小课堂 Step 5: 每日自动新增一课（6 国轮流 us→uk→au→ca→nz→sg）。

每次运行：
  1. 按轮换顺序选下一个国家 + 该国下一个「未产出」的 backlog 场景
  2. GPT 把场景（title + hint）展开成 3 个分区（每区不同实物，避免重复词）
  3. 复用 generate_lessons.generate_lesson_content 生成词表/例句/句型/贴士
  4. 标 is_daily=true、date=今天，写 lesson.json
  5. 生图 → 音频 → 上传（子进程复用现有脚本，全链路幂等）
  6. 记录到 daily_state.json，下次接着轮

用法:
  python3 generate_daily_lesson.py             # 产出今天这一课（跑完整链路）
  python3 generate_daily_lesson.py --dry-run   # 只打印会选哪一课，不生成
  python3 generate_daily_lesson.py --content-only  # 只生成内容 JSON，不跑图/音/传（调试）
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime

from config import OUTPUT_DIR
from lesson_catalog import DAILY_SCENE_BACKLOG, CATEGORIES
from generate_lessons import _call_gpt, generate_lesson_content

LESSONS_DIR = os.path.join(OUTPUT_DIR, "lessons")
STATE_PATH = os.path.join(LESSONS_DIR, "daily_state.json")
HERE = os.path.dirname(os.path.abspath(__file__))

# 轮换顺序：每天下一个国家
ROTATION = ["us", "uk", "au", "ca", "nz", "sg"]

# backlog 条目无 SF Symbol 图标，按分类兜底
ICON_BY_CAT = {
    "arrival": "airplane.arrival",
    "food": "fork.knife",
    "health": "cross.case.fill",
    "settling": "house.fill",
    "social": "person.2.fill",
}

ZONE_DESIGN_PROMPT = """You are designing the zone structure for a scene-based English vocabulary mini-lesson in an app for Chinese learners.

SCENE: {title_en} ({title_zh})
Country: {country}
Things that appear in this scene: {hint}

Split this ONE real-life moment into EXACTLY 3 sequential sub-scenes ("zones") a learner moves through. Each zone becomes one illustration, so each zone MUST contain DIFFERENT concrete drawable objects (no overlap between zones).

Output STRICT JSON only (no markdown, no commentary):
{{"zones": [
  {{"id": "snake_case_id", "en": "Short English Zone Name", "zh": "简短中文名", "hint": "6-9 concrete drawable objects plus a couple of spoken expressions for THIS zone only, comma separated"}},
  {{...}},
  {{...}}
]}}"""


def load_state():
    if os.path.exists(STATE_PATH):
        try:
            return json.load(open(STATE_PATH, encoding="utf-8"))
        except Exception:
            pass
    return {"produced": []}


def save_state(state):
    os.makedirs(LESSONS_DIR, exist_ok=True)
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def pick_next(state):
    """按已产出数量决定下一个国家，取该国第一个未产出的 backlog 场景。"""
    produced = set(state.get("produced", []))
    n = len(produced)
    for i in range(len(ROTATION)):
        cc = ROTATION[(n + i) % len(ROTATION)]
        for entry in DAILY_SCENE_BACKLOG:
            if entry["country"] != cc:
                continue
            lid = "lesson_%s_%s" % (cc, entry["slug"])
            if lid not in produced:
                return entry, lid
    return None, None


def design_zones(entry):
    prompt = ZONE_DESIGN_PROMPT.format(
        title_en=entry["title"]["en"],
        title_zh=entry["title"]["zh"],
        country=entry["country"],
        hint=entry["hint"],
    )
    data = _call_gpt([{"role": "user", "content": prompt}])
    zones = data.get("zones", [])[:3]
    if len(zones) != 3 or not all(z.get("id") and z.get("en") and z.get("zh") and z.get("hint") for z in zones):
        raise ValueError("zone design invalid: %s" % zones)
    # id 去重（GPT 偶尔重复）
    seen, clean = set(), []
    for idx, z in enumerate(zones):
        zid = z["id"]
        if zid in seen:
            zid = "%s_%d" % (zid, idx)
        seen.add(zid)
        clean.append({"id": zid, "en": z["en"], "zh": z["zh"], "hint": z["hint"]})
    return clean


def build_lesson_def(entry, lid, zones):
    cat = entry["category"]
    return {
        "id": lid,
        "slug": entry["slug"],
        "country": entry["country"],
        "category": cat,
        "category_zh": CATEGORIES[cat]["zh"],
        "icon": ICON_BY_CAT.get(cat, "book.fill"),
        "title_zh": entry["title"]["zh"],
        "title_en": entry["title"]["en"],
        "anchor": entry["hint"],
        "zones": zones,
        "is_free": False,
    }


def run_step(argv):
    print("   $ %s" % " ".join(argv))
    r = subprocess.run([sys.executable] + argv, cwd=HERE)
    if r.returncode != 0:
        raise RuntimeError("step failed: %s" % " ".join(argv))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只打印会选哪一课")
    parser.add_argument("--content-only", action="store_true", help="只生成内容 JSON，不跑图/音/传")
    args = parser.parse_args()

    state = load_state()
    entry, lid = pick_next(state)
    if entry is None:
        print("🎉 backlog 已全部产出（%d 课），无新课可加。请补充 DAILY_SCENE_BACKLOG。" % len(state["produced"]))
        return

    cc = entry["country"]
    today = datetime.now().strftime("%Y-%m-%d")
    print("📅 今日每日课: %s — %s（%s）" % (lid, entry["title"]["zh"], cc))
    print("   已产出 %d 课，轮到 %s" % (len(state["produced"]), cc))
    if args.dry_run:
        print("   (dry-run，不生成)")
        return

    out_dir = os.path.join(LESSONS_DIR, cc, lid)
    out_path = os.path.join(out_dir, "lesson.json")

    # 1. 设计分区
    print("🧩 设计分区...")
    zones = design_zones(entry)
    for z in zones:
        print("   ▸ %s (%s)" % (z["id"], z["zh"]))

    # 2. 生成内容
    print("📝 生成词表/例句/句型/贴士...")
    lesson_def = build_lesson_def(entry, lid, zones)
    result = generate_lesson_content(lesson_def)
    if result is None:
        print("❌ 内容生成失败（重试后仍不达标），今日跳过，不消耗轮换。")
        sys.exit(1)

    # 3. 标每日 + 日期
    result["is_daily"] = True
    result["date"] = today
    os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print("   ✅ %d 词 → %s" % (result["word_count"], out_path))

    if args.content_only:
        print("   (content-only，跳过图/音/传；不写 state)")
        return

    # 4. 生图 → 音频 → 上传
    print("🎨 生图...")
    run_step(["generate_lesson_images.py", "--lesson", lid])
    print("🔊 音频...")
    run_step(["generate_lesson_audio.py", "--lesson", lid])
    print("☁️  上传 + 重建索引...")
    run_step(["upload_lessons.py", "--country", cc])

    # 5. 记录 state（成功后才记，失败可重跑同一课）
    state.setdefault("produced", []).append(lid)
    state["last_date"] = today
    save_state(state)
    print("✅ 今日每日课完成: %s（累计 %d 课）" % (lid, len(state["produced"])))


if __name__ == "__main__":
    main()
