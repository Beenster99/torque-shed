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
const CHUNK_LEN := STEP * CHUNK_KNOTS
const MAX_HEADING := deg_to_rad(80.0)
## Road beyond the destination, so the finish isn't the edge of the world.
const RUN_OUT := 480.0
const KINDS: Array[String] = ["straight", "sweeping", "curvy", "very_curvy"]
const KIND_NAMES := {"straight": "Straight", "sweeping": "Sweeping bends", "curvy": "Curvy", "very_curvy": "Very curvy"}
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
const PACE := {"straight": 90.0, "sweeping": 78.0, "curvy": 58.0, "very_curvy": 40.0}
const PACE_SURF := {"tarmac": 1.0, "gravel": 0.68, "sand": 0.5, "snow": 0.5}

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
## [{kind, s, i, side, flat, name}] sorted by s: see add_site.
var sites: Array = []
var _grid := {}
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
var _noise: FastNoiseLite
var _noise_fine: FastNoiseLite
var _noise_far: FastNoiseLite


## Plans the whole road for `seed` and `km`. `extra_sites` ([{kind, s, side, flat}]) are kept
## straight and level like the fuel stations, for whatever is to be built there.
func plan(seed: int, km: float, theme_name := "varied", extra_sites: Array = []) -> void:
	seed_value = seed
	theme = theme_name
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
	_plan_surfaces(rng, n)
	_plan_bends(rng, n)
	_plan_heights(rng, n)
	_integrate(n)
	_stash_default()
	for f in forks.size():
		_plan_ways(f)
	_build_static_grid()
	_planned = true
	_assemble()


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
	if a <= e + 0.9:
		return road_h - (0.05 if a > e else 0.0)
	var flat := _site_flat(i, signf(lat))
	var t := smoothstep(e + 1.5 + flat, e + 14.0 + flat * 1.4, a)
	var h := lerpf(road_h - 0.12, natural_height(i, x, z, a), t)
	return minf(h, _other_road_limit(i, x, z))


## The lie of the land at (x, z), `a` metres from the road beside knot `i`.
func natural_height(i: int, x: float, z: float, a: float) -> float:
	var surf := surface_at_s(i * STEP)
	var hills := {"tarmac": 22.0, "gravel": 34.0, "sand": 18.0, "snow": 55.0}.get(surf, 25.0) as float
	var h := base[i] + _noise.get_noise_2d(x, z) * hills + _noise_fine.get_noise_2d(x, z) * 2.5
	if surf == "sand":
		h += absf(_noise_fine.get_noise_2d(x * 0.35, z * 0.9)) * 6.0   # dunes
	# Higher ground rising away from the road for the skyline, mountains in the snow.
	var far := smoothstep(70.0, 420.0, a)
	var lift := {"snow": 160.0, "gravel": 90.0}.get(surf, 55.0) as float
	h += far * lift * (0.45 + 0.55 * (_noise_far.get_noise_2d(x, z) * 0.5 + 0.5))
	return h


## Keeps the land under the road where another stretch of it (a bend that doubles back, more
## than SITE_KNOTS... 160 m along) passes close by: at most that road's height just under its
## verge, rising gently away from it. Every way at every fork counts, taken or not, so the land
## comes out the same whichever is chosen (see eq).
func _other_road_limit(i: int, x: float, z: float) -> float:
	var limit := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	var e := eq[i] if i < eq.size() else i
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				if absi(_seq[j] - e) < 40:
					continue
				var d := sqrt((_sx[j] - x) * (_sx[j] - x) + (_sz[j] - z) * (_sz[j] - z))
				var reach := _sw[j] + 2.0
				if d < reach + 40.0:
					limit = minf(limit, _sh[j] - 0.35 + maxf(0.0, d - reach) * 0.7)
	return limit


## How much further than usual the land stays flat beside knot `i` on `side`, for a site there.
func _site_flat(i: int, side: float) -> float:
	var out := 0.0
	for st in sites:
		var k := absi(int(st["i"]) - i)
		if k < SITE_KNOTS and float(st["side"]) == side:
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


## How far the land may reach on the inside of a bend at knot `i` on `side` (1 right, -1 left)
## before its cross-sections would fold over each other: a little short of the tightest radius
## near it, growing again with distance from that bend. INF where there's no bend that way.
func inside_reach(i: int, side: int) -> float:
	var out := INF
	for j in range(maxi(0, i - 50), mini(curv.size(), i + 51)):
		var k := curv[j]
		if absf(k) > 1e-5 and signi(int(signf(k))) == side:
			out = minf(out, 0.85 / absf(k) + absi(i - j) * STEP * 0.6)
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
				bag = SURFACE_BAG.duplicate()
				for k in range(bag.size() - 1, 0, -1):   # shuffled with our own rng, the same everywhere
					var j := rng.randi_range(0, k)
					var tmp := bag[k]
					bag[k] = bag[j]
					bag[j] = tmp
			surf = bag.pop_back()
			if surf == last and not bag.is_empty():
				bag.push_front(surf)
				surf = bag.pop_back()
		var span := maxi(4, int(rng.randf_range(SURFACE_LEN[0], SURFACE_LEN[1]) / CHUNK_LEN))
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
	while st["i"] < n - 1:
		var i0: int = st["i"]
		var kind := "straight"
		if i0 > 0:
			kind = _weighted(rng, KIND_WEIGHTS)
		var spec: Dictionary = BENDS[kind]
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
			for k in tk:
				_put(st, sign / r * (k + 0.5) / tk)
			for k in ck:
				_put(st, sign / r)
			for k in tk:
				_put(st, sign / r * (tk - k - 0.5) / tk)
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


