"""The luggage, each drawn at the size BikeModel draws a 35 litre top box or a 60 litre pair of
panniers (the game scales them evenly by its k for other sizes), in the game's axes (a point
(x, y, z) is Blender's (x, -z, y)):

- "luggage/hard_case.glb": a touring hard pannier round its middle, 150 mm deep, its latches on
  the outer face (+X; the game mirrors it for the left).
- "luggage/sport_case.glb": a sports tourer's angular side case the same way, its front raked.
- "luggage/saddlebag.glb": a cruiser's leather saddlebag round its middle, with its flap and
  buckled straps on the outer face (+X).
- "luggage/alu_pannier.glb": an aluminium adventure pannier's body round the case's middle, 150 by
  340 by 460 mm, riveted, ribbed and cornered; "luggage/alu_pannier_lid.glb" its lid with the carry
  handle (the game draws the latches, on the outer face).
- "luggage/alu_top.glb" and "luggage/alu_top_lid.glb": the aluminium top case, 360 by 260 by 340 mm
  round its middle, the same way.
- "luggage/top_case.glb": a plastic top case, 360 by 260 by 340 mm, from the middle of its base:
  black tub, lid in the part's colour, the seam, hinges at the front and the latch housing.
- "luggage/backrest.glb": the 45 litre case's pillion pad, on the front of the case.
- "luggage/crate.glb": a wooden crate from the middle of its base: posts, slats with gaps, floor.
- "luggage/trunk.glb": a leather trunk from the middle of its base, with its welt, straps over
  the lid, brass corners and lock plate; "luggage/trunk_lid.glb" its domed lid.
- "luggage/roll_bag.glb": the roll bag strapped across the top rack, round its middle.
- "luggage/roll_pannier.glb" and "luggage/throw_over.glb": the soft panniers, a roll-top dry bag and
  a canvas throw-over, round their middles on the right (+X).

Tags: paint (the part's colour), paint_2 (its darker trim: a crate's posts, a trunk's welt and
straps, a saddlebag's flap), plastic (tubs, corners, latches), polished_alloy (buckles and brass),
leather (the backrest), raw_steel (rivets and catches)."""

import math

import kit


def g(x, y, z):
    return (x, -z, y)


def box(name, c, half, tag, segs=8, n=8.0):
    """A box round game point `c` with slightly rounded edges."""
    x, y, z = c
    hx, hy, hz = half
    return kit.loft(name, [(-z - hz, hx, hy, hy, n), (-z + hz, hx, hy, hy, n)], segs, tag, at=(x, 0.0, y))


def along(name, secs, segs, tag, at=(0.0, 0.0, 0.0)):
    """A loft along the game's Z through (z, half width, up, down, n) sections."""
    return kit.loft(name, [(-z, hw, up, dn, n) for z, hw, up, dn, n in secs], segs, tag, at=(at[0], 0.0, at[1]))


def upright(name, secs, segs, tag):
    """A loft up the game's Y through (y, half width in X, half depth in Z, n) sections."""
    ob = kit.loft(name, [(y, hw, hd, hd, n) for y, hw, hd, n in secs], segs, tag)
    # (A loft runs along Blender Y; turned up, its Y becomes Blender Z, the game's Y.)
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    return ob


def hard_case(lod):
    segs = [24, 16, 8][lod]
    secs = [(-0.22, 0.075, 0.15, 0.17, 4.0), (-0.16, 0.075, 0.175, 0.17, 4.0), (0.16, 0.075, 0.175, 0.17, 4.0), (0.22, 0.075, 0.15, 0.17, 4.0)]
    parts = [along("case", secs if lod < 2 else [secs[0], secs[3]], segs, "paint")]
    if lod < 2:
        # The lid's seam round the case, and two latches on the outer face.
        parts.append(along("seam", [(-0.215, 0.077, 0.0045, 0.0045, 4.0), (0.215, 0.077, 0.0045, 0.0045, 4.0)], 8, "plastic", at=(0.0, 0.07)))
        for z in (-0.12, 0.12):
            parts.append(box("latch", (0.078, 0.07, z), (0.006, 0.022, 0.014), "plastic", 6))
    if lod == 0:
        for z in (-0.12, 0.12):
            parts.append(box("catch", (0.085, 0.064, z), (0.002, 0.008, 0.008), "raw_steel", 4))
        # The mounting hooks on the inner face.
        for z in (-0.12, 0.12):
            parts.append(box("hook", (-0.08, 0.12, z), (0.006, 0.02, 0.012), "plastic", 6))
    return kit.join(parts, "hard_case")


