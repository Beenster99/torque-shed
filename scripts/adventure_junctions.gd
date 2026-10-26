class_name AdventureJunctions
extends RefCounted
## The junctions along an adventure road (Simon: "occasional roundabouts, cross roads, side roads
## joining and traffic lights for the towns"), where the real map has them (RealPack.junctions): a
## side road joins (a T junction), two cross (crossroads), the road goes round a roundabout (an
## island with kerbs, chevrons and its signs) or a mini roundabout (a white dome painted on the
## road), and some have traffic lights cycling red, red and amber, green, amber (the clock is the
## host's: see AdventureTraffic). The side roads are short stubs of lane that bend off into the
## scenery; traffic turns off down them and comes out of them (TrafficStream), stops at the lights
## and gives way at the roundabouts.
##
## Each is a site (AdventureRoute.add_site, kind KIND) laid out with the road, so it's the same on
## every player's game. The site
## carries its "type" (TYPES), "lights", its "arms" ([{side (1 the right, -1 the left), skew
## (degrees off square), bend (degrees it turns by its end), len (m), w (m), surf, name}]), for a
## roundabout the island's radius "ri", the road's outer radius "ro" and the traffic's circling
## radius "rc", and once the road's laid (lay_out) each arm's centre line "arm_geo" (points every
## ARM_STEP metres from the main road's edge out, relative to the junction's middle in the route
## frame's axes, on the land).
##
## The main road through a roundabout is the "straight on" exit: clockwise round from where you
## come in, it's the 1st exit with no arm on your left, the 2nd with one (exit_number). The sat nav
## says so (instruction). The road is widened into a ring round the island (widen), and the
## traffic's lanes swing round it (swing).

const KIND := "crossing"
const TYPES: Array[String] = ["tee", "cross", "lights", "mini", "roundabout"]
const NAMES := {"tee": "Side road", "cross": "Crossroads", "lights": "Traffic lights", "mini": "Mini roundabout",
	"roundabout": "Roundabout"}
## Knots kept straight either side (a roundabout needs a little more), and how far out the land
## is kept flat at the road's height round it (m past the verge, both sides).
const KEEP := 12
const KEEP_ROUND := 15
const FLAT := 24.0
## How far a junction keeps from other sites (m) by their kind.
const CLEAR := {"village": 100.0, "village_row": 60.0, "fuel": 170.0, "start": 380.0, "finish": 420.0, "fork": 420.0,
	"junction": 520.0, "crossing": 230.0}
const CLEAR_OTHER := 150.0
## The side roads: how long the stub runs (m), its width, and how far it bends off and is skewed.
const ARM_LEN := [55.0, 85.0]
const ARM_W := [4.4, 5.6]
const LANE_W := 3.2
const ARM_STEP := 3.0
## How far the mouth of a side road sits above the main road's edge (m): just proud of it.
const MOUTH_LIFT := 0.012
## Where a side road's strip has its points across it (-1 one side, 1 the other): enough that its
## mouth follows the curve of a roundabout's ring.
const STUB_ACROSS: Array[float] = [-1.0, -0.6, -0.25, 0.0, 0.25, 0.6, 1.0]
## Roundabouts: the island's radius (m), the ring's width round it, and where the traffic circles.
const ISLAND := [5.0, 7.5]
const RING := 6.8
const CIRCLE := 2.9
const MINI_RO := 5.4
const MINI_RC := 3.4
## The traffic lights' cycle (s): main road green, side road green, amber, all red, red and amber.
const MAIN_GREEN := [16.0, 24.0]
const SIDE_GREEN := [8.0, 12.0]
const AMBER := 3.0
const ALL_RED := 1.5
const RED_AMBER := 1.5
## Light states (light_state): red, red and amber, green, amber.
const RED := 0
const RED_AMBER_ON := 1
const GREEN := 2
const AMBER_ON := 3
## The warning signs this far before a junction (m), and how far its pieces are drawn.
const WARN_BEFORE := 110.0
const FAR := 700.0
const NEAR := 260.0

## The traffic lights' clock (s): the host's, kept by AdventureTraffic (and the crew's set from it).
static var clock := 0.0

static var _lamp_mats := {}


# ---------------------------------------------------------------------------- planning

## Adds the junction site of `kind` at `s` with its `arms` (see the file's comment for what it carries).
static func _add_site(route: AdventureRoute, rng: RandomNumberGenerator, kind: String, s: float, arms: Array, village: float) -> void:
	var round_kind: bool = kind in ["roundabout", "mini"]
	var site := route.add_site(KIND, s, 1, FLAT, NAMES[kind], KEEP_ROUND if round_kind else KEEP)
	site["type"] = kind
	site["lights"] = kind == "lights"
	site["arms"] = arms
	site["both"] = true   # the land's kept flat both sides (AdventureRoute._site_flat)
	site["seed"] = rng.randi()
	site["village"] = village
	if kind == "roundabout":
		var ri := rng.randf_range(ISLAND[0], ISLAND[1])
		site["ri"] = ri
		site["ro"] = ri + RING
		site["rc"] = ri + CIRCLE
	elif kind == "mini":
		site["ri"] = 1.4
		site["ro"] = MINI_RO
		site["rc"] = MINI_RC
	# The lights' own timing: how long each road's green lasts, and where in the cycle it starts.
	site["green"] = [rng.randf_range(MAIN_GREEN[0], MAIN_GREEN[1]), rng.randf_range(SIDE_GREEN[0], SIDE_GREEN[1])]
	site["phase"] = rng.randf() * 60.0


## How far (knots either side) and how much (radians) a real road may bend through a junction we draw on it.
const REAL_WINDOW := 6
const REAL_BEND := deg_to_rad(18.0)


