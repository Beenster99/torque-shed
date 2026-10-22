extends RefCounted
## The other bikers on an adventure's road (AdventureBikers, ridden by AdventureTraffic): run from
## tests/run_tests.gd, whose _test_adv_bikers_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## A world stood still (the traffic stepped by hand) with its traffic and bikers, the riders at
## the local positions in spot["ps"] (as AdventureTrafficTests._world). `host` false: a crew
## member's machine. Times how long the bikers' pool took to build into spot["pool_ms"].
func _world(seed: int, km: float, spot: Dictionary, host := true) -> AdventureTraffic:
	var w := AdventureWorld.new()
	w.setup(Rides.pack(km), seed, km)
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
	var t0 := Time.get_ticks_usec()
	w.add_child(tr)
	spot["pool_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	if not host:
		tr.host = false
		tr.stream.host = false
		tr.bikers.host = false
	tr.stream.rng.seed = seed * 31 + 7
	tr.bikers.rng.seed = seed * 17 + 3
	return tr


static func _at(tr: AdventureTraffic, spot: Dictionary, list: Array, lat := -1.5) -> void:
	spot["ps"] = list.map(func(s): return tr.world.transform_at(float(s), lat).origin)


func _free(tr: AdventureTraffic) -> void:
	tr.world.queue_free()
	await _frames(2)


## A stretch of open tarmac road at least `length` m long with no junction or stop on it, from
## `after` m on: its start, or -1.
static func _open_stretch(tr: AdventureTraffic, after: float, length: float) -> float:
	var r := tr.world.route
	var s := after
	while s < r.length - length - 500.0:
		var ok := true
		for st in r.sites:
			var ss := float(st["s"])
			if str(st["kind"]) != "limit" and ss > s - 150.0 and ss < s + length + 150.0:
				ok = false
				s = ss + 160.0
				break
		if ok:
			for k in int(length / 50.0) + 1:
				var i := int((s + k * 50.0) / AdventureRoute.STEP)
				if r.surface_at_s(s + k * 50.0) != "tarmac" or r.width_at_s(s + k * 50.0) < 5.5 or absf(r.smooth_curv(i, 12)) > 1.0 / 150.0:
					ok = false
					s += k * 50.0 + 50.0
					break
		var nf := r.next_fork(s)
		if ok and r.fork_at(s) < 0 and (nf < 0 or r.fork_s(nf) > s + length + 300.0):
			return s
		if ok:
			s += 200.0
	return -1.0


## Rides the riders along the road for `seconds`: each at its s (in `ss`), going at `v` (m/s,
## + the way s grows; a Callable(time) -> v for a changing pace), the traffic stepped as it goes.
## `each` is called every step (with the time); stops early when it returns true.
static func _ride(tr: AdventureTraffic, spot: Dictionary, ss: Array, v, seconds: float, lat := -1.5, each := Callable(), dt := 0.1) -> bool:
	var time := 0.0
	while time < seconds:
		for k in ss.size():
			var vk: float = v.call(time) if v is Callable else float(v)
			ss[k] = float(ss[k]) + vk * dt
		_at(tr, spot, ss, lat)
		tr._physics_process(dt)
		time += dt
		if each.is_valid() and each.call(time):
			return true
	return false


## Bikers turn up both ways, on their own and in groups, on bikes of every style (the pool's all
## different), out of sight, each at a sensible pace for the road (none silly fast, none crawling
## on the open road), leaning into the bends, the groups staggered, never more out than the pool,
## and the pool built behind the fade without much fuss.
func test_spawn() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var b := tr.bikers
	var styles := {}
	for p in b.pool:
		styles[str(p["look"]["style"])] = true
	check(b.pool.size() == AdventureBikers.POOL and styles.size() == AdventureBikers.POOL and b.pool_ms < 6000.0,
		"%d bikes in the pool, every one a different style (%s), built in %.0f ms behind the fade" % [b.pool.size(), ", ".join(styles.keys()), b.pool_ms])
	var same := AdventureBikers.looks_for(tr.world.route.seed_value)
	check(same.size() == b.pool.size() and str(same[3]["style"]) == str(b.pool[3]["look"]["style"]) and same[3]["paint"] == b.pool[3]["look"]["paint"],
		"and the same looks from the same road on every machine")
	var ss := [3000.0]
	var dirs := {}
	var sizes := {}
	# (Numbers a lambda changes are kept in a dictionary: it'd change its own copies of plain ones.)
	var acc := {"most": 0, "nearest": INF, "fast": 0.0, "pace_lo": INF, "pace_hi": 0.0, "lean": 0.0, "stagger": 0.0}
	var seen := {}
	_ride(tr, spot, ss, 22.0, 600.0, -1.5, func(time: float) -> bool:
		acc["most"] = maxi(int(acc["most"]), b.bikers.size())
		for d in b.bikers:
			var id := int(d["id"])
			if not seen.has(int(d["n"])):
				seen[int(d["n"])] = true
				acc["nearest"] = minf(float(acc["nearest"]), absf(float(d["s"]) - float(ss[0])))
			dirs[int(d["dir"])] = true
			var limit := tr.limit_at(float(d["s"]))
			acc["fast"] = maxf(float(acc["fast"]), float(d["v"]) / limit)
			if int(d["lead"]) < 0:
				acc["pace_lo"] = minf(float(acc["pace_lo"]), float(d["pace"]))
				acc["pace_hi"] = maxf(float(acc["pace_hi"]), float(d["pace"]))
			acc["lean"] = maxf(float(acc["lean"]), absf(float(b.pool[id]["roll"])))
			if int(d["lead"]) >= 0:
				var n := 1
				for o in b.bikers:
					if int(o["lead"]) == int(d["lead"]):
						n += 1
				sizes[n] = true
				var lead := b.find(int(d["lead"]))
				if not lead.is_empty() and int(d["slot"]) == 1 and time > 3.0:
					acc["stagger"] = maxf(float(acc["stagger"]), absf(float(d["lat"]) - float(lead["lat"])))
			elif not sizes.has(1):
				var alone := true
				for o in b.bikers:
					if int(o["lead"]) == int(d["id"]):
						alone = false
				if alone:
					sizes[1] = true
		return false)
	check(seen.size() >= 6 and dirs.has(1) and dirs.has(-1) and acc["most"] <= AdventureBikers.POOL,
		"over 10 minutes %d bikers come along, both ways, %d out at most" % [seen.size(), acc["most"]])
	check(sizes.has(1) and sizes.size() >= 2, "riding alone and in groups (of %s)" % str(sizes.keys()))
	check(acc["nearest"] > 300.0, "each turns up out of sight (the nearest %.0f m off)" % acc["nearest"])
	check(acc["fast"] < 1.3 and acc["pace_lo"] > 0.75 and acc["pace_hi"] < 1.25 and acc["pace_hi"] - acc["pace_lo"] > 0.1,
		"each at a pace of their own for the road, %.2f to %.2f of its limit (%.2f at the most)" % [acc["pace_lo"], acc["pace_hi"], acc["fast"]])
	check(acc["lean"] > deg_to_rad(8.0) and acc["lean"] <= Bike.ROAD_LEAN + 0.01, "leaning into the bends (up to %.0f degrees)" % rad_to_deg(acc["lean"]))
	check(acc["stagger"] > 0.7 and acc["stagger"] < 1.6, "a group rides staggered, the second %.2f m across from the leader" % acc["stagger"])
	await _free(tr)


## Ride up behind a biker going your way and keep its pace: it joins the crew. It then keeps its
## place behind you as you speed up and slow down, on the other track to yours, no longer solid,
## stopping when you stop; and one you ride past and keep pace with rides in front.
func test_join() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var b := tr.bikers
	var s0 := _open_stretch(tr, 2500.0, 2500.0)
	check(s0 > 0.0, "an open stretch of road to ride along")
	if s0 < 0.0:
		await _free(tr)
		return
	b._spawn_timer = INF
	tr.stream.clear()
	var ids := b.spawn_group(s0 + 25.0, 1, 1, 18.0)
	var d := b.find(int(ids[0]))
	d["pace"] = 18.0 / tr.limit_at(s0)
	var ss := [s0]
	# Faster than it, so not yet: then at its pace behind it.
	_ride(tr, spot, ss, 26.0, 1.5)
	var passing_joined := int(d["rider"]) >= 0
	ss[0] = float(d["s"]) - 22.0
	var when := [-1.0]
	_ride(tr, spot, ss, func(_time): return float(d["v"]), 8.0, -1.5, func(time: float) -> bool:
		if int(d["rider"]) == 0 and when[0] < 0.0:
			when[0] = time
		return int(d["rider"]) == 0)
	check(not passing_joined and int(d["rider"]) == 0 and float(when[0]) >= AdventureBikers.JOIN_TIME - 0.15 and int(d["jslot"]) == 1,
		"kept its pace behind it for %.1f s and it rides along with the crew, in front" % float(when[0]))
	# It came up behind it: it's ahead. Ride on, faster then slower: it keeps its place ahead.
	var worst := [0.0]
	var lats := []
	_ride(tr, spot, ss, func(time): return 15.0 + 8.0 * sin(time * 0.15), 60.0, -1.5, func(time: float) -> bool:
		if time > 10.0:
			var gap := (float(d["s"]) - float(ss[0]))
			worst[0] = maxf(worst[0], absf(gap - maxf(AdventureBikers.FORM_GAP, float(b.riders[0]["v"]) * AdventureBikers.FORM_TIME)))
			lats.append(float(d["lat"]))
		return false)
	var mean := 0.0
	for l in lats:
		mean += float(l) / maxf(lats.size(), 1)
	check(int(d["rider"]) == 0 and worst[0] < 6.0, "it matches the crew's pace, speeding up and slowing with you, its place in front kept to %.1f m" % worst[0])
	check(absf(mean - (-1.5)) > 0.5 and mean < 0.0 and b.pool[int(d["id"])]["body"].collision_layer == 0,
		"staggered: you on one track (1.5 m left of the middle), it on the other (%.2f m), and it's not solid while it rides with you" % -mean)
	# You stop: it stops ahead of you and waits.
	_ride(tr, spot, ss, func(time): return maxf(0.0, 15.0 - time * 4.0), 7.0)
	check(int(d["rider"]) == 0 and float(d["v"]) < 0.5 and float(d["s"]) > float(ss[0]), "you stop: it stops too, ahead of you (%.1f m/s)" % float(d["v"]))
	_ride(tr, spot, ss, 0.0, 3.0)
	# One behind: a rider coming up from behind you at your pace joins behind.
	ss[0] = float(d["s"]) + 400.0
	_ride(tr, spot, ss, 0.0, 0.3)
	var ids2 := b.spawn_group(ss[0] - 4.0, 1, 1, 0.0)
	var e := b.find(int(ids2[0]))
	_ride(tr, spot, ss, 0.0, 0.2, -2.25)
	e["v"] = 16.0
	e["pace"] = 16.0 / tr.limit_at(ss[0])
	_ride(tr, spot, ss, 16.0, 6.0, -2.25, func(_time): return int(e["rider"]) == 0)
	check(int(e["rider"]) == 0 and int(e["jslot"]) == -1, "one you're alongside at its pace joins behind you (place %d)" % int(e["jslot"]))
	_ride(tr, spot, ss, 16.0, 15.0, -2.25)
	check(int(e["rider"]) == 0 and float(e["s"]) < float(ss[0]) - 5.0 and float(e["s"]) > float(ss[0]) - 20.0,
		"and rides behind you (%.1f m)" % (float(ss[0]) - float(e["s"])))
	await _free(tr)


## Later it peels off: its time up, it signals left, waves, turns down the next side road on its
## left and is gone out of sight (back in the pool); and one whose crew stops a while at a stop
## waves and rides on.
func test_peel() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var b := tr.bikers
	b._spawn_timer = INF
	# A junction with a side road on the left going +s, no roundabout, on the open road.
	var jn := {}
	var jk := -1
	var ji := -1
	for j in tr.stream.junctions.size():
		var c: Dictionary = tr.stream.junctions[j]
		if c.has("ro") or float(c["s"]) < 2000.0:
			continue
		for k in (c["arms"] as Array).size():
			if int(c["arms"][k]["side"]) == -1:
				jn = c
				jk = k
				ji = j
		if not jn.is_empty():
			break
	check(not jn.is_empty(), "a junction with a side road on the left")
	if jn.is_empty():
		await _free(tr)
		return
	var js := float(jn["s"])
	tr.stream.clear()
	var ss := [js - 700.0]
	_ride(tr, spot, ss, 0.0, 1.0)
	var d := b.find(int(b.spawn_group(ss[0] - 14.0, 1, 1, 14.0)[0]))
	b.join(int(d["id"]), 0, -1)
	_ride(tr, spot, ss, 14.0, 4.0)
	tr.stream.clear()
	d["jtime"] = 0.0
	var signalled := [false]
	var waved := [false]
	var down := _ride(tr, spot, ss, 14.0, 70.0, -1.5, func(_time: float) -> bool:
		tr.stream.clear()   # (nothing in the way, for this)
		if int(d["ind"]) == -1 and not d.has("arm"):
			signalled[0] = true
		if int(d["gesture"]) == AdventureBikers.WAVE:
			waved[0] = true
		return d.has("arm") and float(d["t"]) > 15.0)
	check(down and signalled[0] and waved[0] and int(d["rider"]) < 0 and int(d["arm"]) == ji and int(d["k"]) == jk,
		"its time with the crew up, it signals left, waves and peels off down the side road at the junction")
	var pos: Vector3 = b.pool[int(d["id"])]["body"].global_position
	var hit := tr.world.locate_local(pos)
	check(not hit.is_empty() and absf(float(hit["lat"])) > 8.0, "drawn off along the side road (%.1f m from the main road's middle)" % absf(float(hit.get("lat", 0.0))))
	var id := int(d["id"])
	var gone := _ride(tr, spot, ss, 14.0, 60.0, -1.5, func(_time): return b.find(id).is_empty())
	check(gone and not b.pool[id]["used"] and not b.pool[id]["body"].visible, "and it's gone once it's out of sight, its bike back in the pool")
	# Stopping a while: it waves and rides on.
	ss[0] = js + 600.0
	_ride(tr, spot, ss, 0.0, 0.5)
	var e := b.find(int(b.spawn_group(ss[0] - 14.0, 1, 1, 14.0)[0]))
	b.join(int(e["id"]), 0, -1)
	_ride(tr, spot, ss, 14.0, AdventureBikers.JOIN_MIN + 2.0, -1.5, func(_t): tr.stream.clear(); return false)
	var with := int(e["rider"]) == 0
	var parted := _ride(tr, spot, ss, 0.0, AdventureBikers.STOP_PART + 3.0, -4.5, func(_t): return int(e["rider"]) < 0)
	var wave := int(e["gesture"]) == AdventureBikers.WAVE
	_ride(tr, spot, ss, 0.0, 12.0, -4.5)
	check(with and parted and wave and float(e["s"]) > float(ss[0]) + 20.0 and float(e["v"]) > 8.0,
		"stopped at the side a while, it waves and rides on (%.0f m on at %.0f mph)" % [float(e["s"]) - float(ss[0]), float(e["v"]) * 2.237])
	_ride(tr, spot, ss, 0.0, 3.0, -4.5)
	check(int(e["rider"]) < 0 and float(e["cool"]) > 0.0, "and doesn't join again straight away")
	await _free(tr)


## Coming the other way, bikers nod or wave as you pass (most of them); and nod back at you when
## you nod at them (AdventureBikers.nod_back, for the nod key): the head dips, or the left hand
## comes up off the bars.
func test_nods() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var b := tr.bikers
	b._spawn_timer = INF
	var s0 := _open_stretch(tr, 2500.0, 2500.0)
	tr.stream.clear()
	var ss := [s0]
	var greeted := 0
	var waves := 0
	var met := 0
	for i in 16:
		var d := b.find(int(b.spawn_group(float(ss[0]) + 160.0, -1, 1, 15.0)[0]))
		met += 1
		var g := [AdventureBikers.NONE]
		var head := [0.0]
		var arm := [0.0]
		_ride(tr, spot, ss, 0.0, 12.0, -1.5, func(_time: float) -> bool:
			tr.stream.clear()
			if int(d["gesture"]) != AdventureBikers.NONE:
				g[0] = int(d["gesture"])
			var p: Dictionary = b.pool[int(d["id"])]
			head[0] = maxf(head[0], absf((p["head"] as Node3D).rotation.x))
			arm[0] = maxf(arm[0], absf((p["arm"] as Node3D).rotation.z))
			return float(d["s"]) < float(ss[0]) - 40.0)
		if g[0] == AdventureBikers.NOD and head[0] > 0.3:
			greeted += 1
		elif g[0] == AdventureBikers.WAVE and arm[0] > 0.7:
			greeted += 1
			waves += 1
		b.clear()
	check(greeted >= met * 0.4 and greeted < met and waves >= 1 and waves < greeted,
		"of %d oncoming bikers, %d nod or wave as they pass (%d waves)" % [met, greeted, waves])
	# Nod at them: those near nod back.
	var near := b.find(int(b.spawn_group(float(ss[0]) + 30.0, 1, 1, 0.0)[0]))
	var far := b.find(int(b.spawn_group(float(ss[0]) + 400.0, 1, 1, 0.0)[0]))
	_ride(tr, spot, ss, 0.0, 0.3)
	var n := AdventureBikers.nod_back(spot["ps"][0])
	var dipped := [0.0, 0.0]
	_ride(tr, spot, ss, 0.0, 2.5, -1.5, func(_t):
		var pn: Dictionary = b.pool[int(near["id"])]
		var pf: Dictionary = b.pool[int(far["id"])]
		dipped[0] = maxf(dipped[0], maxf(absf((pn["head"] as Node3D).rotation.x), absf((pn["arm"] as Node3D).rotation.z)))
		dipped[1] = maxf(dipped[1], maxf(absf((pf["head"] as Node3D).rotation.x), absf((pf["arm"] as Node3D).rotation.z)))
		return false)
	check(n == 1 and dipped[0] > 0.3 and dipped[1] < 0.01, "you nod: the biker 30 m off nods back, the one 400 m off doesn't see")
	# The rig: the head and left arm on their pivots, the rest of the rider where it was.
	var pr: Dictionary = b.pool[int(near["id"])]
	check((pr["head"] as Node3D).get_child_count() >= 2 and (pr["arm"] as Node3D).get_child_count() >= 3,
		"each rider's head (%d pieces) and left arm (%d) can move" % [(pr["head"] as Node3D).get_child_count(), (pr["arm"] as Node3D).get_child_count()])
	check(AdventureBikers.nod_back(Vector3(1.0e5, 0.0, 0.0)) == 0, "a nod with no one about is nodded back by no one")
	await _free(tr)


## The crew see the host's bikers: the same ones (same bikes), at the same places along the road
## and across it, riding with the crew or not, nodding together, off down the side road together,
## through the traffic's own snapshot (with the traffic and the lights' clock still read right).
func test_sync() -> void:
	var hs := {}
	var host := _world(11, 60.0, hs)
	var cs := {}
	var client := _world(11, 60.0, cs, false)
	var s0 := _open_stretch(host, 2500.0, 2500.0)
	host.bikers._spawn_timer = INF
	host.stream.clear()
	var ss := [s0]
	var ids := host.bikers.spawn_group(s0 + 200.0, -1, 3)
	var j := host.bikers.find(int(host.bikers.spawn_group(s0 + 20.0, 1, 1, 15.0)[0]))
	host.bikers.join(int(j["id"]), 0, 1)
	var worst := [0.0, 0.0]
	var flags_ok := [true]
	var nodded := [false]
	var bad := [""]
	_ride(host, hs, ss, 15.0, 12.0, -1.5, func(time: float) -> bool:
		_at(client, cs, ss)
		var pack := host.stream.pack()
		pack.append_array(host.bikers.pack())
		pack.append_array([AdventureJunctions.clock, AdventureTraffic.CLOCK_TAG])
		client._on_net(pack)
		client._physics_process(0.1)
		if client.stream.vehicles.size() != host.stream.vehicles.size():
			bad[0] = "the traffic: %d vehicles, the host's %d" % [client.stream.vehicles.size(), host.stream.vehicles.size()]
		if time < 0.5:
			return false
		if client.bikers.bikers.size() != host.bikers.bikers.size():
			bad[0] = "%d bikers, the host's %d" % [client.bikers.bikers.size(), host.bikers.bikers.size()]
			return false
		for d in host.bikers.bikers:
			var c := client.bikers.find(int(d["id"]))
			if c.is_empty():
				bad[0] = "biker %d missing" % int(d["id"])
				continue
			worst[0] = maxf(worst[0], absf(float(c["s"]) - float(d["s"])))
			worst[1] = maxf(worst[1], absf(float(c["lat"]) - float(d["lat"])))
			if bool(c["joined"]) != (int(d["rider"]) >= 0):
				flags_ok[0] = false
			if int(c["gesture"]) != AdventureBikers.NONE:
				nodded[0] = true
		return false)
	check(bad[0] == "" and worst[0] < 2.5 and worst[1] < 0.6 and flags_ok[0],
		"the crew see the host's %d bikers, the same bikes within %.1f m along the road and %.2f m across, the one riding with the crew marked so%s" % [
		host.bikers.bikers.size(), worst[0], worst[1], "" if bad[0] == "" else " (" + bad[0] + ")"])
	check(nodded[0], "and see the host's oncoming bikers nod or wave as they pass")
	var p: Dictionary = client.bikers.pool[int(j["id"])]
	check(str(p["look"]["style"]) == str(host.bikers.pool[int(j["id"])]["look"]["style"]) and (p["body"] as Node3D).visible,
		"each drawn as the same bike (%s)" % str(p["look"]["style"]))
	# Gone on the host: gone for the crew.
	host.bikers.clear()
	var pack := host.stream.pack()
	pack.append_array(host.bikers.pack())
	pack.append_array([AdventureJunctions.clock, AdventureTraffic.CLOCK_TAG])
	client._on_net(pack)
	check(client.bikers.bikers.is_empty() and not (p["body"] as Node3D).visible, "and when they're gone on the host, they're gone for the crew")
	await _free(host)
	await _free(client)


## The cost of the bikers riding along: a handful out round you over a minute, a fraction of a
## millisecond a tick.
func test_cost() -> void:
	var spot := {}
	var tr := _world(11, 60.0, spot)
	var ss := [3000.0]
	_ride(tr, spot, ss, 20.0, 30.0)
	var most := [0]
	var t0 := Time.get_ticks_usec()
	var ticks := 0
	var worst := 0.0
	for i in 600:
		ss[0] = float(ss[0]) + 2.0
		_at(tr, spot, ss)
		tr._find_riders()
		var a := Time.get_ticks_usec()
		tr.bikers.step(0.1)
		worst = maxf(worst, (Time.get_ticks_usec() - a) / 1000.0)
		ticks += 1
		tr.stream.step(0.1)
		tr.stream.blockers = []
		most[0] = maxi(most[0], tr.bikers.bikers.size())
	var each := 0.0
	t0 = Time.get_ticks_usec()
	for i in 300:
		tr.bikers.step(1.0 / 60.0)
		tr.stream.blockers = []
	each = (Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	check(most[0] >= 3 and each < 0.5 and worst < 10.0, "with %d bikers out the bikers cost %.3f ms a tick (%.2f ms at the worst)" % [most[0], each, worst])
	await _free(tr)
