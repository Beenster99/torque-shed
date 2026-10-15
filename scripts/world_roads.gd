class_name WorldRoads
extends RefCounted
## The road network of the riding map: the 1 km loop round the yard, tarmac roads between the
## villages and farms and over the mountain pass, and dirt tracks off them. Each road is a
## smooth line through the points in WorldLayout.ROADS, sampled every STEP metres, with a
## height at every sample that follows the land but never climbs steeper than the road's
## grade and has no sudden crests. Roads that branch off another start flat on it, and the
## road they leave is flat where they join, so the two surfaces meet without a step.

const STEP := 2.0
const CELL := 32.0
## A branch's surface sits this much above the road it leaves, where the two overlap.
const JOIN_LIFT := 0.015
## The loop sits this much proud of the yard slab where it crosses it.
const YARD_LIFT := 0.02
## The steepest a tarmac road may be across a crest: how fast its grade may change per metre,
## so a bike at speed stays on the ground (a crest of radius R keeps v^2 / R under g).
const CREST_RATE := 1.0 / 160.0

## Each road: name, label, kind, hw, grade, hard, closed, xz (PackedVector2Array), h
## (PackedFloat32Array), dir (unit direction along it), dist (metres from the start), joins
## (where branches leave it: an Array of sample indices), start_join / end_join ({road, i} or {}).
var roads: Array[Dictionary] = []
var by_name := {}
var _grid := {}   # Vector2i cell -> Array of road * 65536 + sample


## Lays out every road over `terrain`'s natural land.
func build(terrain: WorldTerrain) -> void:
	roads.clear()
	by_name.clear()
	for def in WorldLayout.ROADS:
		var r := {"name": str(def["name"]), "label": str(def.get("label", def["name"])), "kind": str(def["kind"]),
			"hw": float(def["hw"]), "grade": float(def["grade"]), "hard": bool(def.get("hard", false)),
			"closed": bool(def.get("closed", false)), "joins": [], "start_join": {}, "end_join": {}}
		var ctrl := PackedVector2Array(def["pts"])
		# Branches start (and end) exactly on the centre line of the road they meet.
		for end in ["start", "end"]:
			if def.has(end) and by_name.has(str(def[end])):
				var parent: Dictionary = roads[int(by_name[str(def[end])])]
				var k := 0 if end == "start" else ctrl.size() - 1
				var pi := nearest_sample(parent, ctrl[k])
				ctrl[k] = (parent["xz"] as PackedVector2Array)[pi]
				r[end + "_join"] = {"road": int(by_name[str(def[end])]), "i": pi}
				r[end + "_skip"] = float(parent["hw"]) + 1.0
				(parent["joins"] as Array).append(pi)
		r["xz"] = _resample(_spline(ctrl, r["closed"]), r["closed"])
		by_name[r["name"]] = roads.size()
		roads.append(r)
	for r in roads:
		_profile(r, terrain)
	_index()


