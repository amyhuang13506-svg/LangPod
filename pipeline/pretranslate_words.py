"""
预翻译整篇 transcript 里的所有英文单词，存成 words.json 上 OSS。
App 端拉到这个文件后，用户点词查询直接走本地查表，零 GPT 延迟。

输入：transcript {podcast_id, segments: [{start, end, en, zh}]}
输出：raw_podcasts/<id>/words.json，schema：
{
  "podcast_id": "raw-yt-...",
  "words": {
    "intersection": {
      "phonetic": "/ˌɪntərˈsekʃən/",
      "pos": "n.",
      "zh": "交叉点；交集",
      "example": "..."
    },
    ...
  }
}

成本估算：每集 ~3000 unique words，按 30 词/批 = 100 次 gpt-4o-mini 调用，
~$0.10 / 集。比让每个用户在 App 里各自查 GPT 便宜两个数量级。
"""
from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Optional

import requests

from config import (
    GPT_API_ENDPOINT, GPT_API_KEY,
    OSS_CDN_DOMAIN,
)


# 跳过的高频功能词（用户极少点这种词查含义；译了也是浪费钱）
STOPWORDS = {
    "the", "and", "for", "you", "are", "but", "not", "all", "any", "can",
    "had", "her", "was", "one", "our", "out", "day", "get", "has", "him",
    "his", "how", "man", "new", "now", "old", "see", "two", "way", "who",
    "boy", "did", "its", "let", "put", "say", "she", "too", "use", "with",
    "this", "that", "have", "from", "they", "will", "would", "could",
    "should", "there", "their", "these", "those", "what", "when", "which",
    "while", "where", "your", "been", "more", "much", "very", "also",
    "only", "just", "than", "then", "into", "over", "some", "many", "such",
    "well", "even", "back", "still", "down", "after", "before", "again",
    "going", "doing", "being", "saying", "thinking", "really", "actually",
    "kind", "sort", "thing", "things", "stuff", "yeah", "okay", "right",
    "sure", "well", "lot", "lots", "good", "bad", "say", "said", "gone",
    "come", "came", "make", "made", "take", "took", "give", "gave", "want",
    "wanted", "need", "needs", "needed", "know", "knew", "known", "think",
    "thought", "look", "looked", "looking", "find", "found", "feel", "felt",
}

WORD_PATTERN = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")
BATCH_SIZE = 30
GPT_MODEL = "gpt-4o-mini"
MAX_RETRIES = 2


def extract_unique_words(segments: list[dict]) -> dict[str, dict]:
    """
    扫一遍所有 segments，提取去重后的小写单词 + 首次出现的上下文（用于消歧义）。
    返回：{word_lower: {"context": "...", "count": N}}
    """
    words: dict[str, dict] = {}
    for seg in segments:
        en = (seg.get("en") or "").strip()
        if not en:
            continue
        for raw in WORD_PATTERN.findall(en):
            w = raw.lower()
            if len(w) < 3 or w in STOPWORDS:
                continue
            if w not in words:
                words[w] = {"context": en, "count": 0}
            words[w]["count"] += 1
    return words


def build_batch_prompt(batch: list[tuple[str, dict]]) -> str:
    """构造一次 GPT 调用的 prompt：列出 N 个词 + 各自上下文，要求返回 JSON。"""
    lines = []
    for i, (word, meta) in enumerate(batch, 1):
        ctx = meta["context"]
        # 上下文太长会浪费 token，截到 ~120 字符
        if len(ctx) > 120:
            ctx = ctx[:120] + "…"
        lines.append(f'{i}. "{word}" — context: "{ctx}"')
    word_list = "\n".join(lines)
    word_keys = ", ".join(f'"{w}"' for w, _ in batch)

    return f"""You are a bilingual EN→ZH dictionary. Translate each English word below to Chinese, picking the meaning that fits the given context.

Words to translate:
{word_list}

Output STRICT JSON only (no markdown, no extra text), keyed by lowercase word:
{{
  "<word>": {{
    "phonetic": "/IPA/",
    "pos": "n." | "v." | "adj." | "adv." | "phr." | "prep." | "...",
    "zh": "1-2 个中文常用释义，逗号分隔",
    "example": "另一个简单英文例句（可选）"
  }},
  ...
}}

The output MUST contain exactly these keys: {word_keys}

For proper nouns (people / companies / places), set zh to "（专有名词）<音译或品牌名>" and pos to "n.".
"""


