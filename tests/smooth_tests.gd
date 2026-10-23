extends RefCounted
## Smooth roads on adventures (Simon: "Smooth out roads in adventures"), run from tests/run_tests.gd (its
## _test_smooth_* functions hand over to these). A real road's heights came from the land under it every 4 m, kinks
## and all (a grade of +15% to -12% in one knot): at 90 km/h a jolt of four g, enough to throw you off. They're
## smoothed along the road now, the forks' ways eased onto it at both ends, and a side road's mouth no longer sits up
## on the road's edge like a kerb.

var t: Node   # the test runner: check(), get_tree()

## The sharpest crest or dip a road may have: its height's second difference per metre (1/m). At 90 km/h (25 m/s)
## it's a lift or a drop of 625 times this (m/s²): 0.003 is under 2 m/s², a fifth of a g. The made-up roads were
## always a third of that.
const REAL_CURVE := 0.003
## A chunk's road meets the next's to this (m).
const SEAM := 0.003
## The steepest a real road gets (its data is cut and filled to 15%).
const REAL_GRADE := 0.152


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## The sharpest crest or dip in heights `ph` (second difference per metre, 1/m), where it is (m along), and the
## steepest grade.
static func profile(ph: PackedFloat64Array) -> Dictionary:
	var st := AdventureRoute.STEP
	var worst := 0.0
	var at := 0.0
	var grade := 0.0
	for i in range(1, ph.size() - 1):
		var d2 := absf(ph[i + 1] - 2.0 * ph[i] + ph[i - 1]) / (st * st)
		if d2 > worst:
			worst = d2
			at = i * st
		grade = maxf(grade, absf(ph[i + 1] - ph[i]) / st)
	return {"curve": worst, "at": at, "grade": grade}


## Every way through route `r`'s forks in turn (the main road, then the second way at every fork, ...): their profiles.
static func every_way(r: AdventureRoute) -> Array:
	var out := [profile(r.ph)]
	var most := 1
	for f in r.forks.size():
		most = maxi(most, (r.forks[f]["ways"] as Array).size())
	for w in range(1, most):
		for f in r.forks.size():
			r.choose(f, mini(w, (r.forks[f]["ways"] as Array).size() - 1))
		out.append(profile(r.ph))
	return out


static func _worst(rows: Array) -> Dictionary:
	var w: Dictionary = rows[0]
	for r: Dictionary in rows:
		if float(r["curve"]) > float(w["curve"]):
			w = r
	return w


## The smoothing itself: the ends stay put, a kink is rounded off over tens of metres, it gets no steeper.
func test_fair() -> void:
	var h := PackedFloat64Array()
	for i in 200:
		h.append(100.0 + (0.15 * 4.0 * i if i < 100 else 60.0 - 0.12 * 4.0 * (i - 100)))   # up at 15%, then down at 12%
	var before := profile(h)
	var f := AdventureRoute.fair_heights(h)
	var after := profile(f)
	check(f.size() == h.size() and absf(f[0] - h[0]) < 1e-9 and absf(f[-1] - h[-1]) < 1e-9, "smoothing leaves the road's ends where they are")
	check(float(before["curve"]) > 0.06 and float(after["curve"]) < REAL_CURVE,
		"a crest from +15%% to -12%% in one knot (%.4f /m) is rounded off (%.4f /m)" % [before["curve"], after["curve"]])
	check(float(after["grade"]) <= float(before["grade"]) + 1e-9, "and is no steeper anywhere (%.1f%%)" % (float(after["grade"]) * 100.0))
	var lift := 0.0
	for i in h.size():
		lift = maxf(lift, absf(f[i] - h[i]))
	check(lift < 5.0, "the road's cut into the crest by %.1f m at the most" % lift)
	var same := AdventureRoute.fair_heights(h)
	check(same == f, "and the same every time (every player's road is)")


