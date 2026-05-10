"""
Step 3 (post-audio): Extract 2-3 sentence patterns from each episode and
generate explainer audio per the 6-section format.

Sections produced:
  1. pronunciation              (中文导入 + 英文示范)
  2. pronunciation_drill        ("来跟我念 3 次" + 英文核心音节 × 3, speed=0.7)
  3. meaning                    (字面意思; hard 级别如有字面陷阱必须警告)
  4. scene_and_feeling          (核心段: 具象画面 + 感觉关键词 + VS 对比)
  5-7. example1/2/3             (英文例句 + 场景前缀)

Output: writes `patterns: [...]` array back into the episode JSON.
"""

import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

import requests
from pydub import AudioSegment

from config import (
    GPT_API_ENDPOINT,
    GPT_API_KEY,
    GPT_MODEL,
    MINIMAX_API_KEY,
    MINIMAX_API_ENDPOINT,
    MINIMAX_MODEL,
    MINIMAX_VOICE_ALEX,
    MINIMAX_VOICE_LISA,
    MINIMAX_VOICE_ZH_MALE,
    MINIMAX_VOICE_ZH_FEMALE,
    OUTPUT_DIR,
)


PATTERN_MANIFEST_PATH = os.path.join(OUTPUT_DIR, "pattern_manifest.json")

# MiniMax voices are language-specific, so each pattern uses a pair (one English
# voice + one Chinese voice), kept gender-consistent so the speaker sounds like
# the same person across the en/zh switches. Picked by stable hash of pattern_id
# so reruns keep the same voice.
PATTERN_VOICE_PAIRS = [
    {"en": MINIMAX_VOICE_ALEX, "zh": MINIMAX_VOICE_ZH_MALE},     # male pair
    {"en": MINIMAX_VOICE_LISA, "zh": MINIMAX_VOICE_ZH_FEMALE},   # female pair
]

TTS_MAX_ATTEMPTS = 4
TTS_BACKOFF_BASE_S = 2.0
TTS_INTER_CALL_SLEEP_S = 0.15

# Drill cadence — back to 0.7 (for real slow-learning feel) BUT implemented via
# ffmpeg atempo slow-down of the normal-speed demo audio, not a re-synthesis.
# This keeps linking (e.g. "Do you" → /dʒə/) and natural intonation intact.
# TTS at 0.7x (native) separates words and sounds robotic; atempo preserves it.
DRILL_SPEED = 0.6
DRILL_SILENCE_MS = 1200

# Per-level English speed for the demo phrase (the natural-speed read shown
# right after the Chinese intro). Drill is always at DRILL_SPEED regardless.
PATTERN_DEMO_SPEED = {
    "easy": 0.7,
    "medium": 0.8,
    "hard": 0.9,
}

# Examples come at the end and tend to be the hardest to follow — multiple
# new sentences in a row, no repetition. Slow them down a notch below the demo
# so learners have time to actually parse each one.
PATTERN_EXAMPLE_SPEED = {
    "easy": 0.65,
    "medium": 0.75,
    "hard": 0.85,
}

# Pause budget between TTS chunks
SECTION_SILENCE_MS = 400        # between top-level sections
WITHIN_SECTION_SILENCE_MS = 250  # within a section, between zh/en switches

# Dedup is permanent: any template ever extracted is permanently blocked.
# Old explainer audio + scripts are kept long-term; we never regenerate the
# same template (which would produce a near-identical explainer the user has
# already heard). Easy's small daily-talk pool will naturally saturate over
# time and produce zero new patterns per episode — that's accepted.


import re

# Max characters per subtitle subline. Chinese: ~15-20 chars/line on iPhone
# at our font size; 60 chars → ~4 lines → well inside the 5-line cap.
MAX_SUBTITLE_CHARS = 60


