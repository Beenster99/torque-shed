"""The ends of the control cables, where BikeModel._draw_cables and _draw_drum run them into the
clutch arm, the carbs and a drum's brake arm:

- "controls/cable_end.glb": the cable's threaded adjuster with its lock nut and the outer's
  ferrule, 20 mm long round its middle along +Y (the game turns +Y along the cable's last run).

Axes are the game's (x out, y up, z back) as Blender's (x, -z, y). Tags: `raw_steel`, the outer's
end `black_metal`."""

import kit

DETAIL = [{"round": 10}, {"round": 6}, {"round": 5}]


def g(x, y, z):
    return (x, -z, y)


def cable_end(lod):
    d = DETAIL[lod]
    parts = [kit.tube("adjuster", g(0.0, -0.01, 0.0), g(0.0, 0.004, 0.0), 0.0055, d["round"], "raw_steel"),
        kit.tube("ferrule", g(0.0, 0.004, 0.0), g(0.0, 0.01, 0.0), 0.005, d["round"], "black_metal", r_end=0.0045)]
    if lod < 2:
        parts.append(kit.hex_nut("lock", g(0.0, -0.004, 0.0), (0.0, 0.0, 1.0), 0.008, 0.004))
    if lod == 0:
        for y in (-0.009, -0.0075):
            parts.append(kit.tube("thread", g(0.0, y, 0.0), g(0.0, y + 0.0007, 0.0), 0.006, d["round"], "raw_steel"))
    return kit.join(parts, "cable_end")


def parts():
    return [{"kind": "controls", "path": "controls/cable_end.glb", "build": cable_end, "mounts": {}}]
