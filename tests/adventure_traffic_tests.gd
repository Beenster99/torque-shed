extends RefCounted
## The adventure road's traffic checks (AdventureTraffic on a TrafficStream, and TrafficSounds),
## run from tests/run_tests.gd: its _test_adv_traffic_* functions hand over to these.

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## A world (not streaming: it's stood still, and the traffic is stepped by hand) with its traffic,
## whose riders are at the local positions in `spot["ps"]`. Forks left open if `forks_open`, else
## the main road at each.
func _world(seed: int, km: float, spot: Dictionary, forks_open := false) -> AdventureTraffic:
	var w := AdventureWorld.new()
	w.setup(seed, km)
	if not forks_open:
		for f in w.route.forks.size():
			w.route.choose(f, 0)
	spot["ps"] = [w.transform_at(20.0, -1.5).origin]
	w.focus = func(): return spot["ps"]
	w.origin_shifted.connect(func(d):
		var moved := []
		for p in spot["ps"]:
			moved.append(p - d)
		spot["ps"] = moved)
	w.process_mode = Node.PROCESS_MODE_DISABLED
	t.add_child(w)
	var tr := AdventureTraffic.new()
	w.add_child(tr)
	tr.stream.rng.seed = seed * 31 + 7
	tr.bikers._spawn_timer = INF   # just the traffic (the other bikers have tests of their own)
	return tr


## Puts the riders at these distances along the road (and `lat` across it).
static func _at(tr: AdventureTraffic, spot: Dictionary, list: Array, lat := -1.5) -> void:
	spot["ps"] = list.map(func(s): return tr.world.transform_at(float(s), lat).origin)


## Steps the traffic `seconds` on in `dt` steps (as the physics would).
static func _run(tr: AdventureTraffic, seconds: float, dt := 0.1) -> void:
	for i in int(seconds / dt):
		tr._physics_process(dt)


## A seed whose road (km long) has a village at least `after` m in: [seed, the village's site].
static func _with_village(km: float, after := 3000.0) -> Array:
	for seed in range(1, 80):
		var r := AdventureRoute.new()
		r.plan(seed, km)
		for f in r.forks.size():
			r.choose(f, 0)
		for st in r.sites_of("village"):
			if float(st["s"]) > after and float(st["s"]) < r.length - 3000.0 and (r.forks.is_empty() or float(st["s"]) < r.fork_s(0) - 1500.0):
				return [seed, st]
	return []


func _free(tr: AdventureTraffic) -> void:
	tr.world.queue_free()
	await _frames(2)