def split_into_subtitles(text):
    """Split a long Chinese narration into subtitle-sized subsentences.
    Each chunk stays within MAX_SUBTITLE_CHARS so the App's 5-line cap never
    truncates; instead chunks flip as audio advances.

    Strategy:
      1. Split on sentence enders (。！？；.!?;)
      2. Merge adjacent "X. Y." error-demo fragments (rule 8 pattern).
         Example: "不要分开读成 Could." + "I." → "不要分开读成 Could. I."
      3. If a piece is still too long, split further on commas (，,、)
         and merge adjacent short pieces up to the cap.
    """
    text = (text or "").strip()
    if not text:
        return []

    # Step 1: split by sentence enders (keep the ender attached)
    sentences = re.split(r'(?<=[。！？；.!?;])', text)
    # Filter: must contain at least one alphanumeric or Chinese char — drop fragments
    # that are only punctuation (e.g. lone "。" left after GPT writes "..."? 。")
    def has_content(s):
        return any(c.isalnum() or '\u4e00' <= c <= '\u9fff' for c in s)
    sentences = [s.strip() for s in sentences if s.strip() and has_content(s)]

    # Step 2: merge "Word." + "Word." fragments (error-demo pattern from rule 8)
    # A sentence ending with a capitalized English word + period, followed by
    # another sentence starting with a capitalized English word + period,
    # is the rule-8 error demo structure — keep as one subtitle row.
    ends_with_en_word = re.compile(r'\b[A-Z][a-zA-Z]*\.\s*$')
    starts_with_en_word = re.compile(r'^[A-Z][a-zA-Z]*\.')
    merged = []
    i = 0
    while i < len(sentences):
        current = sentences[i]
        while (i + 1 < len(sentences)
               and ends_with_en_word.search(current)
               and starts_with_en_word.match(sentences[i + 1])):
            current = current + " " + sentences[i + 1]
            i += 1
        merged.append(current)
        i += 1
    sentences = merged

    # Step 3: length cap (split overlong on commas + merge)
    result = []
    for s in sentences:
        if len(s) <= MAX_SUBTITLE_CHARS:
            result.append(s)
            continue
        parts = re.split(r'(?<=[，,、])', s)
        parts = [p.strip() for p in parts if p.strip()]
        buf = ""
        for p in parts:
            if len(buf) + len(p) <= MAX_SUBTITLE_CHARS:
                buf = (buf + p) if buf else p
            else:
                if buf:
                    result.append(buf)
                buf = p
        if buf:
            result.append(buf)
    return result


def clean_for_tts(text):
    """Strip / normalize tokens TTS models mishandle:
    - "dot dot dot" / "..." / "…" → 中文逗号 (natural pause)
    - Trailing em-dashes "——" / "—" (ElevenLabs renders as garbled vowel tail)
    """
    if not text:
        return text
    text = text.replace("dot dot dot", "，")
    text = text.replace("...", "，")
    text = text.replace("…", "，")
    text = text.strip()
    # Strip trailing em-dashes AND any whitespace/period between them and the tail
    while text and text[-1] in "——— ":
        text = text[:-1]
    return text.strip()


def slowdown_segment(seg: AudioSegment, tempo: float = 0.7) -> AudioSegment:
    """Slow down audio preserving pitch + linking via ffmpeg's atempo filter.
    tempo < 1.0 slows down. Range 0.5-2.0.

    Why not re-synthesize with MiniMax at 0.7x speed?
    → MiniMax in native slow mode splits words and kills linking/intonation.
    → atempo stretches the waveform while preserving pitch, so the fully-linked
      "Do you" / "I love" stays linked, just slower.
    """
    import subprocess
    import tempfile
    in_path = None
    out_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as fin:
            seg.export(fin.name, format="mp3")
            in_path = fin.name
        out_path = in_path.replace(".mp3", "_slow.mp3")
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", in_path, "-filter:a", "atempo=%s" % tempo, out_path],
            capture_output=True,
        )
        if result.returncode != 0:
            print("   ⚠️  atempo slowdown failed (rc=%d), using original segment" % result.returncode)
            return seg
        return AudioSegment.from_mp3(out_path)
    except Exception as e:
        print("   ⚠️  atempo slowdown exception (%s), using original segment" % e)
        return seg
    finally:
        if in_path and os.path.exists(in_path):
            try: os.unlink(in_path)
            except OSError: pass
        if out_path and os.path.exists(out_path):
            try: os.unlink(out_path)
            except OSError: pass

LEVEL_HINTS = {
    "easy": "日常基础场景（点餐、问路、求助、感谢、道歉）",
    "medium": "表达观点 / 工作生活场景（讨论、建议、不确定、偏好）",
    "hard": "商务 / 新闻 / 高阶讨论（论述、反驳、转折、强调、归纳）",
}


# ---------- Manifest (cross-episode dedup) ----------

def load_pattern_manifest():
    if os.path.exists(PATTERN_MANIFEST_PATH):
        with open(PATTERN_MANIFEST_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"patterns": []}


def save_pattern_manifest(manifest):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(PATTERN_MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)


