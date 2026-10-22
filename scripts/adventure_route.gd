class_name AdventureRoute
extends RefCounted
## The road of an adventure ride, planned whole from its seed and length before anyone sets
## off, so every player's game has the very same road: its centre line (a knot every STEP
## metres, in doubles: the route runs for a hundred kilometres and more), its height, width and
## bends, its surfaces, and the sites along it (fuel stations, stops, and the forks).
##
## Forks: every 20 to 30 km the road splits into two or three ways (the main road, a scenic pass,
## a gravel track: each its own length, surfaces and bends) that meet again a few km on. The
## route is planned along the main road at every fork (the default path, the old single road),
## then each other way is planned from the fork to the rejoin, steered there on its own seed.
## The arrays below (px, pz, ...) are always the path as chosen so far (`choices`, the main road
## where nothing is chosen yet): choose() rebuilds them from that fork on. Nothing past a fork
## that isn't decided is ever built (see stream_end), and nothing built before one reads the road
## past it, so the road up to a fork is the same whichever way is taken. Distances (s) are along
## the path; sites are filed by where they are on the graph and get their s on the path afresh
## whenever it changes.
##
## The road is made of sections, each straight, sweeping, curvy or very curvy, a run of bends
## of that kind (clothoid in and out); the heading never strays past MAX_HEADING from the way
## the route set off, so it always makes progress and never crosses itself. The height follows
## climbs and descents with smooth changes of grade. Surfaces come in long stretches, each
## starting on a chunk boundary (CHUNK_KNOTS knots) so a chunk is all one surface.
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
const MAX_HEADING := deg_to_rad(80.0)
## Road beyond the destination, so the finish isn't the edge of the world.
const RUN_OUT := 480.0
const KINDS: Array[String] = ["straight", "sweeping", "curvy", "very_curvy"]
const KIND_NAMES := {"straight": "Straight", "sweeping": "Sweeping bends", "curvy": "Curvy", "very_curvy": "Very curvy",
	"switchback": "Switchback hairpins"}
## The grade (rise per metre) is steered towards what the stretch wants by at most this much a
## knot on a long climb, and PITCH_RATE on a short steep pitch, a crest or a dip (a vertical
## curve of 1.6 km: light over the top at speed, never airborne); and never past MAX_GRADE.
const GRADE_RATE := 0.0012
const PITCH_RATE := 0.0025
const MAX_GRADE := 0.155
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
## How long a short steep pitch lasts (m, at its steepest), and the rollers' waves: their length
## (m) and the steepest each may be (no tighter than a 1.2 km curve over the crest).
const PITCH_LEN := [70.0, 300.0]
const ROLL_WAVE := [260.0, 560.0]
const ROLL_R := 1200.0
## A stack of switchback hairpins (a theme's "switchbacks"): legs this long (m) across the
## mountainside at this heading off the way on (degrees either side), hairpins of this radius
## (m), climbing (or dropping) at this grade; the turns onto the first leg and off the last.
const SB_LEG := [90.0, 190.0]
const SB_HEADING := [70.0, 77.0]
const SB_RADIUS := [12.0, 17.0]
const SB_GRADE := [0.075, 0.1]
const SB_TURN_R := 70.0
## Tunnels (a theme's "tunnels"): kept this gentle (1/m of bend at most) and level-ish (grade),
## clear of any other stretch of road by this far (m), with this much rock over the roof at the
## portals (m above the road), the hill over it rising this much a metre in from them.
const TUNNEL_BEND := 1.0 / 240.0
const TUNNEL_GRADE := 0.04
const TUNNEL_CLEAR := 110.0
const TUNNEL_COVER := 9.0
const TUNNEL_RISE := 0.5
## Knots either side of a tunnel whose land climbs to its portals (the cutting), and either side
## of a switchback stack whose land eases onto its mountainside.
const TUNNEL_APPROACH := 25
const SLOPE_MARGIN := 50
## Road widths (kerb to kerb, metres): a wide two-lane road down to a single track.
const WIDTHS := {"two_lane": 7.4, "road": 6.0, "narrow": 4.6, "single": 3.3}
## The bends of each kind of section: radius (m), arc (degrees), clothoid length in and out (m),
## the straight between bends (m), and how long a section of it runs (m).
const BENDS := {
	"straight": {"r": [1800.0, 4000.0], "arc": [3.0, 10.0], "t": [60.0, 120.0], "gap": [150.0, 500.0], "len": [400.0, 1300.0]},
	"sweeping": {"r": [220.0, 600.0], "arc": [15.0, 50.0], "t": [40.0, 80.0], "gap": [0.0, 160.0], "len": [800.0, 2000.0]},
	"curvy": {"r": [70.0, 160.0], "arc": [30.0, 95.0], "t": [20.0, 40.0], "gap": [0.0, 70.0], "len": [600.0, 1600.0]},
	"very_curvy": {"r": [24.0, 55.0], "arc": [60.0, 150.0], "t": [12.0, 24.0], "gap": [0.0, 35.0], "len": [400.0, 1200.0]},
}
## How the "varied" theme mixes things.
const KIND_WEIGHTS := {"straight": 0.2, "sweeping": 0.3, "curvy": 0.3, "very_curvy": 0.2}
## The surfaces drawn in turn from a shuffled bag (so each gets its share), and how long a
## stretch of one lasts (m).
const SURFACE_BAG: Array[String] = ["tarmac", "tarmac", "tarmac", "gravel", "gravel", "sand", "snow"]
const SURFACE_LEN := [1500.0, 4200.0]
## Fuel stations: the first this far in (m), then every so often.
const FUEL_FIRST := [9000.0, 15000.0]
const FUEL_EVERY := [22000.0, 32000.0]
## Knots either side of a site that are kept straight and level.
const SITE_KNOTS := 28
## The grid knots are filed in, to find the road near a point (m).
const GRID := 64.0
## Forks: the first this far in (m), then one every so often along the main road; the main road
## through one runs this long before the ways meet again, at least FORK_END_GAP before the end.
const FORK_FIRST := [14000.0, 22000.0]
const FORK_EVERY := [20000.0, 30000.0]
const FORK_MAIN := [5000.0, 9000.0]
const FORK_END_GAP := 3000.0
## Knots kept straight and level either side of a fork and a rejoin: far enough that nothing
## built before the fork reads the road past it.
const JUNCTION_KNOTS := 56
## Where the signpost stands, before the fork (m).
const SIGN_BEFORE := 60.0
const WAY_LETTERS: Array[String] = ["A", "B", "C"]
## How each other kind of way is planned: its bends, how far off the line from fork to rejoin it
## swings (of that distance, to one side), how far its heading may stray from the way to where
## it's making for (radians), and its widths.
const WAY_PLANS := {
	"scenic": {"kinds": {"sweeping": 0.15, "curvy": 0.45, "very_curvy": 0.4}, "off": 0.3, "stray": 1.15,
		"widths": {"road": 0.15, "narrow": 0.55, "single": 0.3}},
	"gravel": {"kinds": {"straight": 0.35, "sweeping": 0.4, "curvy": 0.25}, "off": 0.04, "stray": 0.55,
		"widths": {"road": 0.15, "narrow": 0.5, "single": 0.35}},
}
const PASS_NAMES: Array[String] = ["Hollow", "Raven", "Kestrel", "Windy Gap", "Black Crag", "Eagle", "High Moor", "Stag", "Falcon", "Cloud"]
const TRACK_NAMES: Array[String] = ["Quarry", "Forest", "Drovers'", "Old Mine", "Shepherds'", "Ridge", "Peat", "Miners'", "Fell", "Long Lane"]
## Rough average speeds for how long each way takes (km/h): by its bends, times a surface factor.
const PACE := {"straight": 90.0, "sweeping": 78.0, "curvy": 58.0, "very_curvy": 40.0, "switchback": 30.0}
const PACE_SURF := {"tarmac": 1.0, "gravel": 0.68, "sand": 0.5, "snow": 0.5}
## Where the land under a coastal sea levels out (m; the sea itself is AdventureTheme.SEA_Y).
const SEA_BED := AdventureTheme.SEA_Y - 7.0

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
## Per knot of the default path: 1 where it's in or by a hairpin (see _other_road_limit).
var _hairpin := PackedByteArray()
var _noise: FastNoiseLite
var _noise_fine: FastNoiseLite
var _noise_far: FastNoiseLite
## The theme's planning numbers (see AdventureTheme), read once in plan().
var _kinds: Dictionary = KIND_WEIGHTS
var _bends := {}
var _heights := {"h0": 140.0, "lo": 50.0, "hi": 950.0, "steep": 1.0, "up": 0.5}
var _hills := 1.0
var _lift := 1.0
## The sea off to the left (coastal), and the snow line over the tops (alpine; INF without).
var sea := false
var snow_line := INF
## The theme's colours: {"land", "patch", "verge", "road"} -> {surface: Color} (see AdventureSurface).
var look := {}
## Tunnels, on the default path: [{k0, k1 (its first and last knots), id}] in order; and those on
## the path as chosen now, [{s0, s1, id}] (see _assemble).
var tunnels: Array = []
var tunnels_on: Array = []
## The mountainsides the switchback stacks climb: [{k0, k1 (default path knots), cx, cz, a, b, c}],
## each a plane through the hairpins (height a + b (x - cx) + c (z - cz)) the land lies along.
var slopes: Array = []
## Each knot of the path's tunnel (an index into tunnels) and mountainside (into slopes, for knots
## on or near a stack), or -1.
var tun_k := PackedInt32Array()
var slope_k := PackedInt32Array()
## The theme's relief: {pitch: [odds, steepest from, to (%)], rollers: [odds, grade from, to (%)],
## switchbacks: [odds, legs from, to], tunnels: [first (m), every from, to (m), long from, to (m)]}.
var _relief := {}
## The real road this route follows, or null for a made-up one (see plan_real).
var real: RealPack = null


