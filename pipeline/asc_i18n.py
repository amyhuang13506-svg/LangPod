# -*- coding: utf-8 -*-
"""
5 语上架自动化:App Store Connect API 全流程。

用法:
  python3 asc_i18n.py metadata      # 建/更新 5 个本地化(名称/副标题/关键词/描述/推广/whatsNew)
  python3 asc_i18n.py screenshots   # 上传 5 语截图(APP_IPHONE_65, 1284x2778, 各 6 张)
  python3 asc_i18n.py attach        # 等 build 处理完 → 挂到 1.5.0
  python3 asc_i18n.py submit        # 提审
坑(前次验证):URL 里 filter[] 必须 %5B%5D 编码,否则部分接口 401。
"""
import hashlib
import json
import re
import sys
import time

import jwt
import requests

KEY_ID = "U64H7QL8C6"
ISSUER = "ca103e1b-ec4c-4da5-bf21-74dc18f1d829"
KEY_PATH = "/Users/mac/.appstoreconnect/private_keys/AuthKey_U64H7QL8C6.p8"
BUNDLE = "com.amyhuang.castlingo"
VERSION = "1.5.0"
BASE = "https://api.appstoreconnect.apple.com"
DOCS = "/Users/mac/Desktop/LangPod/docs"
SHOTS = "/Users/mac/Desktop/LangPod/应用商店截图"

LOCALES = {  # ASC locale → (docs 语言段落标识, 截图目录)
    "ko":      ("韩语文档", "多语言_ko"),
    "ja":      ("## 日本語", "多语言_ja"),
    "zh-Hant": ("## 繁體中文", "多语言_zh-Hant"),
    "es-MX":   ("## Español", "多语言_es"),
    "pt-BR":   ("## Português", "多语言_pt-BR"),
}

# 名称/副标题(30 字硬限,es/pt 文档里的副标题超长,用短版)
NAME_SUB = {
    "ko":      ("Castlingo - 영어 리스닝 팟캐스트", "매일 5분, 들리는 영어가 시작돼요"),
    "ja":      ("Castlingo - 英語リスニングPodcast", "毎日5分、聞き流すだけで英語耳に"),
    "zh-Hant": ("Castlingo - 英語聽力Podcast電台", "每天5分鐘,聽著聽著就聽懂了"),
    "es-MX":   ("Castlingo: inglés con pódcast", "Inglés real, 5 min al día"),
    "pt-BR":   ("Castlingo: inglês com podcast", "Inglês real, 5 min por dia"),
}

WHATS_NEW = {
    "ko": "한국어 지원을 시작했어요! 인터페이스·번역 트랙·문형 해설이 모두 한국어로 제공됩니다.",
    "ja": "日本語に対応しました!インターフェース・翻訳トラック・文型解説がすべて日本語でご利用いただけます。",
    "zh-Hant": "新增繁體中文介面與翻譯內容,句型講解、詞彙課程全面在地化。",
    "es-MX": "¡Ahora en español! Interfaz, pista de traducción y explicaciones de patrones, todo en español.",
    "pt-BR": "Agora em português! Interface, faixa de tradução e explicações de padrões, tudo em português.",
    "zh-Hans": "新增韩语、日语、繁体中文、西班牙语、葡萄牙语支持;修复若干显示问题。",
    "en": "Now available in Korean, Japanese, Traditional Chinese, Spanish and Portuguese. Bug fixes.",
}


def token():
    key = open(KEY_PATH).read()
    return jwt.encode(
        {"iss": ISSUER, "iat": int(time.time()) - 30, "exp": int(time.time()) + 1100,
         "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": KEY_ID})


def api(method, path, payload=None, raw_url=None, extra_headers=None, data=None):
    url = raw_url or (BASE + path)
    headers = {"Authorization": "Bearer %s" % token()}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if extra_headers:
        headers.update(extra_headers)
    r = requests.request(method, url, headers=headers,
                         json=payload if payload is not None else None,
                         data=data, timeout=120)
    if r.status_code >= 400:
        raise RuntimeError("%s %s -> %d: %s" % (method, url.replace(BASE, ""), r.status_code, r.text[:400]))
    return r.json() if r.text else {}


