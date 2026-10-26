extends RefCounted
## The adventure road's junctions (AdventureJunctions): the real side roads, crossroads and roundabouts along a planned
## road, traffic lights at the crossroads in town, the traffic at them, the police at a red light and the sat nav
## through them. Run from tests/run_tests.gd: its _test_adv_roads_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")

const DT := 1.0 / 60.0

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## A tour (Rides) with a junction of `type` well along it (and not on a fork's ways), and that junction:
## [seed, route, junction, pack]; [] if no region's tour has one.
static func _with_junction(type: String) -> Array:
	for region_id in AdventurePlans.TOURS:
		var r := Rides.tour_route(region_id, 7)
		for st in r.sites_of(AdventureJunctions.KIND):
			if st["type"] == type and float(st["s"]) > 1500.0 and r.fork_at(float(st["s"])) < 0:
				return [7, r, st, Rides.tour_pack(region_id)]
	return []


## A world along the road `found` (see _with_junction) came from, the main road at every fork.
static func _world_for(found: Array) -> AdventureWorld:
	var w := AdventureWorld.new()
	var pack: RealPack = found[3]
	w.setup(pack, int(found[0]), pack.max_km())
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	return w


# ---------------------------------------------------------------------------- junctions

## Where the real roads join a planned road: side roads, crossroads, roundabouts, and traffic lights at the crossroads
## in town; all clear of the other sites, the same for the same plan.
func test_junction_plan() -> void:
	var types := {}
	var clash := false
	var km := 0.0
	var count := 0
	for region_id in AdventurePlans.TOURS:
		var r := Rides.tour_route(region_id, 42)
		var js := r.sites_of(AdventureJunctions.KIND)
		km += r.length / 1000.0
		count += js.size()
		for st in js:
			types[st["type"]] = int(types.get(st["type"], 0)) + 1
			for o in r.sites:
				if o != st and not str(o["kind"]) in [AdventureJunctions.KIND, "limit"] and absf(float(o["s"]) - float(st["s"])) < 55.0:
					clash = true
	check(types.has("tee") and types.has("cross") and types.has("lights") and count / km > 0.1,
		"the real junctions along the tours, %.2f a km %s" % [count / km, str(types)])
	check(not clash, "none on top of a stop, a fuel station or a fork")
	var a := Rides.tour_route("dales", 42)
	var b := Rides.tour_route("dales", 42)
	check(str(a.sites_of(AdventureJunctions.KIND)) == str(b.sites_of(AdventureJunctions.KIND)), "the same plan has the same junctions, side roads and all")
	# A roundabout: the road widened round its island, its side roads laid on the land.
	var found := _with_junction("roundabout")
	check(not found.is_empty(), "a road with a roundabout on it")
	if found.is_empty():
		return
	var r: AdventureRoute = found[1]
	var st: Dictionary = found[2]
	var ro := float(st["ro"])
	check(r.width_at_s(float(st["s"])) > ro * 1.8 and r.width_at_s(float(st["s"]) - ro - 25.0) < 9.0 and float(st["rc"]) < ro and float(st["ri"]) < float(st["rc"]),
		"a roundabout: the road %.0f m across round its %.1f m island" % [r.width_at_s(float(st["s"])), float(st["ri"])])
	var geo: Array = st["arm_geo"]
	var flat := true
	for k in geo.size():
		var pts: PackedVector3Array = geo[k]
		for q in pts:
			flat = flat and absf(q.y) < 30.0
	var end: Vector3 = (geo[0] as PackedVector3Array)[-1]
	check(geo.size() == (st["arms"] as Array).size() and flat and Vector2(end.x, end.z).length() > 40.0,
		"its side roads run %.0f m out over the land" % Vector2(end.x, end.z).length())
	# Scenery keeps off them, and the fences open across their mouths.
	var c := AdventureRoute.chunk_of(float(st["s"]))
	var data := AdventureChunk.build(r, c)
	var on_arm := 0
	for kind in data["mm"]:
		for xf in data["mm"][kind]:
			var p: Vector3 = (xf as Transform3D).origin + Vector3(float(data["ax"]), 0.0, float(data["az"]))
			if AdventureJunctions.on_arm(r, int(st["i"]), p.x, p.z, 0.5):
				on_arm += 1
	var arms_v := 0
	for surf in data["arms"]:
		arms_v += (data["arms"][surf]["v"] as PackedVector3Array).size()
	check(arms_v > 0 and on_arm == 0, "its chunk has the side roads (%d vertices) and no scenery on them" % arms_v)


