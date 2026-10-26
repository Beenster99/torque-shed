#!/usr/bin/env python3
"""The place profile of each cell of the world's grid: where it is (country and region), its climate (Köppen-Geiger zone
and the months' temperature, rain and sunshine), its land (the cover mix, altitude, sea and coast, how built up it is)
and, when asked, a small true-colour tint of its ground. The game reads them (scripts/place_profile.gd) to make a ride
look and sound like the place. The fields are set out in docs/place_profile.md.

    python3 tools/profile_bake.py LAT LON [--tint] [--out FILE]               # the cell at LAT, LON
    python3 tools/profile_bake.py --index WORLD/index.json --out WORLD [...]  # every cell of the world's index, as
                                                                              # WORLD/profile/cROW_COL.json, hashes in
                                                                              # the index's "profiles"

A cell whose profile was made from the same inputs (PROFILE_VERSION, the sources and whether it has a tint: its
"bake_key") is left as it is, so a re-bake only redoes what changed. Every source is global and read once into --cache
(about 600 MB): Natural Earth (public domain), Beck et al. (2023) Köppen-Geiger maps (CC BY 4.0), ESA WorldCover 2021 and
its Sentinel-2 composite (CC BY 4.0), CRU TS 4.09 (Open Government Licence) and the terrain tiles the cells already use.
Needs numpy, Pillow, rasterio and shapely."""
import argparse
import base64
import calendar
import concurrent.futures
import gzip
import hashlib
import io
import json
import math
import os
import sys
import threading
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import land_bake  # noqa: E402
import region_bake  # noqa: E402

FORMAT = 1
# Part of every profile's bake_key and hash: bump it when what a profile holds, or how it is worked out, changes.
PROFILE_VERSION = 1
SOURCES = {"country": "naturalearth-10m-5.1.1", "koppen": "beck2023-1km-1991-2020", "cover": "esa-worldcover-2021-v200",
           "sea": "naturalearth-10m-5.1.1", "altitude": "mapterhorn", "climate": "cru-ts-4.09-1991-2020",
           "tint": "esa-worldcover-s2-rgb-2021"}
CREDITS = ("Made with Natural Earth. Köppen-Geiger zones: Beck, H.E. et al. (2023), Scientific Data 10, 724 (CC BY 4.0). "
           "Land cover and ground colour: © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data "
           "(2021) processed by ESA WorldCover consortium (CC BY 4.0). Climate: CRU TS 4.09, Climatic Research Unit "
           "(University of East Anglia) and Met Office (Open Government Licence).")
# Natural Earth's towns name a few countries their own way (and New Zealand with a typo).
COUNTRY_ALIASES = {"Cape Verde": "CV", "Chatham Islands": "NZ", "Congo (Brazzaville)": "CG", "Congo (Kinshasa)": "CD",
                   "Curacao": "CW", "Guinea Bissau": "GW", "Kermadec Islands": "NZ", "Macau S.A.R": "MO",
                   "Necw Zealand": "NZ", "Northern Cyprus": "CY", "Sao Tome and Principe": "ST", "Somaliland": "SO",
                   "Svalbard and Jan Mayen Islands": "SJ", "Tokelau": "TK"}
USER_AGENT = "TorqueShed profile_bake (+https://github.com/Beenster99/torque-shed)"

KOPPEN = ["", "Af", "Am", "Aw", "BWh", "BWk", "BSh", "BSk", "Csa", "Csb", "Csc", "Cwa", "Cwb", "Cwc", "Cfa", "Cfb", "Cfc",
          "Dsa", "Dsb", "Dsc", "Dsd", "Dwa", "Dwb", "Dwc", "Dwd", "Dfa", "Dfb", "Dfc", "Dfd", "ET", "EF"]
# ESA WorldCover class -> the game's cover (land_bake.COVER).
WORLDCOVER = {10: "forest", 20: "shrub", 30: "grass", 40: "crop", 50: "urban", 60: "barren", 70: "barren", 80: "water",
              90: "wetland", 95: "wetland", 100: "grass"}
