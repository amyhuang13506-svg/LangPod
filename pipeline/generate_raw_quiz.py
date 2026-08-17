"""
原声理解题生成：从 transcript 前 ~10 分钟内容出 3 道"听懂大意"单选题，
存 quiz.json 上 OSS。App 端退出结算卡上的「测测听懂了多少」消费。

输入：transcript {podcast_id, segments: [{start, end, en, zh}]}
输出：raw_podcasts/<id>/quiz.json，schema：
{
  "podcast_id": "raw-yt-...",
  "questions": [
    {
      "q": "What is the speaker's main point about ...?",   # 英文题干
      "options": ["...", "...", "..."],                      # 3 个选项
      "answer": 0,                                           # 正确项下标
      "explain": {"zh": "..."}                               # 按语言的一句话解析
    }
  ]
}

原则（见 docs/原声结算时刻方案_20260817.md）：
- 考大意 / 关键信息，不考语法、不考细枝末节的数字年份
- 生成失败非致命：主流程 try/except 包住，不影响播客本身入库
- 只对新内容生效，不回溯老内容

用法：
  python3 generate_raw_quiz.py <podcast_id>       # 手动为某集补题（测试用）
"""
from __future__ import annotations

import json
import re
import sys
from typing import Optional

import requests

from config import (
    GPT_API_ENDPOINT, GPT_API_KEY,
    OSS_CDN_DOMAIN,
)

# 取 transcript 前多少秒的内容出题（用户最可能听到的部分）
QUIZ_SOURCE_SECONDS = 600
# 喂给 GPT 的原文上限（字符）
MAX_SOURCE_CHARS = 7000

PROMPT = """You are creating a listening comprehension check for an English learner \
who just listened to part of a real talk/podcast.

Based ONLY on the transcript below, write EXACTLY 3 multiple-choice questions.

Rules:
- Test MAIN IDEAS and key points the speaker made — never grammar, never trivial \
details like exact numbers or years.
- Questions and options in simple English (an intermediate learner must be able to \
read them quickly).
- Each question has exactly 3 options, only one correct.
- Wrong options must be plausible but clearly wrong to someone who understood the talk.
- For each question add a one-sentence explanation of why the answer is correct, \
translated into ALL of these languages: Simplified Chinese (key "zh"), Traditional \
Chinese (key "zh-Hant"), Japanese (key "ja"), Korean (key "ko"), Latin American \
Spanish (key "es"), Brazilian Portuguese (key "pt-BR").

Return ONLY valid JSON, no markdown fences:
{"questions": [{"q": "...", "options": ["...", "...", "..."], "answer": 0, \
"explain": {"zh": "...", "zh-Hant": "...", "ja": "...", "ko": "...", "es": "...", "pt-BR": "..."}}]}

Transcript:
"""


def _build_source_text(segments: list[dict]) -> str:
    parts: list[str] = []
    total = 0
    for seg in segments:
        if float(seg.get("start", 0)) > QUIZ_SOURCE_SECONDS:
            break
        en = (seg.get("en") or "").strip()
        if not en:
            continue
        parts.append(en)
        total += len(en)
        if total >= MAX_SOURCE_CHARS:
            break
    return " ".join(parts)


def _call_gpt(source_text: str) -> Optional[list[dict]]:
    body = {
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": PROMPT + source_text}],
        "temperature": 0.4,
    }
    headers = {"Authorization": f"Bearer {GPT_API_KEY}"}
    r = requests.post(GPT_API_ENDPOINT, json=body, headers=headers, timeout=120)
    r.raise_for_status()
    content = r.json()["choices"][0]["message"]["content"].strip()
    # 容错：偶发 markdown fence 包裹
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content)
    data = json.loads(content)
    questions = data.get("questions")
    if not isinstance(questions, list):
        return None
    # 结构校验：3 选项 + answer 合法 + 中文解析存在。坏题直接丢，宁缺毋滥。
    valid = []
    for q in questions:
        opts = q.get("options")
        ans = q.get("answer")
        if (isinstance(q.get("q"), str) and isinstance(opts, list) and len(opts) == 3
                and isinstance(ans, int) and 0 <= ans < 3
                and isinstance(q.get("explain"), dict) and q["explain"].get("zh")):
            valid.append({"q": q["q"], "options": opts, "answer": ans, "explain": q["explain"]})
    return valid or None


def generate_quiz_for_podcast(podcast_id: str, bucket, transcript: Optional[dict] = None) -> Optional[str]:
    """
    为一集原声生成理解题并上传 quiz.json。
    - transcript: 已在内存里就传进来；否则从 OSS 拉。
    返回 OSS URL 或 None（失败/无可用内容）。
    """
    print(f"\n→ 出题 {podcast_id}")
    if transcript is None:
        try:
            transcript_bytes = bucket.get_object(f"raw_podcasts/{podcast_id}/transcript.json").read()
            transcript = json.loads(transcript_bytes)
        except Exception as e:
            print(f"  ✗ 拉 transcript 失败：{e}")
            return None

    segments = transcript.get("segments") or []
    source = _build_source_text(segments)
    if len(source) < 500:
        print(f"  ⚠️  可出题内容太少（{len(source)} chars），跳过")
        return None

    try:
        questions = _call_gpt(source)
    except Exception as e:
        print(f"  ✗ GPT 出题失败：{e}")
        return None
    if not questions:
        print("  ✗ GPT 返回无有效题目")
        return None

    out = {"podcast_id": podcast_id, "questions": questions}
    key = f"raw_podcasts/{podcast_id}/quiz.json"
    bucket.put_object(
        key,
        json.dumps(out, ensure_ascii=False, indent=2).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    url = f"{OSS_CDN_DOMAIN}/{key}"
    print(f"  ☁️  quiz: {url}（{len(questions)} 题）")
    return url


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    from raw_podcast_processor import get_bucket
    generate_quiz_for_podcast(sys.argv[1], get_bucket())