def sport_case(lod):
    """A sports tourer's side case (a CB1000GT's, a Tracer's): angular, its front raked back
    towards the bottom and its lid sloping up to the back."""
    segs = [24, 16, 8][lod]
    secs = [(-0.25, 0.055, 0.12, 0.02, 7.0), (-0.2, 0.072, 0.15, 0.09, 7.0), (-0.08, 0.075, 0.165, 0.15, 7.0),
        (0.16, 0.075, 0.18, 0.18, 7.0), (0.22, 0.07, 0.175, 0.17, 7.0)]
    parts = [along("case", secs if lod < 2 else [secs[0], secs[2], secs[4]], segs, "paint")]
    if lod < 2:
        parts.append(along("seam", [(-0.2, 0.077, 0.0045, 0.0045, 4.0), (0.215, 0.077, 0.0045, 0.0045, 4.0)], 8, "plastic", at=(0.0, 0.09)))
        parts.append(box("latch", (0.078, 0.08, 0.12), (0.006, 0.02, 0.03), "plastic", 6))
    return kit.join(parts, "sport_case")


def saddlebag(lod):
    segs = [20, 12, 8][lod]
    secs = [(-0.2, 0.075, 0.15, 0.15, 3.0), (0.0, 0.075, 0.16, 0.17, 3.0), (0.2, 0.075, 0.15, 0.1, 3.0)]
    parts = [along("bag", secs, segs, "paint")]
    if lod < 2:
        parts.append(box("flap", (0.005, 0.15, 0.0), (0.085, 0.015, 0.21), "paint_2", 8, 6.0))
        for z in (-0.1, 0.1):
            parts.append(box("strap", (0.083, 0.08, z), (0.003, 0.07, 0.0125), "paint_2", 4, 6.0))
            parts.append(box("buckle", (0.087, 0.05, z), (0.002, 0.012, 0.016), "polished_alloy", 4, 4.0))
    if lod == 0:
        # A row of studs along the flap.
        for k in range(7):
            parts.append(kit.sphere("stud", g(0.09, 0.15, -0.18 + k * 0.06), 0.004, (1.0, 1.0, 1.0), 6, "chrome"))
    return kit.join(parts, "saddlebag")


def alu_case(name, size, face, lod, lid=False):
    """An aluminium case `size` (full sizes) round its middle: its body (the handle across from
    the `face` its latches go on), or with `lid` its lid alone."""
    sx, sy, sz = size
    body_h = sy * 0.66
    lid_h = sy - body_h - 0.01
    bottom = -sy * 0.5
    segs = [16, 8, 4][lod]
    n = 12.0
    if lid:
        parts = [box("lid", (0.0, bottom + body_h + 0.01 + lid_h * 0.5, 0.0), (sx * 0.5 + 0.004, lid_h * 0.5, sz * 0.5 + 0.004), "paint", segs, n)]
        if lod < 2:
            for x in (-1.0, 1.0):
                for z in (-1.0, 1.0):
                    parts.append(box("corner", (x * (sx * 0.5 - 0.01), sy * 0.5 - 0.018, z * (sz * 0.5 - 0.01)), (0.025, 0.024, 0.025), "plastic", 6, 4.0))
            top = sy * 0.5
            hl = min(sx, sz) * 0.22
            pts = [(-hl, top, 0.0), (-hl * 0.8, top + 0.022, 0.0), (hl * 0.8, top + 0.022, 0.0), (hl, top, 0.0)]
            if face[0]:
                pts = [(0.0, y, x) for x, y, _ in pts]
            parts.append(kit.sweep("handle", [g(*p) for p in pts], 0.008, 6, "plastic"))
        return kit.join(parts, name)
    parts = [box("body", (0.0, bottom + body_h * 0.5, 0.0), (sx * 0.5, body_h * 0.5, sz * 0.5), "paint", segs, n)]
    if lod < 2:
        parts.append(box("seal", (0.0, bottom + body_h + 0.005, 0.0), (sx * 0.5 - 0.003, 0.006, sz * 0.5 - 0.003), "plastic", segs, n))
        parts.append(box("rib", (0.0, bottom + body_h * 0.45, 0.0), (sx * 0.5 + 0.003, 0.009, sz * 0.5 + 0.003), "paint", segs, n))
        # Black corners at the bottom.
        for x in (-1.0, 1.0):
            for z in (-1.0, 1.0):
                parts.append(box("corner", (x * (sx * 0.5 - 0.01), bottom + 0.022, z * (sz * 0.5 - 0.01)), (0.025, 0.024, 0.025), "plastic", 6, 4.0))
    if lod == 0:
        # Rivets along the base and under the lid.
        for fx, fz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            span = sz if fx else sx
            count = max(3, round(span / 0.07))
            for i in range(count):
                t = (i + 0.5) / count - 0.5
                for y in (bottom + 0.035, bottom + body_h - 0.02):
                    p = (fx * (sx * 0.5 + 0.001) + (0.0 if fx else t * (span - 0.08)), y, fz * (sz * 0.5 + 0.001) + (t * (span - 0.08) if fx else 0.0))
                    q = (p[0] + fx * 0.003, p[1], p[2] + fz * 0.003)
                    parts.append(kit.tube("rivet", g(*p), g(*q), 0.004, 6, "raw_steel"))
    return kit.join(parts, name)