func _plan_heights(rng: RandomNumberGenerator, n: int) -> void:
	ph.resize(n)
	var h := 140.0
	var g := 0.0
	var target := 0.0
	var seg_end := 0
	for i in n:
		if i >= seg_end:
			var kind := kind_at_s(i * STEP)
			var steep := {"straight": 3.0, "sweeping": 6.0, "curvy": 8.0, "very_curvy": 10.0}.get(kind, 5.0) as float
			target = rng.randf_range(0.25, 1.0) * steep / 100.0 * (1.0 if rng.randf() < 0.5 else -1.0)
			if rng.randf() < 0.22:
				target = 0.0
			seg_end = i + int(rng.randf_range(300.0, 1400.0) / STEP)
		var aim := target
		if h > 950.0:
			aim = -absf(target) - 0.02
		elif h < 50.0:
			aim = absf(target) + 0.02
		if _site_near(i - 30, 150):
			aim = 0.0   # level for a site, from well before it
		g = move_toward(g, aim, 0.0012)
		ph[i] = h
		h += g * STEP


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
	# The lie of the land: the road's height averaged over 200 m either way.
	base.resize(n)
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	for i in n:
		sums[i + 1] = sums[i] + ph[i]
	for i in n:
		var a := maxi(0, i - 50)
		var b := mini(n, i + 51)
		base[i] = (sums[b] - sums[a]) / float(b - a)
	for st in sites:
		st["i"] = clampi(int(round(float(st["s"]) / STEP)), 0, n - 1)


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
		"chunk_surface": chunk_surface.duplicate(), "total": total, "n": px.size()}
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
	# The letters, and which way each points off at the fork (by how it bears 700 m on).
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
	var bends: Dictionary = BENDS["sweeping"]
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
			bends = BENDS[sk]
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
	var sandy := rng.randf() < 0.4
	for c in chunks:
		var ct := (c + 0.5) / chunks
		var surf := "tarmac"
		if kind == "gravel":
			surf = "sand" if sandy and ct > 0.4 and ct < 0.62 else "gravel"
		elif float(way["rise"]) > 120.0 and ct > 0.38 and ct < 0.62:
			surf = "snow"
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
	for k in n:
		if k >= seg_end:
			var kind := _kind_in(way["sections"], k * STEP)
			var steep := {"straight": 3.0, "sweeping": 6.0, "curvy": 8.0, "very_curvy": 10.0}.get(kind, 5.0) as float
			target = rng.randf_range(0.25, 1.0) * steep / 100.0 * (1.0 if rng.randf() < 0.5 else -1.0)
			if rng.randf() < 0.22:
				target = 0.0
			seg_end = k + int(rng.randf_range(300.0, 1400.0) / STEP)
		var aim := target
		if k < JUNCTION_KNOTS + 10 or k > n - JUNCTION_KNOTS - 40 or _site_near(k - 30, 150, way["sites"]):
			aim = 0.0
		gr = move_toward(gr, aim, 0.0012)
		zh[k] = h
		h += gr * STEP
	var len_m := (n - 1) * STEP
	var rise := 0.0
	if way["kind"] == "scenic":
		rise = minf(rng.randf_range(150.0, 320.0), 0.05 * len_m / PI)
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
	var d: Dictionary = _def
	px = PackedFloat64Array()
	pz = PackedFloat64Array()
	ph = PackedFloat64Array()
	hd = PackedFloat64Array()
	curv = PackedFloat32Array()
	width = PackedFloat32Array()
	base = PackedFloat32Array()
	eq = PackedInt32Array()
	sections = []
	chunk_surface = []
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
			for sec in way["sections"]:
				sections.append({"s0": p0 + float(sec["s0"]), "s1": p0 + float(sec["s1"]), "kind": sec["kind"], "width": sec["width"]})
			chunk_surface.append_array(way["chunk_surface"])
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
	_assemble_sites()


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
	var s0 := maxi(a - 1, 0) * STEP
	var s1 := b * STEP
	for sec in d["sections"]:
		if float(sec["s1"]) > s0 and float(sec["s0"]) < s1:
			sections.append({"s0": maxf(float(sec["s0"]), s0) + shift, "s1": minf(float(sec["s1"]), s1) + shift, "kind": sec["kind"], "width": sec["width"]})
	var cs: Array = d["chunk_surface"]
	for ci in range(maxi(a - 1, 0) / CHUNK_KNOTS, mini(int(ceil(float(b) / CHUNK_KNOTS)), cs.size())):
		chunk_surface.append(cs[ci])


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
