"""Real forks for a baked road: a second way between two points of the route for the crew to vote on.

Used by route_bake.py (stage 3 of docs/real_world_plan.md). The route is the best way through the road graph; a fork
is the second best way between two of its junctions, with the main road's own stretch left out of the search. The
game rides the main road unless the crew votes for the other way at the signpost, and builds the road along it from
there (AdventureRoute.plan_real), so the other way is baked as a road of its own:

    forks.json  [{i0, i1, kinds, names, way: {n, x, z, e, chunks}}, ...]

`i0` and `i1` are knots of the main road on 128 m chunk boundaries (the game builds the road a chunk at a time), and
the way runs from the main road's knot i0 to its knot i1, a whole number of chunks long (a few per cent stretched to
make it so), sharing the main road's own line until the two parts of the road really divide. `chunks` rows are
[surface, width, class, name, limit (km/h)] like the main road's, with the name spelled out.

The functions take the baker's module as `rb` (they use its graph, smoothing and grading).
"""
import hashlib
import math

import numpy as np

import road_facts

CHUNK_KNOTS = 32
# Spacing along the road (m): the first fork, and fork to fork; how long the main road's stretch of a fork is.
FIRST_FORK = (5000.0, 10000.0)
FORK_EVERY = (8000.0, 16000.0)
MAIN_LEG = (2000.0, 10000.0)
IDEAL_LEG = 5000.0
# The other way, over the main road's stretch: not much shorter, and not so long it isn't an alternative.
RATIO = (0.8, 2.2)
MAX_TRIES = 40           # pairs of junctions tried for one fork before giving up on it for now
MAX_TURN = 0.7           # radians a way's heading may change between two knots (4 m): a 10 m bend is about 0.4
END_GAP_M = 3500.0       # no fork this close to the end (the run-out and the finish)


