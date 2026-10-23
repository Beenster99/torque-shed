"""The levels of land a pack holds (see route_bake.py, scripts/real_terrain.gd): heights, and for the first two the
land cover, in tiles of n x n samples each `spacing` metres apart.

    fine    4 m    within 320 m of the road: the road's own land, with buildings levelled into it
    coarse  32 m   out to 1.7 km: the hillsides the land mesh runs up (it is sparse there)
    cover   16 m   a cell's cover near the road (no heights: a cell's come from the map tiles, scripts/height_tiles.gd)
    ridge   128 m  out to 14 km: the skyline, drawn as its own mesh (RealRidges), already pushed down near the road
                   so it never shows through the land

Every level's heights are uint16 steps of `scale` over MIN (a coarser level has a coarser step and so a higher
ceiling: the ridge's 0.25 m steps reach 16 km). On disk a tile is zlib-compressed after taking differences along x then
z (land is smooth, so most of what is left is zeros): <folder>/TX_TZ.u16z, and its cover <folder>/TX_TZ.covz, a plain
zlib of the bytes. scripts/real_terrain.gd reads both.
"""
import zlib

import numpy as np

MIN = -256.0


class Level:
    def __init__(self, name, folder, spacing, n, reach, scale):
        self.name, self.folder, self.spacing, self.n, self.reach, self.scale = name, folder, spacing, n, reach, scale

    @property
    def size_m(self):
        return self.spacing * self.n

    def quantise(self, heights):
        return np.clip(np.round((heights - MIN) / self.scale), 0, 65535).astype("<u2")

    def dequantise(self, q):
        return MIN + np.asarray(q, dtype=np.float64) * self.scale

    def meta(self, cover=None):
        return {"name": self.name, "dir": self.folder, "spacing": self.spacing, "n": self.n, "size_m": self.size_m,
                "min": MIN, "scale": self.scale, "cover": self.name in ("fine", "coarse") if cover is None else cover}


FINE = Level("fine", "tiles", 4.0, 128, 320.0, 0.0625)
COARSE = Level("coarse", "coarse", 32.0, 128, 1700.0, 0.125)
RIDGE = Level("ridge", "ridge", 128.0, 256, 14000.0, 0.25)
LEVELS = [FINE, COARSE, RIDGE]
COVER_LEVELS = [FINE, COARSE]
# A cell (region_bake.py --cell) has no heights of its own, and its cover near the road at 16 m, not 4: a sixteenth of
# the bytes (8 MB of a Dales cell's 10 were its cover at 4 m), the woods' edges still sharper than the land blocks'.
COVER = Level("cover", "cover", 16.0, 128, 320.0, 0.25)
CELL_COVER_LEVELS = [COVER, COARSE]


def encode_heights(q):
    """A tile's uint16 steps (n, n) as the bytes written to disk."""
    x = np.asarray(q, dtype=np.int32)
    dx = np.diff(x, axis=1, prepend=0)
    dz = np.diff(dx, axis=0, prepend=0)
    return zlib.compress((dz & 0xFFFF).astype("<u2").tobytes(), 9)


def decode_heights(data, n):
    """The inverse of encode_heights: the tile's uint16 steps (n, n)."""
    dz = np.frombuffer(zlib.decompress(data), dtype="<u2").reshape(n, n).astype(np.int64)
    dx = np.cumsum(dz, axis=0) & 0xFFFF
    return ((np.cumsum(dx, axis=1)) & 0xFFFF).astype("<u2")


def encode_cover(cov):
    return zlib.compress(np.asarray(cov, dtype=np.uint8).tobytes(), 9)
