"""The controls: what's on the bars and what the rider's feet rest on.

On the bars each piece is drawn in the bar's own frame where BikeModel puts it (see its
_bar_end_basis): +X along the bar to the rider's right, +Y up off it and +Z back towards the rider,
in the game's axes (a point (x, y, z) here is Blender's (x, -z, y)). The levers and the switch
gear are drawn for the left-hand end; the game mirrors the brake lever onto the right.

- "controls/grip.glb": a ribbed rubber grip with its flange, along +Y from the flange (0) to the
  bar end (GRIP_LEN), round the bar's axis; "controls/bar_end.glb": the bar-end weight, along +Y
  from just inside the end.
- "controls/switch_left.glb": the left switch housing (indicator, horn and dip switches), round the
  bar at its origin; "controls/throttle.glb": the right throttle housing with its kill switch and
  starter button.
- "controls/clutch_perch.glb": the clutch lever's split clamp and perch with its pivot and cable
  adjuster, its origin on the bar; "controls/lever.glb": the forged lever blade from its pivot out
  to the ball end LEVER_REACH outboard; "controls/master_axial.glb" and "controls/master_radial.glb":
  the front brake master cylinder and reservoir, origin on the bar.
- "controls/bar_clamp.glb": the risers and top clamps holding a one-piece bar, round its middle.
- "controls/hanger.glb": a footrest hanger plate, a unit square in Y and Z (the game stretches it
  from the frame to the peg) and HANGER_T thick in X; "controls/peg_alloy.glb": a rearset's
  serrated alloy peg, out along +X from x -0.02 to 0.07; "controls/cleat.glb": a flat-track cleat;
  "controls/floorboard.glb": a cruiser's floorboard, rubber on a chrome-edged plate."""

import math

import kit

GRIP_LEN = 0.1
LEVER_REACH = 0.127
HANGER_T = 0.012


def g(x, y, z):
    return (x, -z, y)


def T(name, a, b, r, segs, tag, bevel=0.0, r_end=None):
    """A tube between two points in the game's axes."""
    return kit.tube(name, g(*a), g(*b), r, segs, tag, bevel, r_end)


def grip(lod):
    segs = [16, 10, 6][lod]
    secs = [(0.0, 0.022, 0.022, 0.022, 2.0), (-0.006, 0.022, 0.022, 0.022, 2.0), (-0.0065, 0.018, 0.018, 0.018, 2.0)]
    ribs = 14 if lod == 0 else 0
    for k in range(ribs):
        y = -0.012 - (GRIP_LEN - 0.02) * k / ribs
        secs += [(y, 0.0186, 0.0186, 0.0186, 2.0), (y - 0.003, 0.0172, 0.0172, 0.0172, 2.0)]
    secs += [(-GRIP_LEN + 0.004, 0.018, 0.018, 0.018, 2.0), (-GRIP_LEN, 0.0165, 0.0165, 0.0165, 2.0)]
    ob = kit.loft("grip", secs, segs, "rubber")
    # Along the game's +Y (Blender +Z): the loft runs down Blender -Y, so turn it up.
    ob.rotation_euler = (-math.pi * 0.5, 0.0, 0.0)
    return kit.join([ob], "grip")


def bar_end(lod):
    segs = [16, 10, 6][lod]
    prof = [(-0.003, 0.0), (-0.003, 0.016), (0.0, 0.017), (0.016, 0.017), (0.019, 0.014), (0.019, 0.006), (0.017, 0.006), (0.017, 0.0)] \
        if lod == 0 else [(-0.003, 0.0), (-0.003, 0.017), (0.019, 0.017), (0.019, 0.0)]
    ob = kit.revolve("weight", prof, segs, "polished_alloy")
    ob.rotation_euler = (0.0, -math.pi * 0.5, 0.0)
    parts = [ob]
    if lod == 0:
        parts.append(kit.tube("bolt", (0.0, 0.0, 0.012), (0.0, 0.0, 0.017), 0.004, 6, "black_metal"))
    return kit.join(parts, "bar_end")


