"""
把 Whisper 出的词流（词级时间戳）重新切成"按英文句子"对齐的 segments。

输入：[{"word": "Welcome", "start": 0.0, "end": 0.6}, ...]
输出：[{"start", "end", "en", "words": [{"w","s","e"}]}, ...]

切片规则（从严到松）：
1. 词末是 .!? 且不是缩写 / 小数点 / 后跟小写 → 必断
2. 词末是 ,;: 且累积 ≥ MIN_WORDS_FOR_SOFT (25 词) → 软断
3. 累积 ≥ FORCE_BREAK_AT (40 词) → 强断（防超长复合句）

边界 case：
- "Mr. Smith said hello." → 单段（Mr. 是缩写不切）
- "Price is $3.5 today."  → 单段（小数点不切）
- "e.g., GPT-4 and Claude." → 单段（e.g. 缩写不切）
- "I think... maybe yes." → 单段或两段（取决于省略号识别）
"""
import re
from typing import Optional

HARD_BREAK_PUNCT = ".!?"
SOFT_BREAK_PUNCT = ",;:"
MIN_WORDS_FOR_SOFT = 25
FORCE_BREAK_AT = 40

# 常见英文缩写，词末点号不算句号
ABBREVIATIONS = {
    "Mr.", "Mrs.", "Ms.", "Dr.", "Prof.", "Sr.", "Jr.", "St.",
    "Inc.", "Ltd.", "Co.", "Corp.", "Ave.", "Blvd.",
    "vs.", "etc.", "e.g.", "i.e.", "viz.",
    "U.S.", "U.K.", "U.S.A.", "Ph.D.", "M.D.", "B.A.", "M.A.",
    "a.m.", "p.m.", "A.M.", "P.M.",
    "No.", "Vol.", "Fig.", "Ref.",
}

# 数字+小数点 pattern（如 3.5, $3.5, 1.234）
DECIMAL_RE = re.compile(r"^\$?\d+\.\d+[%]?\.?$")


def is_real_sentence_end(word: str, next_word: Optional[str]) -> bool:
    """判断 word 末尾的标点是否真是句末。

    word 是包含尾标点的原始 token（"hello." / "$3.5" / "Mr." / "yes!"）。
    next_word 是下一个词的原始形态（用于看首字母大小写）。
    """
    if not word:
        return False
    last = word[-1]
    if last not in HARD_BREAK_PUNCT:
        return False

    # ?! 几乎不会出现在缩写里，直接当句末
    if last in "?!":
        return True

    # last == "."
    # 1. 缩写表
    if word in ABBREVIATIONS:
        return False
    # 2. 小数 / 货币（"$3.5" "1.234"）
    if DECIMAL_RE.match(word):
        return False
    # 3. 单字母 + 句号（如 J.K. Rowling 中的 J.）—— 大概率人名缩写
    if len(word) == 2 and word[0].isupper():
        return False
    # 4. 后跟小写词 → 大概率不是真句末（缩写 / 列表项 / 省略号片段）
    if next_word:
        first_alpha = next((c for c in next_word if c.isalpha()), None)
        if first_alpha and first_alpha.islower():
            return False
    return True


def _flush(buf: list[dict]) -> dict:
    """把 word buffer 拼成一个 segment。
    buf: [{"word", "start", "end"}, ...]
    """
    return {
        "start": round(buf[0]["start"], 2),
        "end":   round(buf[-1]["end"], 2),
        "en":    " ".join(w["word"] for w in buf).strip(),
        "words": [
            {"w": w["word"], "s": round(w["start"], 2), "e": round(w["end"], 2)}
            for w in buf
        ],
    }


SILENCE_GAP_FORCE_BREAK = 2.0  # 词与词之间静音 ≥2 秒强制断句（说话人停顿/背景音乐过渡）


def words_to_segments(words: list[dict]) -> list[dict]:
    """词流 → 句子级 segments。
    所有时间戳应该已经在调用方平移到全局，本函数不做偏移处理。
    """
    if not words:
        return []
    out: list[dict] = []
    buf: list[dict] = []
    for i, w in enumerate(words):
        # Whisper 偶尔返回空 word，跳过
        if not w.get("word") or not w["word"].strip():
            continue
        buf.append(w)
        nxt = words[i + 1]["word"] if i + 1 < len(words) else None
        nxt_start = words[i + 1]["start"] if i + 1 < len(words) else None

        word_text = w["word"].strip()
        last_char = word_text[-1] if word_text else ""

        # 规则 0：时间间隔强制断 —— 当前词到下一词之间静音 ≥ SILENCE_GAP_FORCE_BREAK 秒
        # 解决 Whisper 把"句末.句首"跨越长静音 (背景音乐/广告) 错误合并问题
        if nxt_start is not None and (nxt_start - w["end"]) >= SILENCE_GAP_FORCE_BREAK:
            out.append(_flush(buf))
            buf = []
            continue

        # 规则 1：硬断（真句末标点）
        if is_real_sentence_end(word_text, nxt):
            out.append(_flush(buf))
            buf = []
            continue

        # 规则 3：强制断（防超长）—— 优先于软断检查
        if len(buf) >= FORCE_BREAK_AT:
            out.append(_flush(buf))
            buf = []
            continue

        # 规则 2：软断（逗号 / 分号 + 累积够长）
        if last_char in SOFT_BREAK_PUNCT and len(buf) >= MIN_WORDS_FOR_SOFT:
            out.append(_flush(buf))
            buf = []
            continue

    if buf:
        out.append(_flush(buf))
    return out


if __name__ == "__main__":
    # 边界 case 烟雾测试
    def _w(text: str, t: float) -> dict:
        return {"word": text, "start": t, "end": t + 0.3}

    cases = [
        # (description, words, expected_segments)
        (
            "Mr. abbreviation 不切",
            [_w("Mr.", 0), _w("Smith", 0.5), _w("said", 1.0), _w("hello.", 1.5)],
            1,
        ),
        (
            "小数点不切",
            [_w("Price", 0), _w("is", 0.5), _w("$3.5", 1.0), _w("today.", 1.5)],
            1,
        ),
        (
            "e.g. 不切（结尾才切）",
            [_w("e.g.,", 0), _w("GPT-4", 0.5), _w("and", 1.0), _w("Claude.", 1.5)],
            1,
        ),
        (
            "正常两句切两段",
            [_w("Hello", 0), _w("world.", 0.5), _w("How", 1.0), _w("are", 1.5), _w("you?", 2.0)],
            2,
        ),
        (
            "三句陈述切三段",
            [_w("First.", 0), _w("Second.", 0.5), _w("Third.", 1.0)],
            3,
        ),
        (
            "强制断长句（>40 词）",
            [_w(f"word{i}", i * 0.3) for i in range(45)],
            2,
        ),
        (
            "空 word 跳过",
            [_w("Hello", 0), _w("", 0.5), _w("world.", 1.0)],
            1,
        ),
    ]
    print("sentence_segmenter 边界 case 测试：")
    for desc, words, expected in cases:
        segs = words_to_segments(words)
        ok = "✓" if len(segs) == expected else "✗"
        print(f"  {ok} {desc}: 期望 {expected} 段，实际 {len(segs)} 段")
        if len(segs) != expected:
            for s in segs:
                print(f"      → \"{s['en']}\"")
