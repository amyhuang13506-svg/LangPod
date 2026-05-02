"""
Pronunciation contrast demo generator (v2).

For each sentence, generates ONE mp3 with both versions back-to-back:
  [Chinese-learner style] + 1s pause + [American natural connected speech]

Chinese-learner style uses ElevenLabs v3 audio tags ([slowly, flatly, ...]) +
high stability to produce a naturally flat, non-connected reading — NOT the
robotic "period after every word" trick.

Output: ~/Desktop/发音对比/NN_slug.mp3  (+ README.txt with IPA reference)
"""

import os
import sys
import time
import tempfile
import requests
from pydub import AudioSegment

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import (
    ELEVENLABS_API_KEY,
    ELEVENLABS_API_ENDPOINT,
    ELEVENLABS_MODEL,
    ELEVENLABS_PATTERN_VOICES,
)

VOICE_ID = ELEVENLABS_PATTERN_VOICES[0]

OUTPUT_ROOT = os.path.expanduser("~/Desktop/发音对比")
GAP_MS = 1000

# Audio-tag prefix that directs v3 to read flatly, syllable-timed, no linking.
CN_STYLE_PREFIX = "[slowly, flat monotone, pronouncing every word separately with equal stress, no connected speech, no reductions] "

SENTENCES = [
    {
        "slug": "01_pick_it_up",
        "text": "Pick it up and put it on the table.",
        "ipa_cn": "/pɪk ɪt ʌp ænd pʊt ɪt ɒn ðə ˈteɪbəl/",
        "ipa_us": "/ˈpɪ.kɪ.ˈtʌ.pən.ˈpʊ.ɾɪ.ˈɒn.ðə.ˈteɪ.bəl/",
        "feature": "Consonant-to-vowel linking",
    },
    {
        "slug": "02_turn_it_off",
        "text": "Turn it off and check it out.",
        "ipa_cn": "/tɜːrn ɪt ɒf ænd tʃek ɪt aʊt/",
        "ipa_us": "/ˈtɜːr.nɪ.ˈtɔːf.ən.ˈtʃe.kɪ.ˈtaʊt/",
        "feature": "Consonant-to-vowel linking",
    },
    {
        "slug": "03_got_a_lot_of_water",
        "text": "I got a lot of water in the city.",
        "ipa_cn": "/aɪ ɡɒt ə lɒt ɒv ˈwɔːtər ɪn ðə ˈsɪti/",
        "ipa_us": "/aɪ ˈɡɑː.ɾə ˈlɑː.ɾə ˈwɑː.ɾɚ.ɪn.ðə ˈsɪ.ɾi/",
        "feature": "Flap T (T between vowels)",
    },
    {
        "slug": "04_better_late",
        "text": "Better late than never at a party.",
        "ipa_cn": "/ˈbetər leɪt ðæn ˈnevər æt ə ˈpɑːrti/",
        "ipa_us": "/ˈbe.ɾɚ ˈleɪt.ðən.ˈne.vɚ.ˈæ.ɾə.ˈpɑːr.ɾi/",
        "feature": "Flap T",
    },
    {
        "slug": "05_gonna_wanna",
        "text": "I'm going to tell you what I want to do.",
        "ipa_cn": "/aɪm ˈɡəʊɪŋ tuː tel juː wɒt aɪ wɒnt tuː duː/",
        "ipa_us": "/aɪm ˈɡʌ.nə ˈte.ljə ˈwʌ.ɾaɪ ˈwɑ.nə ˈduː/",
        "feature": "Reduction (gonna / wanna / whaddai)",
    },
    {
        "slug": "06_cup_of_coffee",
        "text": "Give me a cup of coffee and a piece of bread.",
        "ipa_cn": "/ɡɪv miː ə kʌp ɒv ˈkɒfi ænd ə piːs ɒv bred/",
        "ipa_us": "/ˈɡɪ.mi.ə ˈkʌ.pə ˈkɔː.fi.ə.nə ˈpiː.sə ˈbred/",
        "feature": "Weak form of 'of' / 'and'",
    },
    {
        "slug": "07_did_you",
        "text": "Did you meet your friend? Don't you know him?",
        "ipa_cn": "/dɪd juː miːt jɔːr frend dəʊnt juː nəʊ hɪm/",
        "ipa_us": "/ˈdɪ.dʒə ˈmiː.tʃɚ ˈfrend ˈdoʊn.tʃə ˈnoʊ.ɪm/",
        "feature": "Assimilation (d+y→dʒ, t+y→tʃ, h-dropping)",
    },
    {
        "slug": "08_bet_you",
        "text": "I'll bet you I can get you out of here.",
        "ipa_cn": "/aɪl bet juː aɪ kæn ɡet juː aʊt ɒv hɪər/",
        "ipa_us": "/aɪl ˈbe.tʃə aɪ.kən ˈɡe.tʃə ˈaʊ.ɾə.ˈhɪr/",
        "feature": "Assimilation (t+y→tʃ) + flap T",
    },
    {
        "slug": "09_must_be",
        "text": "He must be the next best friend I've ever had.",
        "ipa_cn": "/hiː mʌst biː ðə nekst best frend aɪv ˈevər hæd/",
        "ipa_us": "/hi ˈmʌs.bi.ðə ˈneks.ˈbes.ˈfren.ˈaɪ.vevɚ.ˈhæd/",
        "feature": "Elision (dropped t/d in consonant clusters)",
    },
    {
        "slug": "10_used_to_send",
        "text": "I used to send him postcards last Christmas.",
        "ipa_cn": "/aɪ juːzd tuː send hɪm ˈpəʊstkɑːrdz lɑːst ˈkrɪsməs/",
        "ipa_us": "/aɪ ˈjuːs.tə ˈsen.ɪm ˈpoʊs.kɑːrdz ˈlæs ˈkrɪs.məs/",
        "feature": "Elision + used to→useta + h-dropping",
    },
]