def _housing(name, hx, hy, hz, lod, tag="plastic"):
    """A rounded switch housing round the bar (along X), split into its two halves."""
    segs = [20, 10, 6][lod]
    secs = [(-hx, hz * 0.92, hy * 0.92, hy * 0.92, 3.0), (-hx * 0.8, hz, hy, hy, 3.2), (hx * 0.8, hz, hy, hy, 3.2), (hx, hz * 0.92, hy * 0.92, hy * 0.92, 3.0)]
    ob = kit.loft(name, secs, segs, tag)
    # The loft runs along Blender Y with its section in XZ: turn it to run along X.
    ob.rotation_euler = (0.0, 0.0, -math.pi * 0.5)
    return ob


def switch_left(lod):
    parts = [_housing("housing", 0.015, 0.021, 0.024, lod)]
    if lod < 2:
        # The horn button, the indicator slider and the dip switch on the rider's face of it.
        parts.append(T("horn", (0.0, -0.008, 0.022), (0.0, -0.008, 0.028), 0.006, 10, "rubber"))
        parts.append(kit.prism("indicator", kit.rounded_rect(0.008, 0.003, 0.002, 1), 0.02, 0.026, "rubber", plane="XY", at=(0.0, 0.0, 0.0)))
        parts[-1].rotation_euler = (math.pi * 0.5, 0.0, 0.0)
        parts[-1].location = g(0.0, 0.008, 0.0)
        parts.append(T("dip", (0.0, 0.021, 0.004), (0.0, 0.026, 0.006), 0.004, 8, "rubber"))
    return kit.join(parts, "switch_left")


def throttle(lod):
    segs = [16, 10, 6][lod]
    parts = [T("housing", (-0.011, 0.0, 0.0), (0.011, 0.0, 0.0), 0.022, segs, "plastic", 0.002 if lod == 0 else 0.0)]
    parts.append(kit.prism("block", kit.rounded_rect(0.01, 0.015, 0.004, 1), 0.0, 0.016, "plastic", at=(0.0, 0.0, 0.016)))
    if lod < 2:
        parts.append(kit.prism("kill", kit.rounded_rect(0.006, 0.004, 0.0015, 1), 0.0, 0.006, "plastic_paint", at=(0.0, 0.004, 0.032)))
        parts.append(T("start", (0.0, -0.006, 0.02), (0.0, -0.006, 0.026), 0.005, 10, "rubber"))
    return kit.join(parts, "throttle")


def clutch_perch(lod):
    segs = [16, 10, 6][lod]
    parts = [T("clamp", (-0.013, 0.0, 0.0), (0.013, 0.0, 0.0), 0.019, segs, "cast_alloy", 0.002 if lod == 0 else 0.0)]
    # The perch forward of the bar, its pivot boss upright through it.
    parts.append(kit.prism("perch", kit.rounded_rect(0.013, 0.016, 0.005, 2 if lod == 0 else 1), -0.01, 0.01, "cast_alloy", at=(0.0, 0.032, 0.0)))
    parts.append(T("boss", (0.0, -0.012, -0.04), (0.0, 0.012, -0.04), 0.008, segs, "cast_alloy"))
    if lod < 2:
        parts.append(T("pivot", (0.0, 0.012, -0.04), (0.0, 0.016, -0.04), 0.005, 6, "raw_steel"))
        # The cable adjuster barrel and its lock ring, pointing off to the cable.
        parts.append(T("adjuster", (0.01, 0.0, -0.035), (0.016, 0.0, -0.055), 0.005, 10, "raw_steel"))
        parts.append(T("lock", (0.0115, 0.0, -0.04), (0.0125, 0.0, -0.043), 0.0065, 10, "raw_steel"))
        # The clamp's two bolts on the rider's side.
        for x in (-0.008, 0.008):
            parts.append(T("bolt", (x, 0.0, 0.018), (x, 0.0, 0.024), 0.004, 6, "raw_steel"))
    return kit.join(parts, "clutch_perch")