# altitude_band by the mean height (m) of the cell's land, and density by how much of it is built up: the first whose
# limit the value is under.
ALTITUDE_BANDS = [(300.0, "lowland"), (1000.0, "upland"), (2500.0, "mountain"), (math.inf, "high")]
# (WorldCover read at 160 m misses much of a scattered village: hence the low limits)
DENSITIES = [(0.0005, "wild"), (0.01, "rural"), (0.05, "village"), (0.2, "town"), (math.inf, "city")]
CLIMATE_KEYS = ["temp_c", "temp_min_c", "temp_max_c", "rain_mm", "rain_days", "sun_h"]
GRID = 16            # the cell sampled GRID x GRID for country, sea and altitude (about 1.7 km apart)
TINT_SIZE = 16
COVER_STEP = 16      # WorldCover read at 1/16 of its 10 m (its 160 m overview)


# ----- the profile from its parts (no data needed: what the tests check) -----

def koppen_of(codes):
    """The Köppen-Geiger code most of `codes` (Beck's numbers, 0 the sea) are; "" when none are land."""
    codes = np.asarray(codes).ravel()
    codes = codes[(codes > 0) & (codes < len(KOPPEN))]
    if len(codes) == 0:
        return ""
    return KOPPEN[int(np.bincount(codes).argmax())]


def cover_mix(counts, sea=0.0):
    """The share of the cell's land in each cover class (land_bake.COVER, summing to 1) from `counts` {WorldCover class:
    pixels}. WorldCover's water includes the sea: the `sea` share of the cell is taken off it first."""
    total = float(sum(counts.values()))
    mix = {name: 0.0 for name in land_bake.COVER}
    if total <= 0:
        mix["water" if sea >= 0.999 else "grass"] = 1.0
        return mix
    for cls, n in counts.items():
        name = WORLDCOVER.get(int(cls))
        if name:
            mix[name] += n / total
    mix["water"] = max(0.0, mix["water"] - sea)
    left = sum(mix.values())
    if left <= 1e-9:
        mix["water" if sea >= 0.999 else "grass"] = 1.0
        return mix
    out = {k: round(v / left, 3) for k, v in mix.items()}
    # (rounded, so the biggest takes up the difference and they still sum to 1)
    big = max(out, key=out.get)
    out[big] = round(out[big] + 1.0 - sum(out.values()), 3)
    return out


def band(value, bands):
    for limit, name in bands:
        if value < limit:
            return name
    return bands[-1][1]


def day_length(lat, month):
    """Hours from sunrise to sunset in the middle of `month` (1 to 12) at `lat` (FAO-56's)."""
    doy = [15, 46, 74, 105, 135, 162, 198, 228, 258, 288, 318, 344][month - 1]
    decl = 0.409 * math.sin(2.0 * math.pi * doy / 365.0 - 1.39)
    x = -math.tan(math.radians(lat)) * math.tan(decl)
    return 24.0 / math.pi * math.acos(max(-1.0, min(1.0, x)))


def sun_hours(cloud_pct, lat, month):
    """Bright sunshine hours in `month` from its mean cloud cover (%): the share of daylight in sun taken as 1 - cloud^1.5
    (a sky three quarters cloudy still has sun a third of the day), a touch less as the sun is low near its ends."""
    days = calendar.monthrange(2001, month)[1]
    c = min(1.0, max(0.0, cloud_pct / 100.0))
    return round((1.0 - c ** 1.5) * 0.95 * day_length(lat, month) * days)