## Plans the whole road for `seed` and `km`. `extra_sites` ([{kind, s, side, flat}]) are kept
## straight and level like the fuel stations, for whatever is to be built there.
func plan(seed: int, km: float, theme_name := "varied", extra_sites: Array = []) -> void:
	seed_value = seed
	theme = theme_name if AdventureTheme.has(theme_name) else "varied"
	_theme_numbers()
	length = clampf(km, 1.0, 1000.0) * 1000.0
	total = length + RUN_OUT
	var n := int(ceil(total / STEP)) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "adventure_road", theme])
	_make_noise(seed)
	_planned = false
	sites.clear()
	forks.clear()
	choices.clear()
	decided.clear()
	_plan_fuel(rng)
	AdventureStops.plan(self)
	add_site("start", 48.0, 1, 0.0, "Start")
	add_site("finish", length, 1, 0.0, "Destination")
	for e in extra_sites:
		add_site(str(e.get("kind", "site")), float(e.get("s", 0.0)), int(e.get("side", 1)), float(e.get("flat", 20.0)),
			str(e.get("name", "")))
	_plan_forks()
	AdventureJunctions.plan(self)
	_plan_surfaces(rng, n)
	_plan_bends(rng, n)
	AdventureJunctions.widen(self)
	_integrate(n)
	_plan_tunnels(n)
	_plan_heights(rng, n)
	_integrate(n)
	_plan_slopes(n)
	_snow_over_tops()
	_stash_default()
	for f in forks.size():
		_plan_ways(f)
	_build_static_grid()
	_planned = true
	_assemble()
	AdventureJunctions.lay_out(self)


## Plans the road along the real road `pack` for `km` (at most the pack's own length): its line,
## heights, widths and surfaces as baked, and the land beside it from the real terrain. Fuel and
## the stops are still made up (and kept to the straight, level stretches); there are no forks,
## junctions, tunnels or switchback slopes on a real road.
func plan_real(pack: RealPack, seed: int, km: float, extra_sites: Array = []) -> void:
	real = pack
	seed_value = seed
	theme = pack.theme if AdventureTheme.has(pack.theme) else "hills"
	_theme_numbers()
	sea = pack.sea
	length = clampf(km, 1.0, maxf(pack.max_km(), 1.0)) * 1000.0
	total = length + RUN_OUT
	var n := mini(int(ceil(total / STEP)) + 1, pack.x.size())
	total = (n - 1) * STEP
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "adventure_road", theme, pack.id])
	_make_noise(seed)
	_planned = false
	sites.clear()
	forks.clear()
	choices.clear()
	decided.clear()
	tunnels = []
	slopes = []
	px = pack.x.slice(0, n)
	pz = pack.z.slice(0, n)
	ph = PackedFloat64Array()
	ph.resize(n)
	for i in n:
		ph[i] = pack.e[i]
	ph = fair_heights(ph)
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
	# The lie of the land: the road's height over 200 m either way.
	base.resize(n)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	for i in n:
		sums[i + 1] = sums[i] + ph[i]
	for i in n:
		var a := maxi(0, i - 50)
		var b := mini(n, i + 51)
		base[i] = (sums[b] - sums[a]) / float(b - a)
	tun_k = PackedInt32Array()
	tun_k.resize(n)
	tun_k.fill(-1)
	slope_k = PackedInt32Array()
	slope_k.resize(n)
	slope_k.fill(-1)
	# The forks first (the baker found them in the road: the stops keep clear of them), then fuel and the stops, only
	# where the road is straight and level enough to pull in.
	_plan_forks_real(pack.forks)
	_plan_fuel(rng)
	AdventureStops.plan(self)
	_adopt_pois()
	_fit_stops()
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


## The speed limit (km/h) at `s` along the path on a real road, 0 on a made-up one.
func limit_kmh_at(s: float) -> float:
	if chunk_limit.is_empty():
		return 0.0
	return float(chunk_limit[clampi(chunk_of(s), 0, chunk_limit.size() - 1)])


## The real road's own name at `s` along the path ("" on a made-up road).
func road_name_at(s: float) -> String:
	if chunk_name.is_empty():
		return ""
	return str(chunk_name[clampi(chunk_of(s), 0, chunk_name.size() - 1)])


## Puts the real road's forks in (`rows` are RealPack.forks): where the baker found a second way between two junctions
## of the road, a fork with its signpost and its junction sites, as the planner makes up (_plan_forks). One that would
## crowd a site already planned, or that runs past the ride's length, is left out. The other way itself is
## built by _plan_ways_real once the default path is kept.
func _plan_forks_real(rows: Array) -> void:
	for row: Dictionary in rows:
		var i0 := int(row["i0"])
		var i1 := int(row["i1"])
		var s := i0 * STEP
		if i1 * STEP > length - FORK_END_GAP or s < 600.0 or i1 >= px.size() - 1 or _junction_clash(s, i1 * STEP):
			continue
		if not _way_meets_road(row):
			continue   # it winds round the other way: its heading wouldn't meet the main road's
		var f := forks.size()
		forks.append({"s": s, "rejoin": i1 * STEP, "i0": i0, "i1": i1, "kinds": row["kinds"], "names": row["names"], "ways": [],
			"real": row})
		var sign := add_site("fork", s - SIGN_BEFORE, 1, 16.0, "Fork", 40)
		sign["fork"] = f
		var part := add_site("junction", s, 1, 0.0, "Fork", JUNCTION_KNOTS)
		part["fork"] = f
		var meet := add_site("junction", i1 * STEP, 1, 0.0, "Ways meet", JUNCTION_KNOTS)
		meet["rejoin"] = f


## Whether a baked other way arrives at the main road's knot i1 heading the way the main road does (not a turn or
## more different, as one that loops round would).
func _way_meets_road(row: Dictionary) -> bool:
	var wr: Dictionary = row["way"]
	var n := int(wr["n"])
	var prev := hd[int(row["i0"])]
	for k in n - 1:
		var sg := atan2(float(wr["x"][k + 1]) - float(wr["x"][k]), -(float(wr["z"][k + 1]) - float(wr["z"][k])))
		prev = prev + wrapf(sg - prev, -PI, PI)
	return absf(prev - hd[int(row["i1"])]) <= PI


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
	var way := {"kind": kind, "n": n, "px": xs, "pz": zs, "ph": hs, "hd": whd, "curv": wcv, "sites": [], "miss": 0.0,
		"rise": 0.0, "chunk_surface": cs, "chunk_name": names, "chunk_limit": limits}
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
## real road, within FIT_REACH, and drops those with none.
func _fit_stops() -> void:
	var moved := {}   # a stop's planned s -> metres it moves
	var keep := []
	for st in sites:
		var kind := str(st["kind"])
		if kind == AdventureStops.ROW or not (kind == "fuel" or AdventureStops.KINDS.has(kind)):
			continue
		var at := _fit_near(float(st["s"]), ADOPT_FIT if st.has("real") else FIT_REACH)
		if at < 0.0 and st.has("real"):
			# No straight, level stretch by the real place: back to where it was planned, and its made-up name.
			st["s"] = st["planned_s"]
			st["name"] = st["planned_name"]
			st.erase("real")
			at = _fit_near(float(st["s"]))
		if at >= 0.0:
			moved[float(st["s"])] = at - float(st["s"])
			keep.append(st)
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


## The s nearest `s` (within `reach`) where a stop fits, or -1.
func _fit_near(s: float, reach := FIT_REACH) -> float:
	var k := 0
	while k * 40.0 <= reach:
		for sign: float in ([1.0] if k == 0 else [1.0, -1.0]):
			var at := snappedf(s + sign * k * 40.0, STEP)
			if at > 300.0 and at < length - 300.0 and _fit_for_stop(int(round(at / STEP))) and not _near_fork(at):
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
	return absf(hd[b] - hd[a]) < deg_to_rad(8.0) and absf(ph[b] - ph[a]) < 0.05 * float(b - a) * STEP

## Marks a site (a fuel station, a town, a stop, a fork) at `s` metres on `side` (1 the right,
## -1 the left): the land there is kept flat at the road's height `flat` metres out past the
## verge. Sites planned with the road (plan's extra_sites) also get a straight, level stretch,
## `keep` knots either side. On a planned route `s` is along the path as chosen so far, and the
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
## first; -1 or a miss falls back to the grid. Empty when there's no road within 600 m.
func locate(x: float, z: float, hint := -1) -> Dictionary:
	var best := -1
	var best_d := INF
	if hint >= 0:
		for i in range(maxi(0, hint - 80), mini(px.size(), hint + 80)):
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

