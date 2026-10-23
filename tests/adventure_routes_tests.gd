extends RefCounted
## The forks on an adventure's road (AdventureRoute's graph of ways, AdventureForks' votes, the
## paper map), run from tests/run_tests.gd: its _test_adv_routes_* functions hand over to these. The forks are where the
## planner found a second way between two junctions of the road (see RoutePlanner.plan_forks): the Dales tour has two.

const Rides := preload("res://tests/rides.gd")

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


## A route along the Dales tour (two forks on it).
static func _route() -> AdventureRoute:
	return Rides.tour_route("dales", 42)


## A world along the Dales tour.
static func _tour_world() -> AdventureWorld:
	var w := AdventureWorld.new()
	w.setup(Rides.tour_pack("dales"), 42)
	return w


## The same plan lays out the same graph, way for way. Each fork has its two ways, of different lengths, and the other
## way meets the road on exactly (same point, heading and height), its knots evenly spaced. The main road everywhere is
## the road as planned.
func test_graph() -> void:
	var a := _route()
	var b := _route()
	var same := a.forks.size() == b.forks.size() and a.forks.size() >= 2
	for f in mini(a.forks.size(), b.forks.size()):
		for w in a.forks[f]["ways"].size():
			var wa: Dictionary = a.forks[f]["ways"][w]
			var wb: Dictionary = b.forks[f]["ways"][w]
			same = same and str(wa["name"]) == str(wb["name"]) and float(wa["len"]) == float(wb["len"])
			if w > 0:
				same = same and wa["px"] == wb["px"] and wa["ph"] == wb["ph"] and wa["chunk_surface"] == wb["chunk_surface"]
	check(same, "the same plan has the same forks and ways (%d forks)" % a.forks.size())
	var differ := true
	var lines := PackedStringArray()
	for f in a.forks.size():
		var ways: Array = a.forks[f]["ways"]
		differ = differ and ways.size() == 2 and float(ways[1]["len"]) != float(ways[0]["len"])
		for way in ways:
			lines.append("%s %s %s" % [way["letter"], way["name"], AdventureForks.way_text(way)])
	check(differ, "each fork's two ways have their own lengths: %s" % "; ".join(lines))
	# The other way meets the road on exactly, evenly spaced.
	var meets := true
	var spacing := true
	for f in a.forks.size():
		var fk: Dictionary = a.forks[f]
		var i1: int = fk["i1"]
		for w in range(1, fk["ways"].size()):
			var way: Dictionary = fk["ways"][w]
			var n: int = way["n"]
			meets = meets and absf(float(way["px"][n - 1]) - float(a._def["px"][i1])) < 0.01 and absf(float(way["pz"][n - 1]) - float(a._def["pz"][i1])) < 0.01 \
				and absf(float(way["hd"][n - 1]) - float(a._def["hd"][i1])) < 1e-9
			for k in range(1, n):
				var d := Vector2(way["px"][k] - way["px"][k - 1], way["pz"][k] - way["pz"][k - 1]).length()
				spacing = spacing and absf(d - AdventureRoute.STEP) < AdventureRoute.STEP * 0.1
	check(meets and spacing, "every other way meets the road on exactly, its knots evenly spaced")
	# The default path is the main road: choosing it changes nothing.
	var px0 := a.px.duplicate()
	var sites0 := a.sites.size()
	a.choose(0, 0)
	var len0 := a.length
	check(a.px == px0 and a.sites.size() == sites0 and a.length == len0, "taking the main road at a fork keeps the road as planned")
	# Choosing another way: the path runs along it, then on along the same road as before.
	var way1: Dictionary = a.forks[0]["ways"][1]
	var main_len := float(a.forks[0]["ways"][0]["len"])
	var fin0 := float(a.sites_of("finish")[0]["s"])
	a.choose(0, 1)
	var shift := float(way1["len"]) - main_len
	var k0 := int(a.fork_s(0) / AdventureRoute.STEP)
	var mid := k0 + int(way1["n"]) / 2
	var after := int(a.rejoin_s(0) / AdventureRoute.STEP) + 500
	check(a.px[mid] == way1["px"][int(way1["n"]) / 2] and a.px[after] == px0[after - int(shift / AdventureRoute.STEP)]
		and absf(a.length - (fin0 + shift)) < 0.01 and float(a.sites_of("finish")[0]["s"]) == a.length,
		"taking %s, the road runs along it and on as before, the destination %.1f km further (%.1f km)" % [way1["name"], shift / 1000.0, a.length / 1000.0])
	# A site added on a way stays on it, and goes when another way's taken.
	var on_way := a.fork_s(0) + 1500.0
	var site := a.add_site("test_stop", on_way, 1, 10.0, "Tea van")
	check(a.sites_of("test_stop").size() == 1 and float(site["s"]) == on_way, "a site added along a way is on the road there")
	a.choose(0, 0)
	check(a.sites_of("test_stop").is_empty(), "and off it when the main road's taken instead")
	a.choose(0, 1)
	check(a.sites_of("test_stop").size() == 1 and float(a.sites_of("test_stop")[0]["s"]) == on_way, "and back with the way")
	# The road and land up to a fork come out the same whichever way is taken: the chunk before
	# it built on one path matches the one built on another.
	var p := _route()
	var q := _route()
	q.choose(0, q.forks[0]["ways"].size() - 1)
	var cf := AdventureRoute.chunk_of(p.fork_s(0)) - 1
	var cp := AdventureChunk.build(p, cf)
	var cq := AdventureChunk.build(q, cf)
	var land_same := true
	for key in cp:
		if (str(key).begins_with("land") or key == "road") and cp[key] is Array and (cp[key] as Array).size() > Mesh.ARRAY_VERTEX:
			land_same = land_same and (cp[key] as Array)[Mesh.ARRAY_VERTEX] == (cq[key] as Array)[Mesh.ARRAY_VERTEX]
	check(land_same and str(cp["mm"]) == str(cq["mm"]), "the road and land up to a fork are the same whichever way's taken")


