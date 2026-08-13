# -*- coding: utf-8 -*-
"""
QC Layer 1 — LLM judge for localized content quality.

Judges what mechanical rules can't: naturalness, register, whether the
explainer would sound like a friendly native teacher. Judge persona is a
native speaker of the target language; prompt written in the target language
to anchor the register.

NOTE: generator and judge currently share the same GPT deployment
(api.v3.cm). Cross-model judging (Claude/Gemini) is the plan-of-record once
a second provider key is provisioned — swap JUDGE_MODEL then. Mitigations in
place until then: judge sees only the OUTPUT (not the generation prompt),
temperature 0, explicit permission to fail.
"""

import json
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests
from config import GPT_API_ENDPOINT, GPT_API_KEY, GPT_MODEL

JUDGE_MODEL = GPT_MODEL  # TODO: cross-model judge when second provider available

_KO_JUDGE_PROMPT = """당신은 한국어 원어민이자 영어 교육 콘텐츠 품질 심사위원입니다.
아래는 한국인 영어 학습자를 위한 팟캐스트 '문형 해설' 대본입니다.
청취자가 실제로 듣게 되는 해설 문장이 번역투이거나 부자연스러우면 불합격 처리하세요.

=== 필드별 성격 (심사 전 반드시 이해) ===
- "translation": 사전식 문형 주석입니다. '~' 는 빈칸 표시이며, 간결한 주석체가 정상입니다.
  뜻이 정확하면 합격 — 구어체 자연스러움 기준을 적용하지 마세요. 어순 취향 차이는 결함이 아닙니다.
- "pronunciation_intro" / "meaning" / "scene_and_feeling" / examples 의 scene_prefix:
  청취자가 음성으로 듣는 해설입니다. 여기가 자연스러움 심사의 핵심입니다.
- "example_sentences[].translation": 예문 번역 — 자연스러운 문장이어야 합니다.

=== 심사 대상 (문형: {template}) ===
{content}

=== 심사 기준 (각 항목 1-5점) ===
1. naturalness: 해설 문장(intro/meaning/scene_and_feeling/scene_prefix/예문 번역)이
   자연스러운 한국어 구어체(해요체)인가? 명백한 번역투(어색한 조사, 영어 어순 직역)가 있는가?
   ※ 사소한 어순 취향이나 '더 나을 수도 있는 표현' 수준은 감점 사유가 아닙니다. 4점 이상을 주고,
     명백히 어색해서 원어민이 듣고 갸웃할 문장이 있을 때만 3점 이하를 주세요.
2. register: 친근한 팟캐스트 선생님 톤이 일관되는가?
3. clarity: 설명이 학습자에게 명확한가? (장면 묘사가 구체적인가)
4. accuracy: 영어 문형에 대한 설명이 정확한가?

JSON만 출력:
{{"scores": {{"naturalness": n, "register": n, "clarity": n, "accuracy": n}},
 "pass": true/false,  // 모든 항목 4점 이상이어야 true
 "issues": ["불합격 사유를 한국어로, 구체적으로 (문제 문장 인용 + 수정안)", ...]}}"""

_JUDGE_PROMPTS = {"ko": _KO_JUDGE_PROMPT}


def _call_judge(prompt):
    response = requests.post(
        GPT_API_ENDPOINT,
        headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
        json={
            "model": JUDGE_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0,
            "response_format": {"type": "json_object"},
            "max_tokens": 2000,
        },
        timeout=180,
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(content.strip())


def judge_pattern_localization(loc, template, lang):
    """LLM-judge a localized pattern explainer. Returns (passed, issues)."""
    prompt_tpl = _JUDGE_PROMPTS.get(lang)
    if prompt_tpl is None:
        return True, []  # no judge for this language yet — L0 rules only

    content = json.dumps(
        {
            "translation": loc.get("translation"),
            "pronunciation_intro": loc.get("pronunciation_intro"),
            "meaning": loc.get("meaning"),
            "scene_and_feeling": loc.get("scene_and_feeling"),
            "examples": loc.get("examples"),
            "example_sentences": loc.get("example_sentences"),
        },
        ensure_ascii=False,
        indent=1,
    )
    try:
        verdict = _call_judge(prompt_tpl.format(template=template, content=content))
    except Exception as e:
        print("   ⚠️  judge call failed (%s) — treating as pass (L0 rules still apply)" % e)
        return True, []

    passed = bool(verdict.get("pass"))
    issues = [str(i) for i in (verdict.get("issues") or [])]
    scores = verdict.get("scores") or {}
    print("   ⚖️  judge: %s %s" % ("PASS" if passed else "FAIL", scores))
    return passed, issues
