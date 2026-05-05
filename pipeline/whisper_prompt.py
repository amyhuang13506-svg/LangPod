"""
为 Whisper API 拼接领域 prompt。

Whisper 支持 ≤244 token 的 `prompt` 参数，模型会偏向用其中词的拼写
（不是逐字转录 prompt 内容，而是作为"之前说过的话"提示风格 + 拼写）。

策略：基础 tech 词典（任何 raw_podcast 都用） + 当条 podcast 的
speaker / title / topic（动态注入人名 / 公司 / 话题）。
"""
import re
from typing import Optional

# 基础 tech 词典 —— 覆盖大部分 raw_podcast 会出现的专有名词
# 排序：人名、AI 公司、AI 模型、技术术语、硬件公司、平台
STATIC_TECH_VOCAB = (
    "Sam Altman, Greg Brockman, Sundar Pichai, Jensen Huang, Elon Musk, "
    "Demis Hassabis, Dario Amodei, Mira Murati, Mark Zuckerberg, Tim Cook, "
    "OpenAI, Anthropic, DeepMind, xAI, Mistral, Cohere, "
    "ChatGPT, GPT-4, GPT-4o, Claude, Gemini, Llama, Sora, "
    "NVIDIA, CUDA, TensorRT, GPU, TPU, H100, B100, "
    "AGI, LLM, RLHF, transformer, embedding, attention, fine-tuning, "
    "Tesla, SpaceX, Microsoft, Apple, Google, Meta, Amazon, "
    "AWS, Azure, GCP"
)

# Whisper prompt 上限 ≈ 244 token，按 4 chars/token 粗估 ≈ 1000 chars
MAX_PROMPT_CHARS = 900


def _extract_caps_and_known(title: str) -> str:
    """从标题里抽出大写开头的 token 和疑似专有名词。
    用启发式：连续 2+ 大写字母的 token、首字母大写且非句首位置的词。
    """
    if not title:
        return ""
    cleaned = re.sub(r"[|\-—–•:]+", " ", title)
    tokens = cleaned.split()
    out = []
    seen = set()
    stopwords = {
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "as", "is", "was", "are",
        "this", "that", "how", "why", "when", "what", "where", "who",
        "i", "we", "you", "they", "it", "be", "been",
    }
    for i, tok in enumerate(tokens):
        clean = tok.strip(".,!?;:\"'()[]")
        if not clean or clean.lower() in seen:
            continue
        is_acronym = len(clean) >= 2 and sum(1 for c in clean if c.isupper()) >= 2
        is_proper = i > 0 and clean[0].isupper() and clean.lower() not in stopwords
        if is_acronym or is_proper:
            out.append(clean)
            seen.add(clean.lower())
    return ", ".join(out)


def build_prompt(meta: Optional[dict]) -> str:
    """构建 Whisper prompt。
    meta 可含 title / speaker / topic / event 字段，缺则用空串。
    返回 ≤MAX_PROMPT_CHARS 字符的字符串。
    """
    meta = meta or {}
    speaker = (meta.get("speaker") or "").strip()
    title = (meta.get("title") or "").strip()
    topic = (meta.get("topic") or "").strip()

    title_terms = _extract_caps_and_known(title)

    parts = ["Tech podcast or keynote transcript."]
    if speaker:
        parts.append(f"Speaker: {speaker}.")
    if title:
        parts.append(f"Title: {title}.")
    if topic:
        parts.append(f"Topic: {topic}.")
    parts.append(f"Common terms: {STATIC_TECH_VOCAB}.")
    if title_terms:
        parts.append(f"Mentioned: {title_terms}.")

    prompt = " ".join(parts)
    if len(prompt) > MAX_PROMPT_CHARS:
        prompt = prompt[:MAX_PROMPT_CHARS - 3] + "..."
    return prompt


if __name__ == "__main__":
    samples = [
        {
            "title": "The OpenAI Founders On Their Plan To Battle Elon, Compute And Everything Else",
            "speaker": "Core Memory",
            "topic": "AI · 访谈",
        },
        {
            "title": "Jensen Huang: NVIDIA - The $4 Trillion Company",
            "speaker": "Acquired",
            "topic": "AI · 芯片",
        },
        {
            "title": "How to Make Claude Code Your AI Engineering Team",
            "speaker": "Y Combinator",
            "topic": "AI · 创业",
        },
        {},
    ]
    for s in samples:
        p = build_prompt(s)
        print(f"\n[{len(p)} chars] meta={s}")
        print(f"  → {p}")
