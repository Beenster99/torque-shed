"""Offline tests for route_bake.py (no network): python3 -m unittest discover -s tools -p 'test_*.py'"""
import math
import os
import struct
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import levels  # noqa: E402
import route_bake as rb  # noqa: E402


def wkb_line(points):
    return struct.pack("<BII", 1, 2, len(points)) + b"".join(struct.pack("<dd", *p) for p in points)


def seg(a, b, pts, cls="secondary", surface=None, names=None, routes=None):
    """A fake Overture segment from connector a to b through `pts` ((lon, lat) pairs)."""
    return {"id": a + b, "subtype": "road", "class": cls, "geometry": wkb_line(pts),
            "connectors": [{"connector_id": a, "at": 0.0}, {"connector_id": b, "at": 1.0}],
            "road_surface": surface, "road_flags": None, "names": names, "routes": routes}


def curvature_at(p):
    a, b, c = p[:-2], p[1:-1], p[2:]
    ab, bc, ac = np.hypot(*(b - a).T), np.hypot(*(c - b).T), np.hypot(*(c - a).T)
    cross = np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0]))
    return 2.0 * cross / np.maximum(ab * bc * ac, 1e-9)


class LiveHeightsTests(unittest.TestCase):
    """bake_terrain with heights=False: no height tiles, but the sea still found (the game reads heights live)."""

    class FlatDem:
        def __init__(self, level):
            self.level = level

        def heights(self, lat, lon):
            # Sea west of the anchor's meridian, land east of it.
            return np.where(np.asarray(lon) < 0.0, 0.0, 20.0)

    def bake(self, heights):
        out = tempfile.mkdtemp()
        frame = rb.Frame(0.0, 0.0)
        knots = np.array([[-2000.0 + 50.0 * i, 0.0] for i in range(81)])
        dems = {lv.name: self.FlatDem(lv) for lv in levels.LEVELS}
        land = {"buildings": []}
        tiles, has_sea, _ = rb.bake_terrain(out, frame, knots, dems, lambda cover: land, lambda *a: None, heights=heights)
        written = [f for _, _, files in os.walk(out) for f in files if f.endswith(".u16z")]
        return tiles, has_sea, written

    def test_live_writes_no_heights_and_still_finds_the_sea(self):
        tiles, has_sea, written = self.bake(False)
        self.assertTrue(has_sea)
        self.assertEqual(written, [])
        self.assertTrue(tiles["fine"])

    def test_baked_writes_every_level(self):
        tiles, has_sea, written = self.bake(True)
        self.assertTrue(has_sea)
        self.assertEqual(len(written), sum(len(v) for v in tiles.values()))


