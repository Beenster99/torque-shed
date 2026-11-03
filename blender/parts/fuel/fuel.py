"""The fuel systems and the ignition BikeModel._draw_fuel and _draw_spark_plugs put on the engine,
in the game's axes round the point each piece goes on (a point (x, y, z) in the game's axes is
Blender's (x, -z, y)). The game turns each so its +Z runs where the piece points and its +Y up.

- "fuel/carb_round.glb": a round-slide carburettor, its origin on the inlet port and its bore
  running back along +Z (0.07 m to its mouth): the body, the slide's round tower and screw cap on
  top, the float bowl underneath with its screws and drain, the tickler and the throttle cable.
- "fuel/carb_flat.glb": a flat-slide racing carb: a square slide housing with its cover plate and
  screws, the accelerator pump on the bowl, and a bell mouth on the bore.
- "fuel/throttle_body.glb": an injection throttle body: the bore with its throttle spindle and
  pulley on the left, the throttle position sensor on the right, the injector up top with its
  plug, and the fuel rail's stub.
- "fuel/throttle_body_race.glb": the same with a second (shower) injector over the mouth and a
  bigger bore.
- "spark_plugs/plug.glb": a spark plug standing up along +Y from where it screws into the head:
  the hex, the ribbed insulator and the terminal nut.
- "spark_plugs/cap.glb": the plug cap's boot over it, rising along +Y and turning out along +X,
  as BikeModel bends it (0.035 m up, then 0.05 m out and 0.01 m down), with its lead's ferrule.
- "spark_plugs/cap_straight.glb": a boxer's cap, straight out along the plug (0.075 m).
- "spark_plugs/coil.glb": the ignition coil tucked under the tank: a ribbed black body with its
  towers for the leads at the front (-Z) and its mounting tabs.

Tags: paint (the fuel system's or the plugs' colour), cast_alloy, polished_alloy, black_metal,
plastic, rubber, raw_steel, chrome."""

import math

import kit

DETAIL = [
    {"round": 18, "small": 8},
    {"round": 10, "small": 6},
    {"round": 6, "small": 4},
]


def g(x, y, z):
    return (x, -z, y)


def gz(name, z0, z1, r, segs, tag, x=0.0, y=0.0, r_end=None):
    """A tube along the game's Z (the bore) at (x, y)."""
    return kit.tube(name, g(x, y, z0), g(x, y, z1), r, segs, tag, r_end=r_end)


def gy(name, y0, y1, r, segs, tag, x=0.0, z=0.0, r_end=None):
    """A tube along the game's Y (up) at (x, z)."""
    return kit.tube(name, g(x, y0, z), g(x, y1, z), r, segs, tag, r_end=r_end)


def gx(name, x0, x1, r, segs, tag, y=0.0, z=0.0):
    return kit.tube(name, g(x0, y, z), g(x1, y, z), r, segs, tag)


def box_y(name, c, half, tag, r=0.004, segs=2):
    """A rounded box round game point `c`, its corners rounded seen from above (the game's Y)."""
    x, y, z = c
    hx, hy, hz = half
    return kit.prism(name, kit.rounded_rect(hx, hz, r, segs), y - hy, y + hy, tag, at=(x, -z, 0.0))


# --------------------------------------------------------------------------------------- carbs