def get_recent_templates(manifest, reference_date=None, level=None):
    """Return ALL templates ever extracted at the given level (or all levels if
    `level` is None). Dedup is permanent — once a template is used, it never
    regenerates, so the user never hears two near-identical explainers.

    `reference_date` is unused (kept for backward-compat with older callers).
    """
    seen = set()
    unique = []
    for p in manifest.get("patterns", []):
        if level is not None:
            ep_id = p.get("episode_id", "")
            # episode_id format: "ep-YYYYMMDD-<level>-NNN"
            parts = ep_id.split("-")
            if len(parts) >= 3 and parts[2] != level:
                continue
        t = p.get("template")
        if t and t not in seen:
            seen.add(t)
            unique.append(t)
    return unique


# ---------- GPT extraction ----------

def extract_patterns_with_gpt(episode, recent_templates):
    """Ask GPT to pick 2-3 patterns + write the full 6-section explainer for each."""
    script_text = "\n".join(
        "%s: %s" % (line["speaker"], line["text"])
        for line in episode.get("script", [])
    )

    level = episode.get("level", "easy")
    level_hint = LEVEL_HINTS.get(level, LEVEL_HINTS["easy"])

    dedup_block = ""
    if recent_templates:
        dedup_block = (
            "\n=== 已经讲解过的句型（永久不得重复，必须跳过这些选新的）===\n"
            + "\n".join("- " + t for t in recent_templates)
            + "\n"
        )

    prompt = """你是一位资深英语教学专家，专长是把母语者的"语感"讲透给中国学习者。

=== 任务 ===
从下面这段英语对话脚本中，提取 2-3 个最高频、最实用、最适合学习者掌握的"句型块"（sentence patterns）。
每个句型必须能直接套用、口语化、适合脱口而出。

=== 选择标准 ===
- 必须是"完整可套用的模板"，如 "Could I borrow ___?" / "I'd rather ___ than ___."，不是孤立单词
- 必须高频出现在日常对话中
- 当前级别：%s —— %s
%s
=== 输入：episode 脚本 ===
%s

=== 讲解风格规则（强制遵守，每条不满足都视为失败）===

**规则 1：所有中文文本绝不能出现 "dot dot dot" 或 "..."**
   - 描述句型空缺处时，**用具体的真实例句代替**，不用占位符
   - ❌ 错误："今天我们学 Could I dot dot dot, please?"
   - ✅ 正确："今天我们学 Could I 加动词加宾语 please 这个句型"
   - ✅ 正确（更好）："今天我们学一个超实用的礼貌请求句型：Could I borrow your pen, please?"
   - meaning_zh / pronunciation_intro_zh / scene_and_feeling_zh 都不准出现 "dot dot dot" 和 "..."

**规则 2：pronunciation_demo_en 和 example1.en_text 必须是 episode 原文里的原句**
   - 从 episode 的 script 字段找一个完整句子，**原封不动**作为 pronunciation_demo_en 和 example1.en_text
   - 绝对不改写、不缩略、不扩展、不翻译
   - 原因：用户刚在播客里听过原文，再跟读相同句子形成"耳朵熟 → 嘴巴熟"的闭环
   - 如果同一 template 在 script 里对应多个句子，挑第一个出现的作为 demo
   - example2 和 example3 可以自由发挥到新场景（扩展使用范围）
   - pronunciation_demo_en 必须和 example1.en_text 字符完全一致
   - 不需要输出 drill_text_en 字段（跟读用 demo 音频慢放，无需独立文本）

**规则 3：3 个 template 必须类型多样，避免同类型重复**
   从下列 4 类中挑选，**禁止 3 个全是同类型**：
   - 疑问句（Wh-问句 / Yes/No 问句）：What ___? / Do you ___? / Where ___? / How ___?
   - 陈述句：I love ___. / I need ___. / It's ___. / We can ___.
   - 请求/建议句：Could I ___? / Can you ___? / Let's ___. / Why don't you ___?
   - 感叹/强调句：How ___! / So ___! / Just ___! / No way ___!
   - 如果 script 太简单只能支撑 2 种类型，宁可只输出 2 个 pattern 也不要凑 3 个同类
   - 反例：不要 3 个都是 "Do you ___?" / "What ___?" / "Where ___?"（全是问句）

**规则 4：scene_and_feeling_zh 是最重要的段，必须包含全部 4 项**
   ① **具象画面**："现在你想象一个画面：你在 X，..."
   ② **感觉关键词**：谦卑、试探、退而求其次、勉强、抚平争议、归根结底、保留判断空间...
   ③ **VS 类似句型对比（强制！）**：必须指出至少 1 个相似句型的微妙差异
       - 句式："它和 X 不一样。X 是 ...; [当前句型] 是 ..."
       - 即使是简单基础句型也必须做对比，举例：
         · I want 必须对比 I'd like / I'll have（直接 vs 礼貌）
         · Do you want 必须对比 Would you like（随意 vs 正式）
         · Could I 必须对比 Can I（试探 vs 默认）
         · How do I get to ___ 必须对比 Where is ___（找路径 vs 找位置）
   ④ **结尾固定句式**："记住这种感觉——当你脑子里有 [画面] 的时候，嘴里就会自动冒出 [句型]。不要去翻译 [中文意思]，直接由感觉触发。"
   - 长度 250-400 字

**规则 5：每个 example 必须带"场景前缀"**
   例："咖啡店点餐——客气地试探。"
   不是简单翻译，是给出场景画面感

**规则 6（仅 hard 级别）：字面陷阱必须警告**
   如果句型字面意思和实际意思脱钩（如 "At the end of the day" 字面是"在一天结束的时候"但实际是"归根结底"），
   meaning_zh 段必须开头警告："这是个最容易翻车的字面翻译——它跟时间完全没关系。"

**规则 7：thumbnail_color 必须从这 5 个候选中选**
   "#E8DCC4" (米色) / "#D4E5D4" (淡绿) / "#E5D4E0" (淡紫) / "#DCE5F0" (淡蓝) / "#F0E0D4" (淡橙)
   不同句型用不同颜色让用户视觉区分

**规则 8：pronunciation_intro_zh 只写中文导入，不嵌入完整英文句子，结尾不要加破折号**
   完整英文示范在 pronunciation_demo_en 独立字段，intro 只写中文引导。
   ❌ "今天我们学：Could I borrow your pen, please? 先听标准发音 ——"（嵌入完整英文 + 破折号）
   ❌ "今天我们学一个礼貌请求句型，先听标准发音 ——"（末尾破折号 TTS 会读出杂音）
   ✅ "今天我们学一个礼貌请求句型。先听标准发音。"（纯中文 + 句号收尾）
   结尾必须用句号或问号，禁止用破折号（——）/ 省略号（...）结尾。

**规则 9：meaning_zh 严格短（≤50 字），只讲字面意思**
   meaning_zh 内容限于：
   - 字面意思（这个句型的中文字面对应）
   - Hard 级别字面陷阱警告（如果有）
   **禁止**在 meaning_zh 里讲：
   - 语气 / 感觉 / 使用场景（归 scene_and_feeling_zh）
   - VS 对比（归 scene_and_feeling_zh）
   - 什么时候用、跟谁用（归 scene_and_feeling_zh）
   如果字面意思很直白（像 "I love ___" = "我爱 ___"），meaning_zh 可以只写一句。

**规则 10：scene_prefix_zh 必须是"具体场景——情绪/态度"双段结构**
   格式：XXX——YYY。
   - XXX（2-8 字）：具体场景，必须有画面感
   - YYY（5-15 字）：带情绪 / 态度 / 动作的描述
   - ❌ YYY 是纯名词（"咖啡店——点餐。"）
   - ❌ YYY 是英文翻译（"借东西——Could I borrow it"）
   - ✅ "咖啡店点餐——客气地试探。"
   - ✅ "朋友家做客——这是你的地盘我请求一下。"
   - ✅ "公司开会——想缓和语气提出不同意见。"

=== 输出 JSON Schema（valid JSON，无 markdown，无解释）===

{
  "patterns": [
    {
      "template": "Could I ___ ___, please?",
      "translation_zh": "我可以...吗？（礼貌请求）",
      "scene": "餐厅 / 借东西 / 公共请求",
      "thumbnail_color": "#E8DCC4",
      "pronunciation_intro_zh": "今天我们学一个超实用的礼貌请求句型。先听标准发音。",
      "pronunciation_demo_en": "Could I borrow your pen, please?",
      "meaning_zh": "Could I 字面意思是：我可以做某事吗？",
      "scene_and_feeling_zh": "现在你想象一个画面：你在咖啡店，店员忙得不可开交，你想点单，但又不想显得理所当然。这时候你说 Could I order a latte, please?。这个 Could I 带着一种谦卑感、一种 我知道你忙、我先试探一下、你拒绝也没关系 的口吻。它和 Can I 不一样。Can I 是默认你会答应；Could I 是先把决定权递给对方。所以越是对陌生人、长辈、服务员、上司，越要用 Could I。记住这种感觉——当你脑子里有 给对方留余地 的画面时，嘴里就会自动冒出 Could I。不要去翻译 我可以怎么样吗 这几个字，直接由感觉触发。",
      "examples": [
        { "scene_prefix_zh": "咖啡店点餐——客气地试探。", "en_text": "Could I order a latte, please?" },
        { "scene_prefix_zh": "跟同事借东西——你完全可以拒绝我，但我先问问。", "en_text": "Could I borrow your charger, please?" },
        { "scene_prefix_zh": "在别人家做客——这是你的地盘，我请求一下。", "en_text": "Could I use your bathroom, please?" }
      ],
      "example_sentences": [
        { "english": "Could I order a latte, please?", "chinese": "我可以点一杯拿铁吗？" },
        { "english": "Could I borrow your charger, please?", "chinese": "我可以借一下你的充电器吗？" },
        { "english": "Could I use your bathroom, please?", "chinese": "我可以用一下你的卫生间吗？" }
      ]
    }
  ]
}

=== 输出前自检 (必须全部通过) ===
1. 每个中文段都不含 "dot dot dot" 和 "..."
2. pronunciation_demo_en 和 example1.en_text 是 episode script 里的原文句子（字符完全一致）
3. 3 个 pattern 的 template 不能全是同一类型（如 3 个都是问句）
4. 每个 scene_and_feeling_zh 段都包含 "它和 X 不一样" 的对比句
5. 每个 scene_and_feeling_zh 都以 "记住这种感觉——" 开头的固定结尾收口
6. 每个 example 的 scene_prefix_zh 是场景画面（"X——Y"格式），不是翻译
7. 当前输出的任何 template 都不能出现在上面"最近已抽取过的句型"列表中（窗口内禁止重复）

请输出 2-3 个句型，按高频实用性排序（script 太简单时只输出 2 个）。""" % (
        level,
        level_hint,
        dedup_block,
        script_text,
    )

    response = requests.post(
        GPT_API_ENDPOINT,
        headers={
            "Authorization": "Bearer %s" % GPT_API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "model": GPT_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.7,
            "max_tokens": 8000,
        },
        timeout=300,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1]
    if content.endswith("```"):
        content = content.rsplit("```", 1)[0]
    return json.loads(content.strip())


