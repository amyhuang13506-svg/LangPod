"""Surgically remove pronunciation_explanation_zh chunks from existing patterns.

For each pattern:
  1. Identify zh chunks in section "pronunciation" that appear AFTER the demo_en
     line — those are the explanation chunks we want to delete.
  2. Rebuild the mp3 by concatenating the remaining chunks with the original
     silence rhythm (silence_short / silence_section / silence_drill).
  3. Update explainer_script timestamps + pattern duration.
  4. Re-upload the mp3 + episode.json to OSS, then refresh the level index.

Modes:
  python3 strip_pronunciation_explanation.py            # all 3 levels
  python3 strip_pronunciation_explanation.py easy       # one level
  python3 strip_pronunciation_explanation.py easy ep-id # one episode
  python3 strip_pronunciation_explanation.py --dry-run  # report only
"""

import glob
import json
import os
import sys

from pydub import AudioSegment

# Match extract_patterns.py
WITHIN_SECTION_SILENCE_MS = 250
SECTION_SILENCE_MS = 400
DRILL_SILENCE_MS = 1200

OUTPUT_ROOT = "/opt/langpod/pipeline/output"


def find_local_audio_for_pattern(pattern, level, episode_id):
    """The pattern's audio_url may be an OSS https URL (post-upload) or a local
    path (pre-upload). Either way, the local mp3 lives at:
       <OUTPUT_ROOT>/<level>/patterns/<pattern_id>.mp3
    """
    pattern_id = pattern["id"]
    return os.path.join(OUTPUT_ROOT, level, "patterns", "%s.mp3" % pattern_id)


def strip_pattern(pattern, level, episode_id, dry_run=False):
    """Returns (changed_bool, removed_count, new_duration_or_none)."""
    lines = pattern.get("explainer_script", [])

    # Find demo_en line in pronunciation section
    demo_idx = None
    for i, ln in enumerate(lines):
        if ln.get("section") == "pronunciation" and ln.get("text_en"):
            demo_idx = i
            break
    if demo_idx is None:
        return False, 0, None

    # Mark zh chunks in pronunciation section AFTER demo for removal
    remove_idx = set()
    for i in range(demo_idx + 1, len(lines)):
        if lines[i].get("section") != "pronunciation":
            break
        if lines[i].get("text_zh"):
            remove_idx.add(i)

    if not remove_idx:
        return False, 0, None

    if dry_run:
        return True, len(remove_idx), None

    audio_path = find_local_audio_for_pattern(pattern, level, episode_id)
    if not os.path.exists(audio_path):
        print("   ⚠️  audio missing: %s" % audio_path)
        return False, 0, None

    try:
        orig = AudioSegment.from_mp3(audio_path)
    except Exception as e:
        print("   ⚠️  load failed (%s): %s" % (audio_path, e))
        return False, 0, None

    silence_short = AudioSegment.silent(duration=WITHIN_SECTION_SILENCE_MS)
    silence_section = AudioSegment.silent(duration=SECTION_SILENCE_MS)
    silence_drill = AudioSegment.silent(duration=DRILL_SILENCE_MS)

    new_audio = AudioSegment.empty()
    new_lines = []
    prev_section = None
    prev_was_drill_repeat = False

    for i, ln in enumerate(lines):
        if i in remove_idx:
            continue

        cur_section = ln["section"]
        cur_is_drill_repeat = (cur_section == "pronunciation_drill" and bool(ln.get("text_en")))

        # Insert silence BEFORE this chunk based on relationship with previous
        if prev_section is not None:
            if cur_section != prev_section:
                # Section transition: matches original (silence_short was already
                # appended after the previous section's last chunk, then
                # silence_section). To match original timing, we add both.
                new_audio += silence_short + silence_section
            elif prev_was_drill_repeat and cur_is_drill_repeat:
                # Between two drill repeats — drill silence (1200ms)
                new_audio += silence_drill
            elif prev_was_drill_repeat and not cur_is_drill_repeat:
                # After last drill repeat, transitioning within drill section
                # (rare — usually the last repeat is followed by section change).
                new_audio += silence_drill
            else:
                new_audio += silence_short

        chunk_start_ms = int(round(ln["start"] * 1000))
        chunk_end_ms = int(round(ln["end"] * 1000))
        chunk = orig[chunk_start_ms:chunk_end_ms]

        new_start = len(new_audio) / 1000.0
        new_audio += chunk
        new_end = len(new_audio) / 1000.0

        new_line = dict(ln)
        new_line["start"] = round(new_start, 3)
        new_line["end"] = round(new_end, 3)
        new_lines.append(new_line)

        prev_section = cur_section
        prev_was_drill_repeat = cur_is_drill_repeat

    # Rewrite mp3 in-place at same bitrate as original synthesis (128k)
    new_audio.export(audio_path, format="mp3", bitrate="128k")

    pattern["explainer_script"] = new_lines
    pattern["duration_seconds"] = int(round(len(new_audio) / 1000.0))

    return True, len(remove_idx), pattern["duration_seconds"]


