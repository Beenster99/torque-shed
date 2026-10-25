#!/usr/bin/env python3
"""Tests for stream_bake.py (a cell's rivers and streams as lines), on made-up roads and water.

    python3 -m unittest tools/test_stream_bake.py
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import stream_bake as st  # noqa: E402


def wkb_line(pts):
    """A WKB line string of [(lon, lat), ...]."""
    return struct.pack("<BII", 1, 2, len(pts)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in pts)


ROW, COL = cb.cell_of(54.3, -2.1)
S, W, N, E = cb.cell_box(ROW, COL)
# A road 1 km due east from inside the cell (0.0154 degrees of longitude at 54.3 N is about 1 km).
ROAD = wkb_line([(W + 0.05, S + 0.1), (W + 0.05 + 0.0154, S + 0.1)])
GRID = st.RoadGrid([ROAD], S + 0.1)
# A beck crossing the road north to south, and one 2 km north of it (0.018 degrees of latitude).
BECK = wkb_line([(W + 0.057, S + 0.105), (W + 0.0572, S + 0.1), (W + 0.057, S + 0.095)])
FAR = wkb_line([(W + 0.057, S + 0.118), (W + 0.06, S + 0.119)])


def points(flat):
    """A flat line's points as [(lat, lon)] in degrees."""
    out = []
    lat, lon = flat[1], flat[2]
    out.append((lat / 1e5, lon / 1e5))
    for k in range(3, len(flat), 2):
        lat += flat[k]
        lon += flat[k + 1]
        out.append((lat / 1e5, lon / 1e5))
    return out


class StreamTests(unittest.TestCase):
    def test_a_beck_by_the_road_is_kept_whole(self):
        got = st.cell_streams([(1, BECK)], GRID, ROW, COL)
        self.assertEqual(len(got["streams"]), 1)
        line = got["streams"][0]
        self.assertEqual(line[0], 1)
        pts = points(line)
        self.assertAlmostEqual(pts[0][0], S + 0.105, places=4)   # (the way it flows, as mapped)
        self.assertAlmostEqual(pts[-1][0], S + 0.095, places=4)
        self.assertEqual(len(pts), 3)

    def test_one_far_from_any_road_is_left_out(self):
        self.assertEqual(st.cell_streams([(1, FAR)], GRID, ROW, COL)["streams"], [])

    def test_a_straight_run_is_simplified(self):
        straight = wkb_line([(W + 0.05 + 0.001 * k, S + 0.1002) for k in range(10)])
        line = st.cell_streams([(0, straight)], GRID, ROW, COL)["streams"][0]
        self.assertEqual(line[0], 0)
        self.assertEqual(len(points(line)), 2)

    def test_only_the_cell_it_runs_through_has_it(self):
        self.assertEqual(st.cell_streams([(1, BECK)], GRID, ROW, COL + 1)["streams"], [])

    def test_a_point_is_not_a_line(self):
        self.assertIsNone(st._flat(1, [(W, S)]))


if __name__ == "__main__":
    unittest.main()
