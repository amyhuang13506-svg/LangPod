# -*- coding: utf-8 -*-
"""
Validate a String Catalog: every translation must carry the same format
specifiers (%@ / %lld / %% ...) as its source key, in the same order —
LLM translation loves dropping or mangling them, which corrupts UI at
runtime. Also flags CJK ideographs leaking into ko translations.

Usage: python3 check_xcstrings_placeholders.py ../LangPod/Localizable.xcstrings
Exit code 1 on any finding (CI-friendly).
"""

import json
import re
import sys

SPEC_RE = re.compile(r"%(?:\d+\$)?(?:@|lld|d|.0f|f|%)")


def specs(s):
    return SPEC_RE.findall(s)


def main(path):
    catalog = json.load(open(path))
    findings = []
    n_units = 0
    for key, entry in catalog.get("strings", {}).items():
        for lang, loc in (entry.get("localizations") or {}).items():
            value = (loc.get("stringUnit") or {}).get("value", "")
            n_units += 1
            sv, sk = specs(value), specs(key)
            if sv != sk:
                # positional reordering (%1$lld ...) is fine when every spec is
                # explicitly positioned and the multiset matches the source
                strip = lambda xs: sorted(re.sub(r"^%\d+\$", "%", x) for x in xs)
                all_positional = sv and all(re.match(r"^%\d+\$", x) for x in sv)
                if not (all_positional and strip(sv) == strip(sk)):
                    findings.append("[%s] placeholder mismatch\n  key:   %r\n  value: %r" % (lang, key, value))
            if lang == "ko" and any("一" <= c <= "鿿" for c in value):
                findings.append("[ko] CJK leak\n  key:   %r\n  value: %r" % (key, value))

    print("checked %d translation units in %s" % (n_units, path))
    if findings:
        print("\n❌ %d findings:" % len(findings))
        for f in findings:
            print(f)
        sys.exit(1)
    print("✅ all placeholders consistent")


if __name__ == "__main__":
    main(sys.argv[1])