## Votes go into the shed's state; the host's vote is the pick, and once a fork is due with no
## pick it's the main road. The fork's choice reads the votes; picks can't be changed.
func test_vote() -> void:
	Shed.start_new("Tester", 7)
	var w := _tour_world()
	t.add_child(w)
	Shed.adventure = {"id": 9, "seed": 42, "km": 60.0, "theme": "varied", "by": "Tester", "riders": {}, "arrived": 0, "arrived_name": ""}
	var me := Shed.me()
	var s := w.route.fork_s(0) - 1800.0
	var c := AdventureForks.choice(w.route, s)
	check(not c.is_empty() and int(c["picked"]) < 0 and (c["ways"] as Array).size() == w.route.forks[0]["ways"].size(),
		"1.8 km before the fork the choice comes up: %s" % " / ".join(AdventureForks.choice_lines(c)))
	check(AdventureForks.choice(w.route, w.route.fork_s(0) - 4000.0).is_empty(), "but not 4 km before")
	# Someone else's vote (checked and applied as the host would), then the host's pick.
	Shed.crew[77] = {"name": "Dave"}
	check(AdventureForks.check(77, {"a": "adventure_vote", "fork": 0, "way": 1}) == "", "a rider can vote")
	AdventureForks.apply(77, {"a": "adventure_vote", "fork": 0, "way": 1}, "Dave")
	Shed.adventure["picks"] = {}   # offline everyone's the host: undo that, Dave isn't
	c = AdventureForks.choice(w.route, s)
	check(Array(c["ways"][1]["voters"]).has("Dave") and int(c["picked"]) < 0, "everyone sees Dave's vote for B")
	Shed.request({"a": "adventure_vote", "fork": 0, "way": 2 if w.route.forks[0]["ways"].size() > 2 else 1})
	var pick := AdventureForks.pick_of(0)
	check(pick >= 1 and int(AdventureForks.votes_of(0)[me]) == pick, "the host's vote is the pick (%s)" % AdventureForks.way_name(0, pick))
	check(Shed.check(me, {"a": "adventure_vote", "fork": 0, "way": 0}) != "" or Adventure.check(me, {"a": "adventure_vote", "fork": 0, "way": 0}) != "",
		"and it can't be changed")
	check(Adventure.check(me, {"a": "adventure_vote", "fork": 0, "way": 5}) != "" and Adventure.check(me, {"a": "adventure_vote", "fork": 9, "way": 0}) != "",
		"there's no voting for a way or a fork that isn't there")
	check(w.apply_picks(AdventureForks.picks()) and w.route.decided.has(0) and int(w.route.choices[0]) == pick, "the world takes the pick")
	# Nobody picks at the next fork: once it's due, the main road.
	Shed.request({"a": "adventure_fork_due", "fork": 1})
	check(AdventureForks.pick_of(1) == 0, "nobody picked at the second fork, so it's the main road")
	Shed.request({"a": "adventure_fork_due", "fork": 1})
	check(AdventureForks.pick_of(1) == 0, "and saying so again changes nothing")
	# Old adventure states (no votes) read as none.
	Shed.adventure = Adventure.sanitize({"id": 3, "seed": 1, "km": 30.0})
	check(AdventureForks.picks().is_empty() and AdventureForks.votes().is_empty(), "an adventure from before forks has no votes")
	Shed.adventure = {}
	Shed.crew.erase(77)
	w.queue_free()
	await _frames(2)
	Shed.stop()