## Busier through a village than on the open road: the road says so (busy 1, 30 mph, more
## wanted), and riding there keeps more vehicles round you; both ways, each driver at a pace of
## their own, lorries and coaches among them, and none past the road's ends.
func test_density() -> void:
	var found := _with_village(60.0)
	check(not found.is_empty(), "a road with a village on it")
	if found.is_empty():
		return
	var spot := {}
	var tr := _world(int(found[0]), 60.0, spot)
	var vs := float(found[1]["s"])
	# Somewhere well out of town on a proper tarmac road: the furthest point from every stop.
	var open_s := 0.0
	var best := 0.0
	var r := tr.world.route
	for k in range(40, int(minf(r.length - 1500.0, 40000.0) / 50.0)):
		var s := k * 50.0
		if r.surface_at_s(s) != "tarmac" or r.width_at_s(s) < 5.5 or (not r.forks.is_empty() and s > r.fork_s(0) - 200.0 and s < r.rejoin_s(0) + 200.0):
			continue
		var d := INF
		for st in tr.world.route.sites:
			d = minf(d, absf(float(st["s"]) - s))
		if d > best:
			best = d
			open_s = s
	check(tr.busy_at(vs) > 0.99 and tr.busy_at(open_s) < 0.01 and tr.limit_at(vs) < AdventureTraffic.TOWN_LIMIT + 0.01 \
			and tr.limit_at(vs) > AdventureTraffic.TOWN_LIMIT * 0.75 and tr.limit_at(open_s) > 15.0,
		"the road knows a village from the open road (busy %.2f, %.0f mph through %s; %.2f, %.0f mph at %.1f km)" % [tr.busy_at(vs),
		tr.limit_at(vs) * 2.237, str(found[1]["name"]), tr.busy_at(open_s), tr.limit_at(open_s) * 2.237, open_s / 1000.0])
	var counts := {}
	var dirs := {}
	var kinds := {}
	var paces := []
	for place in [["open", open_s], ["village", vs]]:
		tr.stream.clear()
		_at(tr, spot, [place[1]])
		tr._physics_process(0.1)
		var wanted := tr.stream.wanted()
		var near := 0.0
		var samples := 0
		for i in 1800:
			tr._physics_process(0.1)
			if i > 300 and i % 10 == 0:
				samples += 1
				for d in tr.stream.vehicles:
					if absf(float(d["s"]) - float(place[1])) < 600.0:
						near += 1.0
					dirs[int(d["dir"])] = true
					kinds[str(d["kind"])] = true
					if not paces.has(float(d["pace"])):
						paces.append(float(d["pace"]))
		counts[place[0]] = [wanted, near / maxf(samples, 1)]
	check(int(counts["village"][0]) > int(counts["open"][0]) + 3 and float(counts["village"][1]) > float(counts["open"][1]) * 1.4,
		"more traffic round you in a village than on the open road (wanted %d to %d; %.1f to %.1f within 600 m)" % [counts["village"][0],
		counts["open"][0], counts["village"][1], counts["open"][1]])
	check(dirs.has(1) and dirs.has(-1) and kinds.has("lorry") and kinds.has("coach") and kinds.size() >= 5,
		"going both ways, cars, vans, lorries and buses (%s)" % str(kinds.keys()))
	paces.sort()
	check(paces.size() > 10 and paces[-1] - paces[0] > 0.3, "every driver's pace their own (%d drivers, %.2f to %.2f of the limit)" % [paces.size(), paces[0], paces[-1]])
	# Never past the start: riders at the start line see nothing behind it.
	tr.stream.clear()
	_at(tr, spot, [30.0])
	var behind := 0
	for i in 600:
		tr._physics_process(0.1)
		for d in tr.stream.vehicles:
			if float(d["s"]) < 0.0:
				behind += 1
	check(behind == 0, "nothing drives off the start of the road")
	await _free(tr)


## Lorries (and coaches) crawl up the steep hills while cars keep going: along a made-up road
## climbing at 9%, and on a real one at its steepest.
func test_climb() -> void:
	var stream := TrafficStream.new()
	stream.sample = func(s: float) -> Dictionary:
		return {"pos": Vector3(0.0, s * 0.09, -s), "fwd": Vector3(0, 0, -1), "hw": 3.6, "busy": 0.0, "limit": 22.0, "grade": 0.09}
	t.add_child(stream)
	stream.set_physics_process(false)
	stream.focus_s = 500.0
	stream.despawn = 5000.0
	stream._spawn_timer = 1.0e9   # only these three
	var lorry: Dictionary = stream.find(stream.spawn_at("lorry", 100.0, 1, 20.0))
	var car: Dictionary = stream.find(stream.spawn_at("hatchback", 400.0, 1, 20.0))
	var down: Dictionary = stream.find(stream.spawn_at("lorry", 900.0, -1, 15.0))
	lorry["pace"] = 1.0
	car["pace"] = 1.0
	down["pace"] = 1.0
	for i in 300:
		stream.step(0.05)
	var lv := float(lorry["v"])
	var cv := float(car["v"])
	# Coming down it a lorry holds back in a low gear, but keeps going.
	check(lv < 9.5 and lv > 4.0 and cv > 20.0 and float(down["v"]) > 7.0 and float(down["v"]) < 15.5,
		"up a 9%% hill a lorry crawls at %.0f mph while a car keeps to %.0f (and one coming down holds back to %.0f)" % [lv * 2.237, cv * 2.237, float(down["v"]) * 2.237])
	stream.queue_free()
	# On a real road: the stretch it climbs most steeply.
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var r := tr.world.route
	var steep := 0.0
	var at := 0.0
	for k in range(100, int(minf(r.stream_end(), r.length) / AdventureRoute.STEP) - 100):
		var g := (r.height_at_s((k + 25) * AdventureRoute.STEP) - r.height_at_s(k * AdventureRoute.STEP)) / (25.0 * AdventureRoute.STEP)
		if g > steep:
			steep = g
			at = k * AdventureRoute.STEP
	_at(tr, spot, [at + 300.0])
	var id := tr.stream.spawn_at("lorry", at, 1, 15.0)
	tr.stream.find(id)["pace"] = 1.0
	var slow := INF
	for i in 120:
		tr._physics_process(0.1)
		var d := tr.stream.find(id)
		if not d.is_empty() and float(d["s"]) > at + 30.0 and float(d["s"]) < at + 100.0:
			slow = minf(slow, float(d["v"]))
	check(steep > 0.04 and slow < tr.limit_at(at + 50.0) * 0.8,
		"on the road's steepest climb (%.0f%%) a lorry's down to %.0f mph (the limit's %.0f)" % [steep * 100.0, slow * 2.237, tr.limit_at(at + 50.0) * 2.237])
	await _free(tr)


