class_name AdventureRoute
extends RefCounted
## The road of an adventure ride, laid out whole along the real road the crew planned (RealPack, see
## RoutePlanner) before anyone sets off, so every player's game has the very same road: its centre
## line (a knot every STEP metres, in doubles: the route runs for a hundred kilometres and more),
## its height, width and bends, its surfaces, and the sites along it (fuel stations, stops and the
## real junctions). Distances (s) are along the road from the start.
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
## The stops the map's own places beside the road become (RealPack.pois kind -> site kind): every one of them is a stop
## (the cafes and pubs no nearer than FOOD_GAP to the last, so a town's high street isn't a row of them).
const REAL_STOPS := {"fuel": "fuel", "cafe": "cafe", "pub": "cafe", "layby": "layby", "viewpoint": "viewpoint"}
const FOOD_GAP := 1500.0
## The longest the road goes (m) without a filling station before a made-up one is put in the gap.
const FUEL_GAP := 60000.0
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
## How much slower than on tarmac the road's taken on each surface (the traffic's pace off the tarmac).
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
## Every knot of the road, filed in a grid like _grid: x, z, height and half width in flat arrays (index = knot).
var _sgrid := {}
var _sx := PackedFloat64Array()
var _sz := PackedFloat64Array()
var _sh := PackedFloat32Array()
var _sw := PackedFloat32Array()
## The sea round the region (coastal), and the snow line over the tops (alpine; INF without).
var sea := false
var snow_line := INF
## The theme's colours: {"land", "patch", "verge", "road"} -> {surface: Color} (see AdventureSurface); on a real road the
## whole look of the place instead (PlaceLook: its cover, plants, fields, sky and weather besides).
var look := {}
## A real road's frame, (lat, lon) of its (0, 0) (its terrain's), or ZERO.
var frame := Vector2.ZERO
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
	frame = Vector2(pack.terrain.lat0, pack.terrain.lon0) if pack.terrain else Vector2.ZERO
	look = PlaceLook.for_pack(pack, PlaceLook.month_now())
	snow_line = float(look["snow_line"])
	length = clampf(km, 1.0, maxf(pack.max_km(), 1.0)) * 1000.0
	total = length + pack.run_out_m
	var n := mini(int(ceil(total / STEP)) + 1, pack.x.size())
	total = (n - 1) * STEP
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "adventure_road", theme, pack.id])
	patches = FastNoiseLite.new()
	patches.seed = seed + 1
	patches.frequency = 1.0 / float(look.get("field_m", 90.0))
	patches.fractal_octaves = 2
	sites.clear()
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
	# Fuel and the stops, only where the road is straight and level enough to pull in: the map's own filling stations,
	# cafes, lay-bys and viewpoints beside the road, a made-up filling station only where the map has none for FUEL_GAP,
	# and a bed every so often (at a real inn or campsite where there's one near).
	_real_stops()
	_plan_fuel_gaps(rng)
	AdventureStops.plan_beds(self)
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
	_lie_of_land()   # (again: the road's been levelled through the stops since)
	_index_sites()
	_build_static_grid()
	_build_grid()
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




## Real places the planned stops take over: each fuel station, cafe, inn, campsite, lay-by and viewpoint the planner
## made up moves to the nearest real one of its sort beside the road within ADOPT_REACH (and takes its side and its
## name when it has one we can print), so the ride stops at real filling stations and cafes where the map has them
## and at made-up ones where it doesn't. Each real place is taken once.
func _adopt_pois() -> void:
	var taken := {}
	for st in sites:
		var roles: Array = ADOPT_ROLES.get(str(st["kind"]), [])
		if roles.is_empty() or st.has("from_map"):
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
		if at < 0.0 and st.has("from_map"):
			continue   # (the map's own place, with nowhere to pull in beside it: left out, not moved away)
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
			if at > 300.0 and at < length - 300.0 and _fit_for_stop(int(round(at / STEP))) \
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

## Marks a site (a fuel station, a town, a stop) at `s` metres on `side` (1 the right, -1 the left): the land there
## is kept flat at the road's height `flat` metres out past the verge.
func add_site(kind: String, s: float, side := 1, flat := 30.0, site_name := "", keep := SITE_KNOTS) -> Dictionary:
	var site := {"kind": kind, "s": s, "i": clampi(int(round(s / STEP)), 0, maxi(0, px.size() - 1)), "side": signi(side) if side != 0 else 1,
		"flat": flat, "name": site_name, "keep": keep}
	sites.append(site)
	sites.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
	return site