## What the sat nav says at each: the exit to take at a roundabout (counted round from the left,
## the main road straight on after the side roads on its left), straight on at a mini roundabout,
## the lights or a crossroads; nothing for a side road joining.
func test_instructions() -> void:
	var st := {"type": "roundabout", "arms": [{"side": -1}, {"side": 1}]}
	var left := {"type": "roundabout", "arms": [{"side": -1}]}
	var right := {"type": "roundabout", "arms": [{"side": 1}]}
	check(AdventureJunctions.instruction(st, 1) == "At the roundabout, take the 2nd exit" and AdventureJunctions.instruction(left, 1) == "At the roundabout, take the 2nd exit"
		and AdventureJunctions.instruction(right, 1) == "At the roundabout, take the 1st exit" and AdventureJunctions.instruction(right, -1) == "At the roundabout, take the 2nd exit",
		"roundabouts: \"%s\" with a road off each side, the 1st exit with one only on the right" % AdventureJunctions.instruction(st, 1))
	check(AdventureJunctions.instruction({"type": "mini", "arms": []}) == "At the mini roundabout, go straight on"
		and AdventureJunctions.instruction({"type": "lights", "arms": []}) == "Straight on at the lights"
		and AdventureJunctions.instruction({"type": "cross", "arms": []}) == "Straight on at the crossroads"
		and AdventureJunctions.instruction({"type": "tee", "arms": []}) == "", "and straight on at the others")
	var found := _with_junction("roundabout")
	if found.is_empty():
		check(false, "a road with a roundabout on it")
		return
	var w := _world_for(found)
	t.add_child(w)
	var js: Dictionary = {}
	for s in w.route.sites_of(AdventureJunctions.KIND):
		if absf(float(s["s"]) - float(found[2]["s"])) < 1.0:
			js = s
	var s0 := float(js["s"])
	var xf := w.transform_at(s0 - 220.0, -1.2)
	var nav := Satnav.AdventureNav.new(w)
	var view := Satnav.view_for(nav, xf.origin, -xf.basis.z, 20.0)
	var j: Dictionary = view.get("junction", {})
	var want := AdventureJunctions.instruction(js, 1)
	check(str(j.get("text", "")) == want and absf(float(j.get("distance", 0.0)) - 220.0) < 6.0 and int(j.get("exit", 0)) == AdventureJunctions.exit_number(js, 1),
		"220 m out the sat nav says \"%s\" (%s)" % [str(j.get("text", "")), SatnavScreen.near_distance(float(j.get("distance", 0.0)))])
	# The way on drawn round the island's left, and the side roads and the ring on the map.
	var route: PackedVector2Array = view["route"]
	var centre := w.transform_at(s0).origin
	var round_left := false
	for q in route:
		if Vector2(q.x - centre.x, q.y - centre.z).length() < 1.0:
			round_left = false
			break
		var side := Vector2(q.x - centre.x, q.y - centre.z).dot(Vector2(-xf.basis.z.z, xf.basis.z.x) * -1.0)
		if Vector2(q.x - centre.x, q.y - centre.z).length() < float(js["rc"]) + 1.0 and side < 0.0:
			round_left = true
	var arms := 0
	for road in view["roads"]:
		if (road["pts"] as PackedVector2Array).size() >= 2 and Vector2((road["pts"] as PackedVector2Array)[-1].x - centre.x, (road["pts"] as PackedVector2Array)[-1].y - centre.z).length() > 40.0 \
				and Vector2((road["pts"] as PackedVector2Array)[0].x - centre.x, (road["pts"] as PackedVector2Array)[0].y - centre.z).length() < 20.0:
			arms += 1
	check(round_left and arms >= (js["arms"] as Array).size(), "the way on goes round the island's left, with the side roads on the map (%d)" % arms)
	# Facing back the way you came, it says nothing (it's behind you).
	var back := Satnav.view_for(nav, xf.origin, xf.basis.z, 20.0)
	check((back.get("junction", {}) as Dictionary).is_empty(), "and nothing turned round")
	var screen := SatnavScreen.new()
	screen.size = Vector2(320, 240)
	t.add_child(screen)
	screen.show_view(view)
	await _frames(2)
	check(screen.view.has("junction"), "the screen draws it")
	screen.queue_free()
	w.queue_free()
	await _frames(2)


