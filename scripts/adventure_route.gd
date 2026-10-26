class_name AdventureRoute
extends RefCounted
## The road of an adventure ride, laid out whole along the real road the crew planned (RealPack, see
## RoutePlanner) before anyone sets off, so every player's game has the very same road: its centre
## line (a knot every STEP metres, in doubles: the route runs for a hundred kilometres and more),
## its height, width and bends, its surfaces, and the sites along it (fuel stations, stops, the
## real junctions and the forks).
##
## Forks: where the planner found a second way between two junctions of the road, the road splits
## into two ways (the main road and the other, each its own length, surfaces and bends) that meet
## again a few km on. The route is laid out along the main road at every fork (the default path),
## then each other way from the fork to the rejoin. The arrays below (px, pz, ...) are always the path as chosen so far (`choices`, the main road
## where nothing is chosen yet): choose() rebuilds them from that fork on. Nothing past a fork
## that isn't decided is ever built (see stream_end), and nothing built before one reads the road
## past it, so the road up to a fork is the same whichever way is taken. Distances (s) are along
## the path; sites are filed by where they are on the graph and get their s on the path afresh
## whenever it changes.
##
## The road is made of sections, each straight, sweeping, curvy or very curvy by how tight its bends
## are. Surfaces come a chunk (CHUNK_KNOTS knots) at a time, so a chunk is all one surface.
##
## Everything here is plain data (no nodes): the chunk builder reads it from worker threads.
## Positions are in the route frame (the start at x = z = 0, heading north, -z); AdventureWorld
## turns them into its floating local frame.

const STEP := 4.0
const CHUNK_KNOTS := 32
## How many knots either way a cross-section of the land is kept from crossing (see inside_reach).
const REACH_KNOTS := 4
## The land beside a knot runs out until it's nearer another stretch of the road than its own
## (see land_reach), then on this far (m) under or over that stretch's land, so there's no slit
## between them; never stopping that way short of this far out (the solid ground by the road
## keeps to inside_reach and other_road_near).
const LAND_OVERLAP := 30.0
const LAND_SHARE_FROM := 70.0
## The cell size (m) of the grid of every fourth knot that land_reach looks through.
const REACH_GRID := 256.0
const CHUNK_LEN := STEP * CHUNK_KNOTS
const KINDS: Array[String] = ["straight", "sweeping", "curvy", "very_curvy"]
const KIND_NAMES := {"straight": "Straight", "sweeping": "Sweeping bends", "curvy": "Curvy", "very_curvy": "Very curvy"}
## How far past another stretch of road's verge the land is kept under it (m, see _other_road_limit).
const OTHER_FLAT := 8.0
## A real road's heights are smoothed along it over this many knots (see fair_heights).
const FAIR_KNOTS := 19
## How far (m) a fuel station or stop may move along a real road to find a straight, level stretch.
const FIT_REACH := 2500.0
## How far along a real road a planned stop may move to take over a real place (m), and how far it may then move to find a
## straight, level stretch (it keeps the place's name, so not far).
const ADOPT_REACH := 3000.0
const ADOPT_FIT := 400.0
## The real places each kind of made-up stop can be (RealPack.pois kinds).
const ADOPT_ROLES := {"fuel": ["fuel"], "cafe": ["cafe", "pub"], "inn": ["inn"], "campsite": ["campsite"], "layby": ["layby"],
	"rest_area": ["layby"], "viewpoint": ["viewpoint"]}
## Road widths (kerb to kerb, metres): a wide two-lane road down to a single track.
const WIDTHS := {"two_lane": 7.4, "road": 6.0, "narrow": 4.6, "single": 3.3}
## Fuel stations: the first this far in (m), then every so often.
const FUEL_FIRST := [9000.0, 15000.0]
const FUEL_EVERY := [22000.0, 32000.0]
## Knots either side of a site that are kept straight and level.
const SITE_KNOTS := 28
## The most the road may climb by a stop (see _fit_for_stop), and how many knots it eases back onto its own heights
## either side of the level stretch through one (see _level_stops).
const STOP_GRADE := 0.05
const LEVEL_EASE := 40
## Knots more the road is levelled past SITE_KNOTS either side of a stop, so that smoothing the road after (see
## _fair_spans, whose reach is FAIR_KNOTS * 3 / 2) leaves the ground under the whole stop level (AdventureStops.GROUND_ALONG).
const LEVEL_PAD := 12
## The grid knots are filed in, to find the road near a point (m).
const GRID := 64.0
const FORK_END_GAP := 3000.0
## Knots kept straight and level either side of a fork and a rejoin: far enough that nothing
## built before the fork reads the road past it.
const JUNCTION_KNOTS := 56
## Where the signpost stands, before the fork (m).
const SIGN_BEFORE := 60.0
const WAY_LETTERS: Array[String] = ["A", "B", "C"]
## Rough average speeds for how long each way takes (km/h): by its bends, times a surface factor.
const PACE := {"straight": 90.0, "sweeping": 78.0, "curvy": 58.0, "very_curvy": 40.0}
const PACE_SURF := {"tarmac": 1.0, "gravel": 0.68, "sand": 0.5, "snow": 0.5}

## Whether roads fork at all. Off in the game (Simon took the forks out); the tests turn it on to keep the machinery
## (the ways, the votes, the signposts) working should they come back.
static var forks_on := false
var seed_value := 0
var theme := "varied"
## Metres from the start to the destination, and the whole road (with the run-out).
var length := 0.0
var total := 0.0
var px := PackedFloat64Array()
var pz := PackedFloat64Array()
var ph := PackedFloat64Array()
## Heading at each knot (radians, 0 north, + turning right) and the curvature after it (1/m, + right).
var hd := PackedFloat64Array()
var curv := PackedFloat32Array()
var width := PackedFloat32Array()
## The road's height smoothed over a few hundred metres: the lie of the land round it.
var base := PackedFloat32Array()
## How much each knot is on a bridge (RealPack.bridges): 1 out over what it crosses, easing from 0 over its first and
## last few knots (the abutments), 0 on the ground. The land under a bridge is left as it is (land_height).
var deck := PackedFloat32Array()
## Knots each end of a bridge the land eases from the road's bank to the ground under it.
const DECK_EASE := 3
## How far under the road a bridge's deck goes (m): its sides go down to here, and the land stays below it.
const BRIDGE_DEPTH := 1.1
## Each knot in a tunnel (RealPack.tunnels): 1 under the hill, 0 out under the sky. The hill is kept over it (land_height)
## and AdventureTunnels builds its tube.
var bore := PackedFloat32Array()
## How near each knot is to a tunnel's portal: 1 at it, easing to 0 TUNNEL_APPROACH knots off (and 0 in it). The land
## either side rises steeply from the road there, a cutting into the hill rather than a long bank.
var cutting := PackedFloat32Array()
const TUNNEL_APPROACH := 12
## How far a river's or lake's bed lies below its water (m), and a beck's trough below the ground at its middle, out to
## this far past its banks (m: the land's mesh is 8 m squares out from the road, so there's always some of it in there).
const WATER_DEPTH := 1.2
const STREAM_DEPTH := 0.9
const STREAM_TROUGH := 6.0
## The least rock over the road in a tunnel (m above it): the hill is raised to this where the real land is lower.
const TUNNEL_COVER := 9.0
## [{s0, s1, kind, width}] in order.
var sections: Array = []
## [{s0, s1, surface}] in order, each on chunk boundaries.
var surfaces: Array = []
## Each chunk's surface.
var chunk_surface: Array[String] = []
## On a real road, each chunk's road name and speed limit (km/h): along the path as chosen (see road_name_at).
var chunk_name: Array = []
var chunk_limit: Array = []
## [{kind, s, i, side, flat, name}] sorted by s: see add_site.
var sites: Array = []
var _grid := {}
var _reach_grid := {}
var _reach_known := {}   # knot * 2 + (side + 1) / 2 -> land_reach
var _reach_lock := Mutex.new()
## [{s, rejoin (on the default path, m), i0, i1 (their knots there), ways: [way]}]: way 0 is the
## main road (the default path's own knots), the others {kind, name, letter, n, len, px, pz, ph,
## hd, curv, width, base, sections, chunk_surface, sites (each with ls, its s along the way)};
## every way has its summary too (see _summarise).
var forks: Array = []
## fork -> the way taken there (0, the main road, wherever nothing's chosen yet), and fork -> true
## once that's decided for good.
var choices := {}
var decided := {}
## Each knot of the path's index on the default path (or the knot level with it, on another
## way), to tell another stretch of road from this one (see _other_road_limit).
var eq := PackedInt32Array()
## The default path's arrays, and its sites (each with ds, its s on that path).
var _def := {}
var _def_sites: Array = []
## The path in pieces: [{fork (-1 between forks), way, d0, d1 (default path s), p0, p1 (path s), k0 (first knot)}].
var _layout: Array = []
var _planned := false
## Every knot of every way, filed in a grid like _grid: x, z, height, half width and eq in flat arrays.
var _sgrid := {}
var _sx := PackedFloat64Array()
var _sz := PackedFloat64Array()
var _sh := PackedFloat32Array()
var _sw := PackedFloat32Array()
var _seq := PackedInt32Array()
## The sea round the region (coastal), and the snow line over the tops (alpine; INF without).
var sea := false
var snow_line := INF
## The theme's colours: {"land", "patch", "verge", "road"} -> {surface: Color} (see AdventureSurface).
var look := {}
## Where the land's colour is patched with the theme's "patch" colour (see AdventureChunk._land_color).
var patches: FastNoiseLite
## The real road this route follows (see plan_real).
var real: RealPack = null