def top_case(lod):
    w, d, h = 0.18, 0.17, 0.26
    segs = [24, 16, 8][lod]
    tub = [(0.0, 0.86, 0.84), (0.04, 0.95, 0.94), (0.12, 1.0, 1.0), (0.5, 1.0, 1.0)]
    lid = [(0.52, 1.015, 1.015), (0.62, 1.01, 1.0), (0.78, 0.97, 0.95), (0.9, 0.88, 0.84), (0.97, 0.72, 0.66), (1.0, 0.5, 0.42)]
    if lod == 2:
        tub, lid = [tub[0], tub[3]], [lid[0], lid[3], lid[5]]
    parts = [upright("tub", [(s[0] * h, w * s[1], d * s[2], 3.6) for s in tub], segs, "plastic"),
        upright("lid", [(s[0] * h, w * s[1], d * s[2], 3.2) for s in lid], segs, "paint")]
    if lod < 2:
        parts.append(upright("seam", [(0.5 * h, w * 1.006, d * 1.02, 3.6), (0.52 * h, w * 1.006, d * 1.02, 3.6)], segs, "plastic"))
        parts.append(box("latch", (0.0, 0.5 * h + 0.003, d * 1.03 + 0.006), (0.04, 0.0225, 0.007), "plastic", 6, 4.0))
        for x in (-1.0, 1.0):
            parts.append(kit.tube("hinge", g(x * w * 0.5 - 0.025, 0.5 * h + 0.003, -d - 0.004), g(x * w * 0.5 + 0.025, 0.5 * h + 0.003, -d - 0.004), 0.008, 8, "plastic"))
    return kit.join(parts, "top_case")


def backrest(lod):
    h = 0.26
    d = 0.17
    segs = [16, 10, 6][lod]
    secs = [(0.46 * h, -d - 0.012, 0.12, 0.015), (0.62 * h, -d - 0.016, 0.125, 0.017), (0.78 * h, -d - 0.008, 0.11, 0.015)]
    if lod == 2:
        secs = [secs[0], secs[2]]
    rings = []
    for y, zc, hw, t in secs:
        rings.append([g(x, y, zc - zz) for x, zz in kit.superellipse(hw, t, t, 3.0, segs)])
    return kit.join([kit.skin("pad", rings, "leather")], "backrest")


def trunk_lid(lod):
    w, d, h = 0.18, 0.17, 0.26
    segs = [20, 12, 8][lod]
    return kit.join([upright("lid", [(0.68 * h, w * 1.01, d * 1.01, 6.0), (0.88 * h, w, d, 6.0), (0.97 * h, w * 0.93, d * 0.93, 6.0), (h, w * 0.8, d * 0.8, 6.0)]
        if lod < 2 else [(0.68 * h, w, d, 6.0), (h, w * 0.85, d * 0.85, 6.0)], segs, "paint")], "trunk_lid")


