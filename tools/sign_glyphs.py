"""The words painted on signs and roads, and written over shops, as flat triangles: data/sign_glyphs.json.

    pip install fonttools uharfbuzz mapbox_earcut
    python3 tools/sign_glyphs.py [font_dir]     # writes data/sign_glyphs.json

Each word is shaped by HarfBuzz (so Arabic joins up and Thai marks sit where they should) in Noto Sans Bold, in the
script the word is written in, and its outline is cut into triangles. The game draws them as plain geometry in the
sign's or road paint's own colour, so it ships no fonts: only the words it uses.

A word's triangles are in em (the font's size), x from 0 at its start to "w", y up from the baseline, with "top" and
"bottom" the highest and lowest any of it reaches.

The fonts are Noto Sans, Noto Sans Arabic, Thai, JP, KR and SC (SIL Open Font License 1.1, from github.com/google/fonts,
cached in the project files' ride-anywhere-v2/cache/fonts). Outlines made from them stay under the OFL: see
data/sign_glyphs.licence.txt.
"""
import json
import os
import sys

import mapbox_earcut
import numpy
import uharfbuzz as hb
from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "data", "sign_glyphs.json")
FONTS = "/mnt/project-files/torque-shed/ride-anywhere-v2/cache/fonts"
FORMAT = 1
WEIGHT = 700
# Curves are cut into straight pieces at most this far (in em) from the curve.
TOLERANCE = 0.012

FONT_OF = {
    "Latn": "NotoSans[wdth,wght].ttf", "Cyrl": "NotoSans[wdth,wght].ttf", "Grek": "NotoSans[wdth,wght].ttf",
    "Arab": "NotoSansArabic[wdth,wght].ttf", "Thai": "NotoSansThai[wdth,wght].ttf",
    "Jpan": "NotoSansJP[wght].ttf", "Kore": "NotoSansKR[wght].ttf", "Hans": "NotoSansSC[wght].ttf",
    "Hant": "NotoSansSC[wght].ttf",
}

# The words, by script. Stop signs' words (data/countries.json "stop"), words painted on the road ("road_words"), and
# shop fronts' (RegionCity's fascias, by language).
WORDS = {
    "Latn": ["STOP", "ALTO", "PARE", "DUR", "SLOW", "STOP", "KEEP CLEAR", "BUS", "SCHOOL", "XING",
             "CAFE", "CAFÉ", "BAR", "PUB", "HOTEL", "BANK", "PHARMACY", "BAKERY", "BUTCHER", "NEWS", "GARAGE",
             "TAKEAWAY", "POST OFFICE", "INN", "DINER", "MOTEL", "LIQUOR", "DELI", "LAUNDROMAT", "HARDWARE",
             "BOULANGERIE", "PHARMACIE", "TABAC", "BOUCHERIE", "BRASSERIE", "BOULANGERIE-PÂTISSERIE", "ÉPICERIE",
             "BÄCKEREI", "APOTHEKE", "METZGEREI", "GASTHAUS", "KIOSK", "FRISEUR",
             "BAKKERIJ", "APOTHEEK", "SLAGERIJ", "FIETSEN", "CAFÉ", "SNACKBAR",
             "PANADERÍA", "FARMACIA", "CARNICERÍA", "TIENDA", "ABARROTES", "TAQUERÍA", "PAPELERÍA", "REFACCIONARIA",
             "PADARIA", "MERCADO", "AÇOUGUE", "LANCHONETE",
             "PANETTERIA", "MACELLERIA", "TABACCHI", "GELATERIA", "TRATTORIA", "ALIMENTARI",
             "BAGERI", "APOTEK", "KONDITORI", "KAFFE", "BAKERI", "KAHVILA", "LEIPOMO", "APTEEKKI",
             "PIEKARNIA", "APTEKA", "SKLEP", "PEKÁRNA", "LÉKÁRNA", "ÉLELMISZER", "PATIKA",
             "FIRIN", "ECZANE", "KASAP", "BAKKAL", "LOKANTA",
             "DAIRY", "BOTTLE STORE", "TAKEAWAYS", "FISH & CHIPS",
             "WARUNG", "TOKO", "APOTEK", "KEDAI", "KOPITIAM", "SARI-SARI", "BOTIKA", "CÀ PHÊ", "PHỞ", "TIỆM",
             "BOUTIQUE", "ALIMENTATION", "SUPERETTE", "CAFÉ DES SPORTS", "SPAZA", "BUTCHERY", "SALON",
             "HOSPEDAJE", "FERRETERÍA", "PULPERÍA", "DROGUERÍA", "SODA"],
    "Cyrl": ["СТОП", "АПТЕКА", "ПРОДУКТЫ", "ХЛЕБ", "КАФЕ", "МАГАЗИН", "ПЕКАРНА", "ПРОДАВНИЦА", "МАРКЕТ", "ЗОГС",
             "ЛАВКА", "ГАСТРОНОМ", "АПТЕКА", "ХЛІБ", "ПРОДУКТИ"],
    "Grek": ["ΣΤΟΠ", "ΦΑΡΜΑΚΕΙΟ", "ΚΑΦΕΝΕΙΟ", "ΦΟΥΡΝΟΣ", "ΤΑΒΕΡΝΑ", "ΠΑΝΤΟΠΩΛΕΙΟ"],
    "Arab": ["قف", "صيدلية", "مقهى", "مخبزة", "مطعم", "بقالة", "حانوت", "جزار", "مخبز", "ایست", "داروخانه", "نانوایی",
             "بقالی", "قهوه خانه"],
    "Thai": ["หยุด", "ร้านกาแฟ", "ร้านขายยา", "ร้านอาหาร", "ร้านค้า", "ช้า"],
    "Jpan": ["止まれ", "薬局", "喫茶", "食堂", "酒", "ラーメン", "パン", "コンビニ", "床屋", "そば", "うどん", "居酒屋"],
    "Kore": ["정지", "약국", "카페", "식당", "편의점", "빵집", "천천히"],
    "Hans": ["停", "药店", "饭店", "超市", "茶馆", "面馆", "商店", "慢", "藥房", "茶餐廳", "麵包", "士多"],
}


