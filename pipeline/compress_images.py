#!/usr/bin/env python3
"""
存量封面/场景图批量压缩（2026-08-22 成本止血二期）。

背景：CDN 一天 7.7GB 流量是 jpg —— lessons 封面/场景图是 DALL-E 原图直传
（平均 1.8MB），episodes 封面平均 581KB，而 App 展示尺寸远小于原图。
本脚本把大图重采样 + 重编码后原路覆盖，所有版本 App（含老版本直连）即刻受益。

规则（按 key 分类，长边上限 / JPEG 质量）：
    lessons/**/cover.jpg   → 640px  q80   （列表小卡）
    lessons/**/*.jpg 其他  → 1024px q80   （全屏场景热点图，保清晰度）
    episodes/**/cover.jpg  → 900px  q80   （播放页大图 ~300pt@3x）
    其余（expressions/raw thumbnail）→ 不动（已经很小）

安全：
  - 覆盖前先 server-side copy 备份到 backup/img_orig_20260822/<key>（免流量）
  - 备份已存在则不重复备份（幂等；重跑不会用压缩图覆盖真原图）
  - 新图必须比原图小 ≥20% 才覆盖，否则跳过
  - 只处理 > 250KB 的 jpg

跑法（阿里云 ECS，内网 endpoint 零流量费）：
    python3 compress_images.py --dry-run          # 只统计不动数据
    python3 compress_images.py --limit 5          # 试跑 5 张
    python3 compress_images.py                    # 全量
"""
from __future__ import annotations

import argparse
import io
import posixpath
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import oss2  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

from config import OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, OSS_BUCKET_NAME  # noqa: E402

INTERNAL_ENDPOINT = "oss-ap-southeast-1-internal.aliyuncs.com"
PUBLIC_ENDPOINT = "oss-ap-southeast-1.aliyuncs.com"

BACKUP_PREFIX = "backup/img_orig_20260822/"
MIN_SIZE = 250 * 1024        # 只碰 >250KB 的
MIN_SAVING_RATIO = 0.8       # 新图必须 ≤ 原图 80% 才覆盖
JPEG_QUALITY = 80


def get_bucket() -> oss2.Bucket:
    auth = oss2.Auth(OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET)
    for endpoint in (INTERNAL_ENDPOINT, PUBLIC_ENDPOINT):
        bucket = oss2.Bucket(auth, endpoint, OSS_BUCKET_NAME)
        try:
            bucket.get_bucket_info()
            return bucket
        except Exception:
            continue
    raise RuntimeError("cannot reach OSS via internal or public endpoint")


def max_dim_for(key: str) -> int | None:
    """返回该 key 的长边上限；None = 不处理。"""
    name = posixpath.basename(key).lower()
    if key.startswith("lessons/"):
        return 640 if name == "cover.jpg" else 1024
    if key.startswith("episodes/") and name == "cover.jpg":
        return 900
    return None


def compress(data: bytes, max_dim: int) -> bytes | None:
    try:
        img = Image.open(io.BytesIO(data))
        img = ImageOps.exif_transpose(img)
    except Exception:
        return None
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    w, h = img.size
    scale = max_dim / max(w, h)
    if scale < 1.0:
        img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    return out.getvalue()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    bucket = get_bucket()
    done = skipped = errors = 0
    bytes_before = bytes_after = 0

    for obj in oss2.ObjectIterator(bucket):
        key = obj.key
        if not key.lower().endswith((".jpg", ".jpeg")):
            continue
        if key.startswith((BACKUP_PREFIX, "logs/")):
            continue
        max_dim = max_dim_for(key)
        if max_dim is None or obj.size <= MIN_SIZE:
            continue
        if args.limit and done >= args.limit:
            break

        if args.dry_run:
            print(f"[dry] {key} ({obj.size/1e6:.2f} MB) → max {max_dim}px")
            done += 1
            bytes_before += obj.size
            continue

        try:
            backup_key = BACKUP_PREFIX + key
            if not bucket.object_exists(backup_key):
                bucket.copy_object(OSS_BUCKET_NAME, key, backup_key)

            data = bucket.get_object(key).read()
            new_data = compress(data, max_dim)
            if new_data is None:
                print(f"[err ] {key}: decode failed")
                errors += 1
                continue
            if len(new_data) > len(data) * MIN_SAVING_RATIO:
                print(f"[skip] {key}: saving too small ({len(data)} → {len(new_data)})")
                skipped += 1
                continue

            bucket.put_object(key, new_data, headers={
                "Content-Type": "image/jpeg",
                "Cache-Control": "public, max-age=2592000",
            })
            bytes_before += len(data)
            bytes_after += len(new_data)
            done += 1
            print(f"[ok  ] {key}: {len(data)/1e6:.2f} MB → {len(new_data)/1e6:.2f} MB")
        except Exception as e:  # noqa: BLE001
            errors += 1
            print(f"[err ] {key}: {e}")

    print(f"\ndone={done} skipped={skipped} errors={errors}")
    if bytes_before:
        print(f"total: {bytes_before/1e6:.0f} MB → {bytes_after/1e6:.0f} MB "
              f"(-{(1 - bytes_after/max(bytes_before,1)) * 100:.0f}%)")


if __name__ == "__main__":
    main()
