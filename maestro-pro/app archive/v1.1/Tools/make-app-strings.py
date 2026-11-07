#!/usr/bin/env python3
"""Builds the app's String Catalogs from Tools/translations/<lang>.txt.

sources.json lists every string the compiler extracted (key, English); each <lang>.txt has `index|translation` lines
(a line without an index continues the previous one, for strings with line breaks). Strings with no letters, and the
brand name, stay as they are. Run: python3 Tools/make-app-strings.py
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "..", "Play Along")
SRC = json.load(open(os.path.join(HERE, "translations", "sources.json")))
LANGS = ["fr", "de", "es", "zh-Hans", "ja", "sv", "pt-PT", "it"]
INFO = {"CFBundleDisplayName", "CFBundleName", "NSAppleMusicUsageDescription", "NSCameraUsageDescription", "NSLocalNetworkUsageDescription", "NSMicrophoneUsageDescription"}


def load(lang):
    path = os.path.join(HERE, "translations", lang + ".txt")
    out, last = {}, None
    if not os.path.exists(path):
        return out
    for line in open(path, encoding="utf-8").read().split("\n"):
        m = re.match(r"^(\d+)\|(.*)$", line)
        if m:
            last = int(m.group(1)); out[last] = m.group(2)
        elif last is not None and line != "":
            out[last] += "\n" + line
    return out


def specs(s):
    return sorted(re.findall(r"%(?:\d+\$)?(?:lld|@|%)", s))


def main():
    tr = {l: load(l) for l in LANGS}
    cat, info = {}, {}
    for n, (key, en) in enumerate(SRC):
        if not re.search(r"[A-Za-z]", re.sub(r"%(?:\d+\$)?(?:lld|@)", "", en)) or key in ("Maestro Pro",) or key.strip() == "":
            continue
        loc = {}
        for l in LANGS:
            v = tr[l].get(n)
            if v is None:
                continue
            lead, trail = en[:len(en) - len(en.lstrip())], en[len(en.rstrip()):]
            v = lead + v.strip() + trail
            assert specs(v) == specs(en), f"{l} #{n} placeholders: {en!r} -> {v!r}"
            loc[l] = {"stringUnit": {"state": "translated", "value": v}}
        if not loc:
            continue
        (info if key in INFO else cat)[key] = {"extractionState": "manual", "localizations": loc}
    pb = open(os.path.join(HERE, "..", "Play Along.xcodeproj", "project.pbxproj"), encoding="utf-8").read()
    for k in sorted(INFO):  # English (and the brand name) must be explicit, or the system shows the bare key
        m = re.search(r"INFOPLIST_KEY_" + k + r' = "(.*?)";', pb)
        v = m.group(1) if m else "Maestro Pro"
        e = info.setdefault(k, {"extractionState": "manual", "localizations": {}})["localizations"]
        for l in ["en"] + (LANGS if k.startswith("CFBundle") else []):
            e[l] = {"stringUnit": {"state": "translated", "value": v}}
    for name, d in (("Localizable", cat), ("InfoPlist", info)):
        json.dump({"sourceLanguage": "en", "strings": d, "version": "1.0"}, open(os.path.join(APP, name + ".xcstrings"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        print(name, len(d))


if __name__ == "__main__":
    main()
