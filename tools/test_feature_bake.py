#!/usr/bin/env python3
"""Tests for feature_bake.py (a cell's things worth stopping for), on made-up map rows.

    python3 -m unittest tools/test_feature_bake.py
"""
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import feature_bake as fb  # noqa: E402

INFRA = ("base", "infrastructure", "class")
LAND = ("base", "land", "class")
RAIL = ("transportation", "segment", "class")
USE = ("base", "land_use", "class")
PLACE = ("places", "place", "taxonomy")
BLD = fb.BUILDINGS


def wkb_point(lon, lat):
    return struct.pack("<BIdd", 1, 1, lon, lat)


def wkb_line(pts):
    return struct.pack("<BII", 1, 2, len(pts)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in pts)


def wkb_polygon(ring, hole=None):
    rings = [ring] + ([hole] if hole else [])
    out = struct.pack("<BII", 1, 3, len(rings))
    for r in rings:
        out += struct.pack("<I", len(r)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in r)
    return out


ROW, COL = cb.cell_of(54.3, -2.1)
S, W, N, E = cb.cell_box(ROW, COL)
# A road 1 km due east from inside the cell (0.0154 degrees of longitude at 54.3 N is about 1 km).
ROAD = wkb_line([(W + 0.05, S + 0.1), (W + 0.05 + 0.0154, S + 0.1)])
GRID = fb.NearGrid([ROAD], S + 0.1)


def row(cls, geometry, **kw):
    r = {"id": "08b%s" % cls, "class": cls, "subtype": kw.pop("subtype", "x"), "geometry": geometry}
    r.update(kw)
    return r


def points(flat_row, first):
    """A flat row's points from index `first` as [(lat, lon)] in degrees."""
    lat, lon = flat_row[first], flat_row[first + 1]
    out = [(lat / 1e5, lon / 1e5)]
    for k in range(first + 2, len(flat_row) - 1, 2):
        lat += flat_row[k]
        lon += flat_row[k + 1]
        out.append((lat / 1e5, lon / 1e5))
    return out