## The real roads, the baked ones and one planned over a region, every way through their forks: no sharp crest or
## dip, nowhere steeper than the data allows.
func test_real() -> void:
	for id in ["shodoshima", "dales"]:
		var pack := AdventurePlans.pack_for(AdventurePlans.tour(id))
		var r := AdventureRoute.new()
		r.plan_real(pack, 7, pack.max_km())
		var raw := PackedFloat64Array()
		for i in r.ph.size():
			raw.append(pack.e[i])
		var was := profile(raw)
		var ways := every_way(r)
		var w := _worst(ways)
		var steep: float = ways.map(func(x): return float(x["grade"])).max()
		check(float(w["curve"]) < REAL_CURVE and steep < REAL_GRADE,
			"%s (%d ways): its sharpest crest or dip %.4f /m (%.1f m/s² at 90 km/h, at %.0f m; it was %.4f, %.1f m/s²), steepest %.1f%%" % [
			pack.title, ways.size(), w["curve"], float(w["curve"]) * 625.0, w["at"], was["curve"], float(was["curve"]) * 625.0, steep * 100.0])
	var rg := RealRegion.get_region("shodoshima")
	var res := RoutePlanner.plan(rg, {"pins": [rg.geo_to_xz(34.518638, 134.269646), rg.geo_to_xz(34.499373, 134.347915)], "mode": "main"})
	var planned: RealPack = res.get("pack")
	check(planned != null, "a journey planned over Shodoshima")
	if planned == null:
		return
	var pr := AdventureRoute.new()
	pr.plan_real(planned, 5, planned.max_km())
	var p := profile(pr.ph)
	check(float(p["curve"]) < REAL_CURVE and float(p["grade"]) < REAL_GRADE,
		"and a journey planned over a region: sharpest %.4f /m (%.1f m/s² at 90 km/h), steepest %.1f%%" % [p["curve"], float(p["curve"]) * 625.0, float(p["grade"]) * 100.0])


## Where a real fork's way leaves the road and comes back to it: the same height and the same grade, no step or kink.
func test_fork_joins() -> void:
	var pack := AdventurePlans.pack_for(AdventurePlans.tour("dales"))
	var r := AdventureRoute.new()
	r.plan_real(pack, 7, pack.max_km())
	check(not r.forks.is_empty(), "the Dales ride has forks (%d)" % r.forks.size())
	var worst := 0.0
	var where := ""
	for f in r.forks.size():
		for w in range(1, (r.forks[f]["ways"] as Array).size()):
			r.choose(f, w)
			for s: float in [r.fork_s(f), r.rejoin_s(f)]:
				var i := int(round(s / AdventureRoute.STEP))
				for k in range(i - 3, i + 4):
					var d2 := absf(r.ph[k + 1] - 2.0 * r.ph[k] + r.ph[k - 1]) / 16.0
					if d2 > worst:
						worst = d2
						where = "fork %d way %d at %.0f m" % [f, w, s]
	check(worst < REAL_CURVE, "every way at every fork joins the road smoothly both ends (sharpest %.4f /m, %s)" % [worst, where])


## The road's surface runs on from chunk to chunk with no step, its collision is the very surface drawn, and a side
## road's mouth lies on the road's tarmac rather than standing up off it.
func test_surface() -> void:
	for real_id in ["shodoshima", "dales"]:
		var r := AdventureRoute.new()
		r.plan_real(AdventurePlans.pack_for(AdventurePlans.tour(real_id)), 7, 30.0)
		var step := 0.0
		var odd := 0
		var lip := 0.0
		var mouths := 0
		var prev := {}
		for c in 40:
			var d := AdventureChunk.build(r, c)
			var v: PackedVector3Array = d["road"][Mesh.ARRAY_VERTEX]
			if not prev.is_empty():
				var pv: PackedVector3Array = prev["road"][Mesh.ARRAY_VERTEX]
				var rows := pv.size() / 5
				for k in 5:
					var a := pv[(rows - 1) * 5 + k] + Vector3(prev["ax"], 0.0, prev["az"])
					var b := v[k] + Vector3(d["ax"], 0.0, d["az"])
					step = maxf(step, a.distance_to(b))
			# The collision: the drawn triangles, every one (those at the chunk's ends run on a few cm along the
			# road, in its own slope, under the next chunk's: every corner of them lies on the line of a drawn edge).
			var idx: PackedInt32Array = d["road"][Mesh.ARRAY_INDEX]
			var faces: PackedVector3Array = d["road_faces"]
			var rows_n := v.size() / 5
			if faces.size() != idx.size():
				odd += 1
			else:
				var drawn := {}
				for q in range(0, idx.size(), 3):
					drawn[[v[idx[q]], v[idx[q + 1]], v[idx[q + 2]]]] = true
				for q in range(0, faces.size(), 3):
					if drawn.has([faces[q], faces[q + 1], faces[q + 2]]):
						continue
					# An end triangle: each corner either a drawn vertex, or an end vertex run on along its edge.
					for p: Vector3 in [faces[q], faces[q + 1], faces[q + 2]]:
						var ok := v.has(p)
						for k in 5:
							for ends: Array in [[k, 5 + k], [(rows_n - 1) * 5 + k, (rows_n - 2) * 5 + k]]:
								var a := v[ends[0]]
								var b := v[ends[1]]
								var on := a + (a - b).normalized() * AdventureChunk.SEAM_OVERLAP
								ok = ok or p.distance_to(on) < 1e-4
						if not ok:
							odd += 1
			# Side roads' mouths: any of their points over the main road's tarmac sits on it.
			for surf in d["arms"]:
				var av: PackedVector3Array = d["arms"][surf]["v"]
				for p in av:
					var hit := r.locate(p.x + float(d["ax"]), p.z + float(d["az"]), int(d["i0"]))
					if hit.is_empty():
						continue
					var e := r.width[int(hit["i"])] * 0.5
					var lat := absf(float(hit["lat"]))
					if lat < e - 0.05:
						var f := lat / e
						var y := r.height_at_s(float(hit["s"])) + AdventureChunk.CROWN * (1.0 - f * f)
						lip = maxf(lip, p.y - y)
						mouths += 1
			prev = d
		var nm := "the Dales road" if real_id == "dales" else "the Shodoshima road"
		check(step < SEAM, "%s: the road runs on from chunk to chunk without a step (%.4f m at the most)" % [nm, step])
		check(odd == 0, "%s: its collision is the road as drawn, triangle for triangle (overlapping the next chunk's by %.0f cm)" % [nm, AdventureChunk.SEAM_OVERLAP * 100.0])
		# Side roads now begin at the road's edge, so few or no points reach over its tarmac; any that do sit on it.
		check(lip < 0.03, "%s: no side road's mouth stands proud of its tarmac (%d points over it, %.3f m up at the most)" % [nm, mouths, lip])


