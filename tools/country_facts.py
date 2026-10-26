"""The country facts table, data/countries.json: what differs from country to country inside a region kit.

    python3 tools/country_facts.py        # writes data/countries.json

Every country the world's towns name (data/world/countries.json) gets a row: its region kit (one of REGIONS, which
RegionKit draws its buildings and furniture from), the side of the road it drives on, its speed and distance units,
its road paint (the centre line's colour, the edge line's), its warning sign shape and speed limit sign, its language
and script (for shop fronts and place names), its places of worship by kind and share, its roadside posts and kerb
paint, and how often its towns have speed bumps. Nothing here is chosen by a player: a cell's profile names its
country and the country names its kit.

The facts are general knowledge of each country's roads and towns (no data source to credit). Where a fact is the
same across most of a region, the region's default holds and only the countries that differ are listed.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "data", "countries.json")
FORMAT = 1

# The region kits (data/region_kits.json), in the plan's order, and the countries in each.
REGIONS = {
    "british_isles": "GB IE IM JE GG FK GS SH",
    "western_europe": "FR DE NL BE LU AT CH LI SI",
    "nordic": "NO SE FI DK IS FO GL AX SJ EE LV LT AQ",
    "eastern_europe": "PL CZ SK HU RO BG RS MD UA BY RU GE AM",
    "mediterranean": "ES PT IT GR MT CY SM VA AD MC GI HR BA ME AL MK XK TR",
    "north_africa_middle_east": "MA DZ TN LY EG EH MR SD SA AE OM YE QA BH KW IQ IR SY JO LB IL PS AF KZ UZ TM TJ KG AZ",
    "sub_saharan_africa": ("NE ML TD SN GM GW GN SL LR CI GH TG BJ BF NG CM CF GQ GA CG CD AO ZM ZW MW MZ TZ KE UG RW BI "
                           "SS ET ER DJ SO NA BW ZA LS SZ MG MU SC KM CV ST"),
    "north_america": "US CA BM",
    "latin_america": ("MX GT BZ HN SV NI CR PA CU JM HT DO PR BS TT BB AG DM LC VC GD KN AW CW SX TC KY VG VI AI MS "
                      "CO VE GY SR EC PE BO BR PY UY AR CL"),
    "south_asia": "IN PK BD LK NP BT MV",
    "east_asia": "CN JP KR KP TW HK MO MN",
    "south_east_asia": "TH VN LA KH MM MY SG ID PH BN TL",
    "australia_nz": "AU NZ FJ PG SB VU NC PF WS TO KI TV FM MH PW GU MP AS CK NU TK",
}

LEFT = set(("AG AI AU BB BD BM BN BS BT BW CK CY DM FJ FK GB GD GG GY HK ID IE IM IN JE JM JP KE KI KN KY LC LK LS "
            "MO MS MT MU MV MW MY MZ NA NP NU NZ PG PK SB SC SG SH SR SZ TC TH TK TL TO TT TV TZ UG VC VG VI WS ZA "
            "ZM ZW").split())
MPH = set("GB IM JE GG FK SH US PR VI LR BS BZ AG DM LC VC GD KN KY VG AI MS TC WS".split())
MILES = set("GB IM JE GG FK SH US PR VI LR BS AG DM LC VC GD KN KY VG AI MS TC WS".split())

# Road paint: the centre line is white unless listed (the Americas, Norway and Finland, China, Korea, Taiwan,
# Thailand paint it yellow); the edge line is white, or yellow (Ireland, southern Africa), or none where few roads
# have one.
YELLOW_CENTRE = set(("US CA MX GT BZ HN SV NI CR PA CO VE EC PE BO BR PY UY AR CL DO PR NO FI CN KR KP TW TH "
                     "IS").split())
YELLOW_EDGE = set("IE ZA NA BW ZW LS SZ".split())
NO_EDGE = set(("AF IQ SY YE LY SD SS TD NE ML MR CF CD CG GQ GA CM BI RW ET ER SO DJ MG KM HT CU NP BT MM LA KH TL "
               "PG SB VU KP").split())
# Warning signs: a red-bordered triangle everywhere but where they're a yellow diamond.
DIAMOND = set(("US CA MX GT BZ HN SV NI CR PA CO VE EC PE BO BR PY UY AR CL DO PR AU NZ PG FJ IE JP TH MY ID PH "
               "BN LR").split())
# Speed limit signs: the red ring, but a white rectangle in the United States and Canada.
RECT_LIMIT = set("US CA".split())

# Language (ISO 639-1) and script (ISO 15924) of the shop fronts.
LANG = {
    "GB": "en Latn", "IE": "en Latn", "IM": "en Latn", "JE": "en Latn", "GG": "en Latn", "FK": "en Latn",
    "GS": "en Latn", "SH": "en Latn",
    "FR": "fr Latn", "DE": "de Latn", "NL": "nl Latn", "BE": "nl Latn", "LU": "fr Latn", "AT": "de Latn",
    "CH": "de Latn", "LI": "de Latn", "SI": "sl Latn",
    "NO": "no Latn", "SE": "sv Latn", "FI": "fi Latn", "DK": "da Latn", "IS": "is Latn", "FO": "fo Latn",
    "GL": "kl Latn", "AX": "sv Latn", "SJ": "no Latn", "EE": "et Latn", "LV": "lv Latn", "LT": "lt Latn",
    "AQ": "en Latn",
    "PL": "pl Latn", "CZ": "cs Latn", "SK": "sk Latn", "HU": "hu Latn", "RO": "ro Latn", "BG": "bg Cyrl",
    "RS": "sr Cyrl", "MD": "ro Latn", "UA": "uk Cyrl", "BY": "be Cyrl", "RU": "ru Cyrl", "GE": "ka Geor",
    "AM": "hy Armn",
    "ES": "es Latn", "PT": "pt Latn", "IT": "it Latn", "GR": "el Grek", "MT": "mt Latn", "CY": "el Grek",
    "SM": "it Latn", "VA": "it Latn", "AD": "ca Latn", "MC": "fr Latn", "GI": "en Latn", "HR": "hr Latn",
    "BA": "bs Latn", "ME": "sr Latn", "AL": "sq Latn", "MK": "mk Cyrl", "XK": "sq Latn", "TR": "tr Latn",
    "MA": "ar Arab", "DZ": "ar Arab", "TN": "ar Arab", "LY": "ar Arab", "EG": "ar Arab", "EH": "ar Arab",
    "MR": "ar Arab", "SD": "ar Arab", "SA": "ar Arab", "AE": "ar Arab", "OM": "ar Arab", "YE": "ar Arab",
    "QA": "ar Arab", "BH": "ar Arab", "KW": "ar Arab", "IQ": "ar Arab", "IR": "fa Arab", "SY": "ar Arab",
    "JO": "ar Arab", "LB": "ar Arab", "IL": "he Hebr", "PS": "ar Arab", "AF": "ps Arab", "KZ": "kk Cyrl",
    "UZ": "uz Latn", "TM": "tk Latn", "TJ": "tg Cyrl", "KG": "ky Cyrl", "AZ": "az Latn",
    "NE": "fr Latn", "ML": "fr Latn", "TD": "fr Latn", "SN": "fr Latn", "GM": "en Latn", "GW": "pt Latn",
    "GN": "fr Latn", "SL": "en Latn", "LR": "en Latn", "CI": "fr Latn", "GH": "en Latn", "TG": "fr Latn",
    "BJ": "fr Latn", "BF": "fr Latn", "NG": "en Latn", "CM": "fr Latn", "CF": "fr Latn", "GQ": "es Latn",
    "GA": "fr Latn", "CG": "fr Latn", "CD": "fr Latn", "AO": "pt Latn", "ZM": "en Latn", "ZW": "en Latn",
    "MW": "en Latn", "MZ": "pt Latn", "TZ": "sw Latn", "KE": "sw Latn", "UG": "en Latn", "RW": "rw Latn",
    "BI": "fr Latn", "SS": "en Latn", "ET": "am Ethi", "ER": "ti Ethi", "DJ": "fr Latn", "SO": "so Latn",
    "NA": "en Latn", "BW": "en Latn", "ZA": "en Latn", "LS": "en Latn", "SZ": "en Latn", "MG": "mg Latn",
    "MU": "fr Latn", "SC": "fr Latn", "KM": "fr Latn", "CV": "pt Latn", "ST": "pt Latn",
    "US": "en Latn", "CA": "en Latn", "BM": "en Latn",
    "MX": "es Latn", "GT": "es Latn", "BZ": "en Latn", "HN": "es Latn", "SV": "es Latn", "NI": "es Latn",
    "CR": "es Latn", "PA": "es Latn", "CU": "es Latn", "JM": "en Latn", "HT": "fr Latn", "DO": "es Latn",
    "PR": "es Latn", "BS": "en Latn", "TT": "en Latn", "BB": "en Latn", "AG": "en Latn", "DM": "en Latn",
    "LC": "en Latn", "VC": "en Latn", "GD": "en Latn", "KN": "en Latn", "AW": "nl Latn", "CW": "nl Latn",
    "SX": "nl Latn", "TC": "en Latn", "KY": "en Latn", "VG": "en Latn", "VI": "en Latn", "AI": "en Latn",
    "MS": "en Latn", "CO": "es Latn", "VE": "es Latn", "GY": "en Latn", "SR": "nl Latn", "EC": "es Latn",
    "PE": "es Latn", "BO": "es Latn", "BR": "pt Latn", "PY": "es Latn", "UY": "es Latn", "AR": "es Latn",
    "CL": "es Latn",
    "IN": "hi Deva", "PK": "ur Arab", "BD": "bn Beng", "LK": "si Sinh", "NP": "ne Deva", "BT": "dz Tibt",
    "MV": "dv Thaa",
    "CN": "zh Hans", "JP": "ja Jpan", "KR": "ko Kore", "KP": "ko Kore", "TW": "zh Hant", "HK": "zh Hant",
    "MO": "zh Hant", "MN": "mn Cyrl",
    "TH": "th Thai", "VN": "vi Latn", "LA": "lo Laoo", "KH": "km Khmr", "MM": "my Mymr", "MY": "ms Latn",
    "SG": "en Latn", "ID": "id Latn", "PH": "tl Latn", "BN": "ms Latn", "TL": "pt Latn",
    "AU": "en Latn", "NZ": "en Latn", "FJ": "en Latn", "PG": "en Latn", "SB": "en Latn", "VU": "bi Latn",
    "NC": "fr Latn", "PF": "fr Latn", "WS": "sm Latn", "TO": "to Latn", "KI": "en Latn", "TV": "en Latn",
    "FM": "en Latn", "MH": "en Latn", "PW": "en Latn", "GU": "en Latn", "MP": "en Latn", "AS": "en Latn",
    "CK": "en Latn", "NU": "en Latn", "TK": "en Latn",
}

# Places of worship by kind (RegionBuildings draws each) and the share of them; a region's default, then countries.
WORSHIP_REGION = {
    "british_isles": {"church": 1.0},
    "western_europe": {"church": 1.0},
    "nordic": {"chapel": 1.0},
    "eastern_europe": {"orthodox": 1.0},
    "mediterranean": {"campanile": 1.0},
    "north_africa_middle_east": {"mosque": 1.0},
    "sub_saharan_africa": {"church": 0.7, "mosque": 0.3},
    "north_america": {"chapel": 0.6, "church": 0.4},
    "latin_america": {"mission": 1.0},
    "south_asia": {"mandir": 0.8, "mosque": 0.15, "church": 0.05},
    "east_asia": {"temple": 1.0},
    "south_east_asia": {"wat": 1.0},
    "australia_nz": {"chapel": 0.7, "church": 0.3},
}
WORSHIP = {
    "PL": {"church": 1.0}, "CZ": {"church": 1.0}, "SK": {"church": 1.0}, "HU": {"church": 1.0},
    "LT": {"church": 1.0}, "EE": {"chapel": 0.7, "orthodox": 0.3}, "LV": {"chapel": 0.6, "orthodox": 0.4},
    "GR": {"orthodox": 1.0}, "CY": {"orthodox": 1.0}, "MK": {"orthodox": 0.7, "mosque": 0.3},
    "ME": {"orthodox": 0.8, "mosque": 0.2}, "BA": {"mosque": 0.5, "orthodox": 0.3, "campanile": 0.2},
    "AL": {"mosque": 0.6, "campanile": 0.2, "orthodox": 0.2}, "XK": {"mosque": 0.9, "orthodox": 0.1},
    "TR": {"mosque": 1.0}, "HR": {"campanile": 1.0}, "GE": {"orthodox": 1.0}, "AM": {"orthodox": 1.0},
    "LB": {"mosque": 0.55, "church": 0.45}, "IL": {"synagogue": 0.8, "mosque": 0.2}, "EG": {"mosque": 0.9, "church": 0.1},
    "KZ": {"mosque": 0.7, "orthodox": 0.3},
    "NE": {"mosque": 1.0}, "ML": {"mosque": 1.0}, "TD": {"mosque": 0.6, "church": 0.4}, "SN": {"mosque": 1.0},
    "GM": {"mosque": 1.0}, "GN": {"mosque": 0.9, "church": 0.1}, "SL": {"mosque": 0.7, "church": 0.3},
    "BF": {"mosque": 0.6, "church": 0.4}, "NG": {"mosque": 0.5, "church": 0.5}, "SO": {"mosque": 1.0},
    "DJ": {"mosque": 1.0}, "KM": {"mosque": 1.0}, "SD": {"mosque": 1.0}, "MR": {"mosque": 1.0},
    "ET": {"orthodox": 0.6, "mosque": 0.4}, "ER": {"orthodox": 0.5, "mosque": 0.5}, "TZ": {"church": 0.6, "mosque": 0.4},
    "CI": {"mosque": 0.45, "church": 0.55}, "MU": {"mandir": 0.5, "church": 0.3, "mosque": 0.2},
    "BR": {"mission": 0.6, "chapel": 0.4}, "GY": {"chapel": 0.6, "mandir": 0.3, "mosque": 0.1},
    "SR": {"chapel": 0.5, "mandir": 0.3, "mosque": 0.2}, "TT": {"chapel": 0.6, "mandir": 0.3, "mosque": 0.1},
    "JM": {"chapel": 1.0}, "BS": {"chapel": 1.0}, "BB": {"chapel": 1.0}, "BZ": {"chapel": 0.6, "mission": 0.4},
    "PK": {"mosque": 1.0}, "BD": {"mosque": 0.9, "mandir": 0.1}, "MV": {"mosque": 1.0},
    "LK": {"stupa": 0.7, "mandir": 0.15, "mosque": 0.1, "church": 0.05}, "NP": {"mandir": 0.8, "stupa": 0.2},
    "BT": {"stupa": 1.0}, "JP": {"shrine": 0.6, "temple": 0.4}, "KR": {"church": 0.5, "temple": 0.5},
    "MN": {"stupa": 1.0}, "VN": {"pagoda": 0.8, "church": 0.2}, "MM": {"stupa": 1.0},
    "MY": {"mosque": 0.7, "temple": 0.2, "mandir": 0.1}, "BN": {"mosque": 1.0}, "SG": {"temple": 0.5, "mosque": 0.3, "church": 0.2},
    "ID": {"mosque": 0.9, "church": 0.1}, "PH": {"mission": 1.0}, "TL": {"mission": 1.0},
    "PG": {"chapel": 1.0}, "FJ": {"chapel": 0.6, "mandir": 0.3, "mosque": 0.1},
}

# Roadside posts (RegionKit draws each style) along the open road, a region's default, then countries'.
POSTS_REGION = {
    "british_isles": "uk", "western_europe": "leitpfosten", "nordic": "nordic", "eastern_europe": "striped",
    "mediterranean": "balise", "north_africa_middle_east": "none", "sub_saharan_africa": "none",
    "north_america": "us", "latin_america": "none", "south_asia": "none", "east_asia": "delineator",
    "south_east_asia": "striped", "australia_nz": "guide",
}
POSTS = {
    "FR": "balise", "BE": "balise", "LU": "balise", "NL": "nl", "IE": "uk", "ES": "balise", "PT": "balise",
    "IT": "balise", "CZ": "leitpfosten", "SK": "leitpfosten", "PL": "leitpfosten", "HU": "leitpfosten",
    "SI": "leitpfosten", "HR": "leitpfosten", "MA": "none", "TR": "striped", "ZA": "guide", "NA": "guide",
    "BW": "guide", "MX": "none", "AR": "striped", "CL": "striped", "BR": "none", "CN": "striped",
    "KR": "delineator", "TW": "delineator", "MY": "striped", "TH": "striped",
}
# Kerb and verge-stone paint in towns and on bends: a pair of colours in blocks, or "none".
KERB_REGION = {
    "british_isles": "none", "western_europe": "none", "nordic": "none", "eastern_europe": "black_white",
    "mediterranean": "none", "north_africa_middle_east": "red_white", "sub_saharan_africa": "black_white",
    "north_america": "none", "latin_america": "yellow", "south_asia": "black_yellow", "east_asia": "none",
    "south_east_asia": "black_white", "australia_nz": "none",
}
KERB = {
    "EG": "black_white", "IR": "black_white", "TR": "black_white", "IL": "red_white", "GR": "none",
    "TH": "red_white", "ID": "black_white", "VN": "black_white", "CN": "black_white", "IN": "black_yellow",
    "LK": "black_white", "BR": "none", "AR": "none", "CL": "none", "UY": "none", "ZA": "none",
}
# Speed bumps (topes, sleeping policemen): how many to a kilometre through a town.
BUMPS_REGION = {
    "british_isles": 0.5, "western_europe": 0.5, "nordic": 0.3, "eastern_europe": 0.5, "mediterranean": 0.7,
    "north_africa_middle_east": 1.5, "sub_saharan_africa": 2.0, "north_america": 0.3, "latin_america": 3.0,
    "south_asia": 1.5, "east_asia": 0.3, "south_east_asia": 1.5, "australia_nz": 0.3,
}
BUMPS = {"JP": 0.1, "DE": 0.2, "AT": 0.2, "CH": 0.2, "AR": 1.5, "CL": 1.0, "UY": 1.0}


# Countries in a region that the world's towns don't name (or name under another code).
NAMES = {"AI": "Anguilla", "GG": "Guernsey", "JE": "Jersey", "MS": "Montserrat", "NL": "Netherlands",
         "SH": "Saint Helena", "SX": "Sint Maarten", "VG": "British Virgin Islands"}


def names():
    """Code -> English name: the world's towns' countries (the first name a code has), and every region's."""
    with open(os.path.join(ROOT, "data", "world", "countries.json")) as f:
        by_name = json.load(f)
    out = {}
    for name, code in by_name.items():
        if code not in NAMES:
            out.setdefault(code, name)
    out.update(NAMES)
    for codes in REGIONS.values():
        for c in codes.split():
            assert c in out, "%s has no name" % c
    return out


