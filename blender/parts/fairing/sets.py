"""Frame-mounted fairings as proper bodywork (Rig built, bodywork track H4): each a set of
panels on a stay from the head stock, as the real ones are built. One glb per set:

- `sport`: a Panigale V4 / S1000RR / ZX-10R full fairing: a pointed nose with slim lamps under
  its brow and the screen on top, upper side panels whose top edge runs back from behind the
  screen down to the spar line, lower panels with radiator ducts wrapping the engine, a belly pan;
- `race`: the same pared down as a MotoGP bike's: no lamps, a taller bubble, winglets;
- `half`: the sport set's nose and upper panels alone, a modern half fairing;
- `seeley`: a café racer's round half fairing (Thruxton RS, Seeley), one moulding;
- `adventure`: a GS / Multistrada upper: a tall screen over a narrow nose, side shrouds;
- `touring`: an FJR1300's: a broad nose and tall screen, wide upper panels down to knee wings.

Every panel is a moulding a few millimetres thick, its edges dark (`plastic`) so each cut line
between two panels reads as one. Dzus fasteners sit along the cut lines and the mirrors' mounts
on the upper panels. The glb's origin is the rig's stay root (BikeModel.rig "stay_head": the front
of the head stock's top, lines agreement 3), in metres, the bike's front along +Y (the game's -Z).
Mount points: `mirror_r`, `mirror_l` (where the mirrors stand), `lamp` (the middle of the lamps).

Shape keys the game sets per bike, so one set fits the frames it goes on:
- `width`: 15% wider all round (a wide engine, a wide frame);
- `length`: the panels behind the head stock 15% longer (a longer tank or frame);
- `drop`: the lower panels and belly 80 mm lower (down to the rig's belly line).

Tags: panels `paint`, cut lines and inner faces `plastic`, ducts and fasteners `black_metal`,
screen `glass`, lamps `lens_white`."""

import math

import bmesh
import bpy

import kit

# Each set's sections down its length: [z back from the stay root, top, bottom, half width,
# squareness]; and its panels, each [name, tag, (z, angle) corners front-top, rear-top,
# rear-bottom, front-bottom, mirrored?]. Angles run round the section from the top's middle
# (0) down the right side to the belly's middle (pi); past pi is the left side coming back up.
PI = math.pi
# A sports fairing's sections drawn as a designer would, through its lines rather than as a round
# section: [z, top, shoulder (x, y), character line (x, y), lower flank (x, y), belly], the
# character line at the frame's spar height and the shoulder where the tank's meets it.
SPORT_STATIONS = [
    # Drawn with a ruler, as a Panigale's is: the top rising straight from the nose's tip to the
    # screen; the bottom running straight back level across the top of the front guard, then a
    # sharp straight drop behind the tyre (two stations close together at each corner keep the
    # spline from rounding it) to a flat bottom line.
    [-0.4, -0.175, (0.035, -0.18), (0.055, -0.2), (0.045, -0.22), -0.23],
    [-0.33, -0.115, (0.075, -0.12), (0.105, -0.17), (0.085, -0.235), -0.24],
    [-0.19, -0.01, (0.1, -0.03), (0.145, -0.145), (0.12, -0.255), -0.255],
    [-0.06, 0.005, (0.11, -0.01), (0.17, -0.14), (0.15, -0.27), -0.27],
    [-0.03, 0.005, (0.112, -0.01), (0.173, -0.14), (0.153, -0.285), -0.285],
    [0.13, 0.0, (0.12, -0.01), (0.195, -0.15), (0.19, -0.56), -0.6],
    [0.17, 0.0, (0.122, -0.015), (0.198, -0.155), (0.195, -0.575), -0.6],
    [0.32, -0.04, (0.135, -0.05), (0.205, -0.17), (0.2, -0.58), -0.6],
    [0.56, -0.1, (0.13, -0.11), (0.19, -0.2), (0.19, -0.575), -0.6],
    [0.7, -0.14, (0.12, -0.15), (0.175, -0.23), (0.175, -0.55), -0.58],
]
SPORT = {
    "stations": SPORT_STATIONS,
    "panels": [
        ["nose", "paint", [(-0.4, -1.45), (0.0, -1.45), (0.0, 1.45), (-0.4, 1.45)], False],
        ["chin", "paint", [(-0.4, 1.45), (0.0, 1.45), (0.0, 2 * PI - 1.45), (-0.4, 2 * PI - 1.45)], False],
        ["upper", "paint", [(0.0, 1.3), (0.64, 0.8), (0.66, 1.45), (0.0, 1.45)], True],
        ["lower", "paint", [(0.0, 1.45), (0.66, 1.45), (0.58, 2.6), (0.15, 2.6)], True],
        ["belly", "paint", [(0.15, 2.6), (0.58, 2.6), (0.58, 2 * PI - 2.6), (0.15, 2 * PI - 2.6)], False],
    ],
    "screen": [(-0.34, 0.0), 0.55, 0.2],       # (front z, rear z), half angle, rise at the back
    "lamps": [(-0.385, -0.25), (0.95, 1.3)],    # z range, angle range, right (and mirrored)
    "mouth": True,                             # a blunt nose, its front an air intake
    "ducts": [(0.06, 0.26), (1.65, 2.05)],
    "slots": 3,                                # the ducts as so many slim vents
    "mirror": (-0.06, 1.05),
    "wings": None,
}
RACE = dict(SPORT, stations=[[z - 0.02 if z < 0 else z, top, (sh[0] * 0.92, sh[1]), (cr[0] * 0.9, cr[1]), (lo[0] * 0.9, lo[1]), bot]
    for z, top, sh, cr, lo, bot in SPORT_STATIONS],
    screen=[(-0.27, 0.04), 0.6, 0.2], lamps=None, mirror=None, wings=[(-0.08, 0.08), 1.25])
