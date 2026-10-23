#!/usr/bin/env python3
"""Tests for world_bake.py (the world's map for the Route planner TV), on made-up shapes: nothing is fetched.

    python3 -m unittest tools/test_world_bake.py
"""
import os
import struct
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world_bake as wb  # noqa: E402


def square(x0, y0, size, hole=None):
    ring = [[x0, y0], [x0 + size, y0], [x0 + size, y0 + size], [x0, y0 + size], [x0, y0]]
    poly = [ring]
    if hole:
        hx, hy, hs = hole
        poly.append([[hx, hy], [hx, hy + hs], [hx + hs, hy + hs], [hx + hs, hy], [hx, hy]])
    return {"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": poly}}


class WorldBakeTests(unittest.TestCase):
    def test_simplify_keeps_the_shape_and_drops_what_strays_less(self):
        xs = np.linspace(0.0, 1.0, 101)
        line = np.stack([xs, 0.001 * np.sin(xs * 40.0)], axis=1)
        line[50, 1] = 0.5   # a spike that must stay
        kept = wb.simplify(line, 0.01)
        self.assertLess(len(kept), 10)
        self.assertTrue(any(abs(p[1] - 0.5) < 1e-9 for p in kept))
        self.assertTrue(np.allclose(kept[0], line[0]) and np.allclose(kept[-1], line[-1]))

    def test_areas_are_cut_into_triangles_round_their_holes(self):
        fc = {"features": [square(0.0, 0.0, 10.0, hole=(4.0, 4.0, 2.0))]}
        pts, tri = wb.bake_areas(fc, 0.001, None)
        self.assertEqual(len(pts), 8)
        self.assertEqual(len(tri) % 3, 0)
        p = pts / wb.SCALE
        area = 0.0
        for k in range(0, len(tri), 3):
            a, b, c = p[tri[k]], p[tri[k + 1]], p[tri[k + 2]]
            area += abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) / 2.0
        self.assertAlmostEqual(area, 100.0 - 4.0, places=6)   # the square without its hole

    def test_the_file_reads_back(self):
        fc = {"features": [square(1.0, 2.0, 3.0)]}
        lines = {"features": [{"type": "Feature", "properties": {},
                               "geometry": {"type": "LineString", "coordinates": [[0.0, 0.0], [1.0, 1.0], [2.0, 0.0]]}}]}
        layers = [("land", 0, wb.bake_areas(fc, 0.001, None)), ("borders", 1, wb.bake_lines(lines, 0.001, None))]
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "world.tsw")
            wb.write_bin(path, layers)
            data = open(path, "rb").read()
        self.assertEqual(data[:4], b"TSW2")
        self.assertEqual(struct.unpack_from("<I", data, 4)[0], 2)
        at = 8
        self.assertEqual(data[at + 1:at + 5], b"land")
        at += 1 + 4
        self.assertEqual(data[at], 0)
        n = struct.unpack_from("<I", data, at + 1)[0]
        self.assertEqual(n, 4)
        first = struct.unpack_from("<ii", data, at + 5)
        self.assertEqual(first, (100000, 200000))

    def test_places_go_in_the_order_maps_name_them(self):
        fc = {"features": [
            {"properties": {"name": "Leeds", "min_zoom": 5.6, "pop_max": 1529000, "adm0name": "United Kingdom"},
             "geometry": {"coordinates": [-1.55, 53.79]}},
            {"properties": {"name": "London", "min_zoom": 1.7, "pop_max": 8567000, "adm0name": "United Kingdom"},
             "geometry": {"coordinates": [-0.12, 51.5]}},
            {"properties": {"name": "Istanbul", "min_zoom": 3.0, "pop_max": 10061000, "adm0name": "Turkey"},
             "geometry": {"coordinates": [28.97, 41.0]}},
        ]}
        self.assertEqual([p[0] for p in wb.bake_places(fc)], ["London", "Istanbul", "Leeds"])


if __name__ == "__main__":
    unittest.main()
