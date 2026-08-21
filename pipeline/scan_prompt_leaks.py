"""
一次性脚本：扫 OSS 上所有 raw_podcast transcript.json，
用新的 PROMPT_LEAK_RE 规则删除 Whisper prompt 复读幻觉段。

幻觉模式：'I'm Dr. NVIDIA, Anthropic, Claude, GPT, AGI.' 这类裸列表，
Whisper 把 prompt 当上下文模板直接复读出来的产物。

只删段，不重转音频（删了的段无法重建原文，没字幕好过有错字幕）。

用法：
    python3 scan_prompt_leaks.py --dry-run         # 只统计，不写
    python3 scan_prompt_leaks.py                   # 实跑：有命中就重传
    python3 scan_prompt_leaks.py --id raw-yt-XXX   # 只扫单条
"""
import argparse
import json
import sys

from raw_podcast_processor import get_bucket, load_master
from transcript_cleaner import PROMPT_LEAK_RE


def scan_transcript(bucket, podcast_id: str, dry_run: bool) -> tuple[int, int, list[str]]:
    """处理单个 transcript。返回 (原段数, 删除数, 命中样例 ≤3 条)"""
    key = f"raw_podcasts/{podcast_id}/transcript.json"
    try:
        data = bucket.get_object(key).read()
    except Exception as e:
        msg = str(e)
        # 不存在的 transcript 静默跳过
        if "NoSuchKey" in msg or "404" in msg:
            return (0, 0, [])
        print(f"  ✗ {podcast_id}: 拉取失败 {msg[:120]}")
        return (0, 0, [])

    try:
        obj = json.loads(data)
    except Exception as e:
        print(f"  ✗ {podcast_id}: JSON 解析失败 {e}")
        return (0, 0, [])

    segments = obj.get("segments") or []
    if not segments:
        return (0, 0, [])

    kept = []
    samples: list[str] = []
    for s in segments:
        en = s.get("en") or ""
        if PROMPT_LEAK_RE.search(en):
            if len(samples) < 3:
                samples.append(en[:100])
            continue
        kept.append(s)

    dropped = len(segments) - len(kept)
    if dropped == 0:
        return (len(segments), 0, [])

    if not dry_run:
        obj["segments"] = kept
        new_bytes = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        try:
            bucket.put_object(key, new_bytes, headers={"Content-Type": "application/json"})
        except Exception as e:
            print(f"  ✗ {podcast_id}: 重传失败 {e}")
            return (len(segments), 0, samples)

    return (len(segments), dropped, samples)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只统计，不重传")
    ap.add_argument("--id", help="只扫单条 podcast_id")
    args = ap.parse_args()

    bucket = get_bucket()
    master = load_master(bucket=bucket)
    if args.id:
        master = [m for m in master if m.get("id") == args.id]
        if not master:
            print(f"未找到 podcast_id={args.id}")
            sys.exit(1)

    mode = "dry-run（只统计）" if args.dry_run else "实跑（命中将重传）"
    print(f"=== 扫描 {len(master)} 个 transcript · {mode} ===\n")

    total_segs = 0
    total_dropped = 0
    affected = 0
    affected_ids: list[str] = []

    for i, m in enumerate(master, 1):
        pid = m.get("id")
        if not pid:
            continue
        n_segs, n_dropped, samples = scan_transcript(bucket, pid, args.dry_run)
        total_segs += n_segs
        total_dropped += n_dropped
        if n_dropped > 0:
            affected += 1
            affected_ids.append(pid)
            verb = "将删" if args.dry_run else "已删"
            title = (m.get("title") or "")[:50]
            print(f"[{i}/{len(master)}] {pid} ({title})")
            print(f"    {verb} {n_dropped}/{n_segs} 段")
            for s in samples:
                print(f"    · \"{s}\"")

    print(f"\n=== 汇总 ===")
    print(f"  扫描总集数:  {len(master)}")
    print(f"  受影响集数:  {affected}")
    print(f"  总段数:      {total_segs}")
    print(f"  命中删除段:  {total_dropped}")
    if args.dry_run and affected > 0:
        print(f"\n  ⚠️  dry-run，未修改。去掉 --dry-run 实跑。")
    elif not args.dry_run and affected > 0:
        print(f"\n  ✓ 已重传 {affected} 个 transcript.json")


if __name__ == "__main__":
    main()
