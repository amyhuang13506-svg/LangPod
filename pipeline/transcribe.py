"""
raw_podcast 字幕生成 pipeline（v2，按句子切 + 词级时间戳）。

主流程：
  1. ffmpeg 抽音轨：16 kHz mono 64 kbps mp3
  2. silence_chunker 按静音点切片（目标 ~8min/片）
  3. 并行调 Groq Whisper API（带 prompt + word-level timestamps）
  4. 平移 chunk 偏移、拼成全局词流
  5. sentence_segmenter 按英文句子重切 segments，每段含 words 数组
  6. GPT 批量翻译（sentence-level）
  7. 输出 transcript.json：{podcast_id, segments: [{start, end, en, zh, words}]}
  8. 上传 OSS（或本地 dump）

改动：相对老版本，不再使用本地 whisper 包；不再用 segment-level；不再单文件上传。
"""
import json
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

import requests

from config import (
    GPT_API_KEY,
    GPT_MODEL,
    OSS_CDN_DOMAIN,
    GROQ_API_KEY,
    GROQ_WHISPER_ENDPOINT,
    GROQ_WHISPER_MODEL,
)
from silence_chunker import chunk_audio_by_silence
from whisper_prompt import build_prompt
from sentence_segmenter import words_to_segments
from transcript_cleaner import clean_segments

WHISPER_API_ENDPOINT = GROQ_WHISPER_ENDPOINT
WHISPER_API_KEY = GROQ_API_KEY
WHISPER_MODEL = GROQ_WHISPER_MODEL
GPT_CHAT_ENDPOINT = "https://api.v3.cm/v1/chat/completions"


def extract_audio_for_transcription(media_path: Path, out_path: Path, bitrate: str = "64k") -> bool:
    """ffmpeg 抽音轨：16 kHz mono mp3。
    64 kbps 兼顾识别准确率和文件大小（30min 视频 ≈ 14MB，单片远小于 25MB Whisper 限制）。
    Layer 1：加 loudnorm 响度归一，让模糊/低音量段也清晰，减少 Whisper 在静默/低音区幻觉。
    """
    import subprocess
    cmd = [
        "ffmpeg", "-y", "-i", str(media_path),
        "-vn", "-ac", "1", "-ar", "16000",
        # loudnorm: 把响度归一到 -16 LUFS，True Peak ≤ -1.5dB，LRA=11
        # 效果：长 podcast 里的低音量话音被推到清晰水平，幻觉触发条件减少
        "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
        "-b:a", bitrate, "-acodec", "libmp3lame",
        str(out_path),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=600)
        if result.returncode != 0:
            print(f"  ✗ ffmpeg 失败: {result.stderr.decode()[:300]}")
            return False
        return out_path.exists()
    except subprocess.TimeoutExpired:
        print("  ✗ ffmpeg 超时（>10min）")
        return False