## Buses stop at a village's bus stop: one already stood there as you ride in, at the kerb by
## the shelter; and one coming along pulls in (indicating), waits, indicates out and goes.
func test_bus() -> void:
	var found := _with_village(60.0)
	if found.is_empty():
		check(false, "a road with a village on it")
		return
	var spot := {}
	var tr := _world(int(found[0]), 60.0, spot)
	tr.bus_chance = 1.0
	var v: Array = tr._villages[0]
	for k in tr._villages:
		if absf(float(k[0]) - float(found[1]["s"])) < 1.0:
			v = k
	var stop_s := float(v[1])
	var dir := int(v[2])
	# Riding in towards the village.
	_at(tr, spot, [stop_s - 500.0])
	tr._physics_process(0.1)
	var waiting := {}
	for d in tr.stream.vehicles:
		if str(d["kind"]) == "coach" and d.get("bus", false) and absf(float(d["s"]) - stop_s) < 12.0:
			waiting = d
	check(not waiting.is_empty() and int(waiting["dir"]) == dir and float(waiting["v"]) == 0.0,
		"a bus is stood at %s's stop as you come in" % str(found[1]["name"]))
	if not waiting.is_empty():
		tr._physics_process(2.0)
		var where := tr.stream.slot(int(waiting["seed"]))
		var hw := tr.world.route.width_at_s(stop_s) * 0.5
		var stop_xf := tr.world.transform_at(stop_s, float(found[1]["side"]) * (hw + 0.9 + 2.6))
		check(absf(float(where["lat"])) > hw - 1.6 and signf(float(where["lat"])) == -dir and (where["pos"] as Vector3).distance_to(stop_xf.origin) < 12.0,
			"at the kerb by the shelter (%.1f m off the middle of a %.1f m road, its middle %.1f m from the shelter)" % [absf(float(where["lat"])),
			hw * 2.0, (where["pos"] as Vector3).distance_to(stop_xf.origin)])
	# A service bus coming along to the stop from 300 m off.
	tr.stream.clear()
	tr._buses_done[stop_s] = true
	var id := tr.stream.spawn_at("coach", stop_s - dir * 300.0, dir, 12.0, {"bus": true})
	var stopped_at := INF
	var pulled_in_ind := false
	var out_ind := false
	var stood := 0.0
	var gone := false
	for i in 900:
		tr._physics_process(0.1)
		var d := tr.stream.find(id)
		if d.is_empty():
			break
		if float(d["v"]) < 0.05 and d.has("dwell"):
			stood += 0.1
			stopped_at = minf(stopped_at, absf(float(d["s"]) + dir * TrafficVehicle.half_length_of("coach") - (stop_s + dir * 2.5)))
		if int(d["ind"]) == -1 and not d.has("dwell"):
			pulled_in_ind = true
		if int(d["ind"]) == 1:
			out_ind = true
		if stood > 0.0 and float(d["v"]) > 5.0 and (float(d["s"]) - stop_s) * dir > 40.0:
			gone = true
			break
	check(stopped_at < 1.5 and pulled_in_ind and out_ind and stood > TrafficStream.BUS_DWELL[0] - 1.0 and gone,
		"a bus pulls in at the stop (front %.1f m from the door mark, indicating in), waits %.0f s, indicates out and goes" % [stopped_at, stood])
	await _free(tr)


