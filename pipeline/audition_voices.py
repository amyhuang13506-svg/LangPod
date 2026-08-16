# -*- coding: utf-8 -*-
"""
Multi-language TTS voice audition (ja / es / pt-BR), mirroring audition_ko_voices.

Synthesizes two samples per candidate voice:
  - translation style (pure target language, podcast translation track)
  - explainer style (teaching narration with embedded English, pattern module)

Output: ~/Desktop/多语言TTS试听/{lang}/{voice}_{style}.mp3

Usage: python3 audition_voices.py [ja|es|pt-BR ...]   (default: all three)
"""
import os
import sys

from generate_audio import synthesize_line

OUT_ROOT = os.path.expanduser("~/Desktop/多语言TTS试听")

CANDIDATES = {
    "ja": [
        "Japanese_KindLady",
        "Japanese_CalmLady",
        "Japanese_DependableWoman",
        "Japanese_GracefulMaiden",
        "Japanese_OptimisticYouth",
        "Japanese_IntellectualSenior",
        "Japanese_LoyalKnight",
        "Japanese_GentleButler",
        "Japanese_SportyStudent",
    ],
    "es": [
        "Spanish_SereneWoman",
        "Spanish_ConfidentWoman",
        "Spanish_Kind-heartedGirl",
        "Spanish_SophisticatedLady",
        "Spanish_FrankLady",
        "Spanish_Narrator",
        "Spanish_WiseScholar",
        "Spanish_ThoughtfulMan",
        "Spanish_RationalMan",
        "Spanish_Steadymentor",
    ],
    "pt-BR": [
        "Portuguese_SereneWoman",
        "Portuguese_ConfidentWoman",
        "Portuguese_SweetGirl",
        "Portuguese_LovelyLady",
        "Portuguese_Wiselady",
        "Portuguese_SmartYoungGirl",
        "Portuguese_ThoughtfulMan",
        "Portuguese_ReservedYoungMan",
        "Portuguese_Deep-VoicedGentleman",
        "Portuguese_CaptivatingStoryteller",
    ],
}

SAMPLES = {
    "ja": {
        "translation": "駅前に新しくできたカフェ、行ってみた？コーヒーがすごく美味しいらしいよ。今週末、一緒に行ってみない？",
        "explainer": "この表現のポイントは Could I です。丁寧にお願いするときに使います。では、ネイティブの発音を聞いてみましょう。Could I get a coffee to go?",
    },
    "es": {
        "translation": "¿Ya fuiste a la cafetería nueva del centro? Dicen que el café es buenísimo. ¿Vamos juntos este fin de semana?",
        "explainer": "La clave de esta expresión es Could I. Se usa para pedir algo con cortesía. Ahora escucha la pronunciación nativa. Could I get a coffee to go?",
    },
    "pt-BR": {
        "translation": "Você já foi na cafeteria nova do centro? Dizem que o café é ótimo. Vamos juntos neste fim de semana?",
        "explainer": "O ponto-chave dessa expressão é Could I. A gente usa para pedir algo com educação. Agora escute a pronúncia nativa. Could I get a coffee to go?",
    },
}


def main():
    langs = sys.argv[1:] or ["ja", "es", "pt-BR"]
    for lang in langs:
        out_dir = os.path.join(OUT_ROOT, lang)
        os.makedirs(out_dir, exist_ok=True)
        voices = CANDIDATES[lang]
        print("=== %s: %d candidate voices ===" % (lang, len(voices)))
        for voice in voices:
            for style, text in SAMPLES[lang].items():
                path = os.path.join(out_dir, "%s_%s.mp3" % (voice, style))
                if os.path.exists(path):
                    print("  skip (exists): %s" % os.path.basename(path))
                    continue
                seg = synthesize_line(text, voice, speed=1.0)
                if seg is None:
                    print("  ❌ %s (%s): synthesis failed" % (voice, style))
                    continue
                seg.export(path, format="mp3", bitrate="64k")
                print("  ✅ %s (%.1fs)" % (os.path.basename(path), len(seg) / 1000))
    print("\nDone → %s" % OUT_ROOT)


if __name__ == "__main__":
    main()