def make_profile(cell, parts, tint=None):
    """A cell's profile (see docs/place_profile.md) from what was read for it. `parts`: countries [(code, name, share)],
    region (name, code), koppen codes, cover counts {WorldCover class: pixels}, sea share, coast, heights of its land,
    climate {key: 12 values}. `tint`: (size x size x 3 uint8) or None."""
    i, j = (int(v) for v in cell.split("_"))
    s, w, n, e = region_bake.cell_box(i, j)
    countries = sorted(parts.get("countries", []), key=lambda c: -c[2])
    sea = round(float(parts.get("sea", 0.0)), 3)
    cover = cover_mix(parts.get("cover", {}), sea)
    heights = np.asarray(parts.get("heights", []), dtype=float)
    if len(heights):
        alt = {"min": int(round(heights.min())), "mean": int(round(heights.mean())), "max": int(round(heights.max()))}
    else:
        alt = {"min": 0, "mean": 0, "max": 0}
    built = cover["urban"]
    climate = {k: [round(float(v), 1) if k.endswith("_c") else int(round(float(v))) for v in parts["climate"][k]]
               for k in CLIMATE_KEYS} if parts.get("climate") else None
    region = parts.get("region") or ("", "")
    p = {
        "format": FORMAT, "cell": cell, "lat": (s + n) / 2.0, "lon": (w + e) / 2.0, "guessed": False,
        "country": countries[0][0] if countries else "", "country_name": countries[0][1] if countries else "",
        "countries": [[c[0], round(c[2], 3)] for c in countries],
        "region": region[0], "region_code": region[1],
        "koppen": koppen_of(parts.get("koppen", [])),
        "cover": cover, "sea": sea, "coast": bool(parts.get("coast", 0.0 < sea < 1.0)),
        "altitude": alt, "altitude_band": band(alt["mean"], ALTITUDE_BANDS),
        "built": built, "density": band(built, DENSITIES),
        "climate": climate,
        "tint": tint_entry(tint) if tint is not None else None,
        "sources": {k: v for k, v in SOURCES.items() if k != "tint" or tint is not None},
    }
    p["bake_key"] = bake_key(tint is not None)
    p["hash"] = profile_hash(p)
    return p


def tint_entry(rgb):
    """The tint field: {size, rgb (the mean colour), png (base64, north up)} of a size x size x 3 uint8 image."""
    from PIL import Image
    buf = io.BytesIO()
    Image.fromarray(np.asarray(rgb, dtype=np.uint8), "RGB").save(buf, "PNG", optimize=True)
    mean = np.asarray(rgb, dtype=float).reshape(-1, 3).mean(0)
    return {"size": int(rgb.shape[0]), "rgb": [int(round(v)) for v in mean], "png": base64.b64encode(buf.getvalue()).decode()}


def to_srgb(reflectance):
    """Sentinel-2 surface reflectance (WorldCover's composite: 0 to 10000) as 8-bit colour, the way a true-colour image
    of the ground is usually shown (a gain, then a gamma)."""
    v = np.clip(np.asarray(reflectance, dtype=float) / 10000.0 * 3.2, 0.0, 1.0)
    return np.round(255.0 * v ** (1.0 / 1.8)).astype(np.uint8)


def bake_key(with_tint):
    """What a profile was made from: the same key, the same profile, so it need not be made again."""
    text = json.dumps([PROFILE_VERSION, FORMAT, {k: v for k, v in SOURCES.items() if k != "tint" or with_tint}],
                      sort_keys=True)
    return hashlib.sha1(text.encode()).hexdigest()[:12]