# ---------- TTS synthesis ----------

def pick_voice_pair_for_pattern(pattern_id):
    """Stable hash → voice pair (en+zh of same gender); same pattern_id always
    gets the same pair on reruns."""
    h = hashlib.md5(pattern_id.encode("utf-8")).hexdigest()
    return PATTERN_VOICE_PAIRS[int(h, 16) % len(PATTERN_VOICE_PAIRS)]


def trim_tts_tail(seg):
    """Trim low-energy tail artifact TTS sometimes leaves (garbled vowel or
    breath sound). Uses detect_leading_silence on reversed segment; safe —
    never touches middle.
    """
    if seg is None or len(seg) < 200:
        return seg
    try:
        from pydub.silence import detect_leading_silence
        rev = seg.reverse()
        trail_ms = detect_leading_silence(rev, silence_threshold=-30, chunk_size=10)
        if 30 < trail_ms < 500:
            return seg[:-trail_ms]
    except Exception:
        pass
    return seg


def minimax_tts(text, voice_id):
    """Synthesize text via MiniMax speech-02-hd. Returns AudioSegment or None.
    Voice is language-specific — caller picks en or zh voice from the pattern's
    gender-paired voice set.
    """
    text = (text or "").strip()
    if not text:
        return None
    body = {
        "model": MINIMAX_MODEL,
        "text": text,
        "voice_setting": {"voice_id": voice_id, "speed": 1.0},
        "audio_setting": {"format": "mp3", "sample_rate": 32000},
    }
    headers = {
        "Authorization": "Bearer %s" % MINIMAX_API_KEY,
        "Content-Type": "application/json",
    }

    last_error = None
    for attempt in range(TTS_MAX_ATTEMPTS):
        try:
            response = requests.post(MINIMAX_API_ENDPOINT, headers=headers, json=body, timeout=60)
        except requests.RequestException as e:
            last_error = "network: %s" % e
            time.sleep(TTS_BACKOFF_BASE_S * (2 ** attempt))
            continue

        time.sleep(TTS_INTER_CALL_SLEEP_S)

        if response.status_code == 429 or response.status_code >= 500:
            last_error = "HTTP %d" % response.status_code
            time.sleep(TTS_BACKOFF_BASE_S * (2 ** attempt))
            continue

        if response.status_code != 200:
            print("   ❌ MiniMax error %d: %s" % (response.status_code, response.text[:300]))
            return None

        try:
            result = response.json()
        except ValueError:
            last_error = "invalid json"
            time.sleep(TTS_BACKOFF_BASE_S * (2 ** attempt))
            continue

        audio_hex = None
        if isinstance(result, dict):
            data = result.get("data")
            if isinstance(data, dict):
                audio_hex = data.get("audio")
            audio_hex = audio_hex or result.get("audio")

        if not audio_hex:
            last_error = "empty audio: %s" % str(result)[:200]
            time.sleep(TTS_BACKOFF_BASE_S * (2 ** attempt))
            continue

        try:
            tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
            tmp.write(bytes.fromhex(audio_hex))
            tmp.close()
            try:
                seg = AudioSegment.from_mp3(tmp.name)
                return trim_tts_tail(seg)
            finally:
                os.unlink(tmp.name)
        except Exception as e:
            last_error = "decode: %s" % e
            time.sleep(TTS_BACKOFF_BASE_S * (2 ** attempt))
            continue

    print("   ❌ MiniMax TTS failed after %d attempts (%s)" % (TTS_MAX_ATTEMPTS, last_error))
    return None