## Puts the real road's junctions in (AdventureRoute.plan_real; `rows` are RealPack.junctions): a site at each place
## a side road joins, with the real side roads as its arms (their sides, skews, classes and names). A real road bends
## through a junction, so a roundabout (the road must go straight on through it)
## stays one only where the road is straight there; elsewhere it's a crossroads or a side road, and one at a corner
## (the road turns more than REAL_BEND through it) is left out. The map doesn't say where the traffic lights are: a
## crossroads in a built-up place (RealPack.COVER "urban") has them. Their own rng, so the rest of the plan is the same with or without them.
static func plan_real(route: AdventureRoute, rows: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([route.seed_value, "real_junctions", route.theme])
	for jn: Dictionary in rows:
		var arms_in: Array = jn["arms"]
		var kind := str(jn["type"])
		var si := int(jn["k"])
		var m := si % AdventureRoute.CHUNK_KNOTS
		if m < 5:
			si += 5 - m
		elif m > 26:
			si -= m - 26
		var s := si * AdventureRoute.STEP
		if s < 450.0 or s > route.length - 450.0:
			continue
		var bend := _bend_through(route, si, KEEP_ROUND)
		if kind in ["roundabout", "mini"] and bend > deg_to_rad(5.0):
			kind = "cross" if arms_in.size() > 1 else "tee"
			if arms_in.is_empty():
				continue
		if _bend_through(route, si, REAL_WINDOW) > REAL_BEND:
			continue   # the road turns here (the sat nav says so): no junction drawn over a corner
		var clear := true
		for st in route.sites:
			if absf(float(st["s"]) - s) < float(CLEAR.get(str(st["kind"]), CLEAR_OTHER)):
				clear = false
				break
		if not clear:
			continue
		var town := route.cover_at(route.px[si], route.pz[si]) == "urban"
		if kind == "cross" and town:
			kind = "lights"
		var arms := []
		for a: Dictionary in arms_in:
			var lane := str(a["surf"]) != "tarmac"
			arms.append({"side": int(a["side"]), "skew": float(a["skew"]), "bend": rng.randf_range(-30.0, 30.0),
				"len": rng.randf_range(ARM_LEN[0], ARM_LEN[1]), "w": float(a["w"]),
				"surf": "gravel" if lane else "tarmac",
				"name": str(a["name"]) if str(a["name"]) != "" else _place_name(rng), "km": rng.randi_range(2, 14)})
		_add_site(route, rng, kind, s, arms, s if town else -1.0)
		if kind == "roundabout" and jn.has("ri"):
			var st := route.sites_of(KIND)[-1] as Dictionary
			st["ri"] = float(jn["ri"])
			st["ro"] = float(jn["ri"]) + RING
			st["rc"] = float(jn["ri"]) + CIRCLE


## How far (radians) the road's heading changes over `knots` knots either side of knot `i`.
static func _bend_through(route: AdventureRoute, i: int, knots: int) -> float:
	var a := maxi(i - knots, 0)
	var b := mini(i + knots, route.hd.size() - 1)
	return absf(wrapf(route.hd[b] - route.hd[a], -PI, PI))


static func _place_name(rng: RandomNumberGenerator) -> String:
	return AdventureStops.NAME_A[rng.randi() % AdventureStops.NAME_A.size()] + AdventureStops.NAME_B[rng.randi() % AdventureStops.NAME_B.size()]


## Widens the road into a ring round each roundabout (and a little for a mini one), its entries
## flared (called once the bends and widths are planned).
static func widen(route: AdventureRoute) -> void:
	for st in route.sites:
		if not st.has("ro"):
			continue
		var si := int(round(float(st["s"]) / AdventureRoute.STEP))   # (the knots aren't laid yet)
		var ro := float(st["ro"])
		var reach := int(ceil((ro + 18.0) / AdventureRoute.STEP))
		for k in range(maxi(0, si - reach), mini(route.width.size(), si + reach + 1)):
			var d := absf(float(k - si)) * AdventureRoute.STEP
			var w0 := route.width[k]
			var ring := 2.0 * sqrt(maxf(ro * ro - d * d, 0.0))
			var flare := w0 + maxf(0.0, ro * 1.25 - w0) * (1.0 - smoothstep(ro * 0.5, ro + 16.0, d))
			route.width[k] = maxf(w0, maxf(ring, flare))


## Lays out each junction's side roads on the land, once the road and its land are planned (the
## end of AdventureRoute.plan_real, the path then the main road at every fork): each arm's centre line
## from the main road's edge (or the ring's) out, skewed and bending as planned, at the land's
## height there. Off the tarmac the side roads are the main road's own surface (a snowy road's
## lanes are snowy too).
static func lay_out(route: AdventureRoute) -> void:
	for st in route.sites_of(KIND):
		var main_surf := route.surface_at_s(float(st["s"]))
		if main_surf != "tarmac":
			for arm in st["arms"]:
				arm["surf"] = main_surf
		var si: int = st["i"]
		var cx := route.px[si]
		var cz := route.pz[si]
		var cy := route.ph[si]
		var h := route.hd[si]
		var e := route.width[si] * 0.5
		var geo := []
		for arm in st["arms"]:
			var side := float(arm["side"])
			var head := h + side * PI * 0.5 + deg_to_rad(float(arm["skew"]))   # the way it runs out, off north
			var pts := PackedVector3Array()
			# From the main road's edge (the ring's, at a roundabout, which is widened to it): the
			# stub is trimmed to the edge where its flared mouth would reach over the tarmac (_stub).
			var x := cos(h) * side * e
			var z := sin(h) * side * e
			var steps := int(float(arm["len"]) / ARM_STEP)
			for k in steps + 1:
				var t := float(k) / steps
				var hit := route.locate(cx + x, cz + z, si)
				var y := cy
				if not hit.is_empty():
					y = route.land_height(int(hit["i"]), float(hit["lat"]), cx + x, cz + z)
				pts.append(Vector3(x, y - cy, z))
				# Square off the road for a few metres, then bending off as planned.
				var turn := head + deg_to_rad(float(arm["bend"])) * smoothstep(0.25, 1.0, t)
				x += sin(turn) * ARM_STEP
				z -= cos(turn) * ARM_STEP
			geo.append(pts)
		st["arm_geo"] = geo


# ---------------------------------------------------------------------------- what they are

## The junction sites with their knot within `pad` knots of knots i0..i1 (the sites are in order:
## found by halves, it's asked for every few things laid out in a chunk).
static func near(route: AdventureRoute, i0: int, i1: int, pad := 0) -> Array:
	var out := []
	var sites: Array = route.sites
	var k := sites.bsearch_custom(i0 - pad, func(st, v): return int(st["i"]) < int(v))
	while k < sites.size() and int(sites[k]["i"]) <= i1 + pad:
		if sites[k]["kind"] == KIND:
			out.append(sites[k])
		k += 1
	return out


## How far either side of a junction's middle (m along the road) the white lines stop.
static func zone(st: Dictionary) -> float:
	if st.has("ro"):
		return float(st["ro"]) + 9.0
	var w := 0.0
	for arm in st["arms"]:
		w = maxf(w, float(arm["w"]))
	return w * 0.5 + (8.0 if st["lights"] else 4.0)


## Whether knot `i` on `side` is across an arm's mouth (no fence, wall or edge line there).
static func mouth(route: AdventureRoute, i: int, side: float, pad := 2.5) -> bool:
	for st in near(route, i, i, 8):
		var d := absf(float(i - int(st["i"]))) * AdventureRoute.STEP
		for arm in st["arms"]:
			if float(arm["side"]) == side and d < float(arm["w"]) * 0.5 / cos(deg_to_rad(float(arm["skew"]))) + pad + 1.5 \
					+ (float(st.get("ro", 0.0)) * 0.5 if st.has("ro") else 0.0):
				return true
	return false


## Whether route-frame (x, z) beside knot `i` is on (or within `keep` of) a side road.
static func on_arm(route: AdventureRoute, i: int, x: float, z: float, keep := 2.0) -> bool:
	for st in near(route, i, i, 30):
		if not st.has("arm_geo"):
			continue
		var si: int = st["i"]
		var p := Vector2(x - route.px[si], z - route.pz[si])
		for k in (st["arms"] as Array).size():
			var pts: PackedVector3Array = st["arm_geo"][k]
			var r := float(st["arms"][k]["w"]) * 0.5 + keep
			for j in pts.size() - 1:
				var a := Vector2(pts[j].x, pts[j].z)
				var b := Vector2(pts[j + 1].x, pts[j + 1].z)
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_squared_to(p) < r * r:
					return true
	return false


## The side road's surface at route-frame (x, z) beside knot `i`, or "" off them.
static func arm_surface(route: AdventureRoute, i: int, x: float, z: float) -> String:
	for st in near(route, i, i, 30):
		if not st.has("arm_geo"):
			continue
		var si: int = st["i"]
		var p := Vector2(x - route.px[si], z - route.pz[si])
		for k in (st["arms"] as Array).size():
			var pts: PackedVector3Array = st["arm_geo"][k]
			var r := float(st["arms"][k]["w"]) * 0.5 + 0.3
			for j in pts.size() - 1:
				if Geometry2D.get_closest_point_to_segment(p, Vector2(pts[j].x, pts[j].z), Vector2(pts[j + 1].x, pts[j + 1].z)).distance_squared_to(p) < r * r:
					return str(st["arms"][k]["surf"])
	return ""


## Whether scenery at route-frame (wx, wz), `lat` off knot `i`, would be in a junction's way: on a
## side road, or in the corners by the mouth where a driver looks along the main road.
static func in_the_way(route: AdventureRoute, i: int, lat: float, wx: float, wz: float, keep := 2.0) -> bool:
	for st in near(route, i, i, 10):
		if absf(float(i - int(st["i"]))) <= 9 and absf(lat) < route.width[i] * 0.5 + 8.0:
			return true
	return on_arm(route, i, wx, wz, keep + 1.0)


## A side road strip's mesh (AdventureProps arrays), with the uv the road texture tiles by.
static func stub_mesh(a: Dictionary) -> ArrayMesh:
	var v: PackedVector3Array = a["v"]
	var uv := PackedVector2Array()
	uv.resize(v.size())
	for k in v.size():
		uv[k] = Vector2(v[k].x, v[k].z) / 3.0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = a["n"]
	arr[Mesh.ARRAY_COLOR] = a["c"]
	arr[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## How far off the centre line (m, unsigned) traffic keeps `ds` metres from a roundabout's middle:
## out round the island (rc beside it), easing back to `lane` on the way in and out. `lane` itself
## away from one.
static func swing(st: Dictionary, ds: float, lane: float) -> float:
	if not st.has("rc"):
		return lane
	var rc := float(st["rc"])
	var reach := rc + 9.0
	var d := absf(ds)
	if d >= reach:
		return lane
	return maxf(lane, lane + (rc - lane) * 0.5 * (1.0 + cos(PI * d / reach)))


## The lights at junction `st` at `t` seconds on the clock: Vector2i(the main road's, the side
## road's), each RED, RED_AMBER_ON, GREEN or AMBER_ON.
static func light_state(st: Dictionary, t: float) -> Vector2i:
	var g: Array = st.get("green", [20.0, 10.0])
	var mg := float(g[0])
	var sg := float(g[1])
	var cycle := mg + AMBER + ALL_RED + RED_AMBER + sg + AMBER + ALL_RED + RED_AMBER
	var p := fposmod(t + float(st.get("phase", 0.0)), cycle)
	if p < mg:
		return Vector2i(GREEN, RED)
	p -= mg
	if p < AMBER:
		return Vector2i(AMBER_ON, RED)
	p -= AMBER
	if p < ALL_RED:
		return Vector2i(RED, RED)
	p -= ALL_RED
	if p < RED_AMBER:
		return Vector2i(RED, RED_AMBER_ON)
	p -= RED_AMBER
	if p < sg:
		return Vector2i(RED, GREEN)
	p -= sg
	if p < AMBER:
		return Vector2i(RED, AMBER_ON)
	p -= AMBER
	if p < ALL_RED:
		return Vector2i(RED, RED)
	return Vector2i(RED_AMBER_ON, RED)


## Where traffic going `dir` (+1 the way s grows) stops for the lights or gives way: metres before
## the junction's middle.
static func stop_line(st: Dictionary) -> float:
	if st.has("ro"):
		return float(st["ro"]) + 0.8
	var w := 0.0
	for arm in st["arms"]:
		w = maxf(w, float(arm["w"]))
	return w * 0.5 + 2.6


## The main road's exit at a roundabout for traffic going `dir`: counted clockwise from where it
## comes in, every arm on its left comes first.
static func exit_number(st: Dictionary, dir: int) -> int:
	var left := 0
	for arm in st["arms"]:
		if int(arm["side"]) == -dir:
			left += 1
	return 1 + left


static func ordinal(n: int) -> String:
	return {1: "1st", 2: "2nd", 3: "3rd"}.get(n, "%dth" % n)


## What the sat nav says coming up to junction `st` going `dir`: "At the roundabout, take the 2nd
## exit", "Straight on at the lights"... ("" for a side road joining, where there's nothing to do).
static func instruction(st: Dictionary, dir := 1) -> String:
	match str(st.get("type", "")):
		"roundabout":
			return "At the roundabout, take the %s exit" % ordinal(exit_number(st, dir))
		"mini":
			return "At the mini roundabout, go straight on"
		"lights":
			return "Straight on at the lights"
		"cross":
			return "Straight on at the crossroads"
	return ""


# ---------------------------------------------------------------------------- the chunk's share

## The junctions' road-surface parts of chunk `data` (AdventureChunk.build; `land` its land rows,
## {side: {v}}): each side road's stub (its mesh and collision, fading off into the land), and the
## paint: give-way lines, stop lines, a mini roundabout's dome.
static func chunk_parts(route: AdventureRoute, i0: int, i1: int, ax: float, az: float, land: Dictionary, out: Dictionary) -> void:
	var arms := {}
	var faces := {}
	var paint := AdventureProps.new_arrays()
	for st in near(route, i0, i1 - 1):
		var si: int = st["i"]
		if si < i0 or si >= i1 or not st.has("arm_geo"):
			continue
		var centre := Vector3(route.px[si] - ax, route.ph[si], route.pz[si] - az)
		for k in (st["arms"] as Array).size():
			var arm: Dictionary = st["arms"][k]
			var surf := str(arm["surf"])
			if not arms.has(surf):
				arms[surf] = AdventureProps.new_arrays()
				faces[surf] = PackedVector3Array()
			_stub(route, st, arm, st["arm_geo"][k], centre, i0, i1, ax, az, land, arms[surf], faces[surf], paint)
		_road_paint(route, st, centre, paint)
	out["arms"] = arms
	out["arm_faces"] = faces
	out["paint"] = paint


## One side road's stub: a strip draped on the chunk's own land (so it never sinks into it or
## floats), flared at the mouth, narrowing and fading into the land's colour as it bends off;
## a tarmac one with its give-way (or stop) line. It starts at the main road's edge and never
## reaches over it (Simon: "Dirt tracks that join the side of the road should start at the edge
## and not cross over"): its mouth lies along the edge, level with it, and anything of its flare
## that would lie on the tarmac is pulled back out to the edge, so the main road's surface (and
## what the tyres feel on it) is its own right up to the edge.
static func _stub(route: AdventureRoute, st: Dictionary, arm: Dictionary, pts: PackedVector3Array, centre: Vector3, i0: int,
		i1: int, ax: float, az: float, land: Dictionary, a: Dictionary, f: PackedVector3Array, paint: Dictionary) -> void:
	var surf := str(arm["surf"])
	var road_col: Color = route.look["road"].get(surf, AdventureSurface.ROAD_COLOR[surf])
	var land_col: Color = route.look["verge"].get(route.surface_at_s(float(st["s"])), Color(0.34, 0.38, 0.2))
	var side := float(arm["side"])
	var si: int = st["i"]
	var hw := float(arm["w"]) * 0.5
	var n := pts.size()
	var rows := []
	var mouth := 0   # the first row drawn: the last that lies wholly on the edge
	# Near the junction the main road runs straight: how far out its edge is (at its widest, the
	# middle of a roundabout's ring), to tell cheaply which points can't be on it.
	var mid := STUB_ACROSS.size() / 2
	var right := Vector3(cos(route.hd[si]), 0.0, sin(route.hd[si])) * side
	var reach := edge_at_s(route, float(st["s"])) + 0.5
	for j in n:
		var p := pts[j] + Vector3(centre.x, 0.0, centre.z)
		var dirv := (pts[mini(j + 1, n - 1)] - pts[maxi(j - 1, 0)])
		dirv.y = 0.0
		dirv = dirv.normalized()
		var across := Vector3(-dirv.z, 0.0, dirv.x)
		var t := float(j) / (n - 1)
		var w := hw * (1.0 + 1.1 * (1.0 - smoothstep(0.0, 0.12, t))) * lerpf(1.0, 0.7, smoothstep(0.7, 1.0, t))
		var row := []
		var cut := []
		var on_edge := 0
		for q: float in STUB_ACROSS:
			var v := p + across * w * q
			var c := []
			if j == 0 or (v - centre).dot(right) < reach:
				c = _to_edge(route, v, dirv, side, si, ax, az, j == 0)
			if not c.is_empty():
				v = c[0]
				on_edge += 1
			row.append(v)
			cut.append(not c.is_empty())
		if on_edge == STUB_ACROSS.size():
			mouth = j
		# Draped on the land as it always was, by its edges and middle (the land under them), the
		# points between on the lines joining those, the middle crowned a little.
		var last := STUB_ACROSS.size() - 1
		for k: int in [0, mid, last]:
			if not cut[k]:
				var v: Vector3 = row[k]
				v.y = _land_y(route, land, i0, i1, ax, az, v) + 0.05
				row[k] = v
		for k in last:
			if k == 0 or k == mid or cut[k]:
				continue
			var k0 := 0 if k < mid else mid
			var k1 := mid if k < mid else last
			var u := (STUB_ACROSS[k] - STUB_ACROSS[k0]) / (STUB_ACROSS[k1] - STUB_ACROSS[k0])
			var v: Vector3 = row[k]
			v.y = lerpf((row[k0] as Vector3).y, (row[k1] as Vector3).y, u) + 0.03 * (1.0 - STUB_ACROSS[k] * STUB_ACROSS[k])
			row[k] = v
		if not cut[mid]:
			row[mid] = (row[mid] as Vector3) + Vector3.UP * 0.03
		var fade := smoothstep(0.6, 1.0, t)
		rows.append([row, road_col.lerp(land_col, fade * 0.85), fade])
	for j in range(mouth, n - 1):
		var r0: Array = rows[j][0]
		var r1: Array = rows[j + 1][0]
		for q in STUB_ACROSS.size() - 1:
			AdventureProps._quad(a, r0[q], r0[q + 1], r1[q + 1], r1[q], rows[j][1])
			f.append_array([r0[q], r1[q], r1[q + 1], r0[q], r1[q + 1], r0[q + 1]])
	# Give way: a double dashed line across the lane coming in (the right of the way out), or
	# the stop line at the lights.
	if n > mouth + 3 and surf == "tarmac":
		var r: Array = rows[mouth + 1][0]
		var dirv: Vector3 = (rows[mouth + 2][0][mid] - rows[mouth + 1][0][mid])
		dirv.y = 0.0
		dirv = dirv.normalized()
		var lit: bool = st["lights"]
		for line in ([0.0] if lit else [0.0, 0.5]):
			var c0: Vector3 = (r[mid] as Vector3).lerp(r[-1], 0.05) + dirv * (0.4 + line) + Vector3.UP * 0.02
			var c1: Vector3 = (r[mid] as Vector3).lerp(r[-1], 0.95) + dirv * (0.4 + line) + Vector3.UP * 0.02
			if lit:
				_strip(paint, c0, c1, 0.3, Color(0.9, 0.9, 0.86))
			else:
				_dashes(paint, c0, c1, 0.15, 0.6, 0.3)


## The main road's half width (to its edge) at `s`, between the knots as its mesh is drawn.
static func edge_at_s(route: AdventureRoute, s: float) -> float:
	var f := clampf(s / AdventureRoute.STEP, 0.0, float(route.width.size() - 1))
	var i := mini(int(f), route.width.size() - 2)
	return lerpf(route.width[i], route.width[i + 1], f - i) * 0.5


## Chunk-local `v` of a side road's strip running out along `dirv` on `side` of the main road,
## slid along `dirv` onto the main road's edge (and level with it) where it lies on the tarmac
## (or, with `mouth`, anywhere: its mouth row lies along the edge): [the point], or [] where it
## stays put. Where sliding it runs away (a strip running almost along the road, the road bending
## back on itself near by: once 220 m off, a triangle across the land), it goes straight across to
## the edge instead.
static func _to_edge(route: AdventureRoute, v: Vector3, dirv: Vector3, side: float, si: int, ax: float, az: float,
		mouth: bool) -> Array:
	var hit := route.locate(v.x + ax, v.z + az, si)
	if hit.is_empty():
		return []
	var s := float(hit["s"])
	var e := edge_at_s(route, s)
	var out := float(hit["lat"]) * side   # how far out on the side road's side
	if out >= e and not mouth:
		return []
	# A few goes, as the edge narrows or widens along the way (round a roundabout's ring).
	var s0 := s
	var far := absf(e - out) / 0.2 + 1.0   # (as far as one go below can take it: further is running away)
	var p := v
	for go in 6:
		var h := route.heading_at_s(s)
		var away := (dirv.x * cos(h) + dirv.z * sin(h)) * side   # how fast the strip runs off the road
		p += dirv * (e - out) / maxf(away, 0.2)
		var at := route.locate(p.x + ax, p.z + az, si)
		if at.is_empty():
			break
		s = float(at["s"])
		e = edge_at_s(route, s)
		out = float(at["lat"]) * side
		if absf(e - out) < 0.005:
			break
	if p.distance_to(v) > far:
		s = s0
		e = edge_at_s(route, s)
		out = -INF
	if out < e - 0.005:
		# Still short (running almost along a ring's curve), or run away: straight across the road to its edge.
		var xz := route.xz_at(s, side * e)
		p = Vector3(float(xz[0]) - ax, p.y, float(xz[1]) - az)
	return [Vector3(p.x, route.height_at_s(s) + MOUTH_LIFT, p.z)]


## The land's height at chunk-local `v` as the chunk draws it: along the knots' rows of its land
## mesh either side, between the two rows it falls between (the land_height sum elsewhere).
static func _land_y(route: AdventureRoute, land: Dictionary, i0: int, i1: int, ax: float, az: float, v: Vector3) -> float:
	var hit := route.locate(v.x + ax, v.z + az, clampi(i0 + 16, 0, route.knot_count() - 1))
	if hit.is_empty():
		return v.y
	var i := int(hit["i"])
	var lat := float(hit["lat"])
	var t := float(hit["s"]) / AdventureRoute.STEP - i
	if absf(lat) <= route.width[i] * 0.5:
		return route.height_at_s(float(hit["s"]))
	if i < i0 or i + 1 > i1:
		return route.land_height(i, lat, v.x + ax, v.z + az)
	var side := 1 if lat > 0.0 else -1
	var rows: PackedVector3Array = land[side]["v"]
	var cols := AdventureChunk.land_cols(route)
	var y0 := _row_y(route, rows, cols, i - i0, i, side, absf(lat), ax, az)
	var y1 := _row_y(route, rows, cols, i + 1 - i0, i + 1, side, absf(lat), ax, az)
	return lerpf(y0, y1, clampf(t, 0.0, 1.0))


static func _row_y(route: AdventureRoute, rows: PackedVector3Array, cols: int, r: int, i: int, side: int, a: float, ax: float, az: float) -> float:
	var c := Vector2(route.px[i] - ax, route.pz[i] - az)
	var right := Vector2(cos(route.hd[i]), sin(route.hd[i])) * side
	var prev_a := 0.0
	var prev_y := route.ph[i]
	for k in cols:
		var vi := r * cols + (k if side > 0 else cols - 1 - k)
		var v := rows[vi]
		var va := (Vector2(v.x, v.z) - c).dot(right)
		if va >= a:
			return lerpf(prev_y, v.y, clampf((a - prev_a) / maxf(va - prev_a, 0.01), 0.0, 1.0))
		prev_a = va
		prev_y = v.y
	return prev_y


## The paint on the main road: at a roundabout, give-way lines across each way in; at the lights,
## the stop lines; a mini roundabout's white dome.
static func _road_paint(route: AdventureRoute, st: Dictionary, centre: Vector3, paint: Dictionary) -> void:
	var si: int = st["i"]
	var s := float(st["s"])
	var white := Color(0.9, 0.9, 0.86)
	if str(st["type"]) == "mini":
		var r := float(st["ri"])
		for k in 14:
			var a0 := TAU * k / 14.0
			var a1 := TAU * (k + 1) / 14.0
			AdventureProps._tri(paint, centre + Vector3(0, 0.07, 0), centre + Vector3(cos(a1) * r, 0.03, sin(a1) * r),
				centre + Vector3(cos(a0) * r, 0.03, sin(a0) * r), white)
	if not (st.has("ro") or st["lights"]) or route.surface_at_s(s) != "tarmac":
		return   # (no lines painted on a dirt road)
	var back := stop_line(st)
	for dir: int in [1, -1]:
		var at := s - dir * back
		var e := route.width_at_s(at) * 0.5
		var xa := route.xz_at(at, 0.0)
		var xb := route.xz_at(at, -dir * (e - 0.3))
		var ya := route.height_at_s(at) + AdventureChunk.CROWN + 0.015
		var p0 := Vector3(float(xa[0]) - (route.px[si] - centre.x), ya, float(xa[1]) - (route.pz[si] - centre.z))
		var p1 := Vector3(float(xb[0]) - (route.px[si] - centre.x), ya - AdventureChunk.CROWN, float(xb[1]) - (route.pz[si] - centre.z))
		if st["lights"]:
			_strip(paint, p0, p1, 0.3, white)
		else:
			var fwd := Vector3(sin(route.hd[si]), 0.0, -cos(route.hd[si])) * dir
			_dashes(paint, p0, p1, 0.15, 0.6, 0.3)
			_dashes(paint, p0 - fwd * 0.5, p1 - fwd * 0.5, 0.15, 0.6, 0.3)


## A painted strip `w` wide from `a` to `b`.
static func _strip(arr: Dictionary, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var along := b - a
	along.y = 0.0
	if along.length() < 0.01:
		return
	var across := Vector3(-along.z, 0.0, along.x).normalized() * w * 0.5
	AdventureProps._quad(arr, a + across, b + across, b - across, a - across, col)


## Dashes `w` wide, `dash` long with `gap` between, from `a` to `b`.
static func _dashes(arr: Dictionary, a: Vector3, b: Vector3, w: float, dash: float, gap: float) -> void:
	var len := a.distance_to(b)
	var at := 0.0
	while at < len:
		var e := minf(at + dash, len)
		_strip(arr, a.lerp(b, at / len), a.lerp(b, e / len), w, Color(0.9, 0.9, 0.86))
		at = e + gap


# ---------------------------------------------------------------------------- the nodes

## Junction `site`'s node at `xf` (its middle on the road, local -z along the way s grows, +x to
## the right): the island and its kerbs, chevrons and sign at a roundabout, the warning signs
## before it both ways, fingerposts down the side roads, and the traffic lights (Signals).
static func build(route: AdventureRoute, site: Dictionary, xf: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Junction_%s_%d" % [str(site["type"]), int(site["s"])]
	root.transform = xf
	root.set_meta("site", site)
	var far := AdventureProps.new_arrays()
	var near_a := AdventureProps.new_arrays()
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.set_meta("surface", "tarmac")
	var si: int = site["i"]
	var inv := xf.basis.inverse()
	var kind := str(site["type"])
	var e := route.width[si] * 0.5
	if kind == "roundabout":
		_island(far, near_a, body, site)
	# Warning signs on the left verge before it, both ways.
	for dir: int in [1, -1]:
		var at := float(site["s"]) - dir * WARN_BEFORE
		var lat := -dir * (route.width_at_s(at) * 0.5 + 1.3)
		var xz := route.xz_at(at, lat)
		var p := inv * Vector3(float(xz[0]) - route.px[si], route.height_at_s(at) - route.ph[si], float(xz[1]) - route.pz[si])
		var yaw := route.heading_at_s(at) - route.hd[si]
		var face := Basis(Vector3.UP, -yaw + (0.0 if dir > 0 else PI))   # facing the traffic coming
		_warning(near_a, body, Transform3D(face, p), kind if not site["lights"] else "lights", site)
	# A fingerpost at each side road's mouth, on its far corner, pointing down it.
	var geo: Array = site.get("arm_geo", [])
	for k in geo.size():
		var arm: Dictionary = site["arms"][k]
		var pts: PackedVector3Array = geo[k]
		if pts.size() < 3:
			continue
		var p0 := inv * pts[0]
		var p2 := inv * pts[2]
		var out := Vector3(p2.x - p0.x, 0.0, p2.z - p0.z).normalized()
		var across := Vector3(-out.z, 0.0, out.x)
		var post := p0 + out * 2.0 + across * (float(arm["w"]) * 0.5 + 1.6) * (1.0 if int(arm["side"]) > 0 else -1.0)
		post.y = (inv * pts[1]).y
		_fingerpost(root, near_a, body, post, out, arm)
	if site["lights"]:
		var sig := Signals.new()
		sig.name = "Signals"
		sig.site = site
		root.add_child(sig)
		_signal_heads(route, site, sig, near_a, body, e, inv)
	for part in [["Far", far, FAR], ["Near", near_a, NEAR]]:
		var arr: Dictionary = part[1]
		if (arr["v"] as PackedVector3Array).is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = AdventureProps.to_mesh(arr)
		AdventureChunk._range(mi, float(part[2]) * clampf(Settings.gfx_draw_distance, 0.5, 2.0))
		root.add_child(mi)
	if body.get_child_count() > 0:
		root.add_child(body)
	else:
		body.free()
	return root


## A roundabout's island: a kerb all round, a grassy mound planted with shrubs, chevron boards
## facing each way in and the blue roundabout sign over them; solid to ride into.
static func _island(far: Dictionary, near_a: Dictionary, body: StaticBody3D, site: Dictionary) -> void:
	var ri := float(site["ri"])
	var segs := 28
	var kerb := Color(0.62, 0.62, 0.6)
	var grass := Color(0.24, 0.42, 0.16)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		var stripe := kerb if k % 2 == 0 else Color(0.85, 0.85, 0.82)
		AdventureProps._quad(far, o1 * ri + Vector3.DOWN * 0.1, o0 * ri + Vector3.DOWN * 0.1, o0 * ri + Vector3.UP * 0.16, o1 * ri + Vector3.UP * 0.16, stripe)
		AdventureProps._quad(far, o1 * ri + Vector3.UP * 0.16, o0 * ri + Vector3.UP * 0.16, o0 * (ri - 0.45) + Vector3.UP * 0.16,
			o1 * (ri - 0.45) + Vector3.UP * 0.16, kerb.darkened(0.1))
		# The mound: rising gently to the middle.
		for ring in 3:
			var r0 := (ri - 0.45) * (1.0 - ring / 3.0)
			var r1 := (ri - 0.45) * (1.0 - (ring + 1) / 3.0)
			var y0 := 0.16 + 0.75 * (ring / 3.0)
			var y1 := 0.16 + 0.75 * ((ring + 1) / 3.0)
			AdventureProps._quad(far, o1 * r0 + Vector3.UP * y0, o0 * r0 + Vector3.UP * y0, o0 * r1 + Vector3.UP * y1, o1 * r1 + Vector3.UP * y1,
				grass.darkened(0.06 * ring))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"])
	for k in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.3, ri - 1.6)
		var c := Vector3(cos(a) * r, 0.9 - r / ri * 0.6, sin(a) * r)
		AdventureProps.blob(far, c, Vector3(1.0, 0.8, 1.0) * rng.randf_range(0.6, 1.1),
			[Color(0.16, 0.34, 0.12), Color(0.3, 0.42, 0.14), Color(0.55, 0.3, 0.42)][k % 3], rng.randi())
	# Chevrons facing each way in (on the island's edge, where the traffic first turns), and the
	# blue roundabout sign above.
	for dir: int in [1, -1]:
		var fwd := Vector3(0, 0, -dir)   # local -z is the way s grows
		var p := -fwd * (ri - 0.8)
		var face := Basis(Vector3.UP, 0.0 if dir > 0 else PI)
		var xf := Transform3D(face, p)
		AdventureProps.box(near_a, xf * Transform3D(Basis(), Vector3(-1.0, 0.0, 0.0)), Vector3(0.1, 1.5, 0.1), Color(0.3, 0.3, 0.32))
		AdventureProps.box(near_a, xf * Transform3D(Basis(), Vector3(1.0, 0.0, 0.0)), Vector3(0.1, 1.5, 0.1), Color(0.3, 0.3, 0.32))
		AdventureProps.box(near_a, xf * Transform3D(Basis(), Vector3(0.0, 0.85, 0.05)), Vector3(2.6, 0.6, 0.04), Color(0.05, 0.05, 0.06))
		for c in 3:
			var cx := -0.75 + c * 0.75
			_chevron(near_a, xf, Vector3(cx, 1.15, 0.08), 0.42, Color(0.95, 0.95, 0.92), -1.0)
		AdventureProps.box(near_a, xf * Transform3D(Basis(), Vector3(0.0, 0.0, -0.3)), Vector3(0.1, 2.6, 0.1), Color(0.3, 0.3, 0.32))
		_disc(near_a, xf, Vector3(0.0, 2.3, -0.24), 0.36, Color(0.1, 0.28, 0.72))
		for arrow in 3:
			var ang := TAU * arrow / 3.0 + 0.3
			_chevron(near_a, xf, Vector3(cos(ang) * 0.2, 2.3 + sin(ang) * 0.2, -0.2), 0.12, Color(0.95, 0.95, 0.95), 1.0)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = ri
	cyl.height = 1.2
	cs.shape = cyl
	cs.position = Vector3(0, 0.4, 0)
	body.add_child(cs)


## A white chevron (or arrowhead) `h` high at `p` on board frame `xf`, pointing left (`point` -1).
static func _chevron(arr: Dictionary, xf: Transform3D, p: Vector3, h: float, col: Color, point: float) -> void:
	var tip := xf * (p + Vector3(point * h * 0.45, 0.0, 0.0))
	var top := xf * (p + Vector3(-point * h * 0.15, h * 0.5, 0.0))
	var bot := xf * (p + Vector3(-point * h * 0.15, -h * 0.5, 0.0))
	var top2 := xf * (p + Vector3(-point * h * 0.45, h * 0.5, 0.0))
	var bot2 := xf * (p + Vector3(-point * h * 0.45, -h * 0.5, 0.0))
	var tip2 := xf * (p + Vector3(point * h * 0.15, 0.0, 0.0))
	if point < 0.0:
		AdventureProps._quad(arr, top2, top, tip, tip2, col)
		AdventureProps._quad(arr, tip2, tip, bot, bot2, col)
	else:
		AdventureProps._quad(arr, tip2, tip, top, top2, col)
		AdventureProps._quad(arr, bot2, bot, tip, tip2, col)


## A flat disc of radius `r` at `p` on frame `xf`, facing its +z.
static func _disc(arr: Dictionary, xf: Transform3D, p: Vector3, r: float, col: Color) -> void:
	for k in 14:
		var a0 := TAU * k / 14.0
		var a1 := TAU * (k + 1) / 14.0
		AdventureProps._tri(arr, xf * p, xf * (p + Vector3(cos(a0) * r, sin(a0) * r, 0.0)), xf * (p + Vector3(cos(a1) * r, sin(a1) * r, 0.0)), col)


## A red-bordered warning triangle on a post at `xf` (facing its +z, the traffic coming), with
## what's ahead on it: a roundabout, crossroads, a side road or traffic lights.
static func _warning(arr: Dictionary, body: StaticBody3D, xf: Transform3D, what: String, site: Dictionary) -> void:
	AdventureProps.box(arr, xf, Vector3(0.09, 2.0, 0.09), Color(0.42, 0.42, 0.44))
	var c := Vector3(0.0, 2.35, 0.06)
	var red := Color(0.78, 0.08, 0.06)
	var white := Color(0.96, 0.96, 0.94)
	var black := Color(0.05, 0.05, 0.05)
	var s := 0.62
	AdventureProps._tri(arr, xf * (c + Vector3(-s, -s * 0.55, 0)), xf * (c + Vector3(s, -s * 0.55, 0)), xf * (c + Vector3(0, s * 1.05, 0)), red)
	var w := s * 0.74
	var c2 := c + Vector3(0, -0.04, 0.01)
	AdventureProps._tri(arr, xf * (c2 + Vector3(-w, -w * 0.55, 0)), xf * (c2 + Vector3(w, -w * 0.55, 0)), xf * (c2 + Vector3(0, w * 1.05, 0)), white)
	var g := c + Vector3(0, -0.06, 0.02)
	match what:
		"roundabout", "mini":
			for k in 3:
				var a := TAU * k / 3.0 + PI * 0.5
				_chevron(arr, xf, g + Vector3(cos(a) * 0.14, sin(a) * 0.14, 0), 0.1, black, 1.0)
		"cross":
			AdventureProps._quad(arr, xf * (g + Vector3(-0.04, -0.2, 0)), xf * (g + Vector3(0.04, -0.2, 0)), xf * (g + Vector3(0.04, 0.24, 0)), xf * (g + Vector3(-0.04, 0.24, 0)), black)
			AdventureProps._quad(arr, xf * (g + Vector3(-0.18, 0.0, 0)), xf * (g + Vector3(0.18, 0.0, 0)), xf * (g + Vector3(0.18, 0.08, 0)), xf * (g + Vector3(-0.18, 0.08, 0)), black)
		"tee":
			var side := float(site["arms"][0]["side"]) * (1.0 if xf.basis.z.dot(Vector3(0, 0, 1)) > 0.0 else -1.0)
			AdventureProps._quad(arr, xf * (g + Vector3(-0.04, -0.2, 0)), xf * (g + Vector3(0.04, -0.2, 0)), xf * (g + Vector3(0.04, 0.24, 0)), xf * (g + Vector3(-0.04, 0.24, 0)), black)
			var x0 := 0.0 if side > 0.0 else -0.18
			AdventureProps._quad(arr, xf * (g + Vector3(x0, 0.0, 0)), xf * (g + Vector3(x0 + 0.18, 0.0, 0)), xf * (g + Vector3(x0 + 0.18, 0.08, 0)), xf * (g + Vector3(x0, 0.08, 0)), black)
		"lights":
			AdventureProps._quad(arr, xf * (g + Vector3(-0.07, -0.22, 0)), xf * (g + Vector3(0.07, -0.22, 0)), xf * (g + Vector3(0.07, 0.24, 0)), xf * (g + Vector3(-0.07, 0.24, 0)), black)
			for k in 3:
				_disc(arr, xf, g + Vector3(0, 0.15 - k * 0.15, 0.005), 0.045, [red, Color(0.95, 0.6, 0.05), Color(0.1, 0.7, 0.25)][k])
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, 2.0, 0.12)
	cs.shape = box
	cs.transform = xf * Transform3D(Basis(), Vector3(0, 1.0, 0))
	body.add_child(cs)


## A white fingerpost at `p` pointing `out` down a side road: the place it goes and how far.
static func _fingerpost(root: Node3D, arr: Dictionary, body: StaticBody3D, p: Vector3, out: Vector3, arm: Dictionary) -> void:
	var yaw := atan2(out.x, out.z)
	var xf := Transform3D(Basis(Vector3.UP, yaw - PI * 0.5), p)
	AdventureProps.box(arr, Transform3D(Basis(), p), Vector3(0.12, 2.3, 0.12), Color(0.9, 0.9, 0.88))
	AdventureProps.box(arr, xf * Transform3D(Basis(), Vector3(-0.75, 1.85, 0.0)), Vector3(1.6, 0.32, 0.05), Color(0.94, 0.94, 0.92))
	for face: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "%s  %d" % [str(arm["name"]), int(arm["km"])]
		label.font_size = 44
		label.pixel_size = 0.005
		label.modulate = Color(0.08, 0.08, 0.08)
		label.outline_size = 0
		label.transform = xf * Transform3D(Basis(Vector3.UP, 0.0 if face > 0.0 else PI), Vector3(-0.75, 2.01, 0.035 * face))
		label.visibility_range_end = 90.0
		root.add_child(label)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.14, 2.3, 0.14)
	cs.shape = box
	cs.position = p + Vector3(0, 1.15, 0)
	body.add_child(cs)


## The traffic lights: a head on a pole at the stop line on the left of each way in (the main
## road both ways and each side road), and a second for the main road across the junction. Their
## lamps are the Signals node's to light.
static func _signal_heads(route: AdventureRoute, site: Dictionary, sig: Signals, arr: Dictionary, body: StaticBody3D, e: float, inv: Basis) -> void:
	var back := stop_line(site)
	for dir: int in [1, -1]:
		# local -z is the way s grows: traffic going dir comes from +z * dir.
		var face := Basis(Vector3.UP, 0.0 if dir > 0 else PI)   # +z towards the traffic coming
		var p := Vector3(-dir * (e + 0.7), 0.0, dir * back)
		_head(sig, arr, body, Transform3D(face, p), "main")
		var p2 := Vector3(dir * (e + 0.7), 0.0, -dir * (back + 1.0))
		_head(sig, arr, body, Transform3D(face, p2), "main", 3.0)
	var geo: Array = site.get("arm_geo", [])
	for k in geo.size():
		var pts: PackedVector3Array = geo[k]
		if pts.size() < 3:
			continue
		var arm: Dictionary = site["arms"][k]
		var p0 := inv * pts[1]
		var p2 := inv * pts[3]
		var out := Vector3(p2.x - p0.x, 0.0, p2.z - p0.z).normalized()
		var across := Vector3(-out.z, 0.0, out.x)
		# On the left of the way in (coming back along the arm towards the road).
		var at := p0 + across * (float(arm["w"]) * 0.5 + 0.7) + out * 1.0
		var yaw := atan2(out.x, out.z)
		_head(sig, arr, body, Transform3D(Basis(Vector3.UP, yaw), at), "side")


## One signal head on its pole at `xf` (+z towards the traffic it stops), `y` its height.
static func _head(sig: Signals, arr: Dictionary, body: StaticBody3D, xf: Transform3D, role: String, y := 2.4) -> void:
	var grey := Color(0.2, 0.21, 0.22)
	AdventureProps.box(arr, xf, Vector3(0.12, y + 0.95, 0.12), grey)
	AdventureProps.box(arr, xf * Transform3D(Basis(), Vector3(0.0, y, 0.12)), Vector3(0.34, 0.95, 0.22), Color(0.08, 0.08, 0.09))
	AdventureProps.box(arr, xf * Transform3D(Basis(), Vector3(0.0, y - 0.07, 0.0)), Vector3(0.54, 1.1, 0.03), Color(0.06, 0.06, 0.07))
	# The backing board's white border.
	for sx: float in [-0.27, 0.27]:
		AdventureProps.box(arr, xf * Transform3D(Basis(), Vector3(sx, y - 0.07, 0.02)), Vector3(0.03, 1.1, 0.01), Color(0.95, 0.95, 0.95))
	var lamps := []
	for k in 3:
		var mi := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.1
		disc.bottom_radius = 0.1
		disc.height = 0.03
		disc.radial_segments = 12
		disc.rings = 1
		mi.mesh = disc
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, y + 0.3 - k * 0.3, 0.235))
		mi.material_override = lamp_material(k, false)
		AdventureChunk._range(mi, NEAR * 1.5)
		sig.add_child(mi)
		lamps.append(mi)
	var glow := OmniLight3D.new()
	glow.omni_range = 5.0
	glow.light_energy = 0.0
	glow.shadow_enabled = false
	glow.transform = xf * Transform3D(Basis(), Vector3(0.0, y, 0.6))
	glow.visible = false
	sig.add_child(glow)
	sig.heads.append({"lamps": lamps, "role": role, "glow": glow})
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.14, y + 0.9, 0.14)
	cs.shape = box
	cs.transform = xf * Transform3D(Basis(), Vector3(0.0, (y + 0.9) * 0.5, 0.0))
	body.add_child(cs)


