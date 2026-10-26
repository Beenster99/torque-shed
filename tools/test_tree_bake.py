#!/usr/bin/env python3
"""Tests for tree_bake.py (a cell's trees from the canopy height map), on made-up tiles, roads and woods.

    python3 -m unittest tools/test_tree_bake.py
"""
import base64
import os
import struct
import sys
import tempfile
import unittest
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coast_bake as cb  # noqa: E402
import tree_bake as tb  # noqa: E402


def wkb_line(pts):
    """A WKB line string of [(lon, lat), ...]."""
    return struct.pack("<BII", 1, 2, len(pts)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in pts)


def wkb_polygon(ring):
    """A WKB polygon of one ring [(lon, lat), ...]."""
    return struct.pack("<BII", 1, 3, 1) + struct.pack("<I", len(ring)) + b"".join(struct.pack("<dd", lon, lat) for lon, lat in ring)


def write_tiff(path, a, rows_per_strip):
    """A little-endian TIFF of byte array `a`, deflated in strips with the horizontal predictor (as the canopy tiles are)."""
    h, w = a.shape
    strips = []
    for y in range(0, h, rows_per_strip):
        s = a[y:y + rows_per_strip].astype(np.int16)
        d = np.concatenate([s[:, :1], np.diff(s, axis=1)], axis=1).astype(np.uint8)
        strips.append(zlib.compress(d.tobytes()))
    n = len(strips)
    data_at = 8
    offs = []
    body = b""
    for s in strips:
        offs.append(data_at + len(body))
        body += s
    arrays_at = data_at + len(body)
    arrays = struct.pack("<%dI" % n, *offs) + struct.pack("<%dI" % n, *[len(s) for s in strips])
    ifd_at = arrays_at + len(arrays)
    tags = [(256, 4, 1, w), (257, 4, 1, h), (258, 3, 1, 8), (259, 3, 1, 8), (273, 4, n, arrays_at), (277, 3, 1, 1),
            (278, 4, 1, rows_per_strip), (279, 4, n, arrays_at + 4 * n), (317, 3, 1, 2)]
    ifd = struct.pack("<H", len(tags)) + b"".join(struct.pack("<HHII", *t) for t in tags) + struct.pack("<I", 0)
    with open(path, "wb") as f:
        f.write(b"II*\x00" + struct.pack("<I", ifd_at) + body + arrays + ifd)


class FakeTile:
    """A canopy tile of the real size whose pixels are 0 but for the boxes set (pixel rows and columns)."""
    width = height = 65536

    def __init__(self):
        self.boxes = []

    def rows(self, y0, y1):
        out = np.zeros((y1 - y0, self.width), np.uint8)
        for (r0, r1, c0, c1, v) in self.boxes:
            a, b = max(r0, y0), min(r1, y1)
            if a < b:
                out[a - y0:b - y0, c0:c1] = v
        return out


ROW, COL = cb.cell_of(54.3, -2.1)
BOX = cb.cell_box(ROW, COL)
S, W, N, E = BOX


def pixel(tx, ty, lat, lon):
    """(row, column) of the pixel at lat, lon in tile (tx, ty)."""
    size = tb.WORLD_M / (1 << tb.CHM_ZOOM)
    x, y = tb.merc(lat, lon)
    return int(round((y - ty * size) / size * 65536)), int(round((x - tx * size) / size * 65536))


