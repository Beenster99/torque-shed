extends RefCounted
## The places along an adventure road's checks (AdventureStops: villages, cafes, lay-bys, rest
## areas, viewpoints, inns, campsites and the fuel stations' shops), run from tests/run_tests.gd:
## its _test_adv_stops_* functions hand over to these.

const SEEDS := [1, 7, 42, 99, 2024]

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


func _until(cond: Callable, seconds := 20.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await t.get_tree().process_frame
	return cond.call()


func _world(seed: int, km: float, spot: Dictionary) -> AdventureWorld:
	var w := AdventureWorld.new()
	w.setup(seed, km)
	spot["p"] = w.transform_at(20.0).origin
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	return w


static func _gaps(list: Array, from := 0.0) -> Array:
	var out := []
	var prev := from
	for s in list:
		out.append(float(s) - prev)
		prev = float(s)
	return out


## The nodes of `group` belonging to the stop at `s` (by their meta "s").
func _in_group(group: String, s: float) -> Array:
	return t.get_tree().get_nodes_in_group(group).filter(func(n): return absf(float(n.get_meta("s", -1.0)) - s) < 1.0)


## For several seeds and lengths: food every 15-25 km (the first within 15 km), somewhere to pull
## in every 5-10 km, an inn or campsite every 40-60 km, never on top of each other or a fuel
## station; a 60 km ride passes a good mix; the same seed plans the same stops.
func test_spacing() -> void:
	var tol := 1600.0   # a stop may be nudged this far to find room
	var bad := []
	var kinds := {}
	for seed in SEEDS:
		for km in [60.0, 150.0]:
			var r := AdventureRoute.new()
			r.plan(seed, km)
			var food := []
			var rest := []
			var sleep := []
			var all := []
			for st in AdventureStops.stops(r):
				var s := float(st["s"])
				var nav: String = AdventureStops.NAV[str(st["kind"])]
				kinds[str(st["kind"])] = true
				all.append(st)
				if nav == "food" or nav == "sleep":
					food.append(s)
				if nav == "sleep":
					sleep.append(s)
				if nav == "rest":
					rest.append(s)
			var fg := _gaps(food)
			var rg := _gaps(rest)
			var sg := _gaps(sleep)
			var tag := "seed %d %d km" % [seed, int(km)]
			if fg.is_empty() or fg[0] > AdventureStops.FOOD_FIRST[1] + tol or fg.slice(1).any(func(g): return g < AdventureStops.FOOD_EVERY[0] - tol or g > AdventureStops.FOOD_EVERY[1] + tol):
				bad.append("%s food %s" % [tag, str(fg.map(func(g): return snappedf(g / 1000.0, 0.1)))])
			if r.length - food[-1] > AdventureStops.FOOD_EVERY[1] + 2500.0 + tol:
				bad.append("%s no food near the end" % tag)
			if rg.is_empty() or rg[0] > AdventureStops.REST_FIRST[1] + tol or rg.slice(1).any(func(g): return g < AdventureStops.REST_EVERY[0] - tol or g > AdventureStops.REST_EVERY[1] + tol):
				bad.append("%s rest %s" % [tag, str(rg.map(func(g): return snappedf(g / 1000.0, 0.1)))])
			if sg.any(func(g): return g < AdventureStops.SLEEP_EVERY[0] - tol or g > AdventureStops.SLEEP_EVERY[1] + tol):
				bad.append("%s sleep %s" % [tag, str(sg.map(func(g): return snappedf(g / 1000.0, 0.1)))])
			if km >= 150.0 and sleep.size() < 2:
				bad.append("%s only %d beds" % [tag, sleep.size()])
			if km == 60.0:
				var mix := {}
				for st in all:
					mix[str(st["kind"])] = true
				if food.size() < 2 or rest.size() < 5 or r.sites_of("fuel").is_empty() or not (mix.has("village") or mix.has("cafe")):
					bad.append("%s mix %s" % [tag, str(mix.keys())])
			for st in all:
				for other in r.sites:
					if other != st and str(other["kind"]) != AdventureStops.ROW and absf(float(other["s"]) - float(st["s"])) < AdventureStops.CLEAR - 1.0:
						bad.append("%s %s at %.0f is on top of %s" % [tag, st["kind"], float(st["s"]), other["kind"]])
	check(bad.is_empty(), "stops are spaced right on every seed: food 15-25 km, pull-ins 5-10 km, beds 40-60 km %s" % str(bad))
	check(kinds.size() == AdventureStops.KINDS.size(), "every kind of stop turns up somewhere %s" % str(kinds.keys()))
	var a := AdventureRoute.new()
	a.plan(42, 80.0)
	var b := AdventureRoute.new()
	b.plan(42, 80.0)
	var same := a.sites.size() == b.sites.size()
	for k in mini(a.sites.size(), b.sites.size()):
		same = same and a.sites[k]["kind"] == b.sites[k]["kind"] and a.sites[k]["s"] == b.sites[k]["s"] and a.sites[k]["name"] == b.sites[k]["name"]
	check(same, "the same seed plans the same stops, names and all (%d sites)" % a.sites.size())
	var vil: Array = a.sites_of("village") + b.sites_of("village")
	if not vil.is_empty():
		var rows := a.sites.filter(func(st): return str(st["kind"]) == AdventureStops.ROW and float(st.get("main_s", -1.0)) == float(vil[0]["s"]))
		check(rows.size() == 5, "a village has a high street: %d more rows of shops" % rows.size())
	# The road's straight and level past a stop.
	var st0: Dictionary = AdventureStops.stops(a)[0]
	var i0 := int(st0["i"])
	var straight := true
	for i in range(i0 - 12, i0 + 12):
		straight = straight and absf(a.curv[i]) < 1e-5
	check(straight, "the road runs straight past a stop (%s at %.1f km)" % [st0["kind"], float(st0["s"]) / 1000.0])


## The first stop of `kind` on any of the seeds: [seed, site].
static func _find(kind: String, km := 150.0) -> Array:
	for seed in SEEDS + [3, 5, 11, 13, 17, 19]:
		var r := AdventureRoute.new()
		r.plan(seed, km)
		var list := r.sites_of(kind)
		if not list.is_empty():
			return [seed, list[0]]
	return []


## Each kind of stop, built in the world: its seats (with a facing, over solid ground), counters
## with a proper menu, beds at the inn and campsite, hard ground to pull onto, and a sign before it.
func test_groups() -> void:
	var report := []
	for kind in AdventureStops.KINDS + ["fuel"]:
		var found := _find(kind)
		if found.is_empty():
			check(false, "a %s turns up on some seed" % kind)
			continue
		var spot := {}
		var w := _world(int(found[0]), 150.0, spot)
		var s := float(found[1]["s"])
		var side := float(found[1]["side"])
		spot["p"] = w.transform_at(s).origin
		w.preload_range(s - 400.0, s + 200.0)
		await t.get_tree().physics_frame
		await t.get_tree().physics_frame
		var seats := _in_group(AdventureStops.SEAT_GROUP, s)
		var counters := _in_group(AdventureStops.COUNTER_GROUP, s)
		var beds := _in_group(AdventureStops.BED_GROUP, s)
		var space := w.get_world_3d().direct_space_state
		var seat_ok := true
		for n: Node3D in seats:
			var f := -n.global_basis.z
			var h := float(n.get_meta("height", -1.0))
			var q := PhysicsRayQueryParameters3D.create(n.global_position + Vector3.UP * 0.3, n.global_position + Vector3.DOWN * (h + 0.6), 1)
			var ground := space.intersect_ray(q)
			var hit := w.locate_local(n.global_position)
			seat_ok = seat_ok and absf(f.length() - 1.0) < 0.01 and absf(f.y) < 0.01 and h > 0.2 and h < 0.8 and not ground.is_empty() \
				and str(n.get_meta("seat", "")) != "" and str(n.get_meta("site", "")) != "" and not hit.is_empty() \
				and absf(float(hit["s"]) - s) < 80.0 and (signf(float(hit["lat"])) == side or kind == "village")   # a high street's both sides
		var menu_ok := not counters.is_empty()
		for n: Node3D in counters:
			var menu: Array = n.get_meta("menu", [])
			menu_ok = menu_ok and menu.size() >= 3 and str(n.get_meta("shop", "")) != ""
			for item in menu:
				menu_ok = menu_ok and str(item.get("id", "")) != "" and str(item.get("name", "")) != "" and float(item.get("price", 0.0)) > 0.0 \
					and float(item["food"]) >= 0.0 and float(item["food"]) <= 1.0 and float(item["drink"]) >= 0.0 and float(item["drink"]) <= 1.0 \
					and float(item["food"]) + float(item["drink"]) > 0.0
			menu_ok = menu_ok and menu.any(func(m): return float(m["drink"]) > 0.0)
		var want_seats := {"village": 10, "cafe": 12, "layby": 4, "rest_area": 12, "viewpoint": 6, "inn": 12, "campsite": 8, "fuel": 2}
		var want_beds := {"inn": 4, "campsite": 6}
		var beds_ok := beds.size() >= int(want_beds.get(kind, 0)) and beds.all(func(n): return float(n.get_meta("price", 0.0)) > 0.0 and str(n.get_meta("bed", "")) in ["room", "tent"])
		if kind not in want_beds:
			beds_ok = beds.is_empty()
		var food_kinds := ["village", "cafe", "inn", "campsite", "fuel"]
		check(seats.size() >= int(want_seats[kind]) and seat_ok, "a %s has %d places to sit, each facing a way over solid ground beside the road" % [kind, seats.size()])
		if kind in food_kinds:
			check(menu_ok, "a %s has %d counters selling food and drink" % [kind, counters.size()])
		check(beds_ok, "a %s has %d beds" % [kind, beds.size()])
		# Hard ground off the road to pull onto, its surface where the tyres find it.
		var pad := AdventureStops.PADS.get(kind, [3.0, 10.0]) as Array
		var pp := w.transform_at(s, side * (w.route.width_at_s(s) * 0.5 + 0.9 + minf(float(pad[0]) * 0.5, 4.0))).origin
		var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 2.0, pp + Vector3.DOWN * 2.0, 1))
		var surf := str((ray["collider"] as Object).get_meta("surface", "")) if ray else ""
		check(surf in ["tarmac", "gravel"] and AdventureWorld.surface_at(pp) in ["tarmac", "gravel"], "and hard ground to pull onto (%s)" % surf)
		if kind != "fuel":
			var roots := w.find_children("Stop_%s_%d" % [kind, int(s)], "", true, false)
			var sign: Label3D = roots[0].get_meta("sign") if not roots.is_empty() else null
			var sh: Dictionary = w.locate_local(sign.global_position) if sign else {}
			var sign_ok: bool = sign != null and not sh.is_empty() and absf(float(sh["s"]) - (s - AdventureStops.SIGN_BEFORE)) < 3.0 and float(sh["lat"]) < 0.0 \
				and str(found[1]["name"]).length() > 0 and (sign.text.contains(str(found[1]["name"])) or kind in ["layby", "rest_area"])
			var faces: bool = sign != null and sign.global_basis.z.dot(w.transform_at(s - AdventureStops.SIGN_BEFORE).basis.z) > 0.9
			check(sign_ok and faces, "with a sign %d m before it on the left verge facing riders coming (%s)" % [int(AdventureStops.SIGN_BEFORE), sign.text.replace("\n", " / ") if sign else "none"])
		report.append("%s: %d seats, %d counters, %d beds" % [kind, seats.size(), counters.size(), beds.size()])
		w.queue_free()
		await _frames(2)
	print("    STOPS: ", ", ".join(report))


