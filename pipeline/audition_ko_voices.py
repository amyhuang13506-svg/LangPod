# -*- coding: utf-8 -*-
"""
One-time Korean TTS voice audition for the multilingual rollout.

1. Queries MiniMax voice list (if the endpoint responds) and filters Korean voices.
2. Falls back to a candidate list of known Korean system voice IDs.
3. Synthesizes two sample lines per voice:
   - translation style (pure Korean, podcast translation track)
   - explainer style (Korean teaching narration with embedded English, pattern module)
4. Writes mp3s to ~/Desktop/韩语TTS试听/ for human listening.

Usage: python3 audition_ko_voices.py [extra_voice_id ...]
"""
import os
import sys
import requests

from config import MINIMAX_API_KEY, MINIMAX_MODEL
from generate_audio import synthesize_line

OUT_DIR = os.path.expanduser("~/Desktop/韩语TTS试听")

# Known/likely MiniMax Korean system voice IDs (unverified — invalid ones just fail politely)
CANDIDATE_VOICES = [
    "Korean_SweetGirl",
    "Korean_CheerfulBoyfriend",
    "Korean_ElegantPrincess",
    "Korean_ReliableYouth",
    "Korean_CalmLady",
    "Korean_EnthusiasticTeacher",
    "Korean_GentleWoman",
    "Korean_MatureMan",
]

SAMPLES = {
    # Podcast translation track style: pure Korean, conversational
    "translation": (
        "시내에 새로 생긴 카페 가 봤어? 커피가 정말 맛있대. "
        "이번 주말에 같이 가 볼래?"
    ),
    # Pattern explainer style: Korean narration with embedded English
    "explainer": (
        "이 표현의 핵심은 Could I 예요. 정중하게 부탁할 때 쓰는 표현이에요. "
        "자, 표준 발음을 들어 보세요. Could I get a coffee to go?"
    ),
}


def fetch_korean_voices():
    """Try MiniMax voice list endpoint; return Korean voice ids or []."""
    try:
        resp = requests.post(
            "https://api.minimax.chat/v1/get_voice",
            headers={
                "Authorization": "Bearer %s" % MINIMAX_API_KEY,
                "Content-Type": "application/json",
            },
            json={"voice_type": "system"},
            timeout=30,
        )
        if resp.status_code != 200:
            print("voice list HTTP %d, falling back to candidates" % resp.status_code)
            return []
        data = resp.json()
        voices = []
        for group in ("system_voice", "voice_slots", "voices"):
            for v in data.get(group) or []:
                vid = v.get("voice_id", "")
                name = (v.get("voice_name") or "") + " " + vid
                if "korean" in name.lower() or "한국" in name:
                    voices.append(vid)
        return voices
    except Exception as e:
        print("voice list query failed (%s), falling back to candidates" % e)
        return []


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    listed = fetch_korean_voices()
    if listed:
        print("API returned %d Korean voices: %s" % (len(listed), listed))
    voices = list(dict.fromkeys(listed + CANDIDATE_VOICES + sys.argv[1:]))

    ok = []
    for vid in voices:
        print("\n=== %s ===" % vid)
        good = True
        for style, text in SAMPLES.items():
            seg = synthesize_line(text, vid, speed=1.0)
            if seg is None:
                print("   ✗ %s failed (voice likely invalid)" % style)
                good = False
                break
            path = os.path.join(OUT_DIR, "%s__%s.mp3" % (vid, style))
            seg.export(path, format="mp3")
            print("   ✓ %s → %s (%.1fs)" % (style, os.path.basename(path), len(seg) / 1000))
        if good:
            ok.append(vid)

    print("\n可用韩语 voice：%s" % (ok or "无 — MiniMax 可能不支持韩语，需切 ElevenLabs"))
    print("试听文件在：%s" % OUT_DIR)


if __name__ == "__main__":
    main()
