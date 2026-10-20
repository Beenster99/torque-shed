"""Offline tests for route_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import os
import struct
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import route_bake as rb  # noqa: E402


def wkb_line(points):
    return struct.pack("<BII", 1, 2, len(points)) + b"".join(struct.pack("<dd", *p) for p in points)


def seg(a, b, pts, cls="secondary", surface=None):
    """A fake Overture segment from connector a to b through `pts` ((lon, lat) pairs)."""
    return {"id": a + b, "subtype": "road", "class": cls, "geometry": wkb_line(pts),
            "connectors": [{"connector_id": a, "at": 0.0}, {"connector_id": b, "at": 1.0}],
            "road_surface": surface, "road_flags": None}


class GeodesyTests(unittest.TestCase):
    def test_start_lands_where_asked_and_north_is_negative_z(self):
        f = rb.Frame(34.5, 134.3)
        x, z = f.to_world(34.5, 134.3)
        self.assertAlmostEqual(float(x), rb.START_WORLD[0], places=6)
        self.assertAlmostEqual(float(z), rb.START_WORLD[1], places=6)
        _, zn = f.to_world(34.51, 134.3)
        self.assertLess(float(zn), rb.START_WORLD[1])
        xe, _ = f.to_world(34.5, 134.31)
        self.assertGreater(float(xe), rb.START_WORLD[0])

    def test_round_trip(self):
        f = rb.Frame(51.5, -0.1)
        lat, lon = f.to_geo(*f.to_world(51.52, -0.05))
        self.assertAlmostEqual(float(lat), 51.52, places=9)
        self.assertAlmostEqual(float(lon), -0.05, places=9)

    def test_a_degree_of_latitude_is_about_111_km(self):
        m_lat, m_lon = rb.metres_per_degree(0.0)
        self.assertAlmostEqual(m_lat, 110574, delta=10)
        self.assertAlmostEqual(m_lon, 111320, delta=30)
        self.assertAlmostEqual(rb.metres_per_degree(60.0)[1], 55800, delta=50)


class HeightTests(unittest.TestCase):
    def test_terrarium_decode(self):
        from PIL import Image
        im = Image.new("RGB", (2, 1))
        im.putpixel((0, 0), (128, 0, 0))     # 0 m
        im.putpixel((1, 0), (128, 100, 128))  # 100.5 m
        h = rb.decode_terrarium(im)
        self.assertAlmostEqual(h[0, 0], 0.0)
        self.assertAlmostEqual(h[0, 1], 100.5)

    def test_zoom_gives_pixels_no_coarser_than_asked(self):
        for lat in (0.0, 34.5, 60.0):
            z = rb.tile_zoom(lat, 4.0)
            px = 40075016.686 * np.cos(np.radians(lat)) / (512 * 2 ** z)
            self.assertLessEqual(px, 4.0)
            self.assertGreater(px, 1.0)

    def test_bilinear(self):
        a = np.array([[0.0, 10.0], [20.0, 30.0]])
        self.assertAlmostEqual(float(rb.bilinear(a, np.array(0.5), np.array(0.5))), 15.0)
        self.assertAlmostEqual(float(rb.bilinear(a, np.array(-5.0), np.array(0.0))), 0.0)   # clamped

    def test_shed_is_level_and_start_is_zero(self):
        n = 65
        ground = np.full((n, n), 300.0) + np.arange(n)[None, :] * 2.0
        h = rb.relative_heights(ground, spacing=64.0, size=n, half=2048.0)
        ax = np.arange(n) * 64.0 - 2048.0
        shed = (np.abs(ax[None, :] - rb.SHED_CENTRE[0]) < 100) & (np.abs(ax[:, None] - rb.SHED_CENTRE[1]) < 100)
        self.assertTrue(np.all(np.abs(h[shed]) < 1e-9))

    def test_quantise_round_trips_within_a_step(self):
        h = np.linspace(-600.0, 160.0, 1000).reshape(20, 50)
        q, lo, scale = rb.quantise(h)
        back = q.astype(float) * scale + lo
        self.assertLessEqual(float(np.abs(back - h).max()), scale)
        self.assertEqual(q.dtype, np.dtype("<u2"))


class GeometryTests(unittest.TestCase):
    def test_wkb_linestring_and_multi(self):
        self.assertEqual(rb.parse_linestrings(wkb_line([(1.0, 2.0), (3.0, 4.0)])), [[(1.0, 2.0), (3.0, 4.0)]])
        multi = struct.pack("<BII", 1, 5, 2) + wkb_line([(0.0, 0.0), (1.0, 1.0)]) + wkb_line([(2.0, 2.0), (3.0, 3.0)])
        self.assertEqual(len(rb.parse_linestrings(multi)), 2)

    def test_rdp_drops_points_on_the_line_and_keeps_corners(self):
        self.assertEqual(rb.rdp([(0, 0), (5, 0.1), (10, 0)], 1.0), [(0, 0), (10, 0)])
        self.assertEqual(len(rb.rdp([(0, 0), (5, 5), (10, 0)], 1.0)), 3)

    def test_classes(self):
        self.assertEqual(rb.segment_kind({"subtype": "road", "class": "primary"})[1], "tarmac")
        self.assertEqual(rb.segment_kind({"subtype": "road", "class": "track"})[1], "dirt")
        self.assertIsNone(rb.segment_kind({"subtype": "road", "class": "footway"}))
        self.assertIsNone(rb.segment_kind({"subtype": "water", "class": None}))
        unpaved = rb.segment_kind({"subtype": "road", "class": "residential",
                                   "road_surface": [{"value": "gravel", "between": None}]})
        self.assertEqual(unpaved[1], "dirt")


class RoadBuildTests(unittest.TestCase):
    def setUp(self):
        self.f = rb.Frame(34.5, 134.3)
        # Roads run east from the start: a straight main road A-B-C, a side road D into B.
        lon0, lat0 = 134.3, 34.5
        self.step = 0.003      # about 275 m of longitude
        pts = lambda i0, i1: [(lon0 + self.step * i, lat0) for i in range(i0, i1 + 1)]
        self.main1 = seg("A", "B", pts(0, 2), "primary")
        self.main2 = seg("B", "C", pts(2, 4), "primary")
        self.side = seg("D", "B", [(lon0 + 2 * self.step, lat0 - 0.003), (lon0 + 2 * self.step, lat0)], "residential")

    def test_degree_two_joins_merge_and_junctions_split(self):
        chains = rb.build_chains([self.main1, self.main2, self.side], self.f)
        self.assertEqual(len(chains), 3)          # B has three roads: nothing merges there
        chains = rb.build_chains([self.main1, self.main2], self.f)
        self.assertEqual(len(chains), 1)          # B has two: one road
        self.assertEqual(len(chains[0]["pts"]), 5)
        self.assertEqual({chains[0]["start_node"], chains[0]["end_node"]}, {"A", "C"})

    def test_merge_follows_either_digitising_direction(self):
        flipped = dict(self.main2)
        flipped["geometry"] = wkb_line(list(reversed(rb.parse_linestrings(self.main2["geometry"])[0])))
        flipped["connectors"] = [{"connector_id": "C", "at": 0.0}, {"connector_id": "B", "at": 1.0}]
        chains = rb.build_chains([self.main1, flipped], self.f)
        self.assertEqual(len(chains), 1)
        xs = [p[0] for p in chains[0]["pts"]]
        self.assertEqual(xs, sorted(xs) if xs[0] < xs[-1] else sorted(xs, reverse=True))

    def test_roads_are_ordered_best_first_and_branches_join_the_owner(self):
        chains = rb.build_chains([self.main1, self.main2, self.side], self.f)
        defs, start = rb.build_roads(chains)
        names = [d["name"] for d in defs]
        self.assertEqual(names[-1], "link")
        by = {d["name"]: d for d in defs}
        primaries = [d for d in defs if d["hw"] == 3.75]
        side = [d for d in defs if d["hw"] == 3.0][0]
        # The side road meets the first primary road at B and says so.
        joined = [side.get("start"), side.get("end")]
        self.assertTrue(any(j in {p["name"] for p in primaries} for j in joined), joined)
        for d in defs:                                # a parent always comes before its branches
            for end in ("start", "end"):
                if d.get(end) and d["name"] != "link":
                    self.assertLess(names.index(d[end]), names.index(d["name"]))
        self.assertEqual(by["link"]["start"], "loop")
        self.assertLess(abs(start[0] - rb.START_WORLD[0]), 1.0)

    def test_clip_removes_roads_near_the_shed_and_keeps_far_ends(self):
        chain = {"pts": [(-100.0, 0.0), (0.0, 0.0), (400.0, 0.0), (900.0, 0.0)], "start_node": "S", "end_node": "E",
                 "cls": "primary", "kind": "tarmac", "hw": 3.75, "grade": 0.12}
        pieces = rb.clip_chain(chain)
        self.assertEqual(len(pieces), 1)
        self.assertEqual(pieces[0]["pts"], [(400.0, 0.0), (900.0, 0.0)])
        self.assertIsNone(pieces[0]["start_node"])
        self.assertEqual(pieces[0]["end_node"], "E")

    def test_start_must_be_on_a_road(self):
        far = seg("A", "B", [(134.4, 34.6), (134.41, 34.6)], "primary")
        with self.assertRaises(SystemExit):
            rb.build_roads(rb.build_chains([far], self.f))


if __name__ == "__main__":
    unittest.main()