class TreeTests(unittest.TestCase):
    def test_the_tile_a_place_is_in_is_named_by_its_quadkey(self):
        tiles = tb.tiles_over((54.29, -2.05, 54.31, -2.03))
        self.assertEqual([tb.quadkey(*t) for t in tiles], ["031311123"])   # (the Dales' tile in Meta's bucket)
        self.assertEqual(len(tb.tiles_over(BOX)), 2)   # (this cell straddles two)

    def test_a_tiff_is_read_a_row_at_a_time(self):
        a = (np.arange(6 * 8).reshape(6, 8) * 37 % 251).astype(np.uint8)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "t.tif")
            write_tiff(path, a, 2)
            t = tb.Tiff(path)
            self.assertEqual((t.width, t.height), (8, 6))
            self.assertTrue((t.rows(1, 5) == a[1:5]).all())
            self.assertTrue((t.rows(0, 6) == a).all())

    def test_a_square_has_its_tallest_tree_and_how_much_is_under_trees(self):
        rows, cols = tb.grid_of(ROW, COL)
        self.assertTrue(1700 < rows < 1780 and 990 < cols < 1040)   # (about 16 m squares at 54 N)
        r, k = 800, 500
        lat_n = N - (N - S) * r / rows
        lat_s = N - (N - S) * (r + 1) / rows
        lon_w = W + (E - W) * k / cols
        lon_e = W + (E - W) * (k + 1) / cols
        tx, ty = [t for t in tb.tiles_over((lat_s, lon_w, lat_n, lon_e))][0]
        tile = FakeTile()
        y0, x0 = pixel(tx, ty, lat_n, lon_w)
        y1, x1 = pixel(tx, ty, lat_s, lon_e)
        tile.boxes.append((y0, y1, x0, x1, 21))   # the whole square under a wood 21 m tall
        _, x2 = pixel(tx, ty, lat_n, W + (E - W) * (k + 2) / cols)
        tile.boxes.append((y0, (y0 + y1) // 2, x1, x2, 9))   # the half of the next one under trees 9 m tall
        tile.boxes.append((y0, y1, x0 - 40, x0, 2))   # and the one before under grass, not trees
        mask = np.zeros((rows, cols), bool)
        mask[r - 1:r + 2, k - 1:k + 3] = True
        got = tb.canopy(BOX, rows, cols, lambda x, y: tile if (x, y) == (tx, ty) else None, mask)
        self.assertEqual(got[r, k], 10 | 7 << 5)   # 20 m (21 to the nearest 2) and all of it
        self.assertIn(got[r, k + 1] >> 5, (3, 4))    # about half
        self.assertEqual(got[r, k + 1] & 31, 4)    # 8 m (9 to the nearest 2)
        self.assertEqual(got[r, k - 1], 0)
        self.assertEqual(int(got.sum()), int(got[r, k]) + int(got[r, k + 1]))

    def test_only_near_a_road(self):
        rows, cols = 200, 200
        box = (S, W, S + (N - S) * 0.1, W + (E - W) * 0.1)
        road = wkb_line([(box[1], (box[0] + box[2]) / 2), (box[3], (box[0] + box[2]) / 2)])
        mask = tb.road_mask([road], box, rows, cols)
        px_m = (box[2] - box[0]) * tb.sketch_bake.metres_per_degree(box[0])[0] / rows
        near = int(tb.NEAR_M / px_m)
        self.assertTrue(mask[100, 50] and mask[100 - near + 3, 50] and mask[100 + near - 3, 50])
        self.assertFalse(mask[100 - near - 3, 50] or mask[100 + near + 3, 50])

    def test_the_leaves_where_the_map_has_them(self):
        rows, cols = 100, 100
        box = (S, W, S + 0.01, W + 0.01)
        wood = wkb_polygon([(W + 0.002, S + 0.002), (W + 0.005, S + 0.002), (W + 0.005, S + 0.005), (W + 0.002, S + 0.005),
                            (W + 0.002, S + 0.002)])
        got = tb.leaf_grid([(tb.LEAVES["needleleaved"], wood)], box, rows, cols)
        self.assertEqual(got[100 - 35, 35], 2)   # (rows from the north)
        self.assertEqual(got[10, 10], 0)

    def test_a_cell_with_no_road_has_no_trees(self):
        got = tb.cell_trees(ROW, COL, lambda x, y: None, [], [])
        self.assertEqual(got["cell"], "%d_%d" % (ROW, COL))
        trees = zlib.decompress(base64.b64decode(got["trees"]))
        self.assertEqual(len(trees), got["rows"] * got["cols"])
        self.assertEqual(trees.count(0), len(trees))
        self.assertLess(len(got["trees"]), 4000)


if __name__ == "__main__":
    unittest.main()