## The lights: red, red and amber, green, amber, round again, the side road's green only while
## the main road's red; all from one clock, so every machine's lights agree.
func test_lights_cycle() -> void:
	var st := {"green": [18.0, 9.0], "phase": 4.0}
	var seen := []
	var both := false
	var side_green_main_red := true
	var t0 := 0.0
	while t0 < 120.0:
		var s := AdventureJunctions.light_state(st, t0)
		if seen.is_empty() or seen[-1] != s.x:
			seen.append(s.x)
		both = both or (s.x == AdventureJunctions.GREEN and s.y == AdventureJunctions.GREEN)
		if s.y == AdventureJunctions.GREEN or s.y == AdventureJunctions.AMBER_ON:
			side_green_main_red = side_green_main_red and s.x == AdventureJunctions.RED
		t0 += 0.25
	var cycle := ""
	for k in range(0, 5):
		cycle += ["R", "RA", "G", "A"][seen[k]] + " "
	var order_ok := true
	for k in range(1, seen.size()):
		var a: int = seen[k - 1]
		var b: int = seen[k]
		order_ok = order_ok and ((a == AdventureJunctions.GREEN and b == AdventureJunctions.AMBER_ON) or (a == AdventureJunctions.AMBER_ON and b == AdventureJunctions.RED)
			or (a == AdventureJunctions.RED and b == AdventureJunctions.RED_AMBER_ON) or (a == AdventureJunctions.RED_AMBER_ON and b == AdventureJunctions.GREEN))
	check(order_ok and not both and side_green_main_red, "the main road's lights go round %s..., never green both ways" % cycle)
	check(AdventureJunctions.light_state(st, 33.3) == AdventureJunctions.light_state(st, 33.3) and AdventureJunctions.light_state(st, 3.0) != AdventureJunctions.light_state(st, 14.0),
		"the same clock, the same lights")
	# A signal head's lamps lit for the state, glowing at night.
	var found := _with_junction("lights")
	if found.is_empty():
		check(false, "a road with traffic lights")
		return
	var r: AdventureRoute = found[1]
	var js: Dictionary = found[2]
	var node := AdventureJunctions.build(r, js, Transform3D())
	t.add_child(node)
	var sig: Node = node.get_node_or_null("Signals")
	await _frames(2)
	check(sig != null and (sig.heads as Array).size() >= 2 + (js["arms"] as Array).size(), "the lights stand at the junction: %d heads" % (sig.heads.size() if sig else 0))
	if sig:
		# Red and amber together is two lamps on a head; every other state is one.
		var lit := 0
		var want := 0
		for h in sig.heads:
			var state: int = sig.shown().x if h["role"] == "main" else sig.shown().y
			want += 2 if state == AdventureJunctions.RED_AMBER_ON else 1
			for k in 3:
				var m: StandardMaterial3D = h["lamps"][k].material_override
				if m.emission_enabled and m.emission_energy_multiplier > 0.5:
					lit += 1
		check(lit == want, "the lamps lit for each head's state (%d of %d)" % [lit, want])
	node.queue_free()
	# The host's clock rides on the end of the traffic it sends; the crew's lights follow it.
	AdventureJunctions.clock = 10.0
	var tr := AdventureTraffic.new()
	var w := _world_for(found)
	t.add_child(w)
	tr.world = w
	w.add_child(tr)
	tr.host = false
	tr.stream.host = false
	tr._on_net(PackedFloat32Array([123.5, AdventureTraffic.CLOCK_TAG]))
	check(absf(AdventureJunctions.clock - 123.5) < 0.01, "the crew's lights clock takes the host's (%.1f)" % AdventureJunctions.clock)
	w.queue_free()
	await _frames(2)