def profile_hash(p):
    """The profile's own hash (12 hex): of everything in it but the hash, with PROFILE_VERSION."""
    body = {k: v for k, v in p.items() if k != "hash"}
    text = json.dumps([PROFILE_VERSION, body], sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(text.encode()).hexdigest()[:12]


def profile_text(p):
    return json.dumps(p, separators=(",", ":"), ensure_ascii=False)


def text_hash(text):
    """The hash the index keeps for a profile file (as for the streams and trees: the sha1 of its text)."""
    return hashlib.sha1(text.encode()).hexdigest()[:12]


# ----- the sources -----

def fetch(url, path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=900) as r, open(path + ".part", "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
        os.replace(path + ".part", path)
    return path


class Places:
    """Countries, first-level regions and land from Natural Earth's 10m maps, asked by point."""
    NE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/%s.geojson"

    def __init__(self, cache):
        from shapely import STRtree
        from shapely.geometry import shape
        self.countries, self.regions = [], []
        for feat in self._load(cache, "ne_10m_admin_0_countries")["features"]:
            p = feat["properties"]
            code = p.get("ISO_A2_EH") or p.get("ISO_A2") or ""
            code = "" if code == "-99" else code
            self.countries.append((shape(feat["geometry"]), code, p.get("NAME_EN") or p.get("NAME") or ""))
        for feat in self._load(cache, "ne_10m_admin_1_states_provinces")["features"]:
            p = feat["properties"]
            code = p.get("iso_3166_2") or ""
            self.regions.append((shape(feat["geometry"]), p.get("name_en") or p.get("name") or "",
                                 "" if code.endswith("~") or "-" not in code else code, p.get("iso_a2") or ""))
        land = [shape(f["geometry"]) for f in self._load(cache, "ne_10m_land")["features"]]
        self.land = STRtree(land)
        self.ctree = STRtree([c[0] for c in self.countries])
        self.rtree = STRtree([r[0] for r in self.regions])

    def _load(self, cache, name):
        with open(fetch(self.NE % name, os.path.join(cache, "naturalearth", name + ".geojson"))) as f:
            return json.load(f)

    def nearest_country(self, lat, lon, reach=0.5):
        """The index of the country nearest (lat, lon) within `reach` degrees, or -1."""
        from shapely.geometry import Point
        pt = Point(lon, lat)
        k = self.ctree.nearest(pt)
        if k is None or self.countries[int(k)][0].distance(pt) > reach:
            return -1
        return int(k)

    def at(self, lats, lons):
        """For each point: (on land, country index or -1, region index or -1)."""
        from shapely import points
        pts = points(np.asarray(lons).ravel(), np.asarray(lats).ravel())
        on_land = np.zeros(len(pts), dtype=bool)
        country = np.full(len(pts), -1)
        region = np.full(len(pts), -1)
        a, b = self.land.query(pts, predicate="intersects")
        on_land[a] = True
        a, b = self.ctree.query(pts, predicate="intersects")
        country[a] = b
        a, b = self.rtree.query(pts, predicate="intersects")
        region[a] = b
        return on_land, country, region


class Koppen:
    URL = "https://ndownloader.figshare.com/files/61012822"
    MEMBER = "1991_2020/koppen_geiger_0p00833333.tif"

    def __init__(self, cache):
        import zipfile
        folder = os.path.join(cache, "koppen")
        tif = os.path.join(folder, self.MEMBER)
        if not os.path.exists(tif):
            with zipfile.ZipFile(fetch(self.URL, os.path.join(folder, "koppen_geiger_tif.zip"))) as z:
                z.extract(self.MEMBER, folder)
        self.tif = tif

    def codes(self, s, w, n, e):
        import rasterio
        from rasterio.windows import from_bounds
        with rasterio.open(self.tif) as ds:
            return ds.read(1, window=from_bounds(w, s, e, n, ds.transform), boundless=True, fill_value=0)


class Climate:
    """CRU TS 4.09's 1991 to 2020 monthly means on its 0.5 degree grid, worked out once and kept (climate.npz)."""
    URL = "https://crudata.uea.ac.uk/cru/data/hrg/cru_ts_4.09/cruts.2503051245.v4.09/%s/cru_ts4.09.%s.%s.dat.gz"
    DECADES = ["1991.2000", "2001.2010", "2011.2020"]
    # CRU variable -> (our key, scale of its stored integers)
    VARS = {"tmp": ("temp_c", 0.1), "tmn": ("temp_min_c", 0.1), "tmx": ("temp_max_c", 0.1), "pre": ("rain_mm", 0.1),
            "wet": ("rain_days", 0.01), "cld": ("cloud", 0.1)}

    def __init__(self, cache):
        folder = os.path.join(cache, "cru")
        npz = os.path.join(folder, "climate-1991-2020.npz")
        if not os.path.exists(npz):
            out = {}
            for var, (key, scale) in self.VARS.items():
                total = np.zeros((12, 360, 720))
                count = np.zeros((12, 360, 720))
                for dec in self.DECADES:
                    path = fetch(self.URL % (var, dec, var), os.path.join(folder, "cru_ts4.09.%s.%s.dat.gz" % (dec, var)))
                    a = self.read_dat(path)
                    for m in range(a.shape[0]):
                        ok = a[m] != -999
                        total[m % 12][ok] += a[m][ok] * scale
                        count[m % 12][ok] += 1
                with np.errstate(invalid="ignore"):
                    out[key] = np.where(count > 0, total / np.maximum(count, 1), np.nan).astype(np.float32)
            np.savez_compressed(npz + ".part.npz", **out)
            os.replace(npz + ".part.npz", npz)
        with np.load(npz) as z:
            self.grids = {k: z[k] for k in z.files}

    @staticmethod
    def read_dat(path):
        """A CRU .dat file: months x 360 rows (south first) x 720 columns (west first) of integers, -999 the sea."""
        with gzip.open(path, "rb") as f:
            a = np.loadtxt(f, dtype=np.int32)
        return a.reshape(-1, 360, 720)

    def at(self, lat, lon):
        """The 12 months of each value at (lat, lon): the nearest land grid point within a degree; None at sea."""
        r, c = int((lat + 90.0) / 0.5), int((lon + 180.0) / 0.5) % 720
        t = self.grids["temp_c"][0]
        for reach in range(3):
            best = None
            for dr in range(-reach, reach + 1):
                for dc in range(-reach, reach + 1):
                    rr, cc = r + dr, (c + dc) % 720
                    if 0 <= rr < 360 and not np.isnan(t[rr, cc]):
                        d = dr * dr + dc * dc
                        if best is None or d < best[0]:
                            best = (d, rr, cc)
            if best:
                _, rr, cc = best
                out = {k: [float(g[m, rr, cc]) for m in range(12)] for k, g in self.grids.items()}
                out["sun_h"] = [sun_hours(out["cloud"][m], lat, m + 1) for m in range(12)]
                del out["cloud"]
                return out
        return None


class WorldCover:
    """ESA WorldCover 2021 (its 3 degree map tiles) and its Sentinel-2 composite (1 degree tiles), each tile read once at
    a sixteenth of its resolution and kept as .npy."""
    MAP = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_%s_Map.tif"
    S2 = "https://esa-worldcover-s2.s3.eu-central-1.amazonaws.com/rgbnir/2021/%s/ESA_WorldCover_10m_2021_v200_%s_S2RGBNIR.tif"

    def __init__(self, cache):
        self.folder = os.path.join(cache, "worldcover")
        os.makedirs(self.folder, exist_ok=True)
        self._locks = {}
        self._lock = threading.Lock()

    @staticmethod
    def tile_name(lat, lon, size):
        """WorldCover's name for the `size` degree tile whose south-west corner is at or below (lat, lon): N54W003."""
        la = int(math.floor(lat / size) * size)
        lo = int(math.floor(lon / size) * size)
        return "%s%02d%s%03d" % ("N" if la >= 0 else "S", abs(la), "E" if lo >= 0 else "W", abs(lo)), la, lo

    def _tile(self, kind, lat, lon):
        size = 3 if kind == "map" else 1
        name, la, lo = self.tile_name(lat, lon, size)
        path = os.path.join(self.folder, kind, name + ".npy")
        with self._lock:
            lock = self._locks.setdefault(path, threading.Lock())
        with lock:
            return self._read_tile(kind, name, path), la, lo, size

    def _read_tile(self, kind, name, path):
        size = 3 if kind == "map" else 1
        if not os.path.exists(path):
            import rasterio
            url = self.MAP % name if kind == "map" else self.S2 % (name[:3], name)
            n = int(size * 12000 / COVER_STEP)
            try:
                with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_MAX_RETRY="4",
                                  GDAL_HTTP_RETRY_DELAY="2"):
                    with rasterio.open("/vsicurl/" + url) as ds:
                        if kind == "map":
                            a = ds.read(1, out_shape=(n, n))
                        else:
                            a = ds.read([1, 2, 3], out_shape=(3, n, n))
            except rasterio.errors.RasterioIOError:
                a = np.zeros((0,), dtype=np.uint8)    # (no tile: all sea)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            np.save(path + ".part.npy", a)
            os.replace(path + ".part.npy", path)
        return np.load(path)

    def _window(self, kind, s, w, n, e):
        a, la, lo, size = self._tile(kind, (s + n) / 2.0, (w + e) / 2.0)
        if a.size == 0:
            return None
        px = a.shape[-1] / float(size)
        r0, r1 = int(round((la + size - n) * px)), int(round((la + size - s) * px))
        c0, c1 = int(round((w - lo) * px)), int(round((e - lo) * px))
        return a[..., r0:r1, c0:c1]

    def counts(self, s, w, n, e):
        """{WorldCover class: pixels} over the box (a cell: inside one 3 degree tile); {} where there is no tile."""
        a = self._window("map", s, w, n, e)
        if a is None:
            return {}
        cls, num = np.unique(a, return_counts=True)
        return {int(c): int(k) for c, k in zip(cls, num) if c in WORLDCOVER}

    def tint(self, s, w, n, e, size=TINT_SIZE):
        """The box's ground as size x size x 3 uint8, north up; None where there is no tile (the sea)."""
        a = self._window("s2", s, w, n, e)
        if a is None or a.shape[1] < size:
            return None
        k = a.shape[1] // size
        a = a[:, :k * size, :k * size].astype(float).reshape(3, size, k, size, k).mean(axis=(2, 4))
        return to_srgb(np.moveaxis(a, 0, -1))


class Sources:
    """Everything a profile is read from, loaded on first use (Natural Earth, Köppen, the climate, land cover,
    heights)."""

    def __init__(self, cache, with_tint=False):
        self.cache = cache
        self.with_tint = with_tint
        self.places = Places(cache)
        self.koppen = Koppen(cache)
        self.climate = Climate(cache)
        self.cover = WorldCover(cache)
        self._dem = None
        self._dem_lock = threading.Lock()

    def heights(self, lats, lons):
        import route_bake as rb
        with self._dem_lock:
            if self._dem is None:
                self._dem = rb.Dem(os.path.join(self.cache, "terrain"), 0.0, lambda *a: None, 300.0)
            return self._dem.heights(lats, lons)

    def parts(self, cell):
        i, j = (int(v) for v in cell.split("_"))
        s, w, n, e = region_bake.cell_box(i, j)
        step = (n - s) / GRID
        lats, lons = np.meshgrid(n - step * (np.arange(GRID) + 0.5), w + step * (np.arange(GRID) + 0.5), indexing="ij")
        lats, lons = lats.ravel(), lons.ravel()
        on_land, country, region = self.places.at(lats, lons)
        sea = 1.0 - on_land.mean()
        countries = []
        for k, num in zip(*np.unique(country[country >= 0], return_counts=True)):
            _, code, name = self.places.countries[int(k)]
            countries.append((code, name, num / float(len(country))))
        if not countries and sea < 1.0:
            # (a speck of land the countries' coarser outlines miss: the nearest country's)
            k = self.places.nearest_country((s + n) / 2.0, (w + e) / 2.0)
            if k >= 0:
                _, code, name = self.places.countries[k]
                countries.append((code, name, 1.0 - sea))
        reg = ("", "")
        if countries:
            main = max(countries, key=lambda c: c[2])[0]
            rs = [r for r in region[region >= 0] if self.places.regions[int(r)][3] == main] or list(region[region >= 0])
            if rs:
                best = self.places.regions[int(np.bincount(rs).argmax())]
                reg = (best[1], best[2])
        land_lats, land_lons = lats[on_land], lons[on_land]
        heights = []
        if len(land_lats):
            try:
                heights = np.maximum(self.heights(land_lats, land_lons), 0.0)
            except Exception as ex:  # (no tiles: leave the altitude to the land cover's guess)
                print("cell %s: no heights (%s)" % (cell, ex), file=sys.stderr)
        # The coast: sea in the cell and land too, or land in the cell at its edge with the sea just over it.
        coast = 0.0 < sea < 1.0
        mid_lat, mid_lon = (s + n) / 2.0, (w + e) / 2.0
        codes = self.koppen.codes(s, w, n, e)
        if sea < 1.0 and koppen_of(codes) == "":
            codes = self.koppen.codes(s - 0.25, w - 0.25, n + 0.25, e + 0.25)   # (an islet the map has as sea)
        return {
            "countries": countries, "region": reg, "koppen": codes,
            "cover": self.cover.counts(s, w, n, e), "sea": sea, "coast": coast, "heights": heights,
            "climate": self.climate.at(mid_lat, mid_lon) if sea < 1.0 else None,
        }, (self.cover.tint(s, w, n, e) if self.with_tint and sea < 1.0 else None)

    def profile(self, cell):
        parts, tint = self.parts(cell)
        return make_profile(cell, parts, tint)


# ----- every cell of the world's index -----

def bake_world(index_path, out, sources, only=None, workers=8, log=print):
    """Makes the profile of every cell the index has (with roads or not) whose bake_key changed or that has none, into
    out/profile/cROW_COL.json, and their hashes into the index's "profiles". Returns (made, kept)."""
    with open(index_path) as f:
        index = json.load(f)
    want = bake_key(sources.with_tint)
    todo, kept = [], 0
    for cell in sorted(index["cells"]):
        if only and cell not in only:
            continue
        if only:
            todo.append(cell)   # (cells asked for by name are made again whatever their key)
            continue
        path = os.path.join(out, "profile", "c%s.json" % cell)
        if os.path.exists(path) and cell in index.get("profiles", {}):
            try:
                with open(path) as f:
                    if json.load(f).get("bake_key") == want:
                        kept += 1
                        continue
            except ValueError:
                pass
        todo.append(cell)
    log("profiles: %d to make, %d kept" % (len(todo), kept))
    made = {}

    def one(cell):
        return cell, sources.profile(cell)

    with concurrent.futures.ThreadPoolExecutor(workers) as pool:
        for k, (cell, p) in enumerate(pool.map(one, todo)):
            text = profile_text(p)
            path = os.path.join(out, "profile", "c%s.json" % cell)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text + "\n")
            made[cell] = text_hash(text)
            if (k + 1) % 100 == 0:
                log("  %d of %d" % (k + 1, len(todo)))
    # (the index read again: a bake may have added cells meanwhile)
    with open(index_path) as f:
        index = json.load(f)
    profiles = index.setdefault("profiles", {})
    profiles.update(made)
    index["profiles"] = dict(sorted(profiles.items()))
    with open(index_path, "w") as f:
        json.dump(index, f, indent=1, sort_keys=False)
        f.write("\n")
    return len(made), kept