## The satnav lists the next stops ahead in order (fuel among them), and draws them.
func test_satnav() -> void:
	var spot := {}
	var w := _world(42, 60.0, spot)
	var nav := Satnav.AdventureNav.new(w)
	var at := w.transform_at(1000.0)
	var p := Vector2(at.origin.x, at.origin.z)
	var fwd3 := -at.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z)
	var list: Array = nav.satnav_stops(p, fwd, 3)
	var ahead := w.route.sites.filter(func(st): return AdventureStops.NAV.has(str(st["kind"])) and float(st["s"]) > 1000.0)
	var ok := list.size() == 3
	for k in mini(3, list.size()):
		ok = ok and str(list[k]["name"]) == str(ahead[k]["name"]) and absf(float(list[k]["distance"]) - (float(ahead[k]["s"]) - 1000.0)) < 2.0 \
			and str(list[k]["kind"]) == AdventureStops.NAV[str(ahead[k]["kind"])]
	check(ok, "the satnav lists the next three stops ahead: %s" % str(list.map(func(q): return "%s %.1f km" % [q["label"], float(q["distance"]) / 1000.0])))
	var back: Array = nav.satnav_stops(p, -fwd, 3)
	check(back.all(func(q): return float(q["distance"]) <= 1000.0),
		"turned round it lists what's back the way (%d)" % back.size())
	var fuel_s := float(w.route.sites_of("fuel")[0]["s"])
	var near := w.transform_at(fuel_s - 200.0)
	var l2: Array = nav.satnav_stops(Vector2(near.origin.x, near.origin.z), Vector2(-near.basis.z.x, -near.basis.z.z), 3)
	check(not l2.is_empty() and str(l2[0]["kind"]) == "fuel", "fuel stations are in the list too")
	var v := Satnav.view_for(nav, at.origin, fwd3, 20.0)
	check((v["stops"] as Array).size() == Satnav.STOPS, "the satnav's view carries the stops ahead")
	var screen := SatnavScreen.new()
	screen.size = Vector2(320, 240)
	t.add_child(screen)
	screen.show_view(v)
	await _frames(2)
	check(is_instance_valid(screen), "and the screen draws them")
	screen.queue_free()
	w.queue_free()
	await _frames(2)