def call_gpt_batch(batch: list[tuple[str, dict]]) -> dict:
    """调一次 GPT 翻译一批词。失败重试 MAX_RETRIES 次。返回 {word: {phonetic, pos, zh, example}}。"""
    prompt = build_batch_prompt(batch)
    body = {
        "model": GPT_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }
    headers = {
        "Authorization": f"Bearer {GPT_API_KEY}",
        "Content-Type": "application/json",
    }
    last_err: Optional[Exception] = None
    for attempt in range(MAX_RETRIES + 1):
        try:
            r = requests.post(GPT_API_ENDPOINT, json=body, headers=headers, timeout=60)
            if r.status_code != 200:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
            content = r.json()["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            # 校验返回的 keys 是否匹配请求的词；不匹配的丢弃
            cleaned: dict[str, dict] = {}
            for word, _ in batch:
                if word in parsed and isinstance(parsed[word], dict):
                    entry = parsed[word]
                    cleaned[word] = {
                        "phonetic": entry.get("phonetic"),
                        "pos": entry.get("pos") or entry.get("part_of_speech"),
                        "zh": entry.get("zh") or entry.get("translation") or "",
                        "example": entry.get("example"),
                    }
            return cleaned
        except Exception as e:
            last_err = e
            if attempt < MAX_RETRIES:
                time.sleep(1.5 * (attempt + 1))
                continue
    print(f"    ✗ batch 全部失败：{last_err}")
    return {}


def batch_translate(words: dict[str, dict]) -> dict[str, dict]:
    """把所有 unique words 分批调 GPT 翻译。返回扁平词典。"""
    result: dict[str, dict] = {}
    items = list(words.items())
    total = len(items)
    if total == 0:
        return result
    n_batches = (total + BATCH_SIZE - 1) // BATCH_SIZE
    print(f"  → {total} unique words → {n_batches} batches × {BATCH_SIZE} words")
    for bi in range(n_batches):
        batch = items[bi * BATCH_SIZE : (bi + 1) * BATCH_SIZE]
        translated = call_gpt_batch(batch)
        result.update(translated)
        print(f"    [{bi + 1}/{n_batches}] +{len(translated)}  total={len(result)}")
    return result


def pretranslate_for_podcast(podcast_id: str, bucket, transcript: Optional[dict] = None) -> Optional[str]:
    """
    预翻译一集的所有词并上传 words.json。
    - transcript: 已经在内存里就传进来；否则从 OSS 拉。
    返回 OSS URL 或 None。
    """
    print(f"\n→ 预译 {podcast_id}")
    if transcript is None:
        try:
            transcript_bytes = bucket.get_object(f"raw_podcasts/{podcast_id}/transcript.json").read()
            transcript = json.loads(transcript_bytes)
        except Exception as e:
            print(f"  ✗ 拉 transcript 失败：{e}")
            return None

    segments = transcript.get("segments") or []
    if not segments:
        print("  ✗ transcript 无 segments")
        return None

    unique = extract_unique_words(segments)
    if not unique:
        print("  ⚠️  没有可翻译的词（可能整篇都是 stopwords）")
        return None

    translated = batch_translate(unique)

    out = {
        "podcast_id": podcast_id,
        "words": translated,
    }
    out_bytes = json.dumps(out, ensure_ascii=False, indent=2).encode("utf-8")
    key = f"raw_podcasts/{podcast_id}/words.json"
    bucket.put_object(key, out_bytes, headers={"Content-Type": "application/json"})
    url = f"{OSS_CDN_DOMAIN}/{key}"
    print(f"  ☁️  words.json: {url}  ({len(translated)} words, {len(out_bytes) // 1024}KB)")
    return url


# CLI: 单跑某条 / 批量补译
def main():
    import sys
    from raw_podcast_processor import get_bucket, load_master

    if len(sys.argv) < 2:
        print("用法：python3 pretranslate_words.py <podcast_id|all>")
        sys.exit(1)

    bucket = get_bucket()
    target = sys.argv[1]

    if target == "all":
        master = load_master(bucket)
        ids = [m["id"] for m in master if m.get("transcript_url")]
        print(f"Backfill 模式：{len(ids)} 条")
        for pid in ids:
            # 已有 words.json 就跳过
            try:
                bucket.head_object(f"raw_podcasts/{pid}/words.json")
                print(f"  ↷ 跳过 {pid}（已有 words.json）")
                continue
            except Exception:
                pass
            pretranslate_for_podcast(pid, bucket)
    else:
        pretranslate_for_podcast(target, bucket)


if __name__ == "__main__":
    main()
