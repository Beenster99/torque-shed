"""The headlights: the lamp bodies BikeModel._draw_headlight hangs off the fork, each drawn round its
lamp's middle in the game's steering space (+X right, +Y up, -Z forward; a point (x, y, z) here is
Blender's (x, -z, y), so a lamp looks down Blender +Y).

The round family is drawn at unit size (the game scales it by the part's "size", its radius):

- "headlight/round.glb": a seven-inch style bowl with its rolled bezel and a domed, fluted glass,
  its back at z 0.75 and its glass's face at z -0.77, as the code's squashed ball; the oval, twin
  and stacked lamps are this one stretched.
- "headlight/bucket.glb": a Bates-style bucket, its round face at z -0.55 and its back tapered to
  0.72 of the face at z 0.55, round its middle (the game puts it 0.03 behind the lamp's point).
- "headlight/bullet.glb": a long bullet, its face at z -0.45 and its tail tapering away to z 1.45.
- "headlight/square.glb": the old-school rectangular lamp, 2.3 wide and 1.7 tall, deep bucket
  and stepped back, its bezel tagged chrome (the game gives it the look's bezel finish).
- "headlight/bugeye.glb": one bug-eye: a tall oval shell with its tapered back, a chrome rim and
  its oval glass at z -1.03, in the lamp's own turned frame.

These are drawn at their sizes in metres:

- "headlight/cell.glb": one of a quad lamp's four square cells, 0.08 by 0.07 and 0.08 deep.
- "headlight/plate.glb": an enduro number-board lamp, the 0.22 by 0.27 board round its middle with
  its lamp window in it, upright (the game leans it back).
- "headlight/projector.glb": the LED projector's flat housing with its two lens cups.

Every glass is tagged lens_white: the game lays its own lamp material over it, so the lamp still
lights with the headlight switch."""

import math

import kit


def g(x, y, z):
    return (x, -z, y)


def lens(name, z, r, segs, lod, depth=0.07, at=(0.0, 0.0, 0.0), sx=1.0, sy=1.0, n=2.0):
    """A domed glass whose rim is at game z `z` (radius `r`, stretched by sx, sy), bulging forward by
    `depth`."""
    y = -z
    secs = [(y - 0.02, r * sx, r * sy, r * sy, n), (y + depth * 0.45, r * 0.94 * sx, r * 0.94 * sy, r * 0.94 * sy, n)]
    if lod < 2:
        secs.append((y + depth * 0.85, r * 0.7 * sx, r * 0.7 * sy, r * 0.7 * sy, n))
    secs.append((y + depth, r * 0.3 * sx, r * 0.3 * sy, r * 0.3 * sy, n))
    return kit.loft(name, secs, segs, "lens_white", at=at)


def flutes(z, r, count, lod, at=(0.0, 0.0, 0.0), sx=1.0, sy=1.0):
    """The glass's moulded flutes: thin upright ribs across the face, just proud of it (lod0 only)."""
    if lod > 0:
        return []
    out = []
    for i in range(count):
        x = (i - (count - 1) * 0.5) / ((count - 1) * 0.5) * r * 0.62 * sx
        h = math.sqrt(max(r * r * sx * sx - x * x, 0.0)) / sx * sy * 0.8
        out.append(kit.loft("flute", [(-z + 0.035, r * 0.012, h, h, 2.0), (-z + 0.05, r * 0.012, h * 0.95, h * 0.95, 2.0)],
            4, "lens_white", at=(at[0] + x, at[1], at[2])))
    return out


def round_lamp(lod):
    segs = [32, 16, 8][lod]
    full = [(-0.75, 0.12), (-0.68, 0.45), (-0.5, 0.75), (-0.25, 0.93), (0.0, 1.0), (0.3, 0.96), (0.55, 0.9), (0.66, 0.9)]
    secs = full if lod == 0 else ([full[0], full[2], full[4], full[6], full[7]] if lod == 1 else [full[1], full[4], full[7]])
    parts = [kit.loft("bowl", [(y, r, r, r, 2.0) for y, r in secs], segs, "paint")]
    if lod < 2:
        # The rolled bezel round the glass, and the adjuster bolts at the sides.
        parts.append(kit.ring("bezel", 0.68, 0.9, 0.05, segs, "paint", 6 if lod == 0 else 4))
        for side in (-1.0, 1.0):
            parts.append(kit.tube("bolt", (side * 0.94, 0.0, 0.0), (side * 1.06, 0.0, 0.0), 0.12, 8 if lod == 0 else 6, "black_metal"))
    if lod == 0:
        # The cable grommet out of the back.
        parts.append(kit.tube("grommet", (0.0, -0.74, -0.1), (0.0, -0.8, -0.12), 0.08, 8, "rubber"))
    parts.append(lens("glass", -0.7, 0.88, segs, lod))
    parts += flutes(-0.7, 0.88, 7, lod)
    return kit.join(parts, "round")