## The road's built up to an open fork and no further; once a way's picked only that way is
## built past it (the other ways nowhere), the signpost stands before it, the sat nav shows the
## ways, and the floating origin carries on across the fork as anywhere.
func test_stream() -> void:
	var w := _tour_world()
	var spot := {}
	w.focus = func(): return [spot["p"]]
	w.origin_shifted.connect(func(d): spot["p"] -= d)
	t.add_child(w)
	var r := w.route
	var fs := r.fork_s(0)
	var cf := AdventureRoute.chunk_of(fs)
	spot["p"] = w.transform_at(fs - 1500.0).origin
	await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)))
	var beyond := w.chunks.keys().filter(func(c): return c >= cf)
	check(w.chunks.has(cf - 1) and beyond.is_empty(), "1.5 km before an open fork the road is there up to it and no further (%d chunks)" % w.chunks.size())
	var signs := _find(w.chunks[AdventureRoute.chunk_of(fs - AdventureRoute.SIGN_BEFORE)], "Signpost") != null
	check(signs, "a signpost stands before the fork")
	var nav := Satnav.AdventureNav.new(w)
	var p2 := Vector2(spot["p"].x, spot["p"].z)
	var fwd3 := w.transform_at(fs - 1500.0).basis * Vector3.FORWARD
	var v := Satnav.view_for(nav, spot["p"], fwd3)
	var ahead: PackedVector2Array = v["route"]
	var end_hit := w.locate_local(Vector3(ahead[-1].x, 0.0, ahead[-1].y))
	check(not (v["choice"] as Dictionary).is_empty() and (v["points"] as Array).any(func(q): return q["kind"] == "fork"),
		"the sat nav shows the ways at the fork coming up")
	spot["p"] = w.transform_at(fs - 200.0).origin
	v = Satnav.view_for(nav, spot["p"], fwd3)
	ahead = v["route"]
	end_hit = w.locate_local(Vector3(ahead[-1].x, 0.0, ahead[-1].y))
	check(float(end_hit["s"]) <= fs + 1.0 and (v["roads"] as Array).any(func(rd): return rd["kind"] == "other"),
		"and stops its way ahead at the fork, the other ways drawn off it (%.0f m)" % (float(end_hit["s"]) - fs))
	# The pick: B. Only B is built past the fork.
	var way: Dictionary = r.forks[0]["ways"][1]
	var main_mid := Vector2(r._def["px"][int(r.forks[0]["i0"]) + 400], r._def["pz"][int(r.forks[0]["i0"]) + 400])
	check(w.apply_picks({0: 1}), "the host picks B")
	spot["p"] = w.transform_at(fs + 600.0).origin
	await _until(func(): return w.wanted_chunks().all(func(c): return w.chunks.has(c)), 30.0)
	var on_b := true
	for c in w.chunks:
		if c >= cf and c < AdventureRoute.chunk_of(r.rejoin_s(0)):
			var k: int = c * AdventureRoute.CHUNK_KNOTS - int(fs / AdventureRoute.STEP)
			var node: Node3D = w.chunks[c]
			on_b = on_b and float(node.get_meta("ax")) == float(way["px"][k]) and float(node.get_meta("az")) == float(way["pz"][k])
	var main_hit := r.locate(main_mid.x, main_mid.y)
	var near_main := main_hit.is_empty() or float(main_hit["d"]) > 20.0
	check(on_b and w.chunks.keys().filter(func(c): return c >= cf).size() >= 10 and near_main,
		"past the fork the road's built along B and only B (the main road's middle %s from it)" % ("far" if main_hit.is_empty() else "%.0f m" % float(main_hit["d"])))
	# Across the fork and on, the origin shifts as anywhere and a point keeps its place.
	var s1 := fs + 900.0
	var p := w.transform_at(s1, 1.2).origin
	var d := w.shift_origin_to(p)
	var hit := w.locate_local(p - d)
	check(d.length() > 0.0 and absf(float(hit["s"]) - s1) < 0.05 and absf(float(hit["lat"]) - 1.2) < 0.05,
		"past the fork the origin shifts and the same point is the same place on B (%.2f m, %.2f m right)" % [float(hit["s"]), float(hit["lat"])])
	check(r.fork_at(s1) == 0 and int(r.choices[0]) == 1, "and it's on B there")
	w.queue_free()
	await _frames(2)


