"""Offline tests for ground_bake.py and paths_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import json
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import coast_bake  # noqa: E402
import ground_bake as gb  # noqa: E402
import paths_bake as pb  # noqa: E402
import sketch_bake  # noqa: E402

ROW, COL = 577, 712
BOX = coast_bake.cell_box(ROW, COL)
LAT0 = (BOX[0] + BOX[2]) / 2.0
M_LAT, M_LON = sketch_bake.metres_per_degree(LAT0)
# (a point in metres from the cell's middle)
MID = ((BOX[1] + BOX[3]) / 2.0, LAT0)


def at(x, z):
    return (MID[0] + x / M_LON, MID[1] + z / M_LAT)


def wkb_point(x, z):
    return struct.pack("<BI2d", 1, 1, *at(x, z))


def wkb_line(pts):
    return struct.pack("<BII", 1, 2, len(pts)) + b"".join(struct.pack("<2d", *at(*p)) for p in pts)


def wkb_polygon(pts):
    ring = list(pts) + [pts[0]]
    return struct.pack("<BIII", 1, 3, 1, len(ring)) + b"".join(struct.pack("<2d", *at(*p)) for p in ring)


def square(x, z, half):
    return [(x - half, z - half), (x + half, z - half), (x + half, z + half), (x - half, z + half)]


def field():
    """A road along z = 0 from x = -3000 to 3000."""
    return gb.RoadField([wkb_line([(-3000, 0), (3000, 0)])], BOX, 500.0)


WATER = ("base", "water", "class")
LAND = ("base", "land", "class")
USE = ("base", "land_use", "class")
INFRA = ("base", "infrastructure", "class")


class RoadFieldTest(unittest.TestCase):
    def test_near_is_by_each_kinds_reach(self):
        f = field()
        self.assertTrue(f.near([at(0, 40)], 60.0))
        self.assertFalse(f.near([at(0, 400)], 150.0))
        self.assertTrue(f.near([at(0, 400)], 500.0))
        self.assertTrue(f.near([at(0, 4000)], None))       # (a kind with no reach: anywhere)
        self.assertFalse(f.near([at(5000, 0)], 100.0))     # (past the road's end)


class Ground(unittest.TestCase):
    def bake(self, rows, f="road"):
        return gb.cell_ground(rows, field() if f == "road" else None, ROW, COL, "r1")

    def test_each_kind_kept_by_its_reach_and_size(self):
        rows = [
            (WATER, {"class": "lake", "names": {"primary": "Semer Water"}, "geometry": wkb_polygon(square(0, 3000, 300))}),
            (WATER, {"class": "pond", "geometry": wkb_polygon(square(100, 50, 3))}),           # 36 m2: too small
            (WATER, {"class": "ditch", "geometry": wkb_line([(0, 30), (200, 30)])}),
            (WATER, {"class": "ditch", "geometry": wkb_line([(0, 900), (200, 900)])}),         # far from the road
            (LAND, {"class": "forest", "source_tags": [("leaf_type", "broadleaved")], "geometry": wkb_polygon(square(0, 300, 100))}),
            (LAND, {"class": "tree", "source_tags": [("species", "Quercus robur")], "geometry": wkb_point(10, 8)}),
            (LAND, {"class": "tree", "geometry": wkb_point(10, 600)}),                          # far: left out
            (USE, {"class": "pitch", "source_tags": [("sport", "soccer")], "geometry": wkb_polygon(square(50, 60, 40))}),
            (USE, {"class": "garden", "geometry": wkb_polygon(square(50, 20, 10))}),            # not a kind of ours
            (INFRA, {"class": "parking", "source_tags": [("surface", "asphalt")], "geometry": wkb_polygon(square(-50, 30, 20))}),
        ]
        got = self.bake(rows)
        kinds = gb.counts(got)
        self.assertEqual(kinds, {"lake": 1, "ditch": 1, "wood": 1, "tree": 1, "pitch": 1, "car_park": 1})
        lake = next(a for a in got["areas"] if got["kinds"][a[0]] == "lake")
        self.assertEqual(got["names"][lake[2]], "Semer Water")
        pitch = next(a for a in got["areas"] if got["kinds"][a[0]] == "pitch")
        self.assertEqual((got["words"][pitch[1]], pitch[2]), ("soccer", 0))                 # a pitch keeps no name
        tree = got["points"][0]
        self.assertEqual(got["words"][tree[1]], "quercus robur")
        self.assertEqual(len(tree), 4)
        self.assertEqual(got["cell"], "%d_%d" % (ROW, COL))
        self.assertEqual(got["classes"], gb.classes_hash())

    def test_no_roads_keeps_only_what_has_no_reach(self):
        rows = [(WATER, {"class": "lake", "geometry": wkb_polygon(square(0, 3000, 300))}),
                (USE, {"class": "residential", "geometry": wkb_polygon(square(0, 50, 100))})]
        self.assertEqual(gb.counts(self.bake(rows, None)), {"lake": 1})

    def test_areas_are_cut_to_the_cell_and_the_same_data_bakes_the_same(self):
        edge = (BOX[3] - MID[0]) * M_LON
        rows = [(LAND, {"class": "beach", "geometry": wkb_polygon(square(edge, 0, 200))})]
        got = self.bake(rows)
        a = got["areas"][0]
        lat, lon = a[3], a[4]
        lons = [lon]
        for k in range(5, len(a), 2):
            lat += a[k]
            lon += a[k + 1]
            lons.append(lon)
        self.assertLessEqual(max(lons), round(BOX[3] * gb.SCALE))
        self.assertEqual(json.dumps(self.bake(rows)), json.dumps(got))


class Paths(unittest.TestCase):
    def test_paths_near_the_road_with_their_width_and_surface(self):
        rows = [{"class": "footway", "geometry": wkb_line([(0, 20), (100, 40)]), "road_surface": [{"value": "paving_stones", "between": None}]},
                {"class": "bridleway", "geometry": wkb_line([(0, 60), (300, 60)]), "width_rules": [{"value": 2.5, "between": None}]},
                {"class": "footway", "subclass": "sidewalk", "geometry": wkb_line([(0, 5), (100, 5)])},   # the road's own pavement
                {"class": "path", "geometry": wkb_line([(0, 2000), (100, 2000)])},                       # far from any road
                {"class": "residential", "geometry": wkb_line([(0, 10), (100, 10)])}]                    # a road: not ours
        got = pb.cell_paths(rows, field(), ROW, COL, "r1")
        kinds = sorted(got["kinds"][ln[0]] for ln in got["lines"])
        self.assertEqual(kinds, ["bridleway", "footway"])
        foot = next(ln for ln in got["lines"] if got["kinds"][ln[0]] == "footway")
        self.assertEqual(got["surfaces"][foot[2]], "paving_stones")
        bridle = next(ln for ln in got["lines"] if got["kinds"][ln[0]] == "bridleway")
        self.assertEqual((bridle[1], bridle[2]), (2.5, 0))
        self.assertEqual(pb.cell_paths(rows, None, ROW, COL)["lines"], [])


if __name__ == "__main__":
    unittest.main()