def crate(lod):
    sx, sy, sz = 0.36, 0.26, 0.34
    w, d = sx * 0.5, sz * 0.5
    parts = [box("floor", (0.0, 0.008, 0.0), (w, 0.008, d), "paint_2", 4, 12.0)]
    for x in (-1.0, 1.0):
        for z in (-1.0, 1.0):
            parts.append(box("post", (x * (w - 0.013), sy * 0.5, z * (d - 0.013)), (0.013, sy * 0.5, 0.013), "paint_2", 4, 12.0))
    slats = 3 if lod < 2 else 1
    gap = 0.022 if lod < 2 else 0.0
    sh = (sy - gap * (slats - 1)) / slats
    for i in range(slats):
        y = (i + 0.5) * (sh + gap) - gap * 0.5
        for z in (-1.0, 1.0):
            parts.append(box("slat", (0.0, y, z * (d - 0.006)), (w - 0.025, sh * 0.5, 0.006), "paint", 4, 12.0))
        for x in (-1.0, 1.0):
            parts.append(box("slat", (x * (w - 0.006), y, 0.0), (0.006, sh * 0.5, d - 0.025), "paint", 4, 12.0))
    if lod == 0:
        # The nails at each slat's ends.
        for i in range(slats):
            y = (i + 0.5) * (sh + gap) - gap * 0.5
            for x in (-1.0, 1.0):
                for z in (-1.0, 1.0):
                    parts.append(kit.tube("nail", g(x * (w - 0.013), y, z * (d + 0.0005)), g(x * (w - 0.013), y, z * (d + 0.0025)), 0.002, 4, "raw_steel"))
    return kit.join(parts, "crate")


def trunk(lod):
    w, d, h = 0.18, 0.17, 0.26
    segs = [20, 12, 8][lod]
    parts = [upright("trunk", [(0.0, w * 0.95, d * 0.95, 6.0), (0.03 * h, w, d, 6.0), (0.66 * h, w, d, 6.0)], segs, "paint")]
    if lod < 2:
        parts.append(upright("welt", [(0.655 * h, w * 1.02, d * 1.02, 6.0), (0.69 * h, w * 1.02, d * 1.02, 6.0)], segs, "paint_2"))
        for x in (-1.0, 1.0):
            sx = x * w * 0.55
            parts.append(box("strap", (sx, h + 0.003, 0.0), (0.02, 0.003, d * 0.86), "paint_2", 4, 6.0))
            for z in (-1.0, 1.0):
                parts.append(box("strap", (sx, h * 0.72, z * (d + 0.003)), (0.02, h * 0.28, 0.003), "paint_2", 4, 6.0))
            parts.append(box("buckle", (sx, h * 0.58, d + 0.008), (0.025, 0.02, 0.003), "polished_alloy", 4, 4.0))
        parts.append(box("lock", (0.0, 0.66 * h, d + 0.008), (0.025, 0.03, 0.003), "polished_alloy", 4, 4.0))
        parts.append(kit.sweep("handle", [g(-0.06, h, 0.0), g(-0.045, h + 0.03, 0.0), g(0.045, h + 0.03, 0.0), g(0.06, h, 0.0)], 0.009, 6, "paint_2"))
    if lod == 0:
        for x in (-1.0, 1.0):
            for z in (-1.0, 1.0):
                parts.append(box("corner", (x * (w - 0.01), 0.02, z * (d - 0.01)), (0.0175, 0.02, 0.0175), "polished_alloy", 4, 4.0))
    return kit.join(parts, "trunk")


def across(name, secs, segs, tag, at=(0.0, 0.0, 0.0)):
    """A loft across the game's X through (x, half depth in Z, up, down, n) sections round game `at`."""
    ob = kit.loft(name, [(x, hz, up, dn, n) for x, hz, up, dn, n in secs], segs, tag)
    # (A loft runs along Blender Y; turned a quarter about Z, its Y becomes Blender -X.)
    ob.rotation_euler = (0.0, 0.0, -math.pi * 0.5)
    ob.location = g(*at)
    return ob


def roll_bag(lod):
    """The top box's roll bag, 560 by 240 by 270 mm, lying across the rack round its middle, with
    its rolled ends standing up at each end (the game adds the clips and straps)."""
    segs = [24, 12, 6][lod]
    shape = [[-1.0, 0.03, 0.72], [-0.92, 0.4, 0.86], [-0.8, 0.9, 0.97], [-0.6, 1.0, 1.0], [0.0, 1.03, 1.02], [0.6, 1.0, 1.0],
        [0.8, 0.9, 0.97], [0.92, 0.4, 0.86], [1.0, 0.03, 0.72]]
    if lod == 2:
        shape = [shape[0], shape[2], shape[6], shape[8]]
    elif lod == 1:
        shape = [shape[0], shape[1], shape[2], shape[4], shape[6], shape[7], shape[8]]
    r = 0.12
    parts = [across("bag", [(f * 0.27, 0.135 * w, r * h, r * h, 2.3) for f, w, h in shape], segs, "paint")]
    for x in (-1.0, 1.0):
        s = [16, 8, 4][lod]
        parts.append(upright_at("rolled", [(-0.09, 0.026, 0.026, 2.0), (0.09, 0.026, 0.026, 2.0)], s, "paint", (x * 0.292, 0.0, 0.0)))
        if lod < 2:
            parts.append(upright_at("inner", [(-0.095, 0.02, 0.02, 2.0), (0.095, 0.02, 0.02, 2.0)], s, "paint_2", (x * 0.3, 0.0, 0.0)))
    if lod == 0:
        # The welded seam along its underside, and the reflective patch's welt.
        parts.append(across("seam", [(-0.2, 0.004, 0.003, 0.003, 2.0), (0.2, 0.004, 0.003, 0.003, 2.0)], 6, "paint_2", at=(0.0, -0.121, 0.0)))
    return kit.join(parts, "roll_bag")