def lever(lod):
    segs = [10, 6, 4][lod]
    route = [(0.0, -0.004, -0.04), (-0.02, -0.006, -0.048), (-0.05, -0.009, -0.05), (-0.09, -0.011, -0.048), (-LEVER_REACH, -0.012, -0.045)] \
        if lod < 2 else [(0.0, -0.004, -0.04), (-0.05, -0.009, -0.05), (-LEVER_REACH, -0.012, -0.045)]
    radii = [0.0075, 0.0065, 0.0058, 0.0055, 0.005][:len(route)] if lod < 2 else [0.0075, 0.006, 0.005]
    parts = [kit.sweep("blade", [g(*p) for p in route], radii, segs, "cast_alloy", squash=0.55, side=(0.0, 0.0, 1.0))]
    parts.append(kit.sphere("ball", g(-LEVER_REACH - 0.002, -0.012, -0.045), 0.009, (1.0, 1.0, 1.0), segs, "cast_alloy"))
    return kit.join(parts, "lever")


def master(radial):
    def make(lod):
        segs = [16, 10, 6][lod]
        parts = [T("clamp", (-0.016, 0.0, 0.0), (0.016, 0.0, 0.0), 0.019, segs, "cast_alloy", 0.002 if lod == 0 else 0.0)]
        if radial:
            parts.append(kit.prism("body", kit.rounded_rect(0.02, 0.025, 0.006, 2 if lod == 0 else 1), -0.018, 0.018, "cast_alloy", at=(0.0, 0.02, 0.0)))
            # A remote reservoir cup on a short stalk.
            parts.append(T("stalk", (0.0, 0.018, -0.01), (0.0, 0.03, -0.01), 0.004, 8, "raw_steel"))
            parts.append(T("cup", (0.0, 0.03, -0.01), (0.0, 0.058, -0.01), 0.022, segs, "plastic", 0.002 if lod == 0 else 0.0))
            parts.append(T("cap", (0.0, 0.058, -0.01), (0.0, 0.062, -0.01), 0.02, segs, "black_metal"))
        else:
            parts.append(kit.prism("body", kit.rounded_rect(0.0175, 0.02, 0.005, 2 if lod == 0 else 1), -0.0175, 0.0175, "cast_alloy", at=(0.0, 0.014, 0.0)))
            parts.append(T("reservoir", (0.0, 0.018, 0.0), (0.0, 0.055, 0.0), 0.018, segs, "cast_alloy", 0.002 if lod == 0 else 0.0))
            parts.append(T("cap", (0.0, 0.055, 0.0), (0.0, 0.059, 0.0), 0.016, segs, "black_metal"))
        if lod < 2:
            # The banjo bolt for the hose underneath, and the clamp's bolts.
            parts.append(T("banjo", (0.0, -0.002, -0.03), (0.0, -0.018, -0.03), 0.0075, 6, "raw_steel"))
            for x in (-0.01, 0.01):
                parts.append(T("bolt", (x, 0.0, 0.018), (x, 0.0, 0.024), 0.004, 6, "raw_steel"))
            parts.append(T("boss", (0.0, -0.01, -0.03), (0.0, 0.01, -0.03), 0.007, segs, "cast_alloy"))
        return kit.join(parts, "master")
    return make


def bar_clamp(lod):
    parts = []
    segs = [16, 10, 6][lod]
    for x in (-0.04, 0.04):
        parts.append(T("riser", (x, -0.015, 0.0), (x, 0.0, 0.0), 0.014, segs, "cast_alloy"))
        parts.append(kit.prism("cap", kit.rounded_rect(0.014, 0.02, 0.006, 2 if lod == 0 else 1), -0.01, 0.01, "cast_alloy", plane="YZ",
            at=(x, 0.0, 0.0)))
        if lod < 2:
            for z in (-0.012, 0.012):
                parts.append(T("bolt", (x, 0.015, z), (x, 0.02, z), 0.0035, 6, "raw_steel"))
    return kit.join(parts, "bar_clamp")


