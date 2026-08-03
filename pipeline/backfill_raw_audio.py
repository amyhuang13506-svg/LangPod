#!/usr/bin/env python3
"""
存量原声视频批量抽音轨：mp4 → m4a（acodec copy，不转码）。

背景（2026-08-03 成本止血）：raw_podcasts 的 321 个 mp4 平均 118MB，App 听的
场景却在为视频字节付流量。新内容由 raw_podcast_processor 自动产 m4a，本脚本
给存量补齐，并把 master 里每条的 `audio_only_url` 填上。

跑法（在阿里云 ECS 上，走内网 endpoint 下载不产生流量费）：
    python3 backfill_raw_audio.py            # 全量，跳过已有 m4a 的
    python3 backfill_raw_audio.py --limit 5  # 试跑 5 条

幂等：OSS 上已有 media.m4a 的条目只补 master 字段，不重复抽取。
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import oss2  # noqa: E402
from config import (  # noqa: E402
    OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, OSS_BUCKET_NAME, OSS_CDN_DOMAIN,
)
from raw_podcast_processor import OSS_MASTER_KEY  # noqa: E402

# ECS 与 OSS 同区（ap-southeast-1）：内网 endpoint 下载免流量费。
# 本机（Mac）调试时用 config 的公网 endpoint。
INTERNAL_ENDPOINT = "oss-ap-southeast-1-internal.aliyuncs.com"
PUBLIC_ENDPOINT = "oss-ap-southeast-1.aliyuncs.com"


def get_bucket() -> oss2.Bucket:
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    for endpoint in (INTERNAL_ENDPOINT, PUBLIC_ENDPOINT):
        bucket = oss2.Bucket(auth, endpoint, OSS_BUCKET_NAME, connect_timeout=5)
        try:
            bucket.get_bucket_info()
            print(f"[backfill] endpoint: {endpoint}")
            return bucket
        except Exception:
            continue
    raise RuntimeError("no reachable OSS endpoint")


def extract_and_upload(bucket: oss2.Bucket, entry: dict) -> str | None:
    """Returns the m4a URL, or None on failure."""
    cid = entry["id"]
    m4a_key = f"raw_podcasts/{cid}/media.m4a"
    m4a_url = f"{OSS_CDN_DOMAIN}/{m4a_key}"

    if bucket.object_exists(m4a_key):
        print(f"   ✓ m4a 已存在，只补字段")
        return m4a_url

    # 找源 mp4（少数条目扩展名可能不是 mp4）
    src_key = None
    for ext in ("mp4", "m4v", "webm", "mov"):
        k = f"raw_podcasts/{cid}/media.{ext}"
        if bucket.object_exists(k):
            src_key = k
            break
    if not src_key:
        print(f"   ✗ 找不到源媒体文件")
        return None

    with tempfile.TemporaryDirectory() as tmp:
        src_local = Path(tmp) / Path(src_key).name
        m4a_local = Path(tmp) / "media.m4a"
        bucket.get_object_to_file(src_key, str(src_local))
        try:
            subprocess.run(
                ["ffmpeg", "-y", "-i", str(src_local), "-vn",
                 "-acodec", "copy", str(m4a_local)],
                check=True, capture_output=True, timeout=600,
            )
        except subprocess.CalledProcessError:
            # webm 等源的音轨可能不是 AAC，copy 进 m4a 容器会失败 → 转码兜底
            subprocess.run(
                ["ffmpeg", "-y", "-i", str(src_local), "-vn",
                 "-c:a", "aac", "-b:a", "64k", str(m4a_local)],
                check=True, capture_output=True, timeout=1800,
            )
        size_mb = m4a_local.stat().st_size / 1024 / 1024
        bucket.put_object(m4a_key, m4a_local.read_bytes(),
                          headers={"Content-Type": "audio/mp4"})
        print(f"   ☁️  {size_mb:.1f}MB → {m4a_key}")
    return m4a_url


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--limit", type=int, default=0, help="只处理前 N 条（试跑用）")
    args = p.parse_args()

    bucket = get_bucket()
    master = json.loads(bucket.get_object(OSS_MASTER_KEY).read())
    print(f"[backfill] master {len(master)} 条")

    todo = [e for e in master if e.get("has_video") and not e.get("audio_only_url")]
    # 无视频轨的（RSS mp3 等）直接把现有 audio_url 补进字段
    for e in master:
        if not e.get("has_video") and not e.get("audio_only_url") and e.get("audio_url"):
            e["audio_only_url"] = e["audio_url"]

    if args.limit:
        todo = todo[: args.limit]
    print(f"[backfill] 待抽取 {len(todo)} 条")

    done = failed = 0
    for i, entry in enumerate(todo, 1):
        print(f"\n[{i}/{len(todo)}] {entry['id']} — {entry['title'][:50]}")
        try:
            url = extract_and_upload(bucket, entry)
        except Exception as e:
            print(f"   ✗ {e}")
            url = None
        if url:
            entry["audio_only_url"] = url
            done += 1
        else:
            failed += 1
        # 每 10 条保存一次 master，中断可续跑
        if i % 10 == 0 or i == len(todo):
            bucket.put_object(
                OSS_MASTER_KEY,
                json.dumps(master, ensure_ascii=False, indent=1).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            print(f"   💾 master 已保存（{done} 成功 / {failed} 失败）")

    # 收尾保存（覆盖 todo 为空、或最后一批不满 10 条已在循环里存过的情况——幂等）
    bucket.put_object(
        OSS_MASTER_KEY,
        json.dumps(master, ensure_ascii=False, indent=1).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    print(f"\n[backfill] 完成：{done} 成功，{failed} 失败")


if __name__ == "__main__":
    main()
