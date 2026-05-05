"""
按静音点切片音频，给 Whisper 转写并行用。

- 用 ffmpeg silencedetect 找音频里 ≥0.5s、强度 ≤-30dB 的静音段
- 贪心规划：每片目标 ~8 分钟，在 [4min, 12min] 区间内挑最长静音切
- 找不到合适静音点 → 放宽阈值再扫；仍无 → 硬切（接受 1-2 词损失）
- 输出 64kbps mono mp3，每片远小于 25MB 的 Whisper 限制

设计取舍：
- 用 ffmpeg 而不是 pydub，避免把整段音频加载进内存（服务器 1.6GB RAM 紧）
- 切片时 mp3 重新编码（不用 -c copy），避免 mp3 帧不齐导致 Whisper 解码异常
"""
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

TARGET_CHUNK_SECONDS = 480       # 8min
MIN_CHUNK_SECONDS = 240          # 不低于 4min（小段 Whisper 上下文不足）
MAX_CHUNK_SECONDS = 720          # 12min，找不到静音的硬切上限
SILENCE_DB = "-30dB"
SILENCE_MIN_LEN = 0.5

# 第二次扫描的放宽阈值
RELAXED_DB = "-25dB"
RELAXED_MIN_LEN = 0.3


def _ffmpeg_silencedetect(audio_path: Path, db: str, min_len: float) -> list[tuple[float, float]]:
    """跑 ffmpeg silencedetect，解析 stderr 拿静音段。
    返回 [(silence_mid_time, duration), ...]，按 mid 排序。
    """
    cmd = [
        "ffmpeg", "-hide_banner", "-nostats", "-i", str(audio_path),
        "-af", f"silencedetect=n={db}:d={min_len}",
        "-f", "null", "-",
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=300)
    except subprocess.TimeoutExpired:
        print(f"  ⚠️  silencedetect 超时（>5min）")
        return []
    stderr = r.stderr.decode("utf-8", errors="ignore")

    # 配对 silence_start / silence_end 行
    starts = [float(m.group(1)) for m in re.finditer(r"silence_start: ([\d.]+)", stderr)]
    ends_dur = [(float(m.group(1)), float(m.group(2)))
                for m in re.finditer(r"silence_end: ([\d.]+) \| silence_duration: ([\d.]+)", stderr)]

    out = []
    for i, (end, dur) in enumerate(ends_dur):
        if i < len(starts):
            mid = (starts[i] + end) / 2
            out.append((mid, dur))
    out.sort(key=lambda x: x[0])
    return out


def _get_audio_duration(audio_path: Path) -> float:
    cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration",
           "-of", "default=noprint_wrappers=1:nokey=1", str(audio_path)]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=30)
        return float(r.stdout.decode().strip())
    except Exception:
        return 0.0


def detect_silences(audio_path: Path) -> list[tuple[float, float]]:
    """两阶段：先严格 -30dB/0.5s 找静音，找到的太少就放宽阈值再扫。"""
    silences = _ffmpeg_silencedetect(audio_path, SILENCE_DB, SILENCE_MIN_LEN)
    duration = _get_audio_duration(audio_path)

    # 启发式：每 4-12min 至少要有一个静音点；总数 < duration/600 就放宽
    expected = max(1, int(duration / 600))
    if len(silences) < expected:
        relaxed = _ffmpeg_silencedetect(audio_path, RELAXED_DB, RELAXED_MIN_LEN)
        if len(relaxed) > len(silences):
            silences = relaxed
            print(f"  · 放宽到 {RELAXED_DB}/{RELAXED_MIN_LEN}s 找到 {len(silences)} 个静音点")
    return silences


def plan_chunks(duration: float, silences: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """规划切点。返回 [(start_sec, end_sec), ...] 覆盖整段。

    贪心：从 t=0 起，目标下一刀在 t+TARGET（480s）。
    在 [t+MIN_CHUNK, t+MAX_CHUNK] 范围内挑 duration 最长的静音点的 mid。
    没合适静音 → 在 t+TARGET 硬切。
    """
    chunks: list[tuple[float, float]] = []
    cursor = 0.0

    while cursor < duration:
        target = cursor + TARGET_CHUNK_SECONDS
        window_lo = cursor + MIN_CHUNK_SECONDS
        window_hi = cursor + MAX_CHUNK_SECONDS

        # 剩余太短，直接收尾
        if duration - cursor <= MAX_CHUNK_SECONDS:
            chunks.append((cursor, duration))
            break

        # 在 [window_lo, window_hi] 内挑最长静音
        candidates = [(mid, dur) for mid, dur in silences if window_lo <= mid <= window_hi]
        if candidates:
            # 优先离 target 近的长静音；用 dur 大优先
            candidates.sort(key=lambda x: (-x[1], abs(x[0] - target)))
            cut = candidates[0][0]
        else:
            # 硬切
            cut = target
            print(f"  · {cursor:.0f}s 起这段没找到合适静音，硬切于 {cut:.0f}s")

        chunks.append((cursor, cut))
        cursor = cut

    return chunks


def chunk_audio_by_silence(
    audio_path: Path,
    out_dir: Path,
    bitrate: str = "64k",
) -> list[tuple[Path, float]]:
    """主入口：找静音 → 规划 → 用 ffmpeg 切片输出 mp3。
    返回 [(chunk_path, chunk_offset_seconds), ...]。
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    duration = _get_audio_duration(audio_path)
    if duration <= 0:
        print(f"  ✗ 无法读取音频时长：{audio_path}")
        return []

    silences = detect_silences(audio_path)
    print(f"  · 检测到 {len(silences)} 个静音点（音频时长 {duration:.0f}s）")

    plan = plan_chunks(duration, silences)
    print(f"  · 规划 {len(plan)} 个切片：" +
          ", ".join(f"{int(s)}-{int(e)}s" for s, e in plan))

    chunks: list[tuple[Path, float]] = []
    for i, (start, end) in enumerate(plan):
        chunk_path = out_dir / f"chunk_{i:03d}.mp3"
        cmd = [
            "ffmpeg", "-y", "-i", str(audio_path),
            "-ss", f"{start:.3f}",
            "-t", f"{end - start:.3f}",
            "-vn", "-ac", "1", "-ar", "16000", "-b:a", bitrate,
            "-acodec", "libmp3lame",
            str(chunk_path),
        ]
        r = subprocess.run(cmd, capture_output=True, timeout=300)
        if r.returncode != 0 or not chunk_path.exists():
            print(f"  ✗ 切片 {i} 失败：{r.stderr.decode()[:200]}")
            continue
        chunks.append((chunk_path, start))

    return chunks


if __name__ == "__main__":
    # python3 silence_chunker.py <audio.mp3> [out_dir]
    if len(sys.argv) < 2:
        print("Usage: python3 silence_chunker.py <audio.mp3> [out_dir]")
        sys.exit(1)
    audio = Path(sys.argv[1])
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/chunks_out")
    out_dir.mkdir(parents=True, exist_ok=True)
    chunks = chunk_audio_by_silence(audio, out_dir)
    print(f"\n✓ {len(chunks)} chunks:")
    for path, off in chunks:
        size_mb = path.stat().st_size / 1024 / 1024
        print(f"  {off:7.1f}s 起  {size_mb:5.2f}MB  {path.name}")