def _append(combined, text, voice_id):
    """Append a MiniMax-synthesized chunk. Text is cleaned first."""
    if not text:
        return combined
    text = clean_for_tts(text)
    if not text:
        return combined
    seg = minimax_tts(text, voice_id)
    if seg is None:
        return combined
    return combined + seg


def synthesize_pattern_audio(pattern_data, output_dir, pattern_id, level="medium"):
    """Generate the explainer audio with PER-SENTENCE timestamps, so subtitles
    can flip alongside the audio (instead of showing one 300-char block).

    `level` controls the English playback speed — beginners get every word
    slowed down for clarity. Demo uses PATTERN_DEMO_SPEED; examples (harder to
    follow because they're new sentences) use the slower PATTERN_EXAMPLE_SPEED.
    The drill segment is always at DRILL_SPEED regardless of level.

    Returns (audio_path, script_lines, duration_sec) where script_lines is a
    list of dicts matching PatternScriptLine in the Swift model.
    """
    demo_speed = PATTERN_DEMO_SPEED.get(level, 1.0)
    example_speed = PATTERN_EXAMPLE_SPEED.get(level, 1.0)
    combined = AudioSegment.empty()
    script_lines = []
    silence_short = AudioSegment.silent(duration=WITHIN_SECTION_SILENCE_MS)
    silence_section = AudioSegment.silent(duration=SECTION_SILENCE_MS)
    silence_drill = AudioSegment.silent(duration=DRILL_SILENCE_MS)

    # Pick a voice pair (en + zh, gender-matched) for this pattern.
    voices = pick_voice_pair_for_pattern(pattern_id)
    en_voice = voices["en"]
    zh_voice = voices["zh"]

    # Pre-synthesize demo once at natural speed; reused (atempo-slowed) in drill.
    demo_text = pattern_data["pronunciation_demo_en"]
    demo_natural = minimax_tts(demo_text, en_voice)
    drill_slow = slowdown_segment(demo_natural, tempo=DRILL_SPEED) if demo_natural is not None else None
    # Demo for the explanation phase is slowed per level (always derived from
    # the natural-speed clip — drill is also from natural, never compounded).
    if demo_natural is not None and demo_speed < 1.0:
        demo_segment = slowdown_segment(demo_natural, tempo=demo_speed)
    else:
        demo_segment = demo_natural

    # ===== 1. pronunciation =====
    # intro (zh, multi-sentence) → demo (en, single line)
    for sub in split_into_subtitles(pattern_data.get("pronunciation_intro_zh", "")):
        s_ms = len(combined)
        combined = _append(combined, sub, zh_voice)
        if len(combined) > s_ms:
            script_lines.append({
                "section": "pronunciation", "text_zh": sub, "text_en": "",
                "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
            })
            combined += silence_short

    if demo_segment is not None:
        s_ms = len(combined)
        combined += demo_segment
        script_lines.append({
            "section": "pronunciation", "text_zh": "", "text_en": demo_text,
            "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
        })
        combined += silence_short

    combined += silence_section

    # ===== 2. pronunciation_drill (3× slowed demo, linking preserved) =====
    s_ms = len(combined)
    combined = _append(combined, "来，跟我念 3 次。", zh_voice)
    if len(combined) > s_ms:
        script_lines.append({
            "section": "pronunciation_drill", "text_zh": "来，跟我念 3 次 ——", "text_en": "",
            "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
        })
    combined += silence_short

    if drill_slow is not None:
        for _ in range(3):
            s_ms = len(combined)
            combined += drill_slow
            # Each drill repeat is a subtitle row showing the English target sentence
            script_lines.append({
                "section": "pronunciation_drill", "text_zh": "", "text_en": demo_text,
                "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
            })
            combined += silence_drill

    combined += silence_section

    # ===== 3. meaning (multi-sentence zh) =====
    for sub in split_into_subtitles(pattern_data.get("meaning_zh", "")):
        s_ms = len(combined)
        combined = _append(combined, sub, zh_voice)
        if len(combined) > s_ms:
            script_lines.append({
                "section": "meaning", "text_zh": sub, "text_en": "",
                "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
            })
            combined += silence_short
    combined += silence_section

    # ===== 4. scene_and_feeling (longest, always needs chunking) =====
    for sub in split_into_subtitles(pattern_data.get("scene_and_feeling_zh", "")):
        s_ms = len(combined)
        combined = _append(combined, sub, zh_voice)
        if len(combined) > s_ms:
            script_lines.append({
                "section": "scene_and_feeling", "text_zh": sub, "text_en": "",
                "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
            })
            combined += silence_short
    combined += silence_section

    # ===== 5-7. example 1/2/3 — zh scene prefix → en sentence =====
    examples = pattern_data.get("examples", [])[:3]
    for i, ex in enumerate(examples, 1):
        section = "example%d" % i
        scene_prefix = ex.get("scene_prefix_zh", "")
        for sub in split_into_subtitles(scene_prefix):
            s_ms = len(combined)
            combined = _append(combined, sub, zh_voice)
            if len(combined) > s_ms:
                script_lines.append({
                    "section": section, "text_zh": sub, "text_en": "",
                    "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
                })
                combined += silence_short

        en_text = ex.get("en_text", "")
        if en_text:
            s_ms = len(combined)
            # Synthesize at natural speed, then slow down per level (matches demo).
            ex_natural = minimax_tts(clean_for_tts(en_text), en_voice)
            if ex_natural is not None:
                ex_seg = slowdown_segment(ex_natural, tempo=example_speed) if example_speed < 1.0 else ex_natural
                combined += ex_seg
                script_lines.append({
                    "section": section, "text_zh": "", "text_en": en_text,
                    "start": s_ms / 1000.0, "end": len(combined) / 1000.0,
                })

        if i < len(examples):
            combined += silence_section

    audio_path = os.path.join(output_dir, "%s.mp3" % pattern_id)
    combined.export(audio_path, format="mp3", bitrate="128k")
    duration_sec = len(combined) / 1000.0
    return audio_path, script_lines, duration_sec