HALF = dict(SPORT, panels=SPORT["panels"][:1] + [["upper", "paint", [(0.0, 1.3), (0.3, 1.05), (0.3, 1.55), (0.0, 1.55)], True],
    ["chin", "paint", [(-0.36, 1.45), (-0.02, 1.45), (-0.02, 2 * PI - 1.45), (-0.36, 2 * PI - 1.45)], False]], ducts=None)
SEELEY = {
    "secs": [[-0.3, -0.03, -0.24, 0.115, 2.0], [-0.24, 0.005, -0.29, 0.165, 2.0], [-0.12, 0.02, -0.33, 0.2, 2.0], [0.04, 0.01, -0.35, 0.21, 2.1],
        [0.2, -0.04, -0.33, 0.2, 2.2]],
    "panels": [["shell", "paint", [(-0.3, -2.25), (0.12, -2.25), (0.12, 2.25), (-0.3, 2.25)], False],
        ["wing", "paint", [(0.12, 0.7), (0.2, 1.2), (0.2, 2.25), (0.12, 2.25)], True]],
    "screen": [(-0.17, 0.04), 0.75, 0.12],
    "lamps": None,
    "ducts": None, "mirror": None, "wings": None, "round_lamp": 0.085,
}
# A Multistrada's / GS's upper drawn through its lines: a sharp beak low at the front (its intake
# black), the lamps' face slanting back up from it to a raked screen, and side shrouds that close
# the bay down round the radiator to the engine.
ADVENTURE = {
    "stations": [
        [-0.44, -0.28, (0.02, -0.282), (0.03, -0.288), (0.025, -0.293), -0.296],
        [-0.405, -0.17, (0.05, -0.18), (0.08, -0.225), (0.06, -0.28), -0.3],
        [-0.35, -0.05, (0.09, -0.06), (0.13, -0.18), (0.1, -0.3), -0.32],
        [-0.2, 0.02, (0.13, 0.0), (0.19, -0.17), (0.15, -0.33), -0.36],
        [-0.06, 0.05, (0.15, 0.025), (0.22, -0.16), (0.2, -0.38), -0.42],
        [0.1, 0.04, (0.17, 0.01), (0.25, -0.2), (0.24, -0.54), -0.6],
        [0.26, 0.0, (0.17, -0.03), (0.25, -0.22), (0.24, -0.58), -0.64],
        [0.4, -0.05, (0.16, -0.07), (0.23, -0.24), (0.22, -0.56), -0.62],
    ],
    # The paint and the black beak under it cut on a diagonal, so the beak reads as its own
    # sharp layer under the nose, as a Multistrada's does.
    "panels": [["nose", "paint", [(-0.44, -0.85), (0.02, -1.5), (0.02, 1.5), (-0.44, 0.85)], False],
        ["shroud", "paint", [(0.02, 0.6), (0.4, 0.8), (0.28, 2.5), (0.04, 2.3)], True],
        ["chin", "plastic", [(-0.44, 0.85), (0.0, 1.5), (0.0, 2 * PI - 1.5), (-0.44, 2 * PI - 0.85)], False]],
    "screen": [(-0.31, -0.06), 0.7, 0.36],
    "lamps": [(-0.38, -0.24), (0.4, 0.8)],
    "max": 14,
    "mouth": True,
    "ducts": [(0.1, 0.3), (1.5, 2.0)],
    "slots": 3,
    "mirror": (0.0, 0.95), "wings": None,
}
# A sports tourer's (CB1000GT, Tracer 9) drawn through its lines: a thin, sharp nose with slim lamps
# and a tall raked screen, the character line creased hard along the flanks, and side panels that
# run down round the radiator with slim vents.
TOURING = {
    "stations": [
        [-0.43, -0.26, (0.02, -0.262), (0.03, -0.268), (0.025, -0.273), -0.276],
        [-0.395, -0.15, (0.05, -0.16), (0.085, -0.2), (0.065, -0.25), -0.27],
        [-0.33, -0.04, (0.09, -0.05), (0.14, -0.16), (0.11, -0.27), -0.29],
        [-0.2, 0.0, (0.12, -0.02), (0.185, -0.15), (0.15, -0.29), -0.31],
        [-0.04, 0.04, (0.15, 0.02), (0.23, -0.15), (0.2, -0.34), -0.37],
        [0.12, 0.03, (0.17, 0.0), (0.26, -0.17), (0.23, -0.46), -0.5],
        [0.3, -0.02, (0.17, -0.05), (0.25, -0.2), (0.22, -0.5), -0.54],
        [0.44, -0.07, (0.15, -0.09), (0.22, -0.22), (0.2, -0.47), -0.5],
    ],
    "panels": [["nose", "paint", [(-0.43, -0.9), (0.02, -1.45), (0.02, 1.45), (-0.43, 0.9)], False],
        ["upper", "paint", [(0.02, 1.2), (0.44, 0.75), (0.44, 1.45), (0.02, 1.45)], True],
        ["knee", "paint", [(0.02, 1.45), (0.44, 1.45), (0.36, 2.45), (0.06, 2.35)], True],
        ["chin", "plastic", [(-0.43, 0.9), (0.0, 1.45), (0.0, 2 * PI - 1.45), (-0.43, 2 * PI - 0.9)], False]],
    "screen": [(-0.3, -0.02), 0.62, 0.34],
    "lamps": [(-0.4, -0.27), (0.5, 0.85)],
    "max": 14,
    "mouth": True,
    "ducts": [(0.1, 0.3), (1.6, 2.1)],
    "slots": 3,
    "mirror": (0.0, 1.1), "wings": None,
}
SETS = {"sport": SPORT, "race": RACE, "half": HALF, "seeley": SEELEY, "adventure": ADVENTURE, "touring": TOURING}