## The height of the land at route-frame (x, z) beside knot `i`, `lat` metres off the centre line
## (+ right): the road's own height on the road and verge, easing out to the lie of the land
## (with its hills, and mountains far off), kept below any other stretch of the road close by so
## the land never covers a bend that doubles back.
func land_height(i: int, lat: float, x: float, z: float) -> float:
	i = clampi(i, 0, ph.size() - 1)
	var e := width[i] * 0.5
	var a := absf(lat)
	var road_h := ph[i]
	var tn := tun_k[i] if i < tun_k.size() else -1
	if tn >= 0 and a >= e - 0.01 and in_tunnel(i):
		# The hill over the tunnel, right from the road's edge (the tube's under it).
		return maxf(natural_height(i, x, z, a), road_h + TUNNEL_COVER)
	if a <= e + 0.9:
		return road_h - (0.05 if a > e else 0.0)
	var nat := natural_height(i, x, z, a)
	var flat := _site_flat(i, signf(lat))
	# Cut into the hill or built up over the dip: the steeper the difference, the further out the
	# bank runs (no sheer walls), but steep rock right up to a tunnel's portals.
	var widen := clampf(absf(nat - road_h) * 0.9, 0.0, 60.0)
	var t := smoothstep(e + 1.5 + flat, e + 14.0 + flat * 1.4 + widen, a)
	if tn >= 0:
		var t1 := tunnels[tn] as Dictionary
		var e_i := eq[i] if i < eq.size() else i
		var d_out := float(maxi(int(t1["k0"]) - e_i, e_i - int(t1["k1"]))) * STEP
		t = lerpf(smoothstep(e + 1.2, e + 5.0, a), t, smoothstep(10.0, float(TUNNEL_APPROACH) * STEP, d_out))
	var h := lerpf(road_h - 0.12, nat, t)
	if sea and lat < 0.0 and real == null:
		h = _coast(h, a, e + flat, x, z)
	return minf(h, _other_road_limit(i, x, z, a))


## The land on the sea side of a coastal road, `a` metres out (the verge and any site's flat
## ground ending at `inner`): it runs on a way, then drops to the sea, steeply off a cliff or
## gently down a beach (noise picks which, and where), and on under the water.
func _coast(h: float, a: float, inner: float, x: float, z: float) -> float:
	var n1 := _noise_far.get_noise_2d(x * 2.3, z * 2.3) * 0.5 + 0.5
	var n2 := _noise.get_noise_2d(x * 1.7 + 900.0, z * 1.7) * 0.5 + 0.5
	var a0 := inner + 26.0 + n1 * 70.0
	var w := lerpf(14.0, 150.0, smoothstep(0.35, 0.7, n2))   # a cliff, or a long beach
	return lerpf(h, SEA_BED, smoothstep(a0, a0 + w, a))


## What covers the ground at route-frame (x, z) on a real road ("forest", "crop", "urban", ... see
## RealPack.COVER), or "" on a made-up one or beyond the baked land.
func cover_at(x: float, z: float) -> String:
	if real == null:
		return ""
	var id := real.terrain.cover(x, z)
	return RealPack.COVER[id] if id >= 0 and id < RealPack.COVER.size() else ""


## The lie of the land at (x, z), `a` metres from the road beside knot `i`.
func natural_height(i: int, x: float, z: float, a: float) -> float:
	if real != null:
		var rh := real.terrain.height(x, z)
		return base[i] if is_nan(rh) else rh
	var surf := surface_at_s(i * STEP)
	var hills := ({"tarmac": 22.0, "gravel": 34.0, "sand": 18.0, "snow": 55.0}.get(surf, 25.0) as float) * _hills
	var h := base[i] + _noise.get_noise_2d(x, z) * hills + _noise_fine.get_noise_2d(x, z) * 2.5
	if surf == "sand":
		h += absf(_noise_fine.get_noise_2d(x * 0.35, z * 0.9)) * 6.0   # dunes
	# Higher ground rising away from the road for the skyline, mountains in the snow.
	var far := smoothstep(70.0, 420.0, a)
	var lift := ({"snow": 160.0, "gravel": 90.0}.get(surf, 55.0) as float) * _lift
	var rise := far * lift * (0.45 + 0.55 * (_noise_far.get_noise_2d(x, z) * 0.5 + 0.5))
	h += rise
	var e := eq[i] if i < eq.size() else i
	var sk := slope_k[i] if i < slope_k.size() else -1
	if sk >= 0:
		# By a switchback stack: the mountainside its hairpins climb, the high ground over it.
		var sl: Dictionary = slopes[sk]
		var d := float(maxi(maxi(int(sl["k0"]) - e, e - int(sl["k1"])), 0))
		var plane := float(sl["a"]) + float(sl["b"]) * (x - float(sl["cx"])) + float(sl["c"]) * (z - float(sl["cz"])) \
			+ _noise.get_noise_2d(x, z) * hills * 0.15 + _noise_fine.get_noise_2d(x, z) * 2.0 + rise * 0.5
		h = lerpf(h, plane, 1.0 - smoothstep(0.0, float(SLOPE_MARGIN), d))
	var tn := tun_k[i] if i < tun_k.size() else -1
	if tn >= 0:
		# Over a tunnel: the ridge it goes through, from the cutting up to its portals and on up
		# over the roof, rising away to either side.
		var t: Dictionary = tunnels[tn]
		var k0 := int(t["k0"])
		var k1 := int(t["k1"])
		var top := 0.0
		if e >= k0 and e <= k1:
			top = minf(TUNNEL_COVER + mini(e - k0, k1 - e) * STEP * TUNNEL_RISE, 150.0)
		else:
			top = TUNNEL_COVER * (1.0 - smoothstep(0.0, float(TUNNEL_APPROACH) * STEP, float(maxi(k0 - e, e - k1)) * STEP))
		var want := ph[i] + top + maxf(0.0, a - 8.0) * 0.25
		h = lerpf(h, maxf(h, want), 1.0 - smoothstep(220.0, 600.0, a))
	return h


## Keeps the land under the road where another stretch of it (a bend that doubles back, more
## than SITE_KNOTS... 160 m along) passes close by: at most that road's height just under its
## verge and on out a few metres (OTHER_FLAT: the land's triangles are wide out there, and one
## reaching over the road from either side mustn't stand up through it), rising gently away from
## it. Every way at every fork counts, taken or not, so the land comes out the same whichever is
## chosen (see eq). A stretch nearer than 160 m along counts too where the land at (x, z), `a` m
## out from its own knot, is much nearer it than its own centre line: the other leg of a hairpin
## or the next in a stack of them (a real road's are often only 120 m apart along the road and
## 20 m apart across), whose land otherwise stood up through this road by as much as half a metre.
func _other_road_limit(i: int, x: float, z: float, a := 0.0) -> float:
	var limit := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	var e := eq[i] if i < eq.size() else i
	# Only by a hairpin can a stretch so near along the road come nearer than the land's own centre line.
	var m := a * 0.8 - 1.0 if e >= 0 and e < _hairpin.size() and _hairpin[e] != 0 else -1.0
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
## within `r` metres of route-frame (x, z).
func other_road_near(i: int, x: float, z: float, r: float) -> bool:
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	var e := eq[i] if i < eq.size() else i
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				if absi(_seq[j] - e) >= 40 and (_sx[j] - x) * (_sx[j] - x) + (_sz[j] - z) * (_sz[j] - z) < r * r:
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

## Reads the theme's planning numbers (AdventureTheme.DATA), varied's where it has none.
func _theme_numbers() -> void:
	_kinds = AdventureTheme.get_value(theme, "kinds", KIND_WEIGHTS)
	_bends = AdventureTheme.get_value(theme, "bends", {})
	_heights = {"h0": 140.0, "lo": 50.0, "hi": 950.0, "steep": 1.0, "up": 0.5}
	_heights.merge(AdventureTheme.get_value(theme, "heights", {}), true)
	_relief = {"pitch": [0.0, 0.0, 0.0], "rollers": [0.0, 0.0, 0.0], "switchbacks": [], "tunnels": []}
	_relief.merge(AdventureTheme.get_value(theme, "relief", {}), true)
	_hills = float(AdventureTheme.get_value(theme, "hills", 1.0))
	_lift = float(AdventureTheme.get_value(theme, "lift", 1.0))
	sea = bool(AdventureTheme.get_value(theme, "sea", false))
	snow_line = INF
	look = {}
	for table in [["land", AdventureSurface.LAND_COLOR], ["patch", AdventureSurface.LAND_PATCH],
			["verge", AdventureSurface.VERGE_COLOR], ["road", AdventureSurface.ROAD_COLOR]]:
		var d := {}
		for surf in AdventureSurface.IDS:
			d[surf] = AdventureTheme.color(theme, table[0], surf, table[1][surf])
		look[table[0]] = d