# ---------- Pattern object assembly ----------

def build_pattern_object(idx, pattern_data, episode_id, episode_date, level, audio_path, script_lines, duration_sec):
    """Assemble final Pattern object. script_lines already has fine-grained
    per-sentence timestamps from synthesize_pattern_audio."""
    date_compact = episode_date.replace("-", "")
    ep_suffix = episode_id.rsplit("-", 1)[-1]
    pattern_id = "pattern_%s_%s_%s_%d" % (level, date_compact, ep_suffix, idx)

    return {
        "id": pattern_id,
        "episode_id": episode_id,
        "template": pattern_data["template"],
        "translation_zh": pattern_data["translation_zh"],
        "scene": pattern_data["scene"],
        # Local path for now; upload_oss step rewrites to OSS URL.
        "audio_url": audio_path,
        "duration_seconds": int(duration_sec),
        "explainer_script": script_lines,
        "example_sentences": pattern_data.get("example_sentences", []),
        "thumbnail_color": pattern_data.get("thumbnail_color", "#E8DCC4"),
    }


# ---------- Per-episode driver ----------

def process_episode(episode_json_path, manifest, force=False):
    """Extract patterns for one episode. Skips if patterns already exist (unless force=True)."""
    with open(episode_json_path, "r", encoding="utf-8") as f:
        episode = json.load(f)

    if episode.get("patterns") and not force:
        print("   ⏭  Skip %s: already has patterns" % episode["id"])
        return False

    print("\n📚 Extracting patterns from %s (%s)..." % (episode["id"], episode["title"]))

    recent = get_recent_templates(manifest, episode.get("date", ""), level=episode.get("level"))
    try:
        result = extract_patterns_with_gpt(episode, recent)
    except Exception as e:
        print("   ❌ GPT extraction failed: %s" % e)
        return False

    raw_patterns = result.get("patterns", [])
    if not raw_patterns:
        print("   ⚠️  GPT returned no patterns")
        return False

    # Defensive client-side dedup: if GPT returned a template we explicitly
    # listed as off-limits (happens occasionally), drop it before TTS to save
    # API cost and keep the 30-day rule hard.
    recent_set = set(recent)
    filtered = []
    for p in raw_patterns:
        t = p.get("template", "").strip()
        if t and t in recent_set:
            print("   ⏭  Dropping already-extracted template: %s" % t[:60])
            continue
        filtered.append(p)
    if not filtered:
        print("   ⚠️  All GPT patterns were already extracted before — skipping episode")
        return False
    raw_patterns = filtered

    episode_dir = os.path.dirname(episode_json_path)
    patterns_dir = os.path.join(episode_dir, "patterns")
    os.makedirs(patterns_dir, exist_ok=True)

    final_patterns = []
    for idx, pattern_data in enumerate(raw_patterns, 1):
        template = pattern_data.get("template", "?")
        print("   🎙  Pattern %d: %s" % (idx, template[:60]))

        date_compact = episode["date"].replace("-", "")
        # Include episode suffix ("001"/"002"/...) so same-day same-level eps don't collide.
        ep_suffix = episode["id"].rsplit("-", 1)[-1]
        pattern_id = "pattern_%s_%s_%s_%d" % (episode["level"], date_compact, ep_suffix, idx)

        try:
            audio_path, script_lines, duration_sec = synthesize_pattern_audio(
                pattern_data, patterns_dir, pattern_id, level=episode["level"]
            )
        except Exception as e:
            print("      ❌ TTS failed for %s: %s" % (pattern_id, e))
            continue

        pattern_obj = build_pattern_object(
            idx, pattern_data,
            episode["id"], episode["date"], episode["level"],
            audio_path, script_lines, duration_sec,
        )
        final_patterns.append(pattern_obj)
        print("      ✅ %.1fs — %s" % (duration_sec, audio_path))

        manifest.setdefault("patterns", []).append({
            "template": template,
            "episode_id": episode["id"],
            "date": episode["date"],
        })

    if not final_patterns:
        print("   ⚠️  All patterns failed for %s" % episode["id"])
        return False

    episode["patterns"] = final_patterns
    with open(episode_json_path, "w", encoding="utf-8") as f:
        json.dump(episode, f, ensure_ascii=False, indent=2)

    save_pattern_manifest(manifest)
    print("   ✅ Wrote %d patterns to %s" % (len(final_patterns), episode_json_path))
    return True