BASE = {"width": 0.0, "length": 0.0, "drop": 0.0}
KEYS = {"width": {"width": 1.0}, "length": {"length": 1.0}, "drop": {"drop": 1.0}}
DETAIL = [{"per_m": 60, "min": 4, "max": 20, "thick": True}, {"per_m": 24, "min": 2, "max": 8, "thick": True},
    {"per_m": 8, "min": 2, "max": 3, "thick": False}]
THICK = 0.004             # m: a panel's moulding
GAP = 0.004               # m: the cut line between two panels, each side's half of it


def g(x, y, z):
    """A point in the glb's Godot space (x right, y up, z back) as Blender's."""
    return (x, -z, y)


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


STATION_AT = [0.0, 0.6, 1.35, 2.3, PI]   # where round the section each station point is


def stations_of(st):
    """A set's stations: its own, or made from its round sections ([z, top, bottom, half width,
    squareness]) at the station angles."""
    if "stations" in st:
        return st["stations"]
    out = []
    for z, yt, yb, w, n in st["secs"]:
        e = 2.0 / n
        yc, h = (yt + yb) * 0.5, (yt - yb) * 0.5
        pts = [(w * abs(math.sin(a)) ** e, yc + h * math.copysign(abs(math.cos(a)) ** e, math.cos(a))) for a in STATION_AT[1:4]]
        out.append([z, yt, pts[0], pts[1], pts[2], yb])
    return out


