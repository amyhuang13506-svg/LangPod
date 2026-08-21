"""Quick A/B test: how does MiniMax render template skeleton with 顿号 vs 句号
as placeholder pauses?

Generates 2 mp3s in ~/Desktop/intro_pause_test/ for human listening.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_patterns import minimax_tts, pick_voice_pair_for_pattern

# Use the same female zh voice the pipeline would pick for a real pattern.
# Hash "pattern_test" → stable voice.
voices = pick_voice_pair_for_pattern("pattern_test_intro_pause")
zh_voice = voices["zh"]

SAMPLES = [
    {
        "label": "A_dunhao_short",
        "text": "今天我们学一个表达偏好的句型，I'd rather、 than、。接下来的例句意思是：我宁愿走路也不要等公交。现在听标准发音。",
    },
    {
        "label": "B_juhao_long",
        "text": "今天我们学一个表达偏好的句型，I'd rather。than。接下来的例句意思是：我宁愿走路也不要等公交。现在听标准发音。",
    },
    {
        "label": "C_dunhao_short_notonly",
        "text": "今天我们学一个递进强调的句型，Not only、 but also、。接下来的例句意思是：他不仅会说英语，还会说日语。现在听标准发音。",
    },
]

OUT_DIR = os.path.expanduser("~/Desktop/intro_pause_test")
os.makedirs(OUT_DIR, exist_ok=True)

for s in SAMPLES:
    print("Synthesizing: %s" % s["label"])
    seg = minimax_tts(s["text"], zh_voice)
    if seg is None:
        print("  ❌ failed")
        continue
    out_path = os.path.join(OUT_DIR, "%s.mp3" % s["label"])
    seg.export(out_path, format="mp3", bitrate="128k")
    print("  ✅ %.1fs → %s" % (len(seg) / 1000.0, out_path))

print("\n打开 Finder 听对比：")
print("  open %s" % OUT_DIR)
