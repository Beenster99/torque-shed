"""Offline tests for land_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import os
import struct
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import land_bake as lb  # noqa: E402
import route_bake as rb  # noqa: E402


def wkb_polygon(rings):
    out = struct.pack("<BII", 1, 3, len(rings))
    for r in rings:
        out += struct.pack("<I", len(r)) + b"".join(struct.pack("<dd", *p) for p in r)
    return out


def wkb_multi(polys):
    return struct.pack("<BII", 1, 6, len(polys)) + b"".join(wkb_polygon(p) for p in polys)


def wkb_point(lon, lat):
    return struct.pack("<BIdd", 1, 1, lon, lat)


FRAME = rb.Frame(34.5, 134.3)


def square_ll(x, z, w, d):
    """A closed ring (lon, lat) of the rectangle at route-frame (x, z) of size w x d."""
    xs = [x - w / 2, x + w / 2, x + w / 2, x - w / 2, x - w / 2]
    zs = [z - d / 2, z - d / 2, z + d / 2, z + d / 2, z - d / 2]
    lat, lon = FRAME.to_geo(np.array(xs), np.array(zs))
    return list(zip(lon.tolist(), lat.tolist()))


class Geometry(unittest.TestCase):
    def test_polygon_and_multipolygon(self):
        ring = [(134.0, 34.0), (134.1, 34.0), (134.1, 34.1), (134.0, 34.0)]
        hole = [(134.02, 34.01), (134.04, 34.01), (134.04, 34.03), (134.02, 34.01)]
        polys = lb.parse_geometry(wkb_polygon([ring, hole]))
        self.assertEqual(len(polys), 1)
        self.assertEqual(len(polys[0]), 2)
        self.assertEqual(polys[0][0][1], (134.1, 34.0))
        self.assertEqual(len(lb.parse_geometry(wkb_multi([[ring], [ring]]))), 2)

    def test_points_and_lines_have_no_polygons(self):
        self.assertEqual(lb.parse_geometry(wkb_point(1.0, 2.0)), [])
        self.assertEqual(lb.parse_point(wkb_point(1.5, 2.5)), (1.5, 2.5))
        line = struct.pack("<BII", 1, 2, 2) + struct.pack("<4d", 0, 0, 1, 1)
        self.assertEqual(lb.parse_geometry(line), [])
        self.assertIsNone(lb.parse_point(line))

    def test_names_the_game_can_print(self):
        self.assertEqual(lb.english_name({"primary": "Shodoshima", "common": None}), "Shodoshima")
        self.assertEqual(lb.english_name({"primary": "小豆島", "common": {"en": "Shodoshima"}}), "Shodoshima")
        self.assertEqual(lb.english_name({"primary": "小豆島", "common": {"ja": "小豆島"}}), "")
        self.assertEqual(lb.english_name(None), "")


class Cover(unittest.TestCase):
    def test_layers_draw_in_order_with_holes(self):
        rows = [{"geometry": wkb_polygon([square_ll(256, 256, 400, 400)]), "subtype": "forest"},
                {"geometry": wkb_polygon([square_ll(256, 256, 100, 100)]), "subtype": "crop"},
                {"geometry": wkb_polygon([square_ll(256, 256, 800, 800), square_ll(256, 256, 60, 60)]), "subtype": "unknown"}]
        layers = lb.polygon_layers(rows, FRAME, lambda r: lb.LAND_COVER.get(r["subtype"]))
        self.assertEqual(len(layers), 2)   # the unknown one is not drawn
        cov = lb.rasterise_tile(0, 0, layers)
        self.assertEqual(cov.shape, (128, 128))
        self.assertEqual(cov[64, 64], lb.CID["crop"])
        self.assertEqual(cov[64, 100], lb.CID["forest"])
        self.assertEqual(cov[2, 2], lb.CID["grass"])

    def test_a_tile_elsewhere_is_untouched(self):
        rows = [{"geometry": wkb_polygon([square_ll(256, 256, 600, 400)]), "subtype": "forest"}]
        layers = lb.polygon_layers(rows, FRAME, lambda r: lb.LAND_COVER.get(r["subtype"]))
        self.assertEqual(int(lb.rasterise_tile(3, 3, layers).max()), 0)
        edge = lb.rasterise_tile(1, 0, layers)   # the forest's east edge lies at x = 556, in the next tile
        self.assertEqual(edge[64, 5], lb.CID["forest"])
        self.assertEqual(edge[64, 100], 0)


class Buildings(unittest.TestCase):
    knots = np.array([[float(x), 0.0] for x in range(0, 600, 4)])

    def row(self, x, z, w, d, **kw):
        r = {"geometry": wkb_polygon([square_ll(x, z, w, d)])}
        r.update(kw)
        return r

    def test_min_rect_finds_the_turned_box(self):
        c, s = np.cos(0.5), np.sin(0.5)
        pts = [(c * x - s * z + 10, s * x + c * z + 20) for x, z in [(-5, -2), (5, -2), (5, 2), (-5, 2)]]
        cx, cz, w, d, _ = lb.min_rect(pts)
        self.assertAlmostEqual(cx, 10, delta=0.2)
        self.assertAlmostEqual(cz, 20, delta=0.2)
        self.assertAlmostEqual(w * d, 40.0, delta=4.0)

    def test_kept_near_and_clear_of_the_road(self):
        rows = [self.row(100, 40, 10, 8),                      # beside the road: kept
                self.row(200, 3, 10, 8),                       # on the road: dropped
                self.row(300, 900, 10, 8),                     # far away: dropped
                self.row(400, 30, 20, 20, height=12.0, subtype="commercial"),
                self.row(500, -40, 9, 9, num_floors=2, class_="x")]
        out = lb.make_buildings(rows, FRAME, self.knots)
        self.assertEqual([round(b[0]) for b in sorted(out)], [100, 400, 500])
        self.assertTrue(all(2.6 <= b[5] <= 40.0 for b in out))
        shop = [b for b in out if round(b[0]) == 400][0]
        self.assertEqual(lb.BUILDING_KINDS[shop[6]], "shop")
        self.assertEqual(shop[5], 12.0)

    def test_order_is_nearest_first_and_deterministic(self):
        rows = [self.row(100, 120, 10, 8), self.row(120, 30, 10, 8), self.row(140, 60, 10, 8)]
        a = lb.make_buildings(rows, FRAME, self.knots)
        self.assertEqual(sorted(round(b[1]) for b in a), [30, 60, 120])
        self.assertEqual([b[7] for b in a], sorted(b[7] for b in a))   # in order along the road
        self.assertEqual([round(b[0]) for b in a], [100, 120, 140])
        self.assertEqual(a[1][7], 30)   # the building at x = 120 is nearest knot 30 (4 m a knot)
        self.assertEqual(a, lb.make_buildings(rows, FRAME, self.knots))

    def test_kinds(self):
        self.assertEqual(lb.building_kind({"class": "temple"}, 12, 12), "worship")
        self.assertEqual(lb.building_kind({"class": "warehouse"}, 30, 20), "industrial")
        self.assertEqual(lb.building_kind({"class": "greenhouse"}, 30, 8), "barn")
        self.assertEqual(lb.building_kind({"class": "garage"}, 5, 3), "shed")
        self.assertEqual(lb.building_kind({"class": "apartments"}, 20, 15), "block")
        self.assertEqual(lb.building_kind({}, 8, 8), "house")
        self.assertEqual(lb.building_kind({}, 3, 3), "shed")

    def test_ground_levelled_under_a_building_and_feathered(self):
        h = np.tile(np.linspace(0.0, 20.0, lb.TILE_N), (lb.TILE_N, 1))   # rises 20 m east across the tile
        out = lb.level_ground(h, 0, 0, [[256.0, 256.0, 20.0, 20.0, 0.0, 6.0, 0]])
        inside = out[64, 60:68]
        self.assertLess(float(inside.max() - inside.min()), 0.5)
        self.assertEqual(float(out[10, 10]), float(h[10, 10]))   # far away: untouched
        self.assertEqual(out.shape, h.shape)


class Landmarks(unittest.TestCase):
    def test_peaks_and_places_near_the_road(self):
        lat, lon = FRAME.to_geo(np.array([1000.0, 9000.0, 800.0]), np.array([800.0, 0.0, 100.0]))
        pt = lambda i: wkb_point(float(lon[i]), float(lat[i]))   # noqa: E731
        peaks = [{"class": "peak", "geometry": pt(0), "names": {"primary": "High Tor"}},
                 {"class": "peak", "geometry": pt(1), "names": {"primary": "Far Tor"}},
                 {"class": "cliff", "geometry": pt(0), "names": None}]
        places = [{"basic_category": "lighthouse", "geometry": pt(2), "names": None, "confidence": 0.9},
                  {"basic_category": "lighthouse", "geometry": pt(2), "names": None, "confidence": 0.2},
                  {"basic_category": "cafe", "geometry": pt(2), "names": None, "confidence": 0.9}]
        knots = np.array([[float(x), 0.0] for x in range(0, 400, 4)])
        out = lb.make_landmarks(places, peaks, FRAME, knots)
        self.assertEqual([(m["kind"], m["name"]) for m in out], [("lighthouse", ""), ("peak", "High Tor")])


class Whole(unittest.TestCase):
    def test_bake_writes_the_files(self):
        fetched = {"land_cover": [{"geometry": wkb_polygon([square_ll(256, 256, 400, 400)]), "subtype": "forest"}],
                   "land": [], "land_use": [], "water": [], "place": [],
                   "building": [{"geometry": wkb_polygon([square_ll(100, 40, 10, 8)]), "class": "house"}]}
        calls = []

        def fake_fetch(bucket, release, theme, kind, box, columns, filesystem=None):
            calls.append(kind)
            return fetched.get(kind, [])
        real = lb.fetch
        lb.fetch = fake_fetch
        try:
            with tempfile.TemporaryDirectory() as d:
                knots = np.array([[float(x), 0.0] for x in range(0, 600, 4)])
                land = lb.bake_land("b", "r", FRAME, knots, [(0, 0), (1, 0)], d, log=lambda *_: None)
                self.assertEqual(len(land["buildings"]), 1)
                self.assertEqual(os.path.getsize(os.path.join(d, "tiles", "0_0.cov")), lb.TILE_N * lb.TILE_N)
                self.assertTrue(os.path.exists(os.path.join(d, "buildings.json")))
                self.assertTrue(os.path.exists(os.path.join(d, "landmarks.json")))
                self.assertIn("water", calls)
        finally:
            lb.fetch = real


if __name__ == "__main__":
    unittest.main()
