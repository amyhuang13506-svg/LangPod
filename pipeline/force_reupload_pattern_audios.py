"""Force-upload all pattern mp3s to OSS regardless of audio_url state.

Why: strip_pronunciation_explanation.py rewrites local mp3s but leaves
audio_url pointing to OSS (since that's how upload_episode left it). Then
upload_episode's skip-if-http logic skips re-uploading those mp3s, leaving
stale (un-stripped) audio on OSS. This script bypasses that skip.
"""

import glob
import json
import os
import sys

sys.path.insert(0, "/opt/langpod/pipeline")
from upload_oss import get_bucket

OUTPUT_ROOT = "/opt/langpod/pipeline/output"


def main():
    bucket = get_bucket()
    total = 0
    failures = 0

    for level in ["easy", "medium", "hard"]:
        for json_path in sorted(glob.glob(os.path.join(OUTPUT_ROOT, level, "ep-*.json"))):
            with open(json_path, "r", encoding="utf-8") as f:
                ep = json.load(f)
            patterns = ep.get("patterns") or []
            if not patterns:
                continue
            ep_id = ep["id"]
            for p in patterns:
                pattern_id = p["id"]
                local = os.path.join(OUTPUT_ROOT, level, "patterns", "%s.mp3" % pattern_id)
                if not os.path.exists(local):
                    print("   ⚠️  missing local mp3: %s" % local)
                    failures += 1
                    continue
                oss_key = "episodes/%s/%s/patterns/%s.mp3" % (level, ep_id, pattern_id)
                try:
                    bucket.put_object_from_file(oss_key, local)
                    total += 1
                    if total % 20 == 0:
                        print("   ... %d uploaded" % total)
                except Exception as e:
                    print("   ❌ upload failed for %s: %s" % (oss_key, e))
                    failures += 1

    print("\n✅ Force-uploaded %d pattern mp3s (%d failures)" % (total, failures))


if __name__ == "__main__":
    main()