def table():
    region_of = {}
    for region, codes in REGIONS.items():
        for c in codes.split():
            assert c not in region_of, "%s is in two regions" % c
            region_of[c] = region
    out = {}
    for code, name in sorted(names().items()):
        region = region_of.get(code)
        assert region, "%s (%s) is in no region" % (code, name)
        lang, script = LANG.get(code, "en Latn").split()
        out[code] = {
            "name": name, "region": region,
            "drive": "left" if code in LEFT else "right",
            "speed": "mph" if code in MPH else "kmh",
            "distance": "mi" if code in MILES else "km",
            "centre": "yellow" if code in YELLOW_CENTRE else "white",
            "edge": "none" if code in NO_EDGE else ("yellow" if code in YELLOW_EDGE else "white"),
            "warning": "diamond" if code in DIAMOND else "triangle",
            "limit": "rect" if code in RECT_LIMIT else "ring",
            "language": lang, "script": script,
            "worship": WORSHIP.get(code, WORSHIP_REGION[region]),
            "posts": POSTS.get(code, POSTS_REGION[region]),
            "kerb": KERB.get(code, KERB_REGION[region]),
            "bumps": BUMPS.get(code, BUMPS_REGION[region]),
        }
    return {"format": FORMAT, "regions": list(REGIONS), "countries": out}


if __name__ == "__main__":
    t = table()
    with open(OUT, "w") as f:
        f.write("{\n")
        f.write('\t"format": %d,\n' % t["format"])
        f.write('\t"regions": %s,\n' % json.dumps(t["regions"]))
        f.write('\t"countries": {\n')
        rows = ['\t\t"%s": %s' % (c, json.dumps(v, ensure_ascii=False)) for c, v in t["countries"].items()]
        f.write(",\n".join(rows))
        f.write("\n\t}\n}\n")
    print("%d countries in %d regions -> %s" % (len(t["countries"]), len(t["regions"]), os.path.relpath(OUT, ROOT)))