static func _find(n: Node, child_name: String) -> Node:
	if n == null:
		return null
	for c in n.get_children():
		if c.name == child_name:
			return c
		var deeper := _find(c, child_name)
		if deeper:
			return deeper
	return null


## Out on an adventure in the game: coming up to a fork the HUD shows the ways, a vote (the host's)
## picks one and the road's built along it; the paper map comes out once stopped (from its key or
## the Esc menu, not while riding) with the whole graph, everyone on it and the vote, and folds away.
func test_map() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	Adventure.start(AdventurePlans.tour("dales"), 42)
	for i in 10:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	var r := trip.world.route
	check(trip.on_trip() and r.forks.size() >= 2, "an adventure with forks")
	trip.jump(r.fork_s(0) - 1500.0 - trip.world.distance_of(main.bike.global_position, "own"))
	for i in 45:
		await t.get_tree().physics_frame
	check(trip._fork_panel.visible and trip._fork_label.text.begins_with("Fork in"), "the HUD shows the fork coming up:\n%s" % trip._fork_label.text)
	# Riding: no map.
	main.bike.speed = 10.0
	check(trip.map_reason() != "", "no map while riding along")
	main.bike.linear_velocity = Vector3.ZERO
	main.bike.speed = 0.0
	await t.get_tree().physics_frame
	main.menu.show_pause()
	check(main.menu._paper_map.visible and not main.menu._paper_map.disabled, "the Esc menu offers the paper map once stopped")
	main.menu._paper_map.pressed.emit()
	await t.get_tree().process_frame
	check(trip.map_open() and not main.menu.visible, "and it opens from there")
	var m: AdventureMap = trip._map
	await _frames(2)
	check(m._lines.size() > 100 and m._riders.size() == 1 and m._fork == 0 and m._vote_box.get_child_count() == r.forks[0]["ways"].size(),
		"with the whole route (%d stretches, %d sites), you on it and a button a way at the fork" % [m._lines.size(), m._sites.size()])
	(m._vote_box.get_child(1) as Button).pressed.emit()
	# (The way's put together off the main thread, and taken in a few frames on: see
	# AdventureWorld.apply_picks_soon.)
	await _until(func(): return r.decided.has(0), 5.0)
	await _frames(2)
	check(AdventureForks.pick_of(0) == 1 and r.decided.has(0) and int(r.choices[0]) == 1 and m._lines.any(func(l): return int(l["fork"]) == 0 and int(l["way"]) == 1 and bool(l["on"])),
		"voting B on the map (the host) picks it, and the map marks it taken")
	m._input(_key_event("paper_map"))
	check(not trip.map_open(), "and it folds away")
	trip.jump(r.fork_s(0) + 1500.0 - trip.world.distance_of(main.bike.global_position, "own"))
	for i in 45:
		await t.get_tree().physics_frame
	var hud: String = trip._hud.text
	check(hud.contains("On B") and not trip._fork_panel.visible, "past the fork the HUD says which way you're on (%s)" % hud)
	trip.jump(r.fork_s(1) + 3000.0 - trip.world.distance_of(main.bike.global_position, "own"))
	await t.get_tree().physics_frame
	var at := trip.world.distance_of(main.bike.global_position, "own")
	check(at < r.fork_s(1) and at > r.fork_s(1) - 100.0, "skipping on stops short of the next fork, still open (%.0f m before it)" % (r.fork_s(1) - at))
	for i in 10:
		await t.get_tree().physics_frame
	check(AdventureForks.pick_of(1) == 0, "and that close with no pick, it's the main road")
	Shed.request({"a": "adventure_end"})
	for i in 10:
		await t.get_tree().physics_frame
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)


static func _key_event(action: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev
