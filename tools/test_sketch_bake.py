#!/usr/bin/env python3
"""Tests for sketch_bake.py (the main-roads sketch of a cell for the Route planner TV), on the Dales fixture cell.

    python3 -m unittest tools/test_sketch_bake.py
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sketch_bake as sb  # noqa: E402

CELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "cells", "c577_711")


def points(line):
    """A sketch line's points (lat, lon in degrees), its steps added up."""
    flat = line[1]
    out = [(flat[0], flat[1])]
    for i in range(2, len(flat), 2):
        out.append((out[-1][0] + flat[i], out[-1][1] + flat[i + 1]))
    return [(a / sb.SCALE, b / sb.SCALE) for a, b in out]


class SketchTests(unittest.TestCase):
    def test_a_cells_main_roads_in_few_lines_inside_it(self):
        s = sb.cell_sketch(CELL)
        self.assertEqual(s["cell"], "577_711")
        self.assertTrue(s["lines"])
        self.assertTrue(all(cls in (0, 1, 2) for cls, _ in s["lines"]))
        for line in s["lines"]:
            for lat, lon in points(line):
                # The cell is 54.25..54.5 N, 2.25..2.0 W (a road may run a little past its edge).
                self.assertTrue(54.2 < lat < 54.55 and -2.3 < lon < -1.95, (lat, lon))

    def test_joined_through_junctions(self):
        rows = {"nodes": [[0, 0], [100, 0], [200, 0], [200, 100], [300, 0]],
                "edges": [{"a": 0, "b": 1, "c": 0}, {"a": 1, "b": 2, "c": 0}, {"a": 2, "b": 3, "c": 0}, {"a": 2, "b": 4, "c": 0}]}
        lines = sb.chains(rows["edges"], [0, 1, 2, 3], rows["nodes"])
        # 0-1-2 is one line (1 is where only two meet); at 2 three meet, so 2-3 and 2-4 are lines of their own.
        self.assertEqual(sorted(len(l) for l in lines), [2, 2, 3])
        self.assertEqual(sum(len(l) - 1 for l in lines), 4)

    def test_simplify_keeps_the_ends_and_the_bends(self):
        pts = [(0, 0), (50, 1), (100, 0), (100, 100)]
        self.assertEqual(sb.simplify(pts, 10.0), [(0, 0), (100, 0), (100, 100)])

    def test_blocks_merge_cells_and_hash(self):
        s = sb.cell_sketch(CELL)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "sketch", "b28_35.json")
            h1 = sb.merge_block(path, [s])
            h2 = sb.merge_block(path, [dict(s, cell="577_712")])
            with open(path) as f:
                block = json.load(f)
        self.assertEqual(sorted(block["cells"]), ["577_711", "577_712"])
        self.assertNotEqual(h1, h2)
        self.assertEqual(sb.block_of("577_711"), "28_35")


if __name__ == "__main__":
    unittest.main()