## The bends of a section of `kind`: BENDS's, with the theme's own over them (alpine hairpins).
func _bend(kind: String) -> Dictionary:
	if not _bends.has(kind):
		return BENDS[kind]
	var spec: Dictionary = (BENDS[kind] as Dictionary).duplicate()
	spec.merge(_bends[kind], true)
	return spec


## Snow on the road over the tops (a theme with "snow"): every chunk of the main road higher than
## the highest fifth of it (and never below the theme's own line) is snow, past the start's
## tarmac. The ways at the forks take the same line (see _try_way).
func _snow_over_tops() -> void:
	var floor_h = AdventureTheme.get_value(theme, "snow", null)
	if floor_h == null or chunk_surface.is_empty():
		return
	var tops := PackedFloat64Array()
	for c in chunk_surface.size():
		tops.append(ph[mini(c * CHUNK_KNOTS + CHUNK_KNOTS / 2, ph.size() - 1)])
	var sorted := tops.duplicate()
	sorted.sort()
	snow_line = maxf(float(floor_h), sorted[int(sorted.size() * 0.8)])
	for c in range(12, chunk_surface.size()):
		if tops[c] > snow_line:
			chunk_surface[c] = "snow"


func _make_noise(seed: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed
	_noise.frequency = 1.0 / 650.0
	_noise.fractal_octaves = 3
	_noise_fine = FastNoiseLite.new()
	_noise_fine.seed = seed + 1
	_noise_fine.frequency = 1.0 / 90.0
	_noise_fine.fractal_octaves = 2
	_noise_far = FastNoiseLite.new()
	_noise_far.seed = seed + 2
	_noise_far.frequency = 1.0 / 1500.0
	_noise_far.fractal_octaves = 2


func _plan_fuel(rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(FUEL_FIRST[0], FUEL_FIRST[1])
	if length < FUEL_FIRST[1] + 3000.0:
		s = length * 0.5
	while s < length - 3000.0 or (sites_of("fuel").is_empty() and s < length):
		add_site("fuel", snappedf(s, STEP), 1, 30.0, "Fuel")
		s += rng.randf_range(FUEL_EVERY[0], FUEL_EVERY[1])


func _plan_surfaces(rng: RandomNumberGenerator, n: int) -> void:
	surfaces.clear()
	chunk_surface.clear()
	var chunks := int(ceil(float(n - 1) / CHUNK_KNOTS))
	var bag: Array[String] = []
	var last := ""
	var c := 0
	while c < chunks:
		var surf := "tarmac"
		if c > 0:
			if bag.is_empty():
				bag.assign(AdventureTheme.get_value(theme, "bag", SURFACE_BAG))
				for k in range(bag.size() - 1, 0, -1):   # shuffled with our own rng, the same everywhere
					var j := rng.randi_range(0, k)
					var tmp := bag[k]
					bag[k] = bag[j]
					bag[j] = tmp
			surf = bag.pop_back()
			if surf == last and not bag.is_empty():
				bag.push_front(surf)
				surf = bag.pop_back()
		var surf_len: Array = AdventureTheme.get_value(theme, "surf_len", SURFACE_LEN)
		var span := maxi(4, int(rng.randf_range(surf_len[0], surf_len[1]) / CHUNK_LEN))
		if c == 0:
			span = maxi(span, 12)   # the start is always on tarmac for a while
		var end := mini(chunks, c + span)
		surfaces.append({"s0": c * CHUNK_LEN, "s1": end * CHUNK_LEN, "surface": surf})
		for k in range(c, end):
			chunk_surface.append(surf)
		last = surf
		c = end


func _plan_bends(rng: RandomNumberGenerator, n: int) -> void:
	sections.clear()
	curv.resize(n)
	hd.resize(n)
	width.resize(n)
	var targets := PackedFloat32Array()
	targets.resize(n)
	var st := {"i": 0, "h": 0.0}
	var filled := 0   # knots up to here have their width target (a bend can run past its section's end)
	var sb: Array = _relief["switchbacks"]
	while st["i"] < n - 1:
		var i0: int = st["i"]
		var kind := "straight"
		if i0 > 0:
			kind = _weighted(rng, _kinds)
		if i0 > 0 and sb.size() == 3 and rng.randf() < float(sb[0]):
			# A stack of hairpins up (or down) a mountainside, where it fits clear of the sites.
			var ops := _switchback_ops(rng, float(st["h"]), rng.randi_range(int(sb[1]), int(sb[2])))
			var knots := _ops_knots(ops, float(st["h"]))
			if i0 + knots < n - 200 and not _site_near(i0, knots + 30):
				var swc := _width_for(rng, "very_curvy", surface_at_s(i0 * STEP))
				sections.append({"s0": i0 * STEP, "s1": (i0 + knots) * STEP, "kind": "switchback", "width": swc})
				for k in range(filled, mini(i0 + knots + 1, n)):
					targets[k] = WIDTHS[swc]
				filled = maxi(filled, mini(i0 + knots + 1, n))
				for op in ops:
					if op[0] == "straight":
						for k in int(op[1]):
							_put(st, 0.0)
					else:
						# Turning to a heading (not by an angle), so the legs stay true however the knots round.
						var arc := absf(float(op[1]) - float(st["h"]))
						_arc(st, signf(float(op[1]) - float(st["h"])), float(op[2]), arc, float(op[3]))
				continue
		var spec: Dictionary = _bend(kind)
		var sec_len := rng.randf_range(spec["len"][0], spec["len"][1]) if i0 > 0 else 260.0
		var end := mini(n - 1, i0 + int(sec_len / STEP))
		var wclass := _width_for(rng, kind, surface_at_s(i0 * STEP))
		sections.append({"s0": i0 * STEP, "s1": end * STEP, "kind": kind, "width": wclass})
		for k in range(filled, mini(end + 1, n)):
			targets[k] = WIDTHS[wclass]
		filled = maxi(filled, mini(end + 1, n))
		var last_sign := 1.0 if rng.randf() < 0.5 else -1.0
		while st["i"] < end:
			# Straight between bends (and always through a site).
			var gap := int(rng.randf_range(spec["gap"][0], spec["gap"][1]) / STEP)
			for k in gap:
				if st["i"] >= end:
					break
				_put(st, 0.0)
			if st["i"] >= end:
				break
			var r: float = rng.randf_range(spec["r"][0], spec["r"][1])
			var arc := deg_to_rad(rng.randf_range(spec["arc"][0], spec["arc"][1]))
			var t: float = rng.randf_range(spec["t"][0], spec["t"][1])
			# Turn back towards the way the route goes once it's swung well round; otherwise mostly
			# swap sides from the last bend.
			var h: float = st["h"]
			var sign := -last_sign if rng.randf() < 0.72 else last_sign
			if h > deg_to_rad(30.0):
				sign = -1.0 if rng.randf() < 0.85 else 1.0
			elif h < -deg_to_rad(30.0):
				sign = 1.0 if rng.randf() < 0.85 else -1.0
			var room := MAX_HEADING - sign * h
			if room < deg_to_rad(12.0):
				sign = -sign
				room = MAX_HEADING - sign * h
			arc = minf(arc, room)
			last_sign = sign
			var tk := maxi(1, int(minf(t, arc * r * 0.5) / STEP))
			var ck := maxi(0, int((arc * r - tk * STEP) / STEP))
			var knots := tk * 2 + ck
			if _site_near(st["i"], knots):
				# A site ahead: keep straight past it instead.
				var site_end := _site_end(st["i"], knots)
				while st["i"] < mini(site_end, n - 1):
					_put(st, 0.0)
				continue
			_arc(st, sign, r, arc, t)
	for k in range(filled, n):
		targets[k] = targets[filled - 1] if filled > 0 else WIDTHS["road"]
	# The width eases from one section's to the next.
	var w := targets[0]
	for i in n:
		w = move_toward(w, targets[i], 0.05)
		width[i] = w


## Writes the curvature at the next knot and moves the heading on, never past MAX_HEADING (a
## little slack for the clothoids: past that the knot runs straight).
func _put(st: Dictionary, k: float) -> void:
	var i: int = st["i"]
	if i >= curv.size():
		st["i"] = i + 1
		return
	var h: float = st["h"]
	if absf(h + k * STEP) > MAX_HEADING + 0.08:
		k = 0.0
	curv[i] = k
	hd[i] = h
	st["h"] = h + k * STEP
	st["i"] = i + 1
	if i + 1 < hd.size():
		hd[i + 1] = st["h"]


## A bend `sign` (+1 right) of radius `r` through `arc` radians, eased in and out over `t` metres
## of clothoid.
func _arc(st: Dictionary, sign: float, r: float, arc: float, t: float) -> void:
	var tk := maxi(1, int(minf(t, arc * r * 0.5) / STEP))
	var ck := maxi(0, int((arc * r - tk * STEP) / STEP))
	for k in tk:
		_put(st, sign / r * (k + 0.5) / tk)
	for k in ck:
		_put(st, sign / r)
	for k in tk:
		_put(st, sign / r * (tk - k - 0.5) / tk)


static func _arc_knots(r: float, arc: float, t: float) -> int:
	var tk := maxi(1, int(minf(t, arc * r * 0.5) / STEP))
	return tk * 2 + maxi(0, int((arc * r - tk * STEP) / STEP))


## A stack of `legs` switchback hairpins from heading `h0`: [["turn", heading, radius, clothoid],
## ["straight", knots]...]: round onto the first leg across the slope (to the side it's already
## heading), then each leg and a hairpin onto the next, the other way across, and off the last
## leg back towards the way on. The legs never point further round than SB_HEADING, so the road
## still makes way north and never crosses itself; each pair of legs is a hairpin's width and
## more apart.
func _switchback_ops(rng: RandomNumberGenerator, h0: float, legs: int) -> Array:
	var head := deg_to_rad(rng.randf_range(SB_HEADING[0], SB_HEADING[1]))
	var side := 1.0 if h0 >= 0.0 else -1.0
	var ops := [["turn", side * head, SB_TURN_R, 24.0]]
	for k in legs:
		ops.append(["straight", int(rng.randf_range(SB_LEG[0], SB_LEG[1]) / STEP)])
		if k < legs - 1:
			side = -side
			ops.append(["turn", side * head, rng.randf_range(SB_RADIUS[0], SB_RADIUS[1]), rng.randf_range(8.0, 12.0)])
	ops.append(["turn", -side * deg_to_rad(rng.randf_range(0.0, 20.0)), SB_TURN_R * 1.3, 30.0])
	return ops


## How many knots a list of switchback ops (see _switchback_ops) runs, from heading `h0`.
static func _ops_knots(ops: Array, h0 := 0.0) -> int:
	var out := 0
	var h := h0
	for op in ops:
		if op[0] == "straight":
			out += int(op[1])
		else:
			out += _arc_knots(float(op[2]), absf(float(op[1]) - h), float(op[3]))
			h = float(op[1])
	return out


## Whether a site of `among` (each kept straight `keep` knots either side) is within the
## `knots` from knot `i`.
func _site_near(i: int, knots: int, among: Array = sites) -> bool:
	for st in among:
		var si: int = int(round(float(st["s"]) / STEP))
		var keep := int(st.get("keep", SITE_KNOTS))
		if si + keep >= i and si - keep <= i + knots:
			return true
	return false


func _site_end(i: int, knots: int, among: Array = sites) -> int:
	var out := i + 1
	for st in among:
		var si: int = int(round(float(st["s"]) / STEP))
		var keep := int(st.get("keep", SITE_KNOTS))
		if si + keep >= i and si - keep <= i + knots:
			out = maxi(out, si + keep + 1)
	return out


func _width_for(rng: RandomNumberGenerator, kind: String, surf: String) -> String:
	var w := {}
	if surf == "tarmac":
		match kind:
			"straight", "sweeping":
				w = {"two_lane": 0.5, "road": 0.4, "narrow": 0.1}
			"curvy":
				w = {"two_lane": 0.1, "road": 0.45, "narrow": 0.35, "single": 0.1}
			_:
				w = {"road": 0.2, "narrow": 0.5, "single": 0.3}
	elif surf == "gravel":
		w = {"road": 0.2, "narrow": 0.5, "single": 0.3}
	elif surf == "sand":
		w = {"road": 0.3, "narrow": 0.5, "single": 0.2}
	else:
		w = {"road": 0.4, "narrow": 0.5, "single": 0.1}
	var mult: Dictionary = AdventureTheme.get_value(theme, "widths", {})
	for k in mult:
		if w.has(k):
			w[k] = float(w[k]) * float(mult[k])
	return _weighted(rng, w)


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var sum := 0.0
	for k in weights:
		sum += float(weights[k])
	var roll := rng.randf() * sum
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return str(k)
	return str(weights.keys()[-1])


## The road's heights, a stretch at a time: long steady climbs and descents (steeper on the
## twistier roads, and over the passes on a theme with a "wave"), short steep pitches (12-15% on
## the hills and in the mountains) over crests and down into dips, rollers (a run of dips and
## rises, the desert's way), switchback stacks climbing (or dropping) steadily all the way, level
## through the sites and near level through tunnels; the grade eased from one to the next (see
## GRADE_RATE, PITCH_RATE) and never past MAX_GRADE.
func _plan_heights(rng: RandomNumberGenerator, n: int) -> void:
	ph.resize(n)
	var h := float(_heights["h0"])
	var steep_mult := float(_heights["steep"])
	var up := float(_heights["up"])
	var top := float(_heights["hi"])
	var bottom := float(_heights["lo"])
	var wave: Array = _heights.get("wave", [])   # [m from top to top, valley, top]
	var pitch: Array = _relief["pitch"]
	var roll: Array = _relief["rollers"]
	var level := _level_mask(n)
	var gentle := _tunnel_mask(n)
	var g := 0.0
	var target := 0.0
	var rate := GRADE_RATE
	var seg_end := 0
	var roll_i0 := -1   # rollers: where the waves start, how long each is (m) and their steepest
	var roll_len := 1.0
	var roll_g := 0.0
	for i in n:
		if i >= seg_end:
			var kind := kind_at_s(i * STEP)
			var steep := ({"straight": 3.0, "sweeping": 6.0, "curvy": 8.0, "very_curvy": 10.0}.get(kind, 5.0) as float) * steep_mult
			# Which way it wants to go: towards the next top (or down into the valley) over passes.
			var up_odds := up
			if wave.size() == 3:
				var want := lerpf(float(wave[1]), float(wave[2]), pow(sin(PI * i * STEP / float(wave[0])), 2.0))
				up_odds = 0.5 if absf(want - h) < 60.0 else (0.92 if want > h else 0.08)
			rate = GRADE_RATE
			roll_i0 = -1
			var r := rng.randf()
			if kind == "switchback":
				# Up (or down) the mountainside, the same grade all the way to the top of the stack.
				var climbs := rng.randf() < up_odds if wave.size() == 3 else h < (top + bottom) * 0.5
				target = (1.0 if climbs else -1.0) * rng.randf_range(SB_GRADE[0], SB_GRADE[1])
				rate = PITCH_RATE
				seg_end = i + 1
				for sec in sections:
					if i * STEP >= float(sec["s0"]) and i * STEP < float(sec["s1"]):
						seg_end = int(float(sec["s1"]) / STEP) + 1
			elif r < float(pitch[0]):
				# A short steep pitch: up and over a crest, or down into a dip.
				target = rng.randf_range(float(pitch[1]), float(pitch[2])) / 100.0 * (1.0 if rng.randf() < up_odds else -1.0)
				rate = PITCH_RATE
				seg_end = i + int(absf(target - g) / PITCH_RATE) + int(rng.randf_range(PITCH_LEN[0], PITCH_LEN[1]) / STEP)
			elif r < float(pitch[0]) + float(roll[0]):
				# Rollers: a few dips and rises one after another.
				roll_len = rng.randf_range(ROLL_WAVE[0], ROLL_WAVE[1])
				roll_g = minf(rng.randf_range(float(roll[1]), float(roll[2])) / 100.0, roll_len / (TAU * ROLL_R))
				roll_i0 = i
				target = 0.0
				rate = maxf(GRADE_RATE, roll_g * TAU / roll_len * STEP * 1.15)
				seg_end = i + int(roll_len * rng.randi_range(2, 4) / STEP)
			else:
				if wave.size() == 3:
					# Over the passes: climbing hard towards the next top, then down into the valley.
					target = rng.randf_range(0.55, 1.0) * steep / 100.0 * (1.0 if rng.randf() < up_odds else -1.0)
				else:
					target = rng.randf_range(0.25, 1.0) * steep / 100.0 * (1.0 if rng.randf() < up else -1.0)
					if rng.randf() < 0.22:
						target = 0.0
				seg_end = i + int(rng.randf_range(300.0, 1400.0) / STEP)
		var aim := target
		var step_rate := rate
		if roll_i0 >= 0:
			aim = roll_g * sin(TAU * (i - roll_i0) * STEP / roll_len)
		# Turning back in time at the top and bottom: where it would level off from here at this rate.
		var ease_h := g * absf(g) / (2.0 * step_rate) * STEP
		if h + maxf(ease_h, 0.0) > top:
			aim = -absf(aim) - 0.02
		elif h + minf(ease_h, 0.0) < bottom:
			aim = absf(aim) + 0.02
		if gentle[i] != 0 and absf(aim) > TUNNEL_GRADE:
			aim = clampf(aim, -TUNNEL_GRADE, TUNNEL_GRADE)   # near level through a tunnel
			step_rate = PITCH_RATE
		if level[i] != 0:
			aim = 0.0   # level for a site, from well before it
			step_rate = maxf(rate, GRADE_RATE * 1.5)
		g = clampf(move_toward(g, aim, step_rate), -MAX_GRADE, MAX_GRADE)
		ph[i] = h
		h += g * STEP


## Knots to keep level for the sites: from well before each (where the grade eases off) to a little
## after; a crossing (AdventureJunctions) only needs a short level stretch either side.
func _level_mask(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	for st in sites:
		var si := int(round(float(st["s"]) / STEP))
		var keep := int(st.get("keep", SITE_KNOTS))
		var short: bool = st["kind"] == AdventureJunctions.KIND
		for k in range(maxi(0, si - keep - (90 if short else 120)), mini(n, si + keep + (20 if short else 30) + 1)):
			out[k] = 1
	return out


## Knots kept near level for a tunnel: through it, and a run-up to it so the grade is eased off
## by the portal.
func _tunnel_mask(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	for t in tunnels:
		for k in range(maxi(0, int(t["k0"]) - 70), mini(n, int(t["k1"]) + 12)):
			out[k] = 1
	return out


## Where the tunnels go (a theme's relief "tunnels"): every so often, a stretch of the road gentle
## enough to bore through (bends no tighter than TUNNEL_BEND), clear of the sites, the forks, the
## switchback stacks and every other stretch of road (TUNNEL_CLEAR), so the hill over it is whole.
## Its own rng: the rest of the road is planned the same with or without them.
func _plan_tunnels(n: int) -> void:
	tunnels = []
	var spec: Array = _relief["tunnels"]
	if spec.size() != 5:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "tunnels", theme])
	var cells := {}
	for i in range(0, n, 4):
		var key := Vector2i(int(floor(px[i] / 128.0)), int(floor(pz[i] / 128.0)))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(i)
	var busy := PackedByteArray()   # the switchback stacks and the forks' ways
	busy.resize(n)
	for sec in sections:
		if sec["kind"] == "switchback":
			for k in range(maxi(0, int(float(sec["s0"]) / STEP) - 40), mini(n, int(float(sec["s1"]) / STEP) + 40)):
				busy[k] = 1
	for fk in forks:
		for k in range(maxi(0, int(fk["i0"]) - 80), mini(n, int(fk["i1"]) + 80)):
			busy[k] = 1
	var s := float(spec[0])
	while s < length - 2000.0:
		var k := int(rng.randf_range(float(spec[3]), float(spec[4])) / STEP)
		var i := int(s / STEP)
		var stop := mini(n - k - 120, i + int(4000.0 / STEP))
		var found := -1
		while i < stop:
			var skip := _tunnel_clash(i, k, cells, busy)
			if skip < 0:
				found = i
				break
			i = skip
		if found >= 0:
			tunnels.append({"k0": found, "k1": found + k, "id": tunnels.size()})
			s = (found + k) * STEP + rng.randf_range(float(spec[1]), float(spec[2]))
		else:
			s += 4000.0


## Whether a tunnel from knot `i`, `k` knots long, won't do there: the knot to try from next
## (past what's in the way), or -1 when it's fine.
func _tunnel_clash(i: int, k: int, cells: Dictionary, busy: PackedByteArray) -> int:
	for j in range(i - 15, i + k + 16):
		if busy[j] != 0 or absf(curv[j]) > TUNNEL_BEND:
			return maxi(j + 16, i + 1)   # (its run-in clear of it)
	if _site_near(i - 60, k + 120):
		return maxi(_site_end(i - 60, k + 120) + 60, i + 1)
	for j in range(i, i + k + 1, 4):
		var cx := int(floor(px[j] / 128.0))
		var cz := int(floor(pz[j] / 128.0))
		for gz in range(cz - 1, cz + 2):
			for gx in range(cx - 1, cx + 2):
				for m in cells.get(Vector2i(gx, gz), []):
					if absi(m - j) > 90 and Vector2(px[m] - px[j], pz[m] - pz[j]).length() < TUNNEL_CLEAR:
						return j + 1
	return -1


## The mountainside under each switchback stack: the plane fitted (least squares) through its
## knots, which the land between the hairpins lies along (see natural_height). And each knot's
## tunnel and mountainside (tun_k, slope_k) on the default path.
func _plan_slopes(n: int) -> void:
	slopes = []
	for sec in sections:
		if sec["kind"] != "switchback":
			continue
		var k0 := int(float(sec["s0"]) / STEP)
		var k1 := mini(n - 1, int(float(sec["s1"]) / STEP))
		var cnt := float(k1 - k0 + 1)
		var cx := 0.0
		var cz := 0.0
		var ch := 0.0
		for k in range(k0, k1 + 1):
			cx += px[k] / cnt
			cz += pz[k] / cnt
			ch += ph[k] / cnt
		var sxx := 0.0
		var sxz := 0.0
		var szz := 0.0
		var sxh := 0.0
		var szh := 0.0
		for k in range(k0, k1 + 1):
			var dx := px[k] - cx
			var dz := pz[k] - cz
			var dh := ph[k] - ch
			sxx += dx * dx
			sxz += dx * dz
			szz += dz * dz
			sxh += dx * dh
			szh += dz * dh
		var det := sxx * szz - sxz * sxz
		var b := (sxh * szz - szh * sxz) / det if absf(det) > 1e-6 else 0.0
		var c := (szh * sxx - sxh * sxz) / det if absf(det) > 1e-6 else 0.0
		slopes.append({"k0": k0, "k1": k1, "cx": cx, "cz": cz, "a": ch, "b": b, "c": c})
	tun_k = PackedInt32Array()
	tun_k.resize(n)
	tun_k.fill(-1)
	slope_k = PackedInt32Array()
	slope_k.resize(n)
	slope_k.fill(-1)
	for t in tunnels:
		for k in range(maxi(0, int(t["k0"]) - TUNNEL_APPROACH), mini(n, int(t["k1"]) + TUNNEL_APPROACH + 1)):
			tun_k[k] = int(t["id"])
	for q in slopes.size():
		for k in range(maxi(0, int(slopes[q]["k0"]) - SLOPE_MARGIN), mini(n, int(slopes[q]["k1"]) + SLOPE_MARGIN + 1)):
			slope_k[k] = q


## Whether knot `i` of the path is inside a tunnel (between its portals).
func in_tunnel(i: int) -> bool:
	var tn := tun_k[i] if i >= 0 and i < tun_k.size() else -1
	if tn < 0:
		return false
	var e := eq[i] if i < eq.size() else i
	return e >= int(tunnels[tn]["k0"]) and e <= int(tunnels[tn]["k1"])


## The tunnel at `s` along the path ({s0, s1, id}), or {} out in the open.
func tunnel_at_s(s: float) -> Dictionary:
	for t in tunnels_on:
		if s >= float(t["s0"]) and s <= float(t["s1"]):
			return t
	return {}


func _integrate(n: int) -> void:
	px.resize(n)
	pz.resize(n)
	var x := 0.0
	var z := 0.0
	for i in n:
		px[i] = x
		pz[i] = z
		if i < n - 1:
			var h := hd[i] + curv[i] * STEP * 0.5
			x += sin(h) * STEP
			z -= cos(h) * STEP
	for st in sites:
		st["i"] = clampi(int(round(float(st["s"]) / STEP)), 0, n - 1)
	# The lie of the land: the road's height averaged over 200 m either way (once there are
	# heights: the first pass, for the tunnels' places, is before them).
	if ph.size() < n:
		return
	base.resize(n)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	for i in n:
		sums[i + 1] = sums[i] + ph[i]
	for i in n:
		var a := maxi(0, i - 50)
		var b := mini(n, i + 51)
		base[i] = (sums[b] - sums[a]) / float(b - a)


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

## Where the forks go, along the main road: clear of the sites already planned, each with the
## signpost before it and the junctions kept straight at the fork and where the ways meet again.
func _plan_forks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "forks", theme])
	var s := snappedf(rng.randf_range(FORK_FIRST[0], FORK_FIRST[1]), CHUNK_LEN)
	while true:
		var main_len := snappedf(rng.randf_range(FORK_MAIN[0], FORK_MAIN[1]), CHUNK_LEN)
		var tries := 0
		while _junction_clash(s, s + main_len) and tries < 30:
			s += CHUNK_LEN * 2.0
			tries += 1
		if s + main_len > length - FORK_END_GAP:
			break
		var f := forks.size()
		var kinds: Array[String] = ["main", "scenic", "gravel"]
		if rng.randf() < 0.45:
			kinds.remove_at(1 if rng.randf() < 0.5 else 2)
		var names := {"main": "Main road", "scenic": PASS_NAMES[rng.randi() % PASS_NAMES.size()] + " Pass",
			"gravel": TRACK_NAMES[rng.randi() % TRACK_NAMES.size()] + " Track"}
		forks.append({"s": s, "rejoin": s + main_len, "i0": int(round(s / STEP)), "i1": int(round((s + main_len) / STEP)),
			"kinds": kinds, "names": names, "ways": []})
		var sign := add_site("fork", s - SIGN_BEFORE, 1, 16.0, "Fork", 40)
		sign["fork"] = f
		var part := add_site("junction", s, 1, 0.0, "Fork", JUNCTION_KNOTS)
		part["fork"] = f
		var meet := add_site("junction", s + main_len, 1, 0.0, "Ways meet", JUNCTION_KNOTS)
		meet["rejoin"] = f
		s += snappedf(rng.randf_range(FORK_EVERY[0], FORK_EVERY[1]), CHUNK_LEN)


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
		"width": width.duplicate(), "base": base.duplicate(), "sections": sections.duplicate(true),
		"tun_k": tun_k.duplicate(), "slope_k": slope_k.duplicate(),
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