def carb(flat, lod):
    d = DETAIL[lod]
    parts = []
    # The bore: the inlet spigot into the rubber, the body, and the mouth the filter fits on.
    parts.append(gz("spigot", 0.0, 0.022, 0.024, d["round"], "black_metal" if not flat else "rubber"))
    parts.append(gz("bore", 0.018, 0.07, 0.026, d["round"], "paint"))
    if flat:
        # A bell mouth.
        parts.append(kit.revolve("bell", [(0.0, 0.026), (0.006, 0.03), (0.012, 0.036), (0.014, 0.036), (0.014, 0.0)] if lod < 2 else
            [(0.0, 0.026), (0.012, 0.036), (0.012, 0.0)], d["round"], "polished_alloy"))
        bell = parts[-1]
        # (kit.revolve turns round Blender's X: lay it along the game's Z, at the mouth.)
        bell.rotation_euler = (0.0, 0.0, -math.pi * 0.5)
        bell.location = g(0.0, 0.0, 0.07)
    # The body round the slide, the slide's housing on top and the float bowl under it.
    zc = 0.05
    parts.append(box_y("body", (0.0, -0.008, zc), (0.0275, 0.022, 0.024), "paint", 0.008 if lod < 2 else 0.004, 3 if lod < 2 else 1))
    if flat:
        parts.append(box_y("slide", (0.0, 0.028, zc), (0.024, 0.016, 0.02), "paint", 0.004, 2 if lod < 2 else 1))
        parts.append(box_y("plate", (0.0, 0.0455, zc), (0.022, 0.0015, 0.018), "polished_alloy", 0.003, 1))
        if lod == 0:
            for x in (-0.017, 0.017):
                for z in (-0.013, 0.013):
                    parts.append(kit.hex_nut("screw", g(x, 0.047, zc + z), (0.0, 0.0, 1.0), 0.0025, 0.002))
        # The accelerator pump on the side of the bowl, and its rod up to the slide.
        if lod < 2:
            parts.append(box_y("pump", (0.024, -0.045, zc), (0.008, 0.01, 0.012), "paint", 0.003, 1))
            parts.append(gy("rod", -0.035, 0.03, 0.0018, d["small"], "raw_steel", x=0.031, z=zc))
    else:
        parts.append(gy("tower", 0.012, 0.04, 0.02, d["round"], "paint", z=zc))
        parts.append(gy("cap", 0.04, 0.048, 0.021, d["round"], "polished_alloy", z=zc))
        if lod < 2:
            parts.append(kit.hex_nut("adjuster", g(0.0, 0.048, zc), (0.0, 0.0, 1.0), 0.005, 0.008))
        if lod == 0:
            # The tickler, a little plunger on the bowl's side.
            parts.append(gx("tickler", 0.026, 0.036, 0.004, d["small"], "raw_steel", y=-0.03, z=zc - 0.012))
    # The float bowl and its screws and drain.
    parts.append(gy("bowl", -0.064, -0.03, 0.025, d["round"], "paint", z=zc))
    if lod == 0:
        for x in (-0.016, 0.016):
            parts.append(kit.hex_nut("screw", g(x, -0.064, zc), (0.0, 0.0, -1.0), 0.0035, 0.003))
        parts.append(gy("drain", -0.074, -0.064, 0.0028, d["small"], "raw_steel", z=zc))
        # The fuel inlet banjo on the bowl's front.
        parts.append(gz("inlet", zc - 0.035, zc - 0.022, 0.005, d["small"], "polished_alloy", y=-0.045))
    if lod < 2:
        # The throttle cable's adjuster, where the cable goes in.
        top = 0.048 if not flat else 0.047
        x = 0.0 if not flat else 0.016
        parts.append(gy("cable_adj", top, top + 0.008, 0.0045, d["small"], "polished_alloy", x=x, z=zc if not flat else zc - 0.014))
    return kit.join(parts, "carb")


def throttle_body(race, lod):
    d = DETAIL[lod]
    r = 0.03 if not race else 0.033
    parts = [gz("spigot", 0.0, 0.016, r - 0.003, d["round"], "black_metal"),
        gz("bore", 0.014, 0.07, r, d["round"], "paint")]
    parts.append(gz("lip", 0.066, 0.072, r + 0.003, d["round"], "polished_alloy"))
    # The throttle spindle across, its pulley on the left and the position sensor on the right.
    parts.append(gx("spindle", -r - 0.012, r + 0.006, 0.006, d["small"], "raw_steel", z=0.036))
    parts.append(gx("pulley", -r - 0.02, -r - 0.01, 0.017 if lod < 2 else 0.015, d["round"], "black_metal", z=0.036))
    parts.append(box_y("tps", (r + 0.008, 0.0, 0.036), (0.006, 0.014, 0.012), "plastic", 0.003, 1))
    if lod < 2:
        parts.append(box_y("tps_plug", (r + 0.008, 0.017, 0.03), (0.005, 0.005, 0.006), "plastic", 0.002, 1))
    # The injector up top, tilted into the port, with its plug, and the rail's stub across.
    tip = (0.0, r * 0.6, 0.03)
    top = (0.0, r + 0.038, 0.048)
    parts.append(kit.tube("injector", g(*tip), g(*top), 0.008, d["small"] + 2, "black_metal"))
    parts.append(box_y("inj_plug", (0.0, top[1] - 0.006, top[2] + 0.012), (0.006, 0.006, 0.008), "plastic", 0.002, 1))
    parts.append(gx("rail", -0.03, 0.03, 0.007, d["small"], "polished_alloy", y=top[1] + 0.004, z=top[2]))
    if race:
        # The shower injector over the mouth.
        stip = (0.0, r + 0.004, 0.072)
        stop = (0.0, r + 0.034, 0.08)
        parts.append(kit.tube("shower", g(*stip), g(*stop), 0.007, d["small"] + 2, "black_metal"))
        if lod < 2:
            parts.append(kit.tube("mount", g(0.0, r - 0.002, 0.068), g(*stip), 0.006, d["small"], "polished_alloy"))
    return kit.join(parts, "throttle_body")


