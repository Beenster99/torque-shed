"""Offline tests for route_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import math
import os
import struct
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import route_bake as rb  # noqa: E402


def wkb_line(points):
    return struct.pack("<BII", 1, 2, len(points)) + b"".join(struct.pack("<dd", *p) for p in points)


def wkb_polygon(points):
    ring = list(points) + [points[0]]
    return (struct.pack("<BII", 1, 3, 1) + struct.pack("<I", len(ring))
            + b"".join(struct.pack("<dd", *p) for p in ring))


def seg(a, b, pts, cls="secondary", surface=None, names=None, routes=None):
    """A fake Overture segment from connector a to b through `pts` ((lon, lat) pairs)."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return {"id": a + b, "subtype": "road", "class": cls, "geometry": wkb_line(pts),
            "connectors": [{"connector_id": a, "at": 0.0}, {"connector_id": b, "at": 1.0}],
            "road_surface": surface, "road_flags": None, "names": names, "routes": routes,
            "bbox": {"xmin": min(xs), "xmax": max(xs), "ymin": min(ys), "ymax": max(ys)}}


class GeodesyTests(unittest.TestCase):
    def test_anchor_lands_at_start_and_north_is_negative_z(self):
        f = rb.Frame(34.5, 134.3, rb.START_WORLD)
        x, z = f.to_world(34.5, 134.3)
        self.assertAlmostEqual(float(x), rb.START_WORLD[0], places=6)
        self.assertAlmostEqual(float(z), rb.START_WORLD[1], places=6)
        self.assertLess(float(f.to_world(34.51, 134.3)[1]), rb.START_WORLD[1])
        self.assertGreater(float(f.to_world(34.5, 134.31)[0]), rb.START_WORLD[0])

    def test_round_trip(self):
        f = rb.Frame(51.5, -0.1)
        lat, lon = f.to_geo(*f.to_world(51.52, -0.05))
        self.assertAlmostEqual(float(lat), 51.52, places=9)
        self.assertAlmostEqual(float(lon), -0.05, places=9)

    def test_a_shifted_frame_is_a_pure_translation(self):
        g = rb.Frame(34.5, 134.3)
        leg = g.shifted((1000.0, -500.0))
        gx, gz = g.to_world(34.52, 134.34)
        lx, lz = leg.to_world(34.52, 134.34)
        self.assertAlmostEqual(float(gx - lx), 1000.0, places=6)
        self.assertAlmostEqual(float(gz - lz), -500.0, places=6)
        lat, lon = leg.to_geo(lx, lz)
        self.assertAlmostEqual(float(lat), 34.52, places=9)

    def test_degree_lengths(self):
        self.assertAlmostEqual(rb.metres_per_degree(0.0)[0], 110574, delta=10)
        self.assertAlmostEqual(rb.metres_per_degree(60.0)[1], 55800, delta=50)