## Plans the ways at fork `f`: the main road (the default path's own), and the others steered off
## to the other side of it and back to the rejoin.
func _plan_ways(f: int) -> void:
	var fk: Dictionary = forks[f]
	var i0: int = fk["i0"]
	var i1: int = fk["i1"]
	var mid := (i0 + i1) / 2
	var cx := (px[i0] + px[i1]) * 0.5
	var cz := (pz[i0] + pz[i1]) * 0.5
	# Which side of the line from fork to rejoin the main road bows out to.
	var rx := -(pz[i1] - pz[i0])
	var rz := px[i1] - px[i0]
	var main_side := 1.0 if (px[mid] - cx) * rx + (pz[mid] - cz) * rz >= 0.0 else -1.0
	var ways := [{"kind": "main", "name": fk["names"]["main"], "n": i1 - i0 + 1, "sites": []}]
	_summarise(ways[0], _def, i0, i1)
	for kind in fk["kinds"]:
		if kind == "main":
			continue
		var way := _plan_way(f, kind, -main_side if kind == "scenic" else main_side)
		way["name"] = fk["names"][kind]
		_summarise(way, way, 0, int(way["n"]) - 1)
		ways.append(way)
	_finish_ways(fk, ways)


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


## Plans way `kind` at fork `f` (see _try_way): if one comes in far off the rejoin (so easing it
## across would stretch it out of shape), it's planned again on the next seed, keeping the best.
func _plan_way(f: int, kind: String, side: float) -> Dictionary:
	var best := {}
	for attempt in 5:
		var way := _try_way(f, kind, side, attempt)
		if best.is_empty() or float(way["miss"]) < float(best["miss"]):
			best = way
		if float(best["miss"]) < 90.0:
			break
	return best


