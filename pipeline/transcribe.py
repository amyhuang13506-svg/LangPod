"""
Pipeline A 字幕生成模块。
1. ffmpeg 把 mp4 的音轨抽成低采样率 mp3（Whisper API 上限 25MB，~1.5h 音频可装下）
2. OpenAI Whisper API 转写 → 段级时间戳
3. GPT 批量翻译每段 → 中文
4. 输出 transcript JSON（segments: [{start, end, en, zh}, ...]）
5. 上传 OSS at raw_podcasts/<id>/transcript.json

Whisper API 走 GPT_API_ENDPOINT (api.v3.cm) 同账号 key，价格 ~$0.006/min。
3 集（30+65+90 min）合计 ~$1.10。
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

import requests

from config import (
    GPT_API_KEY,
    GPT_MODEL,
    OSS_CDN_DOMAIN,
)

# api.v3.cm 是 GPT 代理，但他们的 audio/transcriptions endpoint 是 OpenAI 兼容
# OpenAI 直接调用：https://api.openai.com/v1/audio/transcriptions
# 我们用代理：在 api.v3.cm/v1/audio/transcriptions
# (如果代理不支持 audio，回退到 OpenAI 直连，需要单独 key)
WHISPER_API_ENDPOINT = "https://api.v3.cm/v1/audio/transcriptions"
GPT_CHAT_ENDPOINT = "https://api.v3.cm/v1/chat/completions"
WHISPER_MODEL = "whisper-1"

# Whisper API 文件大小上限（25 MB），加点缓冲到 24 MB
MAX_WHISPER_FILE_BYTES = 24 * 1024 * 1024


def extract_audio_for_transcription(media_path: Path, out_path: Path) -> bool:
    """ffmpeg 抽音轨：16 kHz mono mp3 64 kbps（Whisper 推荐配置，文件极小）。
    1.5 小时音频约 ~40MB 64kbps，需要更激进压缩到 32kbps 才能装下 25MB 上限。"""
    cmd = [
        "ffmpeg", "-y", "-i", str(media_path),
        "-vn",
        "-ac", "1",
        "-ar", "16000",
        "-b:a", "32k",
        "-acodec", "mp3",
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


def get_audio_duration(audio_path: Path) -> float:
    """ffprobe 拿音频时长（秒）。"""
    cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration",
           "-of", "default=noprint_wrappers=1:nokey=1", str(audio_path)]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=30)
        return float(r.stdout.decode().strip())
    except Exception:
        return 0.0


def split_audio(audio_path: Path, chunk_seconds: int, out_dir: Path) -> list[tuple[Path, float]]:
    """ffmpeg 切 audio。返回 [(chunk_path, start_offset_seconds), ...]。
    chunk_seconds 默认 30min（api.v3.cm Whisper 限制 1hr，30min 留充足缓冲）。"""
    duration = get_audio_duration(audio_path)
    if duration <= chunk_seconds:
        return [(audio_path, 0.0)]
    chunks = []
    start = 0.0
    idx = 0
    while start < duration:
        out = out_dir / f"chunk_{idx:03d}.mp3"
        cmd = [
            "ffmpeg", "-y", "-i", str(audio_path),
            "-ss", str(start),
            "-t", str(chunk_seconds),
            "-acodec", "copy",
            str(out),
        ]
        result = subprocess.run(cmd, capture_output=True, timeout=120)
        if result.returncode == 0 and out.exists():
            chunks.append((out, start))
        else:
            print(f"  ⚠️  chunk {idx} 切片失败: {result.stderr.decode()[:200]}")
        start += chunk_seconds
        idx += 1
    return chunks


_LOCAL_WHISPER_MODEL = None


def _get_local_whisper(model_name: str = "base"):
    """懒加载 whisper 模型。base = 74M params，英文 keynote 准确度足够。
    更高准确度可换 small (244M) / medium (769M)，但速度变慢。"""
    global _LOCAL_WHISPER_MODEL
    if _LOCAL_WHISPER_MODEL is None:
        import whisper as _whisper
        print(f"  · 加载 whisper 模型 ({model_name})…")
        _LOCAL_WHISPER_MODEL = _whisper.load_model(model_name)
    return _LOCAL_WHISPER_MODEL


def transcribe_with_whisper(audio_path: Path) -> Optional[list[dict]]:
    """本地 whisper 转写。Apple Silicon 上 base 模型大概 5x 实时（30 min 音频
    跑 6 min 左右）。返回段级时间戳列表。
    服务端用同样代码（CPU 慢些但 5min 音频也就 ~3min）。"""
    duration = get_audio_duration(audio_path)
    print(f"  → 本地 Whisper 转写：{duration / 60:.1f}min")

    try:
        model = _get_local_whisper("base")
        result = model.transcribe(
            str(audio_path),
            language="en",
            verbose=False,
            fp16=False,  # macOS CPU 模式
        )
    except Exception as e:
        print(f"  ✗ whisper 异常：{e}")
        return None

    segments = result.get("segments", [])
    out = []
    for s in segments:
        text = (s.get("text") or "").strip()
        if not text:
            continue
        out.append({
            "start": round(s["start"], 2),
            "end":   round(s["end"], 2),
            "en":    text,
        })
    print(f"  ✓ Whisper 出 {len(out)} 段")
    return out


def translate_segments_to_zh(segments: list[dict]) -> list[dict]:
    """批量调 GPT 翻译。学习目的：直译为主，让中文逐句逐短语对齐英文。"""
    BATCH = 50
    all_with_zh = []
    for i in range(0, len(segments), BATCH):
        chunk = segments[i:i + BATCH]
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
            "7. Avoid Chinese idioms / 成语 unless the English uses an idiom too.\n\n"
            "Output STRICT JSON array, same length and order as input.\n\n"
            "Input lines:\n" + "\n".join(en_lines) + "\n\n"
            'Output: {"translations": ["zh line 0", "zh line 1", ...]}'
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
                # fallback：原样保留无中文
                for s in chunk:
                    all_with_zh.append({**s, "zh": ""})
                continue
            content = r.json()["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            zh_list = parsed.get("translations", [])
            for j, s in enumerate(chunk):
                zh = zh_list[j] if j < len(zh_list) else ""
                all_with_zh.append({**s, "zh": zh})
            print(f"    · 翻译进度 {i + len(chunk)}/{len(segments)}")
        except Exception as e:
            print(f"  ⚠️  GPT translate error: {e}")
            for s in chunk:
                all_with_zh.append({**s, "zh": ""})
    return all_with_zh


def generate_transcript(media_path: Path, podcast_id: str, bucket=None) -> Optional[str]:
    """整合：抽音轨 → Whisper → 翻译 → 上传 OSS。返回 transcript_url 或 None。"""
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tf:
        audio_path = Path(tf.name)
    try:
        if not extract_audio_for_transcription(media_path, audio_path):
            return None

        segments_en = transcribe_with_whisper(audio_path)
        if not segments_en:
            return None

        segments_zh = translate_segments_to_zh(segments_en)

        transcript = {
            "podcast_id": podcast_id,
            "segments": segments_zh,
        }
        transcript_bytes = json.dumps(transcript, ensure_ascii=False, indent=2).encode("utf-8")

        if bucket is not None:
            key = f"raw_podcasts/{podcast_id}/transcript.json"
            bucket.put_object(key, transcript_bytes, headers={"Content-Type": "application/json"})
            url = f"{OSS_CDN_DOMAIN}/{key}"
            print(f"  ☁️  transcript: {url}")
            return url
        return None
    finally:
        audio_path.unlink(missing_ok=True)


if __name__ == "__main__":
    # 用法：python3 transcribe.py <media.mp4> <podcast_id>
    if len(sys.argv) < 3:
        print("Usage: python3 transcribe.py <media.mp4> <podcast_id>")
        sys.exit(1)
    media = Path(sys.argv[1])
    pid = sys.argv[2]
    from raw_podcast_processor import get_bucket
    url = generate_transcript(media, pid, get_bucket())
    print("transcript URL:", url)