## The lamp material for red (0), amber (1) or green (2), lit or dark: shared by every head.
static func lamp_material(k: int, lit: bool) -> StandardMaterial3D:
	var key := k * 2 + (1 if lit else 0)
	if _lamp_mats.has(key):
		return _lamp_mats[key]
	var col: Color = [Color(1.0, 0.12, 0.06), Color(1.0, 0.62, 0.06), Color(0.15, 1.0, 0.45)][k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.78) if not lit else col
	m.roughness = 0.3
	if lit:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.2
	_lamp_mats[key] = m
	return m


## Lights a junction's signal heads by the clock (AdventureJunctions.clock): the main road's and
## the side roads' each red, red and amber, green or amber; and after dark a little coloured glow
## of the lit lamp on the road under each.
class Signals:
	extends Node3D
	var site: Dictionary
	var heads: Array = []
	var _shown := Vector2i(-1, -1)
	var _night := -1.0

	func _process(_delta: float) -> void:
		var st := AdventureJunctions.light_state(site, AdventureJunctions.clock)
		var night := snappedf(Daylight.current.lamps if Daylight.current else 0.0, 0.05)
		if st == _shown and night == _night:
			return
		_shown = st
		_night = night
		for h in heads:
			var state: int = st.x if h["role"] == "main" else st.y
			var on := [state == AdventureJunctions.RED or state == AdventureJunctions.RED_AMBER_ON,
				state == AdventureJunctions.RED_AMBER_ON or state == AdventureJunctions.AMBER_ON, state == AdventureJunctions.GREEN]
			for k in 3:
				(h["lamps"][k] as MeshInstance3D).material_override = AdventureJunctions.lamp_material(k, on[k])
			var glow: OmniLight3D = h["glow"]
			var k_on := 2 if on[2] else (1 if on[1] and not on[0] else 0)
			glow.light_color = [Color(1.0, 0.15, 0.08), Color(1.0, 0.6, 0.1), Color(0.2, 1.0, 0.5)][k_on]
			glow.light_energy = 0.9 * night
			glow.visible = night > 0.05

	## The state shown now (tests).
	func shown() -> Vector2i:
		return _shown