def station_at(st, z):
    """The section's five points at `z` [(x, y) top, shoulder, character line, lower, belly],
    eased between the set's stations."""
    sts = stations_of(st)

    def pts(k):
        return [(0.0, k[1]), k[2], k[3], k[4], (0.0, k[5])]
    if z <= sts[0][0]:
        return pts(sts[0])
    n = len(sts)
    for j in range(n - 1):
        if z <= sts[j + 1][0]:
            # A Catmull-Rom spline through the stations along the length, so the skin runs on
            # smoothly through each one rather than easing to a stop at it (which rippled it).
            f = (z - sts[j][0]) / (sts[j + 1][0] - sts[j][0])
            ks = [pts(sts[max(j - 1, 0)]), pts(sts[j]), pts(sts[j + 1]), pts(sts[min(j + 2, n - 1)])]
            f2, f3 = f * f, f * f * f

            def cr(p0, p1, p2, p3):
                return 0.5 * (2.0 * p1 + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)
            return [(cr(*[k[i][0] for k in ks]), cr(*[k[i][1] for k in ks])) for i in range(5)]
    return pts(sts[-1])


def centre_y(st, z):
    p = station_at(st, z)
    return (p[0][1] + p[4][1]) * 0.5


def surface(st, p, z, th):
    """The fairing's skin at `z` back and `th` round (see SETS), as (x, y, z) in Godot space,
    with the shape keys `p` in: a smooth curve (Catmull-Rom) through the section's points."""
    pts = station_at(st, z)
    drop = 0.08 * p["drop"] * smoothstep(-0.15, 0.25, z)
    k = 1.0 + 0.15 * p["width"]
    pts = [(x * k, y - drop * (i / 4.0) ** 1.5) for i, (x, y) in enumerate(pts)]
    zz = z + 0.15 * p["length"] * max(z, 0.0)
    side = 1.0
    t = th
    if t < 0.0:
        t, side = -t, -1.0
    elif t > PI:
        t, side = 2.0 * PI - t, -1.0
    i = 0
    while i < 3 and t > STATION_AT[i + 1]:
        i += 1
    f = (t - STATION_AT[i]) / (STATION_AT[i + 1] - STATION_AT[i])
    # The neighbours past the top and the belly are the far side's, mirrored.
    ext = [(-pts[1][0], pts[1][1])] + pts + [(-pts[3][0], pts[3][1])]
    p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
    f2, f3 = f * f, f * f * f
    c = [0.5 * ((2.0 * p1[q]) + (-p0[q] + p2[q]) * f + (2.0 * p0[q] - 5.0 * p1[q] + 4.0 * p2[q] - p3[q]) * f2 + (-p0[q] + 3.0 * p1[q] - 3.0 * p2[q] + p3[q]) * f3) for q in (0, 1)]
    return (side * max(c[0], 0.0), c[1], zz)