def collect_episode_paths(level_filter=None, ep_filter=None):
    """Return list of (level, episode_json_path) pairs."""
    levels = [level_filter] if level_filter else ["easy", "medium", "hard"]
    out = []
    for level in levels:
        pattern = "ep-*.json"
        if ep_filter:
            pattern = "%s.json" % ep_filter
        for path in sorted(glob.glob(os.path.join(OUTPUT_ROOT, level, pattern))):
            out.append((level, path))
    return out


def process_episode(level, json_path, dry_run=False):
    with open(json_path, "r", encoding="utf-8") as f:
        ep = json.load(f)
    if not ep.get("patterns"):
        return None  # no patterns in this episode

    ep_id = ep["id"]
    changed_any = False
    summary = []
    for pat in ep["patterns"]:
        changed, removed, new_dur = strip_pattern(pat, level, ep_id, dry_run=dry_run)
        if changed:
            changed_any = True
            summary.append({
                "pattern_id": pat["id"],
                "template": pat["template"][:50],
                "removed": removed,
                "new_duration": new_dur,
            })

    if changed_any and not dry_run:
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(ep, f, ensure_ascii=False, indent=2)

    return {"episode_id": ep_id, "changes": summary, "json_path": json_path}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry_run = "--dry-run" in sys.argv

    level_filter = args[0] if args else None
    ep_filter = args[1] if len(args) > 1 else None

    eps = collect_episode_paths(level_filter, ep_filter)
    print("Scanning %d episodes (dry_run=%s)" % (len(eps), dry_run))

    grand_eps_changed = 0
    grand_chunks = 0
    grand_patterns_changed = 0
    affected = []

    for level, path in eps:
        result = process_episode(level, path, dry_run=dry_run)
        if not result or not result["changes"]:
            continue
        grand_eps_changed += 1
        for c in result["changes"]:
            grand_chunks += c["removed"]
            grand_patterns_changed += 1
        affected.append((level, result))
        print("  [%s] %s — %d patterns updated" % (level, result["episode_id"], len(result["changes"])))
        for c in result["changes"]:
            new_dur_str = ("%ds" % c["new_duration"]) if c["new_duration"] else "(dry)"
            print("       - %s  (-%d chunks, %s)" % (c["template"], c["removed"], new_dur_str))

    print()
    print("=" * 60)
    print("Episodes with changes:    %d" % grand_eps_changed)
    print("Patterns modified:        %d" % grand_patterns_changed)
    print("Explanation chunks removed: %d" % grand_chunks)
    if dry_run:
        print("(dry run — no files written)")

    # Print affected list for downstream upload step
    if affected and not dry_run:
        with open("/tmp/strip_affected.json", "w", encoding="utf-8") as f:
            json.dump(
                [{"level": lv, "episode_id": r["episode_id"], "json_path": r["json_path"]} for lv, r in affected],
                f, ensure_ascii=False, indent=2,
            )
        print("Wrote /tmp/strip_affected.json (%d eps) for re-upload step" % len(affected))


if __name__ == "__main__":
    main()