def transcribe_chunk(chunk_path: Path, offset: float, prompt: str, max_5xx_retries: int = 6) -> tuple:
    """单片 Whisper 转写。返回 (offset, list_of_words)。
    words 时间戳是 chunk 内相对的（未平移），调用方自己加 offset。

    重试策略：
    - 429 限频：**无限重试**，尊重 Retry-After header（无 header 则用梯度 [15, 30, 60, 120, 300]s）
    - 5xx 瞬态错误：最多 max_5xx_retries 次，指数退避 [2, 4, 8, 16, 32, 64]s
    - 4xx 客户端错误（非 429）：立即放弃
    - 网络异常：当 5xx 处理
    """
    import time

    backoff_429 = [15, 30, 60, 120, 300]   # 末尾 300s 兜底，超过这个数继续用 300s
    backoff_5xx = [2, 4, 8, 16, 32, 64]

    attempt_429 = 0   # 429 计数器（无上限）
    attempt_5xx = 0   # 5xx 计数器（有上限）

    # Layer 2：彻底去掉长 prompt（实测会触发 Groq 500 + prompt 词汇泄露到输出）
    # 仅保留极简 6 词专有名词提示，作为拼写线索
    minimal_prompt = "OpenAI, NVIDIA, Anthropic, Claude, GPT, AGI."
    use_prompt = True

    while True:
        try:
            with chunk_path.open("rb") as f:
                files = {"file": (chunk_path.name, f, "audio/mpeg")}
                data = [
                    ("model", WHISPER_MODEL),
                    ("response_format", "verbose_json"),
                    ("timestamp_granularities[]", "word"),
                    ("language", "en"),
                    ("temperature", "0"),  # Layer 2：显式零温度，最少随机性
                ]
                if use_prompt:
                    data.append(("prompt", minimal_prompt))
                r = requests.post(
                    WHISPER_API_ENDPOINT,
                    headers={
                        "Authorization": f"Bearer {WHISPER_API_KEY}",
                        # Groq 对 python-requests 默认 UA 偶发返回 500，伪装成 curl
                        "User-Agent": "curl/8.4.0",
                    },
                    files=files,
                    data=data,
                    timeout=600,
                )
            if r.status_code == 200:
                body = r.json()
                words = body.get("words") or []
                clean = [w for w in words if w.get("word") and w["word"].strip()]
                return (offset, clean)

            # 4xx 客户端错误（非 429）立刻放弃
            if 400 <= r.status_code < 500 and r.status_code != 429:
                print(f"  ✗ HTTP {r.status_code} on chunk@{offset:.0f}s（4xx 不重试）: {r.text[:200]}")
                return (offset, [])

            # 429：尊重 Retry-After，无限重试
            if r.status_code == 429:
                retry_after = r.headers.get("retry-after") or r.headers.get("Retry-After")
                if retry_after:
                    try:
                        wait = max(int(float(retry_after)), 1)
                    except ValueError:
                        wait = backoff_429[min(attempt_429, len(backoff_429) - 1)]
                else:
                    wait = backoff_429[min(attempt_429, len(backoff_429) - 1)]
                print(f"  ⚠️  429 chunk@{offset:.0f}s #{attempt_429 + 1}（无限重试），{wait}s 后再试")
                attempt_429 += 1
                time.sleep(wait)
                continue

            # 5xx 瞬态错误：有上限。第二次 5xx 时丢 prompt（某些 prompt+音频组合触发 Groq bug）
            if attempt_5xx >= max_5xx_retries:
                print(f"  ✗ chunk@{offset:.0f}s 5xx 重试 {max_5xx_retries} 次仍失败")
                return (offset, [])
            wait = backoff_5xx[min(attempt_5xx, len(backoff_5xx) - 1)]
            if attempt_5xx == 1 and use_prompt:
                use_prompt = False
                print(f"  ⚠️  HTTP {r.status_code} chunk@{offset:.0f}s 第{attempt_5xx + 1}/{max_5xx_retries}次，丢 prompt + {wait}s 后重试")
            else:
                print(f"  ⚠️  HTTP {r.status_code} chunk@{offset:.0f}s 第{attempt_5xx + 1}/{max_5xx_retries}次，{wait}s 后重试")
            attempt_5xx += 1
            time.sleep(wait)
        except Exception as e:
            if attempt_5xx >= max_5xx_retries:
                print(f"  ✗ chunk@{offset:.0f}s 网络异常重试上限")
                return (offset, [])
            wait = backoff_5xx[min(attempt_5xx, len(backoff_5xx) - 1)]
            print(f"  ⚠️  网络异常 chunk@{offset:.0f}s #{attempt_5xx + 1}/{max_5xx_retries}：{e}（{wait}s 后再试）")
            attempt_5xx += 1
            time.sleep(wait)


GAP_DETECT_THRESHOLD = 5.0   # 词间隔 ≥ 5s 视为可能漏听
GAP_PADDING = 1.5             # 抽片前后多留 1.5 秒上下文
GAP_MIN_DURATION = 1.0        # 间隔至少 1s 才补转（避免抖动）


def _detect_gaps(words: list[dict]) -> list[tuple[float, float]]:
    """扫描词流，返回 [(gap_start, gap_end), ...] 漏听可疑区间"""
    gaps = []
    for i in range(len(words) - 1):
        gap_start = words[i]["end"]
        gap_end = words[i + 1]["start"]
        gap_dur = gap_end - gap_start
        if gap_dur >= GAP_DETECT_THRESHOLD:
            gaps.append((gap_start, gap_end))
    return gaps