## Plans one other way at fork `f` (WAY_PLANS[kind]): from the fork, straight for the junction,
## then sections of bends steered towards a point off to `side` of the line to the rejoin, then
## to a point in line behind the rejoin, then followed in onto the rejoin. What's left over
## (tens of metres, and a few degrees of heading) is spread along the way, so it meets the road
## on from there exactly. A whole number of chunks long.
func _try_way(f: int, kind: String, side: float, attempt: int) -> Dictionary:
	var fk: Dictionary = forks[f]
	var spec: Dictionary = WAY_PLANS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "way", theme, f, kind, attempt])
	var i0: int = fk["i0"]
	var i1: int = fk["i1"]
	var a := Vector2(px[i0], pz[i0])
	var b := Vector2(px[i1], pz[i1])
	var hb := hd[i1]
	var chord := b - a
	var dist := chord.length()
	var right := Vector2(-chord.y, chord.x) / dist
	var aim := a + chord * 0.5 + right * side * dist * float(spec["off"]) * rng.randf_range(0.8, 1.2)
	var approach := b - Vector2(sin(hb), -cos(hb)) * 700.0
	# The fuel and the stops (AdventureStops) on the main road through the fork are matched on
	# every other way, as far along it in proportion and in the same order, so whichever's taken
	# nobody's left dry or hungry and the stops keep their spacing. A village's other rows of
	# shops keep their distance from its middle.
	var wsites := []
	var lo := JUNCTION_KNOTS * STEP + 250.0
	var hi := maxf(lo + 200.0, dist * 0.8 - 300.0)
	for st in sites:
		var ds := float(st["s"])
		if ds <= float(fk["s"]) or ds >= float(fk["rejoin"]):
			continue
		if not (st["kind"] == "fuel" or bool(st.get("stop", false)) or st.has("main_s")):
			continue
		var centre := float(st.get("main_s", ds))
		var frac := clampf((centre - float(fk["s"])) / (float(fk["rejoin"]) - float(fk["s"])), 0.0, 1.0)
		var lc := snappedf(lerpf(lo, hi, frac), STEP)
		var copy: Dictionary = st.duplicate()
		copy.erase("ds")
		copy["ls"] = lc + ds - centre
		copy["s"] = copy["ls"]
		if st.has("main_s"):
			copy["main_off"] = centre - ds
		wsites.append(copy)
	var g := {"x": float(px[i0]), "z": float(pz[i0]), "h": float(hd[i0]), "cv": [], "hs": [],
		"xs": [], "zs": []}
	var secs := []
	for k in JUNCTION_KNOTS:
		_wput(g, 0.0)
	var stage := 0
	var limit := int(dist * 3.0 / STEP) + 400
	var sec_end := 0
	var bends: Dictionary = _bend("sweeping")
	var last_sign := side
	var stray: float = spec["stray"]
	while _wn(g) < limit:
		var p := Vector2(g["x"], g["z"])
		if stage == 0 and (p.distance_to(aim) < dist * 0.2 or (p - a).dot(chord) > (aim - a).dot(chord)):
			stage = 1
		if stage == 1 and (p.distance_to(approach) < 500.0 or (p - a).dot(chord) > (approach - a).dot(chord) - 100.0 * dist):
			break
		if _wn(g) >= sec_end:
			var sk := _weighted(rng, spec["kinds"])
			bends = _bend(sk)
			sec_end = _wn(g) + int(rng.randf_range(bends["len"][0], bends["len"][1]) / STEP)
			secs.append({"s0": _wn(g) * STEP, "s1": sec_end * STEP, "kind": sk, "width": _weighted(rng, spec["widths"])})
		var target := aim if stage == 0 else approach
		for k in int(rng.randf_range(bends["gap"][0], bends["gap"][1]) / STEP):
			_wput(g, 0.0)
		var r: float = rng.randf_range(bends["r"][0], bends["r"][1])
		var arc := deg_to_rad(rng.randf_range(bends["arc"][0], bends["arc"][1]))
		var t: float = rng.randf_range(bends["t"][0], bends["t"][1])
		# Bend towards where it's making for when it's well off it, otherwise mostly swap sides;
		# never so far that the heading strays more than `stray` from it.
		var to := target - Vector2(g["x"], g["z"])
		var err := wrapf(atan2(to.x, -to.y) - float(g["h"]), -PI, PI)
		var sign := 1.0 if err > 0.0 else -1.0
		if absf(err) < stray * 0.5:
			sign = -last_sign if rng.randf() < 0.72 else last_sign
		var room := stray + sign * err
		if room < deg_to_rad(10.0):
			sign = -sign
			room = stray + sign * err
		arc = minf(arc, maxf(room, deg_to_rad(5.0)))
		last_sign = sign
		var tk := maxi(1, int(minf(t, arc * r * 0.5) / STEP))
		var ck := maxi(0, int((arc * r - tk * STEP) / STEP))
		var knots := tk * 2 + ck
		if _site_near(_wn(g), knots, wsites):
			var end := _site_end(_wn(g), knots, wsites)
			while _wn(g) < end:
				_wput(g, 0.0)
			continue
		for k in tk:
			_wput(g, sign / r * (k + 0.5) / tk)
		for k in ck:
			_wput(g, sign / r)
		for k in tk:
			_wput(g, sign / r * (tk - k - 0.5) / tk)
	# In onto the line behind the rejoin and along it, following a point a little ahead.
	var ab := b - approach
	var lab := ab.length()
	var u := ab / lab
	var final_at := _wn(g)
	while _wn(g) < limit + 600:
		var p := Vector2(g["x"], g["z"])
		var along := (p - approach).dot(u)
		if along >= lab - STEP * 0.5:
			break
		var carrot := approach + u * minf(maxf(along, 0.0) + 120.0, lab + 60.0)
		var to := carrot - p
		var err := wrapf(atan2(to.x, -to.y) - float(g["h"]), -PI, PI)
		_wput(g, clampf(2.0 * sin(err) / maxf(to.length(), 30.0), -1.0 / 70.0, 1.0 / 70.0))
	secs.append({"s0": final_at * STEP, "s1": INF, "kind": "sweeping", "width": _weighted(rng, spec["widths"])})
	# A whole number of chunks: straight on a little further, or cut back.
	var cnt := _wn(g) + 1
	var n := maxi(CHUNK_KNOTS * 4 + 1, int(round(float(cnt - 1) / CHUNK_KNOTS)) * CHUNK_KNOTS + 1)
	while _wn(g) < n - 1:
		_wput(g, 0.0)
	var xs := PackedFloat64Array(g["xs"])
	var zs := PackedFloat64Array(g["zs"])
	var hs := PackedFloat64Array(g["hs"])
	var cv := PackedFloat64Array(g["cv"])
	xs.append(g["x"])
	zs.append(g["z"])
	hs.append(g["h"])
	cv.append(0.0)
	xs.resize(n)
	zs.resize(n)
	hs.resize(n)
	cv.resize(n)
	# Turn the last stretch round onto the rejoin's heading...
	var dh := wrapf(hb - hs[n - 1], -PI, PI)
	var m := mini(120, (n - 1) / 3)
	var k0 := n - 1 - m
	for k in range(k0, n - 1):
		var sh := hs[k] + cv[k] * STEP * 0.5 + dh * smoothstep(float(k0), float(n - 1), k + 0.5)
		xs[k + 1] = xs[k] + sin(sh) * STEP
		zs[k + 1] = zs[k] - cos(sh) * STEP
	# ...and ease the whole way across onto it.
	var ex := px[i1] - xs[n - 1]
	var ez := pz[i1] - zs[n - 1]
	for k in n:
		var tt := float(k) / float(n - 1)
		var w := tt * tt * tt * (tt * (tt * 6.0 - 15.0) + 10.0)
		xs[k] += ex * w
		zs[k] += ez * w
	xs[0] = px[i0]
	zs[0] = pz[i0]
	xs[n - 1] = px[i1]
	zs[n - 1] = pz[i1]
	# Headings and curvature from where the knots ended up.
	var whd := PackedFloat64Array()
	whd.resize(n)
	var wcv := PackedFloat32Array()
	wcv.resize(n)
	var prev := hd[i0]
	var segs := PackedFloat64Array()
	segs.resize(n - 1)
	for k in n - 1:
		var sg := atan2(xs[k + 1] - xs[k], -(zs[k + 1] - zs[k]))
		prev = prev + wrapf(sg - prev, -PI, PI)
		segs[k] = prev
	whd[0] = hd[i0]
	for k in range(1, n - 1):
		whd[k] = (segs[k - 1] + segs[k]) * 0.5
	whd[n - 1] = hb
	for k in n - 1:
		wcv[k] = (whd[k + 1] - whd[k]) / STEP
	var way := {"kind": kind, "n": n, "px": xs, "pz": zs, "hd": whd, "curv": wcv, "sites": wsites, "miss": Vector2(ex, ez).length()}
	for sec in secs:
		sec["s1"] = minf(float(sec["s1"]), (n - 1) * STEP)
	way["sections"] = secs.filter(func(sec): return float(sec["s1"]) > float(sec["s0"]))
	_way_heights(way, rng, ph[i0], ph[i1])
	_way_widths(way, width[i0], width[i1])
	# Its surfaces, a chunk at a time: a gravel track (sand in the middle of some), a scenic pass
	# on tarmac, snowy over the top of a high one.
	var cs: Array[String] = []
	var chunks := (n - 1) / CHUNK_KNOTS
	var sandy := rng.randf() < float(AdventureTheme.get_value(theme, "track_sand", 0.4))
	var pass_snow := bool(AdventureTheme.get_value(theme, "pass_snow", true))
	var wph: PackedFloat64Array = way["ph"]
	for c in chunks:
		var ct := (c + 0.5) / chunks
		var surf := "tarmac"
		if kind == "gravel":
			surf = "sand" if sandy and ct > 0.4 and ct < 0.62 else "gravel"
		elif pass_snow and float(way["rise"]) > 120.0 and ct > 0.38 and ct < 0.62:
			surf = "snow"
		if wph[mini(c * CHUNK_KNOTS + CHUNK_KNOTS / 2, n - 1)] > snow_line:
			surf = "snow"   # over the snow line (alpine)
		cs.append(surf)
	way["chunk_surface"] = cs
	way["base"] = _leg_base(way["ph"], [0, n - 1])
	return way


