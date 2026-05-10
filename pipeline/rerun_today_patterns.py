"""Re-extract patterns (with new MiniMax code) for today's episodes and re-upload to OSS.

Usage:
    python3 rerun_today_patterns.py 20260510
"""
import os
import sys

sys.path.insert(0, "/opt/langpod/pipeline")

from extract_patterns import (
    process_episode as process_patterns,
    load_pattern_manifest,
    save_pattern_manifest,
)
from upload_oss import get_bucket, upload_episode, update_episode_list


def main():
    date_compact = sys.argv[1] if len(sys.argv) > 1 else "20260510"
    levels = ["easy", "medium", "hard"]

    manifest = load_pattern_manifest()
    bucket = get_bucket()

    for level in levels:
        level_dir = "/opt/langpod/pipeline/output/%s" % level
        prefix = "ep-%s-%s-" % (date_compact, level)
        eps = sorted(
            f for f in os.listdir(level_dir)
            if f.startswith(prefix) and f.endswith(".json")
        )
        print("\n========== %s (%d eps) ==========" % (level, len(eps)))
        for ep_file in eps:
            ep_path = os.path.join(level_dir, ep_file)
            print("\n>>> %s" % ep_file)
            ok = process_patterns(ep_path, manifest, force=True)
            if ok:
                save_pattern_manifest(manifest)
                print("   uploading to OSS...")
                upload_episode(bucket, ep_path, level)
            else:
                print("   pattern extraction skipped/failed for %s" % ep_file)
        try:
            update_episode_list(bucket, level)
            print("   index refreshed for %s" % level)
        except Exception as e:
            print("   index refresh failed for %s: %s" % (level, e))

    print("\nDone")


if __name__ == "__main__":
    main()