def _transcribe_gap(audio_path: Path, work_dir: Path, gap_start: float, gap_end: float,
                    prompt: str, idx: int) -> list[dict]:
    """对漏听区间单独抽片重转，返回带全局时间戳的词流"""
    import subprocess
    pad = GAP_PADDING
    actual_start = max(0.0, gap_start - pad)
    actual_end = gap_end + pad
    duration = actual_end - actual_start

    if duration < GAP_MIN_DURATION:
        return []

    chunk_path = work_dir / f"gap_{idx:03d}.mp3"
    cmd = [
        "ffmpeg", "-y",
        "-ss", f"{actual_start:.3f}",
        "-t", f"{duration:.3f}",
        "-i", str(audio_path),
        "-vn", "-ac", "1", "-ar", "16000",
        "-b:a", "64k", "-acodec", "libmp3lame",
        str(chunk_path),
    ]
    r = subprocess.run(cmd, capture_output=True, timeout=120)
    if r.returncode != 0 or not chunk_path.exists():
        return []

    offset, words = transcribe_chunk(chunk_path, actual_start, prompt)
    if not words:
        return []

    adjusted = []
    for w in words:
        wstart = float(w["start"]) + actual_start
        wend = float(w["end"]) + actual_start
        # 只保留落在间隔范围内的（去掉 padding 区域避免和原 chunk 重叠）
        if gap_start <= wstart < gap_end:
            adjusted.append({"word": w["word"], "start": wstart, "end": wend})
    return adjusted


def fill_gaps(audio_path: Path, work_dir: Path, all_words: list[dict], prompt: str) -> list[dict]:
    """Layer 5：检测漏听间隔 → 单独重转 → 按位置插回词流（不参与 sort，保留 Whisper 内部顺序）"""
    if not all_words:
        return all_words
    gaps = _detect_gaps(all_words)
    if not gaps:
        return all_words

    total_gap_sec = sum(e - s for s, e in gaps)
    print(f"  → 检测到 {len(gaps)} 个可疑漏听区间（总 {total_gap_sec:.0f}s）")

    # gaps 是按主词流位置升序的，倒序插入避免索引漂移
    insertions = []  # (insert_index, new_words)
    new_words_total = 0
    for idx, (gs, ge) in enumerate(gaps):
        new_words = _transcribe_gap(audio_path, work_dir, gs, ge, prompt, idx)
        if not new_words:
            continue
        # 找该 gap 在 all_words 里的位置：第一个 start >= ge 的索引
        insert_at = next(
            (i for i, w in enumerate(all_words) if w["start"] >= ge),
            len(all_words)
        )
        insertions.append((insert_at, new_words))
        print(f"    · gap@{gs:.0f}-{ge:.0f}s（{ge-gs:.0f}s）补 {len(new_words)} 词")
        new_words_total += len(new_words)

    # 倒序插入（保证前面索引不变）
    for insert_at, new_words in reversed(insertions):
        all_words[insert_at:insert_at] = new_words

    if new_words_total:
        print(f"  ✓ 补转累计 {new_words_total} 词，总词流 {len(all_words)}")
    else:
        print(f"  ✓ 间隔区间均为真实静音，无新词")
    return all_words


def transcribe_audio(audio_path: Path, work_dir: Path, prompt: str, max_workers: int = 4) -> list[dict]:
    """主转写流程：切片 → 并行 Whisper → 平移 offset → 漏听补转 → 词流。
    返回全局词流：[{word, start, end}, ...]。
    """
    chunks = chunk_audio_by_silence(audio_path, work_dir / "chunks")
    if not chunks:
        return []

    print(f"  → 并行转写 {len(chunks)} 片（max_workers={max_workers}）")
    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = [ex.submit(transcribe_chunk, p, off, prompt) for p, off in chunks]
        for fut in as_completed(futures):
            offset, words = fut.result()
            results.append((offset, words))
            print(f"    · chunk@{offset:.0f}s → {len(words)} 词")

    # 按 offset 排序后拼接（并行完成顺序 ≠ chunk 顺序）
    results.sort(key=lambda x: x[0])
    all_words = []
    for offset, words in results:
        for w in words:
            all_words.append({
                "word": w["word"],
                "start": float(w["start"]) + offset,
                "end": float(w["end"]) + offset,
            })
    print(f"  ✓ 主转写累计 {len(all_words)} 词")

    # Layer 5：漏听补转
    gap_dir = work_dir / "gaps"
    gap_dir.mkdir(exist_ok=True)
    all_words = fill_gaps(audio_path, gap_dir, all_words, prompt)

    return all_words