def hanger(lod):
    outline = kit.rounded_rect(0.5, 0.5, 0.12, 3 if lod == 0 else 1) if lod < 2 else [(0.5, 0.5), (-0.5, 0.5), (-0.5, -0.5), (0.5, -0.5)]
    parts = [kit.prism("plate", outline, -HANGER_T * 0.5, HANGER_T * 0.5, "cast_alloy", plane="YZ")]
    if lod == 0:
        # A pocket milled in its outer face, and the bolt heads at the top.
        parts.append(kit.prism("pocket", kit.rounded_rect(0.28, 0.18, 0.08, 2), HANGER_T * 0.5 - 0.001, HANGER_T * 0.5 + 0.0005, "black_metal", plane="YZ"))
    return kit.join(parts, "hanger")


def peg_alloy(lod):
    segs = [12, 8, 6][lod]
    parts = [T("peg", (-0.02, 0.0, 0.0), (0.07, 0.0, 0.0), 0.011, segs, "cast_alloy", 0.002 if lod == 0 else 0.0)]
    if lod < 2:
        # Serrations across its top and bottom for the boot to bite on.
        for k in range(5 if lod == 0 else 2):
            x = 0.008 + k * 0.014 * (1 if lod == 0 else 2)
            for y in (0.011, -0.011):
                parts.append(kit.prism("tooth", kit.rounded_rect(0.002, 0.011, 0.001, 1), -0.0035, 0.0035, "cast_alloy", at=(x, 0.0, y)))
    return kit.join(parts, "peg_alloy")


def cleat(lod):
    parts = [kit.prism("cleat", kit.rounded_rect(0.055, 0.0275, 0.008, 2 if lod == 0 else 1), -0.009, 0.009, "cast_alloy", 0.002 if lod == 0 else 0.0)]
    parts[-1].location = (0.015, 0.0, 0.0)
    if lod < 2:
        for k in range(3):
            parts.append(kit.prism("tooth", kit.rounded_rect(0.003, 0.029, 0.001, 1), 0.009, 0.016, "cast_alloy", at=(-0.025 + k * 0.035 + 0.015, 0.0, 0.0)))
    return kit.join(parts, "cleat")


def floorboard(lod):
    parts = [] if lod == 2 else [kit.prism("plate", kit.rounded_rect(0.062, 0.1375, 0.03, 3 if lod == 0 else 1), -0.018, -0.01, "chrome", 0.002 if lod == 0 else 0.0)]
    parts.append(kit.prism("pad", kit.rounded_rect(0.058, 0.133, 0.028, 3 if lod == 0 else 1), -0.01, 0.006, "rubber"))
    if lod == 0:
        for k in range(9):
            y = -0.11 + k * 0.0275
            parts.append(kit.prism("rib", kit.rounded_rect(0.05, 0.004, 0.002, 1), 0.006, 0.01, "rubber", at=(0.0, y, 0.0)))
    return kit.join(parts, "floorboard")


def parts():
    out = []
    for name, build in (("grip", grip), ("bar_end", bar_end), ("switch_left", switch_left), ("throttle", throttle),
            ("clutch_perch", clutch_perch), ("lever", lever), ("master_axial", master(False)), ("master_radial", master(True)),
            ("bar_clamp", bar_clamp), ("hanger", hanger), ("peg_alloy", peg_alloy), ("cleat", cleat), ("floorboard", floorboard)):
        out.append({"kind": "controls", "path": "controls/%s.glb" % name, "build": build, "mounts": {}})
    return out