## Up the stack of hairpins on the tour of Shodoshima (21 km in, the legs under 20 m apart and 120 m apart along the
## road): no land from the next leg stands up through the road (its wide triangles reached over it by as much as half
## a metre: a hump, then a drop).
func test_land_under() -> void:
	var r := AdventureRoute.new()
	r.plan_real(AdventurePlans.pack_for(AdventurePlans.tour("shodoshima")), 11, 23.0)
	for f in r.forks.size():
		r.choose(f, 0)   # (nothing past a fork still open is built)
	var s0 := 20600.0
	var s1 := 21900.0
	# Every land triangle near the stretch, filed by the 8 m cells its box covers (route frame).
	var cells := {}
	var tris := []
	for c in range(AdventureRoute.chunk_of(s0) - 2, AdventureRoute.chunk_of(s1) + 3):
		var d := AdventureChunk.build(r, c)
		var o := Vector3(float(d["ax"]), 0.0, float(d["az"]))
		for side: int in [-1, 1]:
			var v: PackedVector3Array = d["land_%d" % side][Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = d["land_%d" % side][Mesh.ARRAY_INDEX]
			for q in range(0, idx.size(), 3):
				var a := v[idx[q]] + o
				var b := v[idx[q + 1]] + o
				var cc := v[idx[q + 2]] + o
				var lo := Vector2i(floori(minf(a.x, minf(b.x, cc.x)) / 8.0), floori(minf(a.z, minf(b.z, cc.z)) / 8.0))
				var hi := Vector2i(floori(maxf(a.x, maxf(b.x, cc.x)) / 8.0), floori(maxf(a.z, maxf(b.z, cc.z)) / 8.0))
				if (hi - lo).x > 40 or (hi - lo).y > 40:
					continue   # (the far side running down under everything)
				tris.append([a, b, cc])
				for gx in range(lo.x, hi.x + 1):
					for gz in range(lo.y, hi.y + 1):
						var key := Vector2i(gx, gz)
						if not cells.has(key):
							cells[key] = []
						cells[key].append(tris.size() - 1)
	var worst := -INF
	var at := ""
	var under := 0
	var s := s0
	while s < s1:
		var e := r.width_at_s(s) * 0.5
		for f: float in [-0.85, -0.4, 0.0, 0.4, 0.85]:
			var xz := r.xz_at(s, f * e)
			var p := Vector2(xz[0], xz[1])
			var road := r.height_at_s(s) + AdventureChunk.CROWN * (1.0 - f * f)
			for ti in cells.get(Vector2i(floori(p.x / 8.0), floori(p.y / 8.0)), []):
				var tr: Array = tris[ti]
				var a: Vector3 = tr[0]
				var b: Vector3 = tr[1]
				var cc: Vector3 = tr[2]
				var w = Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(cc.x, cc.z))
				if not w:
					continue
				under += 1
				# The land's height there, on the triangle's plane.
				var n := (b - a).cross(cc - a)
				if absf(n.y) < 1e-6:
					continue
				var y := a.y - (n.x * (p.x - a.x) + n.z * (p.y - a.z)) / n.y
				if y - road > worst:
					worst = y - road
					at = "%.0f m, %.1f m across" % [s, f * e]
		s += 2.0
	check(under > 0 and worst < 0.01, "up Shodoshima's hairpins no land stands through the road (%d points of it over the next leg's land, the highest of that %+.2f m from its surface, at %s)" % [under, worst, at])