def app_id():
    r = api("GET", "/v1/apps?filter%5BbundleId%5D=" + BUNDLE)
    return r["data"][0]["id"]


# ---------- 文案解析 ----------

def _first_code_block(text):
    m = re.search(r"```\n(.*?)```", text, re.S)
    return m.group(1).strip() if m else None


def parse_copy():
    """从两份材料文档提取 keywords/promo/description。"""
    out = {}
    ko_doc = open(f"{DOCS}/ASC韩语商店材料_20260815.md", encoding="utf-8").read()
    multi = open(f"{DOCS}/ASC多语言商店材料_20260816.md", encoding="utf-8").read()

    def extract(section_text):
        d = {}
        for field, keys in (("keywords", ["关键词"]), ("promo", ["推广文本"]), ("description", ["描述"])):
            for k in keys:
                m = re.search(r"#+\s*%s.*?\n(.*?)(?=\n#|\Z)" % k, section_text, re.S)
                if m:
                    block = _first_code_block(m.group(1))
                    if block:
                        d[field] = block
                        break
        return d

    out["ko"] = extract(ko_doc)
    for loc, (marker, _) in LOCALES.items():
        if loc == "ko":
            continue
        i = multi.find(marker)
        j = min(x for x in [multi.find("\n## ", i + 4), len(multi)] if x > 0)
        out[loc] = extract(multi[i:j])
    return out


# ---------- 元数据 ----------

def get_version_id(app):
    r = api("GET", f"/v1/apps/{app}/appStoreVersions?filter%5BappStoreState%5D=PREPARE_FOR_SUBMISSION&limit=5")
    for v in r["data"]:
        if v["attributes"]["versionString"] == VERSION:
            return v["id"]
    if r["data"]:
        vid = r["data"][0]["id"]
        api("PATCH", f"/v1/appStoreVersions/{vid}",
            {"data": {"id": vid, "type": "appStoreVersions",
                      "attributes": {"versionString": VERSION}}})
        return vid
    r = api("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": VERSION},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    return r["data"]["id"]