## A stop's places go with its chunk once the road behind is freed.
func test_freed() -> void:
	var spot := {}
	var w := _world(42, 60.0, spot)
	var st: Dictionary = AdventureStops.stops(w.route)[0]
	var s := float(st["s"])
	spot["p"] = w.transform_at(s).origin
	await _until(func(): return w.chunks.has(AdventureRoute.chunk_of(s)))
	await _frames(2)
	var before := _in_group(AdventureStops.SEAT_GROUP, s).size()
	spot["p"] = w.transform_at(s + 6000.0).origin
	await _until(func(): return not w.chunks.has(AdventureRoute.chunk_of(s)))
	await _frames(2)
	check(before > 0 and _in_group(AdventureStops.SEAT_GROUP, s).is_empty() and _in_group(AdventureStops.COUNTER_GROUP, s).is_empty(),
		"the %s's %d seats are there when you reach it and gone once it's far behind" % [st["kind"], before])
	w.queue_free()
	await _frames(2)


## What the stops cost: building each kind on the main thread, the plan, and racing past them all.
func test_frame_cost() -> void:
	var worst := {}
	for kind in AdventureStops.KINDS:
		var found := _find(kind)
		if found.is_empty():
			continue
		var r := AdventureRoute.new()
		r.plan(int(found[0]), 150.0)
		var site: Dictionary = found[1]
		var xf := Transform3D(Basis(), Vector3(0, 100, 0))
		for car in AdventureStops.PARKED:
			VehicleModel.parts(car, 0)   # as the adventure's start does
		var t0 := Time.get_ticks_usec()
		var node := AdventureStops.build(r, site, xf)
		worst[kind] = (Time.get_ticks_usec() - t0) / 1000.0
		var tris := 0
		var meshes := 0
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			var m := (mi as MeshInstance3D).mesh
			for k in m.get_surface_count():
				tris += m.surface_get_array_len(k) / 3
		worst[kind + "_tris"] = tris
		worst[kind + "_meshes"] = meshes
		node.free()
	var build_max := 0.0
	for kind in AdventureStops.KINDS:
		build_max = maxf(build_max, float(worst.get(kind, 0.0)))
	check(build_max < 12.0, "each stop builds in a few ms on the main thread (worst %.1f ms) %s" % [build_max, str(worst)])
	var spot := {}
	var w := _world(42, 60.0, spot)
	check(float(w.stats["plan_ms"]) < 1500.0, "planning a 60 km road with its stops takes %.0f ms" % float(w.stats["plan_ms"]))
	await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)))
	var frame_worst := 0.0
	for k in 140:
		spot["p"] = w.transform_at(20.0 + k * 100.0).origin
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		frame_worst = maxf(frame_worst, (Time.get_ticks_usec() - t0) / 1000.0)
		while Time.get_ticks_usec() - t0 < 16000:
			await t.get_tree().process_frame
	var passed := AdventureStops.stops(w.route).filter(func(st): return float(st["s"]) < 14000.0).size()
	check(float(w.stats["commit_ms_max"]) < 25.0 and float(w.stats["stream_ms_max"]) < 30.0,
		"racing past %d stops, a chunk with a stop on it still goes in without a hitch: %s" % [passed, w.timing_text()])
	print("    STOPS TIMING: ", w.timing_text(), "; worst whole frame %.1f ms" % frame_worst)
	w.queue_free()
	await _frames(2)