## Lays the road out along the real road `pack` for `km` (at most the pack's own length): its line,
## heights, widths and surfaces as planned, and the land beside it from the real terrain. Fuel and
## the stops take over real places beside it where there are some, made-up ones where there aren't
## (kept to the straight, level stretches; their spacing laid out by `seed`).
func plan_real(pack: RealPack, seed: int, km: float, extra_sites: Array = []) -> void:
	real = pack
	seed_value = seed
	theme = pack.theme if AdventureTheme.has(pack.theme) else "hills"
	_theme_numbers()
	sea = pack.sea
	length = clampf(km, 1.0, maxf(pack.max_km(), 1.0)) * 1000.0
	total = length + pack.run_out_m
	var n := mini(int(ceil(total / STEP)) + 1, pack.x.size())
	total = (n - 1) * STEP
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "adventure_road", theme, pack.id])
	patches = FastNoiseLite.new()
	patches.seed = seed + 1
	patches.frequency = 1.0 / 90.0
	patches.fractal_octaves = 2
	_planned = false
	sites.clear()
	forks.clear()
	choices.clear()
	decided.clear()
	px = pack.x.slice(0, n)
	pz = pack.z.slice(0, n)
	ph = PackedFloat64Array()
	ph.resize(n)
	for i in n:
		ph[i] = pack.e[i]
	ph = fair_heights(ph)
	deck = deck_of(pack.bridges, n)
	bore = deck_of(pack.tunnels, n, 0)
	cutting = cutting_of(bore)
	hd.resize(n)
	curv.resize(n)
	for i in n - 1:
		var h := atan2(px[i + 1] - px[i], -(pz[i + 1] - pz[i]))
		if i > 0:
			h = hd[i - 1] + wrapf(h - hd[i - 1], -PI, PI)   # continuous: no jump at north
		hd[i] = h
	hd[n - 1] = hd[maxi(n - 2, 0)]
	for i in n - 1:
		curv[i] = (hd[i + 1] - hd[i]) / STEP
	curv[n - 1] = 0.0
	# Surfaces and widths from the baked chunks.
	surfaces.clear()
	chunk_surface.clear()
	var chunks := int(ceil(float(n - 1) / CHUNK_KNOTS))
	var targets := PackedFloat32Array()
	targets.resize(n)
	for c in chunks:
		var row: Array = pack.chunks[mini(c, pack.chunks.size() - 1)]
		var surf := str(row[0])
		chunk_surface.append(surf if AdventureSurface.IDS.has(surf) else "tarmac")
		var best := "road"
		for k in WIDTHS:
			if absf(float(WIDTHS[k]) - float(row[1])) < absf(float(WIDTHS[best]) - float(row[1])):
				best = k
		for k in range(c * CHUNK_KNOTS, mini(n, (c + 1) * CHUNK_KNOTS + 1)):
			targets[k] = WIDTHS[best]
	var w := targets[0]
	width.resize(n)
	for i in n:
		w = move_toward(w, targets[i], 0.05)
		width[i] = w
	var c := 0
	while c < chunks:
		var e := c
		while e < chunks and chunk_surface[e] == chunk_surface[c]:
			e += 1
		surfaces.append({"s0": c * CHUNK_LEN, "s1": e * CHUNK_LEN, "surface": chunk_surface[c]})
		c = e
	chunk_name.clear()
	chunk_limit.clear()
	for cc in chunks:
		var crow: Array = pack.chunks[mini(cc, pack.chunks.size() - 1)]
		chunk_name.append(str(pack.names[int(crow[3])]))
		chunk_limit.append(int(crow[4]) if crow.size() > 4 else 0)
	# Sections by how tight the bends are in each 256 m.
	sections.clear()
	var span := int(256.0 / STEP)
	for k0 in range(0, n - 1, span):
		var k1 := mini(n - 1, k0 + span)
		var tight := 0.0
		for k in range(k0, k1):
			tight = maxf(tight, absf(curv[k]))
		var kind := "straight"
		if tight > 1.0 / 50.0:
			kind = "very_curvy"
		elif tight > 1.0 / 160.0:
			kind = "curvy"
		elif tight > 1.0 / 400.0:
			kind = "sweeping"
		if not sections.is_empty() and sections[-1]["kind"] == kind and sections[-1]["width"] == "road":
			sections[-1]["s1"] = k1 * STEP
		else:
			sections.append({"s0": k0 * STEP, "s1": k1 * STEP, "kind": kind, "width": "road"})
	_lie_of_land()
	# The forks first (the baker found them in the road: the stops keep clear of them), then fuel and the stops, only
	# where the road is straight and level enough to pull in.
	_plan_forks_real(pack.forks)
	_plan_fuel(rng)
	AdventureStops.plan(self)
	_adopt_pois()
	_fit_stops()
	_level_stops()
	add_site("start", 48.0, 1, 0.0, "Start")
	add_site("finish", length, 1, 0.0, "Destination")
	for e in extra_sites:
		add_site(str(e.get("kind", "site")), float(e.get("s", 0.0)), int(e.get("side", 1)), float(e.get("flat", 20.0)),
			str(e.get("name", "")))
	AdventureJunctions.plan_real(self, pack.junctions)
	AdventureJunctions.widen(self)
	_plan_limit_signs()
	_stash_default()
	for f in forks.size():
		_plan_ways_real(f)
	_build_static_grid()
	_planned = true
	_assemble()
	AdventureJunctions.lay_out(self)


## A real road's heights smoothed along it, as a road is built (cut into the rises and built up over the dips), so it
## rides smoothly: three passes of a moving average FAIR_KNOTS long, much like a bell curve some 60 m across. The
## heights come from the lie of the land under the road every 4 m, and its little kinks (a grade of +15% to -12% in
## one knot at the worst, a jolt of four g at 90 km/h) threw the bike about and could throw you off. The ends stay put:
## past them it's taken as running on as it was going (the profile turned about the end).
static func fair_heights(h: PackedFloat64Array, knots := FAIR_KNOTS) -> PackedFloat64Array:
	var out := h
	for _pass in 3:
		out = _moving_average(out, knots / 2)
	return out


## The average of `h` over `k` knots either way, at each knot.
static func _moving_average(h: PackedFloat64Array, k: int) -> PackedFloat64Array:
	var n := h.size()
	var out := PackedFloat64Array()
	out.resize(n)
	if n < 3:
		return h.duplicate()
	k = mini(k, n - 1)
	# A running sum, over the heights with k more either end (each turned about its end: 2 h0 - h[j]).
	var sum := 0.0
	for j in range(-k, k + 1):
		sum += _turned(h, j)
	for i in n:
		out[i] = sum / float(2 * k + 1)
		sum += _turned(h, i + k + 1) - _turned(h, i - k)
	return out


## Height `j` of `h`, and before its start or past its end the profile turned about that end.
static func _turned(h: PackedFloat64Array, j: int) -> float:
	var n := h.size()
	if j < 0:
		return 2.0 * h[0] - h[mini(-j, n - 1)]
	if j >= n:
		return 2.0 * h[n - 1] - h[maxi(2 * (n - 1) - j, 0)]
	return h[j]


## A real fork's way's heights `hs`, smoothed as the road's are (fair_heights), with the road's own (unsmoothed) heights
## before the fork and after the rejoin either end, so it's smoothed into them as one road; then eased onto the road as
## it is at both ends, at the same height and grade, so there's no step or kink where it leaves or comes back.
func _fair_way(hs: PackedFloat64Array, i0: int, i1: int) -> PackedFloat64Array:
	var n := hs.size()
	if n < 4 or real == null:
		return hs
	var m := FAIR_KNOTS * 3
	var a := maxi(0, i0 - m)
	var b := mini(real.e.size() - 1, i1 + m)
	var ext := PackedFloat64Array()
	for i in range(a, i0):
		ext.append(real.e[i])
	ext.append_array(hs)
	for i in range(i1 + 1, b + 1):
		ext.append(real.e[i])
	var out := fair_heights(ext).slice(i0 - a, i0 - a + n)
	var last := ph.size() - 1
	var d0 := ph[i0] - out[0]
	var g0 := (ph[mini(i0 + 1, last)] - ph[i0]) - (out[1] - out[0])
	var d1 := ph[i1] - out[n - 1]
	var g1 := (ph[maxi(i1 - 1, 0)] - ph[i1]) - (out[n - 2] - out[n - 1])
	var ease := mini(m * 2, n / 2)
	for k in n:
		var j := n - 1 - k
		out[k] += (1.0 - smoothstep(0.0, ease, k)) * (d0 + g0 * k) + (1.0 - smoothstep(0.0, ease, j)) * (d1 + g1 * j)
	out[0] = ph[i0]
	out[n - 1] = ph[i1]
	return out


## The speed limit (km/h) at `s` along the path (0 where the map doesn't say).
func limit_kmh_at(s: float) -> float:
	if chunk_limit.is_empty():
		return 0.0
	return float(chunk_limit[clampi(chunk_of(s), 0, chunk_limit.size() - 1)])


## The real road's own name at `s` along the path ("" where it has none).
func road_name_at(s: float) -> String:
	if chunk_name.is_empty():
		return ""
	return str(chunk_name[clampi(chunk_of(s), 0, chunk_name.size() - 1)])


## Puts the real road's forks in (`rows` are RealPack.forks): where the baker found a second way between two junctions
## of the road, a fork with its signpost and its junction sites, as the planner makes up (_plan_forks). One that would
## crowd a site already planned, or that runs past the ride's length, is left out. The other way itself is
## built by _plan_ways_real once the default path is kept.
func _plan_forks_real(rows: Array) -> void:
	if not forks_on:
		return
	for row: Dictionary in rows:
		var i0 := int(row["i0"])
		var i1 := int(row["i1"])
		var s := i0 * STEP
		if i1 * STEP > length - FORK_END_GAP or s < 600.0 or i1 >= px.size() - 1 or _junction_clash(s, i1 * STEP):
			continue
		if not _way_meets_road(row):
			continue   # it turns off or joins at a corner, or winds round the other way: it wouldn't meet the main road
		var f := forks.size()
		forks.append({"s": s, "rejoin": i1 * STEP, "i0": i0, "i1": i1, "kinds": row["kinds"], "names": row["names"], "ways": [],
			"real": row})
		var sign := add_site("fork", s - SIGN_BEFORE, 1, 16.0, "Fork", 40)
		sign["fork"] = f
		var part := add_site("junction", s, 1, 0.0, "Fork", JUNCTION_KNOTS)
		part["fork"] = f
		var meet := add_site("junction", i1 * STEP, 1, 0.0, "Ways meet", JUNCTION_KNOTS)
		meet["rejoin"] = f