def run_metadata(app):
    copy = parse_copy()
    vid = get_version_id(app)
    print("version id:", vid)

    # appInfo(名称/副标题)
    r = api("GET", f"/v1/apps/{app}/appInfos?limit=5")
    # 取可编辑的那份(PREPARE_FOR_SUBMISSION / DEVELOPER_*)
    info = None
    for it in r["data"]:
        if it["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                     "REJECTED", "METADATA_REJECTED", None):
            info = it["id"]
    info = info or r["data"][-1]["id"]
    have = api("GET", f"/v1/appInfos/{info}/appInfoLocalizations?limit=20")
    have_info = {x["attributes"]["locale"]: x["id"] for x in have["data"]}

    for loc, (name, sub) in NAME_SUB.items():
        attrs = {"name": name, "subtitle": sub}
        if loc in have_info:
            api("PATCH", f"/v1/appInfoLocalizations/{have_info[loc]}",
                {"data": {"id": have_info[loc], "type": "appInfoLocalizations", "attributes": attrs}})
        else:
            api("POST", "/v1/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations", "attributes": dict(attrs, locale=loc),
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info}}}}})
        print("  ✅ appInfo", loc, name)

    # 版本本地化(描述/关键词/推广/whatsNew)
    have = api("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=20")
    have_ver = {x["attributes"]["locale"]: x["id"] for x in have["data"]}
    base_loc = have["data"][0]["attributes"] if have["data"] else {}
    support = base_loc.get("supportUrl")

    for loc in list(LOCALES) + ["zh-Hans", "en-US" if "en-US" in have_ver else "en"]:
        wn = WHATS_NEW.get(loc) or WHATS_NEW.get(loc.split("-")[0])
        attrs = {"whatsNew": wn} if wn else {}
        if loc in LOCALES:
            c = copy[loc]
            clean = lambda s: s.replace(" → ", " · ").replace("→", "·")  # ASC 禁用箭头字符
            attrs.update({"description": clean(c["description"]), "keywords": c["keywords"][:100],
                          "promotionalText": clean(c["promo"])[:170]})
            if support:
                attrs["supportUrl"] = support
        if not attrs:
            continue
        if loc in have_ver:
            api("PATCH", f"/v1/appStoreVersionLocalizations/{have_ver[loc]}",
                {"data": {"id": have_ver[loc], "type": "appStoreVersionLocalizations", "attributes": attrs}})
        elif loc in LOCALES:
            api("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations", "attributes": dict(attrs, locale=loc),
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        else:
            continue
        print("  ✅ versionLoc", loc)
    return vid


# ---------- 截图 ----------

def upload_screenshots(app):
    vid = get_version_id(app)
    have = api("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=20")
    ver_locs = {x["attributes"]["locale"]: x["id"] for x in have["data"]}
    import os
    for loc, (_, shot_dir) in LOCALES.items():
        vl = ver_locs.get(loc)
        if not vl:
            print("  ⚠️ no versionLocalization for", loc)
            continue
        sets = api("GET", f"/v1/appStoreVersionLocalizations/{vl}/appScreenshotSets?limit=10")
        set_id = None
        for s in sets["data"]:
            if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_65":
                set_id = s["id"]
        if not set_id:
            r = api("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": "APP_IPHONE_65"},
                "relationships": {"appStoreVersionLocalization":
                                  {"data": {"type": "appStoreVersionLocalizations", "id": vl}}}}})
            set_id = r["data"]["id"]
        existing = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=20")
        if existing["data"]:
            print("  ⏭ %s already has %d shots" % (loc, len(existing["data"])))
            continue
        files = sorted(f for f in os.listdir(f"{SHOTS}/{shot_dir}") if f.endswith(".png"))
        for fname in files:
            path = f"{SHOTS}/{shot_dir}/{fname}"
            blob = open(path, "rb").read()
            r = api("POST", "/v1/appScreenshots", {"data": {
                "type": "appScreenshots",
                "attributes": {"fileName": fname, "fileSize": len(blob)},
                "relationships": {"appScreenshotSet":
                                  {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
            shot = r["data"]
            for op in shot["attributes"]["uploadOperations"]:
                chunk = blob[op["offset"]:op["offset"] + op["length"]]
                hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
                rr = requests.request(op["method"], op["url"], headers=hdrs, data=chunk, timeout=300)
                rr.raise_for_status()
            api("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
                "id": shot["id"], "type": "appScreenshots",
                "attributes": {"uploaded": True,
                               "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
            print("  ✅ %s %s" % (loc, fname))


# ---------- build 挂载 + 提审 ----------

def attach_build(app):
    vid = get_version_id(app)
    for _ in range(60):
        r = api("GET", f"/v1/builds?filter%5Bapp%5D={app}&sort=-uploadedDate&limit=3")
        for b in r["data"]:
            if b["attributes"]["version"] == "13":
                st = b["attributes"]["processingState"]
                print("build 13:", st)
                if st == "VALID":
                    api("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                        {"data": {"type": "builds", "id": b["id"]}})
                    print("✅ build attached")
                    return True
                if st in ("FAILED", "INVALID"):
                    raise RuntimeError("build processing failed")
        time.sleep(60)
    raise RuntimeError("build not found/processed in time")


def submit(app):
    vid = get_version_id(app)
    r = api("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    sub_id = r["data"]["id"]
    api("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    api("PATCH", f"/v1/reviewSubmissions/{sub_id}",
        {"data": {"id": sub_id, "type": "reviewSubmissions", "attributes": {"submitted": True}}})
    print("🚀 submitted for review")


if __name__ == "__main__":
    cmd = sys.argv[1]
    a = app_id()
    print("app:", a)
    if cmd == "metadata":
        run_metadata(a)
    elif cmd == "screenshots":
        upload_screenshots(a)
    elif cmd == "attach":
        attach_build(a)
    elif cmd == "submit":
        submit(a)