## The riders are in the lanes too: traffic coming up behind a rider stood in the left lane
## stops a gap behind, and what's coming waits for one stood in the right lane.
func test_blockers() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var s := 6000.0
	var results := []
	for case in [[-1.5, 1], [1.5, -1]]:
		tr.stream.clear()
		_at(tr, spot, [s], float(case[0]))
		var dir := int(case[1])
		var id := tr.stream.spawn_at("saloon", s - dir * 150.0, dir, 15.0)
		var gap := INF
		for i in 1200:
			tr._physics_process(0.05)
			var d := tr.stream.find(id)
			if d.is_empty():
				break
			gap = minf(gap, (s - float(d["s"])) * dir - TrafficVehicle.half_length_of("saloon") - 1.2)
		var d := tr.stream.find(id)
		results.append([gap, float(d.get("v", -1.0))])
	check(float(results[0][0]) > 1.5 and float(results[0][0]) < 8.0 and float(results[0][1]) < 0.2,
		"a car stops %.1f m behind a rider stood in its lane" % float(results[0][0]))
	check(float(results[1][0]) > 1.5 and float(results[1][0]) < 8.0 and float(results[1][1]) < 0.2,
		"and one coming waits %.1f m short of a rider stood in the right lane" % float(results[1][0]))
	await _free(tr)


## Only on the way chosen at each fork and fine across the floating origin: nothing goes past a
## fork that's still open; once it's decided they drive on along the way picked; and when the
## origin moves every vehicle stays at the same place on the route.
func test_forks_origin() -> void:
	var spot := {}
	var seed := 0
	for k in range(1, 40):
		var r := AdventureRoute.new()
		r.plan(k, 80.0)
		if not r.forks.is_empty() and r.fork_s(0) < 40000.0:
			seed = k
			break
	var tr := _world(seed, 80.0, spot, true)
	var r := tr.world.route
	var fork := r.fork_s(0)
	_at(tr, spot, [fork - 300.0], -8.0)   # stood on the verge, out of the traffic's way
	var past := 0
	var seen_near := 0
	for i in 1500:
		tr._physics_process(0.1)
		for d in tr.stream.vehicles:
			if float(d["s"]) > fork:
				past += 1
			if float(d["s"]) > fork - 60.0:
				seen_near += 1
	check(past == 0 and seen_near > 0, "with the fork still open, the traffic goes up to it and no further (%d times near it)" % seen_near)
	tr.world.apply_picks({0: 1})
	tr._physics_process(0.1)
	var on_way := 0
	for i in 1500:
		tr._physics_process(0.1)
		for d in tr.stream.vehicles:
			if float(d["s"]) > fork + 20.0:
				on_way += 1
	var check_s := -1.0
	for d in tr.stream.vehicles:
		if float(d["s"]) > fork + 20.0:
			check_s = float(d["s"])
	var on_road := false
	if check_s > 0.0:
		var id := -1
		for d in tr.stream.vehicles:
			if float(d["s"]) == check_s:
				id = int(d["seed"])
		var p: Vector3 = tr.stream.slot(id)["pos"]
		var hit := tr.world.locate_local(p)
		on_road = not hit.is_empty() and absf(float(hit["s"]) - check_s) < 2.0 and absf(float(hit["lat"])) < 4.0
	check(on_way > 0 and on_road and tr.busy_at(0.0) >= 0.0 and is_same(tr._sites_ref, r.sites),
		"once it's decided they drive on along way B, on its road (and the stops along it are known)")
	# The origin moves under them.
	var before := {}
	for d in tr.stream.vehicles:
		var body: TrafficVehicle = d["body"]
		var xz := tr.world.route_xz(body.global_position)
		before[int(d["seed"])] = [xz[0], xz[1], float(d["s"])]
		d["v"] = 0.0
		d["pace"] = 0.0
	var shift := tr.world.shift_origin_to(spot["ps"][0] + Vector3(1500.0, 0.0, -900.0))
	tr._physics_process(0.02)
	var worst := 0.0
	for d in tr.stream.vehicles:
		if not before.has(int(d["seed"])):
			continue
		var b: Array = before[int(d["seed"])]
		var xz := tr.world.route_xz((d["body"] as Node3D).global_position)
		worst = maxf(worst, Vector2(xz[0] - b[0], xz[1] - b[1]).length() if absf(float(d["s"]) - float(b[2])) < 0.01 else 99.0)
	check(shift.length() > 500.0 and before.size() > 0 and worst < 0.05,
		"the origin moves %.0f m and the %d vehicles stay where they were on the route (%.3f m at worst)" % [shift.length(), before.size(), worst])
	await _free(tr)