def _rng(seed, tag):
    return int(hashlib.sha1(("%s%d" % (tag, seed)).encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def route_nodes(steps):
    """The nodes a path goes through, in order (one more than it has steps)."""
    return [steps[0][0]] + [s[2] for s in steps]


def find_forks(rb, graph, steps, knots, shift, seed=0, first_m=None):
    """Where the route forks: [{ja, jb, i0, i1, alt}] with `alt` the other way's steps (from node ja to node jb), in
    order along the road and kept apart. `knots` are the route frame's, `shift` takes them to the graph's; the first
    fork is looked for from `first_m` metres on (by default a seeded 7 to 13 km)."""
    nodes = route_nodes(steps)
    gk = knots + np.asarray(shift)
    kn = [int(np.argmin(np.hypot(gk[:, 0] - graph.pos[n][0], gk[:, 1] - graph.pos[n][1]))) for n in nodes]
    junction = [len(graph.adj.get(n, [])) > 2 for n in nodes]
    total_m = (len(knots) - 1) * rb.STEP
    out = []
    at = first_m if first_m is not None else FIRST_FORK[0] + (FIRST_FORK[1] - FIRST_FORK[0]) * _rng(seed, "first")
    n_fork = 0
    while at + MAIN_LEG[0] < total_m - END_GAP_M:
        # The first junction from `at` on that has another way to a junction a few km on (the best of its pairs).
        cands_a = [j for j in range(len(nodes)) if junction[j] and kn[j] * rb.STEP >= at and kn[j] > 24
                   and kn[j] * rb.STEP < total_m - END_GAP_M - MAIN_LEG[0]]
        found = None
        tries = 0
        for ja in sorted(cands_a, key=lambda j: kn[j]):
            for jb in range(ja + 1, len(nodes)):
                leg = (kn[jb] - kn[ja]) * rb.STEP
                if leg > MAIN_LEG[1]:
                    break
                if leg < MAIN_LEG[0] or not junction[jb] or kn[jb] * rb.STEP > total_m - END_GAP_M:
                    continue
                tries += 1
                main_edges = {s[1] for s in steps[ja:jb]}
                main_len = sum(graph.edges[e]["length"] for e in main_edges)
                main_cost = sum(graph.weight(e) for e in main_edges)
                alt = graph.shortest(nodes[ja], nodes[jb], banned=frozenset(main_edges), max_cost=main_cost * 3.5)
                if not alt:
                    continue
                alt_len = sum(graph.edges[s[1]]["length"] for s in alt)
                if not (RATIO[0] <= alt_len / max(main_len, 1.0) <= RATIO[1]):
                    continue
                score = abs(leg - IDEAL_LEG) + 3000.0 * abs(alt_len / main_len - 1.1)
                if found is not None and score >= found[0]:
                    continue
                if _doubles_back(rb, graph, alt, knots, kn[ja], kn[jb]):
                    continue
                # Its line must be a road a bike can ride: no spike where it leaves or joins.
                trial = {"i0": (kn[ja] // CHUNK_KNOTS) * CHUNK_KNOTS, "i1": -(-kn[jb] // CHUNK_KNOTS) * CHUNK_KNOTS,
                         "ka": kn[ja], "kb": kn[jb], "alt": alt}
                if trial["i1"] >= len(knots) - 1:
                    continue
                line, _, _ = compose_way(rb, graph, trial, knots, shift, lambda s: 0)
                if sharpest_turn(line) > MAX_TURN:
                    continue
                found = (score, ja, jb, alt)
            if found is not None or tries > MAX_TRIES:
                break
        if found is None:
            at += 3000.0
            continue
        _, ja, jb, alt = found
        i0 = (kn[ja] // CHUNK_KNOTS) * CHUNK_KNOTS
        i1 = -(-kn[jb] // CHUNK_KNOTS) * CHUNK_KNOTS
        if i1 >= len(knots) - 1 or i1 - i0 < CHUNK_KNOTS or (out and i0 <= out[-1]["i1"] + CHUNK_KNOTS * 8):
            at += 3000.0
            continue
        out.append({"ja": ja, "jb": jb, "ka": kn[ja], "kb": kn[jb], "i0": i0, "i1": i1, "alt": alt})
        n_fork += 1
        at = i1 * rb.STEP + FORK_EVERY[0] + (FORK_EVERY[1] - FORK_EVERY[0]) * _rng(seed, "every%d" % n_fork)
    return out


def _chain(graph, alt):
    """The points along the other way's edges, in order."""
    pts = []
    for n0, ei, n1 in alt:
        e = graph.edges[ei]
        line = e["pts"] if e["a"] == n0 else e["pts"][::-1]
        pts += line if not pts else line[1:]
    return pts


def _doubles_back(rb, graph, alt, knots, ka, kb, reach=30.0, limit=2.1):
    """Whether the other way leaves the main road going back the way the main road came from, or arrives going back
    the way it was heading (more than `limit` radians off): a hairpin on the main road rather than a way on."""
    chain = _chain(graph, alt)
    out = np.array(rb.point_at(chain, reach)) - np.array(chain[0])
    back = np.array(chain[-1]) - np.array(rb.point_at(chain, reach, from_end=True))
    main_out = knots[min(ka + 8, len(knots) - 1)] - knots[ka]
    main_in = knots[kb] - knots[max(kb - 8, 0)]

    def angle(a, b):
        return float(math.acos(max(-1.0, min(1.0, float(np.dot(a, b)) / max(float(np.linalg.norm(a) * np.linalg.norm(b)), 1e-9)))))
    return angle(out, main_out) > limit or angle(back, main_in) > limit


def resample_count(pts, n):
    """`n` points evenly spaced along the line through `pts` (N x 2), both ends included."""
    pts = np.asarray(pts, dtype=float)
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    s = np.linspace(0.0, cum[-1], n)
    return np.stack([np.interp(s, cum, pts[:, 0]), np.interp(s, cum, pts[:, 1])], axis=1)


def pin_ends(e, first, last, decay=60.0):
    """Heights `e` shifted so they start at `first` and end at `last`, the correction dying away over `decay` knots."""
    k = np.arange(len(e), dtype=float)
    out = e + (first - e[0]) * np.exp(-k / decay) + (last - e[-1]) * np.exp(-(len(e) - 1 - k) / decay)
    out[0], out[-1] = first, last
    return out


def compose_way(rb, graph, fork, knots, shift, edge_of_main):
    """The other way's line: (points (n, 2) in the route frame, n a whole number of chunks and one; the edge each of the
    composed points came along; their cumulative lengths). It runs from the main road's knot i0, along the main road
    to the junction where the two divide, along the other way to the junction where they meet, and on along the main
    road to knot i1; smoothed like the main road and stretched a little to a whole number of chunks."""
    i0, i1, ka, kb = fork["i0"], fork["i1"], fork["ka"], fork["kb"]
    pts = [tuple(p) for p in knots[i0:ka + 1]]
    owner = [edge_of_main(k * rb.STEP) for k in range(i0, ka + 1)]
    for n0, ei, n1 in fork["alt"]:
        e = graph.edges[ei]
        line = e["pts"] if e["a"] == n0 else e["pts"][::-1]
        for p in line[1:]:
            pts.append((p[0] - shift[0], p[1] - shift[1]))
            owner.append(ei)
    for k in range(kb, i1 + 1):
        pts.append(tuple(knots[k]))
        owner.append(edge_of_main(k * rb.STEP))
    comp = np.array(pts)
    cum_comp = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(comp, axis=0).T))])
    smooth = rb.smooth_line(comp)
    if math.dist(smooth[-1], knots[i1]) > 0.25:
        smooth = np.vstack([smooth, knots[i1]])
    length = float(np.hypot(*np.diff(smooth, axis=0).T).sum())
    n_chunks = max(1, int(round(length / (rb.STEP * CHUNK_KNOTS))))
    way = resample_count(smooth, n_chunks * CHUNK_KNOTS + 1)
    way[0], way[-1] = knots[i0], knots[i1]
    return way, owner, cum_comp


def sharpest_turn(way):
    """The most the way's heading changes between two knots (radians): a hairpin or a spike is near pi."""
    hd = np.arctan2(np.diff(way[:, 0]), -np.diff(way[:, 1]))
    return float(np.abs((np.diff(hd) + np.pi) % (2 * np.pi) - np.pi).max()) if len(hd) > 1 else 0.0


def build_way(rb, graph, fork, knots, shift, elev, dem, frame, edge_of_main, region):
    """The fork's other way as a road: knots `n` (a whole number of chunks and one), their x and z in the route frame,
    heights e, and per chunk [surface, width, class, name, limit]. See the file's comment."""
    i0, i1 = fork["i0"], fork["i1"]
    way, owner, cum_comp = compose_way(rb, graph, fork, knots, shift, edge_of_main)
    n = len(way)
    lat, lon = frame.to_geo(way[:, 0], way[:, 1])
    ground = dem.heights(lat, lon)
    e = rb.grade_limit(pin_ends(rb.grade_limit(rb.smooth_heights(np.maximum(ground, 0.0))), elev[i0], elev[i1]))
    e[0], e[-1] = elev[i0], elev[i1]
    owner_arr = np.array(owner)
    scale = cum_comp[-1] / max((n - 1) * rb.STEP, 1e-9)

    def edge_of_s(s):
        i = int(np.searchsorted(cum_comp, s * scale, side="right")) - 1
        return int(owner_arr[min(max(i, 0), len(owner_arr) - 1)])
    rows = []
    for c in rb.chunk_attributes(n, edge_of_s, graph):
        limit = int(c["limit"]) if c.get("limit") else road_facts.default_limit(c["cls"], region, False)
        rows.append([c["surface"], c["width"], c["cls"], c["name"], limit])
    return {"n": n, "x": way[:, 0], "z": way[:, 1], "e": e, "chunks": rows, "length": (n - 1) * rb.STEP}


def way_kind_and_name(rows, generic):
    """("gravel" when most of the way is unpaved, else "scenic"; and the road name most of it has)."""
    gravel = sum(1 for r in rows if r[0] == "gravel")
    names = {}
    for r in rows:
        names[r[3]] = names.get(r[3], 0) + 1
    name = max(names, key=names.get) if names else generic
    return ("gravel" if gravel * 2 > len(rows) else "scenic"), name


def fork_rows(rb, forks, ways, main_chunks):
    """The forks.json rows: the main road's kind and name over the fork's stretch, and the other way's."""
    out = []
    for fk, way in zip(forks, ways):
        c0, c1 = fk["i0"] // CHUNK_KNOTS, fk["i1"] // CHUNK_KNOTS
        main_rows = [[c["surface"], c["width"], c["cls"], c["name"], 0] for c in main_chunks[c0:c1]]
        _, main_name = way_kind_and_name(main_rows, "Main road")
        kind, name = way_kind_and_name(way["chunks"], "Minor road")
        if name == main_name:
            name = name + " (the other way)"
        out.append({"i0": fk["i0"], "i1": fk["i1"], "kinds": ["main", kind], "names": {"main": main_name, kind: name},
                    "way": {"n": way["n"], "x": [round(float(v), 2) for v in way["x"]],
                            "z": [round(float(v), 2) for v in way["z"]],
                            "e": [round(float(v), 2) for v in way["e"]], "chunks": way["chunks"]}})
    return out
