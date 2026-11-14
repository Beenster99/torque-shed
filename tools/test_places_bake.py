#!/usr/bin/env python3
"""Tests for places_bake.py (the places worth riding to), on a made-up map.

    python3 -m unittest tools/test_places_bake.py
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import places_bake as pb  # noqa: E402

OSM = """<?xml version='1.0' encoding='UTF-8'?>
<osm version="0.6" generator="test">
 <node id="1" lat="54.6026" lon="-3.0982"><tag k="historic" v="archaeological_site"/><tag k="site_type" v="megalith"/><tag k="megalith_type" v="stone_circle"/><tag k="name" v="Castlerigg Stone Circle"/><tag k="wikidata" v="Q1049357"/></node>
 <node id="2" lat="54.6000" lon="-3.1000"/>
 <node id="3" lat="54.6000" lon="-3.0990"/>
 <node id="4" lat="54.6006" lon="-3.0990"/>
 <node id="5" lat="54.6006" lon="-3.1000"/>
 <way id="10"><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="5"/><nd ref="2"/><tag k="amenity" v="place_of_worship"/><tag k="religion" v="christian"/><tag k="denomination" v="anglican"/><tag k="name" v="St John's"/><tag k="building" v="church"/></way>
 <node id="6" lat="54.6100" lon="-3.1100"><tag k="amenity" v="place_of_worship"/></node>
 <node id="7" lat="54.6110" lon="-3.1110"><tag k="highway" v="primary"/><tag k="wikidata" v="Q99"/></node>
 <node id="8" lat="54.6120" lon="-3.1120"><tag k="man_made" v="tower"/><tag k="tower:type" v="observation"/><tag k="height" v="120 m"/></node>
 <node id="9" lat="54.6130" lon="-3.1130"><tag k="place" v="hamlet"/><tag k="name" v="Nowhere"/><tag k="wikidata" v="Q42"/></node>
 <node id="11" lat="54.6140" lon="-3.1140"><tag k="historic" v="memorial"/><tag k="memorial" v="plaque"/></node>
 <node id="12" lat="54.6150" lon="-3.1150"><tag k="historic" v="castle"/><tag k="ruins" v="yes"/><tag k="name" v="Old Castle"/><tag k="wikidata" v="Q7"/></node>
 <node id="13" lat="54.6151" lon="-3.1151"/>
 <node id="14" lat="54.6153" lon="-3.1151"/>
 <node id="15" lat="54.6153" lon="-3.1149"/>
 <way id="16"><nd ref="13"/><nd ref="14"/><nd ref="15"/><nd ref="13"/><tag k="historic" v="castle"/><tag k="ruins" v="yes"/><tag k="wikidata" v="Q7"/><tag k="name" v="Old Castle"/></way>
</osm>
"""


class PlacesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        d = tempfile.mkdtemp()
        path = os.path.join(d, "t.osm")
        with open(path, "w") as f:
            f.write(OSM)
        cut = pb.PlaceCut.read(path)
        r, c = cb.cell_of(54.6, -3.1)
        cls.baked = pb.bake_cell(r, c, cut, "x")
        cls.by = {}
        for row in cls.baked["places"]:
            cls.by.setdefault(pb.KINDS[row[0]], []).append(row)

    def test_kinds(self):
        self.assertEqual(sorted(self.by), ["castle_ruin", "church", "settlement", "stone_circle", "tower"])

    def test_stone_circle_wikidata(self):
        r = self.by["stone_circle"][0]
        self.assertEqual((r[1], r[2]), ("Castlerigg Stone Circle", "Q1049357"))

    def test_church_outline(self):
        r = self.by["church"][0]
        self.assertEqual(r[7], "anglican")
        self.assertEqual(len(r[8]), 8)   # (four corners, the last not repeated)

    def test_unnamed_worship_and_plaque_and_road_left_out(self):
        self.assertEqual(len(self.by["church"]), 1)
        self.assertNotIn("memorial", self.by)

    def test_height(self):
        self.assertEqual(self.by["tower"][0][5], 120.0)

    def test_one_row_per_wikidata_outline_kept(self):
        self.assertEqual(len(self.by["castle_ruin"]), 1)
        self.assertEqual(len(self.by["castle_ruin"][0][8]), 6)

    def test_count(self):
        d = tempfile.mkdtemp()
        import json
        with open(os.path.join(d, "c1.json"), "w") as f:
            json.dump(self.baked, f)
        self.assertEqual(pb.count([os.path.join(d, "c1.json")])["stone_circle"], (1, 1))


if __name__ == "__main__":
    unittest.main()