## Ridden at 90 km/h over the worst of Shodoshima's roads, its stack of hairpins (the bike held to its lane, everything
## up and down left to its suspension): no jolt to speak of, and it doesn't throw you off.
func test_ride() -> void:
	var w := AdventureWorld.new()
	w.setup(AdventurePlans.pack_for(AdventurePlans.tour("shodoshima")), 11, 23.0)
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	var s0 := 20500.0
	var s1 := 21900.0
	var bike := Bike.new()
	bike.setup(BikeBuild.new(Contracts.style_build("classic")))
	var spot := {"p": w.transform_at(s0).origin}
	w.focus = func(): return [spot["p"]]
	t.add_child(w)
	t.add_child(bike)
	bike.can_sleep = false
	w.origin_shifted.connect(func(d): spot["p"] -= d; bike.shift_origin(d))
	var weather = Weather.current
	Weather.current = null
	w.preload_range(s0 - 60.0, s1 + 100.0)
	var lat := -1.6
	var xf := w.transform_at(s0, lat)
	bike.place(xf.origin, w.heading_at(s0))
	await t.get_tree().physics_frame
	var v := 25.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var s := s0
	var k := 0
	var vy_was := NAN
	var acc := PackedFloat32Array()
	var acc_s := PackedFloat32Array()   # (where along the road each was)
	var crashed := false
	while s < s1:
		k += 1
		s += v * dt
		var at := w.transform_at(s, lat)
		hold(bike, at.basis, Vector3(at.origin.x, bike.global_position.y, at.origin.z), v)
		spot["p"] = bike.global_position
		await t.get_tree().physics_frame
		crashed = crashed or bike.is_crashed
		if k > Engine.physics_ticks_per_second:
			if not is_nan(vy_was):
				acc.append((bike.linear_velocity.y - vy_was) / dt)
				acc_s.append(s)
			vy_was = bike.linear_velocity.y
	Weather.current = weather if is_instance_valid(weather) else null
	bike.queue_free()
	w.queue_free()
	await t.get_tree().process_frame
	var worst := felt_at(acc)
	check(not crashed and float(worst[0]) < 2.5, "Shodoshima at 90 km/h: never thrown off, the bike lifted or dropped %.1f m/s² at the most (over a tenth of a second, at %.0f m)" % [
		worst[0], acc_s[int(worst[1])] if not acc_s.is_empty() else 0.0])


## Holds `bike` on its line along the road: where it is across and along it, and which way it faces, from `road` and
## `p`, at `v` m/s; its height, its pitch and how fast it's rising are its own, the suspension's work.
static func hold(bike: Bike, road: Basis, p: Vector3, v: float) -> void:
	var pitch := asin(clampf((-bike.global_transform.basis.z).y, -1.0, 1.0))
	var b := road * Basis(Vector3.RIGHT, pitch)
	var vy := bike.linear_velocity.y
	var spin := b.x * bike.angular_velocity.dot(b.x)
	var ahead := -road.z * v
	bike.global_transform = Transform3D(b, p)
	bike.linear_velocity = Vector3(ahead.x, vy, ahead.z)
	bike.angular_velocity = spin
	bike.steer = 0.0
	bike.throttle = 0.0
	for wh in bike.wheels:
		wh["omega"] = v / float(wh["radius"])


## The biggest vertical acceleration in `acc` (m/s² a tick) felt over a tenth of a second (the tyres' rumble over the
## road's grain left out).
static func felt(acc: PackedFloat32Array) -> float:
	return float(felt_at(acc)[0])


## felt(acc), and the index in `acc` where it was felt: [m/s², index].
static func felt_at(acc: PackedFloat32Array) -> Array:
	var win := maxi(1, int(0.1 * Engine.physics_ticks_per_second))
	var sum := 0.0
	var most := 0.0
	var at := 0
	for i in acc.size():
		sum += acc[i]
		if i >= win:
			sum -= acc[i - win]
			if absf(sum / win) > most:
				most = absf(sum / win)
				at = i
	return [most, at]
