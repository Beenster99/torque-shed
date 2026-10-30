#!/usr/bin/env python3
"""The words on the boards at a border (Ride Anywhere v2, phase D round 3, D8): each country's own name for itself and
its word of welcome, in its language and script (data/countries.json "language" and "script"): data/border_words.json.
tools/sign_glyphs.py bakes every word here into data/sign_glyphs.json, so the game draws them as it draws a sign's.

    python3 tools/border_words.py        # writes data/border_words.json

    {"format": 1, "countries": {CODE: {"name": "ESPAÑA", "welcome": "BIENVENIDOS", "script": "Latn"}, ...}}

A country's name is Natural Earth's in its language where it has one (NAME_xx), else the table below, else its
English name; a language written in a script the game has no font for (sign_glyphs.FONT_OF) has the English board
("WELCOME" and its English name). Latin, Cyrillic and Greek words are in capitals, as the boards have them.

Natural Earth is public domain (the country names); cached in the project files' ride-anywhere-v2/cache/naturalearth.
"""
import json
import os
import unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "border_words.json")
COUNTRIES = os.path.join(ROOT, "data", "countries.json")
NE = "/mnt/project-files/torque-shed/ride-anywhere-v2/cache/naturalearth/ne_10m_admin_0_countries.geojson"
FORMAT = 1
# The scripts sign_glyphs.py has a font for.
SCRIPTS = ("Latn", "Cyrl", "Grek", "Arab", "Thai", "Jpan", "Kore", "Hans", "Hant")
# Natural Earth's name columns, by language.
NE_NAMES = {"ar": "NAME_AR", "de": "NAME_DE", "en": "NAME_EN", "es": "NAME_ES", "fa": "NAME_FA", "fr": "NAME_FR",
            "el": "NAME_EL", "hu": "NAME_HU", "id": "NAME_ID", "it": "NAME_IT", "ja": "NAME_JA", "ko": "NAME_KO",
            "nl": "NAME_NL", "pl": "NAME_PL", "pt": "NAME_PT", "ru": "NAME_RU", "sv": "NAME_SV", "tr": "NAME_TR",
            "uk": "NAME_UK", "ur": "NAME_UR", "vi": "NAME_VI", "zh": "NAME_ZH"}
