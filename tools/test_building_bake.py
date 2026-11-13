#!/usr/bin/env python3
"""Tests for building_bake.py (every building in a cell with its outline and height), on made-up map rows.

    python3 -m unittest tools/test_building_bake.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import building_bake as bb  # noqa: E402
import coast_bake as cb  # noqa: E402
from test_feature_bake import wkb_polygon  # noqa: E402

ROW, COL = cb.cell_of(53.96, -1.08)
S, W, N, E = cb.cell_box(ROW, COL)
# About a metre in each: 1 / 111,000 degrees of latitude, 1 / 65,600 of longitude at 54 N.
DLAT, DLON = 1.0 / 111300.0, 1.0 / 65600.0


def house(lat, lon, w=8.0, d=6.0, clockwise=False, **kw):
    """A w by d metre rectangle with its south-west corner at (lat, lon), as an Overture row."""
    ring = [(lon, lat), (lon + w * DLON, lat), (lon + w * DLON, lat + d * DLAT), (lon, lat + d * DLAT), (lon, lat)]
    if clockwise:
        ring = ring[::-1]
    r = {"id": "08b%.6f%.6f" % (lat, lon), "geometry": wkb_polygon(ring), "class": kw.pop("cls", None)}
    r.update(kw)
    return r


def points(b):
    """A building row's outline as [(lat, lon)] in degrees."""
    lat, lon = b[9], b[10]
    out = [(lat / 1e6, lon / 1e6)]
    for k in range(11, len(b) - 1, 2):
        lat += b[k]
        lon += b[k + 1]
        out.append((lat / 1e6, lon / 1e6))
    return out


class BuildingBakeTest(unittest.TestCase):
    def bake(self, rows):
        return bb.cell_buildings(rows, ROW, COL, "test")

    def all_rows(self, got):
        return [b for rows in got["rows"].values() for b in rows]

    def test_a_house_keeps_its_outline_height_and_words(self):
        got = self.bake([house(S + 0.1, W + 0.1, height=7.5, num_floors=2, roof_shape="gabled", facade_material="brick")])
        (b,) = self.all_rows(got)
        self.assertEqual(b[0], 75)
        self.assertEqual(b[2], 2)
        self.assertEqual(got["words"][b[4]], "gabled")
        self.assertEqual(got["words"][b[7]], "brick")
        pts = points(b)
        self.assertEqual(len(pts), 4)
        self.assertAlmostEqual(pts[0][0], S + 0.1, places=6)
        self.assertAlmostEqual(pts[0][1], W + 0.1, places=6)

    def test_no_height_is_minus_one_and_outlines_turn_counter_clockwise(self):
        (b,) = self.all_rows(self.bake([house(S + 0.1, W + 0.1, clockwise=True)]))
        self.assertEqual(b[0], -1)
        self.assertEqual(b[2], -1)
        pts = points(b)
        area = sum(a[1] * c[0] - c[1] * a[0] for a, c in zip(pts, pts[1:] + pts[:1]))
        self.assertGreater(area, 0.0)

    def test_a_building_is_its_middles_cell_and_tile(self):
        got = self.bake([house(S - 0.0001, W + 0.1), house(S + 0.0001, W + 0.0001), house(N - 0.001, E - 0.001)])
        self.assertEqual(sorted(got["rows"]), ["0_0", "%d_%d" % (bb.TILES - 1, bb.TILES - 1)])

    def test_towers_and_tiny_things_are_left_out(self):
        rows = [house(S + 0.1, W + 0.1, height=60.0), house(S + 0.11, W + 0.1, w=60.0, d=60.0),
                house(S + 0.12, W + 0.1, w=1.5, d=1.5), house(S + 0.13, W + 0.1, is_underground=True)]
        self.assertEqual(self.all_rows(self.bake(rows)), [])

    def test_floors_only_and_a_raised_part(self):
        (b,) = self.all_rows(self.bake([house(S + 0.1, W + 0.1, num_floors=3, min_floor=1)]))
        self.assertEqual(b[0], -1)
        self.assertEqual(b[1], 32)
        self.assertEqual(b[2], 3)

    def test_the_same_file_whatever_order_the_rows_come_in(self):
        rows = [house(S + 0.1 + k * 0.0002, W + 0.1, height=5.0 + k) for k in range(5)]
        self.assertEqual(self.bake(rows), self.bake(rows[::-1]))

    def test_a_curve_is_thinned_but_its_corners_stay(self):
        import math
        ring = []
        for k in range(64):
            a = 2.0 * math.pi * k / 64.0
            ring.append((W + 0.1 + 10.0 * DLON * math.cos(a), S + 0.1 + 10.0 * DLAT * math.sin(a)))
        ring.append(ring[0])
        r = {"id": "08bround", "geometry": wkb_polygon(ring)}
        (b,) = self.all_rows(self.bake([r]))
        n = len(points(b))
        self.assertLess(n, 64)
        self.assertGreater(n, 12)


if __name__ == "__main__":
    unittest.main()
