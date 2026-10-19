class_name AdventureRoute
extends RefCounted
## The road of an adventure ride, planned whole from its seed and length before anyone sets
## off, so every player's game has the very same road: its centre line (a knot every STEP
## metres, in doubles: the route runs for a hundred kilometres and more), its height, width and
## bends, its surfaces, and the sites along it (fuel stations now; towns, stops and forks later).
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
	sites.clear()
	_plan_fuel(rng)
	AdventureStops.plan(self)
	add_site("start", 48.0, 1, 0.0, "Start")
	add_site("finish", length, 1, 0.0, "Destination")
	for e in extra_sites:
		add_site(str(e.get("kind", "site")), float(e.get("s", 0.0)), int(e.get("side", 1)), float(e.get("flat", 20.0)),
			str(e.get("name", "")))
	_plan_surfaces(rng, n)
	_plan_bends(rng, n)
	_plan_heights(rng, n)
	_integrate(n)
	_build_grid()


## Marks a site (a fuel station, later a town, a stop or a fork) at `s` metres on `side` (1 the
## right, -1 the left): the land there is kept flat at the road's height `flat` metres out past
## the verge. Sites added before plan() also get a straight, level stretch of road.
func add_site(kind: String, s: float, side := 1, flat := 30.0, site_name := "") -> Dictionary:
	var site := {"kind": kind, "s": s, "i": clampi(int(round(s / STEP)), 0, maxi(0, px.size() - 1)), "side": signi(side) if side != 0 else 1,
		"flat": flat, "name": site_name}
	sites.append(site)
	sites.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
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
## verge, rising gently away from it.
func _other_road_limit(i: int, x: float, z: float) -> float:
	var limit := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
				if absi(j - i) < 40:
					continue
				var d := sqrt((px[j] - x) * (px[j] - x) + (pz[j] - z) * (pz[j] - z))
				var reach := width[j] * 0.5 + 2.0
				if d < reach + 40.0:
					limit = minf(limit, ph[j] - 0.35 + maxf(0.0, d - reach) * 0.7)
	return limit


## How much further than usual the land stays flat beside knot `i` on `side`, for a site there.
func _site_flat(i: int, side: float) -> float:
	var out := 0.0
	for st in sites:
		var k := absi(int(st["i"]) - i)
		if k < SITE_KNOTS and float(st["side"]) == side:
			out = maxf(out, float(st["flat"]) * (1.0 - smoothstep(SITE_KNOTS * 0.5, SITE_KNOTS, k)))
	return out


## The distance from route-frame (x, z) to the road's nearest centre line, less its half width
## (negative on the road), looking only at knots filed near it.
func clearance(x: float, z: float) -> float:
	var best := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
				var d := sqrt((px[j] - x) * (px[j] - x) + (pz[j] - z) * (pz[j] - z)) - width[j] * 0.5
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
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _grid.get(Vector2i(gx, gz), PackedInt32Array()):
				if absi(j - i) >= 40 and (px[j] - x) * (px[j] - x) + (pz[j] - z) * (pz[j] - z) < r * r:
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


func _site_near(i: int, knots: int) -> bool:
	for st in sites:
		var si: int = int(round(float(st["s"]) / STEP))
		if si + SITE_KNOTS >= i and si - SITE_KNOTS <= i + knots:
			return true
	return false


func _site_end(i: int, knots: int) -> int:
	var out := i + 1
	for st in sites:
		var si: int = int(round(float(st["s"]) / STEP))
		if si + SITE_KNOTS >= i and si - SITE_KNOTS <= i + knots:
			out = maxi(out, si + SITE_KNOTS + 1)
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