def main():
    """Usage:
       python3 extract_patterns.py                  # all levels
       python3 extract_patterns.py easy             # one level
       python3 extract_patterns.py easy ep_id       # one specific episode
       python3 extract_patterns.py easy ep_id force # rerun even if patterns exist
    """
    target_level = sys.argv[1] if len(sys.argv) > 1 else None
    target_id = sys.argv[2] if len(sys.argv) > 2 else None
    force = len(sys.argv) > 3 and sys.argv[3] == "force"

    manifest = load_pattern_manifest()

    if target_id and target_level:
        ep_path = os.path.join(OUTPUT_DIR, target_level, "%s.json" % target_id)
        if not os.path.exists(ep_path):
            print("❌ Episode not found: %s" % ep_path)
            return
        process_episode(ep_path, manifest, force=force)
        return

    levels = [target_level] if target_level else ["easy", "medium", "hard"]
    for level in levels:
        level_dir = os.path.join(OUTPUT_DIR, level)
        if not os.path.exists(level_dir):
            print("⚠️  No episodes for [%s]" % level)
            continue
        for ep_path in sorted(Path(level_dir).glob("*.json")):
            process_episode(str(ep_path), manifest, force=force)

    print("\n🎉 Pattern extraction complete!")


if __name__ == "__main__":
    main()
