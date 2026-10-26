#!/usr/bin/env python3
"""Tests for profile_bake.py (a cell's place profile), on made-up parts: nothing is fetched.

    python3 -m unittest tools/test_profile_bake.py
"""
import json
import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import land_bake  # noqa: E402
import profile_bake as pb  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "profiles")
CLIMATE = {k: [10.0 + m for m in range(12)] for k in pb.CLIMATE_KEYS}


def dales_parts():
    return {"countries": [("GB", "United Kingdom", 1.0)], "region": ("North Yorkshire", "GB-NYK"),
            "koppen": np.array([[15, 15], [15, 16]]), "cover": {30: 900, 10: 50, 50: 20, 80: 30}, "sea": 0.0,
            "coast": False, "heights": [120.0, 340.0, 700.0], "climate": CLIMATE}


class FakeSources:
    """Stands in for the real sources: a profile of made-up parts for any cell, counting how many it made."""

    def __init__(self, with_tint=False):
        self.with_tint = with_tint
        self.made = []

    def profile(self, cell):
        self.made.append(cell)
        return pb.make_profile(cell, dales_parts())


class ProfileBakeTests(unittest.TestCase):
    def test_koppen_is_the_zone_most_of_the_cell_is(self):
        self.assertEqual(pb.koppen_of([[15, 15, 8], [0, 0, 0]]), "Cfb")
        self.assertEqual(pb.koppen_of([[0, 0]]), "")
        self.assertEqual(pb.KOPPEN[29], "ET")

    def test_cover_mix_sums_to_one_without_the_sea(self):
        mix = pb.cover_mix({30: 500, 80: 500}, sea=0.4)
        self.assertEqual(set(mix), set(land_bake.COVER))
        self.assertAlmostEqual(sum(mix.values()), 1.0, places=6)
        # half the pixels were water, 0.4 of the cell the sea: of the land, 5/6 grass and 1/6 lakes
        self.assertAlmostEqual(mix["grass"], 0.833, places=2)
        self.assertAlmostEqual(mix["water"], 0.167, places=2)
        self.assertEqual(pb.cover_mix({}, sea=1.0)["water"], 1.0)
        self.assertEqual(pb.cover_mix({}, sea=0.0)["grass"], 1.0)

    def test_bands(self):
        self.assertEqual(pb.band(120, pb.ALTITUDE_BANDS), "lowland")
        self.assertEqual(pb.band(300, pb.ALTITUDE_BANDS), "upland")
        self.assertEqual(pb.band(1800, pb.ALTITUDE_BANDS), "mountain")
        self.assertEqual(pb.band(3000, pb.ALTITUDE_BANDS), "high")
        self.assertEqual(pb.band(0.0, pb.DENSITIES), "wild")
        self.assertEqual(pb.band(0.03, pb.DENSITIES), "village")
        self.assertEqual(pb.band(0.6, pb.DENSITIES), "city")

    def test_sun_hours_follow_the_day_and_the_cloud(self):
        self.assertGreater(pb.day_length(54.0, 6), 16.5)
        self.assertLess(pb.day_length(54.0, 12), 8.0)
        self.assertAlmostEqual(pb.day_length(0.0, 3), 12.0, delta=0.1)
        self.assertGreater(pb.sun_hours(10.0, 30.0, 7), 3 * pb.sun_hours(80.0, 30.0, 7))
        self.assertEqual(pb.sun_hours(100.0, 54.0, 1), 0)
        self.assertGreater(pb.day_length(-54.0, 12), 16.5)   # (the south's summer)

    def test_a_profile_has_every_field_of_the_fixture(self):
        p = pb.make_profile("576_712", dales_parts())
        with open(os.path.join(FIXTURES, "c576_712.json")) as f:
            fixture = json.load(f)
        self.assertEqual(set(fixture), set(p))
        self.assertEqual(p["country"], "GB")
        self.assertEqual(p["koppen"], "Cfb")
        self.assertEqual(p["altitude"], {"min": 120, "mean": 387, "max": 700})
        self.assertEqual(p["altitude_band"], "upland")
        self.assertAlmostEqual(p["lat"], 54.125)
        self.assertAlmostEqual(p["lon"], -1.875)
        self.assertEqual(p["built"], p["cover"]["urban"])
        self.assertEqual(sorted(p["climate"]), sorted(pb.CLIMATE_KEYS))
        self.assertTrue(all(len(v) == 12 for v in p["climate"].values()))
        self.assertIsNone(p["tint"])
        self.assertNotIn("tint", p["sources"])

    def test_the_hash_changes_with_the_profile_and_the_version(self):
        a = pb.make_profile("576_712", dales_parts())
        b = pb.make_profile("576_712", dales_parts())
        self.assertEqual(a["hash"], b["hash"])
        parts = dales_parts()
        parts["heights"] = [500.0]
        self.assertNotEqual(a["hash"], pb.make_profile("576_712", parts)["hash"])
        old = pb.PROFILE_VERSION
        try:
            pb.PROFILE_VERSION = old + 1
            c = pb.make_profile("576_712", dales_parts())
        finally:
            pb.PROFILE_VERSION = old
        self.assertNotEqual(a["hash"], c["hash"])
        self.assertNotEqual(a["bake_key"], c["bake_key"])
        self.assertNotEqual(pb.bake_key(False), pb.bake_key(True))

    def test_tint_is_a_small_png_and_its_mean(self):
        rgb = np.zeros((16, 16, 3), dtype=np.uint8)
        rgb[..., 1] = 100
        p = pb.make_profile("576_712", dales_parts(), rgb)
        self.assertEqual(p["tint"]["size"], 16)
        self.assertEqual(p["tint"]["rgb"], [0, 100, 0])
        import base64
        self.assertEqual(base64.b64decode(p["tint"]["png"])[:4], b"\x89PNG")
        self.assertIn("tint", p["sources"])
        self.assertEqual(pb.to_srgb([0, 10000]).tolist(), [0, 255])

    def test_tile_names_are_worldcovers(self):
        self.assertEqual(pb.WorldCover.tile_name(54.1, -1.9, 3)[0], "N54W003")
        self.assertEqual(pb.WorldCover.tile_name(31.1, -7.9, 3)[0], "N30W009")
        self.assertEqual(pb.WorldCover.tile_name(-33.9, 18.4, 1)[0], "S34E018")

    def test_a_world_rebake_redoes_only_what_changed(self):
        with tempfile.TemporaryDirectory() as d:
            index = os.path.join(d, "index.json")
            with open(index, "w") as f:
                json.dump({"format": 1, "cells": {"576_712": {"hash": "x"}, "560_640": {"empty": True}}}, f)
            src = FakeSources()
            self.assertEqual(pb.bake_world(index, d, src, log=lambda *a: None), (2, 0))
            with open(index) as f:
                idx = json.load(f)
            self.assertEqual(sorted(idx["profiles"]), ["560_640", "576_712"])
            with open(os.path.join(d, "profile", "c576_712.json")) as f:
                text = f.read().rstrip("\n")
            self.assertEqual(idx["profiles"]["576_712"], pb.text_hash(text))
            # Again: nothing to do.
            src = FakeSources()
            self.assertEqual(pb.bake_world(index, d, src, log=lambda *a: None), (0, 2))
            # A new version: all of them again.
            old = pb.PROFILE_VERSION
            try:
                pb.PROFILE_VERSION = old + 1
                self.assertEqual(pb.bake_world(index, d, FakeSources(), log=lambda *a: None), (2, 0))
            finally:
                pb.PROFILE_VERSION = old


if __name__ == "__main__":
    unittest.main()
