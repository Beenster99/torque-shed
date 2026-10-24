#!/usr/bin/env python3
"""Tests for coast_bake.py (a cell's coast for the Route planner TV), on made-up land.

    python3 -m unittest tools/test_coast_bake.py
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402


def wkb_polygon(*rings):
    """A WKB polygon of rings [(lon, lat), ...]."""
    out = struct.pack("<BII", 1, 3, len(rings))
    for ring in rings:
        out += struct.pack("<I", len(ring)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in ring)
    return out


def points(flat):
    pts = [(flat[0], flat[1])]
    for i in range(2, len(flat), 2):
        pts.append((pts[-1][0] + flat[i], pts[-1][1] + flat[i + 1]))
    return [(a / cb.SCALE, b / cb.SCALE) for a, b in pts]


ROW, COL = cb.cell_of(54.3, -0.6)   # 54.25..54.5 N, 0.75..0.5 W
S, W, N, E = cb.cell_box(ROW, COL)


class CoastTests(unittest.TestCase):
    def test_land_over_the_whole_cell_is_all(self):
        big = wkb_polygon([(W - 1, S - 1), (E + 1, S - 1), (E + 1, N + 1), (W - 1, N + 1), (W - 1, S - 1)])
        self.assertEqual(cb.cell_coast([big], ROW, COL)["land"], "all")

    def test_no_land_is_all_sea(self):
        away = wkb_polygon([(W - 3, S), (W - 2, S), (W - 2, N), (W - 3, N), (W - 3, S)])
        self.assertEqual(cb.cell_coast([away], ROW, COL)["land"], "none")
        self.assertEqual(cb.cell_coast([], ROW, COL)["land"], "none")

    def test_a_coast_is_cut_to_the_cell(self):
        # Land to the west of a wiggly coast down the cell's middle, running on past it north and south.
        mid = (W + E) / 2
        coast = [(mid + 0.01 * ((k % 2) * 2 - 1), S - 0.5 + k * 0.05) for k in range(0, 31)]
        ring = [(W - 1, S - 0.5)] + coast + [(W - 1, coast[-1][1]), (W - 1, S - 0.5)]
        got = cb.cell_coast([wkb_polygon(ring)], ROW, COL)["land"]
        self.assertIsInstance(got, dict)
        self.assertEqual(len(got["rings"]), 1)
        pts = points(got["rings"][0])
        self.assertTrue(all(S - 1e-5 <= lat <= N + 1e-5 and W - 1e-5 <= lon <= E + 1e-5 for lat, lon in pts))
        self.assertTrue(any(abs(lon - (mid + 0.01)) < 1e-4 for _, lon in pts) and any(abs(lon - (mid - 0.01)) < 1e-4 for _, lon in pts))

    def test_rocks_are_left_out_and_lakes_kept_as_holes(self):
        rock = wkb_polygon([(W + 0.1, S + 0.1), (W + 0.1001, S + 0.1), (W + 0.1001, S + 0.1001), (W + 0.1, S + 0.1)])
        self.assertEqual(cb.cell_coast([rock], ROW, COL)["land"], "none")
        lake = [(W + 0.1, S + 0.1), (W + 0.15, S + 0.1), (W + 0.15, S + 0.15), (W + 0.1, S + 0.15), (W + 0.1, S + 0.1)]
        island = [(W - 1, S - 1), (E + 1, S - 1), (E + 1, N + 1), (W - 1, N + 1), (W - 1, S - 1)]
        got = cb.cell_coast([wkb_polygon(island, lake)], ROW, COL)["land"]
        self.assertEqual((len(got["rings"]), len(got["holes"])), (1, 1))


if __name__ == "__main__":
    unittest.main()