class FeatureTests(unittest.TestCase):
    def bake(self, rows, grid=GRID):
        return fb.cell_features(rows, grid, ROW, COL, "test")

    def kinds(self, got, part):
        return [got["kinds"][r[0]] for r in got[part]]

    def test_a_turbine_far_from_any_road_is_kept(self):
        tags = [("generator:source", "wind"), ("height:hub", "80")]
        got = self.bake([(INFRA, row("generator", wkb_point(W + 0.2, S + 0.2), height=95.0, source_tags=tags))])
        self.assertEqual(self.kinds(got, "points"), ["wind_turbine"])
        p = got["points"][0]
        self.assertEqual(p[3], 95.0)
        self.assertEqual((p[1], p[2]), (round((S + 0.2) * 1e5), round((W + 0.2) * 1e5)))

    def test_a_pole_is_kept_only_near_a_road(self):
        near = (INFRA, row("power_pole", wkb_point(W + 0.055, S + 0.1005)))
        far = (INFRA, row("power_pole", wkb_point(W + 0.2, S + 0.2)))
        self.assertEqual(len(self.bake([near, far])["points"]), 1)
        self.assertEqual(self.bake([near], grid=None)["points"], [])

    def test_classes_not_named_are_left_out(self):
        got = self.bake([(INFRA, row("fire_hydrant", wkb_point(W + 0.055, S + 0.1))),
                         (INFRA, row("parking_space", wkb_point(W + 0.055, S + 0.1)))])
        self.assertEqual(got["points"], [])

    def test_a_point_outside_the_cell_is_left_to_its_own(self):
        self.assertEqual(self.bake([(LAND, row("peak", wkb_point(W - 0.01, S + 0.1), elevation=700))])["points"], [])

    def test_a_peak_keeps_its_name_and_height(self):
        names = {"primary": "Great Shunner Fell", "common": None}
        got = self.bake([(LAND, row("peak", wkb_point(W + 0.1, S + 0.1), elevation=716, names=names))])
        p = got["points"][0]
        self.assertEqual(p[4], 716.0)
        self.assertEqual(got["names"][p[6]], "Great Shunner Fell")
        self.assertIsNone(p[3])
        self.assertIsNone(p[5])

    def test_a_direction_is_a_heading(self):
        got = self.bake([(INFRA, row("viewpoint", wkb_point(W + 0.1, S + 0.1), source_tags=[("direction", "SW")]))])
        self.assertEqual(got["points"][0][5], 225.0)
        got = self.bake([(INFRA, row("viewpoint", wkb_point(W + 0.1, S + 0.1), source_tags=[("direction", "400")]))])
        self.assertEqual(got["points"][0][5], 40.0)

    def test_a_line_over_the_cell_edge_is_cut_there(self):
        line = wkb_line([(W - 0.05, S + 0.1), (W + 0.05, S + 0.1)])
        got = self.bake([(INFRA, row("power_line", line))])
        self.assertEqual(len(got["lines"]), 1)
        pts = points(got["lines"][0], 6)
        self.assertAlmostEqual(pts[0][1], W, places=5)
        self.assertAlmostEqual(pts[-1][1], W + 0.05, places=5)

    def test_a_line_that_leaves_and_comes_back_is_two(self):
        line = wkb_line([(W + 0.1, S + 0.1), (W - 0.1, S + 0.12), (W + 0.1, S + 0.14)])
        self.assertEqual(len(self.bake([(INFRA, row("power_line", line))])["lines"]), 2)

    def test_a_railway_is_cut_at_its_bridges(self):
        line = wkb_line([(W + 0.01, S + 0.1), (W + 0.21, S + 0.1)])
        flags = [{"values": ["is_bridge"], "between": [0.4, 0.6]}]
        got = self.bake([(RAIL, row("standard_gauge", line, subtype="rail", rail_flags=flags))])
        self.assertEqual([r[3] for r in got["lines"]], [0, fb.BRIDGE, 0])
        mid = points(got["lines"][1], 6)
        self.assertAlmostEqual(mid[0][1], W + 0.09, places=4)
        self.assertAlmostEqual(mid[-1][1], W + 0.13, places=4)

    def test_rail_pieces_meet_end_to_end(self):
        # A railway on a slant over the cell's west edge with a bridge on it: the piece in the next cell west ends, and
        # each piece after a flag change starts, at exactly the point (to the 1e-5 degree) the one before ends.
        line = wkb_line([(W - 0.0731, S + 0.1013), (W + 0.0417, S + 0.1377), (W + 0.1903, S + 0.1171)])
        flags = [{"values": ["is_bridge"], "between": [0.55, 0.62]}]
        r = row("standard_gauge", line, subtype="rail", rail_flags=flags)
        here = self.bake([(RAIL, r)])
        west = fb.cell_features([(RAIL, r)], GRID, ROW, COL - 1, "test")
        pieces = [points(x, 6) for x in west["lines"]] + [points(x, 6) for x in here["lines"]]
        self.assertEqual(len(pieces), 4)
        # (the files keep their lines in a fixed order, not along the railway: each join is one piece's end that is
        # exactly another's start)
        starts = [p[0] for p in pieces]
        self.assertEqual(len([p[-1] for p in pieces if p[-1] in starts]), 3)

    def test_canals_and_subways_are_kept(self):
        line = wkb_line([(W + 0.01, S + 0.1), (W + 0.21, S + 0.1)])
        got = self.bake([(("base", "water", "class"), row("canal", line)),
                         (RAIL, row("subway", line, subtype="rail"))])
        self.assertEqual(sorted(self.kinds(got, "lines")), ["canal", "subway"])

    def test_a_canal_lock_is_in_its_tags(self):
        line = wkb_line([(W + 0.01, S + 0.1), (W + 0.011, S + 0.1)])
        ring = [(W + 0.01, S + 0.1), (W + 0.011, S + 0.1), (W + 0.011, S + 0.1001), (W + 0.01, S + 0.1)]
        water = ("base", "water", "class")
        tags = [("lock", "yes"), ("lock_name", "Bingley Five Rise Top Lock")]
        got = self.bake([(water, row("canal", line, source_tags=tags, names={"primary": "Leeds and Liverpool Canal"})),
                         (water, row("canal", line)), (water, row("water", wkb_polygon(ring), source_tags=[("water", "lock")])),
                         (water, row("water", wkb_polygon(ring)))])
        self.assertEqual(self.kinds(got, "lines"), ["canal", "canal_lock"])
        self.assertEqual(got["names"][got["lines"][1][4]], "Bingley Five Rise Top Lock")
        self.assertEqual(self.kinds(got, "areas"), ["canal_lock"])

    def test_a_road_segment_is_never_a_feature(self):
        line = wkb_line([(W + 0.01, S + 0.1), (W + 0.21, S + 0.1)])
        self.assertEqual(self.bake([(RAIL, row("unknown", line, subtype="road"))])["lines"], [])

    def test_a_ferry_is_a_water_segment(self):
        line = wkb_line([(W + 0.01, S + 0.1), (W + 0.21, S + 0.1)])
        got = self.bake([(RAIL, row("unknown", line, subtype="water"))])
        self.assertEqual(self.kinds(got, "lines"), ["ferry"])

    def test_an_area_is_cut_to_the_cell_without_its_holes(self):
        ring = [(W - 0.05, S + 0.1), (W + 0.05, S + 0.1), (W + 0.05, S + 0.15), (W - 0.05, S + 0.15), (W - 0.05, S + 0.1)]
        hole = [(W + 0.01, S + 0.11), (W + 0.02, S + 0.11), (W + 0.02, S + 0.12), (W + 0.01, S + 0.11)]
        got = self.bake([(USE, row("vineyard", wkb_polygon(ring, hole)))])
        self.assertEqual(self.kinds(got, "areas"), ["vineyard"])
        pts = points(got["areas"][0], 5)
        self.assertEqual(len(pts), 4)
        self.assertTrue(all(p[1] >= W - 1e-5 for p in pts))

    def test_the_same_rows_bake_the_same_bytes(self):
        rows = [(LAND, row("peak", wkb_point(W + 0.1, S + 0.1), names={"primary": "B"})),
                (LAND, row("peak", wkb_point(W + 0.11, S + 0.1), names={"primary": "A"}))]
        a = self.bake(rows)
        b = self.bake(list(reversed(rows)))
        self.assertEqual(a, b)
        self.assertEqual(a["names"], ["", "B", "A"])   # (numbered in the order the rows are: west to east here)

    def test_a_border_is_named_for_its_sides(self):
        key = ("divisions", "division_boundary", "subtype")
        r = row("x", wkb_line([(W + 0.1, S + 0.05), (W + 0.1, S + 0.2)]), subtype="country", division_ids=["a", "b"])
        r["sides"] = fb.border_sides(r, {"a": "FR", "b": "ES"})
        got = self.bake([(key, r)])
        self.assertEqual(self.kinds(got, "lines"), ["country_border"])
        self.assertEqual(got["names"][got["lines"][0][4]], "FR|ES")
        # (the line keeps its way: left and right are as the map has them)
        pts = points(got["lines"][0], 6)
        self.assertLess(pts[0][0], pts[-1][0])
        self.assertEqual(fb.border_sides({"division_ids": ["a", "z"]}, {"a": "FR"}), "FR|")
        self.assertEqual(fb.border_sides({}, {"a": "FR"}), "")

    def test_the_classes_hash_changes_with_the_classes(self):
        h = fb.classes_hash()
        self.assertEqual(len(h), 12)
        fb.CLASSES[INFRA]["made_up"] = ("made_up", False)
        try:
            self.assertNotEqual(fb.classes_hash(), h)
        finally:
            del fb.CLASSES[INFRA]["made_up"]
        self.assertEqual(fb.classes_hash(), h)

    def test_every_kind_has_a_kit_row(self):
        import json
        kits = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "scenery_kits.json")))
        missing = [k for k in fb.KINDS if k not in kits["kinds"]]
        self.assertEqual(missing, [])

    def test_merge_keeps_one_list(self):
        a = self.bake([(LAND, row("peak", wkb_point(W + 0.1, S + 0.1), names={"primary": "A"}))])
        b = dict(a, cell="x")
        got = fb.merge([a, b])
        self.assertEqual(len(got["points"]), 2)
        self.assertEqual(got["cells"], ["%d_%d" % (ROW, COL), "x"])
        self.assertEqual(got["names"], ["", "A"])


    def square(self, lon, lat, d=0.0001):
        return wkb_polygon([(lon, lat), (lon + d, lat), (lon + d, lat + d), (lon, lat + d), (lon, lat)])

    def test_a_building_keeps_its_mapped_look(self):
        got = self.bake([(BLD, {"geometry": self.square(W + 0.1, S + 0.1), "class": "house", "roof_shape": "Gabled",
                                "roof_color": "#778899", "roof_material": "slate"}),
                         (BLD, {"geometry": self.square(W + 0.1002, S + 0.1), "class": "church"})])
        rows = fb.undelta_rows(got["buildings"])
        self.assertEqual(len(rows), 2)
        first = [got["words"][i] for i in rows[0][2:]]
        self.assertEqual(first, ["", "gabled", "#778899", "slate", "", ""])   # (a house is no class of its own)
        self.assertEqual(got["words"][rows[1][2]], "church")
        self.assertAlmostEqual(rows[0][0] / 1e5, S + 0.10005, places=4)
        self.assertAlmostEqual(rows[0][1] / 1e5, W + 0.10005, places=4)

    def test_a_building_the_map_says_nothing_of_is_left_out(self):
        got = self.bake([(BLD, {"geometry": self.square(W + 0.1, S + 0.1), "class": "house"})])
        self.assertNotIn("buildings", got)
        self.assertEqual(got["points"], [])

    def test_a_building_is_in_the_cell_its_middle_is_in(self):
        got = self.bake([(BLD, {"geometry": self.square(W - 0.00005, S + 0.1), "class": "chapel"})])
        self.assertNotIn("buildings", got)

    def test_a_monument_place_is_a_named_point(self):
        got = self.bake([(PLACE, {"id": "p1", "geometry": wkb_point(W + 0.2, S + 0.2), "confidence": 0.9,
                                  "taxonomy": {"primary": "castle"}, "names": {"primary": "Conwy Castle"}}),
                         (PLACE, {"id": "p2", "geometry": wkb_point(W + 0.2, S + 0.21), "confidence": 0.3,
                                  "taxonomy": {"primary": "monument"}, "names": {"primary": "Unsure"}}),
                         (PLACE, {"id": "p3", "geometry": wkb_point(W + 0.2, S + 0.22), "confidence": 0.9,
                                  "taxonomy": {"primary": "historic_site"}, "names": {"primary": "Holiday let"}})])
        self.assertEqual(self.kinds(got, "points"), ["castle"])
        self.assertEqual(got["names"][got["points"][0][6]], "Conwy Castle")

    def test_merge_keeps_the_building_looks(self):
        a = self.bake([(BLD, {"geometry": self.square(W + 0.1, S + 0.1), "roof_shape": "flat"})])
        b = self.bake([(BLD, {"geometry": self.square(W + 0.2, S + 0.1), "roof_color": "#FF0000"})])
        got = fb.merge([a, b])
        rows = fb.undelta_rows(got["buildings"])
        self.assertEqual(len(rows), 2)
        self.assertEqual(sorted(got["words"]), ["", "#FF0000", "flat"])


if __name__ == "__main__":
    unittest.main()