def bucket(lod):
    segs = [32, 16, 8][lod]
    full = [(-0.6, 0.5), (-0.55, 0.72), (-0.2, 0.84), (0.2, 0.93), (0.45, 0.99), (0.55, 1.0)]
    secs = full if lod == 0 else ([full[0], full[1], full[3], full[5]] if lod == 1 else [full[1], full[5]])
    parts = [kit.loft("bucket", [(y, r, r, r, 2.0) for y, r in secs], segs, "paint")]
    if lod < 2:
        parts.append(kit.ring("bezel", 0.56, 0.95, 0.055, segs, "paint", 6 if lod == 0 else 4))
        # The mounting stud under the bucket, and the switch on its back.
        parts.append(kit.tube("stud", (0.0, -0.1, -0.8), (0.0, -0.1, -1.0), 0.1, 8, "black_metal"))
    if lod == 0:
        parts.append(kit.tube("switch", (0.0, -0.6, 0.15), (0.0, -0.66, 0.15), 0.12, 8, "chrome"))
    parts.append(lens("glass", -0.55, 0.92, segs, lod, depth=0.08))
    parts += flutes(-0.55, 0.92, 7, lod)
    return kit.join(parts, "bucket")


def bullet(lod):
    segs = [32, 16, 8][lod]
    full = [(-1.45, 0.12), (-1.35, 0.35), (-1.1, 0.55), (-0.7, 0.75), (-0.2, 0.92), (0.3, 1.0), (0.45, 1.0)]
    secs = full if lod == 0 else ([full[0], full[2], full[4], full[6]] if lod == 1 else [full[1], full[4], full[6]])
    parts = [kit.loft("bullet", [(y, r, r, r, 2.0) for y, r in secs], segs, "paint")]
    if lod < 2:
        parts.append(kit.ring("bezel", 0.46, 0.95, 0.05, segs, "paint", 6 if lod == 0 else 4))
    if lod == 0:
        # The swage line round its body.
        parts.append(kit.ring("swage", -0.3, 0.92, 0.025, segs, "paint", 4))
    parts.append(lens("glass", -0.45, 0.9, segs, lod, depth=0.07))
    return kit.join(parts, "bullet")


def square(lod):
    n = 6.0
    segs = [24, 16, 6][lod]
    w, h = 1.15, 0.85
    parts = [
        kit.loft("body", [(-0.54, w * 0.93, h * 0.92, h * 0.92, n), (0.3, w * 0.96, h * 0.94, h * 0.94, n)], segs, "paint"),
        kit.loft("back", [(-0.9, w * 0.62, h * 0.56, h * 0.56, n), (-0.5, w * 0.7, h * 0.64, h * 0.64, n)], segs, "paint"),
        kit.loft("bezel", [(0.28, w, h, h, n), (0.36, w, h, h, n), (0.38, w * 0.94, h * 0.92, h * 0.92, n)], segs, "chrome"),
        kit.loft("glass", [(0.34, w * 0.86, h * 0.8, h * 0.8, n), (0.4, w * 0.85, h * 0.79, h * 0.79, n)], segs, "lens_white"),
    ]
    if lod == 0:
        # The glass's flutes and its middle rib.
        for i in range(7):
            x = (i - 3) / 3.0 * w * 0.74
            parts.append(kit.loft("flute", [(0.4, 0.012, h * 0.74, h * 0.74, 2.0), (0.42, 0.01, h * 0.72, h * 0.72, 2.0)], 4, "lens_white", at=(x, 0.0, 0.0)))
        parts.append(kit.loft("rib", [(0.4, w * 0.8, 0.012, 0.012, 2.0), (0.425, w * 0.78, 0.01, 0.01, 2.0)], 4, "lens_white"))
        # The bezel's screw at the bottom.
        parts.append(kit.tube("screw", (0.0, 0.37, -h * 0.97), (0.0, 0.42, -h * 0.97), 0.05, 6, "chrome"))
    return kit.join(parts, "square")