## How sharply (radians) the other way may leave the main road at a fork, and join it again: a bend a bike takes in its
## stride, not a corner turned in a knot.
const WAY_JOIN := 0.6


## Whether a planned other way leaves the main road at knot i0 and arrives at its knot i1 heading about the way the
## main road does there (not a corner, nor a turn or more different, as one that loops round would).
func _way_meets_road(row: Dictionary) -> bool:
	var wr: Dictionary = row["way"]
	var n := int(wr["n"])
	var i0 := int(row["i0"])
	var i1 := int(row["i1"])
	var prev := hd[i0]
	var first := 0.0
	var last := 0.0
	for k in n - 1:
		var sg := atan2(float(wr["x"][k + 1]) - float(wr["x"][k]), -(float(wr["z"][k + 1]) - float(wr["z"][k])))
		prev = prev + wrapf(sg - prev, -PI, PI)
		if k == 0:
			first = absf(wrapf(sg - hd[i0], -PI, PI))
		if k == n - 2:
			last = absf(wrapf(sg - hd[i1], -PI, PI))
	return absf(prev - hd[i1]) <= PI and first <= WAY_JOIN and last <= WAY_JOIN


## Plans the ways at real fork `f`: the main road (the default path's own), and the other way from the pack as a road
## of its own (its line, heights, widths, surfaces, names and limits as baked), meeting the main road at both ends.
func _plan_ways_real(f: int) -> void:
	var fk: Dictionary = forks[f]
	var i0: int = fk["i0"]
	var i1: int = fk["i1"]
	var row: Dictionary = fk["real"]
	var wr: Dictionary = row["way"]
	var n := int(wr["n"])
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var hs := PackedFloat64Array()
	xs.resize(n)
	zs.resize(n)
	hs.resize(n)
	for k in n:
		xs[k] = float(wr["x"][k])
		zs[k] = float(wr["z"][k])
		hs[k] = float(wr["e"][k])
	hs = _fair_way(hs, i0, i1)
	var whd := PackedFloat64Array()
	whd.resize(n)
	var wcv := PackedFloat32Array()
	wcv.resize(n)
	var segs := PackedFloat64Array()
	segs.resize(n - 1)
	var prev := hd[i0]
	for k in n - 1:
		var sg := atan2(xs[k + 1] - xs[k], -(zs[k + 1] - zs[k]))
		prev = prev + wrapf(sg - prev, -PI, PI)
		segs[k] = prev
	var hb := hd[i1]
	whd[0] = hd[i0]
	for k in range(1, n - 1):
		whd[k] = (segs[k - 1] + segs[k]) * 0.5
	whd[n - 1] = hb
	for k in n - 1:
		wcv[k] = (whd[k + 1] - whd[k]) / STEP
	var rows: Array = wr["chunks"]
	var cs: Array[String] = []
	var names: Array = []
	var limits: Array = []
	for r: Array in rows:
		cs.append(str(r[0]) if AdventureSurface.IDS.has(str(r[0])) else "tarmac")
		names.append(str(r[3]))
		limits.append(int(r[4]))
	var kind := str((row["kinds"] as Array)[1])
	var wbore := deck_of(wr.get("tunnels", PackedInt32Array()), n, 0)
	var way := {"kind": kind, "n": n, "px": xs, "pz": zs, "ph": hs, "hd": whd, "curv": wcv, "sites": [], "miss": 0.0,
		"rise": 0.0, "chunk_surface": cs, "chunk_name": names, "chunk_limit": limits,
		"deck": deck_of(wr.get("bridges", PackedInt32Array()), n), "bore": wbore, "cutting": cutting_of(wbore)}
	way["sections"] = _real_sections(wcv, n, rows)
	_way_widths(way, width[i0], width[i1])
	way["base"] = _leg_base(hs, [0, n - 1])
	way["name"] = str((row["names"] as Dictionary)[kind])
	var ways := [{"kind": "main", "name": str((row["names"] as Dictionary)["main"]), "n": i1 - i0 + 1, "sites": []}]
	_summarise(ways[0], _def, i0, i1)
	_summarise(way, way, 0, n - 1)
	ways.append(way)
	_finish_ways(fk, ways)


## Sections for a real way's bends: by how tight they are in each 256 m, with the road width the chunk rows give there.
func _real_sections(curvature: PackedFloat32Array, n: int, rows: Array) -> Array:
	var out := []
	var span := int(256.0 / STEP)
	for k0 in range(0, n - 1, span):
		var k1 := mini(n - 1, k0 + span)
		var tight := 0.0
		for k in range(k0, k1):
			tight = maxf(tight, absf(curvature[k]))
		var kind := "straight"
		if tight > 1.0 / 50.0:
			kind = "very_curvy"
		elif tight > 1.0 / 160.0:
			kind = "curvy"
		elif tight > 1.0 / 400.0:
			kind = "sweeping"
		var row: Array = rows[mini(k0 / CHUNK_KNOTS, rows.size() - 1)]
		var wkey := _width_key(float(row[1]))
		if not out.is_empty() and out[-1]["kind"] == kind and out[-1]["width"] == wkey:
			out[-1]["s1"] = k1 * STEP
		else:
			out.append({"s0": k0 * STEP, "s1": k1 * STEP, "kind": kind, "width": wkey})
	return out


## The planner's width class nearest `w` metres (WIDTHS).
static func _width_key(w: float) -> String:
	var best := "road"
	for k in WIDTHS:
		if absf(float(WIDTHS[k]) - w) < absf(float(WIDTHS[best]) - w):
			best = k
	return best


## Real places the planned stops take over: each fuel station, cafe, inn, campsite, lay-by and viewpoint the planner
## made up moves to the nearest real one of its sort beside the road within ADOPT_REACH (and takes its side and its
## name when it has one we can print), so the ride stops at real filling stations and cafes where the map has them
## and at made-up ones where it doesn't. Each real place is taken once.
func _adopt_pois() -> void:
	var taken := {}
	for st in sites:
		var roles: Array = ADOPT_ROLES.get(str(st["kind"]), [])
		if roles.is_empty():
			continue
		var best: Dictionary = {}
		var best_d := ADOPT_REACH
		for poi: Dictionary in real.pois:
			if not roles.has(str(poi["kind"])) or taken.has(poi):
				continue
			var d := absf(float(int(poi["k"]) * STEP) - float(st["s"]))
			if d < best_d:
				best = poi
				best_d = d
		if best.is_empty():
			continue
		taken[best] = true
		st["planned_s"] = st["s"]
		st["planned_name"] = st["name"]
		st["s"] = float(int(best["k"]) * STEP)
		st["side"] = 1 if float(best["lat"]) >= 0.0 else -1
		if str(best["name"]) != "":
			st["name"] = str(best["name"])
		st["real"] = true


## Moves the fuel stations and stops (a village with its rows) to the nearest straight, level stretch of the
## road, within FIT_REACH, and drops those with none, or that would end up within AdventureStops.CLEAR of another
## (the ones at real places are placed first, so they're the ones kept).
func _fit_stops() -> void:
	var moved := {}   # a stop's planned s -> metres it moves
	var keep := []
	var placed: Array[float] = []
	var todo := sites.filter(func(st): return str(st["kind"]) == "fuel" or AdventureStops.KINDS.has(str(st["kind"])))
	todo.sort_custom(func(a, b): return int(a.has("real")) > int(b.has("real")))
	for st in todo:
		var at := _fit_near(float(st["s"]), ADOPT_FIT if st.has("real") else FIT_REACH, placed)
		if at < 0.0 and st.has("real"):
			# No straight, level stretch by the real place: back to where it was planned, and its made-up name.
			st["s"] = st["planned_s"]
			st["name"] = st["planned_name"]
			st.erase("real")
			at = _fit_near(float(st["s"]), FIT_REACH, placed)
		if at < 0.0:
			at = _fit_near(float(st["s"]), FIT_REACH * 2.0, placed)   # (a winding, hilly road: look further)
		if at >= 0.0:
			moved[float(st["s"])] = at - float(st["s"])
			keep.append(st)
			placed.append(at)
	var out := []
	for st in sites:
		var kind := str(st["kind"])
		if kind == AdventureStops.ROW:
			var key := float(st["main_s"])
			if not moved.has(key):
				continue
			st["s"] = float(st["s"]) + float(moved[key])
		elif kind == "fuel" or AdventureStops.KINDS.has(kind):
			if not keep.has(st):
				continue
			st["s"] = float(st["s"]) + float(moved[float(st["s"])])
		else:
			out.append(st)
			continue
		st["ds"] = st["s"]
		if st.has("main_s"):
			st["main_s"] = float(st["main_s"]) + float(moved[float(st["main_s"])])
		out.append(st)
	sites = out
	sites.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))


## The s nearest `s` (within `reach`) where a stop fits, clear of the stops already `placed` there (their s), or -1.
func _fit_near(s: float, reach := FIT_REACH, placed: Array[float] = []) -> float:
	var k := 0
	while k * 40.0 <= reach:
		for sign: float in ([1.0] if k == 0 else [1.0, -1.0]):
			var at := snappedf(s + sign * k * 40.0, STEP)
			if at > 300.0 and at < length - 300.0 and _fit_for_stop(int(round(at / STEP))) and not _near_fork(at) \
					and not placed.any(func(q): return absf(q - at) < AdventureStops.CLEAR):
				return at
		k += 1
	return -1.0


## A speed-limit sign on the right verge at the start of the ride and wherever the limit changes along the default
## path, unless a site or a junction's mouth is close by (see AdventureProps.limit_sign).
func _plan_limit_signs() -> void:
	var last := 0
	for c in chunk_limit.size():
		var kmh := int(chunk_limit[c])
		if kmh <= 0 or (c > 0 and kmh == last):
			last = kmh if kmh > 0 else last
			continue
		last = kmh
		var s := float(c) * CHUNK_LEN + (60.0 if c == 0 else 24.0)
		if s > length - 300.0:
			continue
		if sites.any(func(st): return absf(float(st["s"]) - s) < 45.0):
			continue
		var sign := add_site("limit", s, 1, 0.0, "Speed limit", 0)
		sign["kmh"] = kmh