class FlatPen(BasePen):
    """Records a glyph's contours as lists of points, its curves cut into straight pieces."""

    def __init__(self, glyphset, step):
        super().__init__(glyphset)
        self.step = step
        self.contours = []
        self.cur = []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        n = self._pieces(p0, p3, p1, p2)
        for k in range(1, n + 1):
            t = k / n
            u = 1 - t
            self.cur.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                             u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        n = self._pieces(p0, p2, p1)
        for k in range(1, n + 1):
            t = k / n
            u = 1 - t
            self.cur.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                             u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))

    def _pieces(self, a, b, *ctrl):
        # How far the control points stand off the chord says how many pieces keep within the tolerance.
        dev = 0.0
        for c in ctrl:
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = (dx * dx + dy * dy) ** 0.5 or 1.0
            dev = max(dev, abs((c[0] - a[0]) * dy - (c[1] - a[1]) * dx) / L)
        return max(1, min(12, int((dev / self.step) ** 0.5 * 1.5) + 1))

    def _closePath(self):
        if len(self.cur) > 2:
            if self.cur[0] == self.cur[-1]:
                self.cur.pop()
            self.contours.append(self.cur)
        self.cur = []

    _endPath = _closePath


def area(c):
    return 0.5 * sum(c[k][0] * c[(k + 1) % len(c)][1] - c[(k + 1) % len(c)][0] * c[k][1] for k in range(len(c)))


def inside(p, c):
    x, y = p
    hit = False
    for k in range(len(c)):
        x0, y0 = c[k]
        x1, y1 = c[(k + 1) % len(c)]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def triangles(contours):
    """Fills contours by the nonzero rule as outlines with their holes: flat [x, y, x, y, ...] per triangle corner."""
    contours = [c for c in contours if abs(area(c)) > 1e-9]
    if not contours:
        return []
    # The outer contours wind one way (the way the biggest does), holes the other.
    sign = 1 if area(max(contours, key=lambda c: abs(area(c)))) > 0 else -1
    outers = [c for c in contours if area(c) * sign > 0]
    holes = [c for c in contours if area(c) * sign < 0]
    groups = {id(o): [] for o in outers}
    for h in holes:
        best = None
        for o in outers:
            if inside(h[0], o) and (best is None or abs(area(o)) < abs(area(best))):
                best = o
        if best is not None:
            groups[id(best)].append(h)
    out = []
    for o in outers:
        rings = [o] + groups[id(o)]
        verts = numpy.array([p for r in rings for p in r], dtype=numpy.float64).reshape(-1, 2)
        ends = numpy.cumsum([len(r) for r in rings]).astype(numpy.uint32)
        idx = mapbox_earcut.triangulate_float64(verts, ends)
        for i in idx:
            out.extend([round(float(verts[i][0]), 3), round(float(verts[i][1]), 3)])
    return out


def word(path, text):
    blob = hb.Blob.from_file_path(path)
    face = hb.Face(blob)
    font = hb.Font(face)
    upem = face.upem
    tt = TTFont(path)
    loc = {}
    if "fvar" in tt:
        axes = {a.axisTag: a for a in tt["fvar"].axes}
        if "wght" in axes:
            loc["wght"] = min(max(WEIGHT, axes["wght"].minValue), axes["wght"].maxValue)
        font.set_variations(loc)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf, {})
    glyphs = tt.getGlyphSet(location=loc) if loc else tt.getGlyphSet()
    order = tt.getGlyphOrder()
    contours = []
    x = 0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        pen = FlatPen(glyphs, TOLERANCE * upem)
        glyphs[order[info.codepoint]].draw(pen)
        ox = x + pos.x_offset
        oy = pos.y_offset
        for c in pen.contours:
            contours.append([((px + ox) / upem, (py + oy) / upem) for px, py in c])
        x += pos.x_advance
    tris = triangles(contours)
    ys = tris[1::2] or [0.0]
    return {"w": round(x / upem, 4), "top": max(ys), "bottom": min(ys), "tris": tris}


def main():
    fonts = sys.argv[1] if len(sys.argv) > 1 else FONTS
    out = {}
    for script, words in WORDS.items():
        path = os.path.join(fonts, FONT_OF[script])
        for w in words:
            if w not in out:
                out[w] = word(path, w)
    with open(OUT, "w") as f:
        f.write('{\n\t"format": %d,\n\t"words": {\n' % FORMAT)
        rows = ['\t\t%s: %s' % (json.dumps(w, ensure_ascii=False), json.dumps(g, separators=(",", ":")))
                for w, g in sorted(out.items())]
        f.write(",\n".join(rows))
        f.write("\n\t}\n}\n")
    n = sum(len(g["tris"]) // 6 for g in out.values())
    print("%d words, %d triangles, %d KB -> %s" % (len(out), n, os.path.getsize(OUT) // 1024, os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