def bugeye(lod):
    segs = [28, 14, 6][lod]
    rings = [10, 6, 3][lod]
    secs = []
    for i in range(rings + 1):
        a = math.pi * (0.06 + 0.94 * i / rings)
        secs.append((-math.cos(a) * 1.05, math.sin(a) * 0.9 + 0.02, math.sin(a) * 1.2 + 0.02, math.sin(a) * 1.2 + 0.02, 2.0))
    # (The ball is cut flat at the front for the glass: its front-most ring stays as wide as the rim.)
    secs = [(min(y, 0.96), hw, up, dn, n) for y, hw, up, dn, n in secs if y < 0.97] + [(0.96, 0.8, 1.06, 1.06, 2.0)]
    parts = [kit.loft("shell", secs, segs, "paint"),
        kit.loft("back", [(-1.3, 0.35, 0.35, 0.35, 2.0)] + ([(-0.8, 0.68, 0.68, 0.68, 2.0)] if lod < 2 else []) + [(-0.3, 0.75, 0.75, 0.75, 2.0)], max(segs // 2, 6), "paint")]
    if lod < 2:
        rim = kit.ring("rim", 0.98, 0.88, 0.05, segs, "chrome", 6 if lod == 0 else 4)
        rim.scale = (0.88, 1.0, 1.18)
        parts.append(rim)
    parts.append(lens("glass", -0.97, 0.86, segs, lod, depth=0.06, sx=0.88, sy=1.18))
    return kit.join(parts, "bugeye")


def cell(lod):
    n = 5.0
    segs = [20, 12, 8][lod]
    parts = [kit.loft("cell", [(-0.04, 0.036, 0.031, 0.031, n), (-0.03, 0.04, 0.035, 0.035, n), (0.036, 0.04, 0.035, 0.035, n),
        (0.04, 0.038, 0.033, 0.033, n)], segs, "paint")]
    parts.append(kit.loft("glass", [(0.036, 0.034, 0.029, 0.029, n), (0.044, 0.033, 0.028, 0.028, n)], segs, "lens_white"))
    if lod == 0:
        # The reflector's ring and its LED in the glass, and the cooling fins on the back.
        parts.append(kit.loft("ring", [(0.044, 0.016, 0.016, 0.016, 2.0), (0.0455, 0.012, 0.012, 0.012, 2.0)], 12, "polished_alloy"))
        for k in range(4):
            y = -0.024 + k * 0.016
            parts.append(kit.loft("fin", [(-0.046, 0.003, 0.03, 0.03, 4.0), (-0.04, 0.003, 0.03, 0.03, 4.0)], 4, "black_metal", at=(y, 0.0, 0.0)))
    return kit.join(parts, "cell")


def plate(lod):
    n = 7.0
    segs = [24, 12, 8][lod]
    secs = [(-0.01, 0.105, 0.13, 0.13, n), (-0.006, 0.11, 0.135, 0.135, n), (0.006, 0.11, 0.135, 0.135, n), (0.01, 0.105, 0.13, 0.13, n)]
    if lod == 2:
        secs = [secs[1], secs[2]]
    parts = [kit.loft("board", secs, segs, "paint")]
    # The lamp's black surround and its glass, a little above the board's middle.
    at = (0.0, 0.0, 0.02)
    parts.append(kit.loft("surround", [(0.008, 0.058, 0.043, 0.043, 5.0), (0.016, 0.056, 0.041, 0.041, 5.0)], segs, "plastic", at=at))
    parts.append(kit.loft("glass", [(0.014, 0.05, 0.035, 0.035, 5.0), (0.021, 0.049, 0.034, 0.034, 5.0)], segs, "lens_white", at=at))
    if lod == 0:
        # The board's strap slots' bosses and the two bolts holding the lamp in.
        for side in (-1.0, 1.0):
            parts.append(kit.tube("bolt", (side * 0.07, 0.008, 0.02), (side * 0.07, 0.016, 0.02), 0.006, 6, "black_metal"))
            parts.append(kit.loft("boss", [(-0.016, 0.012, 0.022, 0.022, 3.0), (-0.01, 0.012, 0.022, 0.022, 3.0)], 8, "plastic", at=(side * 0.085, 0.0, -0.08)))
    return kit.join(parts, "plate")


def projector(lod):
    n = 5.0
    segs = [20, 12, 6][lod]
    secs = [(-0.045, 0.08, 0.04, 0.04, n), (-0.035, 0.085, 0.045, 0.045, n), (0.04, 0.085, 0.045, 0.045, n), (0.045, 0.082, 0.042, 0.042, n)]
    parts = [kit.loft("housing", secs if lod < 2 else [(-0.045, 0.085, 0.045, 0.045, n), (0.045, 0.085, 0.045, 0.045, n)], segs, "paint")]
    for side in (-1.0, 1.0):
        at = (side * 0.04, 0.0, 0.0)
        if lod < 2:
            parts.append(kit.loft("cup", [(0.042, 0.03, 0.03, 0.03, 2.0), (0.048, 0.029, 0.029, 0.029, 2.0)], segs, "polished_alloy", at=at))
        parts.append(lens("glass", -0.046, 0.025, [16, 12, 6][lod], lod, depth=0.01, at=at))
    if lod == 0:
        # The heat sink's fins across its back.
        for k in range(6):
            x = -0.06 + k * 0.024
            parts.append(kit.loft("fin", [(-0.052, 0.003, 0.038, 0.038, 4.0), (-0.044, 0.003, 0.038, 0.038, 4.0)], 4, "black_metal", at=(x, 0.0, 0.0)))
    return kit.join(parts, "projector")


def parts():
    out = []
    for name, build in (("round", round_lamp), ("bucket", bucket), ("bullet", bullet), ("square", square), ("bugeye", bugeye),
            ("cell", cell), ("plate", plate), ("projector", projector)):
        out.append({"kind": "headlight", "path": "headlight/%s.glb" % name, "build": build, "mounts": {}})
    return out
