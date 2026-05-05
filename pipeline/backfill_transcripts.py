"""
一次性脚本：用 v2 pipeline 重跑 OSS master 上的老 raw_podcast transcript。

v2 transcript 特征：每个 segment 带 `words` 数组（词级时间戳）。
脚本默认跳过已有 v2 transcript 的条目。

用法：
    python3 backfill_transcripts.py --dry-run         # 估配额 / 时间，不实跑
    python3 backfill_transcripts.py --id raw-yt-XXX   # 单条
    python3 backfill_transcripts.py --all             # 全跑（默认 skip-existing）
    python3 backfill_transcripts.py --all --force     # 强制覆盖已有 v2

跑完顺便重新生成 words.json 给 App 点词查询用。
"""
import argparse
import json
import sys
import tempfile
from pathlib import Path
from typing import Optional

import requests

from raw_podcast_processor import get_bucket, OSS_MASTER_KEY, OSS_CDN_DOMAIN
from transcribe import generate_transcript


def has_v2_transcript(bucket, podcast_id: str) -> bool:
    """v2 = transcript.json 里 segments[0] 有 words 字段"""
    key = f"raw_podcasts/{podcast_id}/transcript.json"
    try:
        data = bucket.get_object(key).read()
        obj = json.loads(data)
        segs = obj.get("segments") or []
        if not segs:
            return False
        return "words" in segs[0]
    except Exception:
        return False


def download_media(podcast_id: str, dst: Path) -> bool:
    """从 OSS 下 media.mp4 / media.mp3 到本地"""
    for ext in ("mp4", "mp3", "m4a"):
        url = f"{OSS_CDN_DOMAIN}/raw_podcasts/{podcast_id}/media.{ext}"
        try:
            r = requests.get(url, stream=True, timeout=300, allow_redirects=True)
            if r.status_code == 200:
                with dst.open("wb") as f:
                    for chunk in r.iter_content(chunk_size=8192):
                        f.write(chunk)
                if dst.stat().st_size > 0:
                    return True
        except Exception:
            continue
    return False


def backfill_one(item: dict, bucket, force: bool, skip_words: bool = False, skip_translate: bool = False) -> bool:
    """处理单条 master entry。返回 True 成功 / False 跳过或失败"""
    pid = item["id"]
    if not force and has_v2_transcript(bucket, pid):
        print(f"  ⏭  {pid} 已有 v2 transcript，跳过")
        return False

    print(f"\n=== {pid} | {item.get('title', '')[:60]} ===")

    podcast_meta = {
        "title": item.get("title", ""),
        "speaker": item.get("speaker", ""),
        "topic": item.get("topic", ""),
        "event": item.get("event") or item.get("speaker", ""),
    }

    with tempfile.TemporaryDirectory() as tmp:
        media_local = Path(tmp) / "media.mp4"
        if not download_media(pid, media_local):
            print(f"  ✗ {pid} OSS media 下载失败")
            return False
        size_mb = media_local.stat().st_size / 1024 / 1024
        print(f"  ✓ media {size_mb:.1f}MB")

        transcript_url = generate_transcript(
            media_local, pid, bucket=bucket, podcast_meta=podcast_meta,
            skip_translate=skip_translate,
        )
        if not transcript_url:
            print(f"  ✗ {pid} 转写失败")
            return False

    # 同步重新跑 words.json（基于新 transcript）—— --no-words 时跳过
    if skip_words:
        print(f"  ⏭  跳过 words.json 生成 (--no-words)")
    else:
        try:
            from pretranslate_words import pretranslate_for_podcast
            pretranslate_for_podcast(pid, bucket)
        except Exception as e:
            print(f"  ⚠️  {pid} pretranslate 失败（不阻塞）：{e}")

    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="跑全部 master entries")
    parser.add_argument("--id", help="跑单条 podcast_id")
    parser.add_argument("--dry-run", action="store_true", help="估配额，不实跑")
    parser.add_argument("--force", action="store_true", help="强制覆盖已有 v2")
    parser.add_argument("--no-words", action="store_true", help="跳过 words.json 生成（测试时用，省 GPT 钱 + 时间）")
    parser.add_argument("--no-translate", action="store_true", help="跳过中文翻译（最快验证字幕，zh 字段留空）")
    args = parser.parse_args()

    if not args.all and not args.id:
        print("Usage: --all 或 --id <pid>")
        sys.exit(1)

    bucket = get_bucket()
    master_data = bucket.get_object(OSS_MASTER_KEY).read()
    master = json.loads(master_data)
    print(f"OSS master: {len(master)} 条")

    if args.id:
        targets = [m for m in master if m["id"] == args.id]
        if not targets:
            print(f"✗ {args.id} 不在 master 里")
            sys.exit(1)
    else:
        targets = master

    # 过滤已有 v2（除非 --force）
    if not args.force:
        filtered = []
        for t in targets:
            if has_v2_transcript(bucket, t["id"]):
                print(f"  ⏭  {t['id']} 已 v2，跳过")
                continue
            filtered.append(t)
        targets = filtered

    total_sec = sum(t.get("duration_seconds", 0) for t in targets)
    print(f"\n→ 待处理 {len(targets)} 条 / 总时长 {total_sec / 60:.0f}min ({total_sec / 3600:.1f}h)")
    print(f"  Groq 免费层日上限 28800s = 8h；预计需要 {total_sec / 28800:.1f} 天配额")

    if args.dry_run:
        print("\n  (dry-run 模式，未实际处理)")
        for t in targets:
            print(f"    · {t['id']:30}  {t.get('duration_seconds', 0) / 60:5.1f}min  {t.get('title', '')[:50]}")
        return

    print("\n开始处理...")
    ok, fail = 0, 0
    failures = []
    for i, t in enumerate(targets, 1):
        print(f"\n[{i}/{len(targets)}]", end="")
        try:
            if backfill_one(t, bucket, force=args.force, skip_words=args.no_words, skip_translate=args.no_translate):
                ok += 1
            else:
                fail += 1
                failures.append(t["id"])
        except Exception as e:
            print(f"  ✗ {t['id']} 异常: {e}")
            fail += 1
            failures.append(t["id"])

    print(f"\n\n=== 完成: ok={ok} / fail={fail} ===")
    if failures:
        out = Path(__file__).resolve().parent / "output" / "backfill_failures.json"
        out.parent.mkdir(exist_ok=True)
        out.write_text(json.dumps(failures, ensure_ascii=False, indent=2))
        print(f"  失败 ID 写入：{out}")


if __name__ == "__main__":
    main()