def country_codes(features, names):
    """{name: ISO code} for each of `names` (as Natural Earth's towns name countries) from Natural Earth's countries
    (`features`). A country's own names win over its sovereign's: Sint Maarten's sovereign is the Netherlands, and must
    not give the Netherlands its code."""
    codes = {k: v for k, v in COUNTRY_ALIASES.items() if k in names}
    for keys in (("ADMIN", "NAME", "NAME_LONG", "GEOUNIT"), ("SOVEREIGNT",)):
        for feat in features:
            p = feat["properties"]
            code = p.get("ISO_A2_EH") or p.get("ISO_A2") or ""
            if code in ("", "-99"):
                continue
            for key in keys:
                if p.get(key) in names and p[key] not in codes:
                    codes[p[key]] = code
    return codes


def write_countries(places, cache, out):
    """The country codes of the countries data/world/places.json names ({name: ISO code}): the game's guess at the
    country of a cell with no profile goes by the nearest town."""
    with open(places) as f:
        names = {p[4] for p in json.load(f)}
    with open(fetch(Places.NE % "ne_10m_admin_0_countries",
                    os.path.join(cache, "naturalearth", "ne_10m_admin_0_countries.geojson"))) as f:
        codes = country_codes(json.load(f)["features"], names)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(codes.items())), f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    return len(codes), sorted(names - set(codes))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("lat", type=float, nargs="?")
    ap.add_argument("lon", type=float, nargs="?")
    ap.add_argument("--index", help="the world's index.json: make every cell's profile")
    ap.add_argument("--only", default="", help="with --index, just these cells (ROW_COL,...)")
    ap.add_argument("--out", help="the profile's file (one cell), or the world repo's folder (--index)")
    ap.add_argument("--tint", action="store_true", help="give each profile its ground's tint (Sentinel-2)")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/torque-shed-profile"), help="download cache")
    ap.add_argument("--countries", metavar="PLACES", help="write the country codes of data/world/places.json's countries"
                    " to --out (data/world/countries.json)")
    args = ap.parse_args(argv)
    if args.countries:
        n, missing = write_countries(args.countries, args.cache, args.out)
        print("countries: %d; no code for %s" % (n, ", ".join(missing) or "none"))
        return 0
    sources = Sources(args.cache, args.tint)
    if args.index:
        only = {c for c in args.only.split(",") if c}
        made, kept = bake_world(args.index, args.out or os.path.dirname(args.index), sources, only, args.workers)
        print("profiles: %d made, %d kept" % (made, kept))
        return 0
    if args.lat is None or args.lon is None:
        ap.error("give LAT LON, or --index")
    i, j = region_bake.cell_of(args.lat, args.lon)
    p = sources.profile("%d_%d" % (i, j))
    text = json.dumps(p, indent=1, ensure_ascii=False)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