class GeodesyTests(unittest.TestCase):
    def test_anchor_lands_at_start_and_north_is_negative_z(self):
        f = rb.Frame(34.5, 134.3)
        x, z = f.to_world(34.5, 134.3)
        self.assertAlmostEqual(float(x), 0.0, places=6)
        self.assertAlmostEqual(float(z), 0.0, places=6)
        self.assertLess(float(f.to_world(34.51, 134.3)[1]), 0.0)
        self.assertGreater(float(f.to_world(34.5, 134.31)[0]), 0.0)

    def test_round_trip_and_shifted_frames(self):
        f = rb.Frame(51.5, -0.1)
        lat, lon = f.to_geo(*f.to_world(51.52, -0.05))
        self.assertAlmostEqual(float(lat), 51.52, places=9)
        g = f.shifted((1000.0, -500.0))
        gx, gz = f.to_world(51.52, -0.05)
        sx, sz = g.to_world(51.52, -0.05)
        self.assertAlmostEqual(float(gx - sx), 1000.0, places=6)
        self.assertAlmostEqual(float(gz - sz), -500.0, places=6)

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
            self.assertLessEqual(40075016.686 * math.cos(math.radians(lat)) / (512 * 2 ** z), 4.0)

    def test_bilinear(self):
        a = np.array([[0.0, 10.0], [20.0, 30.0]])
        self.assertAlmostEqual(float(rb.bilinear(a, np.array(0.5), np.array(0.5))), 15.0)

    def test_quantise_round_trips_within_a_step(self):
        h = np.linspace(-200.0, 3700.0, 1000)
        q = rb.quantise(h)
        self.assertEqual(q.dtype, np.dtype("<u2"))
        back = levels.MIN + q.astype(float) * rb.HEIGHT_SCALE
        self.assertLessEqual(float(np.abs(back - h).max()), rb.HEIGHT_SCALE)

    def test_sea_gets_a_floor_and_land_is_left_alone(self):
        n = 129
        ground = np.full((n, n), 30.0)
        ground[:, : n // 2] = 0.0
        out, sea = rb.shape_sea(ground, spacing=16.0)
        self.assertTrue(sea)
        self.assertTrue(np.all(out[:, -1] == 30.0))
        self.assertTrue(np.all(out[:, : n // 2] < 0.0))
        self.assertLess(out[0, 0], out[0, n // 2 - 1])        # deeper away from the shore

    def test_a_pond_is_not_a_sea(self):
        ground = np.full((65, 65), 30.0)
        ground[10:14, 10:14] = 0.0
        out, sea = rb.shape_sea(ground, spacing=16.0)
        self.assertFalse(sea)
        self.assertTrue(np.array_equal(out, ground))

    def test_box_blur_keeps_a_constant(self):
        self.assertTrue(np.allclose(rb.box_blur(np.full((40, 50), 3.0), 5), 3.0))


class GeometryTests(unittest.TestCase):
    def test_wkb(self):
        self.assertEqual(rb.parse_wkb(wkb_line([(1.0, 2.0), (3.0, 4.0)])), [[(1.0, 2.0), (3.0, 4.0)]])
        multi = struct.pack("<BII", 1, 5, 2) + wkb_line([(0.0, 0.0), (1.0, 1.0)]) + wkb_line([(2.0, 2.0), (3.0, 3.0)])
        self.assertEqual(len(rb.parse_wkb(multi)), 2)

    def test_classes_and_names(self):
        self.assertEqual(rb.segment_kind({"subtype": "road", "class": "primary"}), ("primary", "tarmac"))
        self.assertEqual(rb.segment_kind({"subtype": "road", "class": "track"}), ("track", "gravel"))
        self.assertIsNone(rb.segment_kind({"subtype": "road", "class": "footway"}))
        gravel = rb.segment_kind({"subtype": "road", "class": "residential",
                                  "road_surface": [{"value": "gravel", "between": None}]})
        self.assertEqual(gravel, ("residential", "gravel"))
        en = {"names": {"primary": "上庄池田線", "common": [("ja", "上庄池田線"), ("en", "Kamisho Ikeda Line")]}}
        self.assertEqual(rb.segment_label(en), "Kamisho Ikeda Line")
        self.assertEqual(rb.segment_label({"names": {"primary": "X"}, "routes": [{"ref": "27"}]}), "Route 27")
        self.assertEqual(rb.segment_label({"names": {"primary": "上庄"}}), "上庄")
        self.assertIsNone(rb.segment_label({"names": None}))


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.f = rb.Frame(34.5, 134.3)
        lon0, lat0 = 134.3, 34.5
        st = 0.003    # about 275 m of longitude
        line = lambda i0, i1: [(lon0 + st * i, lat0) for i in range(i0, i1 + 1)]
        # A main road A-B-C-D east and on to G, a side road B-E north, a spur D-F south.
        self.segs = [
            seg("A", "B", line(0, 3), "primary"), seg("B", "C", line(3, 6), "primary"),
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
        self.assertEqual([s[2] for s in g.path(prev, "A", "D")], ["B", "C", "D"])

    def test_one_way_roads_are_only_driven_their_way(self):
        segs = list(self.segs)
        segs[1]["access_restrictions"] = [{"access_type": "denied", "when": {"heading": "backward"}, "between": None}]
        g = rb.Graph(segs, self.f)
        self.assertEqual(rb.segment_direction(segs[1]), 1)
        self.assertIsNotNone(g.shortest("A", "D"))
        self.assertIsNone(g.shortest("D", "A"))   # B-C can't be driven back, and there's no other way round
        segs[1]["access_restrictions"] = [{"access_type": "denied", "when": {"heading": "backward", "mode": ["bicycle"]}, "between": None}]
        self.assertEqual(rb.segment_direction(segs[1]), 0)   # a rule for bicycles only is no rule for us

    def test_a_banned_turn_is_not_taken(self):
        segs = list(self.segs)
        # Coming along A-B, turning north onto B-E is prohibited.
        segs[0]["prohibited_transitions"] = [{"sequence": [{"segment_id": "BE", "connector_id": "B"}], "when": None, "between": None}]
        g = rb.Graph(segs, self.f)
        self.assertEqual(len(g.bans), 1)
        self.assertIsNone(g.shortest("A", "E"))
        self.assertIsNotNone(g.shortest("C", "E"))

    def test_main_roads_cost_less_per_metre(self):
        g = rb.Graph(self.segs, self.f)
        per_m = lambda cls: next(g.weight(i) / g.edges[i]["length"] for i, e in enumerate(g.edges) if e["cls"] == cls)
        self.assertLess(per_m("primary"), per_m("residential"))

    def test_choose_end_hits_the_length_or_warns(self):
        g = rb.Graph(self.segs, self.f)
        _, length, _ = g.dijkstra("A")
        end, warn = rb.choose_end(g, "A", 2500.0)
        self.assertIsNone(warn)
        self.assertTrue(0.9 * 2500.0 <= length[end] <= 1.15 * 2500.0)
        end, warn = rb.choose_end(g, "A", 50000.0)
        self.assertIsNotNone(warn)

    def test_turns(self):
        g = rb.Graph(self.segs, self.f)
        _, _, prev = g.dijkstra("A")
        pts, owner, turns = rb.route_from_path(g, g.path(prev, "A", "E"))
        self.assertEqual(turns[0]["turn"], "left")            # north off an eastbound road
        self.assertEqual(len(pts), len(owner))
        pts, owner, turns = rb.route_from_path(g, g.path(prev, "A", "F"))
        self.assertEqual([t["turn"] for t in turns], ["straight", "right"])

    def test_classify_turn(self):
        self.assertEqual(rb.classify_turn(5), "straight")
        self.assertEqual(rb.classify_turn(-40), "slight_left")
        self.assertEqual(rb.classify_turn(90), "right")
        self.assertEqual(rb.classify_turn(-170), "sharp_left")


class RoadKnotTests(unittest.TestCase):
    def test_resample_spacing_and_ends(self):
        pts, cum, total = rb.resample([(0.0, 0.0), (100.0, 0.0), (100.0, 60.0)], 4.0)
        self.assertAlmostEqual(total, 160.0)
        self.assertEqual(tuple(pts[0]), (0.0, 0.0))
        self.assertEqual(tuple(pts[-1]), (100.0, 60.0))
        pts, _, _ = rb.resample([(0.0, 0.0), (100.0, 0.0)], 4.0, exact=True)
        self.assertTrue(np.allclose(np.hypot(*np.diff(pts, axis=0).T), 4.0))

    def test_a_gentle_road_is_left_as_mapped(self):
        xs = np.arange(0.0, 800.0, 10.0)
        zs = 30.0 * np.sin(xs / 120.0)
        knots = rb.smooth_line(np.stack([xs, zs], axis=1))
        ref, _, _ = rb.resample(np.stack([xs, zs], axis=1), 4.0, exact=True)
        n = min(len(knots), len(ref))
        self.assertLess(float(np.hypot(*(knots[:n] - ref[:n]).T).max()), 1.0)

    def test_a_kinked_road_gets_no_bend_tighter_than_the_limit_and_keeps_its_length(self):
        # A road with a sharp dog-leg at every junction, like a mapped road through a village.
        pts = [(0.0, 0.0), (200.0, 0.0), (200.0, 5.0), (400.0, 5.0), (400.0, 60.0), (600.0, 60.0)]
        knots = rb.smooth_line(pts)
        self.assertLessEqual(float(curvature_at(knots).max()), 1.0 / rb.MIN_RADIUS * 1.15)
        raw = rb.length_of(pts)
        got = float(np.hypot(*np.diff(knots, axis=0).T).sum())
        self.assertGreater(got, raw * 0.97)
        self.assertLess(float(np.hypot(*(knots[0] - np.array(pts[0])))), 0.01)
        self.assertLess(float(np.hypot(*(knots[-1] - np.array(pts[-1])))), 4.5)

    def test_grade_limit(self):
        e = np.concatenate([np.zeros(50), np.full(50, 100.0)])    # a 100 m cliff
        out = rb.grade_limit(e)
        self.assertLessEqual(float(np.abs(np.diff(out)).max()), rb.MAX_GRADE * rb.STEP + 1e-9)
        self.assertTrue(np.allclose(rb.grade_limit(np.linspace(0, 10, 100)), np.linspace(0, 10, 100)))

    def test_smooth_heights_flattens_a_bump_and_keeps_the_ends(self):
        h = np.zeros(60)
        h[30] = 9.0
        out = rb.smooth_heights(h)
        self.assertLess(out.max(), 2.0)
        self.assertAlmostEqual(out[0], 0.0)

    def test_chunk_attributes_vote_by_length(self):
        g = rb.Graph([seg("A", "B", [(134.3, 34.5), (134.31, 34.5)], "primary"),
                      seg("B", "C", [(134.31, 34.5), (134.32, 34.5)], "track")], rb.Frame(34.5, 134.3))
        n = 100
        edge = lambda s: 0 if s < 200.0 else 1
        chunks = rb.chunk_attributes(n, edge, g)
        self.assertEqual(len(chunks), 4)                       # 396 m: four 128 m chunks (the last short)
        self.assertEqual(chunks[0]["surface"], "tarmac")
        self.assertEqual(chunks[0]["width"], 7.4)
        self.assertEqual(chunks[3]["surface"], "gravel")
        self.assertEqual(chunks[3]["width"], 3.3)
        self.assertEqual(chunks[0]["name"], "Main road")

    def test_corridor_tiles_cover_the_road_and_its_reach(self):
        knots = np.stack([np.arange(0.0, 1000.0, 4.0), np.zeros(250)], axis=1)
        tiles = rb.corridor_tiles(knots, reach=600.0)
        have = set(tiles)
        for x, z in knots[::10]:
            for ox, oz in ((0, 0), (-590, 0), (590, 0), (0, -590), (0, 590)):
                self.assertIn((int(math.floor((x + ox) / rb.TILE_M)), int(math.floor((z + oz) / rb.TILE_M))), have)
        self.assertNotIn((0, 5), have)

    def test_tile_heights_from_a_flat_dem(self):
        class Flat:
            def heights(self, lat, lon):
                return np.full(np.shape(lat), 50.0)
        h, sea = rb.tile_heights(Flat(), rb.Frame(34.5, 134.3), 0, 0)
        self.assertEqual(h.shape, (rb.TILE_N, rb.TILE_N))
        self.assertFalse(sea)
        self.assertTrue(np.allclose(h, 50.0))

        class Coast:
            def heights(self, lat, lon):
                return np.where(np.asarray(lon) < 134.3, 0.0, 40.0)
        h, sea = rb.tile_heights(Coast(), rb.Frame(34.5, 134.3), -1, 0)
        self.assertTrue(sea)
        self.assertLess(h.min(), -2.0)

    def test_pack_hash_ignores_pack_json_and_follows_the_data(self):
        with tempfile.TemporaryDirectory() as d:
            for name, text in (("route.json", "a"), ("pack.json", "x")):
                with open(os.path.join(d, name), "w") as f:
                    f.write(text)
            first = rb.pack_hash(d)
            with open(os.path.join(d, "pack.json"), "w") as f:
                f.write("y")
            self.assertEqual(first, rb.pack_hash(d))
            with open(os.path.join(d, "route.json"), "w") as f:
                f.write("b")
            self.assertNotEqual(first, rb.pack_hash(d))


class Summary(unittest.TestCase):
    def test_roads_by_length_and_the_climb(self):
        chunks = [{"name": "Main road"}] * 5 + [{"name": "A65"}] * 3 + [{"name": "B6255"}] * 7 + [{"name": "Minor road"}] * 4
        got = rb.road_summary(chunks, None, [100.0, 140.0, 120.0, 300.0, 250.0], {"from": "Settle", "to": "Leyburn"})
        self.assertEqual(got["roads"], ["B6255", "A65"])
        self.assertEqual((got["climb_m"], got["top_m"], got["low_m"]), (220, 300, 100))
        self.assertEqual((got["from"], got["to"]), ("Settle", "Leyburn"))


class Spurs(unittest.TestCase):
    def test_out_and_back_is_taken_out(self):
        steps = [("a", 0, "b"), ("b", 1, "c"), ("c", 2, "d"), ("d", 2, "c"), ("c", 1, "b"), ("b", 3, "e")]
        self.assertEqual(rb.strip_spurs(steps), [("a", 0, "b"), ("b", 3, "e")])
        self.assertEqual(rb.strip_spurs([("a", 0, "b"), ("b", 1, "c")]), [("a", 0, "b"), ("b", 1, "c")])
        self.assertEqual(rb.strip_spurs([]), [])


class Connectors(unittest.TestCase):
    def test_a_segment_is_cut_at_its_middle_connectors(self):
        pts = [(0.0, 0.0), (1000.0, 0.0)]
        cons = [{"connector_id": "a", "at": 0.0}, {"connector_id": "m", "at": 0.25}, {"connector_id": "b", "at": 1.0}]
        parts = rb.cut_at_connectors(pts, cons)
        self.assertEqual([(a, b) for a, b, _ in parts], [("a", "m"), ("m", "b")])
        self.assertAlmostEqual(rb.length_of(parts[0][2]), 250.0, places=6)
        self.assertAlmostEqual(rb.length_of(parts[1][2]), 750.0, places=6)
        self.assertEqual(parts[1][2][0], parts[0][2][-1])

    def test_a_road_joined_part_way_along_is_reachable_through_the_graph(self):
        f = rb.Frame(34.5, 134.3)

        def ll(x, z):
            lat, lon = f.to_geo(x, z)
            return (float(lon), float(lat))
        long_road = {"id": "L", "subtype": "road", "class": "primary", "geometry": wkb_line([ll(0, 0), ll(500, 0), ll(1000, 0)]),
                     "connectors": [{"connector_id": "a", "at": 0.0}, {"connector_id": "m", "at": 0.5}, {"connector_id": "b", "at": 1.0}],
                     "road_surface": None, "road_flags": None, "names": None, "routes": None}
        side = {"id": "S", "subtype": "road", "class": "tertiary", "geometry": wkb_line([ll(500, 0), ll(500, -400)]),
                "connectors": [{"connector_id": "m", "at": 0.0}, {"connector_id": "c", "at": 1.0}],
                "road_surface": None, "road_flags": None, "names": None, "routes": None}
        g = rb.Graph([long_road, side], f)
        self.assertEqual(len(g.edges), 3)
        cost, length, prev = g.dijkstra("a")
        self.assertIn("c", prev)                    # a to the side road's end, through the junction in the middle
        self.assertAlmostEqual(length["c"], 900.0, delta=1.0)
        self.assertEqual(len(g.adj["m"]), 3)       # a junction, as the fork finder needs
        self.assertEqual(len(g.component_of("a")), 4)
        # a stray bit of road is a component of its own, which nothing snaps to unless it is the start's
        stray = dict(side, id="Z", geometry=wkb_line([ll(3000, 3000), ll(3000, 3400)]),
                     connectors=[{"connector_id": "y", "at": 0.0}, {"connector_id": "z", "at": 1.0}])
        g2 = rb.Graph([long_road, side, stray], f)
        self.assertNotIn("y", g2.component_of("a"))
        self.assertIsNone(g2.nearest_node((g2.pos["y"][0], g2.pos["y"][1]), 5.0, g2.component_of("a")))
        self.assertEqual(g2.nearest_node((g2.pos["y"][0], g2.pos["y"][1]), 5.0), "y")
        # a start point snaps to a real network over a stray bit of road next to it
        self.assertEqual(g2.nearest_connected((g2.pos["a"][0], g2.pos["a"][1]), 5.0, min_nodes=3), "a")


class Levels(unittest.TestCase):
    def field(self, level, value):
        return rb.LevelField(level, {(0, 0): np.full((level.n, level.n), float(value))})

    def test_tile_codec_round_trips_exactly_and_is_smaller(self):
        rng = np.random.default_rng(3)
        z, x = np.mgrid[0:128, 0:128]
        q = (np.sin(x / 9.0) * 900 + z * 7 + rng.integers(0, 3, (128, 128)) + 4000).astype("<u2")
        data = levels.encode_heights(q)
        self.assertTrue(np.array_equal(levels.decode_heights(data, 128), q))
        self.assertLess(len(data), q.nbytes * 0.6)
        wrap = np.array([[0, 65535, 3], [65535, 0, 7], [1, 2, 65530]], dtype="<u2")   # a step across the uint16 range
        self.assertTrue(np.array_equal(levels.decode_heights(levels.encode_heights(wrap), 3), wrap))

    def test_levels_get_coarser_and_reach_further(self):
        f, c, r = levels.LEVELS
        self.assertLess(f.spacing, c.spacing)
        self.assertLess(c.spacing, r.spacing)
        self.assertLess(f.reach, c.reach)
        self.assertLess(c.reach, r.reach)
        self.assertGreater(r.reach, 10000.0)
        self.assertGreaterEqual(c.reach, 1500.0)   # the land mesh runs 1 km out and a bit past it

    def test_quantise_per_level_round_trips_within_its_step(self):
        h = np.array([-12.3, 0.0, 41.7, 640.2, 2100.9])
        for lv in levels.LEVELS:
            back = lv.dequantise(lv.quantise(h))
            self.assertLessEqual(float(np.abs(back - h).max()), lv.scale)

    def test_field_is_bilinear_and_nan_beyond_its_tiles(self):
        lv = levels.COARSE
        t = np.zeros((lv.n, lv.n))
        t[:, :] = np.arange(lv.n)[None, :] * 10.0   # 10 m a sample eastwards
        f = rb.LevelField(lv, {(0, 0): t})
        got = f.heights(np.array([16.0, 48.0]), np.array([100.0, 100.0]))
        self.assertAlmostEqual(float(got[0]), 5.0, places=6)
        self.assertAlmostEqual(float(got[1]), 15.0, places=6)
        self.assertTrue(np.isnan(f.heights(np.array([-50.0]), np.array([10.0]))[0]))

    def test_field_reads_across_tile_seams(self):
        lv = levels.COARSE
        f = rb.LevelField(lv, {(0, 0): np.full((lv.n, lv.n), 4.0), (1, 0): np.full((lv.n, lv.n), 8.0)})
        edge = lv.size_m
        self.assertAlmostEqual(float(f.heights(np.array([edge - lv.spacing / 2]), np.array([10.0]))[0]), 6.0, places=6)

    def test_blend_eases_a_free_edge_into_the_coarser_level(self):
        lv = levels.FINE
        coarse = self.field(levels.COARSE, 50.0)
        h = np.zeros((lv.n, lv.n))
        out = rb.blend_edges(h, lv, 0, 0, {(0, 0)}, coarse, 16)
        self.assertAlmostEqual(float(out[64, 0]), 50.0, delta=0.01)   # the free west edge is the coarse height
        self.assertAlmostEqual(float(out[64, 64]), 0.0, places=6)     # the middle is untouched
        self.assertTrue(np.all(np.diff(out[64, :17]) <= 1e-9))         # easing back, never past it
        # Only the diagonal tile missing: that corner is free, and eased.
        corner = rb.blend_edges(h, lv, 0, 0, {(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1)}, coarse, 16)
        self.assertAlmostEqual(float(corner[lv.n - 1, lv.n - 1]), 50.0, delta=0.01)
        self.assertAlmostEqual(float(corner[64, 64]), 0.0, places=6)
        joined = rb.blend_edges(h, lv, 0, 0, {(a, b) for a in (-1, 0, 1) for b in (-1, 0, 1)}, coarse, 16)
        self.assertEqual(float(joined.max()), 0.0)                      # with every neighbour present, nothing changes

    def test_ridge_is_pushed_down_near_the_road_and_real_far_off(self):
        lv = levels.RIDGE
        h = np.full((lv.n, lv.n), 300.0)
        knots = np.array([[x, 0.0] for x in np.arange(0.0, 8000.0, 4.0)])
        out = rb.ridge_tile(h, 0, 0, knots)
        near = out[1, 20]    # z = 128 m, x = 2560 m: by the road
        far = out[200, 20]   # z = 25 km: well away
        self.assertAlmostEqual(float(near), 300.0 - rb.RIDGE_LOWER_M, delta=0.5)
        self.assertAlmostEqual(float(far), 300.0, delta=0.5)

    def test_ridge_sea_is_just_under_the_water(self):
        lv = levels.RIDGE
        h = np.full((lv.n, lv.n), -20.0)
        out = rb.ridge_tile(h, 0, 0, np.array([[0.0, 0.0], [8.0, 0.0]]))
        self.assertTrue(np.all(out <= rb.RIDGE_SEA_M + 1e-9))
        self.assertTrue(np.all(out <= -20.0))

    def test_bake_terrain_writes_every_level(self):
        class Slope:
            def heights(self, lat, lon):
                return 400.0 + (np.asarray(lon) - 134.3) * 1000.0
        frame = rb.Frame(34.5, 134.3)
        knots = np.array([[float(x), 0.0] for x in range(0, 1200, 4)])
        with tempfile.TemporaryDirectory() as d:
            tiles, sea, land = rb.bake_terrain(d, frame, knots, {lv.name: Slope() for lv in levels.LEVELS},
                                               lambda t: {"buildings": [], "tiles": t}, log=lambda *_: None)
            self.assertFalse(sea)
            self.assertEqual(set(tiles), {"fine", "coarse", "ridge"})
            for lv in levels.LEVELS:
                for tx, tz in tiles[lv.name]:
                    with open(os.path.join(d, lv.folder, "%d_%d.u16z" % (tx, tz)), "rb") as f:
                        q = levels.decode_heights(f.read(), lv.n)
                    self.assertEqual(q.shape, (lv.n, lv.n))
            self.assertEqual(set(land["tiles"]), {"fine", "coarse"})
            self.assertLess(len(tiles["coarse"]), len(tiles["fine"]) * 10)


if __name__ == "__main__":
    unittest.main()