def normal(st, p, z, th):
    """The skin's outward normal at (`z`, `th`), in Godot space."""
    d = 0.002
    a = surface(st, p, z, th)
    bz = surface(st, p, z + d, th)
    bt = surface(st, p, z, th + d)
    u = [bz[i] - a[i] for i in range(3)]
    v = [bt[i] - a[i] for i in range(3)]
    nx = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    ln = math.sqrt(sum(c * c for c in nx)) or 1.0
    nx = [c / ln for c in nx]
    out = (a[0], a[1] - centre_y(st, z))
    if nx[0] * out[0] + nx[1] * out[1] < 0.0:
        nx = [-c for c in nx]
    return nx


def lerp2(a, b, f):
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)


def grid(corners, ni, nj, gap=GAP):
    """(z, angle) points over a panel's four corners [front-top, rear-top, rear-bottom,
    front-bottom], `ni` along and `nj` round, pulled in from its edges by the cut line's `gap`."""
    ft, rt, rb, fb = corners
    rows = []
    for i in range(ni + 1):
        f = i / ni
        top = lerp2(ft, rt, f)
        bot = lerp2(fb, rb, f)
        rows.append([lerp2(top, bot, j / nj) for j in range(nj + 1)])
    # The gap: each edge pulled in (in z by `gap`, round by about `gap` at a 0.2 m radius).
    g_th = gap / 0.2
    for i, row in enumerate(rows):
        for j, (z, th) in enumerate(row):
            dz = gap if i == 0 else (-gap if i == ni else 0.0)
            dt = g_th if j == 0 else (-g_th if j == nj else 0.0)
            if th > PI or th < 0.0:
                pass
            row[j] = (z + dz, th + dt * (1.0 if corners[3][1] >= corners[0][1] else -1.0))
    return rows