## The index of `road`'s sample nearest `p`.
static func nearest_sample(road: Dictionary, p: Vector2) -> int:
	var xz: PackedVector2Array = road["xz"]
	var best := 0
	var best_d := INF
	for i in xz.size():
		var d := xz[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## The road surface point at sample `i` of road `r` (centre line, top of the tarmac).
func point(r: int, i: int) -> Vector3:
	var road := roads[r]
	var xz: Vector2 = (road["xz"] as PackedVector2Array)[i]
	return Vector3(xz.x, (road["h"] as PackedFloat32Array)[i], xz.y)


## The nearest road centre line to (x, z) within `max_d` metres: {d, h, road, i, u (0..1 along
## the segment from sample i)}, or {} when there's none that close. `kind` limits it to
## "tarmac" or "dirt".
func nearest(x: float, z: float, max_d := 40.0, kind := "") -> Dictionary:
	var c := Vector2i(floori(x / CELL), floori(z / CELL))
	var reach := ceili(max_d / CELL)
	var best := {}
	var best_d := max_d
	var p := Vector2(x, z)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(key):
				continue
			for code in _grid[key]:
				var ri: int = code >> 16
				var road := roads[ri]
				if kind != "" and road["kind"] != kind:
					continue
				var xz: PackedVector2Array = road["xz"]
				var i: int = code & 0xFFFF
				var n := xz.size()
				var j := i + 1
				if j >= n:
					if not road["closed"]:
						j = i
					else:
						j = 0
				var a := xz[i]
				var seg := xz[j] - a
				var u := 0.0
				var len2 := seg.length_squared()
				if len2 > 0.0001:
					u = clampf((p - a).dot(seg) / len2, 0.0, 1.0)
				var d := p.distance_to(a + seg * u)
				if d < best_d:
					best_d = d
					var hs: PackedFloat32Array = road["h"]
					best = {"d": d, "h": lerpf(hs[i], hs[j], u), "road": ri, "i": i, "u": u}
	return best


## Total length of every road of `kind` ("" for all), in metres.
func total_length(kind := "") -> float:
	var total := 0.0
	for r in roads:
		if kind == "" or r["kind"] == kind:
			total += float(r["length"])
	return total


# ---------------------------------------------------------------------------- the line

## A smooth curve (centripetal Catmull-Rom) through `ctrl`, densely sampled.
static func _spline(ctrl: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	var segs := n if closed else n - 1
	for s in segs:
		var p1 := ctrl[s]
		var p2 := ctrl[(s + 1) % n]
		var p0: Vector2
		var p3: Vector2
		if closed:
			p0 = ctrl[(s - 1 + n) % n]
			p3 = ctrl[(s + 2) % n]
		else:
			p0 = ctrl[s - 1] if s > 0 else p1 * 2.0 - p2
			p3 = ctrl[s + 2] if s + 2 < n else p2 * 2.0 - p1
		var t0 := 0.0
		var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 0.01))
		var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.01))
		var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.01))
		var steps := maxi(8, int(p1.distance_to(p2) / 0.5))
		for k in steps:
			var t := lerpf(t1, t2, float(k) / steps)
			var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			out.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
	if not closed:
		out.append(ctrl[n - 1])
	return out