## How many knots a way being planned has so far.
static func _wn(g: Dictionary) -> int:
	return (g["xs"] as Array).size()


## Writes the next knot of a way being planned (curvature `k` after it) and moves on.
static func _wput(g: Dictionary, k: float) -> void:
	var h: float = g["h"]
	(g["cv"] as Array).append(k)
	(g["hs"] as Array).append(h)
	(g["xs"] as Array).append(g["x"])
	(g["zs"] as Array).append(g["z"])
	var hm := h + k * STEP * 0.5
	g["x"] = float(g["x"]) + sin(hm) * STEP
	g["z"] = float(g["z"]) - cos(hm) * STEP
	g["h"] = h + k * STEP


## A way's heights: climbs and descents like the main road's, level by the junctions and its
## sites, eased to meet the rejoin's height; a scenic pass rises over a top on the way.
func _way_heights(way: Dictionary, rng: RandomNumberGenerator, h0: float, h1: float) -> void:
	var n: int = way["n"]
	var zh := PackedFloat64Array()
	zh.resize(n)
	var h := h0
	var gr := 0.0
	var target := 0.0
	var seg_end := 0
	var rate := GRADE_RATE
	var pitch: Array = _relief["pitch"]
	for k in n:
		if k >= seg_end:
			var kind := _kind_in(way["sections"], k * STEP)
			var steep := ({"straight": 3.0, "sweeping": 6.0, "curvy": 8.0, "very_curvy": 10.0}.get(kind, 5.0) as float) * float(_heights["steep"])
			rate = GRADE_RATE
			if rng.randf() < float(pitch[0]):
				# A short steep pitch, as on the main road.
				target = rng.randf_range(float(pitch[1]), float(pitch[2])) / 100.0 * (1.0 if rng.randf() < 0.5 else -1.0)
				rate = PITCH_RATE
				seg_end = k + int(absf(target - gr) / PITCH_RATE) + int(rng.randf_range(PITCH_LEN[0], PITCH_LEN[1]) / STEP)
			else:
				target = rng.randf_range(0.25, 1.0) * steep / 100.0 * (1.0 if rng.randf() < 0.5 else -1.0)
				if rng.randf() < 0.22:
					target = 0.0
				seg_end = k + int(rng.randf_range(300.0, 1400.0) / STEP)
		var aim := target
		if k < JUNCTION_KNOTS + 10 or k > n - JUNCTION_KNOTS - 40 or _site_near(k - 30, 150, way["sites"]):
			aim = 0.0
		gr = clampf(move_toward(gr, aim, rate), -MAX_GRADE, MAX_GRADE)
		zh[k] = h
		h += gr * STEP
	var len_m := (n - 1) * STEP
	var rise := 0.0
	if way["kind"] == "scenic":
		var pr: Array = AdventureTheme.get_value(theme, "pass_rise", [150.0, 320.0])
		rise = minf(rng.randf_range(pr[0], pr[1]), 0.05 * len_m / PI)
	var dz := h1 - zh[n - 1]
	for k in n:
		var t := float(k) / float(n - 1)
		zh[k] += dz * t * t * t * (t * (t * 6.0 - 15.0) + 10.0) + rise * pow(sin(PI * t), 2.0)
	zh[0] = h0
	zh[n - 1] = h1
	way["ph"] = zh
	way["rise"] = rise


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
	# The hairpins: where the road comes back within half the distance it went along (12 to 36 knots on), and a
	# little either side.
	_hairpin = PackedByteArray()
	_hairpin.resize(int(d["n"]))
	for i in int(d["n"]):
		for gap: int in [12, 24, 36]:
			var j := i + gap
			if j >= int(d["n"]):
				break
			if Vector2(dpx[j] - dpx[i], dpz[j] - dpz[i]).length() < gap * STEP * 0.5:
				for k in range(maxi(0, i - 4), mini(int(d["n"]), j + 5)):
					_hairpin[k] = 1
				break


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
## the forks' ways, the tunnels), with the ways picked at forks `picks` ({fork: way}): its
## _assemble_path can run on a worker thread while this route is still ridden and built on (it
## takes a tenth of a second and more on a long road: on the main thread that was a hitch for
## everyone at once, as the crew's pick reached them all together). Then hand it to take_path.
func path_copy(picks: Dictionary) -> AdventureRoute:
	var r := AdventureRoute.new()
	r._def = _def
	r.forks = forks
	r.tunnels = tunnels
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
	eq = r.eq
	tun_k = r.tun_k
	slope_k = r.slope_k
	sections = r.sections
	chunk_surface = r.chunk_surface
	chunk_name = r.chunk_name
	chunk_limit = r.chunk_limit
	_layout = r._layout
	total = r.total
	surfaces = r.surfaces
	tunnels_on = r.tunnels_on
	_grid = r._grid
	_reach_grid = r._reach_grid
	_reach_lock.lock()
	_reach_known = {}   # the road past the fork counts now (see land_reach)
	_reach_lock.unlock()
	_assemble_sites()