## A straight test road for a stream with junction `jn` at 500 m; arm k runs straight out to its side.
func _stream_with(jn: Dictionary, light: Array) -> TrafficStream:
	var stream := TrafficStream.new()
	stream.rng.seed = 2024   # the same traffic every run
	stream.sample = func(s: float) -> Dictionary:
		return {"pos": Vector3(0.0, 0.0, -s), "fwd": Vector3(0, 0, -1), "hw": 3.4, "busy": 0.0, "limit": 15.0, "grade": 0.0}
	stream.junctions = [jn]
	stream.signal_state = func(_j: Dictionary) -> Vector2i: return Vector2i(light[0], light[1])
	stream.arm_at = func(j: Dictionary, k: int, d: float) -> Dictionary:
		var side := float(j["arms"][k]["side"])
		return {"pos": Vector3(side * (3.4 + d), 0.0, -float(j["s"])), "fwd": Vector3(side, 0.0, 0.0)}
	t.add_child(stream)
	stream.set_physics_process(false)
	stream.focus_s = 500.0
	stream.despawn = 5000.0
	stream._spawn_timer = 1.0e9
	stream._side_timer = 1.0e9
	return stream


func _step(stream: TrafficStream, seconds: float, until := Callable()) -> bool:
	for i in int(seconds / DT):
		stream.step(DT)
		if until.is_valid() and until.call():
			return true
	return until.is_valid() and until.call()


## The traffic at the lights: stopped at the line on red (and on an amber it can stop for), away
## on green; at a roundabout slowing round the island on its left and giving way to what's going
## round.
func test_traffic_stops() -> void:
	var light := [AdventureJunctions.RED, AdventureJunctions.GREEN]
	var jn := {"s": 500.0, "stop": 5.0, "lights": true, "village": true, "arms": [{"side": -1, "len": 60.0, "w": 5.0}, {"side": 1, "len": 60.0, "w": 5.0}]}
	var stream := _stream_with(jn, light)
	var car: Dictionary = stream.find(stream.spawn_at("hatchback", 380.0, 1, 13.0))
	car["seen"] = 0   # (going straight on)
	var stopped := _step(stream, 20.0, func(): return float(car["v"]) < 0.05)
	var front := float(car["s"]) + TrafficVehicle.half_length_of("hatchback")
	check(stopped and front < 495.0 + 0.1 and front > 488.0, "at a red light a car stops at the line (its nose %.1f m short of the middle)" % (500.0 - front))
	_step(stream, 3.0)
	var held := float(car["v"]) < 0.05
	light[0] = AdventureJunctions.GREEN
	var went := _step(stream, 15.0, func(): return float(car["s"]) > 520.0)
	check(held and went, "it waits there till the green, then goes")
	# Amber: one close to the line goes on through, one further back stops.
	light[0] = AdventureJunctions.AMBER_ON
	var near: Dictionary = stream.find(stream.spawn_at("saloon", 486.0, -1, 13.0))
	var far: Dictionary = stream.find(stream.spawn_at("saloon", 700.0, -1, 13.0))
	near["s"] = 514.0
	near["seen"] = 0
	far["seen"] = 0
	_step(stream, 6.0)
	check(float(near["s"]) < 495.0 and float(far["s"]) > 505.0, "on amber one too close to stop goes through, one further back stops")
	stream.queue_free()
	# The roundabout: round the island, giving way at the line.
	var rb := {"s": 500.0, "stop": 12.6, "lights": false, "village": false, "ro": 11.8, "rc": 7.9, "arms": [{"side": -1, "len": 60.0, "w": 5.0}]}
	var s2 := _stream_with(rb, light)
	var a: Dictionary = s2.find(s2.spawn_at("hatchback", 420.0, 1, 13.0))
	a["seen"] = 0
	var widest := {"lat": 0.0, "v": INF}
	_step(s2, 15.0, func():
		if absf(float(a["s"]) - 500.0) < 2.0:
			widest["lat"] = minf(float(widest["lat"]), float(s2._place(a)[2]))
			widest["v"] = minf(float(widest["v"]), float(a["v"]))
		return float(a["s"]) > 530.0)
	check(float(widest["lat"]) < -7.0 and float(widest["v"]) < TrafficStream.ROUND_SPEED + 1.0,
		"at a roundabout it slows to %.0f mph and goes round the island's left (%.1f m off the middle)" % [float(widest["v"]) * 2.237, float(widest["lat"])])
	# Something going round: wait at the line for it.
	var round_car: Dictionary = s2.find(s2.spawn_at("van", 503.0, -1, 0.0))
	var taken := s2.take(int(round_car["seed"]))
	var b: Dictionary = s2.find(s2.spawn_at("estate", 440.0, 1, 12.0))
	b["seen"] = 0
	_step(s2, 12.0)
	var waiting := float(b["v"]) < 0.1 and float(b["s"]) < 500.0 - 12.6
	s2.remove_id(int(taken["seed"]))
	var on := _step(s2, 10.0, func(): return float(b["s"]) > 515.0)
	check(waiting and on, "and gives way at the line to one going round, then goes")
	s2.queue_free()
	await _frames(1)


