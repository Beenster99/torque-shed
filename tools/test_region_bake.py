"""Offline tests for region_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import json
import os
import struct
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import region_bake as rg  # noqa: E402
import route_bake as rb  # noqa: E402

F = rb.Frame(34.5, 134.3)


def ll(x, z):
    lat, lon = F.to_geo(x, z)
    return (float(lon), float(lat))


def wkb_line(points):
    return struct.pack("<BII", 1, 2, len(points)) + b"".join(struct.pack("<dd", *p) for p in points)


def seg(a, b, pts_xz, cls="primary", name=None, surface=None, limit=None, oneway=0, bans=None):
    access = [{"access_type": "denied", "when": {"heading": "backward" if oneway > 0 else "forward"}, "between": None}] if oneway else None
    return {"id": a + b, "subtype": "road", "class": cls, "geometry": wkb_line([ll(*p) for p in pts_xz]),
            "access_restrictions": access, "prohibited_transitions": bans,
            "connectors": [{"connector_id": a, "at": 0.0}, {"connector_id": b, "at": 1.0}],
            "road_surface": [{"value": surface, "between": None}] if surface else None, "road_flags": None,
            "names": {"primary": name} if name else None, "routes": None,
            "speed_limits": [{"max_speed": {"value": limit, "unit": "km/h"}, "when": None}] if limit else None}


class Simplify(unittest.TestCase):
    def test_straight_runs_lose_their_middle_and_bends_keep_theirs(self):
        line = [(0, 0), (10, 0.2), (20, -0.1), (30, 0), (40, 0)]
        self.assertEqual(rg.simplify(line, 1.5), [(0, 0), (40, 0)])
        bent = [(0, 0), (50, 0), (50, 50)]
        self.assertEqual(rg.simplify(bent, 1.5), bent)
        self.assertEqual(rg.simplify([(0, 0), (1, 1)], 1.5), [(0, 0), (1, 1)])

    def test_never_further_than_the_tolerance_from_the_original(self):
        t = np.linspace(0, 6.0, 200)
        line = list(zip((t * 40).tolist(), (np.sin(t) * 30).tolist()))
        kept = np.array(rg.simplify(line, 1.5))
        self.assertLess(len(kept), len(line) / 3)
        orig = np.array(line)
        for p in orig:
            d = np.min([_dist_to_segment(p, a, b) for a, b in zip(kept, kept[1:])])
            self.assertLessEqual(d, 1.5 + 1e-6)


def _dist_to_segment(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, float(np.dot(p - a, ab)) / max(float(np.dot(ab, ab)), 1e-12)))
    return float(np.hypot(*(p - (a + ab * t))))


class Rows(unittest.TestCase):
    def graph(self):
        segs = [seg("A", "B", [(0, 0), (500, 30), (1000, 0)], "primary", "Main Street", limit=60),
                seg("B", "C", [(1000, 0), (1000, 800)], "tertiary", None, "gravel"),
                seg("B", "D", [(1000, 0), (2000, 0)], "secondary", "Shore Road"),
                seg("X", "Y", [(5000, 5000), (5100, 5000)], "primary", "Stray"),      # a bit of road that leads nowhere
                ]
        return rb.Graph(segs, F)

    def test_rows_number_everything_and_drop_stray_networks(self):
        rows = rg.graph_rows(self.graph(), min_network=3)
        self.assertEqual(len(rows["nodes"]), 4)
        self.assertEqual(len(rows["edges"]), 3)
        names = rows["names"]
        main = next(e for e in rows["edges"] if names[e["n"]] == "Main Street")
        self.assertEqual((rows["classes"][main["c"]], main["l"], main["s"]), ("primary", 60, 0))
        track = next(e for e in rows["edges"] if rows["classes"][e["c"]] == "tertiary")
        self.assertEqual(rows["surfaces"][track["s"]], "gravel")
        self.assertEqual(names[track["n"]], "")
        # the road's bend is kept as its middle points, as a flat list
        self.assertEqual(len(main["p"]) % 2, 0)
        self.assertGreaterEqual(len(main["p"]), 2)
        for e in rows["edges"]:
            self.assertLess(max(e["a"], e["b"]), len(rows["nodes"]))

    def test_the_same_data_gives_the_same_rows(self):
        a = json.dumps(rg.graph_rows(self.graph(), min_network=3))
        b = json.dumps(rg.graph_rows(self.graph(), min_network=3))
        self.assertEqual(a, b)

    def test_one_way_roads_and_banned_turns_are_in_the_rows(self):
        segs = [seg("A", "B", [(0, 0), (1000, 0)], oneway=1),
                seg("B", "C", [(1000, 0), (2000, 0)], oneway=-1),
                seg("B", "D", [(1000, 0), (1000, 800)], bans=[{"sequence": [{"segment_id": "BC", "connector_id": "B"}], "when": None, "between": None}]),
                seg("A", "D", [(0, 0), (1000, 800)])]
        rows = rg.graph_rows(rb.Graph(segs, F), min_network=2)
        o = {(e["a"], e["b"]): e["o"] for e in rows["edges"]}
        self.assertEqual(sorted(o.values()), [-1, 0, 0, 1])
        self.assertEqual(len(rows["bans"]), 1)
        ef, node, et = rows["bans"][0]
        self.assertEqual(rows["nodes"][node], [1000.0, 0.0])
        self.assertEqual((rows["edges"][ef]["o"], rows["edges"][et]["o"]), (0, -1))

    def test_places_come_from_named_divisions_near_a_road(self):
        def div(subtype, x, z, names, pop=None):
            lon, lat = ll(x, z)
            return {"subtype": subtype, "names": names, "population": pop,
                    "geometry": struct.pack("<BIdd", 1, 1, lon, lat)}
        pts = np.array([[0.0, 0.0], [1000.0, 0.0], [2000.0, 0.0]])
        rows = rg.make_places([
            div("locality", 100, 50, {"primary": "Harbour", "common": {"en": "Harbour Town"}}, 900),
            div("microhood", 1500, 300, {"primary": "東", "common": {"en": "Higashi"}}),
            div("neighborhood", 1600, 320, {"primary": "東", "common": {"en": "Higashi"}}),   # the same place twice
            div("microhood", 1900, 100, {"primary": "西"}),                                   # no name we can print
            div("locality", 1000, 9000, {"primary": "Far", "common": {"en": "Far"}}),         # far from any road
            div("country", 500, 0, {"primary": "Japan", "common": {"en": "Japan"}}),
        ], F, pts, (-100, -100, 3000, 1000))
        self.assertEqual([(p["name"], p["kind"], p["pop"]) for p in rows], [("Harbour Town", "town", 900), ("Higashi", "village", 0)])

    def test_everything_is_kept_with_a_small_enough_limit(self):
        self.assertEqual(len(rg.graph_rows(self.graph(), min_network=2)["nodes"]), 6)

    def test_road_points_follow_every_road(self):
        rows = rg.graph_rows(self.graph(), min_network=3)
        pts = rg.road_points(rows, 16.0)
        self.assertGreater(len(pts), (1000 + 800 + 1000) / 16.0 * 0.9)
        self.assertTrue(np.all(pts[:, 0] > -50) and np.all(pts[:, 0] < 2050))
        # the spacing along a road is about the asked-for one
        main = pts[:int(1000 / 16)]
        steps = np.hypot(*np.diff(main, axis=0).T)
        self.assertLess(float(np.abs(steps - 16.0).max()), 4.0)


class Hash(unittest.TestCase):
    def test_hash_covers_every_file_but_region_json(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "roads.json"), "w") as f:
                f.write("a")
            with open(os.path.join(d, "region.json"), "w") as f:
                f.write("one")
            first = rg.region_hash(d)
            with open(os.path.join(d, "region.json"), "w") as f:
                f.write("two")
            self.assertEqual(first, rg.region_hash(d))
            with open(os.path.join(d, "roads.json"), "w") as f:
                f.write("b")
            self.assertNotEqual(first, rg.region_hash(d))


if __name__ == "__main__":
    unittest.main()


class Zip(unittest.TestCase):
    def test_zip_holds_the_folder_and_the_entry_has_its_hash(self):
        import zipfile
        import region_zip
        with tempfile.TemporaryDirectory() as d:
            folder = os.path.join(d, "tiny")
            os.makedirs(os.path.join(folder, "tiles"))
            with open(os.path.join(folder, "region.json"), "w") as f:
                json.dump({"format": rg.FORMAT, "title": "Tiny"}, f)
            with open(os.path.join(folder, "roads.json"), "w") as f:
                f.write("{}")
            with open(os.path.join(folder, "tiles", "0_0.u16z"), "wb") as f:
                f.write(b"abc")
            out = os.path.join(d, "tiny.zip")
            entry = region_zip.zip_region(folder, out)
            self.assertEqual(entry["hash"], rg.region_hash(folder))
            self.assertEqual(entry["title"], "Tiny")
            with zipfile.ZipFile(out) as z:
                self.assertEqual(sorted(z.namelist()), ["region.json", "roads.json", "tiles/0_0.u16z"])