# ------------------------------------------------------------------------------------- ignition

def plug(lod):
    d = DETAIL[lod]
    parts = [gy("hex", 0.0, 0.008, 0.011, 6, "raw_steel"),
        gy("insulator", 0.008, 0.026, 0.0068, d["round"], "paint", r_end=0.0058),
        gy("terminal", 0.026, 0.032, 0.0028, d["small"], "raw_steel")]
    if lod == 0:
        for k in range(4):
            y = 0.012 + k * 0.0035
            parts.append(gy("rib", y, y + 0.0015, 0.0074 - k * 0.0003, d["round"], "paint"))
    if lod < 2:
        parts.append(gy("nut", 0.029, 0.034, 0.0045, d["small"], "raw_steel"))
    return kit.join(parts, "plug")


def cap(lod):
    d = DETAIL[lod]
    # BikeModel's bend: from 0.02 up the plug, to the elbow at 0.035, to 0.05 out and 0.01 down.
    pts = [g(0.0, 0.016, 0.0), g(0.0, 0.03, 0.0), g(0.006, 0.037, 0.0), g(0.02, 0.034, 0.0), g(0.05, 0.025, 0.0)]
    parts = [kit.sweep("boot", pts, [0.0135, 0.0145, 0.014, 0.0115, 0.009], d["round"], "rubber")]
    if lod < 2:
        # The skirt where it grips the plug, and the ferrule the lead comes out of.
        parts.append(gy("skirt", 0.012, 0.02, 0.0145, d["round"], "rubber"))
        parts.append(kit.tube("ferrule", g(0.046, 0.0262, 0.0), g(0.054, 0.0238, 0.0), 0.0065, d["small"], "raw_steel"))
    return kit.join(parts, "cap")


def cap_straight(lod):
    """A boxer's plug cap, straight out along the plug from the head (BikeModel's straight bend,
    0.075 m out), its lead coming out of the end."""
    d = DETAIL[lod]
    parts = [gy("boot", 0.012, 0.066, 0.0145, d["round"], "rubber", r_end=0.011)]
    if lod < 2:
        parts.append(gy("grip", 0.03, 0.05, 0.0148, d["round"], "rubber"))
        parts.append(gy("ferrule", 0.066, 0.075, 0.0065, d["small"], "raw_steel"))
    return kit.join(parts, "cap_straight")


def coil(lod):
    d = DETAIL[lod]
    parts = [box_y("body", (0.0, 0.0, 0.0), (0.0225, 0.0175, 0.0375), "black_metal", 0.006 if lod < 2 else 0.003, 3 if lod < 2 else 1)]
    if lod == 0:
        for k in range(4):
            z = -0.02 + k * 0.014
            parts.append(box_y("rib", (0.0, 0.0, z), (0.0235, 0.0165, 0.002), "black_metal", 0.004, 1))
    for x in (-0.012, 0.012):
        parts.append(gz("tower", -0.045, -0.036, 0.007, d["small"] + 2, "plastic", x=x))
        if lod < 2:
            parts.append(gz("boot", -0.05, -0.044, 0.0055, d["small"], "rubber", x=x))
    if lod < 2:
        for z in (-0.03, 0.03):
            parts.append(box_y("tab", (0.0, 0.019, z), (0.028, 0.0015, 0.006), "raw_steel", 0.002, 1))
        parts.append(box_y("plug", (0.0, -0.02, 0.025), (0.008, 0.004, 0.007), "plastic", 0.002, 1))
    return kit.join(parts, "coil")


def parts():
    return [
        {"kind": "fuel", "path": "fuel/carb_round.glb", "build": lambda lod: carb(False, lod), "mounts": {}},
        {"kind": "fuel", "path": "fuel/carb_flat.glb", "build": lambda lod: carb(True, lod), "mounts": {}},
        {"kind": "fuel", "path": "fuel/throttle_body.glb", "build": lambda lod: throttle_body(False, lod), "mounts": {}},
        {"kind": "fuel", "path": "fuel/throttle_body_race.glb", "build": lambda lod: throttle_body(True, lod), "mounts": {}},
        {"kind": "spark_plugs", "path": "spark_plugs/plug.glb", "build": plug, "mounts": {}},
        {"kind": "spark_plugs", "path": "spark_plugs/cap.glb", "build": cap, "mounts": {}},
        {"kind": "spark_plugs", "path": "spark_plugs/cap_straight.glb", "build": cap_straight, "mounts": {}},
        {"kind": "spark_plugs", "path": "spark_plugs/coil.glb", "build": coil, "mounts": {}},
    ]
