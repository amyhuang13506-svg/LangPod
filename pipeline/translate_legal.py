# -*- coding: utf-8 -*-
"""
Translate docs/privacy.html + docs/terms.html into ko/ja/zh-Hant/es/pt-BR.

- zh-Hant: OpenCC s2twp (free, instant)
- others: GPT chunked by <h2> sections, HTML tags preserved
Output: docs/{name}_{lang}.html  (App links append ContentLanguage suffix)
"""
import re
import sys
import os

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import GPT_API_ENDPOINT, GPT_API_KEY, GPT_MODEL  # noqa: E402


def _call_gpt_raw(prompt):
    """直接返回文本（法律 HTML 含换行/引号，JSON 包裹易碎）。"""
    resp = requests.post(
        GPT_API_ENDPOINT,
        headers={"Authorization": "Bearer %s" % GPT_API_KEY, "Content-Type": "application/json"},
        json={"model": GPT_MODEL, "messages": [{"role": "user", "content": prompt}],
              "temperature": 0.2, "max_tokens": 16000},
        timeout=300)
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1]
    if content.endswith("```"):
        content = content.rsplit("```", 1)[0]
    return content.strip()

DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

LANGS = {
    "ko": ("Korean", "ko"),
    "ja": ("Japanese", "ja"),
    "es": ("Spanish (Latin American)", "es"),
    "pt-BR": ("Brazilian Portuguese", "pt-BR"),
}

PROMPT = """Translate this legal-document HTML fragment from Simplified Chinese to {lang_name}.

RULES:
1. Translate ONLY the human-readable text. Keep every HTML tag, attribute, class,
   and structure EXACTLY as-is. Do not add or remove elements.
2. Legal register appropriate for an app privacy policy / terms of service.
3. Keep product names (Castlingo, Apple, iTunes, App Store), emails, and URLs unchanged.
4. Dates stay in a natural local format (e.g. 2026年4月1日 → April 1, 2026 equivalents).
5. Output ONLY the translated HTML fragment — no commentary, no code fences.

FRAGMENT:
{chunk}
"""


def split_chunks(body, max_len=4500):
    """按 <h2> 切段再拼到 ~max_len 的块，保持标签完整。"""
    parts = re.split(r"(?=<h2)", body)
    chunks, cur = [], ""
    for p in parts:
        if cur and len(cur) + len(p) > max_len:
            chunks.append(cur)
            cur = p
        else:
            cur += p
    if cur:
        chunks.append(cur)
    return chunks


def translate_doc(name, lang):
    lang_name, html_lang = LANGS[lang]
    src = open(f"{DOCS}/{name}.html", encoding="utf-8").read()
    head, body_and_rest = src.split("<body>", 1)
    body, tail = body_and_rest.rsplit("</body>", 1)

    # head 里的 <title> 单独翻
    title = re.search(r"<title>(.*?)</title>", head).group(1)
    r = _call_gpt_raw(PROMPT.format(lang_name=lang_name, chunk=f"<title>{title}</title>"))
    head = head.replace(f"<title>{title}</title>", r)
    head = head.replace('lang="zh-CN"', f'lang="{html_lang}"')

    out_body = ""
    chunks = split_chunks(body)
    for i, chunk in enumerate(chunks):
        r = _call_gpt_raw(PROMPT.format(lang_name=lang_name, chunk=chunk))
        out_body += r
        print("   %s %s [%s] chunk %d/%d" % (name, lang, lang_name, i + 1, len(chunks)))

    out = head + "<body>" + out_body + "</body>" + tail
    path = f"{DOCS}/{name}_{lang}.html"
    open(path, "w", encoding="utf-8").write(out)
    print("✅", path)


def hant_doc(name):
    from hant import to_hant
    src = open(f"{DOCS}/{name}.html", encoding="utf-8").read()
    head, body_and_rest = src.split("<body>", 1)
    body, tail = body_and_rest.rsplit("</body>", 1)
    # head 只繁化 <title>；样式等不动
    m = re.search(r"<title>(.*?)</title>", head)
    head = head.replace(m.group(0), "<title>%s</title>" % to_hant(m.group(1)))
    head = head.replace('lang="zh-CN"', 'lang="zh-Hant"')
    out = head + "<body>" + to_hant(body) + "</body>" + tail
    path = f"{DOCS}/{name}_zh-Hant.html"
    open(path, "w", encoding="utf-8").write(out)
    print("✅", path)


if __name__ == "__main__":
    for name in ("privacy", "terms"):
        if not os.path.exists(f"{DOCS}/{name}_zh-Hant.html"):
            hant_doc(name)
    for lang in LANGS:
        for name in ("privacy", "terms"):
            if not os.path.exists(f"{DOCS}/{name}_{lang}.html"):
                translate_doc(name, lang)