## The path's arrays, its pieces, surfaces and tunnels, and its grids (see _assemble).
func _assemble_path() -> void:
	var d: Dictionary = _def
	px = PackedFloat64Array()
	pz = PackedFloat64Array()
	ph = PackedFloat64Array()
	hd = PackedFloat64Array()
	curv = PackedFloat32Array()
	width = PackedFloat32Array()
	base = PackedFloat32Array()
	eq = PackedInt32Array()
	tun_k = PackedInt32Array()
	slope_k = PackedInt32Array()
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
			for k in range(1, n):
				eq.append(_way_eq(fk, way, k))
				tun_k.append(-1)
				slope_k.append(-1)
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
	# The tunnels on the path as it runs now.
	tunnels_on = []
	var k := 0
	while k < tun_k.size():
		if in_tunnel(k):
			var k0 := k
			while k + 1 < tun_k.size() and in_tunnel(k + 1):
				k += 1
			tunnels_on.append({"s0": k0 * STEP, "s1": k * STEP, "id": tun_k[k0]})
		k += 1
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
	for j in range(a, b + 1):
		eq.append(j)
	tun_k.append_array((d["tun_k"] as PackedInt32Array).slice(a, b + 1))
	slope_k.append_array((d["slope_k"] as PackedInt32Array).slice(a, b + 1))
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