def _translate_one_batch(chunk: list[dict]) -> list[str]:
    """翻译一批，返回 zh 列表。返回 [] 表示彻底失败。"""
    en_lines = [f"{idx}: {s['en']}" for idx, s in enumerate(chunk)]
    prompt = (
        "You are translating English video subtitles into Chinese for an "
        "English-learning app. Users will see English and Chinese side-by-side "
        "and need to map each English word/phrase to its Chinese equivalent.\n\n"
        "RULES (strict):\n"
        "1. **Translate literally**, preserving English word order and clause "
        "structure as much as possible.\n"
        "2. **Do NOT paraphrase, summarize, or add information** that isn't in "
        "the English source.\n"
        "3. **Do NOT remove anything** — even filler words like 'you know' / "
        "'I mean' get translated to '你知道' / '我是说'.\n"
        "4. Keep tech acronyms in English (CUDA, GPU, AGI, LLM, AI, API, CPU).\n"
        "5. Translate proper nouns using standard Chinese transliteration "
        "(Jensen Huang → 黄仁勋, Tesla → 特斯拉, Apple → 苹果).\n"
        "6. Maintain sentence boundaries: each English line gets exactly one "
        "Chinese translation in the same position.\n"
        "7. Avoid Chinese idioms / 成语 unless the English uses an idiom too.\n"
        f"8. **CRITICAL**: Output array MUST have EXACTLY {len(chunk)} items.\n\n"
        "Output STRICT JSON, same length and order as input.\n\n"
        "Input lines:\n" + "\n".join(en_lines) + "\n\n"
        f'Output: {{"translations": ["zh line 0", ..., "zh line {len(chunk)-1}"]}}'
    )
    try:
        r = requests.post(
            GPT_CHAT_ENDPOINT,
            headers={"Authorization": f"Bearer {GPT_API_KEY}"},
            json={
                "model": GPT_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "response_format": {"type": "json_object"},
                "temperature": 0.2,
            },
            timeout=120,
        )
        if r.status_code != 200:
            print(f"  ⚠️  GPT translate HTTP {r.status_code}: {r.text[:200]}")
            return []
        content = r.json()["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        return parsed.get("translations", [])
    except Exception as e:
        print(f"  ⚠️  GPT translate error: {e}")
        return []


def translate_segments_to_zh(segments: list[dict]) -> list[dict]:
    """批量调 GPT 翻译。Layer 4：批 20 + 长度校验 + 失败重试 + 漏译单独补。"""
    BATCH = 20
    all_with_zh = []
    for i in range(0, len(segments), BATCH):
        chunk = segments[i:i + BATCH]
        # 第一次尝试
        zh_list = _translate_one_batch(chunk)
        # 长度校验：返回数 ≠ 输入数 → 重试一次
        if len(zh_list) != len(chunk):
            print(f"    · 翻译批 {i}-{i+len(chunk)} 长度不匹配（{len(zh_list)}/{len(chunk)}），重试")
            zh_list = _translate_one_batch(chunk)
        # 仍漏 → 占位空字符串，后续单条补
        for j, s in enumerate(chunk):
            zh = zh_list[j] if j < len(zh_list) else ""
            all_with_zh.append({**s, "zh": zh})
        print(f"    · 翻译进度 {i + len(chunk)}/{len(segments)}")

    # 收尾：找漏译的（zh 为空）逐条单独补译
    missing_idx = [i for i, s in enumerate(all_with_zh) if not s.get("zh", "").strip() and s["en"].strip()]
    if missing_idx:
        print(f"  → 兜底单译 {len(missing_idx)} 条漏译")
        for idx in missing_idx:
            single = [all_with_zh[idx]]
            zh = _translate_one_batch(single)
            if zh:
                all_with_zh[idx]["zh"] = zh[0]
    return all_with_zh


def generate_transcript(
    media_path: Path,
    podcast_id: str,
    bucket=None,
    podcast_meta: Optional[dict] = None,
    local_output: Optional[Path] = None,
    skip_translate: bool = False,
) -> Optional[str]:
    """主入口：抽音轨 → 切片 → 转写 → 句段化 → 翻译 → 输出。

    输出去向（三选一）：
    - local_output 指定路径 → dump 到本地，不上传 OSS（开发/测试）
    - bucket 指定 → 上传 OSS，返回 URL（生产）
    - 都不指定 → 仅返回 dict（rare，仅测试用）
    """
    with tempfile.TemporaryDirectory() as tmp:
        tmpd = Path(tmp)
        audio_path = tmpd / "audio.mp3"

        # 1) 抽音轨
        if not extract_audio_for_transcription(media_path, audio_path):
            return None

        # 2) 构 prompt
        prompt = build_prompt(podcast_meta or {})
        print(f"  · prompt（{len(prompt)} chars）")

        # 3) 切片 + 并行 Whisper → 全局词流
        all_words = transcribe_audio(audio_path, tmpd, prompt)
        if not all_words:
            print("  ✗ 转写失败，无词流")
            return None

        # 4) 词流 → 句段
        segments_en = words_to_segments(all_words)
        print(f"  ✓ 切句出 {len(segments_en)} 段")

        # 4.5) Layer 3：清洗 segments（去 Topic-N、URL、Copyright、loop、非 ASCII 末尾、过短段）
        segments_en, modified, dropped = clean_segments(segments_en)
        # 删除 _dirty 标记，对外不暴露
        for s in segments_en:
            s.pop("_dirty", None)
        print(f"  ✓ 清洗：修改 {modified} 段，删除 {dropped} 段，剩 {len(segments_en)}")

        # 5) 翻译（可跳过）
        if skip_translate:
            print(f"  ⏭  跳过翻译（skip_translate=True）")
            segments_zh = [{**s, "zh": ""} for s in segments_en]
        else:
            segments_zh = translate_segments_to_zh(segments_en)

        # 6) 输出
        transcript = {
            "podcast_id": podcast_id,
            "segments": segments_zh,
        }
        transcript_bytes = json.dumps(transcript, ensure_ascii=False, indent=2).encode("utf-8")

        if local_output is not None:
            local_output.parent.mkdir(parents=True, exist_ok=True)
            local_output.write_bytes(transcript_bytes)
            print(f"  💾 dumped to {local_output}（未上传 OSS）")
            return str(local_output)

        if bucket is not None:
            key = f"raw_podcasts/{podcast_id}/transcript.json"
            bucket.put_object(key, transcript_bytes, headers={"Content-Type": "application/json"})
            url = f"{OSS_CDN_DOMAIN}/{key}"
            print(f"  ☁️  transcript: {url}")
            return url

        return None


if __name__ == "__main__":
    # 命令行用法：
    #   python3 transcribe.py <media.mp4> <output.json> [meta_json]
    # 示例：
    #   python3 transcribe.py /tmp/veri.mp4 /tmp/out.json '{"speaker":"Veritasium","title":"...","topic":"科学"}'
    if len(sys.argv) < 3:
        print("Usage: python3 transcribe.py <media.mp4> <output.json> [meta_json]")
        sys.exit(1)
    media = Path(sys.argv[1])
    out = Path(sys.argv[2])
    meta = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    pid = meta.get("podcast_id") or "test_local"

    print(f"=== transcribe {media.name} → {out} ===")
    print(f"  meta: {meta}")
    result = generate_transcript(media, pid, podcast_meta=meta, local_output=out)
    if result:
        print(f"\n✓ 完成：{result}")
    else:
        print("\n✗ 失败")
        sys.exit(1)
