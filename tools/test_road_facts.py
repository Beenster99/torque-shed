"""Offline tests for road_facts.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import math
import os
import struct
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import road_facts as rf  # noqa: E402
import route_bake as rb  # noqa: E402

F = rb.Frame(34.5, 134.3)


def ll(x, z):
    lat, lon = F.to_geo(x, z)
    return (float(lon), float(lat))


def wkb_line(points):
    return struct.pack("<BII", 1, 2, len(points)) + b"".join(struct.pack("<dd", *p) for p in points)


def wkb_point(lon, lat):
    return struct.pack("<BIdd", 1, 1, lon, lat)


def seg(a, b, pts_xz, cls="primary"):
    return {"id": a + b, "subtype": "road", "class": cls, "geometry": wkb_line([ll(*p) for p in pts_xz]),
            "connectors": [{"connector_id": a, "at": 0.0}, {"connector_id": b, "at": 1.0}],
            "road_surface": None, "road_flags": None, "names": None, "routes": None}


def route(graph, start, end):
    _, _, prev = graph.dijkstra(start)
    steps = graph.path(prev, start, end)
    pts, _, _ = rb.route_from_path(graph, steps)
    knots, _, _ = rb.resample(pts, 4.0)
    return steps, knots


class Limits(unittest.TestCase):
    def test_posted_limits_in_kmh_or_mph(self):
        self.assertEqual(rf.segment_limit([{"max_speed": {"value": 40, "unit": "km/h"}, "when": None}]), 40)
        self.assertEqual(rf.segment_limit([{"max_speed": {"value": 30, "unit": "mph"}, "when": None}]), 48)
        self.assertIsNone(rf.segment_limit([{"max_speed": {"value": 30, "unit": "km/h"}, "when": {"during": "x"}}]))
        self.assertIsNone(rf.segment_limit(None))
        self.assertIsNone(rf.segment_limit([{"max_speed": None, "when": None}]))

    def test_defaults_by_country_class_and_built_up(self):
        self.assertEqual(rf.region_of(54.1, -2.0), "uk")
        self.assertEqual(rf.region_of(34.5, 134.3), "jp")
        self.assertEqual(rf.region_of(0.0, 0.0), "world")
        self.assertEqual(rf.default_limit("primary", "uk"), 96)
        self.assertEqual(rf.default_limit("primary", "uk", True), 48)
        self.assertLess(rf.default_limit("residential", "jp"), rf.default_limit("primary", "jp"))
        self.assertEqual(rf.default_limit("nonsense", "uk"), rf.LIMITS["uk"]["unclassified"])

    def test_chunk_limits_prefer_the_posted_one(self):
        chunks = [{"cls": "primary"}, {"cls": "primary"}, {"cls": "primary"}]
        got = rf.chunk_limits(chunks, [None, 30, None], [False, False, True], "uk")
        self.assertEqual(got, [96, 30, 48])

    def test_built_up_chunks_count_buildings_by_knot(self):
        buildings = [[0, 0, 5, 5, 0, 5, 0, 8]] * 9 + [[0, 0, 5, 5, 0, 5, 0, 100]] * 2   # knots 8 (chunk 0) and 100 (chunk 3)
        self.assertEqual(rf.built_up_chunks(5, buildings), [True, False, False, False, False])


class Junctions(unittest.TestCase):
    def straight(self, extra=()):
        main = [seg("A", "B", [(0, 0), (500, 0), (1000, 0)]), seg("B", "C", [(1000, 0), (1500, 0), (2000, 0)]),
                seg("C", "D", [(2000, 0), (3000, 0)])]
        return rb.Graph(main + list(extra), F)

    def test_a_side_road_on_the_left_is_a_tee_with_a_left_arm(self):
        g = self.straight([seg("B", "E", [(1000, 0), (1000, -300)], "residential")])   # north: left of a road heading east
        steps, knots = route(g, "A", "D")
        js = rf.junctions_along(g, steps, knots)
        self.assertEqual(len(js), 1)
        j = js[0]
        self.assertEqual(j["type"], "tee")
        self.assertEqual([a["side"] for a in j["arms"]], [-1])
        self.assertAlmostEqual(j["k"] * 4.0, 1000.0, delta=12.0)
        self.assertEqual(j["arms"][0]["cls"], "residential")
        self.assertAlmostEqual(j["arms"][0]["skew"], 0.0, delta=3.0)

    def test_both_sides_is_a_crossroads(self):
        g = self.straight([seg("B", "E", [(1000, 0), (1000, -300)], "residential"),
                           seg("B", "S", [(1000, 0), (1010, 300)], "tertiary")])
        steps, knots = route(g, "A", "D")
        js = rf.junctions_along(g, steps, knots)
        self.assertEqual([j["type"] for j in js], ["cross"])
        self.assertEqual(sorted(a["side"] for a in js[0]["arms"]), [-1, 1])
        self.assertAlmostEqual([a["skew"] for a in js[0]["arms"] if a["side"] == 1][0], -1.9, delta=0.5)   # leaning on along the road

    def test_a_road_running_on_is_a_fork_not_a_side_road(self):
        g = self.straight([seg("B", "E", [(1000, 0), (1300, -60)], "secondary")])    # only 11 degrees off the road
        steps, knots = route(g, "A", "D")
        self.assertEqual(rf.junctions_along(g, steps, knots), [])

    def test_a_plain_road_has_no_junctions(self):
        g = self.straight()
        steps, knots = route(g, "A", "D")
        self.assertEqual(rf.junctions_along(g, steps, knots), [])

    def test_a_ring_the_route_goes_round_is_a_roundabout(self):
        r = 18.0
        cx = 1000.0
        arc = lambda a0, a1: [(cx + r * math.cos(math.radians(a)), r * math.sin(math.radians(a))) for a in np.linspace(a0, a1, 4)]
        # nodes: W (180 deg), N (270 deg: north is -z), E (0), S (90). The route comes in at W and leaves at E over N.
        ring = [seg("W", "N", arc(180, 270), "primary"), seg("N", "E", arc(270, 360), "primary"),
                seg("E", "S", arc(0, 90), "primary"), seg("S", "W", arc(90, 180), "primary")]
        g = rb.Graph([seg("A", "W", [(0, 0), (cx - r, 0)]), seg("E", "D", [(cx + r, 0), (2000, 0)]),
                      seg("S", "X", [(cx, r), (cx, r + 300)], "tertiary")] + ring, F)
        steps, knots = route(g, "A", "D")
        js = rf.junctions_along(g, steps, knots)
        self.assertEqual([j["type"] for j in js], ["roundabout"])
        j = js[0]
        self.assertAlmostEqual(j["k"] * 4.0, cx, delta=20.0)
        self.assertEqual([a["side"] for a in j["arms"]], [1])      # the south road is on the right of a road heading east
        self.assertGreaterEqual(j["ri"], 4.0)
        self.assertAlmostEqual(j["ro"] - j["ri"], 6.8, places=1)

    def test_a_long_loop_of_short_links_is_not_a_roundabout(self):
        # a dual-carriageway junction: two 14 m links either side of a 60 m gap, 4 nodes in a long thin ring
        loop = [seg("W", "N", [(980, 0), (1000, -14)]), seg("N", "E", [(1000, -14), (1060, -14)]),
                seg("E", "S", [(1060, -14), (1080, 0)]), seg("S", "W", [(1080, 0), (980, 0)])]
        g = rb.Graph([seg("A", "W", [(0, 0), (980, 0)]), seg("S", "D", [(1080, 0), (2000, 0)])] + loop, F)
        steps, knots = route(g, "A", "D")
        self.assertEqual([j["type"] for j in rf.junctions_along(g, steps, knots) if j["type"] in ("roundabout", "mini")], [])

    def test_a_town_block_is_not_a_roundabout(self):
        # a square block of straight one-way streets, 60 m a side: its points are at its corners only, so it is as
        # "round" as a circle by its radius, but it turns square at each corner
        block = [seg("W", "N", [(1000, 0), (1000, -60)]), seg("N", "E", [(1000, -60), (1060, -60)]),
                 seg("E", "S", [(1060, -60), (1060, 0)]), seg("S", "W", [(1060, 0), (1000, 0)])]
        g = rb.Graph([seg("A", "W", [(0, 0), (1000, 0)]), seg("S", "D", [(1060, 0), (2000, 0)])] + block, F)
        steps, knots = route(g, "A", "D")
        self.assertEqual([j["type"] for j in rf.junctions_along(g, steps, knots) if j["type"] in ("roundabout", "mini")], [])

    def test_a_tiny_ring_is_a_mini_roundabout(self):
        r = 6.0
        cx = 1000.0
        arc = lambda a0, a1: [(cx + r * math.cos(math.radians(a)), r * math.sin(math.radians(a))) for a in np.linspace(a0, a1, 3)]
        ring = [seg("W", "N", arc(180, 270)), seg("N", "E", arc(270, 360)), seg("E", "S", arc(0, 90)), seg("S", "W", arc(90, 180))]
        g = rb.Graph([seg("A", "W", [(0, 0), (cx - r, 0)]), seg("E", "D", [(cx + r, 0), (2000, 0)])] + ring, F)
        steps, knots = route(g, "A", "D")
        self.assertEqual([j["type"] for j in rf.junctions_along(g, steps, knots)], ["mini"])

    def test_thinning_keeps_them_apart_and_the_biggest(self):
        js = [{"k": 100, "type": "tee"}, {"k": 130, "type": "roundabout"}, {"k": 400, "type": "cross"}, {"k": 450, "type": "tee"}]
        got = rf.thin_junctions(js, 100)
        self.assertEqual([(j["k"], j["type"]) for j in got], [(130, "roundabout"), (400, "cross")])


class Places(unittest.TestCase):
    knots = np.array([[float(x), 0.0] for x in range(0, 2000, 4)])

    def place(self, cat, x, z, conf=0.9, names=None):
        lon, lat = ll(x, z)
        return {"basic_category": cat, "geometry": wkb_point(lon, lat), "names": names, "confidence": conf}

    def test_places_beside_the_road_become_stops_with_their_side(self):
        rows = [self.place("gas_station", 500, 40, names={"primary": "Shell", "common": None}),
                self.place("cafe", 900, -60), self.place("hotel", 1200, 80, conf=0.3),
                self.place("gas_station", 700, 500), self.place("museum", 800, 20),
                self.place("campground", 1500, 120, names={"primary": "星空", "common": {"en": "Starfield"}})]
        out = rf.make_pois(rows, F, self.knots)
        self.assertEqual([(p["kind"], p["name"]) for p in out], [("fuel", "Shell"), ("cafe", ""), ("campsite", "Starfield")])
        self.assertGreater(out[0]["lat"], 0)      # south of an eastbound road: its right
        self.assertLess(out[1]["lat"], 0)
        self.assertAlmostEqual(out[0]["k"] * 4.0, 500.0, delta=8.0)

    def test_names_the_game_can_print(self):
        self.assertEqual(rf.english_name({"primary": "ENEOS", "common": None}), "ENEOS")
        self.assertEqual(rf.english_name({"primary": "小豆島", "common": None}), "")
        self.assertEqual(rf.english_name(None), "")


if __name__ == "__main__":
    unittest.main()
