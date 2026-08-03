#!/usr/bin/env python3
"""
Pipeline health watchdog — cron at 08:00 CST, right after the 07:30 push flush.

Why it exists: the content/push chain can die silently. Last real outage:
IPRoyal proxy traffic ran dry on 7-26 → nine days of zero new YouTube items
AND zero morning pushes (the flush drains a queue only the raw pipeline
fills), discovered by hand on 8-03. This watchdog turns that failure mode
into a same-day alert.

Check: for each push type (raw_podcast / episode), look at the last N runs
in logs/push_flush.log — if the most recent ALERT_AFTER_EMPTY_RUNS runs all
flushed nothing, the upstream pipeline is stuck.

Alert channels:
  - append to logs/ALERT.log
  - APNs to every SANDBOX token in tokens.json (= dev devices only, i.e.
    the owner's phone — end users never see this)
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PIPELINE_DIR = "/opt/langpod/pipeline"
FLUSH_LOG = os.path.join(PIPELINE_DIR, "logs", "push_flush.log")
ALERT_LOG = os.path.join(PIPELINE_DIR, "logs", "ALERT.log")
TOKENS_FILE = "/opt/langpod/secrets/tokens.json"

ALERT_AFTER_EMPTY_RUNS = 2  # 连续 2 次 flush 空队列即告警

RUN_RE = re.compile(
    r"\[flush\] (\d{4}-\d{2}-\d{2})T[\d:]+ — queue size (\d+), type=(\w+)"
)


def recent_runs() -> list[dict]:
    """Parse flush log into [{date, size, type}], oldest → newest."""
    if not os.path.exists(FLUSH_LOG):
        return []
    with open(FLUSH_LOG, "r", errors="replace") as f:
        lines = f.readlines()[-400:]
    runs = []
    for line in lines:
        m = RUN_RE.search(line)
        if m:
            runs.append({"date": m.group(1), "size": int(m.group(2)), "type": m.group(3)})
    return runs


def check() -> list[str]:
    runs = recent_runs()
    problems = []
    for ptype, label in (("raw_podcast", "早间 YouTube 推送"), ("episode", "下午集数推送")):
        typed = [r for r in runs if r["type"] == ptype]
        if len(typed) < ALERT_AFTER_EMPTY_RUNS:
            continue  # 该类型还没跑满 N 次，不判
        tail = typed[-ALERT_AFTER_EMPTY_RUNS:]
        if all(r["size"] == 0 for r in tail):
            dates = ", ".join(r["date"] for r in tail)
            problems.append(
                f"{label}连续 {ALERT_AFTER_EMPTY_RUNS} 次空队列（{dates}）— "
                "上游管线可能已停摆（常见根因：IPRoyal 代理流量耗尽，402）"
            )
    return problems


def alert(problems: list[str]) -> None:
    stamp = datetime.now().isoformat(timespec="seconds")
    os.makedirs(os.path.dirname(ALERT_LOG), exist_ok=True)
    with open(ALERT_LOG, "a") as f:
        for p in problems:
            f.write(f"{stamp} {p}\n")

    # 推到开发者自己的设备（只发 sandbox token，绝不打扰真实用户）
    try:
        from apns_push import send_push
        with open(TOKENS_FILE, "r") as f:
            tokens = json.load(f)
        dev_tokens = [t["token"] for t in tokens if t.get("is_sandbox")]
        body = "；".join(problems)[:200]
        for tok in dev_tokens:
            status, resp = send_push(
                device_token=tok,
                title="⚠️ Castlingo 管线告警",
                body=body,
                sandbox=True,
            )
            print(f"[watchdog] alert push → {tok[:8]}… status={status}")
    except Exception as e:
        print(f"[watchdog] alert push failed: {e}")


def main() -> None:
    problems = check()
    if problems:
        print(f"[watchdog] {len(problems)} problem(s):")
        for p in problems:
            print(f"  ! {p}")
        alert(problems)
    else:
        print("[watchdog] push pipeline healthy")


if __name__ == "__main__":
    main()