## Off down a side road and out of one: a car indicating turns off (a right turn waiting for a gap
## in what's coming), drives off along it and out of sight; one comes out of a side road, waits at
## the mouth for a gap (or the side road's green) and pulls out; all of it carried to the crew.
func test_traffic_turns() -> void:
	var light := [AdventureJunctions.GREEN, AdventureJunctions.RED]
	var jn := {"s": 500.0, "stop": 5.0, "lights": false, "village": false, "arms": [{"side": -1, "len": 60.0, "w": 5.0}, {"side": 1, "len": 60.0, "w": 5.0}]}
	var stream := _stream_with(jn, light)
	var car: Dictionary = stream.find(stream.spawn_at("hatchback", 400.0, 1, 12.0))
	car["seen"] = 0
	car["turn"] = [0, 0, false]   # left, onto arm 0
	var signalled := {"ind": 0}
	var off := _step(stream, 20.0, func():
		if not car.has("arm") and int(car["ind"]) != 0:
			signalled["ind"] = int(car["ind"])
		return car.has("arm") and float(car["t"]) > 20.0)
	var pos: Vector3 = stream._place_arm(car)[0] if car.has("arm") else Vector3.ZERO
	check(off and int(signalled["ind"]) == -1 and pos.x < -20.0, "a car indicates left, turns off and drives away down the side road (%.0f m out)" % -pos.x)
	var gone := _step(stream, 20.0, func(): return stream.find(int(car["seed"])).is_empty())
	check(gone, "and is gone at its end, out of sight")
	# The bend off the lane and onto the side road (and back) is one smooth curve: it leaves the lane along it, meets
	# the side road along it, and turns a little at a time between (no snapping round at either end).
	for out: bool in [true, false]:
		var lane_s := 500.0 + (-1.0 if out else 1.0) * TrafficStream._bend_reach(stream.junctions[0])
		var lane_fwd: Vector3 = stream._place({"s": lane_s, "dir": 1, "kind": "hatchback"})[1]
		var worst := 0.0
		var prev := Vector3.ZERO
		var ends := []
		var t := -TrafficStream.TURN_LEN
		while t <= 4.0:
			var fwd: Vector3 = stream._place_arm({"arm": 0, "k": 0, "t": t, "out": out, "dir": 1, "kind": "hatchback"})[1]
			if prev != Vector3.ZERO:
				worst = maxf(worst, rad_to_deg(prev.angle_to(fwd)))
			if is_equal_approx(t, -TrafficStream.TURN_LEN):
				ends.append(rad_to_deg(fwd.angle_to(lane_fwd)))
			prev = fwd
			t += 0.25
		check(worst < 8.0 and ends[0] < 3.0, "turning %s a side road, the car turns smoothly: at most %.1f deg every 25 cm, %.1f deg off the lane where it leaves it"
			% ["off down" if out else "out of", worst, ends[0]])
	# Turning right waits for the oncoming car to pass.
	var right: Dictionary = stream.find(stream.spawn_at("saloon", 482.0, 1, 5.0))
	right["seen"] = 0
	right["turn"] = [0, 1, true]
	var oncoming: Dictionary = stream.find(stream.spawn_at("van", 580.0, -1, 13.0))
	oncoming["seen"] = 0
	var waited := {"v": INF}
	var crossed := _step(stream, 30.0, func():
		if float(oncoming["s"]) > 500.0 and not right.has("arm"):
			waited["v"] = minf(float(waited["v"]), float(right["v"]))
		return right.has("arm"))
	check(crossed and float(waited["v"]) < 0.5 and float(oncoming["s"]) < 500.0, "turning right it waits for the van coming the other way, then goes")
	# Coming out: waits at the mouth till the lane's clear.
	for i in range(stream.vehicles.size() - 1, -1, -1):
		stream._remove(i)
	stream._find_junctions()
	var out := stream.spawn_side()
	check(not out.is_empty() and out.has("arm") and not out["out"], "a car turns up along a side road, heading for the main road")
	var dir := int(out["dir"])
	# The lorry comes along as it gets to the mouth.
	_step(stream, 30.0, func(): return float(out["t"]) < 4.0)
	var busy: Dictionary = stream.find(stream.spawn_at("lorry", 500.0 - dir * 45.0, dir, 12.0))
	busy["seen"] = 0
	var at_mouth := {"held": false}
	var joined := _step(stream, 40.0, func():
		if out.has("arm") and float(out["t"]) < 1.0 and float(out["v"]) < 0.1 and absf(float(busy["s"]) - 500.0) < 40.0:
			at_mouth["held"] = true
		return not out.has("arm"))
	check(joined and at_mouth["held"] and int(out["dir"]) == dir and (float(out["s"]) - 500.0) * dir > 0.0,
		"it waits at the mouth while the lorry goes by, then pulls out and drives on")
	# To the crew: a car down a side road goes as its place along it.
	var down: Dictionary = stream.find(stream.spawn_at("estate", 470.0, 1, 10.0))
	down["seen"] = 0
	down["turn"] = [0, 0, false]
	_step(stream, 8.0, func(): return down.has("arm") and float(down["t"]) > 6.0)
	var client := _stream_with(jn, light)
	client.host = false
	client.unpack(stream.pack())
	var copy := client.find(int(down["seed"]))
	var here: Vector3 = stream._place_arm(down)[0]
	var there: Vector3 = client._place_arm(copy)[0] if copy.has("arm") else Vector3(1e6, 0, 0)
	check(copy.has("arm") and here.distance_to(there) < 0.5, "and the crew see it there too (%.2f m apart)" % here.distance_to(there))
	client.queue_free()
	stream.queue_free()
	await _frames(1)