class HeightTests(unittest.TestCase):
    def test_terrarium_decode(self):
        from PIL import Image
        im = Image.new("RGB", (2, 1))
        im.putpixel((0, 0), (128, 0, 0))
        im.putpixel((1, 0), (128, 100, 128))
        h = rb.decode_terrarium(im)
        self.assertAlmostEqual(h[0, 0], 0.0)
        self.assertAlmostEqual(h[0, 1], 100.5)

    def test_zoom_gives_pixels_no_coarser_than_asked(self):
        for lat in (0.0, 34.5, 60.0):
            z = rb.tile_zoom(lat, 4.0)
            px = 40075016.686 * np.cos(np.radians(lat)) / (512 * 2 ** z)
            self.assertLessEqual(px, 4.0)

    def test_bilinear_and_quantise(self):
        a = np.array([[0.0, 10.0], [20.0, 30.0]])
        self.assertAlmostEqual(float(rb.bilinear(a, np.array(0.5), np.array(0.5))), 15.0)
        h = np.linspace(-600.0, 160.0, 1000).reshape(20, 50)
        q, lo, scale = rb.quantise(h)
        self.assertLessEqual(float(np.abs(q.astype(float) * scale + lo - h).max()), scale)

    def test_shed_is_level(self):
        n = 65
        ground = np.full((n, n), 300.0) + np.arange(n)[None, :] * 2.0
        rel, sea = rb.shape_heights(ground, 400.0, shed=True, spacing=64.0, size=n)
        ax = np.arange(n) * 64.0 - 2048.0
        shed = (np.abs(ax[None, :] - rb.SHED_CENTRE[0]) < 100) & (np.abs(ax[:, None] - rb.SHED_CENTRE[1]) < 100)
        self.assertTrue(np.all(np.abs(rel[shed]) < 1e-9))
        self.assertIsNone(sea)

    def test_sea_is_found_given_a_floor_and_the_land_left_alone(self):
        n = 129
        ground = np.full((n, n), 30.0)
        ground[:, : n // 2] = 0.0          # the western half is sea
        rel, sea = rb.shape_heights(ground, 30.0, shed=False, spacing=16.0, size=n)
        self.assertAlmostEqual(sea, -30.0)
        self.assertTrue(np.all(rel[:, -1] == 0.0))                     # land is land
        self.assertTrue(np.all(rel[:, 0] < sea - 10.0))                 # far from shore it is deep
        self.assertTrue(np.all(rel[:, : n // 2] < sea))                 # the sea floor is always under the water
        self.assertLess(rel[0, n // 2 - 1], rel[0, 0] + 40.0)

    def test_a_pond_is_not_a_sea(self):
        ground = np.full((65, 65), 30.0)
        ground[10:14, 10:14] = 0.0
        rel, sea = rb.shape_heights(ground, 30.0, spacing=16.0, size=65)
        self.assertIsNone(sea)

    def test_box_blur_keeps_a_constant(self):
        a = np.full((40, 50), 3.0)
        self.assertTrue(np.allclose(rb.box_blur(a, 5), 3.0))


class GeometryTests(unittest.TestCase):
    def test_wkb(self):
        self.assertEqual(rb.parse_wkb(wkb_line([(1.0, 2.0), (3.0, 4.0)])), [[(1.0, 2.0), (3.0, 4.0)]])
        poly = wkb_polygon([(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)])
        rings = rb.parse_wkb(poly)
        self.assertEqual(len(rings), 1)
        self.assertEqual(len(rings[0]), 5)
        multi = struct.pack("<BII", 1, 5, 2) + wkb_line([(0.0, 0.0), (1.0, 1.0)]) + wkb_line([(2.0, 2.0), (3.0, 3.0)])
        self.assertEqual(len(rb.parse_wkb(multi)), 2)

    def test_rdp(self):
        self.assertEqual(rb.rdp([(0, 0), (5, 0.1), (10, 0)], 1.0), [(0, 0), (10, 0)])
        self.assertEqual(len(rb.rdp([(0, 0), (5, 5), (10, 0)], 1.0)), 3)

    def test_resample_spacing(self):
        pts, dist = rb.resample([(0.0, 0.0), (100.0, 0.0), (100.0, 60.0)], 25.0)
        self.assertEqual(pts[0], (0.0, 0.0))
        self.assertEqual(pts[-1], (100.0, 60.0))
        self.assertAlmostEqual(dist[-1], 160.0)
        self.assertTrue(all(abs((b - a) - 25.0) < 1e-6 for a, b in zip(dist[:-2], dist[1:-1])))

    def test_classes_and_names(self):
        self.assertEqual(rb.segment_kind({"subtype": "road", "class": "primary"})[1], "tarmac")
        self.assertEqual(rb.segment_kind({"subtype": "road", "class": "track"})[1], "dirt")
        self.assertIsNone(rb.segment_kind({"subtype": "road", "class": "footway"}))
        unpaved = rb.segment_kind({"subtype": "road", "class": "residential",
                                   "road_surface": [{"value": "gravel", "between": None}]})
        self.assertEqual(unpaved[1], "dirt")
        en = {"names": {"primary": "上庄池田線", "common": [("ja", "上庄池田線"), ("en", "Kamisho Ikeda Line")]}}
        self.assertEqual(rb.segment_label(en), "Kamisho Ikeda Line")
        self.assertEqual(rb.segment_label({"names": {"primary": "X"}, "routes": [{"ref": "27"}]}), "Route 27")
        self.assertEqual(rb.segment_label({"names": {"primary": "上庄"}}), "上庄")
        self.assertIsNone(rb.segment_label({"names": None}))


class BuildingTests(unittest.TestCase):
    def test_min_rect_finds_a_turned_rectangle(self):
        # A 20 x 8 m rectangle turned 30 degrees, centred on (100, 50).
        yaw = math.radians(30)
        c, s = math.cos(yaw), math.sin(yaw)
        local = [(-10, -4), (10, -4), (10, 4), (-10, 4)]
        pts = [(100 + lx * c + lz * s, 50 - lx * s + lz * c) for lx, lz in local]
        cx, cz, w, d, got = rb.min_rect(pts)
        self.assertAlmostEqual(cx, 100.0, delta=0.5)
        self.assertAlmostEqual(cz, 50.0, delta=0.5)
        self.assertAlmostEqual(w * d, 160.0, delta=3.0)
        self.assertAlmostEqual(max(w, d), 20.0, delta=0.6)

    def test_kinds(self):
        self.assertEqual(rb.building_kind(4, 5), "shed")
        self.assertEqual(rb.building_kind(8, 10), "house")
        self.assertEqual(rb.building_kind(15, 60), "barn")

    def test_buildings_keep_clear_of_roads_and_become_boxes(self):
        f = rb.Frame(34.5, 134.3)
        # A road running east through the origin, a house 30 m north of it and one on it.
        road = [{"name": "r000", "hw": 3.5, "pts": [[-200.0, 0.0], [200.0, 0.0]]}]

        def footprint(cx, cz, w=10.0, d=8.0):
            pts = [(cx - w / 2, cz - d / 2), (cx + w / 2, cz - d / 2), (cx + w / 2, cz + d / 2), (cx - w / 2, cz + d / 2)]
            ring = [tuple(map(float, np.concatenate(f.to_geo(z, x)[::-1]))) if False else None for x, z in pts]
            lon_lat = [(float(f.to_geo(x, z)[1]), float(f.to_geo(x, z)[0])) for x, z in pts]
            return {"geometry": wkb_polygon(lon_lat), "height": None, "num_floors": 2}
        rows = [footprint(60.0, -30.0), footprint(0.0, 0.0), footprint(-60.0, 40.0)]
        out = rb.make_buildings(rows, f, road)
        xs = sorted(round(b["x"]) for b in out)
        self.assertEqual(xs, [-60, 60])                      # the one on the road is gone
        self.assertTrue(all(abs(b["z"]) > 20 for b in out))
        self.assertTrue(all(b["kind"] == "house" and 2.8 <= b["h"] <= 9.0 for b in out))

    def test_flatten_levels_the_ground_under_a_building(self):
        n = 129
        rel = np.fromfunction(lambda z, x: x * 0.5, (n, n))     # a slope rising east
        b = {"x": 0.0, "z": 0.0, "w": 12.0, "d": 10.0, "yaw": 0.0, "h": 5.0, "kind": "house"}
        out = rb.flatten_under(rel.copy(), [b], spacing=16.0, size=n, half=1024.0)
        ix = iz = n // 2
        under = out[iz - 0:iz + 1, ix - 0:ix + 1]
        self.assertTrue(np.allclose(under, under.mean()))
        self.assertTrue(np.allclose(out[:, 0], rel[:, 0]))      # far away is untouched


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.f = rb.Frame(34.5, 134.3)
        lon0, lat0 = 134.3, 34.5
        st = 0.003    # about 275 m of longitude
        line = lambda i0, i1, dz=0.0: [(lon0 + st * i, lat0 + dz) for i in range(i0, i1 + 1)]
        # A main road A-B-C-D east, a side road B-E north, a long loop-free spur D-F.
        self.segs = [
            seg("A", "B", line(0, 3), "primary"),
            seg("B", "C", line(3, 6), "primary"),
            seg("C", "D", line(6, 9), "primary"),
            seg("B", "E", [(lon0 + st * 3, lat0), (lon0 + st * 3, lat0 + 0.01)], "residential"),
            seg("D", "F", [(lon0 + st * 9, lat0), (lon0 + st * 9, lat0 - 0.01)], "tertiary"),
            seg("D", "G", line(9, 11), "primary"),
        ]

    def test_graph_and_dijkstra(self):
        g = rb.Graph(self.segs, self.f)
        self.assertEqual(len(g.edges), 6)
        cost, length, prev = g.dijkstra("A")
        self.assertAlmostEqual(length["D"], 9 * 0.003 * self.f.m_lon, delta=2.0)
        steps = g.path(prev, "A", "D")
        self.assertEqual([s[2] for s in steps], ["B", "C", "D"])

    def test_class_cost_makes_main_roads_cheaper(self):
        g = rb.Graph(self.segs, self.f)
        e_main = [i for i, e in enumerate(g.edges) if e["cls"] == "primary"][0]
        e_res = [i for i, e in enumerate(g.edges) if e["cls"] == "residential"][0]
        per_m = lambda i: g.weight(i) / g.edges[i]["length"]
        self.assertLess(per_m(e_main), per_m(e_res))

    def test_choose_end_hits_the_length(self):
        g = rb.Graph(self.segs, self.f)
        end, warn = rb.choose_end(g, "A", 2500.0)
        _, length, _ = g.dijkstra("A")
        self.assertIsNone(warn)
        self.assertGreaterEqual(length[end], 0.9 * 2500.0)
        self.assertLessEqual(length[end], 1.15 * 2500.0)

    def test_choose_end_warns_when_the_roads_run_out(self):
        g = rb.Graph(self.segs, self.f)
        end, warn = rb.choose_end(g, "A", 50000.0)
        self.assertIsNotNone(warn)
        self.assertEqual(end, max(g.dijkstra("A")[1], key=g.dijkstra("A")[1].get))

    def test_turns(self):
        g = rb.Graph(self.segs, self.f)
        _, _, prev = g.dijkstra("A")
        pts, turns = rb.route_from_path(g, g.path(prev, "A", "D"))
        # B has a side road, so it is listed (straight on); C and the ends are not junctions.
        self.assertEqual(len(turns), 1)
        self.assertEqual(turns[0]["turn"], "straight")
        _, _, prev = g.dijkstra("A")
        pts, turns = rb.route_from_path(g, g.path(prev, "A", "E"))
        self.assertEqual(turns[0]["turn"], "left")            # north off an eastbound road is a left turn
        _, _, prev = g.dijkstra("A")
        pts, turns = rb.route_from_path(g, g.path(prev, "A", "F"))
        self.assertEqual([t["turn"] for t in turns], ["straight", "right"])

    def test_classify_turn(self):
        self.assertEqual(rb.classify_turn(5), "straight")
        self.assertEqual(rb.classify_turn(-40), "slight_left")
        self.assertEqual(rb.classify_turn(90), "right")
        self.assertEqual(rb.classify_turn(-170), "sharp_left")

    def test_legs_cover_the_route_and_overlap(self):
        pts = [(float(x), 0.0) for x in range(0, 12000, 25)]
        dist = [p[0] for p in pts]
        shed_origin = (-800.0, 60.0)
        legs = rb.plan_legs(pts, dist, shed_origin)
        self.assertEqual(legs[0]["first"], 0)
        self.assertEqual(legs[-1]["last"], len(pts) - 1)
        for a, b in zip(legs, legs[1:]):
            self.assertLess(b["first"], a["last"])                                   # they overlap
            self.assertGreaterEqual(a["exit_d"] - b["enter_d"], rb.OVERLAP_M - 25.0)
        for leg in legs:
            for p in pts[leg["first"]:leg["last"] + 1]:
                self.assertLessEqual(abs(p[0] - leg["origin"][0]), rb.LEG_REACH + 1e-6)
                self.assertLessEqual(abs(p[1] - leg["origin"][1]), rb.LEG_REACH + 1e-6)

    def test_a_short_route_is_one_leg(self):
        pts = [(float(x), 0.0) for x in range(0, 900, 25)]
        legs = rb.plan_legs(pts, [p[0] for p in pts], (-800.0, 60.0))
        self.assertEqual(len(legs), 1)


class RoadBuildTests(unittest.TestCase):
    def setUp(self):
        self.f = rb.Frame(34.5, 134.3, rb.START_WORLD)
        lon0, lat0 = 134.3, 34.5
        self.step = 0.003
        pts = lambda i0, i1: [(lon0 + self.step * i, lat0) for i in range(i0, i1 + 1)]
        self.main1 = seg("A", "B", pts(0, 2), "primary", names={"primary": "X", "common": [("en", "Coast Road")]})
        self.main2 = seg("B", "C", pts(2, 4), "primary")
        self.side = seg("D", "B", [(lon0 + 2 * self.step, lat0 - 0.003), (lon0 + 2 * self.step, lat0)], "residential")

    def test_degree_two_joins_merge_and_junctions_split(self):
        self.assertEqual(len(rb.build_chains([self.main1, self.main2, self.side], self.f)), 3)
        chains = rb.build_chains([self.main1, self.main2], self.f)
        self.assertEqual(len(chains), 1)
        self.assertEqual(len(chains[0]["pts"]), 5)
        self.assertEqual({chains[0]["start_node"], chains[0]["end_node"]}, {"A", "C"})
        self.assertEqual(chains[0]["label"], "Coast Road")       # the name carried by the merged segments

    def test_unnamed_roads_get_their_class(self):
        chains = rb.build_chains([self.main2], self.f)
        self.assertEqual(chains[0]["label"], "Main road")

    def test_roads_ordered_best_first_and_branches_join_the_owner(self):
        chains = rb.build_chains([self.main1, self.main2, self.side], self.f)
        defs, start = rb.build_roads(chains, start=rb.START_WORLD, shed=True)
        names = [d["name"] for d in defs]
        self.assertEqual(names[-1], "link")
        side = [d for d in defs if d["hw"] == 3.0][0]
        primaries = {d["name"] for d in defs if d["hw"] == 3.75}
        self.assertTrue(any(side.get(e) in primaries for e in ("start", "end")))
        for d in defs:
            for end in ("start", "end"):
                if d.get(end) and d["name"] != "link":
                    self.assertLess(names.index(d[end]), names.index(d["name"]))
        self.assertTrue(all("label" in d for d in defs))

    def test_a_leg_without_the_shed_has_no_link_and_no_keep_out(self):
        chains = rb.build_chains([self.main1, self.main2], rb.Frame(34.5, 134.3, (0.0, 0.0)))
        defs, start = rb.build_roads(chains, shed=False)
        self.assertEqual(len(defs), 1)
        self.assertIsNone(start)

    def test_clip_removes_roads_near_the_shed_and_keeps_far_ends(self):
        chain = {"pts": [(-100.0, 0.0), (0.0, 0.0), (400.0, 0.0), (900.0, 0.0)], "start_node": "S", "end_node": "E"}
        pieces = rb.clip_chain(chain, centre=rb.SHED_CENTRE)
        self.assertEqual(len(pieces), 1)
        self.assertEqual(pieces[0]["pts"], [(400.0, 0.0), (900.0, 0.0)])
        self.assertIsNone(pieces[0]["start_node"])
        self.assertEqual(pieces[0]["end_node"], "E")
        self.assertEqual(len(rb.clip_chain(chain, centre=None)[0]["pts"]), 4)

    def test_start_must_be_on_a_road(self):
        far = seg("A", "B", [(134.4, 34.6), (134.41, 34.6)], "primary")
        with self.assertRaises(SystemExit):
            rb.build_roads(rb.build_chains([far], self.f), start=rb.START_WORLD, shed=True)


if __name__ == "__main__":
    unittest.main()
