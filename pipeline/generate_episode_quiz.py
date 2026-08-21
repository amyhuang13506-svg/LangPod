"""
每日播客听力测验出题：取 episode script 前 ~90 秒的对白出 3 道"听懂大意"
单选题（六语言解析），存 episodes/{level}/{id}/quiz.json。

听力测试体系（docs/听力测试体系方案_20260821.md）的供给层：
- 只基于前 90 秒出题 → 保证「听 90 秒就能作答」，测验轻量化的根基；
- 复用 generate_raw_quiz 的 prompt / GPT 调用 / 结构校验（同一套质量标准）。

用法：
  python3 generate_episode_quiz.py <level> <episode_id>   # 手动为某集补题
"""
from __future__ import annotations

import json
import sys
from typing import Optional

from config import OSS_CDN_DOMAIN
from generate_raw_quiz import _call_gpt

# 取 script 前多少秒（对应测验里试听的片段长度）
CLIP_SECONDS = 90
# 时间戳缺失时的行数上限兜底
MAX_LINES = 15


def build_source_text(script: list[dict], clip_seconds: int, max_lines: int) -> str:
    parts: list[str] = []
    for i, line in enumerate(script):
        if i >= max_lines:
            break
        start = line.get("start")
        if start is not None and float(start) > clip_seconds:
            break
        text = (line.get("text") or "").strip()
        if text:
            speaker = line.get("speaker") or ""
            parts.append(f"{speaker}: {text}" if speaker else text)
    return "\n".join(parts)


def generate_quiz_for_episode(level: str, ep_id: str, bucket, episode: Optional[dict] = None) -> Optional[str]:
    """
    为一集每日播客生成听力测验并上传 quiz.json。
    - episode: 已在内存里（generate_daily 流程）就传进来；否则从 OSS 拉主 episode.json。
    返回 OSS URL 或 None（失败/内容太少）。
    """
    print(f"\n→ 出题 {level}/{ep_id}")
    if episode is None:
        try:
            raw = bucket.get_object(f"episodes/{level}/{ep_id}/episode.json").read()
            episode = json.loads(raw)
        except Exception as e:
            print(f"  ✗ 拉 episode.json 失败：{e}")
            return None

    # 自适应窗口：慢速集（老 Easy）前 90 秒文本可能不够 → 扩到 150 秒再试。
    # clip_seconds 如实写进 quiz.json，App 按它决定试听片段长度。
    script = episode.get("script") or []
    clip = CLIP_SECONDS
    source = build_source_text(script, clip, MAX_LINES)
    if len(source) < 200:
        clip = 150
        source = build_source_text(script, clip, 25)
    if len(source) < 150:
        print(f"  ⚠️  前 {clip} 秒内容太少（{len(source)} chars），跳过")
        return None

    try:
        questions = _call_gpt(source)
    except Exception as e:
        print(f"  ✗ GPT 出题失败：{e}")
        return None
    if not questions:
        print("  ✗ GPT 返回无有效题目")
        return None

    out = {
        "episode_id": ep_id,
        "clip_seconds": clip,
        "questions": questions,
    }
    key = f"episodes/{level}/{ep_id}/quiz.json"
    bucket.put_object(
        key,
        json.dumps(out, ensure_ascii=False, indent=2).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    url = f"{OSS_CDN_DOMAIN}/{key}"
    print(f"  ☁️  quiz: {url}（{len(questions)} 题）")
    return url


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    from upload_oss import get_bucket
    generate_quiz_for_episode(sys.argv[1], sys.argv[2], get_bucket())