## Even samples every STEP metres along a dense line.
static func _resample(dense: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var line := dense.duplicate()
	if closed:
		line.append(dense[0])
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var count := maxi(2, roundi(total / STEP))
	var step := total / (count if closed else count)
	var out := PackedVector2Array()
	var seg := 0
	var seg_start := 0.0
	var n := count if closed else count + 1
	for k in n:
		var target := minf(k * step, total)
		while seg < line.size() - 2 and seg_start + line[seg].distance_to(line[seg + 1]) < target:
			seg_start += line[seg].distance_to(line[seg + 1])
			seg += 1
		var seg_len := maxf(line[seg].distance_to(line[seg + 1]), 0.0001)
		out.append(line[seg].lerp(line[seg + 1], clampf((target - seg_start) / seg_len, 0.0, 1.0)))
	return out


# ---------------------------------------------------------------------------- heights

## Heights along road `r`: the land smoothed out, held to the road's grade, flat where
## branches join, level with the road it leaves at each end, and level with the yard.
func _profile(r: Dictionary, terrain: WorldTerrain) -> void:
	var xz: PackedVector2Array = r["xz"]
	var n := xz.size()
	var closed: bool = r["closed"]
	var tarmac: bool = r["kind"] == "tarmac"
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = terrain.natural(xz[i].x, xz[i].y)
	# Fixed heights: the yard, and the ends that sit on another road.
	var fixed := PackedByteArray()
	fixed.resize(n)
	var fix_h := PackedFloat32Array()
	fix_h.resize(n)
	if r["name"] == "loop":
		for i in n:
			if xz[i].y > 95.0 and xz[i].x > -70.0 and xz[i].x < 92.0:
				fixed[i] = 1
				fix_h[i] = YARD_LIFT
	for end in ["start_join", "end_join"]:
		var j: Dictionary = r[end]
		if j.is_empty():
			continue
		var parent := roads[int(j["road"])]
		var h: float = (parent["h"] as PackedFloat32Array)[int(j["i"])] + JOIN_LIFT
		var span := ceili((float(parent["hw"]) + 2.5) / STEP)
		for k in span + 1:
			var i := k if end == "start_join" else n - 1 - k
			fixed[i] = 1
			fix_h[i] = h
	# The grade allowed between each sample and the next: none where a branch leaves, and
	# easing in from there and from the fixed ends, so the road never kinks into a climb.
	var smooth_w := 10 if tarmac else (1 if r["hard"] else 2)
	var passes := 3 if tarmac else 2
	var ramp := 20.0 if tarmac else 6.0
	var flat := PackedByteArray()
	flat.resize(n)
	for i in n:
		flat[i] = fixed[i]
	for pi in r["joins"]:
		var half := ceili((7.0 + STEP * smooth_w) / STEP)
		for k in range(-half, half + 1):
			var i: int = pi + k
			if closed:
				i = posmod(i, n)
			if i >= 0 and i < n:
				flat[i] = 1
	var near := _distance_to(fixed, closed)
	var grade := PackedFloat32Array()
	grade.resize(n)
	for i in n:
		var nxt := (i + 1) % n
		var d := minf(near[i], near[nxt])
		grade[i] = 0.0 if (flat[i] and flat[nxt]) else float(r["grade"]) * STEP * clampf(d / ramp, 0.08, 1.0)
	var t := _smooth(raw, 8 if tarmac else 2, 1, closed)
	for i in n:
		if fixed[i]:
			t[i] = fix_h[i]
	var h := _pin(_smooth(_lipschitz(t, fixed, fix_h, grade, closed), smooth_w, passes, closed), fixed, fix_h, closed, ramp)
	if tarmac:
		_ease_crests(h, fixed, closed, CREST_RATE * STEP * STEP)
	r["h"] = h
	# Direction and distance along it.
	var dir := PackedVector2Array()
	dir.resize(n)
	var dist := PackedFloat32Array()
	dist.resize(n)
	var run := 0.0
	for i in n:
		var a := xz[posmod(i - 1, n)] if (closed or i > 0) else xz[i]
		var b := xz[(i + 1) % n] if (closed or i < n - 1) else xz[i]
		dir[i] = (b - a).normalized()
		dist[i] = run
		if i < n - 1 or closed:
			run += xz[i].distance_to(xz[(i + 1) % n])
	r["dir"] = dir
	r["dist"] = dist
	r["length"] = run


## Moving average over `w` samples either side, `passes` times (wrapping round a loop).
static func _smooth(src: PackedFloat32Array, w: int, passes: int, closed: bool) -> PackedFloat32Array:
	var cur := src.duplicate()
	var n := cur.size()
	if w <= 0 or n < 3:
		return cur
	for p in passes:
		var pre := PackedFloat64Array()
		var m := n + 2 * w
		pre.resize(m + 1)
		for k in m:
			var i := k - w
			var v: float
			if closed:
				v = cur[posmod(i, n)]
			else:
				v = cur[clampi(i, 0, n - 1)]
			pre[k + 1] = pre[k] + v
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			out[i] = (pre[i + 2 * w + 1] - pre[i]) / (2 * w + 1)
		cur = out
	return cur


## The heights `t` held to a grade limit (per sample, `grade` metres each step) while keeping
## every fixed height: clamp into the cones the fixed points allow, then take the middle of
## the steepest-allowed envelopes from above and below.
static func _lipschitz(t: PackedFloat32Array, fixed: PackedByteArray, fix_h: PackedFloat32Array,
		grade: PackedFloat32Array, closed: bool) -> PackedFloat32Array:
	var n := t.size()
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(n)
	hi.resize(n)
	var any_fixed := false
	for i in n:
		lo[i] = fix_h[i] if fixed[i] else -1.0e9
		hi[i] = fix_h[i] if fixed[i] else 1.0e9
		any_fixed = any_fixed or fixed[i] == 1
	if any_fixed:
		_envelope(hi, grade, closed, true)
		_envelope(lo, grade, closed, false)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in n:
		f[i] = clampf(t[i], lo[i], hi[i]) if lo[i] <= hi[i] else (lo[i] + hi[i]) * 0.5
	var low := f.duplicate()
	var high := f.duplicate()
	_envelope(low, grade, closed, true)
	_envelope(high, grade, closed, false)
	for i in n:
		f[i] = (low[i] + high[i]) * 0.5
		if fixed[i]:
			f[i] = fix_h[i]
	return f


## In place: the greatest function under `a` (`down` true) or least above it, whose step
## from each sample to the next is at most `grade` of that step.
static func _envelope(a: PackedFloat32Array, grade: PackedFloat32Array, closed: bool, down: bool) -> void:
	var n := a.size()
	var laps := 2 if closed else 1
	for lap in laps:
		for k in range(1, n + (1 if closed else 0)):
			var i := k % n
			var prev := k - 1
			var g := grade[prev]
			a[i] = minf(a[i], a[prev] + g) if down else maxf(a[i], a[prev] - g)
		for k in range(n - 2 + (1 if closed else 0), -1, -1):
			var i := k
			var nxt := (k + 1) % n
			var g := grade[i]
			a[i] = minf(a[i], a[nxt] + g) if down else maxf(a[i], a[nxt] - g)


## In place: rounds off every crest sharper than `limit` (the most the height may bend down
## over one sample each side), lowering its top, so nothing on a road throws a bike in the air.
static func _ease_crests(h: PackedFloat32Array, fixed: PackedByteArray, closed: bool, limit: float) -> void:
	var n := h.size()
	for sweep in 600:
		var worst := 0.0
		for i in n:
			if not closed and (i == 0 or i == n - 1):
				continue
			var ia := posmod(i - 1, n)
			var ib := (i + 1) % n
			var bend := 2.0 * h[i] - h[ia] - h[ib]
			if bend <= limit:
				continue
			worst = maxf(worst, bend)
			if not fixed[i] and fixed[ia] and not fixed[ib]:
				h[ib] += bend - limit        # next to a fixed stretch: lift the far side instead
			elif not fixed[i] and fixed[ib] and not fixed[ia]:
				h[ia] += bend - limit
			elif not fixed[i]:
				h[i] = (h[ia] + h[ib] + limit) * 0.5
			elif not fixed[ia] and not fixed[ib]:
				h[ia] += (bend - limit) * 0.5
				h[ib] += (bend - limit) * 0.5
			elif not fixed[ia]:
				h[ia] += bend - limit
			elif not fixed[ib]:
				h[ib] += bend - limit
		if worst <= limit * 1.02:
			return


## Puts the fixed samples back exactly after smoothing, easing each correction out over
## `ramp` samples either side so the road bends no more than the smoothing left it.
static func _pin(h: PackedFloat32Array, fixed: PackedByteArray, fix_h: PackedFloat32Array, closed: bool, ramp: float) -> PackedFloat32Array:
	var n := h.size()
	var out := h.duplicate()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	left.resize(n)
	right.resize(n)
	left.fill(-1)
	right.fill(-1)
	var laps := 2 if closed else 1
	var last := -1
	for lap in laps:
		for i in n:
			if fixed[i]:
				last = i
			elif last >= 0:
				left[i] = last
	last = -1
	for lap in laps:
		for k in range(n - 1, -1, -1):
			if fixed[k]:
				last = k
			elif last >= 0:
				right[k] = last
	for i in n:
		if fixed[i]:
			out[i] = fix_h[i]
			continue
		for j in [left[i], right[i]]:
			if j < 0:
				continue
			var gap := absi(i - j)
			if closed:
				gap = mini(gap, n - gap)
			out[i] += (fix_h[j] - h[j]) * (1.0 - smoothstep(0.0, ramp, float(gap)))
	return out


## For each sample, how many samples it is from the nearest one marked in `mask` (wrapping
## round a loop); a big number when none is marked.
static func _distance_to(mask: PackedByteArray, closed: bool) -> PackedFloat32Array:
	var n := mask.size()
	var d := PackedFloat32Array()
	d.resize(n)
	for i in n:
		d[i] = 0.0 if mask[i] else 1.0e6
	var laps := 2 if closed else 1
	for lap in laps:
		for k in range(1, n + (1 if closed else 0)):
			d[k % n] = minf(d[k % n], d[k - 1] + 1.0)
		for k in range(n - 2 + (1 if closed else 0), -1, -1):
			d[k] = minf(d[k], d[(k + 1) % n] + 1.0)
	return d


func _index() -> void:
	_grid.clear()
	for ri in roads.size():
		var xz: PackedVector2Array = roads[ri]["xz"]
		for i in xz.size():
			var key := Vector2i(floori(xz[i].x / CELL), floori(xz[i].y / CELL))
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(ri * 65536 + i)