# The welcome, by language (an English board where a language isn't here).
WELCOME = {
    "en": "WELCOME", "fr": "BIENVENUE", "es": "BIENVENIDOS", "pt": "BEM-VINDOS", "it": "BENVENUTI", "de": "WILLKOMMEN",
    "nl": "WELKOM", "sv": "VÄLKOMMEN", "no": "VELKOMMEN", "da": "VELKOMMEN", "fi": "TERVETULOA", "is": "VELKOMIN",
    "fo": "VÆLKOMIN", "et": "TERE TULEMAST", "lv": "LAIPNI LŪDZAM", "lt": "SVEIKI ATVYKĘ", "pl": "WITAMY",
    "cs": "VÍTEJTE", "sk": "VITAJTE", "sl": "DOBRODOŠLI", "hr": "DOBRO DOŠLI", "bs": "DOBRO DOŠLI",
    "sr": "DOBRO DOŠLI", "sr-Cyrl": "ДОБРО ДОШЛИ", "hu": "ÜDVÖZÖLJÜK", "ro": "BINE AȚI VENIT", "bg": "ДОБРЕ ДОШЛИ",
    "mk": "ДОБРЕДОЈДОВТЕ", "ru": "ДОБРО ПОЖАЛОВАТЬ", "uk": "ЛАСКАВО ПРОСИМО", "be": "ЛАСКАВА ПРОСІМ",
    "el": "ΚΑΛΩΣ ΗΡΘΑΤΕ", "tr": "HOŞ GELDİNİZ", "sq": "MIRË SE VINI", "mt": "MERĦBA", "ca": "BENVINGUTS",
    "ar": "أهلا وسهلا", "fa": "خوش آمدید", "ps": "ښه راغلاست", "ur": "خوش آمدید", "zh-Hans": "欢迎", "zh-Hant": "歡迎",
    "ja": "ようこそ", "ko": "환영합니다", "th": "ยินดีต้อนรับ", "ms": "SELAMAT DATANG", "id": "SELAMAT DATANG",
    "vi": "CHÀO MỪNG", "tl": "MABUHAY", "sw": "KARIBU", "az": "XOŞ GƏLMİSİNİZ", "kk": "ҚОШ КЕЛДІҢІЗ",
    "ky": "КОШ КЕЛИҢИЗ", "mn": "ТАВТАЙ МОРИЛНО УУ", "tg": "ХУШ ОМАДЕД", "tk": "HOŞ GELDIŇIZ", "uz": "XUSH KELIBSIZ",
    "kl": "TIKILLUARIT", "mg": "TONGA SOA", "rw": "MURAKAZA NEZA", "so": "SOO DHAWOW", "to": "TALITALI FIEFIA",
    "sm": "AFIO MAI", "bi": "WELKAM",
}
# Countries' own names Natural Earth hasn't in their language, by code.
OWN_NAMES = {
    "CZ": "ČESKO", "SK": "SLOVENSKO", "SI": "SLOVENIJA", "HR": "HRVATSKA", "RS": "СРБИЈА", "BA": "BOSNA I HERCEGOVINA",
    "ME": "CRNA GORA", "BG": "БЪЛГАРИЯ", "RO": "ROMÂNIA", "MD": "MOLDOVA", "DK": "DANMARK", "NO": "NORGE", "FI": "SUOMI",
    "IS": "ÍSLAND", "FO": "FØROYAR", "EE": "EESTI", "LV": "LATVIJA", "LT": "LIETUVA", "AL": "SHQIPËRIA",
    "XK": "KOSOVA", "MK": "СЕВЕРНА МАКЕДОНИЈА", "BY": "БЕЛАРУСЬ", "AD": "ANDORRA", "MT": "MALTA", "AZ": "AZƏRBAYCAN",
    "KZ": "ҚАЗАҚСТАН", "KG": "КЫРГЫЗСТАН", "MN": "МОНГОЛ УЛС", "TJ": "ТОҶИКИСТОН", "TM": "TÜRKMENISTAN",
    "UZ": "OʻZBEKISTON", "MY": "MALAYSIA", "BN": "BRUNEI", "TH": "ประเทศไทย", "AF": "افغانستان", "PH": "PILIPINAS",
    "TZ": "TANZANIA", "KE": "KENYA", "GL": "KALAALLIT NUNAAT", "MG": "MADAGASIKARA", "RW": "RWANDA", "SO": "SOOMAALIYA",
    "US": "UNITED STATES", "TO": "TONGA", "WS": "SAMOA", "VU": "VANUATU", "TW": "臺灣", "HK": "香港", "MO": "澳門", "CN": "中国",
}
CASED = ("Latn", "Cyrl", "Grek")


def words(countries, ne_names):
    out = {}
    for code, f in sorted(countries.items()):
        lang = str(f.get("language", "en"))
        script = str(f.get("script", "Latn"))
        english = str(f.get("name", code))
        key = lang + "-" + script if lang + "-" + script in WELCOME else lang
        if script not in SCRIPTS or key not in WELCOME:
            out[code] = {"name": english.upper(), "welcome": WELCOME["en"], "script": "Latn"}
            continue
        name = OWN_NAMES.get(code) or ne_names.get(code, {}).get(lang) or english
        if script in CASED:
            name = name.upper()
        if script == "Grek":
            # (Greek capitals carry no accents)
            name = unicodedata.normalize("NFC", "".join(ch for ch in unicodedata.normalize("NFD", name)
                                                        if unicodedata.category(ch) != "Mn"))
        out[code] = {"name": name, "welcome": WELCOME[key], "script": script}
    return out


def ne_names_of(path):
    got = {}
    for ft in json.load(open(path))["features"]:
        p = ft["properties"]
        code = p.get("ISO_A2_EH") if p.get("ISO_A2_EH") not in (None, "-99") else p.get("ISO_A2")
        if not code or code == "-99":
            continue
        # (a code used twice, a country's and a far territory's: the one with more people)
        if code in got and float(p.get("POP_EST") or 0) <= got[code][0]:
            continue
        got[code] = (float(p.get("POP_EST") or 0), {lang: p[col] for lang, col in NE_NAMES.items() if p.get(col)})
    return {code: v[1] for code, v in got.items()}


def main():
    countries = json.load(open(COUNTRIES))["countries"]
    out = {"format": FORMAT, "countries": words(countries, ne_names_of(NE))}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, sort_keys=True, indent=0)
        f.write("\n")
    print("border words: %d countries" % len(out["countries"]))


if __name__ == "__main__":
    main()
