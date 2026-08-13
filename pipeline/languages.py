# -*- coding: utf-8 -*-
"""
Language registry for the multilingual rollout (docs/多语言版方案_20260814.md).

All five target languages are registered here; NEW_LANGS is the per-language
generation switch — only languages listed there get daily/backfill localization.
Adding a language to production = fill its voices/rules + append to NEW_LANGS
(+ prompts_{lang}.py + App: add to ContentLanguage.enabled).

zh is the legacy path: existing files keep *_zh field names and unsuffixed
filenames; it is listed here only for push-copy grouping and shared metadata.
New-language derivative files use generic field names (translation,
example_translation, ...) and a `_{lang}` filename suffix.
"""

LANGUAGES = {
    "zh": {
        "legacy": True,
        "suffix": "",
        "name_en": "Chinese (Simplified)",
        "push_copy_episode": {
            "easy": "今天的新一集（初级）",
            "medium": "今天的新一集（中级）",
            "hard": "今天的新一集（高级）",
        },
        "push_copy_episode_body": "打开听一听",
        "push_copy_raw": "今日视频",
        "push_copy_raw_body": "打开看一看",
    },
    "ko": {
        "legacy": False,
        "suffix": "_ko",
        "name_en": "Korean",
        "prompt_lang": "Korean (South Korea)",
        # 字幕/翻译长度规则（App 单行字幕上限；上线前 UI 实测校准）
        "subtitle_max_chars": 44,          # 讲解字幕单块上限（含空格，≈3 行）
        "podcast_seg_max_chars": 40,       # 播客整句翻译软上限
        "char_range": ("가", "힣"),  # 韩文音节块（가-힣）
        # MiniMax speech-02-hd 韩语系统音色（2026-08-14 试听 49 个可用音色后初选，
        # 用户终选后可改 —— pick 逻辑按 speaker 性别选）
        "tts": {
            "provider": "minimax",
            "voice_male": "Korean_ReliableYouth",
            "voice_female": "Korean_FriendlyBigSister",
            # patterns 讲解声（韩语叙述 + 夹读英文），P3 用
            "voice_teacher_female": "Korean_SoothingLady",
            "voice_teacher_male": "Korean_WiseTeacher",
        },
        "push_copy_episode": {
            "easy": "오늘의 새 에피소드 (초급)",
            "medium": "오늘의 새 에피소드 (중급)",
            "hard": "오늘의 새 에피소드 (고급)",
        },
        "push_copy_episode_body": "열어서 들어보세요",
        "push_copy_raw": "오늘의 원어민 영상",
        "push_copy_raw_body": "열어서 확인해 보세요",
    },
    "zh-Hant": {
        "legacy": False,
        "suffix": "_zh-Hant",
        "name_en": "Chinese (Traditional)",
        # 特殊通道：文本 OpenCC 简转繁 + GPT 润色用词；翻译音频复用 zh 的 mp3。
        "reuse_audio_from": "zh",
        "tts": None,
        "push_copy_episode": {
            "easy": "今天的新一集（初級）",
            "medium": "今天的新一集（中級）",
            "hard": "今天的新一集（高級）",
        },
        "push_copy_episode_body": "打開聽一聽",
        "push_copy_raw": "今日影片",
        "push_copy_raw_body": "打開看一看",
    },
    "ja": {
        "legacy": False,
        "suffix": "_ja",
        "name_en": "Japanese",
        "prompt_lang": "Japanese",
        "subtitle_max_chars": 22,
        "podcast_seg_max_chars": 36,
        "char_range": None,  # 日文混用汉字/假名，QC 用假名占比判定（TODO P-ja）
        "tts": {"provider": "minimax", "voice_male": None, "voice_female": None},  # TODO 试听
        "push_copy_episode": {
            "easy": "今日の新エピソード（初級）",
            "medium": "今日の新エピソード（中級）",
            "hard": "今日の新エピソード（上級）",
        },
        "push_copy_episode_body": "開いて聴いてみましょう",
        "push_copy_raw": "今日のネイティブ動画",
        "push_copy_raw_body": "開いてチェック",
    },
    "es": {
        "legacy": False,
        "suffix": "_es",
        "name_en": "Spanish (Latin America)",
        "prompt_lang": "Spanish (neutral Latin American)",
        "subtitle_max_chars": 42,
        "podcast_seg_max_chars": 70,
        "char_range": None,
        "tts": {"provider": "minimax", "voice_male": None, "voice_female": None},  # TODO 试听
        "push_copy_episode": {
            "easy": "Nuevo episodio de hoy (básico)",
            "medium": "Nuevo episodio de hoy (intermedio)",
            "hard": "Nuevo episodio de hoy (avanzado)",
        },
        "push_copy_episode_body": "Ábrelo y escucha",
        "push_copy_raw": "Video nativo de hoy",
        "push_copy_raw_body": "Ábrelo y míralo",
    },
    "pt-BR": {
        "legacy": False,
        "suffix": "_pt-BR",
        "name_en": "Portuguese (Brazil)",
        "prompt_lang": "Brazilian Portuguese",
        "subtitle_max_chars": 42,
        "podcast_seg_max_chars": 70,
        "char_range": None,
        "tts": {"provider": "minimax", "voice_male": None, "voice_female": None},  # TODO 试听
        "push_copy_episode": {
            "easy": "Novo episódio de hoje (básico)",
            "medium": "Novo episódio de hoje (intermediário)",
            "hard": "Novo episódio de hoje (avançado)",
        },
        "push_copy_episode_body": "Abra e ouça",
        "push_copy_raw": "Vídeo nativo de hoje",
        "push_copy_raw_body": "Abra e confira",
    },
}

# 当前开启每日生成/回填的新语言（zh 走 legacy 主流程，不在此列）
NEW_LANGS = ["ko"]


def lang_suffix(lang):
    """Filename suffix for a language ("" for zh legacy)."""
    return LANGUAGES[lang]["suffix"]


def contains_han(text):
    """True if text contains any CJK ideograph — used by QC to catch
    untranslated Chinese leaking into non-Chinese output."""
    return any("一" <= c <= "鿿" for c in text)


def target_char_ratio(text, lang):
    """Share of target-language characters among letter-ish chars (0..1).
    Only meaningful for languages with char_range (ko)."""
    rng = LANGUAGES[lang].get("char_range")
    if not rng:
        return 1.0
    lo, hi = rng
    relevant = [c for c in text if c.isalpha()]
    if not relevant:
        return 1.0
    hits = sum(1 for c in relevant if lo <= c <= hi)
    return hits / len(relevant)