def eleven_tts(text, stability, style):
    """Call ElevenLabs v3 TTS. Returns AudioSegment or None."""
    url = "%s/%s" % (ELEVENLABS_API_ENDPOINT, VOICE_ID)
    headers = {
        "xi-api-key": ELEVENLABS_API_KEY,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }
    body = {
        "text": text,
        "model_id": ELEVENLABS_MODEL,
        "voice_settings": {
            "stability": stability,
            "similarity_boost": 0.75,
            "style": style,
            "use_speaker_boost": True,
        },
    }

    for attempt in range(3):
        try:
            r = requests.post(url, headers=headers, json=body, timeout=180)
        except requests.RequestException as e:
            print("   network error: %s, retrying..." % e)
            time.sleep(2 ** attempt)
            continue

        if r.status_code == 200:
            tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
            tmp.write(r.content)
            tmp.close()
            try:
                return AudioSegment.from_mp3(tmp.name)
            finally:
                os.unlink(tmp.name)

        print("   ❌ HTTP %d: %s" % (r.status_code, r.text[:200]))
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(2 ** attempt)
            continue
        return None
    return None


def generate_pair(sentence):
    """Returns a single AudioSegment: cn-style + 1s silence + us-style."""
    cn_text = CN_STYLE_PREFIX + sentence["text"]
    print("   → CN-style (flat, no linking)...")
    cn = eleven_tts(cn_text, stability=0.85, style=0.0)
    if cn is None:
        return None

    print("   → US-style (natural connected)...")
    us = eleven_tts(sentence["text"], stability=0.35, style=0.4)
    if us is None:
        return None

    gap = AudioSegment.silent(duration=GAP_MS)
    return cn + gap + us


def main():
    os.makedirs(OUTPUT_ROOT, exist_ok=True)

    for idx, s in enumerate(SENTENCES, 1):
        print("\n[%d/%d] %s — %s" % (idx, len(SENTENCES), s["slug"], s["feature"]))
        print("   text: %s" % s["text"])

        out_path = os.path.join(OUTPUT_ROOT, "%s.mp3" % s["slug"])
        if os.path.exists(out_path):
            print("   ⏭️  already exists, skip")
            continue

        combined = generate_pair(s)
        if combined is None:
            print("   ❌ failed")
            continue

        combined.export(out_path, format="mp3")
        print("   ✅ %s (%.1fs)" % (out_path, len(combined) / 1000.0))

    readme_lines = [
        "# 发音对比 Demo",
        "",
        "每个 mp3 = 中式读法（平淡、无连读）+ 1秒停顿 + 美式读法（自然连读）",
        "",
        "Voice: ElevenLabs %s / voice_id %s" % (ELEVENLABS_MODEL, VOICE_ID),
        "",
        "=" * 70,
        "",
    ]
    for idx, s in enumerate(SENTENCES, 1):
        readme_lines.append("## %d. %s — %s" % (idx, s["slug"], s["feature"]))
        readme_lines.append("")
        readme_lines.append("Sentence: %s" % s["text"])
        readme_lines.append("")
        readme_lines.append("中式 IPA: %s" % s["ipa_cn"])
        readme_lines.append("美式 IPA: %s" % s["ipa_us"])
        readme_lines.append("")

    readme_path = os.path.join(OUTPUT_ROOT, "README.txt")
    with open(readme_path, "w") as f:
        f.write("\n".join(readme_lines))
    print("\n📝 README: %s" % readme_path)
    print("✅ Output folder: %s" % OUTPUT_ROOT)


if __name__ == "__main__":
    main()
