"""
Layer 3：transcript 输出后处理 / 兜底过滤。

Whisper 偶尔会产出：
- 末尾粘连的非 ASCII 字符（变音符 / 中韩日俄阿文碎片）
- "Topic 1. Topic 2." 这种数字模板幻觉
- 假 URL / Copyright 套话
- 重复短语 ≥3 次（Whisper attention loop bug）
- 仅含标点的过短段（".", "5." 等）

这层在 transcribe 出来后、翻译前过滤一遍，让 GPT 翻译看到的是干净英文。
被改动的段会标记 dirty=True，调用方可决定是否重新翻译（如果 zh 已经存在）。
"""
import re
from typing import Tuple

# 正则池
NON_ASCII_RUN_RE = re.compile(r'[^\x00-\x7F]+')
TOPIC_N_RE = re.compile(r'(?:\bTopic\s+\d+[\.,]?\s*){1,}', re.IGNORECASE)
URL_RE = re.compile(r'(?:https?://|www\.)\S+', re.IGNORECASE)
EMAIL_RE = re.compile(r'\S+@\S+\.\S+')
COPYRIGHT_RE = re.compile(r'Copyright\s*©?\s*\d{0,4}[^.]*\.', re.IGNORECASE)
SUBSCRIBE_RE = re.compile(
    r'(?:thanks for watching|subscribe to (?:my|our|the)|don\'?t forget to subscribe|like and subscribe|ring the bell|link in (?:the )?description)[^.]*\.?',
    re.IGNORECASE
)


def _strip_trailing_garbage(text: str) -> str:
    """剥掉末尾连续的非 ASCII / 模板套话。
    保留中间的非 ASCII（中间的可能是引用的外文人名等合法用法）。
    """
    s = text.rstrip()
    while True:
        prev = s
        # 末尾 Topic-N 模板
        s = TOPIC_N_RE.sub('', s).rstrip()
        # 末尾 URL
        m = URL_RE.search(s)
        if m and m.end() >= len(s) - 5:  # URL 在末尾附近
            s = s[:m.start()].rstrip()
        # 末尾 Copyright
        m = COPYRIGHT_RE.search(s)
        if m and m.end() >= len(s) - 5:
            s = s[:m.start()].rstrip()
        # 末尾 Subscribe / Thanks-for-watching 套话
        m = SUBSCRIBE_RE.search(s)
        if m and m.end() >= len(s) - 5:
            s = s[:m.start()].rstrip()
        # 末尾连续非 ASCII run
        # 只剥末尾的非 ASCII 块，保留前面的英文标点（包括末尾句号）
        tail_match = re.search(r'\s*[^\x00-\x7F\s]+[^\x00-\x7F\s.,!?]*\s*$', s)
        if tail_match and tail_match.start() > 0:
            s = s[:tail_match.start()].rstrip()
        if s == prev:
            break
    return s


def _dedupe_loop(text: str) -> str:
    """检测并去重 ≥3 次的相邻短语循环。
    例：'or a or a or a robotic arm' → 'or a robotic arm'
    """
    words = text.split()
    if len(words) < 6:
        return text

    out: list[str] = []
    i = 0
    while i < len(words):
        # 试 2-词 phrase 起步
        for phrase_len in (3, 2):
            if i + phrase_len * 3 > len(words):
                continue
            phrase = words[i:i + phrase_len]
            # 看接下来是否连续重复 ≥2 次（总共 3 次）
            repeat_count = 1
            j = i + phrase_len
            while j + phrase_len <= len(words) and words[j:j + phrase_len] == phrase:
                repeat_count += 1
                j += phrase_len
            if repeat_count >= 3:
                # 跳过重复，只保留 1 次
                out.extend(phrase)
                i = j
                break
        else:
            out.append(words[i])
            i += 1
            continue
        # break 出 for-else 会到这里（已 i=j）
    return ' '.join(out)


def clean_segment_text(text: str) -> Tuple[str, bool]:
    """清洗单段英文。返回 (新文本, 是否被改)。"""
    if not text:
        return text, False
    original = text
    cleaned = _strip_trailing_garbage(text)
    cleaned = _dedupe_loop(cleaned)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned, cleaned != original


def clean_segments(segments: list[dict]) -> tuple[list[dict], int, int]:
    """清洗整批 segments。返回 (新 segments, 修改数, 删除数)。
    - 改了内容 → 标记 _dirty=True 让调用方知道需要重新翻译
    - 段长 < 3 字符 → 整段删除
    - words 数组保留不动（时间戳还有用）
    """
    out = []
    modified = 0
    dropped = 0
    for s in segments:
        en = s.get("en", "") or ""
        new_en, dirty = clean_segment_text(en)
        if len(new_en.strip()) < 3:
            dropped += 1
            continue
        s2 = dict(s)
        s2["en"] = new_en
        if dirty:
            s2["_dirty"] = True
            modified += 1
        out.append(s2)
    return out, modified, dropped


if __name__ == "__main__":
    cases = [
        ("Topic 1. Topic 2. Topic 3.", ""),
        ("Hello world. Topic 1.", "Hello world."),
        ("Welcome. Copyright © 2020 So-and-So. www.fake.com", "Welcome."),
        ("or a or a or a robotic arm", "or a robotic arm"),
        ("This is normal text.", "This is normal text."),
        ("These are foreign 中文 words intentionally.", "These are foreign 中文 words intentionally."),
        ("Hello world. 中文乱入", "Hello world."),
        ("Thanks for watching, please subscribe!", ""),
        (".", ""),
        ("a", ""),
    ]
    print("transcript_cleaner 边界 case 测试：")
    for src, expected in cases:
        got, dirty = clean_segment_text(src)
        ok = "✓" if got.strip() == expected.strip() else "✗"
        print(f"  {ok} src=\"{src[:50]}\"")
        print(f"     got=\"{got}\" dirty={dirty}")
        if got.strip() != expected.strip():
            print(f"     EXPECTED=\"{expected}\"")