## The police's way in: a vehicle of a given kind put in at s and dir, read back, taken over
## (moved by hand to the verge with its lights flag, kept even far away), sent to the crew as
## it is, and handed back to drive on in its lane.
func test_takeover() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var s := 5000.0
	_at(tr, spot, [s])
	var st := tr.stream
	var id := st.spawn_at("estate", s + 300.0, -1, 0.0)
	var info := st.slot(id)
	check(id >= 0 and str(info["kind"]) == "estate" and int(info["dir"]) == -1 and absf(float(info["s"]) - s - 300.0) < 0.01 and info["pos"] is Vector3,
		"a vehicle of a given kind goes in at s and dir and can be read back (%s)" % str(info.keys()))
	var d := st.take(id)
	var hw := tr.world.route.width_at_s(s + 300.0) * 0.5
	d["v"] = 0.0
	d["lat"] = hw + 1.5
	d["aux"] = 3
	d["ind"] = -1
	tr._physics_process(0.1)
	var held := st.slot(id)
	var hit := tr.world.locate_local((d["body"] as Node3D).global_position)
	check(bool(held["scripted"]) and absf(float(held["s"]) - s - 300.0) < 0.01 and absf(float(hit["lat"]) - (hw + 1.5)) < 0.1 and (d["body"] as TrafficVehicle).aux == 3,
		"taken over, it stays where it's put: on the verge %.1f m off the middle" % float(hit["lat"]))
	# The crew get it as it is.
	var client := TrafficStream.new()
	client.sample = st.sample
	client.host = false
	t.add_child(client)
	client.set_physics_process(false)
	client.unpack(st.pack())
	var mirror := client.find(id)
	check(not mirror.is_empty() and absf(float(mirror["lat"]) - (hw + 1.5)) < 0.01 and int(mirror["aux"]) == 3 and int(mirror["ind"]) == -1,
		"the crew see it there, its lights flag and indicator too")
	client.queue_free()
	# Far from everyone it's kept while it's taken over.
	_at(tr, spot, [s + 3000.0])
	tr._physics_process(0.1)
	check(not st.find(id).is_empty(), "kept while taken over, however far off")
	_at(tr, spot, [s])
	st.release(id)
	for i in 100:
		tr._physics_process(0.1)
	var back := st.slot(id)
	check(not back.is_empty() and not bool(back["scripted"]) and float(back["v"]) > 8.0 and float(back["lat"]) > 0.5 and float(back["lat"]) < hw,
		"handed back, it drives on in its own lane (%.1f m/s, %.1f m off the middle)" % [float(back.get("v", 0.0)), float(back.get("lat", 0.0))])
	st.remove_id(id)
	check(st.find(id).is_empty(), "and can be taken off the road")
	await _free(tr)


