class_name RoutePlanner
extends RefCounted
## Plans a road journey across a real region (RealRegion) from the places the crew pinned, and makes the RealPack the
## adventure rides (AdventureRoute.plan_real): the in-game twin of tools/route_bake.py, which does the same from the
## mapped roads of a corridor. Planning reads the region and nothing else, so it runs on a worker thread, and the same
## pins make the same route on every machine (co-op checks the hash).
##
## The steps: pins -> the cheapest roads between them (Dijkstra, the road classes costed by the style of ride) -> the
## road as a line -> smoothed so no bend is tighter than a bike can take -> knots every STEP metres with their height
## (the land under them, smoothed and graded) -> per 128 m chunk its surface, width, class, name and speed limit ->
## the junctions it passes, the buildings, places to stop and landmarks beside it.

const STEP := 4.0
const CHUNK := 128.0
## The road continues this far past the last pin, so the ride has somewhere to run out to.
const RUN_OUT := 600.0
const SNAP_M := 800.0
const MIN_RADIUS := 10.0
const MAX_GRADE := 0.15
const MAX_ROUNDS := 20000
## The version of the planner, in every plan's hash: a change to how routes are made changes the hash.
const VERSION := 1

## What a metre of each class of road costs, by the style of ride ("main": the quick way, "scenic": quiet back roads,
## "tracks": gravel and tracks where there are any).
const CLASS_COST := {
	"main": {"motorway": 0.7, "trunk": 0.75, "primary": 0.8, "secondary": 0.9, "tertiary": 1.0, "unclassified": 1.15,
		"residential": 1.3, "living_street": 1.4, "track": 3.0},
	"scenic": {"motorway": 3.0, "trunk": 2.0, "primary": 1.3, "secondary": 0.95, "tertiary": 0.9, "unclassified": 0.9,
		"residential": 1.2, "living_street": 1.5, "track": 3.0},
	"tracks": {"motorway": 5.0, "trunk": 3.0, "primary": 2.0, "secondary": 1.4, "tertiary": 1.1, "unclassified": 0.9,
		"residential": 1.2, "living_street": 1.5, "track": 0.7},
}
const WIDTH := {"motorway": 7.4, "trunk": 7.4, "primary": 7.4, "secondary": 6.0, "tertiary": 6.0, "unclassified": 4.6,
	"residential": 4.6, "living_street": 4.6, "track": 3.3}
const ORDER: Array[String] = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "track"]
## Speed limits (km/h) where the data has none: by class, by country, lower where built up (tools/road_facts.py LIMITS).
const LIMITS := {
	"uk": {"motorway": 112, "trunk": 96, "primary": 96, "secondary": 96, "tertiary": 96, "unclassified": 96,
		"residential": 48, "living_street": 32, "track": 48, "built_up": 48},
	"jp": {"motorway": 100, "trunk": 60, "primary": 60, "secondary": 50, "tertiary": 40, "unclassified": 40,
		"residential": 30, "living_street": 20, "track": 30, "built_up": 40},
	"world": {"motorway": 110, "trunk": 90, "primary": 80, "secondary": 80, "tertiary": 70, "unclassified": 60,
		"residential": 40, "living_street": 20, "track": 30, "built_up": 50},
}
const BUILT_UP_PER_CHUNK := 8
## How far (m) buildings are kept from the route, places from it by kind, and landmarks by kind.
const BUILDING_REACH := 500.0
const POI_REACH := {"fuel": 120.0, "cafe": 100.0, "pub": 100.0, "inn": 120.0, "campsite": 150.0, "layby": 60.0, "viewpoint": 150.0}
const LANDMARK_REACH := {"peak": 3500.0, "lighthouse": 2500.0, "beach": 800.0, "worship": 500.0, "castle": 2000.0}
## Side roads (degrees off the road's direction) and rings of road, as tools/road_facts.py has them.
const SIDE_MIN := 35.0
const SIDE_MAX := 145.0
const RING_EDGE_M := 90.0
const RING_TOTAL_M := 260.0
const RING_MAX_EDGES := 8
const RING_ROUNDNESS := 0.18
const MINI_RING_M := 12.0
const JUNCTION_GAP_KNOTS := 100


## A binary min-heap of (cost, node), ties to the lower node so the same graph always gives the same path.
class Heap:
	var cost := PackedFloat64Array()
	var node := PackedInt32Array()

	func is_empty() -> bool:
		return node.is_empty()

	func _less(i: int, j: int) -> bool:
		return cost[i] < cost[j] or (cost[i] == cost[j] and node[i] < node[j])

	func _swap(i: int, j: int) -> void:
		var c := cost[i]
		cost[i] = cost[j]
		cost[j] = c
		var n := node[i]
		node[i] = node[j]
		node[j] = n

	func push(c: float, n: int) -> void:
		cost.append(c)
		node.append(n)
		var i := node.size() - 1
		while i > 0:
			var up := (i - 1) / 2
			if not _less(i, up):
				break
			_swap(i, up)
			i = up

	## Takes the smallest; returns its node (its cost is in `top_cost`).
	var top_cost := 0.0

	func pop() -> int:
		var out := node[0]
		top_cost = cost[0]
		var last := node.size() - 1
		cost[0] = cost[last]
		node[0] = node[last]
		cost.resize(last)
		node.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and _less(l, m):
				m = l
			if r < last and _less(r, m):
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return out


## Plans a route over `region`: `request` is {pins: [Vector2 (region x, z)] (two or more, in order), mode: "main" |
## "scenic" | "tracks" (default "main"), names: [String] (the pins' names, for the magazine), seed: int}. Returns
## {ok, error, pack (a RealPack, or null), km, ms}.
static func plan(region: RealRegion, request: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var parts := {}
	var pins: Array = request.get("pins", [])
	var mode := str(request.get("mode", "main"))
	if not CLASS_COST.has(mode):
		return _fail("There is no style of ride called %s." % mode)
	if pins.size() < 2:
		return _fail("Pin a start and somewhere to get to.")
	var costs := PackedFloat64Array()
	for c in region.classes:
		costs.append(float((CLASS_COST[mode] as Dictionary).get(str(c), 1.5)))
	# The pins, on the road network.
	var stops := PackedInt32Array()
	for p: Vector2 in pins:
		var n := region.nearest_connected(p.x, p.y, SNAP_M)
		if n < 0:
			return _fail("That pin is too far from any road (%d m is the most)." % int(SNAP_M))
		if stops.size() > 0 and region.component[n] != region.component[stops[0]]:
			return _fail("There is no way by road between those places.")
		stops.append(n)
	var steps: Array[Vector3i] = []
	for i in stops.size() - 1:
		var leg = _shortest(region, stops[i], stops[i + 1], costs)
		if leg == null:
			return _fail("There is no way by road between those places.")
		steps.append_array(leg)
	steps = strip_spurs(steps)
	if steps.is_empty():
		return _fail("Those pins are the same place: pin somewhere else to get to.")
	parts["roads"] = Time.get_ticks_msec() - t0
	var run_start := steps.size()
	var tail := _run_out(region, steps, costs)
	steps.append_array(tail)
	var line := _line_of(region, steps)
	var raw: PackedVector2Array = line["pts"]
	var owner: PackedInt32Array = line["owner"]
	var turns: Array = line["turns"]
	# The road: smoothed, as knots.
	var knots := smooth_line(raw)
	parts["smooth"] = Time.get_ticks_msec() - t0
	if knots.size() < 12:
		return _fail("That route is too short to ride.")
	var n := knots.size()
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	xs.resize(n)
	zs.resize(n)
	for i in n:
		xs[i] = knots[i].x
		zs[i] = knots[i].y
	var elev := _heights(region, xs, zs)
	parts["heights"] = Time.get_ticks_msec() - t0
	# Where the pins' route ends and the run-out begins.
	var ends_at := _length_of_steps(region, steps, run_start)
	# Chunks.
	var chunks_info := _chunks(region, raw, owner, n)
	var buildings := _buildings(region, xs, zs)
	parts["buildings"] = Time.get_ticks_msec() - t0
	var built := _built_up(chunks_info.size(), buildings)
	var names: Array = []
	for c: Dictionary in chunks_info:
		if not names.has(c["name"]):
			names.append(c["name"])
	names.sort()
	var rows: Array = []
	for i in chunks_info.size():
		var c: Dictionary = chunks_info[i]
		var limit := int(c["limit"]) if int(c["limit"]) > 0 else default_limit(str(c["cls"]), region.country, built[i])
		rows.append([c["surface"], c["width"], c["cls"], names.find(c["name"]), limit])
	# The pack.
	var pack := RealPack.new()
	pack.title = region.title
	pack.credits = region.credits
	pack.theme = region.theme
	pack.sea = region.sea
	pack.region = region.country
	pack.step = STEP
	pack.x = xs
	pack.z = zs
	pack.e = elev
	pack.chunks = rows
	pack.names = names
	var end_k := n - 1
	turns.append({"d": snappedf((n - 1) * STEP, 0.1), "x": snappedf(xs[end_k], 0.1), "z": snappedf(zs[end_k], 0.1), "turn": "arrive", "onto": "", "branches": 0})
	pack.turns = turns
	pack.terrain = region.terrain
	pack.length_m = (n - 1) * STEP
	pack.run_out_m = clampf(pack.length_m - ends_at * ((n - 1) * STEP) / maxf(_raw_length(raw), 1.0), 0.0, RUN_OUT)
	for b: Array in buildings:
		var c := int(b[7]) / int(CHUNK / STEP)
		if not pack.buildings.has(c):
			pack.buildings[c] = []
		(pack.buildings[c] as Array).append(b)
	pack.building_count = buildings.size()
	pack.landmarks = _landmarks(region, xs, zs)
	pack.pois = _pois(region, xs, zs)
	parts["places"] = Time.get_ticks_msec() - t0
	pack.junctions = thin_junctions(junctions_along(region, steps, xs, zs))
	pack.summary = _summary(rows, names, elev, request)
	var hash := _hash(region, request, steps)
	pack.hash = hash
	pack.id = "plan_" + hash
	parts["junctions"] = Time.get_ticks_msec() - t0
	return {"ok": true, "error": "", "pack": pack, "km": pack.max_km(), "ms": Time.get_ticks_msec() - t0, "parts": parts}


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "error": why, "pack": null, "km": 0.0, "ms": 0}


## The hash of a plan: the region's, the style, the pins' junctions and the roads taken (the same on every machine
## that plans the same journey, and different if any of them planned another).
static func _hash(region: RealRegion, request: Dictionary, steps: Array[Vector3i]) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var text := "%d|%s|%s|%s" % [VERSION, region.hash, str(request.get("mode", "main")), str(request.get("seed", 0))]
	ctx.update(text.to_utf8_buffer())
	var path := PackedInt32Array()
	for s in steps:
		path.append(s.y)
		path.append(s.z)
	ctx.update(path.to_byte_array())
	return ctx.finish().hex_encode().substr(0, 16)


# ---------------------------------------------------------------------------- roads

## The cheapest way from node `start` to `goal` as steps (from, edge, to), [] if they are the same, or null.
static func _shortest(region: RealRegion, start: int, goal: int, costs: PackedFloat64Array, banned := {}) -> Variant:
	if start == goal:
		return [] as Array[Vector3i]
	var best := PackedFloat64Array()
	best.resize(region.node_count())
	best.fill(INF)
	var prev_node := PackedInt32Array()
	prev_node.resize(region.node_count())
	var prev_edge := PackedInt32Array()
	prev_edge.resize(region.node_count())
	var done := PackedByteArray()
	done.resize(region.node_count())
	var heap := Heap.new()
	best[start] = 0.0
	heap.push(0.0, start)
	while not heap.is_empty():
		var n := heap.pop()
		var c := heap.top_cost
		if done[n] == 1:
			continue
		done[n] = 1
		if n == goal:
			break
		for ei in region.adjacent[n]:
			if banned.has(ei):
				continue
			var m := region.other_end(ei, n)
			var w := c + region.edge_len[ei] * costs[region.edge_class[ei]]
			if w < best[m] - 1e-9:
				best[m] = w
				prev_node[m] = n
				prev_edge[m] = ei
				heap.push(w, m)
	if done[goal] == 0:
		return null
	var out: Array[Vector3i] = []
	var at := goal
	while at != start:
		out.append(Vector3i(prev_node[at], prev_edge[at], at))
		at = prev_node[at]
	out.reverse()
	return out


## The path with every out-and-back along the same road taken out (a pin on a dead-end street would make the route
## drive in and turn round).
static func strip_spurs(steps: Array[Vector3i]) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for st in steps:
		if not out.is_empty() and out[out.size() - 1].y == st.y and out[out.size() - 1].z == st.x and out[out.size() - 1].x == st.z:
			out.pop_back()
		else:
			out.append(st)
	return out


## Steps that carry on RUN_OUT metres past the end of `steps`, along the biggest road that goes on (never back the way
## it came); fewer where the road ends.
static func _run_out(region: RealRegion, steps: Array[Vector3i], costs: PackedFloat64Array) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var at := steps[steps.size() - 1].z
	var came := steps[steps.size() - 1].y
	var seen := {}
	var run := 0.0
	var heading_pts := region.line_from(came, steps[steps.size() - 1].x)
	var h := _bearing(heading_pts[heading_pts.size() - 1] - heading_pts[maxi(heading_pts.size() - 2, 0)])
	while run < RUN_OUT + 50.0:
		var best := -1
		var best_key := Vector2(INF, INF)
		for ei in region.adjacent[at]:
			if ei == came or seen.has(ei):
				continue
			var line := region.line_from(ei, at)
			var turn := absf(wrapf(_bearing(line[mini(1, line.size() - 1)] - line[0]) - h, -PI, PI))
			var key := Vector2(costs[region.edge_class[ei]], turn)
			if key.x < best_key.x - 1e-9 or (absf(key.x - best_key.x) <= 1e-9 and key.y < best_key.y):
				best_key = key
				best = ei
		if best < 0:
			break
		seen[best] = true
		var to := region.other_end(best, at)
		out.append(Vector3i(at, best, to))
		var l := region.line_from(best, at)
		h = _bearing(l[l.size() - 1] - l[maxi(l.size() - 2, 0)])
		run += region.edge_len[best]
		at = to
		came = best
	return out


static func _bearing(d: Vector2) -> float:
	return atan2(d.x, -d.y)


static func _heading_deg(a: Vector2, b: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(b.x - a.x, -(b.y - a.y))), 360.0)


static func _length_of(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


static func _raw_length(pts: PackedVector2Array) -> float:
	return _length_of(pts)


## The metres of road in steps[0 .. count).
static func _length_of_steps(region: RealRegion, steps: Array[Vector3i], count: int) -> float:
	var l := 0.0
	for i in mini(count, steps.size()):
		l += region.edge_len[steps[i].y]
	return l


## The point `dist` metres along `pts` from its start, or its end when `from_end`.
static func _point_at(pts: PackedVector2Array, dist: float, from_end := false) -> Vector2:
	var left := dist
	var count := pts.size()
	for i in range(count - 1):
		var p := pts[count - 1 - i] if from_end else pts[i]
		var q := pts[count - 2 - i] if from_end else pts[i + 1]
		var seg := p.distance_to(q)
		if seg >= left and seg > 0.0:
			return p.lerp(q, left / seg)
		left -= seg
	return pts[0] if from_end else pts[count - 1]


## The instruction word for a turn of `angle` degrees (positive is to the right).
static func classify_turn(angle: float) -> String:
	var a := absf(angle)
	var side := "right" if angle > 0.0 else "left"
	if a < 25.0:
		return "straight"
	if a < 60.0:
		return "slight_" + side
	if a < 135.0:
		return side
	return "sharp_" + side


## {pts, owner (the edge of each point), turns} for the steps.
static func _line_of(region: RealRegion, steps: Array[Vector3i]) -> Dictionary:
	var pts := PackedVector2Array()
	var owner := PackedInt32Array()
	var turns: Array = []
	var run := 0.0
	for i in steps.size():
		var st := steps[i]
		var line := region.line_from(st.y, st.x)
		if i > 0:
			var prev := steps[i - 1]
			var pline := region.line_from(prev.y, prev.x)
			var incoming := _heading_deg(_point_at(pline, 25.0, true), pline[pline.size() - 1])
			var outgoing := _heading_deg(line[0], _point_at(line, 25.0))
			var branches := region.adjacent[st.x].size() - 2
			if branches >= 1:
				var ang := fposmod(outgoing - incoming + 540.0, 360.0) - 180.0
				turns.append({"d": snappedf(run, 0.1), "x": snappedf(line[0].x, 0.1), "z": snappedf(line[0].y, 0.1),
					"turn": classify_turn(ang), "onto": region.name_of(st.y), "branches": branches})
		var from := 0 if pts.is_empty() else 1
		for k in range(from, line.size()):
			pts.append(line[k])
			owner.append(st.y)
			if pts.size() > 1:
				run += pts[pts.size() - 1].distance_to(pts[pts.size() - 2])
	return {"pts": pts, "owner": owner, "turns": turns}


# ---------------------------------------------------------------------------- the road as knots

## The line through `pts` as points `step` metres apart along it, and its last point, as [xs, zs, total length].
static func resample(xs: PackedFloat64Array, zs: PackedFloat64Array, step: float, exact := false) -> Array:
	var keep_x := PackedFloat64Array()
	var keep_z := PackedFloat64Array()
	var cum := PackedFloat64Array()
	var total := 0.0
	for i in xs.size():
		if i > 0:
			var seg := Vector2(xs[i], zs[i]).distance_to(Vector2(keep_x[keep_x.size() - 1], keep_z[keep_z.size() - 1]))
			if seg <= 1e-9:
				continue
			total += seg
		keep_x.append(xs[i])
		keep_z.append(zs[i])
		cum.append(total)
	var s_list := PackedFloat64Array()
	var s := 0.0
	while s < total:
		s_list.append(s)
		s += step
	if exact:
		if s_list.size() > 0 and total - s_list[s_list.size() - 1] < 1e-6:
			s_list.resize(s_list.size() - 1)
	elif s_list.size() > 0 and total - s_list[s_list.size() - 1] > step * 0.25:
		s_list.append(total)
	elif s_list.size() > 0:
		s_list[s_list.size() - 1] = total
	else:
		s_list.append(total)
	var ox := PackedFloat64Array()
	var oz := PackedFloat64Array()
	ox.resize(s_list.size())
	oz.resize(s_list.size())
	var j := 0
	for i in s_list.size():
		var v := s_list[i]
		while j < cum.size() - 2 and cum[j + 1] < v:
			j += 1
		var span := cum[j + 1] - cum[j] if j + 1 < cum.size() else 0.0
		var t := 0.0 if span <= 0.0 else clampf((v - cum[j]) / span, 0.0, 1.0)
		var j2 := mini(j + 1, cum.size() - 1)
		ox[i] = lerpf(keep_x[j], keep_x[j2], t)
		oz[i] = lerpf(keep_z[j], keep_z[j2], t)
	return [ox, oz, total]


## 1 / radius of the bend at point i from the points two either side.
static func _bend(px: PackedFloat64Array, pz: PackedFloat64Array, i: int) -> float:
	var ax := px[i - 2]
	var az := pz[i - 2]
	var bx := px[i]
	var bz := pz[i]
	var cx := px[i + 2]
	var cz := pz[i + 2]
	var ab := Vector2(bx - ax, bz - az).length()
	var bc := Vector2(cx - bx, cz - bz).length()
	var ac := Vector2(cx - ax, cz - az).length()
	var cross := absf((bx - ax) * (cz - az) - (bz - az) * (cx - ax))
	return 2.0 * cross / maxf(ab * bc * ac, 1e-9)


## A smooth road through `pts`: knots STEP apart, no bend tighter than MIN_RADIUS. Only bends tighter than the
## limit are touched (each round pulls their points, and a few either side, towards the middle of their neighbours,
## until none is too tight) so gentle roads stay exactly as mapped; the ends stay put. Works only where the last
## round changed something, so a long road costs little.
static func smooth_line(pts: PackedVector2Array, min_radius := MIN_RADIUS) -> PackedVector2Array:
	var rx := PackedFloat64Array()
	var rz := PackedFloat64Array()
	for p in pts:
		rx.append(p.x)
		rz.append(p.y)
	var fine := resample(rx, rz, 2.0)
	var px: PackedFloat64Array = fine[0]
	var pz: PackedFloat64Array = fine[1]
	var n := px.size()
	var limit := 1.0 / min_radius
	var cand := PackedInt32Array()
	for i in range(2, n - 2):
		cand.append(i)
	var rounds := 0
	while n >= 7 and not cand.is_empty() and rounds < MAX_ROUNDS:
		rounds += 1
		var bad := PackedInt32Array()
		for i in cand:
			if _bend(px, pz, i) > limit:
				bad.append(i)
		if bad.is_empty():
			break
		# The bad bends and three points either side of each, in order.
		var idx := PackedInt32Array()
		var next_from := 2
		for b in bad:
			var lo := maxi(maxi(b - 3, 2), next_from)
			var hi := mini(b + 3, n - 3)
			for i in range(lo, hi + 1):
				idx.append(i)
			next_from = maxi(next_from, hi + 1)
		var nx := PackedFloat64Array()
		var nz := PackedFloat64Array()
		nx.resize(idx.size())
		nz.resize(idx.size())
		for k in idx.size():
			var i := idx[k]
			nx[k] = px[i] + ((px[i - 1] + px[i + 1]) / 2.0 - px[i]) * 0.6
			nz[k] = pz[i] + ((pz[i - 1] + pz[i + 1]) / 2.0 - pz[i]) * 0.6
		for k in idx.size():
			px[idx[k]] = nx[k]
			pz[idx[k]] = nz[k]
		# What may be bad next: the points near any that moved.
		cand = PackedInt32Array()
		var from := 2
		for i in idx:
			var lo := maxi(maxi(i - 2, 2), from)
			var hi := mini(i + 2, n - 3)
			for j in range(lo, hi + 1):
				cand.append(j)
			from = maxi(from, hi + 1)
	var knots := resample(px, pz, STEP, true)
	var kx: PackedFloat64Array = knots[0]
	var kz: PackedFloat64Array = knots[1]
	var out := PackedVector2Array()
	for i in kx.size():
		out.append(Vector2(kx[i], kz[i]))
	return out


## The ground under the road, averaged over 9 knots (the road rides over bumps), no steeper than MAX_GRADE.
static func _heights(region: RealRegion, xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat32Array:
	var n := xs.size()
	var ground := PackedFloat64Array()
	ground.resize(n)
	var last := 0.0
	for i in n:
		var h := region.terrain.height(xs[i], zs[i])
		if is_nan(h):
			h = last
		last = h
		ground[i] = maxf(h, 0.0)
	var smooth := smooth_heights(ground, 9)
	var graded := grade_limit(smooth)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = graded[i]
	return out


static func smooth_heights(h: PackedFloat64Array, window := 9) -> PackedFloat64Array:
	var k := window / 2
	var n := h.size()
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		var sum := 0.0
		for j in range(i - k, i + k + 1):
			sum += h[clampi(j, 0, n - 1)]
		out[i] = sum / window
	return out


## Heights with no climb steeper than `max_grade`: the road is cut and filled to stay within it.
static func grade_limit(e: PackedFloat64Array, max_grade := MAX_GRADE) -> PackedFloat64Array:
	var out := e.duplicate()
	var lim := max_grade * STEP
	for _round in 3:
		for i in range(1, out.size()):
			out[i] = minf(maxf(out[i], out[i - 1] - lim), out[i - 1] + lim)
		for i in range(out.size() - 2, -1, -1):
			out[i] = minf(maxf(out[i], out[i + 1] - lim), out[i + 1] + lim)
	return out


# ---------------------------------------------------------------------------- what is along the road

## Per 128 m chunk: {surface, width, cls, name, limit} from the roads under it (by most knots).
static func _chunks(region: RealRegion, raw: PackedVector2Array, owner: PackedInt32Array, knots: int) -> Array:
	var cum := PackedFloat64Array()
	cum.resize(raw.size())
	var run := 0.0
	for i in raw.size():
		if i > 0:
			run += raw[i].distance_to(raw[i - 1])
		cum[i] = run
	var scale := run / maxf((knots - 1) * STEP, 1e-9)
	var out: Array = []
	var count := int(ceil((knots - 1) * STEP / CHUNK))
	for c in count:
		var votes := {}
		var s := c * CHUNK
		var stop := minf((c + 1) * CHUNK, (knots - 1) * STEP)
		while s < stop:
			var i := clampi(cum.bsearch(s * scale, false) - 1, 0, owner.size() - 1)
			var ei := owner[i]
			votes[ei] = int(votes.get(ei, 0)) + 1
			s += STEP
		var top := -1
		var top_n := -1
		for ei in votes:
			if int(votes[ei]) > top_n:
				top_n = int(votes[ei])
				top = int(ei)
		if top < 0:
			top = owner[owner.size() - 1]
		var cls := region.class_of(top)
		out.append({"surface": region.surface_of(top), "width": float(WIDTH.get(cls, 4.6)), "cls": cls,
			"name": region.name_of(top), "limit": region.edge_limit[top]})
	return out


static func default_limit(cls: String, country: String, built_up := false) -> int:
	var table: Dictionary = LIMITS.get(country, LIMITS["world"])
	var limit := int(table.get(cls, table["unclassified"]))
	return mini(limit, int(table["built_up"])) if built_up else limit


static func _built_up(chunks: int, buildings: Array) -> Array[bool]:
	var count := PackedInt32Array()
	count.resize(chunks)
	for b: Array in buildings:
		var c := int(float(int(b[7])) * STEP / CHUNK)
		if c >= 0 and c < chunks:
			count[c] += 1
	var out: Array[bool] = []
	for c in chunks:
		out.append(count[c] >= BUILT_UP_PER_CHUNK)
	return out


## A grid of the knots (every other one), for finding the nearest to a point.
class KnotGrid:
	const CELL := 64.0
	const COARSE := 256.0
	var cells := {}
	var coarse := {}
	var xs: PackedFloat64Array
	var zs: PackedFloat64Array

	func _init(x: PackedFloat64Array, z: PackedFloat64Array) -> void:
		xs = x
		zs = z
		for k in range(0, x.size(), 2):
			var key := Vector2i(floori(x[k] / CELL), floori(z[k] / CELL))
			var cell: PackedInt32Array = cells.get(key, PackedInt32Array())
			cell.append(k)
			cells[key] = cell

	## [distance, knot] of the knot nearest (x, z) within `reach`, or [INF, -1]. Looks in widening rings of cells and
	## stops once nothing further out could be nearer.
	func nearest(x: float, z: float, reach: float) -> Array:
		var span := int(reach / CELL) + 1
		var gx := floori(x / CELL)
		var gz := floori(z / CELL)
		var best := INF
		var bk := -1
		for r in span + 1:
			if bk >= 0 and best <= (r - 1) * CELL:
				break
			for ix in range(gx - r, gx + r + 1):
				for iz in range(gz - r, gz + r + 1):
					if maxi(absi(ix - gx), absi(iz - gz)) != r:
						continue
					var cell: PackedInt32Array = cells.get(Vector2i(ix, iz), PackedInt32Array())
					for k in cell:
						var d := Vector2(x - xs[k], z - zs[k]).length()
						if d < best or (d == best and k < bk):
							best = d
							bk = k
		return [best, bk] if best <= reach else [INF, -1]

	## Whether any knot is within about `reach` of (x, z), judged by a coarse grid (a quick no for far-off points).
	func near_any(x: float, z: float, reach: float) -> bool:
		if coarse.is_empty():
			for key: Vector2i in cells:
				coarse[Vector2i(floori(key.x * CELL / COARSE), floori(key.y * CELL / COARSE))] = true
		var span := int(reach / COARSE) + 1
		var gx := floori(x / COARSE)
		var gz := floori(z / COARSE)
		for ix in range(gx - span, gx + span + 1):
			for iz in range(gz - span, gz + span + 1):
				if coarse.has(Vector2i(ix, iz)):
					return true
		return false


## The region's buildings within reach of the road, each with the road's nearest knot ([x, z, w, d, yaw, h, kind, knot]).
static func _buildings(region: RealRegion, xs: PackedFloat64Array, zs: PackedFloat64Array) -> Array:
	var grid := KnotGrid.new(xs, zs)
	var out: Array = []
	for b: Array in region.buildings:
		if not grid.near_any(float(b[0]), float(b[1]), BUILDING_REACH):
			continue
		var near := grid.nearest(float(b[0]), float(b[1]), BUILDING_REACH)
		if int(near[1]) < 0:
			continue
		var row := b.duplicate()
		row[7] = int(near[1])
		out.append(row)
	out.sort_custom(func(a, c): return int(a[7]) < int(c[7]))
	return out


static func _pois(region: RealRegion, xs: PackedFloat64Array, zs: PackedFloat64Array) -> Array:
	var grid := KnotGrid.new(xs, zs)
	var out: Array = []
	for q: Dictionary in region.pois:
		var kind := str(q["kind"])
		var x := float(q["x"])
		var z := float(q["z"])
		var near := grid.nearest(x, z, float(POI_REACH.get(kind, 100.0)))
		var bk := int(near[1])
		if bk < 0:
			continue
		var k2 := mini(bk + 1, xs.size() - 1)
		var h := atan2(xs[k2] - xs[bk], -(zs[k2] - zs[bk]))
		var lat := (x - xs[bk]) * cos(h) + (z - zs[bk]) * sin(h)
		var row := q.duplicate()
		row["k"] = bk
		row["lat"] = snappedf(lat, 0.1)
		out.append(row)
	out.sort_custom(func(a, c):
		if int(a["k"]) != int(c["k"]):
			return int(a["k"]) < int(c["k"])
		if str(a["kind"]) != str(c["kind"]):
			return str(a["kind"]) < str(c["kind"])
		return float(a["x"]) < float(c["x"]))
	return out


static func _landmarks(region: RealRegion, xs: PackedFloat64Array, zs: PackedFloat64Array) -> Array:
	var out: Array = []
	for m: Dictionary in region.landmarks:
		var reach := float(LANDMARK_REACH.get(str(m["kind"]), 500.0))
		var mx := float(m["x"])
		var mz := float(m["z"])
		for k in range(0, xs.size(), 8):
			if Vector2(xs[k] - mx, zs[k] - mz).length() <= reach:
				out.append(m)
				break
	return out


## What the magazine says about the road: {from, to, roads, climb_m, top_m, low_m}.
static func _summary(rows: Array, names: Array, elev: PackedFloat32Array, request: Dictionary) -> Dictionary:
	var generic: Array = RealRegion.GENERIC_NAMES.values()
	var metres := {}
	for r: Array in rows:
		var name := str(names[int(r[3])])
		if not generic.has(name):
			metres[name] = float(metres.get(name, 0.0)) + CHUNK
	var roads: Array = metres.keys()
	roads.sort_custom(func(a, b): return float(metres[a]) > float(metres[b]) or (float(metres[a]) == float(metres[b]) and str(a) < str(b)))
	var climb := 0.0
	var top := -INF
	var low := INF
	for i in elev.size():
		top = maxf(top, elev[i])
		low = minf(low, elev[i])
		if i > 0:
			climb += maxf(elev[i] - elev[i - 1], 0.0)
	var pin_names: Array = request.get("names", [])
	return {"from": str(pin_names[0]) if pin_names.size() > 0 else "", "to": str(pin_names[pin_names.size() - 1]) if pin_names.size() > 1 else "",
		"roads": roads.slice(0, 4), "climb_m": int(round(climb)), "top_m": int(round(top)), "low_m": int(round(low))}


# ---------------------------------------------------------------------------- junctions

static func _wrap_deg(a: float) -> float:
	return fposmod(a + 180.0, 360.0) - 180.0


static func _arm_of(region: RealRegion, ei: int, node: int, route_heading: float, here: Vector2) -> Variant:
	var line := region.line_from(ei, node)
	var end := _point_at(line, 25.0)
	var rel := _wrap_deg(rad_to_deg(_bearing(end - here)) - route_heading)
	if absf(rel) < SIDE_MIN or absf(rel) > SIDE_MAX:
		return null
	var cls := region.class_of(ei)
	var side := 1 if rel > 0.0 else -1
	return {"side": side, "skew": snappedf(clampf(rel - side * 90.0, -60.0, 60.0), 0.1), "cls": cls,
		"name": str(region.names[region.edge_name[ei]]), "w": float(WIDTH.get(cls, 4.6)), "surf": region.surface_of(ei), "rel": rel}


## At most one arm a side: the biggest road (then the squarest).
static func _one_per_side(arms: Array) -> Array:
	var best := {}
	for a: Dictionary in arms:
		var cur = best.get(a["side"])
		if cur == null or _arm_key(a) < _arm_key(cur):
			best[a["side"]] = a
	var sides: Array = best.keys()
	sides.sort()
	var out: Array = []
	for s in sides:
		var a: Dictionary = (best[s] as Dictionary).duplicate()
		a.erase("rel")
		out.append(a)
	return out


static func _arm_key(a: Dictionary) -> Vector2:
	return Vector2(ORDER.find(str(a["cls"])), absf(float(a["skew"])))


## A short ring of road through edge `start_edge`: its nodes ([] when it is on none, or it is not round).
static func find_ring(region: RealRegion, start_edge: int) -> PackedInt32Array:
	if region.edge_len[start_edge] > RING_EDGE_M:
		return PackedInt32Array()
	var goal := region.edge_b[start_edge]
	# (node, nodes so far, edges so far, total length)
	var stack: Array = [[region.edge_a[start_edge], PackedInt32Array([region.edge_a[start_edge]]), PackedInt32Array([start_edge]), region.edge_len[start_edge]]]
	var best_nodes := PackedInt32Array()
	var best_edges := PackedInt32Array()
	var found := false
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: int = item[0]
		var nodes: PackedInt32Array = item[1]
		var used: PackedInt32Array = item[2]
		var total: float = item[3]
		if node == goal and used.size() > 2:
			if not found or used.size() < best_edges.size():
				best_nodes = nodes
				best_edges = used
				found = true
			continue
		if used.size() >= RING_MAX_EDGES:
			continue
		for ei in region.adjacent[node]:
			if used.has(ei) or region.edge_len[ei] > RING_EDGE_M or total + region.edge_len[ei] > RING_TOTAL_M:
				continue
			var n2 := nodes.duplicate()
			n2.append(region.other_end(ei, node))
			var u2 := used.duplicate()
			u2.append(ei)
			stack.append([region.other_end(ei, node), n2, u2, total + region.edge_len[ei]])
	if not found or not _is_round(region, best_edges):
		return PackedInt32Array()
	return best_nodes


## Whether the road along these edges lies about a circle of a plausible size.
static func _is_round(region: RealRegion, edge_ids: PackedInt32Array) -> bool:
	var pts: Array[Vector2] = []
	for ei in edge_ids:
		for p in region.edge_line[ei]:
			pts.append(p)
	var centre := Vector2.ZERO
	for p in pts:
		centre += p
	centre /= pts.size()
	var mean := 0.0
	for p in pts:
		mean += p.distance_to(centre)
	mean /= pts.size()
	var var_ := 0.0
	for p in pts:
		var_ += pow(p.distance_to(centre) - mean, 2.0)
	var std := sqrt(var_ / pts.size())
	return mean >= 4.0 and mean <= 45.0 and std <= RING_ROUNDNESS * mean


## The junctions the route passes: [{k (the nearest road knot), type, arms, ri, ro}] in order along the road.
static func junctions_along(region: RealRegion, steps: Array[Vector3i], xs: PackedFloat64Array, zs: PackedFloat64Array) -> Array:
	var out: Array = []
	var used := {}
	var ringed := {}
	var count := steps.size()
	var grid := KnotGrid.new(xs, zs)
	var i := 1
	while i < count:
		if used.has(i):
			i += 1
			continue
		var st := steps[i]
		var ring := find_ring(region, st.y)
		if not ring.is_empty():
			var ring_set := {}
			for r in ring:
				ring_set[r] = true
				ringed[r] = true
			var j := i
			while j < count and ring_set.has(steps[j].x) and ring_set.has(steps[j].z):
				j += 1
			var centre := Vector2.ZERO
			for r in ring_set:
				centre += region.node_pos[r]
			centre /= ring_set.size()
			var radius := 0.0
			for r in ring_set:
				radius += region.node_pos[r].distance_to(centre)
			radius /= ring_set.size()
			var k := _knot_near(grid, centre, xs, zs)
			var h := _knot_heading(xs, zs, k)
			var ring_edges := {}
			for r in ring_set:
				for ej in region.adjacent[r]:
					if ring_set.has(region.other_end(ej, r)):
						ring_edges[ej] = true
			var path_edges := {}
			for q in range(maxi(0, i - 1), mini(j + 1, count)):
				path_edges[steps[q].y] = true
			var arms: Array = []
			for r in ring_set:
				for ej in region.adjacent[r]:
					if ring_edges.has(ej) or path_edges.has(ej):
						continue
					var arm = _arm_of(region, ej, r, h, region.node_pos[r])
					if arm != null:
						arms.append(arm)
			var ri := clampf(radius - 5.0, 4.0, 9.0)
			out.append({"k": k, "type": "mini" if radius <= MINI_RING_M else "roundabout", "arms": _one_per_side(arms),
				"ri": snappedf(ri, 0.1), "ro": snappedf(ri + 6.8, 0.1)})
			for q in range(i, j):
				used[q] = true
			i = j
			continue
		var node := st.x
		if not ringed.has(node) and region.adjacent[node].size() > 2:
			var prev_edge := steps[i - 1].y
			var k2 := _knot_near(grid, region.node_pos[node], xs, zs)
			var h2 := _knot_heading(xs, zs, k2)
			var arms2: Array = []
			for ej in region.adjacent[node]:
				if ej == prev_edge or ej == st.y:
					continue
				var arm = _arm_of(region, ej, node, h2, region.node_pos[node])
				if arm != null:
					arms2.append(arm)
			arms2 = _one_per_side(arms2)
			if not arms2.is_empty():
				out.append({"k": k2, "type": "cross" if arms2.size() > 1 else "tee", "arms": arms2})
		i += 1
	out.sort_custom(func(a, b): return int(a["k"]) < int(b["k"]))
	return out


## The road knot nearest `p` (searching widening rings, the junction is on the road so it is close).
static func _knot_near(grid: KnotGrid, p: Vector2, xs: PackedFloat64Array, zs: PackedFloat64Array) -> int:
	var near := grid.nearest(p.x, p.y, 200.0)
	if int(near[1]) < 0:
		return 0
	# (the grid holds every other knot: look at the one either side too)
	var k := int(near[1])
	var best := k
	var best_d := Vector2(xs[k] - p.x, zs[k] - p.y).length()
	for q in [k - 1, k + 1]:
		if q >= 0 and q < xs.size():
			var d := Vector2(xs[q] - p.x, zs[q] - p.y).length()
			if d < best_d:
				best_d = d
				best = q
	return best


static func _knot_heading(xs: PackedFloat64Array, zs: PackedFloat64Array, k: int) -> float:
	var k2 := mini(k, xs.size() - 2)
	return rad_to_deg(atan2(xs[k2 + 1] - xs[k2], -(zs[k2 + 1] - zs[k2])))


## The junctions kept apart (the game keeps its sites clear of each other): the biggest (roundabouts first) wins.
static func thin_junctions(junctions: Array) -> Array:
	var rank := {"roundabout": 0, "mini": 1, "cross": 2, "tee": 3}
	var sorted := junctions.duplicate()
	sorted.sort_custom(func(a, b):
		if rank[a["type"]] != rank[b["type"]]:
			return rank[a["type"]] < rank[b["type"]]
		return int(a["k"]) < int(b["k"]))
	var kept: Array = []
	for j: Dictionary in sorted:
		var clear := true
		for o: Dictionary in kept:
			if absi(int(j["k"]) - int(o["k"])) < JUNCTION_GAP_KNOTS:
				clear = false
				break
		if clear:
			kept.append(j)
	kept.sort_custom(func(a, b): return int(a["k"]) < int(b["k"]))
	return kept
