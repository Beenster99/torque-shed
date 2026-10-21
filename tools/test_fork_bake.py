"""Offline tests for fork_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import os
import struct
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import fork_bake as fb  # noqa: E402
import road_facts as rf  # noqa: E402
import route_bake as rb  # noqa: E402

F = rb.Frame(34.5, 134.3)


def ll(x, z):
    lat, lon = F.to_geo(x, z)
    return (float(lon), float(lat))


def wkb_line(points):
    return struct.pack("<BII", 1, 2, len(points)) + b"".join(struct.pack("<dd", *p) for p in points)


def seg(a, b, pts_xz, cls="primary", name=None):
    return {"id": a + b, "subtype": "road", "class": cls, "geometry": wkb_line([ll(*p) for p in pts_xz]),
            "connectors": [{"connector_id": a, "at": 0.0}, {"connector_id": b, "at": 1.0}],
            "road_surface": None, "road_flags": None, "names": {"primary": name} if name else None, "routes": None}


class Flat:
    def heights(self, lat, lon):
        return np.full(np.shape(lat), 120.0)


def diamond(detour=1500.0, extra=()):
    """A main road A-J1-J2-D east along z = 0 (J1 at 8 km, J2 at 13 km) and a detour J1-X-J2 north of it, with a side
    road at each junction so they are junctions."""
    segs = [seg("A", "J1", [(0, 0), (4000, 0), (8000, 0)], "primary", "Main Street"),
            seg("J1", "J2", [(8000, 0), (10500, 0), (13000, 0)], "primary", "Main Street"),
            seg("J2", "D", [(13000, 0), (17000, 0), (22000, 0)], "primary", "Main Street"),
            seg("J1", "X", [(8000, 0), (8500, -detour), (10500, -detour)], "tertiary", "Moor Road"),
            seg("X", "J2", [(10500, -detour), (12500, -detour), (13000, 0)], "tertiary", "Moor Road")]
    return rb.Graph(segs + list(extra), F)


def route(graph, start, end):
    _, _, prev = graph.dijkstra(start)
    steps = graph.path(prev, start, end)
    pts, owner, _ = rb.route_from_path(graph, steps)
    knots, _, _ = rb.resample(pts, 4.0)
    return steps, knots, owner, np.array(pts)


class Forks(unittest.TestCase):
    def setUp(self):
        self.g = diamond()
        self.steps, self.knots, self.owner, self.raw = route(self.g, "A", "D")

    def test_finds_the_detour_as_a_fork_on_chunk_boundaries(self):
        forks = fb.find_forks(rb, self.g, self.steps, self.knots, (0.0, 0.0), seed=3, first_m=6000.0)
        self.assertEqual(len(forks), 1)
        f = forks[0]
        self.assertEqual(f["i0"] % 32, 0)
        self.assertEqual(f["i1"] % 32, 0)
        self.assertLessEqual(f["i0"] * 4.0, 8000.0)
        self.assertGreaterEqual(f["i1"] * 4.0, 13000.0)
        edges = {self.g.edges[s[1]]["label"] for s in f["alt"]}
        self.assertEqual(edges, {"Moor Road"})

    def test_no_fork_without_another_way(self):
        g = rb.Graph([seg("A", "J1", [(0, 0), (8000, 0)]), seg("J1", "J2", [(8000, 0), (13000, 0)]),
                      seg("J2", "D", [(13000, 0), (22000, 0)])], F)
        steps, knots, _, _ = route(g, "A", "D")
        self.assertEqual(fb.find_forks(rb, g, steps, knots, (0.0, 0.0), first_m=6000.0), [])

    def test_a_way_far_longer_is_not_a_fork(self):
        g = diamond(detour=9000.0)
        steps, knots, _, _ = route(g, "A", "D")
        self.assertEqual(fb.find_forks(rb, g, steps, knots, (0.0, 0.0), first_m=6000.0), [])

    def test_same_forks_every_time(self):
        a = fb.find_forks(rb, self.g, self.steps, self.knots, (0.0, 0.0), seed=3, first_m=6000.0)
        b = fb.find_forks(rb, self.g, self.steps, self.knots, (0.0, 0.0), seed=3, first_m=6000.0)
        self.assertEqual([(f["i0"], f["i1"]) for f in a], [(f["i0"], f["i1"]) for f in b])

    def test_the_way_is_a_road_of_whole_chunks_that_meets_the_main_road(self):
        f = fb.find_forks(rb, self.g, self.steps, self.knots, (0.0, 0.0), seed=3, first_m=6000.0)[0]
        elev = np.full(len(self.knots), 120.0)
        cum = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(self.raw, axis=0).T))])
        owner = np.array(self.owner)
        scale = cum[-1] / ((len(self.knots) - 1) * 4.0)
        edge_of_main = lambda s: int(owner[min(max(int(np.searchsorted(cum, s * scale, side="right")) - 1, 0), len(owner) - 1)])
        way = fb.build_way(rb, self.g, f, self.knots, (0.0, 0.0), elev, Flat(), F, edge_of_main, "uk")
        self.assertEqual((way["n"] - 1) % 32, 0)
        self.assertEqual(len(way["chunks"]), (way["n"] - 1) // 32)
        self.assertLess(float(np.hypot(*(np.array([way["x"][0], way["z"][0]]) - self.knots[f["i0"]]))), 0.01)
        self.assertLess(float(np.hypot(*(np.array([way["x"][-1], way["z"][-1]]) - self.knots[f["i1"]]))), 0.01)
        steps = np.hypot(np.diff(way["x"]), np.diff(way["z"]))
        self.assertTrue(np.all(np.abs(steps - 4.0) < 0.5), "knots about 4 m apart (%.2f..%.2f)" % (steps.min(), steps.max()))
        self.assertAlmostEqual(float(way["e"][0]), 120.0, places=3)
        self.assertAlmostEqual(float(way["e"][-1]), 120.0, places=3)
        self.assertTrue(np.all(np.abs(np.diff(way["e"])) <= 4.0 * rb.MAX_GRADE + 1e-6))
        mid = way["chunks"][len(way["chunks"]) // 2]
        self.assertEqual((mid[2], mid[3]), ("tertiary", "Moor Road"))
        self.assertEqual(mid[4], rf.default_limit("tertiary", "uk"))
        self.assertGreater(way["length"], (f["i1"] - f["i0"]) * 4.0)   # the detour is longer than the main road

    def test_a_way_that_doubles_back_where_it_leaves_is_not_a_fork(self):
        # the detour leaves J1 backwards (towards A) and comes round: a hairpin on the main road, not a way to ride
        segs = [seg("A", "J1", [(0, 0), (4000, 0), (8000, 0)], "primary", "Main Street"),
                seg("J1", "J2", [(8000, 0), (10500, 0), (13000, 0)], "primary", "Main Street"),
                seg("J2", "D", [(13000, 0), (17000, 0), (22000, 0)], "primary", "Main Street"),
                seg("J1", "X", [(8000, 0), (7000, -60), (6000, -600), (9000, -1500), (13000, -1500)], "tertiary", "Moor Road"),
                seg("X", "J2", [(13000, -1500), (13000, 0)], "tertiary", "Moor Road")]
        g = rb.Graph(segs, F)
        steps, knots, _, _ = route(g, "A", "D")
        self.assertEqual(fb.find_forks(rb, g, steps, knots, (0.0, 0.0), first_m=6000.0), [])
        self.assertLess(fb.sharpest_turn(np.array([[0.0, 0.0], [4.0, 0.0], [8.0, 0.0]])), 0.01)
        self.assertGreater(fb.sharpest_turn(np.array([[0.0, 0.0], [4.0, 0.0], [0.5, 0.2]])), 2.5)

    def test_pin_ends(self):
        e = fb.pin_ends(np.array([10.0] * 400), 20.0, 5.0)
        self.assertEqual((e[0], e[-1]), (20.0, 5.0))
        self.assertAlmostEqual(float(e[200]), 10.0, delta=0.5)

    def test_rows_name_the_ways(self):
        f = fb.find_forks(rb, self.g, self.steps, self.knots, (0.0, 0.0), seed=3, first_m=6000.0)
        way = {"n": 97, "x": np.zeros(97), "z": np.zeros(97), "e": np.zeros(97),
               "chunks": [["tarmac", 4.6, "tertiary", "Moor Road", 96]] * 3}
        main = [{"surface": "tarmac", "width": 7.4, "cls": "primary", "name": "Main Street"}] * 400
        rows = fb.fork_rows(rb, f, [way], main)
        self.assertEqual(rows[0]["kinds"], ["main", "scenic"])
        self.assertEqual(rows[0]["names"], {"main": "Main Street", "scenic": "Moor Road"})
        self.assertEqual(fb.way_kind_and_name([["gravel", 3.3, "track", "", 30]] * 3, "x")[0], "gravel")


if __name__ == "__main__":
    unittest.main()