## The engines: a small pool of players on the nearest few vehicles in hearing only, each
## running faster with road speed; the town's traffic has them too.
func test_sounds() -> void:
	var a := TrafficSounds.make_loop("petrol")
	var b := TrafficSounds.make_loop("diesel")
	check(a.data.size() > 20000 and b.data.size() > 20000 and a.loop_mode == AudioStreamWAV.LOOP_FORWARD, "petrol and diesel engine loops are made")
	var holder := Node3D.new()
	t.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.5, 0)
	var sounds := TrafficSounds.new()
	holder.add_child(sounds)
	var cars := []
	for k in 9:
		var c := TrafficVehicle.new()
		c.setup(["hatchback", "lorry", "coach"][k % 3], k + 1)
		holder.add_child(c)
		c.global_position = Vector3(3.0, 0.0, -10.0 - 22.0 * k)
		cars.append(c)
	var far := TrafficVehicle.new()
	far.setup("saloon", 99)
	holder.add_child(far)
	far.global_position = Vector3(0, 0, 400.0)
	for i in 600:
		if TrafficSounds.loop("petrol") != null:
			break
		await t.get_tree().process_frame
	sounds._timer = 0.0
	await _frames(3)
	var heard := sounds.heard_vehicles()
	var nearest := cars.slice(0, TrafficSounds.POOL)
	check(heard.size() == TrafficSounds.POOL and heard.all(func(c): return nearest.has(c)) and not heard.has(far),
		"only the nearest %d are heard (of %d about), and not one far off" % [heard.size(), cars.size() + 1])
	check(TrafficSounds.revs(20.0, TrafficSounds.VOICE["hatchback"]) > TrafficSounds.revs(0.0, TrafficSounds.VOICE["hatchback"])
		and TrafficSounds.revs(2.0, TrafficSounds.VOICE["lorry"]) > TrafficSounds.revs(0.0, TrafficSounds.VOICE["lorry"]),
		"the engines run up with road speed")
	holder.queue_free()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await _frames(1)
	check(main.traffic.get_node_or_null("VehicleSounds") is TrafficSounds, "the town's traffic is heard too")
	main.queue_free()
	await _frames(2)


## Riding through a village with its traffic, in the real game: the profiler's numbers for the
## traffic (driving, drawing, the adventure's side and the sounds), and a vehicle you hit is solid.
func test_perf() -> void:
	var found := _with_village(40.0, 4000.0)
	if found.is_empty():
		check(false, "a road with a village on it")
		return
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 7)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	Adventure.start(int(found[0]), 40.0)
	for i in 10:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	var tr := AdventureTraffic.current
	check(trip.on_trip() and tr != null and tr.get_parent() == trip.world and tr.host, "the adventure has its traffic")
	if tr == null:
		main.queue_free()
		AdventureTrip.instant = false
		Shed.stop()
		return
	tr.bus_chance = 1.0
	var vs := float(found[1]["s"])
	var from := vs - 700.0
	trip.jump(from - trip.world.distance_of(main.bike.global_position, "own"))
	for i in 30:
		await t.get_tree().physics_frame
	Perf.on = true
	Perf.start_recording()
	# Through the village at 30 mph and out the other side, on the left.
	var s := from
	var most := 0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while s < vs + 500.0:
		s += 13.4 / 60.0
		var xf := trip.world.transform_at(s, -1.6)
		main.bike.place(xf.origin, trip.world.heading_at(s))
		main.bike.linear_velocity = xf.basis * Vector3(0, 0, -13.4)
		await t.get_tree().physics_frame
		Perf.end_frame()
		frames += 1
		most = maxi(most, tr.stream.vehicles.size())
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	Perf.stop_recording()
	var sums: Dictionary = Perf.rec_sums
	var parts := []
	var total := 0.0
	for key in ["adv_traffic", "traffic", "traffic_sound"]:
		var r: Array = sums.get(key, [0, 0, 0])
		var avg := float(r[0]) / 1000.0 / maxf(Perf.rec_frames, 1)
		total += avg if key != "traffic" else 0.0
		parts.append("%s %.3f ms avg, %.2f peak" % [key, avg, float(r[1]) / 1000.0])
	Perf.on = false
	print("    TRAFFIC PROFILE (village, %d vehicles at most, %d frames, %.1f ms a whole frame headless): %s" % [most, frames, wall, ", ".join(parts)])
	check(most >= 5 and total < 1.5, "riding through a village with %d vehicles about, the traffic costs %.2f ms a frame (%s)" % [most, total, ", ".join(parts)])
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
