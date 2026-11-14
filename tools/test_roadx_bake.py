#!/usr/bin/env python3
"""Tests for roadx_bake.py (the road itself, from OpenStreetMap), on a made-up map.

    python3 -m unittest tools/test_roadx_bake.py
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import roadx_bake as rb  # noqa: E402

OSM = """<?xml version='1.0' encoding='UTF-8'?>
<osm version="0.6" generator="test">
 <node id="1" lat="54.4000" lon="-1.7400"/>
 <node id="2" lat="54.4010" lon="-1.7400"><tag k="highway" v="traffic_signals"/><tag k="traffic_signals:direction" v="forward"/></node>
 <node id="3" lat="54.4020" lon="-1.7400"/>
 <node id="4" lat="54.4000" lon="-1.7397"/>
 <node id="5" lat="54.4020" lon="-1.7397"/>
 <node id="6" lat="54.4015" lon="-1.7400"><tag k="highway" v="crossing"/><tag k="crossing" v="uncontrolled"/><tag k="crossing_ref" v="zebra"/><tag k="crossing:island" v="yes"/></node>
 <node id="7" lat="54.4100" lon="-1.7500"/>
 <node id="8" lat="54.4105" lon="-1.7500"><tag k="highway" v="passing_place"/></node>
 <node id="9" lat="54.4110" lon="-1.7500"><tag k="traffic_calming" v="hump"/></node>
 <node id="10" lat="54.4200" lon="-1.7600"><tag k="highway" v="crossing"/></node>
 <node id="11" lat="54.4201" lon="-1.7600"/>
 <way id="100"><nd ref="1"/><nd ref="2"/><nd ref="6"/><nd ref="3"/><tag k="highway" v="trunk"/><tag k="oneway" v="yes"/><tag k="ref" v="A1"/><tag k="lanes" v="2"/><tag k="lit" v="yes"/></way>
 <way id="101"><nd ref="5"/><nd ref="4"/><tag k="highway" v="trunk"/><tag k="oneway" v="yes"/><tag k="ref" v="A 1"/></way>
 <way id="102"><nd ref="4"/><nd ref="5"/><tag k="barrier" v="guard_rail"/></way>
 <way id="103"><nd ref="7"/><nd ref="8"/><nd ref="9"/><tag k="highway" v="unclassified"/><tag k="lanes" v="1"/><tag k="width" v="3.2 m"/><tag k="sidewalk" v="left"/><tag k="maxweight" v="7.5"/></way>
 <way id="104"><nd ref="10"/><nd ref="11"/><tag k="highway" v="footway"/></way>
 <way id="105"><nd ref="7"/><nd ref="9"/><tag k="highway" v="residential"/></way>
</osm>
"""


def seg(sid, way, line):
    return {"id": sid, "sources": [{"dataset": "OpenStreetMap", "record_id": "w%d@2" % way}], "line": line}


class RoadxTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp()
        path = os.path.join(cls.dir, "t.osm")
        with open(path, "w") as f:
            f.write(OSM)
        cls.osm = rb.OsmCut.read(path)
        cls.cell = cb.cell_of(54.401, -1.74)
        segs = [seg("a", 100, [(54.4, -1.74), (54.402, -1.74)]), seg("b", 101, [(54.402, -1.7397), (54.4, -1.7397)]),
                # (the lane drawn against its way: its left is the way's right)
                seg("c", 103, [(54.411, -1.75), (54.41, -1.75)]), seg("d", 105, [(54.41, -1.75), (54.411, -1.75)]),
                {"id": "e", "sources": [{"dataset": "OpenStreetMap", "record_id": "w999@1"}], "line": []}]
        cls.baked = rb.bake_cell(cls.cell[0], cls.cell[1], segs, cls.osm, "r")
        cls.rows = {r[0]: r for r in cls.baked["edges"]}

    def row(self, sid):
        return self.rows.get(rb.region_bake.short_id(sid))

    def test_way_of_sources(self):
        self.assertEqual(rb.way_of([{"dataset": "OpenStreetMap", "record_id": "w123@4"}]), 123)
        self.assertIsNone(rb.way_of([{"dataset": "OpenStreetMap", "record_id": "n5@1"}]))
        self.assertIsNone(rb.way_of(None))

    def test_numbers(self):
        self.assertEqual(rb.number("7.3 m"), 7.3)
        self.assertAlmostEqual(rb.number("6'6\""), 1.98, places=2)
        self.assertEqual(rb.number("7,5"), 7.5)
        self.assertIsNone(rb.number("default"))

    def test_matched_share(self):
        self.assertEqual(self.baked["matched"], [4, 5])

    def test_lanes_lit_and_halves(self):
        a, b = self.row("a"), self.row("b")
        self.assertEqual(a[1:4], [2, 2, 0])
        self.assertTrue(a[5] & rb.EDGE_FLAGS["lit"])
        # (A1 and "A 1" are the same road number, running opposite ways 20 m apart)
        self.assertEqual(a[11], b[0])
        self.assertEqual(b[11], a[0])

    def test_reversed_segment_swaps_sides(self):
        c = self.row("c")
        self.assertEqual(c[4], 32)
        self.assertTrue(c[5] & rb.EDGE_FLAGS["pave_right"])
        self.assertFalse(c[5] & rb.EDGE_FLAGS["pave_left"])
        self.assertEqual(c[10], 75)

    def test_untagged_road_has_no_row(self):
        self.assertIsNone(self.row("d"))

    def test_points(self):
        k = self.baked["kinds"]
        kinds = sorted(k[p[0]] for p in self.baked["points"])
        # (the crossing on a footway alone is left out)
        self.assertEqual(kinds, ["crossing_zebra", "hump", "passing_place", "traffic_signals"])
        light = next(p for p in self.baked["points"] if k[p[0]] == "traffic_signals")
        self.assertEqual(light[3], 0)   # facing the northbound traffic on way 100
        zebra = next(p for p in self.baked["points"] if k[p[0]] == "crossing_zebra")
        self.assertEqual(zebra[4] & rb.POINT_FLAGS["island"], 1)

    def test_barrier_line(self):
        self.assertEqual(self.baked["lines"], [[rb.KINDS.index("guard_rail"), 5440000, -173970, 200, 0]])

    def test_report(self):
        self.assertIn("4 of 5 segments matched (80%)", rb.report(self.baked))

    def test_no_pair_beyond_reach(self):
        segs = [("x", {"oneway": "yes", "ref": "A66"}, [(54.0, -1.0), (54.01, -1.0)]),
                ("y", {"oneway": "yes", "ref": "A66"}, [(54.01, -0.999), (54.0, -0.999)])]   # (65 m apart)
        self.assertEqual(rb.pair_halves(segs), {})
        segs[1] = ("y", {"oneway": "yes", "ref": "A66"}, [(54.0, -0.9996), (54.01, -0.9996)])   # (the same way)
        self.assertEqual(rb.pair_halves(segs), {})


if __name__ == "__main__":
    unittest.main()
