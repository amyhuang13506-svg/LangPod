# -*- coding: utf-8 -*-
"""
口语表达库 音频↔文本 全量核对（Groq Whisper 转写后与屏幕文字比对）。
覆盖：表达本体 / 例句 / 场景对话 三类音频。
断点续跑：结果存 checkpoint，跑过的跳过；网络失败直接重跑同一命令即可。

用法:
  python3 verify_expression_audio.py            # 全量
  python3 verify_expression_audio.py greetings  # 单分类
"""

import glob
import json
import os
import re
import sys
import time

import requests

from config import GROQ_API_KEY, GROQ_WHISPER_ENDPOINT, GROQ_WHISPER_MODEL, OUTPUT_DIR

BASE = os.path.join(OUTPUT_DIR, "expressions")
CKPT = os.path.join(BASE, "verify_ckpt.json")

results = {}
if os.path.exists(CKPT):
    results = json.load(open(CKPT))


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).split()


def similar(a, b):
    wa, wb = set(norm(a)), set(norm(b))
    if not wa or not wb:
        return 0
    return len(wa & wb) / max(len(wa), len(wb))


def transcribe(local, fname):
    for attempt in range(4):
        try:
            with open(local, "rb") as f:
                r = requests.post(
                    GROQ_WHISPER_ENDPOINT,
                    headers={"Authorization": "Bearer %s" % GROQ_API_KEY},
                    files={"file": (fname, f, "audio/mpeg")},
                    data={"model": GROQ_WHISPER_MODEL, "language": "en"},
                    timeout=90,
                )
            if r.status_code == 200:
                return r.json().get("text", "")
            if r.status_code == 429:
                time.sleep(20)
                continue
            return None
        except requests.exceptions.RequestException:
            time.sleep(10 * (attempt + 1))
    return None


def check(cat_id, key, text, audio_url):
    global checked, skipped
    if key in results:
        skipped += 1
        return
    fname = (audio_url or "").split("/")[-1]
    local = os.path.join(BASE, "audio", cat_id, fname)
    if not fname or not os.path.exists(local):
        results[key] = {"status": "missing", "text": text}
        return
    heard = transcribe(local, fname)
    if heard is None:
        return  # 本轮失败，下轮续跑
    score = similar(text, heard)
    results[key] = {
        "status": "ok" if score >= 0.5 else "MISMATCH",
        "text": text, "heard": heard.strip(), "score": round(score, 2),
    }
    checked += 1
    if checked % 40 == 0:
        json.dump(results, open(CKPT, "w"))
        print("progress: %d new, %d cached" % (checked, skipped), flush=True)


checked = skipped = 0
only = sys.argv[1] if len(sys.argv) > 1 else None
for p in sorted(glob.glob(os.path.join(BASE, "*.json"))):
    d = json.load(open(p))
    if only and d["id"] != only:
        continue
    for e in d["expressions"]:
        check(d["id"], "%s|%s|expr" % (d["id"], e["english"]), e["english"], e.get("audio"))
        for i, ex in enumerate(e.get("examples") or []):
            check(d["id"], "%s|%s|ex%d" % (d["id"], e["english"], i), ex["en"], ex.get("audio"))
        for i, line in enumerate((e.get("scene") or {}).get("dialogue", [])):
            check(d["id"], "%s|%s|sc%d" % (d["id"], e["english"], i), line["en"], line.get("audio"))

json.dump(results, open(CKPT, "w"))
bad = {k: v for k, v in results.items() if v["status"] != "ok"}
print("\n=== total %d verified, %d problems ===" % (len(results), len(bad)))
for k, v in bad.items():
    print(" ❌", k, "|", v.get("status"), "| text:", v["text"], "| heard:", v.get("heard", ""))