## Whether `s` is in a fork (between its signpost and 400 m past where the ways meet), where a stop would vanish when the
## crew takes the other way.
func _near_fork(s: float) -> bool:
	for fk in forks:
		if s > float(fk["s"]) - SIGN_BEFORE - 400.0 and s < float(fk["rejoin"]) + 400.0:
			return true
	return false


## Whether the real road about knot `i` is straight and level enough for a stop to go beside it.
func _fit_for_stop(i: int) -> bool:
	var a := clampi(i - 15, 0, px.size() - 1)
	var b := clampi(i + 15, 0, px.size() - 1)
	for j in range(a, b + 1):
		if (j < deck.size() and deck[j] > 0.0) or (j < cutting.size() and (bore[j] > 0.0 or cutting[j] > 0.0)):
			return false   # (not on a bridge, nor in a tunnel or its cutting)
	return absf(hd[b] - hd[a]) < deg_to_rad(8.0) and absf(ph[b] - ph[a]) < STOP_GRADE * float(b - a) * STEP


## The road levelled through every fuel station and stop (a village's rows with it), as a stop is built level: each
## stretch they keep (SITE_KNOTS and LEVEL_PAD either side, run together where they overlap) at its average height,
## eased back onto the real road's heights over LEVEL_EASE knots either side, no steeper than the planner's limit, and
## smoothed again where it was eased (_fair_spans). A stop only goes where the road climbs no more than STOP_GRADE (see
## _fit_for_stop), so the road moves a few metres at most.
func _level_stops() -> void:
	var spans := []
	for st in sites:
		var kind := str(st["kind"])
		if kind == "fuel" or kind == AdventureStops.ROW or AdventureStops.KINDS.has(kind):
			var i := int(round(float(st["s"]) / STEP))
			spans.append([maxi(0, i - SITE_KNOTS - LEVEL_PAD), mini(ph.size() - 1, i + SITE_KNOTS + LEVEL_PAD)])
	spans.sort_custom(func(p, q): return int(p[0]) < int(q[0]))
	var merged := []
	for sp: Array in spans:
		if not merged.is_empty() and int(sp[0]) <= int(merged[-1][1]):
			merged[-1][1] = maxi(int(merged[-1][1]), int(sp[1]))
		else:
			merged.append(sp.duplicate())
	var n := ph.size()
	for sp: Array in merged:
		var a: int = sp[0]
		var b: int = sp[1]
		var h := 0.0
		for k in range(a, b + 1):
			h += ph[k] / float(b - a + 1)
		for k in range(maxi(0, a - LEVEL_EASE), mini(n, b + LEVEL_EASE + 1)):
			var t := 1.0
			if k < a:
				t = smoothstep(0.0, 1.0, 1.0 - float(a - k) / LEVEL_EASE)
			elif k > b:
				t = smoothstep(0.0, 1.0, 1.0 - float(k - b) / LEVEL_EASE)
			ph[k] = lerpf(ph[k], h, t)
	if not merged.is_empty():
		ph = RoutePlanner.grade_limit(ph)   # (easing onto a steep hill could make it steeper than a road is)
		ph = _fair_spans(ph, merged)
	_lie_of_land()


## Heights `h` smoothed again (fair_heights) about the levelled stretches `spans` ([a, b] knots): easing onto a level
## stretch, then holding to the planner's grade limit, leaves kinks (a crest of 0.025 /m by a layby, a jolt of a g and
## a half at 90 km/h). The smoothed road is taken over each level stretch, LEVEL_EASE either side and a smoothing's
## reach past that (FAIR_KNOTS * 3 / 2: all but that reach in from the level stretch's ends stays exactly level), then
## eased back into the road as it was over LEVEL_EASE more knots. The rest of the road is untouched, and the road is
## no steeper anywhere (an average of grades is no steeper than the steepest of them).
static func _fair_spans(h: PackedFloat64Array, spans: Array) -> PackedFloat64Array:
	var n := h.size()
	var fair := fair_heights(h)
	var keep := PackedFloat64Array()
	keep.resize(n)
	var pad := LEVEL_EASE + FAIR_KNOTS * 3 / 2
	for sp: Array in spans:
		var a := int(sp[0]) - pad
		var b := int(sp[1]) + pad
		for k in range(maxi(0, a - LEVEL_EASE), mini(n, b + LEVEL_EASE + 1)):
			var t := 1.0
			if k < a:
				t = smoothstep(0.0, 1.0, 1.0 - float(a - k) / LEVEL_EASE)
			elif k > b:
				t = smoothstep(0.0, 1.0, 1.0 - float(k - b) / LEVEL_EASE)
			keep[k] = maxf(keep[k], t)
	var out := h.duplicate()
	for k in n:
		if keep[k] > 0.0:
			out[k] = lerpf(h[k], fair[k], keep[k])
	return out


## The lie of the land: the road's height averaged over 200 m either way.
func _lie_of_land() -> void:
	var n := ph.size()
	base.resize(n)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	for i in n:
		sums[i + 1] = sums[i] + ph[i]
	for i in n:
		var a := maxi(0, i - 50)
		var b := mini(n, i + 51)
		base[i] = (sums[b] - sums[a]) / float(b - a)

## Marks a site (a fuel station, a town, a stop, a fork) at `s` metres on `side` (1 the right,
## -1 the left): the land there is kept flat at the road's height `flat` metres out past the
## verge. On a road with forks `s` is along the path as chosen so far, and the
## site stays on that stretch of road (on a way that isn't taken it's off the path: not in sites).
func add_site(kind: String, s: float, side := 1, flat := 30.0, site_name := "", keep := SITE_KNOTS) -> Dictionary:
	var site := {"kind": kind, "s": s, "i": clampi(int(round(s / STEP)), 0, maxi(0, px.size() - 1)), "side": signi(side) if side != 0 else 1,
		"flat": flat, "name": site_name, "keep": keep}
	if not _planned:
		site["ds"] = s
		sites.append(site)
		sites.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
		return site
	var piece := _piece_at(s)
	if int(piece["fork"]) >= 0 and int(piece["way"]) > 0:
		site["ls"] = s - float(piece["p0"])
		forks[int(piece["fork"])]["ways"][int(piece["way"])]["sites"].append(site)
	else:
		site["ds"] = float(piece["d0"]) + s - float(piece["p0"])
		_def_sites.append(site)
	_assemble_sites()
	return site


## The sites of `kind` ("" for all).
func sites_of(kind: String) -> Array:
	return sites.filter(func(st): return kind == "" or st["kind"] == kind)


func knot_count() -> int:
	return px.size()


func chunk_count() -> int:
	return int(ceil(float(px.size() - 1) / CHUNK_KNOTS))


static func chunk_of(s: float) -> int:
	return int(floor(s / CHUNK_LEN))


func surface_at_s(s: float) -> String:
	var c := clampi(chunk_of(s), 0, chunk_surface.size() - 1)
	return chunk_surface[c] if c >= 0 else "tarmac"


func kind_at_s(s: float) -> String:
	for sec in sections:
		if s < float(sec["s1"]):
			return str(sec["kind"])
	return "straight" if sections.is_empty() else str(sections[-1]["kind"])


func width_at_s(s: float) -> float:
	return width[clampi(int(round(s / STEP)), 0, width.size() - 1)]


func height_at_s(s: float) -> float:
	var f := clampf(s / STEP, 0.0, float(ph.size() - 1))
	var i := mini(int(f), ph.size() - 2)
	return lerpf(ph[i], ph[i + 1], f - i)


## The heading at `s` (radians from north, + to the right).
func heading_at_s(s: float) -> float:
	var f := clampf(s / STEP, 0.0, float(hd.size() - 1))
	var i := mini(int(f), hd.size() - 2)
	return lerpf(hd[i], hd[i + 1], f - i)


## The route frame's x and z at `s` and `lat` metres to the right, as doubles.
func xz_at(s: float, lat := 0.0) -> PackedFloat64Array:
	var f := clampf(s / STEP, 0.0, float(px.size() - 1))
	var i := mini(int(f), px.size() - 2)
	var t := f - i
	var h := heading_at_s(s)
	return PackedFloat64Array([lerpf(px[i], px[i + 1], t) + cos(h) * lat, lerpf(pz[i], pz[i + 1], t) + sin(h) * lat])


## The road's grade at `s` (rise per metre).
func grade_at_s(s: float) -> float:
	var i := clampi(int(s / STEP), 0, ph.size() - 2)
	return (ph[i + 1] - ph[i]) / STEP


## The nearest point of the road to route-frame (x, z): {i (knot before it), s, lat (+ right of
## the centre line), d (distance off the centre line)}. `hint` (a knot index) searches round it
## first; -1 or a miss falls back to the grid. Empty when there's no road within 600 m. Never past a fork still open:
## there's no road there yet (and a tour that ends where it began, on the road it set off along, would otherwise
## find a bike stood at the start at the end).
func locate(x: float, z: float, hint := -1) -> Dictionary:
	var best := -1
	var best_d := INF
	var end := stream_end()
	var n := px.size() if end == INF else mini(px.size(), int(end / STEP) + 2)
	if hint >= 0:
		for i in range(maxi(0, hint - 80), mini(n, hint + 80)):
			var d := (px[i] - x) * (px[i] - x) + (pz[i] - z) * (pz[i] - z)
			if d < best_d:
				best_d = d
				best = i
	if best < 0 or best_d > 40.0 * 40.0:
		var cx := int(floor(x / GRID))
		var cz := int(floor(z / GRID))
		for r in range(0, 10):
			var found := false
			for gz in range(cz - r, cz + r + 1):
				for gx in range(cx - r, cx + r + 1):
					if maxi(absi(gx - cx), absi(gz - cz)) != r:
						continue
					for i in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
						if i >= n:
							continue
						var d := (px[i] - x) * (px[i] - x) + (pz[i] - z) * (pz[i] - z)
						if d < best_d:
							best_d = d
							best = i
							found = true
			if found and r >= 1 and sqrt(best_d) < float(r) * GRID:
				break
	if best < 0:
		return {}
	# Onto the segment either side of the nearest knot.
	var out := {}
	var best_seg := INF
	for i in [best - 1, best]:
		if i < 0 or i >= px.size() - 1:
			continue
		var ax := px[i]
		var az := pz[i]
		var dx := px[i + 1] - ax
		var dz := pz[i + 1] - az
		var t := clampf(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0.0, 1.0)
		var qx := ax + dx * t
		var qz := az + dz * t
		var d := sqrt((x - qx) * (x - qx) + (z - qz) * (z - qz))
		if d < best_seg:
			best_seg = d
			var h := lerpf(hd[i], hd[i + 1], t)
			var lat := (x - qx) * cos(h) + (z - qz) * sin(h)
			out = {"i": i, "s": (float(i) + t) * STEP, "lat": lat, "d": d}
	if out.is_empty() or float(out["d"]) > 600.0:
		return {}
	return out