## Through a red light with the police there: they come after you, and it's a fine (£100, more
## for each time that day). Through on green, nothing.
func test_police_red() -> void:
	Shed.adventure = {"id": 4242, "seed": 7, "km": 60.0, "theme": "varied", "riders": {}, "arrived": 0, "arrived_name": ""}
	var found := _with_junction("lights")
	if found.is_empty():
		check(false, "a road with traffic lights")
		return
	var me := Shed.me()
	var keep := Progress.money()
	Progress.set_money(1000)
	for want_red in [false, true]:
		var sim := {me: {"s": 0.0, "v": 0.0}}
		var w := _world_for(found)
		var p := AdventurePolice.new()
		p.world = w
		p.rider_source = func() -> Array: return [{"peer": me, "s": sim[me]["s"], "v": sim[me]["v"]}]
		t.add_child(p)
		p.set_physics_process(false)
		p.plan = []
		var st: Dictionary = {}
		for s in w.route.sites_of(AdventureJunctions.KIND):
			if absf(float(s["s"]) - float(found[2]["s"])) < 1.0:
				st = s
		var js := float(st["s"])
		# The clock where the main road's lights are red (or green) for a good while.
		var clock := 0.0
		while true:
			var ok := true
			for k in 20:
				var x := AdventureJunctions.light_state(st, clock + k * 0.5).x
				ok = ok and (x == AdventureJunctions.RED if want_red else x == AdventureJunctions.GREEN)
			if ok:
				break
			clock += 0.5
		AdventureJunctions.clock = clock
		var id := p.spawn(js + 90.0, -1, false, 0.4)
		sim[me]["s"] = js - 40.0
		sim[me]["v"] = 9.0
		for i in int(6.0 / DT):
			sim[me]["s"] = float(sim[me]["s"]) + float(sim[me]["v"]) * DT
			p.tick(DT)
		var chased := p.chasing(me)
		if not want_red:
			check(not chased, "through the lights on green with the police there: nothing")
		else:
			check(chased and str(p.cars[id].get("why", "")) == "red" and p.messages.size() > 0 and "red light" in p.messages[-1],
				"through a red light in front of a police car: \"%s\"" % (p.messages[-1] if p.messages.size() > 0 else ""))
			# Stop, and the fine comes.
			for i in int(60.0 / DT):
				sim[me]["v"] = move_toward(float(sim[me]["v"]), 0.0, 5.0 * DT)
				sim[me]["s"] = float(sim[me]["s"]) + float(sim[me]["v"]) * DT
				p.tick(DT)
				if not AdventurePolice.fines_of(me).is_empty() and int(AdventurePolice.fines_of(me)[-1]["paid"]) >= 0:
					break
			var fines := AdventurePolice.fines_of(me)
			var f: Dictionary = fines[-1] if not fines.is_empty() else {}
			check(int(f.get("amount", 0)) == 100 and str(f.get("why", "")) == "red" and Progress.money() == 900 and "running a red light" in p.messages[-1],
				"pulled over and fined £%d: \"%s\"" % [int(f.get("amount", 0)), p.messages[-1] if p.messages.size() > 0 else ""])
			check(AdventurePolice.line_for(id, p.cars[id]).length() > 0 and "red" in AdventurePolice.line_for(1, {"why": "red", "speed": 20.0}).to_lower(),
				"the officer has his say about it")
		p.queue_free()
		w.free()
	Progress.set_money(keep)
	Shed.adventure = {}
	await _frames(2)


## Building a chunk with a junction in it costs about what any other does.
func test_chunk_cost() -> void:
	var t0 := Time.get_ticks_usec()
	var r := Rides.tour_route("dales", 42)
	var plan_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var special := {}
	for st in r.sites_of(AdventureJunctions.KIND):
		special[AdventureRoute.chunk_of(float(st["s"]))] = true
	var plain := []
	var with := []
	for c in range(2, 120):
		var c0 := Time.get_ticks_usec()
		AdventureChunk.build(r, c)
		var ms := (Time.get_ticks_usec() - c0) / 1000.0
		(with if special.has(c) else plain).append(ms)
	plain.sort()
	with.sort()
	var mp: float = plain[plain.size() / 2]
	var mw: float = with[with.size() / 2] if not with.is_empty() else 0.0
	check(not with.is_empty() and mw < mp * 1.6 + 5.0 and plan_ms < 2000.0,
		"a chunk with a junction builds in %.1f ms against %.1f ms for the rest (median; laying out the road %.0f ms)" % [mw, mp, plan_ms])
