#!/usr/bin/env python3
"""Tests for span_bake.py (a cell's bridges and tunnels), on made-up roads.

    python3 -m unittest tools/test_span_bake.py
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import span_bake as sp  # noqa: E402


def wkb_line(pts):
    """A WKB line string of [(lon, lat), ...]."""
    return struct.pack("<BII", 1, 2, len(pts)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in pts)


ROW, COL = cb.cell_of(54.3, -2.1)
S, W, N, E = cb.cell_box(ROW, COL)
# A road 1 km due east from inside the cell (0.0154 degrees of longitude at 54.3 N is about 1 km).
ROAD = wkb_line([(W + 0.05, S + 0.1), (W + 0.05 + 0.0154, S + 0.1)])


class SpanTests(unittest.TestCase):
    def test_a_bridge_part_way_along(self):
        got = sp.cell_spans([(ROAD, [{"values": ["is_bridge"], "between": [0.4, 0.45]}])], ROW, COL)
        self.assertEqual(len(got["spans"]), 1)
        kind, la0, lo0, la1, lo1 = got["spans"][0]
        self.assertEqual(kind, 0)
        self.assertAlmostEqual(lo0 / 1e5, W + 0.05 + 0.0154 * 0.4, places=4)
        self.assertAlmostEqual(lo1 / 1e5, W + 0.05 + 0.0154 * 0.45, places=4)
        self.assertEqual(la0, la1)

    def test_a_whole_segment_tunnel(self):
        got = sp.cell_spans([(ROAD, [{"values": ["is_tunnel"], "between": None}])], ROW, COL)
        self.assertEqual([s[0] for s in got["spans"]], [1])

    def test_a_culvert_is_road_and_other_flags_are_nothing(self):
        flags = [{"values": ["is_bridge"], "between": [0.5, 0.505]}, {"values": ["is_link"], "between": None}]
        self.assertEqual(sp.cell_spans([(ROAD, flags)], ROW, COL)["spans"], [])

    def test_a_span_is_the_cell_its_start_is_in(self):
        flags = [{"values": ["is_bridge"], "between": [0.1, 0.2]}]
        self.assertEqual(sp.cell_spans([(ROAD, flags)], ROW, COL + 1)["spans"], [])


if __name__ == "__main__":
    unittest.main()