def upright_at(name, secs, segs, tag, at):
    ob = upright(name, secs, segs, tag)
    ob.location = g(*at)
    return ob


def roll_pannier(lod):
    """A roll-top soft pannier, 150 by 300 by 420 mm round its middle, on the right (+X; the game
    mirrors it), its top rolled down into a tube a little to the outside."""
    segs = [24, 12, 6][lod]
    shape = [[0.0, 0.75, 0.85], [0.06, 0.96, 0.97], [0.5, 1.0, 1.0], [0.86, 0.9, 0.97], [1.0, 0.45, 0.95]]
    if lod == 2:
        shape = [shape[0], shape[2], shape[4]]
    parts = [upright("bag", [(-0.15 + f * 0.3, 0.075 * w, 0.21 * d, 2.8) for f, w, d in shape], segs, "paint")]
    parts.append(along("rolled", [(-0.1995, 0.03, 0.03, 0.03, 2.0), (0.1995, 0.03, 0.03, 0.03, 2.0)], [16, 8, 4][lod], "paint", at=(0.018, 0.172)))
    if lod < 2:
        # The darker base panel, and the rolled tube's folded end.
        parts.append(upright("base", [(-0.151, 0.058, 0.18, 2.8), (-0.125, 0.073, 0.205, 2.8)], segs, "paint_2"))
        for z in (-1.0, 1.0):
            parts.append(along("fold", [(z * 0.2 - 0.004, 0.033, 0.033, 0.033, 2.0), (z * 0.2 + 0.004, 0.033, 0.033, 0.033, 2.0)], 8, "paint_2", at=(0.018, 0.172)))
    return kit.join(parts, "roll_pannier")


def throw_over(lod):
    """A canvas throw-over pannier, 150 by 300 by 400 mm round its middle (the game adds its flap,
    straps and yoke), with piping round its top."""
    segs = [24, 12, 6][lod]
    shape = [[0.0, 0.7, 0.8], [0.08, 0.95, 0.96], [0.55, 1.0, 1.0], [1.0, 0.85, 0.97]]
    if lod == 2:
        shape = [shape[0], shape[2], shape[3]]
    parts = [upright("bag", [(-0.15 + f * 0.3, 0.075 * w, 0.2 * d, 3.0) for f, w, d in shape], segs, "paint")]
    if lod < 2:
        parts.append(upright("piping", [(0.14, 0.066, 0.196, 3.0), (0.15, 0.066, 0.196, 3.0)], segs, "paint_2"))
        parts.append(upright("piping", [(-0.14, 0.055, 0.162, 3.0), (-0.13, 0.073, 0.195, 3.0)], segs, "paint_2"))
    return kit.join(parts, "throw_over")


def parts():
    out = []
    for name, build in (("hard_case", hard_case), ("sport_case", sport_case), ("saddlebag", saddlebag), ("top_case", top_case), ("backrest", backrest), ("crate", crate), ("trunk", trunk), ("trunk_lid", trunk_lid), ("roll_bag", roll_bag), ("roll_pannier", roll_pannier), ("throw_over", throw_over),
            ("alu_pannier", lambda lod: alu_case("alu_pannier", (0.15, 0.34, 0.46), (1, 0), lod)),
            ("alu_pannier_lid", lambda lod: alu_case("alu_pannier_lid", (0.15, 0.34, 0.46), (1, 0), lod, True)),
            ("alu_top", lambda lod: alu_case("alu_top", (0.36, 0.26, 0.34), (0, 1), lod)),
            ("alu_top_lid", lambda lod: alu_case("alu_top_lid", (0.36, 0.26, 0.34), (0, 1), lod, True))):
        out.append({"kind": "luggage", "path": "luggage/%s.glb" % name, "build": build, "mounts": {}})
    return out