# ---------------------------------------------------------------------------- the land

## Each of `n` knots' deck weight (see deck) from bridges [first knot, last knot, ...], eased over `ease_knots` at each
## end (0 for none: a tunnel's bore).
static func deck_of(bridges: PackedInt32Array, n: int, ease_knots := DECK_EASE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for k in range(0, bridges.size() - 1, 2):
		var i0 := bridges[k]
		var i1 := mini(bridges[k + 1], n - 1)
		var ease := mini(ease_knots, (i1 - i0) / 2)
		for i in range(i0, i1 + 1):
			var w := 1.0 if ease <= 0 else clampf(float(mini(i - i0, i1 - i)) / ease, 0.0, 1.0)
			out[i] = maxf(out[i], w)
	return out


## Each knot's cutting weight (see cutting) from its `bore`.
static func cutting_of(bores: PackedFloat32Array) -> PackedFloat32Array:
	var n := bores.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if bores[i] <= 0.0 or (i > 0 and bores[i - 1] > 0.0 and i < n - 1 and bores[i + 1] > 0.0):
			continue
		# A portal: the knots out from it, either way that's under the sky.
		for d in range(1, TUNNEL_APPROACH + 1):
			for j: int in [i - d, i + d]:
				if j >= 0 and j < n and bores[j] <= 0.0:
					out[j] = maxf(out[j], 1.0 - float(d - 1) / TUNNEL_APPROACH)
	return out


## Whether knot `i` is in a tunnel.
func in_tunnel(i: int) -> bool:
	return i >= 0 and i < bore.size() and bore[i] > 0.0


## The tunnel knot `i` is in, as its first and last knots along the path (Vector2i(-1, -1) when it's in none).
func tunnel_span(i: int) -> Vector2i:
	if not in_tunnel(i):
		return Vector2i(-1, -1)
	var a := i
	var b := i
	while a > 0 and bore[a - 1] > 0.0:
		a -= 1
	while b < bore.size() - 1 and bore[b + 1] > 0.0:
		b += 1
	return Vector2i(a, b)


## The height of the land at route-frame (x, z) beside knot `i`, `lat` metres off the centre line
## (+ right): the road's own height on the road and verge, easing out to the real land, kept below
## any other stretch of the road close by so the land never covers a bend that doubles back; over
## a tunnel the hill, at least TUNNEL_COVER over the road.
func land_height(i: int, lat: float, x: float, z: float) -> float:
	i = clampi(i, 0, ph.size() - 1)
	if in_tunnel(i):
		return _hill_height(i, lat, x, z)
	var w := deck[i] if i < deck.size() else 0.0
	if w > 0.0:
		# On a bridge: the land under it and round it as it is, below the deck, eased in from the bank at its ends.
		var bank := _bank_height(i, lat, x, z)
		var under := minf(natural_height(i, x, z, absf(lat)), ph[i] - BRIDGE_DEPTH - 0.4)
		return lerpf(bank, minf(under, _other_road_limit(i, x, z, absf(lat))), w)
	return _bank_height(i, lat, x, z)


## land_height without a bridge: the road's own height on the road and verge, then the bank out to the land.
func _bank_height(i: int, lat: float, x: float, z: float) -> float:
	var e := width[i] * 0.5
	var a := absf(lat)
	var road_h := ph[i]
	if a <= e + 0.9:
		return road_h - (0.05 if a > e else 0.0)
	var nat := natural_height(i, x, z, a)
	var flat := _site_flat(i, signf(lat))
	# Cut into the hill or built up over the dip: the steeper the difference, the further out the
	# bank runs (no sheer walls).
	var widen := clampf(absf(nat - road_h) * 0.9, 0.0, 60.0)
	var t := smoothstep(e + 1.5 + flat, e + 14.0 + flat * 1.4 + widen, a)
	var cut := cutting[i] if i < cutting.size() else 0.0
	if cut > 0.0:
		# Up to a tunnel's portal: the hill comes steeply down to the road's edge, a cutting.
		t = lerpf(t, smoothstep(e + 1.2, e + 5.0, a), cut)
	var h := lerpf(road_h - 0.12, nat, t)
	return minf(h, _other_road_limit(i, x, z, a))


## The land over a tunnel at knot `i`: the real hill, but never less than TUNNEL_COVER over the road from the road's
## edge out a few metres (over the tube), easing down onto the real land further out.
func _hill_height(i: int, lat: float, x: float, z: float) -> float:
	var e := width[i] * 0.5
	var a := absf(lat)
	var nat := natural_height(i, x, z, a)
	var top := ph[i] + TUNNEL_COVER
	var h := maxf(nat, lerpf(top, nat, smoothstep(e + 4.0, e + 30.0, a)))
	# (another stretch of the road nearby keeps it down, but never into the tube)
	return maxf(minf(h, _other_road_limit(i, x, z, a)), top if a < e + 4.0 else -INF)


## What covers the ground at route-frame (x, z) ("forest", "crop", "urban", ... see RealPack.COVER),
## or "" beyond the land the pack holds.
func cover_at(x: float, z: float) -> String:
	var id := real.terrain.cover(x, z)
	return RealPack.COVER[id] if id >= 0 and id < RealPack.COVER.size() else ""


## The lie of the land at (x, z), `a` metres from the road beside knot `i`: the real terrain's (ground_at), or
## the road's own lie of the land beyond what the pack holds.
func natural_height(i: int, x: float, z: float, _a := 0.0) -> float:
	var rh := ground_at(x, z)
	return base[i] if is_nan(rh) else rh


## The real ground at (x, z), NAN beyond what the pack holds: under a river or a lake (RealPack.WATER cover) its bed,
## WATER_DEPTH below the water (the heights are the water's surface there), and by a beck (RealPack.streams) a trough
## STREAM_DEPTH deep at its middle line, out to STREAM_TROUGH past its banks, so the water lies in it (RealLand draws it).
func ground_at(x: float, z: float) -> float:
	var rh := real.terrain.height(x, z)
	if is_nan(rh):
		return rh
	if real.terrain.cover(x, z) == RealPack.WATER:
		return rh - WATER_DEPTH
	var near := real.stream_at(x, z)
	if near.x < near.y + STREAM_TROUGH:
		rh -= STREAM_DEPTH * (1.0 - smoothstep(near.y, near.y + STREAM_TROUGH, near.x))
	return rh


## Keeps the land under the road where another stretch of it (a bend that doubles back, more
## than SITE_KNOTS... 160 m along) passes close by: at most that road's height just under its
## verge and on out a few metres (OTHER_FLAT: the land's triangles are wide out there, and one
## reaching over the road from either side mustn't stand up through it), rising gently away from
## it. Every way at every fork counts, taken or not, so the land comes out the same whichever is
## chosen (see eq). A stretch nearer than 160 m along counts too where the land at (x, z), `a` m
## out from its own knot, is much nearer it than its own centre line (which only a stretch that has
## come back round can be): the other leg of a hairpin, or the next in a stack of them or of a
## switchback (a real road's are often only 90 to 120 m apart along the road and 20 m apart
## across), whose land otherwise stood up through this road by as much as ten metres.
func _other_road_limit(i: int, x: float, z: float, a := 0.0) -> float:
	var limit := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	var e := eq[i] if i < eq.size() else i
	var m := a * 0.8 - 1.0
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				var near := absi(_seq[j] - e) < 40
				if near and m <= 0.0:
					continue
				var d2 := (_sx[j] - x) * (_sx[j] - x) + (_sz[j] - z) * (_sz[j] - z)
				if near and d2 > m * m:
					continue
				var d := sqrt(d2)
				var reach := _sw[j] + 2.0
				if d < reach + 40.0:
					limit = minf(limit, _sh[j] - 0.35 + maxf(0.0, d - reach - OTHER_FLAT) * 0.7)
	return limit


## How much further than usual the land stays flat beside knot `i` on `side`, for a site there
## (`junctions` false: leaving out the junctions, whose flat ground is the scenery's to stand on).
func _site_flat(i: int, side: float, junctions := true) -> float:
	var out := 0.0
	# The sites are in order along the road: from the first that could be near, found by halves.
	var j := sites.bsearch_custom(i - SITE_KNOTS, func(st, v): return int(st["i"]) < int(v))
	while j < sites.size() and int(sites[j]["i"]) < i + SITE_KNOTS:
		var st: Dictionary = sites[j]
		j += 1
		var k := absi(int(st["i"]) - i)
		if not junctions and st["kind"] == AdventureJunctions.KIND:
			continue
		if k < SITE_KNOTS and (float(st["side"]) == side or st.get("both", false)):
			out = maxf(out, float(st["flat"]) * (1.0 - smoothstep(SITE_KNOTS * 0.5, SITE_KNOTS, k)))
	return out


## The distance from route-frame (x, z) to the nearest centre line of any way, less its half
## width (negative on the road), looking only at knots filed near it.
func clearance(x: float, z: float) -> float:
	var best := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				var d := sqrt((_sx[j] - x) * (_sx[j] - x) + (_sz[j] - z) * (_sz[j] - z)) - _sw[j]
				best = minf(best, d)
	return best


## How far the land may reach out on `side` (1 right, -1 left) of knot `i` before its cross-
## section would run into one of the next few knots' (REACH_KNOTS either way: on the inside of a
## bend they close in on its middle, and land past that folds over itself): a little short of
## where it would first cross one. INF where none does. (It used to stop short of the tightest
## bend within 200 m, so beside a winding road whole stretches of the countryside were missing
## and you could see through them to the far ground.)
func inside_reach(i: int, side: int) -> float:
	var out := INF
	var dix := cos(hd[i]) * side
	var diz := sin(hd[i]) * side
	for j in range(maxi(0, i - REACH_KNOTS), mini(hd.size(), i + REACH_KNOTS + 1)):
		if j == i:
			continue
		var djx := cos(hd[j]) * side
		var djz := sin(hd[j]) * side
		var cross := dix * djz - diz * djx
		if absf(cross) < 1e-6:
			continue
		var wx := px[j] - px[i]
		var wz := pz[j] - pz[i]
		var t := (wx * djz - wz * djx) / cross   # out along this knot's cross-section
		var u := (wx * diz - wz * dix) / cross   # and along the other's
		if t > 0.0 and u > 0.0:
			out = minf(out, t * 0.85)
	return out


## How far the land runs out on `side` of knot `i`: as far as inside_reach lets it, and only
## to about where it's nearer another stretch of the road than this one (each stretch has the
## land on its own side of the line halfway between them, overlapping a little), so the land
## of two stretches never lies in two sheets at different heights, one floating over the other.
## Stretches past the first undecided fork don't count (they may never be built).
## Worked out once a knot (chunks are built on worker threads, so the cache is locked).
func land_reach(i: int, side: int) -> float:
	var key := i * 2 + (side + 1) / 2
	_reach_lock.lock()
	var known = _reach_known.get(key)
	_reach_lock.unlock()
	if known != null:
		return known
	var out := inside_reach(i, side)
	var dx := cos(hd[i]) * side
	var dz := sin(hd[i]) * side
	var end := stream_end()
	var cx := int(floor(px[i] / REACH_GRID))
	var cz := int(floor(pz[i] / REACH_GRID))
	var rings := int(ceil(2.0 * float(AdventureChunk.LAND_OUT[-1]) / REACH_GRID))
	for ring in rings + 1:
		# Ring by ring outwards: a knot further off than twice the reach so far can't be nearer.
		if (ring - 1) * REACH_GRID > 2.0 * out:
			break
		for gz in range(cz - ring, cz + ring + 1):
			var edge := gz == cz - ring or gz == cz + ring
			for gx in (range(cx - ring, cx + ring + 1) if edge else [cx - ring, cx + ring]):
				for j in _reach_grid.get(Vector2i(gx, gz), PackedInt32Array()):
					if absi(j - i) <= 40 or j * STEP >= end:
						continue
					var wx := px[j] - px[i]
					var wz := pz[j] - pz[i]
					var ahead := wx * dx + wz * dz
					if ahead <= 0.0:
						continue
					# Out along the cross-section, where it's as near knot j as its own road.
					var t := (wx * wx + wz * wz) / (2.0 * ahead)
					out = minf(out, maxf(t + LAND_OVERLAP, LAND_SHARE_FROM))
	_reach_lock.lock()
	_reach_known[key] = out
	_reach_lock.unlock()
	return out


## Whether another stretch of the road (a bend doubling back, not the road beside knot `i`) runs
## within `r` metres of route-frame (x, z), `a` metres out from knot `i`. A stretch near along the
## road (the other leg of a hairpin or a switchback) counts too where it's much nearer (x, z) than
## knot `i` is (as in _other_road_limit): a row of land run out across it had a triangle from just
## past it to 70 m out, up the hillside, reaching back over it (a bump of up to two metres on the
## road, enough to throw the bike up at 90 km/h).
func other_road_near(i: int, x: float, z: float, r: float, a := 0.0) -> bool:
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	var e := eq[i] if i < eq.size() else i
	var m := minf(r, a * 0.8 - 1.0)
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				var d2 := (_sx[j] - x) * (_sx[j] - x) + (_sz[j] - z) * (_sz[j] - z)
				if absi(_seq[j] - e) >= 40:
					if d2 < r * r:
						return true
				elif m > 0.0 and d2 < m * m:
					return true
	return false


## The curvature at knot `i` smoothed over `span` knots either side.
func smooth_curv(i: int, span := 8) -> float:
	var sum := 0.0
	var cnt := 0
	for j in range(maxi(0, i - span), mini(curv.size(), i + span + 1)):
		sum += curv[j]
		cnt += 1
	return sum / maxf(cnt, 1)


# ---------------------------------------------------------------------------- planning

## Reads the look of the theme's land (AdventureTheme.DATA), varied's where it has none.
func _theme_numbers() -> void:
	sea = bool(AdventureTheme.get_value(theme, "sea", false))
	snow_line = INF
	look = {}
	for table in [["land", AdventureSurface.LAND_COLOR], ["patch", AdventureSurface.LAND_PATCH],
			["verge", AdventureSurface.VERGE_COLOR], ["road", AdventureSurface.ROAD_COLOR]]:
		var d := {}
		for surf in AdventureSurface.IDS:
			d[surf] = AdventureTheme.color(theme, table[0], surf, table[1][surf])
		look[table[0]] = d


func _plan_fuel(rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(FUEL_FIRST[0], FUEL_FIRST[1])
	if length < FUEL_FIRST[1] + 3000.0:
		s = length * 0.5
	while s < length - 3000.0 or (sites_of("fuel").is_empty() and s < length):
		add_site("fuel", snappedf(s, STEP), 1, 30.0, "Fuel")
		s += rng.randf_range(FUEL_EVERY[0], FUEL_EVERY[1])


func _build_grid() -> void:
	var cells := {}
	for i in px.size():
		var key := Vector2i(int(floor(px[i] / GRID)), int(floor(pz[i] / GRID)))
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		var arr: PackedInt32Array = cells[key]
		arr.append(i)
		cells[key] = arr
	_grid = cells
	# Every fourth knot again in big cells, for how far out the land reaches (see land_reach).
	var coarse := {}
	for i in range(0, px.size(), 4):
		var key := Vector2i(int(floor(px[i] / REACH_GRID)), int(floor(pz[i] / REACH_GRID)))
		if not coarse.has(key):
			coarse[key] = PackedInt32Array()
		var arr: PackedInt32Array = coarse[key]
		arr.append(i)
		coarse[key] = arr
	_reach_grid = coarse
	_reach_lock.lock()
	_reach_known = {}
	_reach_lock.unlock()


# ---------------------------------------------------------------------------- forks

func _junction_clash(a: float, b: float) -> bool:
	for st in sites:
		if st["kind"] != "start" and (absf(float(st["s"]) - a) < 600.0 or absf(float(st["s"]) - b) < 600.0):
			return true
	return false


## Keeps the default path (the main road at every fork) to build any path from, with its lie of
## the land worked out a stretch between junctions at a time, so the land up to a fork never
## depends on the road past it.
func _stash_default() -> void:
	var cuts := [0]
	for fk in forks:
		cuts.append_array([int(fk["i0"]), int(fk["i1"])])
	cuts.append(px.size() - 1)
	base = _leg_base(ph, cuts)
	_def = {"px": px.duplicate(), "pz": pz.duplicate(), "ph": ph.duplicate(), "hd": hd.duplicate(), "curv": curv.duplicate(),
		"width": width.duplicate(), "base": base.duplicate(), "deck": deck.duplicate(), "bore": bore.duplicate(),
		"cutting": cutting.duplicate(), "sections": sections.duplicate(true),
		"chunk_surface": chunk_surface.duplicate(), "chunk_name": chunk_name.duplicate(), "chunk_limit": chunk_limit.duplicate(),
		"total": total, "n": px.size()}
	_def_sites = sites.duplicate()
	for st in _def_sites:
		if st.has("main_s"):
			st["main_off"] = float(st["main_s"]) - float(st["s"])   # a village row's middle, kept with it


## The lie of the land along heights `h`: averaged over 200 m either way, but never across a cut
## (each stretch between cuts on its own; a cut knot goes with the stretch before it).
static func _leg_base(h: PackedFloat64Array, cuts: Array) -> PackedFloat32Array:
	var n := h.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	for i in n:
		sums[i + 1] = sums[i] + h[i]
	for k in range(cuts.size() - 1):
		var a: int = cuts[k]
		var b: int = cuts[k + 1]
		for i in range(a if k == 0 else a + 1, b + 1):
			var lo := maxi(a, i - 50)
			var hi := mini(b, i + 50) + 1
			out[i] = (sums[hi] - sums[lo]) / float(hi - lo)
	return out


## Gives a fork's ways their letters and which way each points off at the fork (by how it bears 700 m on).
func _finish_ways(fk: Dictionary, ways: Array) -> void:
	var order := range(ways.size())
	order.sort_custom(func(p, q): return float(ways[p]["bear"]) < float(ways[q]["bear"]))
	var arrows := ["<", ">"] if ways.size() == 2 else ["<", "^", ">"]
	for k in order.size():
		ways[order[k]]["arrow"] = arrows[k]
	for w in ways.size():
		ways[w]["letter"] = WAY_LETTERS[w]
	fk["ways"] = ways


## A way's widths by its sections, eased from the road's at the fork and onto it at the rejoin.
func _way_widths(way: Dictionary, w0: float, w1: float) -> void:
	var n: int = way["n"]
	var out := PackedFloat32Array()
	out.resize(n)
	var w := w0
	for k in n:
		var aim := w0
		for sec in way["sections"]:
			if k * STEP >= float(sec["s0"]) and k * STEP < float(sec["s1"]):
				aim = WIDTHS[str(sec["width"])]
		w = move_toward(w, aim, 0.05)
		out[k] = lerpf(w, w1, smoothstep(float(n - 81), float(n - 1), float(k)))
	out[n - 1] = w1
	way["width"] = out


static func _kind_in(secs: Array, s: float) -> String:
	for sec in secs:
		if s < float(sec["s1"]):
			return str(sec["kind"])
	return "straight" if secs.is_empty() else str(secs[-1]["kind"])


## What the satnav, signpost and map say about a way: its length (len), how long it takes about
## (time, s), metres of each surface (surfaces) and kind of bends (kinds), the climbing (climb, m),
## its high point over the fork (top, m), how twisty it is (twist, degrees of turning a km), how
## it bears off at the fork (bear, radians) and the box round it. From arrays `a` (a way's own,
## or _def), knots k0..k1.
func _summarise(way: Dictionary, a: Dictionary, k0: int, k1: int) -> void:
	var surfs := {}
	var kinds := {}
	var secs := 0.0
	var climb := 0.0
	var turn := 0.0
	var top := 0.0
	var aph: PackedFloat64Array = a["ph"]
	var acv: PackedFloat32Array = a["curv"]
	var apx: PackedFloat64Array = a["px"]
	var apz: PackedFloat64Array = a["pz"]
	var cs: Array = a["chunk_surface"]
	var box := Rect2(apx[k0], apz[k0], 0.0, 0.0)
	for k in range(k0, k1):
		var sf := str(cs[clampi(k / CHUNK_KNOTS, 0, cs.size() - 1)])
		var kd := _kind_in(a["sections"], k * STEP)
		surfs[sf] = float(surfs.get(sf, 0.0)) + STEP
		kinds[kd] = float(kinds.get(kd, 0.0)) + STEP
		secs += STEP / (float(PACE.get(kd, 70.0)) * float(PACE_SURF.get(sf, 0.7)) / 3.6)
		climb += maxf(0.0, aph[k + 1] - aph[k])
		turn += absf(acv[k]) * STEP
		top = maxf(top, aph[k] - aph[k0])
		box = box.expand(Vector2(apx[k], apz[k]))
	var len_m := (k1 - k0) * STEP
	var kb := mini(k0 + 175, k1)
	var bear := atan2(apx[kb] - apx[k0], -(apz[kb] - apz[k0])) - float(a["hd"][k0])
	way["len"] = len_m
	way["time"] = secs
	way["surfaces"] = surfs
	way["kinds"] = kinds
	way["climb"] = climb
	way["top"] = top
	way["twist"] = rad_to_deg(turn) / maxf(len_m / 1000.0, 0.1)
	way["bear"] = wrapf(bear, -PI, PI)
	way["box"] = box.grow(60.0)


## Files every knot of every way (taken or not) in the static grid: the land and scenery keep
## clear of all of them, the same whichever way the crew goes.
func _build_static_grid() -> void:
	_sgrid = {}
	_sx = PackedFloat64Array()
	_sz = PackedFloat64Array()
	_sh = PackedFloat32Array()
	_sw = PackedFloat32Array()
	_seq = PackedInt32Array()
	var d: Dictionary = _def
	var dpx: PackedFloat64Array = d["px"]
	var dpz: PackedFloat64Array = d["pz"]
	var dph: PackedFloat64Array = d["ph"]
	var dw: PackedFloat32Array = d["width"]
	for j in int(d["n"]):
		_file_knot(dpx[j], dpz[j], dph[j], dw[j] * 0.5, j)
	for fk in forks:
		for w in range(1, fk["ways"].size()):
			var way: Dictionary = fk["ways"][w]
			var wpx: PackedFloat64Array = way["px"]
			var wpz: PackedFloat64Array = way["pz"]
			var wph: PackedFloat64Array = way["ph"]
			var ww: PackedFloat32Array = way["width"]
			for k in range(1, int(way["n"]) - 1):
				_file_knot(wpx[k], wpz[k], wph[k], ww[k] * 0.5, _way_eq(fk, way, k))
	for key in _sgrid:
		_sgrid[key] = PackedInt32Array(_sgrid[key])


func _file_knot(x: float, z: float, h: float, hw: float, e: int) -> void:
	var key := Vector2i(int(floor(x / GRID)), int(floor(z / GRID)))
	if not _sgrid.has(key):
		_sgrid[key] = []
	(_sgrid[key] as Array).append(_sx.size())
	_sx.append(x)
	_sz.append(z)
	_sh.append(h)
	_sw.append(hw)
	_seq.append(e)


## The default path's knot level with knot `k` of another way: counted on from the fork for its
## first half, back from the rejoin for the rest.
static func _way_eq(fk: Dictionary, way: Dictionary, k: int) -> int:
	var n: int = way["n"]
	return int(fk["i0"]) + k if k < (n - 1) / 2 else int(fk["i1"]) - (n - 1 - k)


# ---------------------------------------------------------------------------- the path as chosen

## Builds the path's arrays from the default path and the ways chosen (choices): the road between
## forks as planned, and at each fork the way taken. Its sites get their places along it.
func _assemble() -> void:
	_assemble_path()
	_assemble_sites()


## A copy of this route holding only what putting its path together reads (the default path,
## the forks' ways), with the ways picked at forks `picks` ({fork: way}): its
## _assemble_path can run on a worker thread while this route is still ridden and built on (it
## takes a tenth of a second and more on a long road: on the main thread that was a hitch for
## everyone at once, as the crew's pick reached them all together). Then hand it to take_path.
func path_copy(picks: Dictionary) -> AdventureRoute:
	var r := AdventureRoute.new()
	r._def = _def
	r.forks = forks
	r.choices = choices.duplicate()
	for f in picks:
		if int(f) >= 0 and int(f) < forks.size():
			r.choices[int(f)] = clampi(int(picks[f]), 0, forks[int(f)]["ways"].size() - 1)
	return r


## Takes the path a path_copy put together (on the main thread, with nothing building on the route
## meanwhile): its ways are decided for good, and the sites go to their places along it.
func take_path(r: AdventureRoute, picks: Dictionary) -> void:
	for f in picks:
		if int(f) >= 0 and int(f) < forks.size():
			choices[int(f)] = int(r.choices[int(f)])
			decided[int(f)] = true
	px = r.px
	pz = r.pz
	ph = r.ph
	hd = r.hd
	curv = r.curv
	width = r.width
	base = r.base
	deck = r.deck
	bore = r.bore
	cutting = r.cutting
	eq = r.eq
	sections = r.sections
	chunk_surface = r.chunk_surface
	chunk_name = r.chunk_name
	chunk_limit = r.chunk_limit
	_layout = r._layout
	total = r.total
	surfaces = r.surfaces
	_grid = r._grid
	_reach_grid = r._reach_grid
	_reach_lock.lock()
	_reach_known = {}   # the road past the fork counts now (see land_reach)
	_reach_lock.unlock()
	_assemble_sites()


## The path's arrays, its pieces and surfaces, and its grids (see _assemble).
func _assemble_path() -> void:
	var d: Dictionary = _def
	px = PackedFloat64Array()
	pz = PackedFloat64Array()
	ph = PackedFloat64Array()
	hd = PackedFloat64Array()
	curv = PackedFloat32Array()
	width = PackedFloat32Array()
	base = PackedFloat32Array()
	deck = PackedFloat32Array()
	bore = PackedFloat32Array()
	cutting = PackedFloat32Array()
	eq = PackedInt32Array()
	sections = []
	chunk_surface = []
	chunk_name = []
	chunk_limit = []
	_layout = []
	_take_def(0, 0)
	var at := 0
	for f in forks.size():
		var fk: Dictionary = forks[f]
		var i0: int = fk["i0"]
		var i1: int = fk["i1"]
		var t0 := (px.size() - 1) * STEP
		_take_def(at + 1, i0)
		_layout.append({"fork": -1, "way": 0, "d0": at * STEP, "d1": i0 * STEP, "p0": t0, "p1": (px.size() - 1) * STEP})
		var w := clampi(int(choices.get(f, 0)), 0, fk["ways"].size() - 1)
		var p0 := (px.size() - 1) * STEP
		if w == 0:
			_take_def(i0 + 1, i1)
		else:
			var way: Dictionary = fk["ways"][w]
			var n: int = way["n"]
			px.append_array((way["px"] as PackedFloat64Array).slice(1, n))
			pz.append_array((way["pz"] as PackedFloat64Array).slice(1, n))
			ph.append_array((way["ph"] as PackedFloat64Array).slice(1, n))
			hd.append_array((way["hd"] as PackedFloat64Array).slice(1, n))
			curv.append_array((way["curv"] as PackedFloat32Array).slice(1, n))
			width.append_array((way["width"] as PackedFloat32Array).slice(1, n))
			base.append_array((way["base"] as PackedFloat32Array).slice(1, n))
			deck.append_array((way["deck"] as PackedFloat32Array).slice(1, n))
			bore.append_array((way["bore"] as PackedFloat32Array).slice(1, n))
			cutting.append_array((way["cutting"] as PackedFloat32Array).slice(1, n))
			for k in range(1, n):
				eq.append(_way_eq(fk, way, k))
			for sec in way["sections"]:
				sections.append({"s0": p0 + float(sec["s0"]), "s1": p0 + float(sec["s1"]), "kind": sec["kind"], "width": sec["width"]})
			chunk_surface.append_array(way["chunk_surface"])
			if way.has("chunk_name"):
				chunk_name.append_array(way["chunk_name"])
				chunk_limit.append_array(way["chunk_limit"])
		_layout.append({"fork": f, "way": w, "d0": i0 * STEP, "d1": i1 * STEP, "p0": p0, "p1": (px.size() - 1) * STEP})
		at = i1
	var last := int(d["n"]) - 1
	var t1 := (px.size() - 1) * STEP
	_take_def(at + 1, last)
	_layout.append({"fork": -1, "way": 0, "d0": at * STEP, "d1": last * STEP, "p0": t1, "p1": (px.size() - 1) * STEP})
	total = float(d["total"]) + (px.size() - int(d["n"])) * STEP
	surfaces = []
	var c := 0
	while c < chunk_surface.size():
		var e := c
		while e < chunk_surface.size() and chunk_surface[e] == chunk_surface[c]:
			e += 1
		surfaces.append({"s0": c * CHUNK_LEN, "s1": e * CHUNK_LEN, "surface": chunk_surface[c]})
		c = e
	_build_grid()


## Appends the default path's knots a..b (inclusive), with their sections and the surfaces of
## the chunks they finish.
func _take_def(a: int, b: int) -> void:
	if b < a:
		return
	var d: Dictionary = _def
	var shift := (px.size() - a) * STEP   # path s less default s from here on
	px.append_array((d["px"] as PackedFloat64Array).slice(a, b + 1))
	pz.append_array((d["pz"] as PackedFloat64Array).slice(a, b + 1))
	ph.append_array((d["ph"] as PackedFloat64Array).slice(a, b + 1))
	hd.append_array((d["hd"] as PackedFloat64Array).slice(a, b + 1))
	curv.append_array((d["curv"] as PackedFloat32Array).slice(a, b + 1))
	width.append_array((d["width"] as PackedFloat32Array).slice(a, b + 1))
	base.append_array((d["base"] as PackedFloat32Array).slice(a, b + 1))
	for key in ["deck", "bore", "cutting"]:
		var arr: PackedFloat32Array = get(key)
		arr.append_array((d.get(key, PackedFloat32Array()) as PackedFloat32Array).slice(a, b + 1))
		set(key, arr)
	for j in range(a, b + 1):
		eq.append(j)
	var s0 := maxi(a - 1, 0) * STEP
	var s1 := b * STEP
	for sec in d["sections"]:
		if float(sec["s1"]) > s0 and float(sec["s0"]) < s1:
			sections.append({"s0": maxf(float(sec["s0"]), s0) + shift, "s1": minf(float(sec["s1"]), s1) + shift, "kind": sec["kind"], "width": sec["width"]})
	var cs: Array = d["chunk_surface"]
	var cn: Array = d.get("chunk_name", [])
	var cl: Array = d.get("chunk_limit", [])
	for ci in range(maxi(a - 1, 0) / CHUNK_KNOTS, mini(int(ceil(float(b) / CHUNK_KNOTS)), cs.size())):
		chunk_surface.append(cs[ci])
		if ci < cn.size():
			chunk_name.append(cn[ci])
			chunk_limit.append(cl[ci])


## Puts every site on the path at its place along it (sites), and the destination's distance (length).
func _assemble_sites() -> void:
	sites = []
	for piece in _layout:
		var f: int = piece["fork"]
		var d0: float = piece["d0"]
		var d1: float = piece["d1"]
		var p0: float = piece["p0"]
		if f >= 0 and int(piece["way"]) > 0:
			for st in forks[f]["ways"][int(piece["way"])]["sites"]:
				st["s"] = p0 + float(st["ls"])
				sites.append(st)
			continue
		for st in _def_sites:
			var ds := float(st["ds"])
			if (ds >= d0 and ds <= d1) if f < 0 else (ds > d0 and ds < d1):
				st["s"] = p0 + ds - d0
				sites.append(st)
	for st in sites:
		st["i"] = clampi(int(round(float(st["s"]) / STEP)), 0, px.size() - 1)
		if st.has("main_off"):
			st["main_s"] = float(st["s"]) + float(st["main_off"])
	sites.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
	for st in sites:
		if st["kind"] == "finish":
			length = float(st["s"])


func _piece_at(s: float) -> Dictionary:
	for piece in _layout:
		if s <= float(piece["p1"]):
			return piece
	return _layout[-1]


## Takes way `way` at fork `f`, for good: the path is rebuilt along it from there on (true when
## that changed it). Whoever holds chunks past the fork drops them (see AdventureWorld.apply_picks).
func choose(f: int, way: int) -> bool:
	if f < 0 or f >= forks.size():
		return false
	way = clampi(way, 0, forks[f]["ways"].size() - 1)
	var changed := int(choices.get(f, 0)) != way
	choices[f] = way
	decided[f] = true
	_reach_lock.lock()
	_reach_known = {}   # the road past the fork counts now (see land_reach)
	_reach_lock.unlock()
	if changed:
		_assemble()
	return changed


## How far along the path fork `f` is (the junction where its ways part), and where they meet again.
func fork_s(f: int) -> float:
	for piece in _layout:
		if int(piece["fork"]) == f:
			return float(piece["p0"])
	return INF


func rejoin_s(f: int) -> float:
	for piece in _layout:
		if int(piece["fork"]) == f:
			return float(piece["p1"])
	return INF


## The first fork at or ahead of `s` (its junction no more than a few metres behind), or -1.
func next_fork(s: float) -> int:
	for f in forks.size():
		if fork_s(f) > s - 5.0:
			return f
	return -1


## The fork whose ways `s` is on (between the junction and the rejoin), or -1.
func fork_at(s: float) -> int:
	for f in forks.size():
		if s > fork_s(f) and s < rejoin_s(f):
			return f
	return -1


## How far the road can be built: up to the first fork that isn't decided (INF once all are).
func stream_end() -> float:
	for f in forks.size():
		if not decided.has(f):
			return fork_s(f)
	return INF


func way_of(f: int, w: int) -> Dictionary:
	if f < 0 or f >= forks.size() or w < 0 or w >= forks[f]["ways"].size():
		return {}
	return forks[f]["ways"][w]


## Whether way `w` at fork `f` is the one on the path now.
func on_path(f: int, w: int) -> bool:
	return int(choices.get(f, 0)) == w


# ---------------------------------------------------------------------------- the whole graph

## Way `w` at fork `f`: [x, z, first knot, last knot, chunk surfaces] (way 0 out of the default path).
func _way_xz(f: int, w: int) -> Array:
	if w == 0:
		return [_def["px"], _def["pz"], int(forks[f]["i0"]), int(forks[f]["i1"]), _def["chunk_surface"]]
	var way: Dictionary = forks[f]["ways"][w]
	return [way["px"], way["pz"], 0, int(way["n"]) - 1, way["chunk_surface"]]


## The whole route graph for a map, a chunk at a time: [{pts (route frame x z, every `every`
## knots), surface, fork (-1 between forks), way, on (on the path as chosen)}].
func map_lines(every := 8) -> Array:
	var out := []
	var d: Dictionary = _def
	var bounds := [0]
	for fk in forks:
		bounds.append_array([int(fk["i0"]), int(fk["i1"])])
	bounds.append(int(d["n"]) - 1)
	for k in range(bounds.size() - 1):
		var f := -1 if k % 2 == 0 else k / 2
		_lines_of(out, d["px"], d["pz"], d["chunk_surface"], bounds[k], bounds[k + 1], every, f, 0, f < 0 or on_path(f, 0))
	for f in forks.size():
		for w in range(1, forks[f]["ways"].size()):
			var way: Dictionary = forks[f]["ways"][w]
			_lines_of(out, way["px"], way["pz"], way["chunk_surface"], 0, int(way["n"]) - 1, every, f, w, on_path(f, w))
	return out


static func _lines_of(out: Array, xs: PackedFloat64Array, zs: PackedFloat64Array, cs: Array, a: int, b: int, every: int,
		f: int, w: int, on: bool) -> void:
	var k := a
	while k < b:
		var e := mini(b, (k / CHUNK_KNOTS + 1) * CHUNK_KNOTS)
		var pts := PackedVector2Array()
		var j := k
		while j < e:
			pts.append(Vector2(xs[j], zs[j]))
			j += every
		pts.append(Vector2(xs[e], zs[e]))
		var ci := clampi((k - a) / CHUNK_KNOTS if w > 0 else k / CHUNK_KNOTS, 0, cs.size() - 1)
		out.append({"pts": pts, "surface": cs[ci], "fork": f, "way": w, "on": on})
		k = e


## Every site on the graph, taken or not: [{site, x, z (route frame), on (on the path), fork, way}].
func map_sites() -> Array:
	var out := []
	var d: Dictionary = _def
	for st in _def_sites:
		var j := clampi(int(round(float(st["ds"]) / STEP)), 0, int(d["n"]) - 1)
		var f := -1
		for k in forks.size():
			if j > int(forks[k]["i0"]) and j < int(forks[k]["i1"]):
				f = k
		out.append({"site": st, "x": d["px"][j], "z": d["pz"][j], "on": f < 0 or on_path(f, 0), "fork": f, "way": 0})
	for f in forks.size():
		for w in range(1, forks[f]["ways"].size()):
			var way: Dictionary = forks[f]["ways"][w]
			for st in way["sites"]:
				var k := clampi(int(round(float(st["ls"]) / STEP)), 0, int(way["n"]) - 1)
				out.append({"site": st, "x": way["px"][k], "z": way["pz"][k], "on": on_path(f, w), "fork": f, "way": w})
	return out


## The ways off the path within `r` of route-frame (x, z), for the satnav to show the roads off
## at a fork: [{xs, zs (route frame), surface}], every `every` knots.
func ways_near(x: float, z: float, r: float, every := 2) -> Array:
	var out := []
	var view := Rect2(x - r, z - r, r * 2.0, r * 2.0)
	for f in forks.size():
		for w in forks[f]["ways"].size():
			if on_path(f, w) or not (forks[f]["ways"][w]["box"] as Rect2).intersects(view):
				continue
			var src := _way_xz(f, w)
			var xs: PackedFloat64Array = src[0]
			var zs: PackedFloat64Array = src[1]
			var rx := PackedFloat64Array()
			var rz := PackedFloat64Array()
			for k in range(int(src[2]), int(src[3]) + 1, every):
				if absf(xs[k] - x) < r and absf(zs[k] - z) < r:
					rx.append(xs[k])
					rz.append(zs[k])
				else:
					if rx.size() > 1:
						out.append({"xs": rx, "zs": rz, "surface": src[4][0]})
					rx = PackedFloat64Array()
					rz = PackedFloat64Array()
			if rx.size() > 1:
				out.append({"xs": rx, "zs": rz, "surface": src[4][0]})
	return out