def slab(name, st, p, uv_rows, tag, edge_tag, thick, lift=0.0, lifts=None):
    """A moulding over `uv_rows` ((z, angle) grid): its outer skin in `tag`, its inner face and
    its edges in `edge_tag`, `thick` deep (a single skin, facing out, when 0), raised `lift` off
    the fairing's skin (or by `lifts[i]` row by row)."""
    bm = bmesh.new()
    outer, inner = [], []
    for i, row in enumerate(uv_rows):
        lo, li = [], []
        up = lift if lifts is None else lifts[i]
        for z, th in row:
            s = surface(st, p, z, th)
            n = normal(st, p, z, th)
            o = [s[k] + n[k] * up for k in range(3)]
            lo.append(bm.verts.new(g(*o)))
            if thick > 0.0:
                li.append(bm.verts.new(g(*[o[k] - n[k] * thick for k in range(3)])))
        outer.append(lo)
        inner.append(li)
    ni, nj = len(uv_rows) - 1, len(uv_rows[0]) - 1
    faces = []
    for i in range(ni):
        for j in range(nj):
            faces.append((bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1])), 0))
            if thick > 0.0:
                faces.append((bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j])), 1))
    if thick > 0.0:
        ring_o = [outer[0][j] for j in range(nj)] + [outer[i][nj] for i in range(ni)] + \
            [outer[ni][j] for j in range(nj, 0, -1)] + [outer[i][0] for i in range(ni, 0, -1)]
        ring_i = [inner[0][j] for j in range(nj)] + [inner[i][nj] for i in range(ni)] + \
            [inner[ni][j] for j in range(nj, 0, -1)] + [inner[i][0] for i in range(ni, 0, -1)]
        m = len(ring_o)
        for k in range(m):
            faces.append((bm.faces.new((ring_o[(k + 1) % m], ring_o[k], ring_i[k], ring_i[(k + 1) % m])), 1))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    else:
        # One skin: faces out, as the normal at its middle says.
        mid = uv_rows[ni // 2][nj // 2]
        n = normal(st, p, *mid)
        f0 = faces[len(faces) // 2][0]
        want = g(*n)
        if sum(f0.normal[k] * want[k] for k in range(3)) < 0.0:
            for f, _ in faces:
                f.normal_flip()
    for f, k in faces:
        f.material_index = k
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(kit.tag_material(tag))
    me.materials.append(kit.tag_material(edge_tag))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def counts(corners, lod, cap=99):
    d = dict(DETAIL[lod])
    d["max"] = min(d["max"], cap)
    along = max(abs(corners[1][0] - corners[0][0]), abs(corners[2][0] - corners[3][0]))
    round_ = max(abs(corners[3][1] - corners[0][1]), abs(corners[2][1] - corners[1][1])) * 0.2
    ni = int(min(max(round(along * d["per_m"]), d["min"]), d["max"]))
    nj = int(min(max(round(round_ * d["per_m"]), d["min"]), d["max"]))
    return ni, nj


def mirrored(corners):
    return [(z, -th) if th <= PI else (z, 2.0 * PI - th) for z, th in [corners[0], corners[1], corners[2], corners[3]]]


def mouth(st, p, lod):
    """A blunt nose's front closed by its air intake: a black face across the first section,
    set a little back inside the nose's lip."""
    z0 = stations_of(st)[0][0]
    n = 24 if lod == 0 else (12 if lod == 1 else 6)
    bm = bmesh.new()
    ring = []
    for k in range(n):
        th = -PI + 2.0 * PI * k / n
        x, y, z = surface(st, p, z0, th)
        ring.append(bm.verts.new(g(x * 0.97, y, z + 0.012)))
    yc = centre_y(st, z0)
    c = bm.verts.new(g(0.0, yc, z0 + 0.03))
    faces = [bm.faces.new((ring[k], ring[(k + 1) % n], c)) for k in range(n)]
    ahead = g(0.0, 0.0, -1.0)
    if sum(faces[0].normal[k] * ahead[k] for k in range(3)) < 0.0:
        for f in faces:
            f.normal_flip()
    me = bpy.data.meshes.new("mouth")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(kit.tag_material("black_metal"))
    ob = bpy.data.objects.new("mouth", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_set(name, lod, p):
    st = SETS[name]
    d = DETAIL[lod]
    thick = THICK if d["thick"] else 0.0
    objs = []
    for pname, tag, corners, both in st["panels"]:
        for side in ((1, -1) if both else (1,)):
            cs = corners if side > 0 else mirrored(corners)
            if side < 0:
                # (Mirrored, the panel's corners run the other way round: keep them front-top first.)
                cs = [cs[0], cs[1], cs[2], cs[3]]
            ni, nj = counts(cs, lod, st.get("max", 99))
            objs.append(slab(pname, st, p, grid(cs, ni, nj), tag, "plastic", thick))
    if st.get("mouth"):
        objs.append(mouth(st, p, lod))
    # The screen: glass on the nose's top, rising off it towards the back.
    (z0, z1), half, rise = st["screen"]
    ni, nj = (10, 12) if lod == 0 else ((4, 5) if lod == 1 else (1, 2))
    rows = grid([(z0, -half), (z1, -half), (z1, half), (z0, half)], ni, nj, 0.0)
    lifts = [0.006 + rise * (i / ni) ** 1.7 for i in range(ni + 1)]
    objs.append(slab("screen", st, p, rows, "glass", "glass", 0.004 if lod < 2 else 0.0, lifts=lifts))
    if lod < 2:
        if st.get("lamps"):
            (lz0, lz1), (a0, a1) = st["lamps"]
            for s in (1, -1):
                cs = [(lz0, a0 * s), (lz1, a0 * s), (lz1, a1 * s), (lz0, a1 * s)]
                objs.append(slab("lamp", st, p, grid(cs, 8, 3, 0.0), "lens_white", "black_metal", 0.004, lift=0.003))
        if st.get("round_lamp"):
            # One round headlamp filling the nose's opening, set a little back inside it.
            z0 = stations_of(st)[0][0]
            at = (0.0, centre_y(st, z0), z0 + 0.03)
            objs.append(kit.tube("lamp", g(*at), g(at[0], at[1], at[2] - 0.012), st["round_lamp"], 24 if lod == 0 else 10, "lens_white"))
            objs.append(kit.tube("bezel", g(at[0], at[1], at[2] + 0.04), g(*at), st["round_lamp"] + 0.006, 24 if lod == 0 else 10, "chrome"))
        if st.get("ducts"):
            (dz0, dz1), (a0, a1) = st["ducts"]
            # One duct, or (`slots`) so many slim vents slanting back down the panel, as a
            # modern sports bike's are, rather than one open hole.
            n = st.get("slots", 0)
            if n:
                w = (dz1 - dz0) / (2.0 * n)
                vents = [[(dz0 + 2 * k * w, a0), (dz0 + 2 * k * w + w, a0), (dz0 + 2 * k * w + 1.6 * w, a1), (dz0 + 2 * k * w + 0.6 * w, a1)] for k in range(n)]
            else:
                vents = [[(dz0, a0), (dz1, a0), (dz1, a1), (dz0, a1)]]
            for v in vents:
                for s in (1, -1):
                    cs = v if s > 0 else [(z, 2 * PI - a) for z, a in v]
                    objs.append(slab("duct", st, p, grid(cs, 2 if n else 8, 5, 0.0), "black_metal", "black_metal", 0.004, lift=0.003))
        if st.get("wings"):
            (wz0, wz1), a = st["wings"]
            for s in (1, -1):
                at = surface(st, p, (wz0 + wz1) * 0.5, a * s)
                n = normal(st, p, (wz0 + wz1) * 0.5, a * s)
                tip = [at[k] + n[k] * 0.09 for k in range(3)]
                objs.append(kit.tube("wing", g(*at), g(tip[0], tip[1] + 0.01, tip[2] + 0.04), 0.03, 4, "carbon"))
                objs[-1].scale = (1.0, 0.2, 1.0)
        # Dzus fasteners along the cut lines: where each side panel meets the nose and the next.
        for pname, tag, corners, both in st["panels"]:
            if not both:
                continue
            for s in (1, -1):
                cs = corners if s > 0 else mirrored(corners)
                for f in (0.25, 0.75):
                    z, th = lerp2(cs[0], cs[3], f)
                    z += 0.012
                    at = surface(st, p, z, th)
                    n = normal(st, p, z, th)
                    objs.append(kit.tube("dzus", g(*at), g(*[at[k] + n[k] * 0.004 for k in range(3)]), 0.007, 8 if lod == 0 else 5, "black_metal"))
    ob = kit.join(objs, "fairing")
    return ob


def mounts(name):
    st = SETS[name]
    p = dict(BASE)
    out = {}
    if st.get("mirror"):
        z, th = st["mirror"]
        for s, side in ((1, "r"), (-1, "l")):
            at = surface(st, p, z, th * s)
            n = normal(st, p, z, th * s)
            out["mirror_" + side] = (g(*at), g(*n))
    if st.get("lamps"):
        (lz0, lz1), (a0, a1) = st["lamps"]
        at = surface(st, p, (lz0 + lz1) * 0.5, 0.0)
        out["lamp"] = (g(at[0], at[1] - 0.05, at[2]), (0.0, 1.0, 0.0))
    elif st.get("round_lamp"):
        z0 = stations_of(st)[0][0]
        out["lamp"] = (g(0.0, centre_y(st, z0), z0 + 0.03), (0.0, 1.0, 0.0))
    return out


def build(name):
    def make(lod):
        return kit.keyed(lambda p: build_set(name, lod, p), BASE, KEYS)
    return make


def parts():
    return [{"kind": "fairing", "path": "fairing/set/%s.glb" % name, "build": build(name), "mounts": mounts(name)} for name in SETS]
