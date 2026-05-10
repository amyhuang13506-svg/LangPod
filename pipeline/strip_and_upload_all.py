"""End-to-end: backup current pattern mp3s + episode JSONs, run strip across
all 3 levels, re-upload affected episodes to OSS, refresh per-level indexes.

Designed to run on the server.
"""

import json
import os
import subprocess
import sys
import time

sys.path.insert(0, "/opt/langpod/pipeline")

from strip_pronunciation_explanation import collect_episode_paths, process_episode
from upload_oss import get_bucket, upload_episode, update_episode_list


BACKUP_DIR = "/opt/langpod/pipeline/backups"
OUTPUT_ROOT = "/opt/langpod/pipeline/output"


def backup():
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    backup_path = os.path.join(BACKUP_DIR, "patterns_pre_strip_%s.tar.gz" % ts)
    print("📦 Backing up to %s ..." % backup_path)
    cmd = ["tar", "-czf", backup_path, "-C", OUTPUT_ROOT]
    for level in ["easy", "medium", "hard"]:
        cmd += ["%s/patterns" % level]
        # Also back up episode JSONs (they're in <level>/*.json)
        for f in sorted(os.listdir(os.path.join(OUTPUT_ROOT, level))):
            if f.startswith("ep-") and f.endswith(".json"):
                cmd += ["%s/%s" % (level, f)]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print("   ❌ backup failed: %s" % result.stderr.decode()[:300])
        sys.exit(1)
    size_mb = os.path.getsize(backup_path) / 1024.0 / 1024.0
    print("   ✅ %.1f MB" % size_mb)
    return backup_path


def main():
    backup_path = backup()
    print()

    print("✂️  Stripping pronunciation explanation across all levels...")
    eps = collect_episode_paths()
    affected = []
    for level, path in eps:
        result = process_episode(level, path, dry_run=False)
        if result and result["changes"]:
            affected.append((level, result["episode_id"], path))

    print("\n   %d episodes modified" % len(affected))

    if not affected:
        print("Nothing to upload. Done.")
        return

    print("\n☁️  Re-uploading affected episodes to OSS...")
    bucket = get_bucket()
    levels_touched = set()
    for i, (level, ep_id, path) in enumerate(affected, 1):
        levels_touched.add(level)
        print("   [%d/%d] %s" % (i, len(affected), ep_id))
        try:
            upload_episode(bucket, path, level)
        except Exception as e:
            print("      ❌ upload failed: %s" % e)

    print("\n📋 Refreshing level indexes...")
    for level in sorted(levels_touched):
        try:
            update_episode_list(bucket, level)
            print("   ✅ %s index refreshed" % level)
        except Exception as e:
            print("   ❌ %s index refresh failed: %s" % (level, e))

    print("\n🎉 Done. Backup at: %s" % backup_path)


if __name__ == "__main__":
    main()