## Gives every site its knot afresh (the stops have moved since they were marked: _fit_stops), in order along the road.
func _index_sites() -> void:
	for st in sites:
		st["i"] = clampi(int(round(float(st["s"]) / STEP)), 0, px.size() - 1)
	sites.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))


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
	var n := px.size()
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
## it. A stretch nearer than 160 m along counts too where the land at (x, z), `a` m
## out from its own knot, is much nearer it than its own centre line (which only a stretch that has
## come back round can be): the other leg of a hairpin, or the next in a stack of them or of a
## switchback (a real road's are often only 90 to 120 m apart along the road and 20 m apart
## across), whose land otherwise stood up through this road by as much as ten metres.
func _other_road_limit(i: int, x: float, z: float, a := 0.0) -> float:
	var limit := INF
	var cx := int(floor(x / GRID))
	var cz := int(floor(z / GRID))
	var m := a * 0.8 - 1.0
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				var near := absi(j - i) < 40
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
					if absi(j - i) <= 40:
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
	var m := minf(r, a * 0.8 - 1.0)
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			for j in _sgrid.get(Vector2i(gx, gz), PackedInt32Array()):
				var d2 := (_sx[j] - x) * (_sx[j] - x) + (_sz[j] - z) * (_sz[j] - z)
				if absi(j - i) >= 40:
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


## A stop at every filling station, cafe, lay-by and viewpoint the map has beside the road (REAL_STOPS), on its side
## of the road and under its own name, clear of the others (AdventureStops.CLEAR). Marked "from_map": one with no
## straight, level stretch near it is left out rather than moved away (_fit_stops).
func _real_stops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "real_stops", real.id])
	var food_last := -INF
	for poi: Dictionary in real.pois:
		var kind := str(REAL_STOPS.get(str(poi["kind"]), ""))
		if kind == "":
			continue
		var s := float(int(poi["k"]) * STEP)
		if s < 600.0 or s > length - 400.0 or (kind == "cafe" and s - food_last < FOOD_GAP) or not AdventureStops._clear(self, s):
			continue
		var name := str(poi.get("name", ""))
		if name == "":
			name = "Fuel" if kind == "fuel" else AdventureStops._name(rng, kind)
		var st := add_site(kind, s, 1 if float(poi["lat"]) >= 0.0 else -1, 30.0 if kind == "fuel" else float(AdventureStops.FLAT[kind]), name)
		if kind != "fuel":
			st["stop"] = true
			st["seed"] = rng.randi()
		st["real"] = true
		st["from_map"] = true
		st["planned_s"] = s
		st["planned_name"] = name
		if kind == "cafe":
			food_last = s


## A made-up filling station in every stretch the map leaves without one for longer than FUEL_GAP (from the start, between
## two, and on to the destination), spaced FUEL_EVERY through it; one halfway on a ride with none at all.
func _plan_fuel_gaps(rng: RandomNumberGenerator) -> void:
	var at: Array[float] = [0.0]
	for st in sites_of("fuel"):
		at.append(float(st["s"]))
	at.append(length)
	if at.size() == 2:
		add_site("fuel", snappedf(clampf(rng.randf_range(FUEL_FIRST[0], FUEL_FIRST[1]), 0.0, length * 0.5), STEP), 1, 30.0, "Fuel")
		at.insert(1, float(sites_of("fuel")[0]["s"]))
	for k in at.size() - 1:
		var a := at[k]
		var b := at[k + 1]
		if b - a <= FUEL_GAP:
			continue
		var s := a + rng.randf_range(FUEL_EVERY[0], FUEL_EVERY[1])
		while s < b - FUEL_EVERY[0] * 0.5 and s < length - 3000.0:
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


## Files every knot of the road in the static grid (its index the knot's): the land and scenery keep clear of it.
func _build_static_grid() -> void:
	_sgrid = {}
	_sx = px.duplicate()
	_sz = pz.duplicate()
	_sh = PackedFloat32Array()
	_sw = PackedFloat32Array()
	_sh.resize(px.size())
	_sw.resize(px.size())
	for j in px.size():
		_sh[j] = ph[j]
		_sw[j] = width[j] * 0.5
		var key := Vector2i(int(floor(px[j] / GRID)), int(floor(pz[j] / GRID)))
		if not _sgrid.has(key):
			_sgrid[key] = []
		(_sgrid[key] as Array).append(j)
	for key in _sgrid:
		_sgrid[key] = PackedInt32Array(_sgrid[key])


# ---------------------------------------------------------------------------- the map

## The road for a map, a chunk at a time: [{pts (route frame x z, every `every` knots), surface}].
func map_lines(every := 8) -> Array:
	var out := []
	var b := px.size() - 1
	var k := 0
	while k < b:
		var e := mini(b, (k / CHUNK_KNOTS + 1) * CHUNK_KNOTS)
		var pts := PackedVector2Array()
		var j := k
		while j < e:
			pts.append(Vector2(px[j], pz[j]))
			j += every
		pts.append(Vector2(px[e], pz[e]))
		out.append({"pts": pts, "surface": chunk_surface[clampi(k / CHUNK_KNOTS, 0, chunk_surface.size() - 1)]})
		k = e
	return out


## Every site along the road: [{site, x, z (route frame)}].
func map_sites() -> Array:
	var out := []
	for st in sites:
		var j := clampi(int(st["i"]), 0, px.size() - 1)
		out.append({"site": st, "x": px[j], "z": pz[j]})
	return out

