extends RefCounted
## The police on an adventure's road (AdventurePolice, PoliceDriver, PoliceSiren and the police
## car's model), run from tests/run_tests.gd: its _test_adv_police_* functions hand over to these.
## The police are ticked by hand here at 60 Hz with stand-in riders (rider_source), so a minute
## of chasing takes a moment.

const SEEDS := [1, 7, 42, 99, 2024]
const DT := 1.0 / 60.0
## How hard a rider told to stop brakes (m/s^2): a bike pulled over, off the throttle on the brakes.
const BRAKE := 5.0

var t: Node   # the test runner: check(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


## A world for `seed` (the main way at every fork, so the road goes on) and police on it, ticked
## by hand, with the riders in `sim` ({peer: {s, v}}) and nothing planned to turn up by itself.
func _police(seed: int, sim: Dictionary, km := 60.0) -> AdventurePolice:
	var w := AdventureWorld.new()
	w.setup(seed, km)
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	var p := AdventurePolice.new()
	p.world = w
	p.rider_source = func() -> Array:
		var out := []
		for peer in sim:
			out.append({"peer": peer, "s": sim[peer]["s"], "v": sim[peer]["v"]})
		return out
	t.add_child(p)
	p.set_physics_process(false)
	p.plan = []
	p.set_meta("world", w)
	return p


func _free(p: AdventurePolice) -> void:
	var w: AdventureWorld = p.get_meta("world")
	p.queue_free()
	w.free()
	Shed.adventure = {}
	await t.get_tree().process_frame


## Ticks the police (and moves the riders on, each at its v, or as `move` says) for up to
## `seconds`, stopping early once `until` is true. Returns whether it was.
func _run(p: AdventurePolice, sim: Dictionary, seconds: float, until := Callable(), move := Callable()) -> bool:
	var n := int(seconds / DT)
	for i in n:
		if move.is_valid():
			move.call()
		for peer in sim:
			if sim[peer].get("brake", false):
				sim[peer]["v"] = move_toward(float(sim[peer]["v"]), 0.0, BRAKE * DT)
			sim[peer]["s"] = float(sim[peer]["s"]) + float(sim[peer]["v"]) * DT
		p.tick(DT)
		if until.is_valid() and until.call():
			return true
	return until.is_valid() and until.call()


## Somewhere the road runs near enough straight for `span` metres from `s` (bends wider than a
## kilometre), past `from`.
static func _straight(route: AdventureRoute, from: float, span := 900.0) -> float:
	var s := from
	while s < route.length - span - 400.0:
		var ok := true
		var k := s - 200.0
		while k < s + span and ok:
			ok = absf(route.curv[clampi(int(k / AdventureRoute.STEP), 0, route.curv.size() - 1)]) < 0.0008
			k += AdventureRoute.STEP * 2.0
		if ok:
			return s
		s += 100.0
	return from


func _active() -> void:
	Shed.adventure = {"id": 4242, "seed": 7, "km": 60.0, "theme": "varied", "riders": {}, "arrived": 0, "arrived_name": ""}


func _has(p: AdventurePolice, what: String, peer := -1) -> bool:
	for e in p.events:
		if e[0] == what and (peer < 0 or (e.size() > 2 and int(e[2]) == peer)):
			return true
	return false


## One police car every 15-25 km (the first within 16 km) on every seed, either way, some of
## them parked in lay-bys; the same seed plans the same; on the road one turns up ahead of the
## riders as they near it, and is gone once they're well past.
func test_spawn_rate() -> void:
	var bad := []
	var traps := 0
	var dirs := {}
	var total := 0
	for seed in SEEDS:
		var r := AdventureRoute.new()
		r.plan(seed, 200.0)
		var plan := AdventurePolice.plan_for(r)
		total += plan.size()
		var prev := 0.0
		for i in plan.size():
			var gap := float(plan[i]["s"]) - prev
			prev = float(plan[i]["s"])
			var lo: float = AdventurePolice.FIRST[0] if i == 0 else AdventurePolice.EVERY[0]
			var hi: float = AdventurePolice.FIRST[1] if i == 0 else AdventurePolice.EVERY[1]
			if gap < lo - 1.0 or gap > hi + 1.0:
				bad.append("seed %d #%d %.1f km" % [seed, i, gap / 1000.0])
			traps += 1 if plan[i]["trap"] else 0
			dirs[int(plan[i]["dir"])] = true
		if plan.size() < 7 or plan.size() > 13:
			bad.append("seed %d: %d on 200 km" % [seed, plan.size()])
	check(bad.is_empty(), "a police car every 15-25 km on every seed (%d over %d km) %s" % [total, 200 * SEEDS.size(), str(bad)])
	check(dirs.size() == 2 and traps > total * 0.2 and traps < total * 0.65, "they come both ways, and %d of %d are speed traps in a lay-by" % [traps, total])
	var a := AdventureRoute.new()
	a.plan(42, 80.0)
	var b := AdventureRoute.new()
	b.plan(42, 80.0)
	check(str(AdventurePolice.plan_for(a)) == str(AdventurePolice.plan_for(b)), "the same seed plans the same police")
	# On the road: riders coming up to the first one.
	var sim := {1: {"s": 0.0, "v": 25.0}}
	var p := _police(7, sim)
	p.plan = AdventurePolice.plan_for(p.world.route)
	var first: Dictionary = p.plan[0]
	sim[1]["s"] = float(first["s"]) - 5200.0
	var came := _run(p, sim, 240.0, func(): return not p.cars.is_empty())
	var id: int = p.cars.keys()[0] if came else 0
	var st := p.driver.state(id) if came else {}
	var ahead := float(st.get("s", 0.0)) - float(sim[1]["s"])
	check(came and ahead > 0.0 and ahead < AdventurePolice.SPAWN_AHEAD + 30.0,
		"a police car turns up %.0f m ahead as the riders near it (%s)" % [ahead, str(p.cars.get(id, {}).get("mode", "none"))])
	sim[1]["s"] = float(st.get("s", 0.0)) + AdventurePolice.DESPAWN + 300.0
	var gone := _run(p, sim, 3.0, func(): return not p.cars.has(id))
	check(gone, "and it's gone once they're well past it")
	await _free(p)


## The rule at its edge: passing a car 30 mph faster than it's going (or 30 over the limit past a
## parked one) is fine, a whisker more and it chases. Both ways: overtaking one going your way and
## meeting one coming the other way (which turns round to come after you).
func test_rule() -> void:
	var th := AdventurePolice.THRESHOLD
	check(AdventurePolice.over_rule(24.0 + th - 0.1, 24.0, false, 26.8) < 0.0 and AdventurePolice.over_rule(24.0 + th + 0.1, 24.0, false, 26.8) > 0.0,
		"the rule: %.1f m/s (30 mph) faster than the police is the most" % th)
	check(AdventurePolice.over_rule(-(20.0 + th + 0.1), 20.0, false, 26.8) > 0.0 and AdventurePolice.over_rule(26.8 + th - 0.1, 0.0, true, 26.8) < 0.0
		and AdventurePolice.over_rule(26.8 + th + 0.1, 0.0, true, 26.8) > 0.0, "either way along the road, and past a parked car 30 over the limit")
	for case in [[th - 0.6, false], [th + 0.6, true]]:
		var sim := {1: {"s": 0.0, "v": 0.0}}
		var p := _police(7, sim)
		var s0 := _straight(p.world.route, 3000.0)
		var id := p.spawn(s0, 1, false, 0.85)
		sim[1]["s"] = s0 - 120.0
		var d: float = case[0]
		# Overtaking it, d faster than it's going.
		_run(p, sim, 25.0, func(): return float(sim[1]["s"]) > float(p.driver.state(id)["s"]) + 150.0 or p.chasing(1),
			func(): sim[1]["v"] = float(p.driver.state(id)["v"]) + d)
		var chased := p.chasing(1)
		check(chased == case[1], "overtaking a police car %.1f m/s (%.1f mph) faster than it: %s" % [d, d * AdventurePolice.MPH, "chased" if chased else "left alone"])
		await _free(p)
	# Meeting one coming the other way.
	var sim2 := {1: {"s": 0.0, "v": 0.0}}
	var p2 := _police(7, sim2)
	var s1 := _straight(p2.world.route, 3000.0)
	var id2 := p2.spawn(s1 + 200.0, -1, false, 0.85)
	sim2[1]["s"] = s1
	_run(p2, sim2, 15.0, func(): return float(sim2[1]["s"]) > float(p2.driver.state(id2)["s"]) + 100.0 or p2.chasing(1),
		func(): sim2[1]["v"] = float(p2.driver.state(id2)["v"]) + th + 2.0)
	var met := p2.chasing(1)
	sim2[1]["v"] = 30.0
	var turned := _run(p2, sim2, 15.0, func(): return int(p2.driver.state(id2)["dir"]) == 1 and float(p2.driver.state(id2)["v"]) > 15.0)
	check(met and turned, "meeting one coming the other way too fast: it turns round and comes after you (chased %s, turned %s)" % [met, turned])
	await _free(p2)


## The chase: lights and siren on, flat out after the speeder (well past its patrol pace),
## round a slow lorry in its lane when the other side's clear; the siren's pitch higher coming
## and lower going.
func test_chase() -> void:
	var sim := {1: {"s": 0.0, "v": 0.0}}
	var p := _police(7, sim)
	var s0 := _straight(p.world.route, 3000.0, 1500.0)
	var id := p.spawn(s0, 1, false, 0.85)
	var patrol_v := float(p.driver.state(id)["v"])
	sim[1]["s"] = s0 - 60.0
	sim[1]["v"] = patrol_v + 20.0
	var started := _run(p, sim, 10.0, func(): return p.chasing(1))
	check(started and _has(p, "chase", 1), "passing it %.0f mph faster starts a chase" % (20.0 * AdventurePolice.MPH))
	check(p.messages.size() > 0 and p.messages[-1].begins_with("POLICE!"), "and you're told: \"%s\"" % (p.messages[-1] if p.messages.size() > 0 else ""))
	var seen := {"lit": false, "top": 0.0}
	_run(p, sim, 6.0, func():
		seen["lit"] = seen["lit"] or p.driver.body(id).blues != Vector2.ZERO
		seen["top"] = maxf(seen["top"], float(p.driver.state(id)["v"]))
		return false)
	var lit: bool = seen["lit"]
	var top: float = seen["top"]
	var siren: PoliceSiren = p._sirens.get(id)
	check(lit and siren != null and siren.on, "its blue lights flash and the siren's on")
	check(top > patrol_v + 8.0, "it goes after you hard: %.0f mph against its patrol's %.0f" % [top * AdventurePolice.MPH, patrol_v * AdventurePolice.MPH])
	var day := TrafficVehicle.BLUE_ON > 10.0 and AdventurePolice.blues_at(0.02).x > 0.0 and AdventurePolice.blues_at(0.42).y > 0.0
	check(day, "the blue lamps alternate left and right, bright enough to see by day")
	# A lorry ahead in its lane, nothing coming: it pulls out round it.
	var stream := TrafficStream.new()
	stream.sample = p.road_sample
	p.add_child(stream)
	stream.set_physics_process(false)   # alongside the driver, where it looks for the traffic
	var at := float(p.driver.state(id)["s"])
	sim[1]["s"] = at + 300.0
	sim[1]["v"] = float(p.driver.state(id)["v"])
	stream._add({"s": at + 40.0, "dir": 1, "v": 12.0, "pace": 0.6, "kind": "lorry", "seed": 5, "ind": 0})
	var low := {"lane": INF}
	_run(p, sim, 3.0, func():
		stream.vehicles[0]["s"] = float(stream.vehicles[0]["s"]) + 12.0 * DT
		low["lane"] = minf(low["lane"], float(p.driver.state(id)["lane"]))
		return low["lane"] < 0.0)
	var lane_min: float = low["lane"]
	check(lane_min < 0.0, "it pulls out round a slow lorry when the other side's clear (lane %.1f m)" % lane_min)
	stream.queue_free()
	var coming := PoliceSiren.doppler(Vector3.ZERO, Vector3(0, 0, 30), Vector3(0, 0, 100), Vector3.ZERO)
	var going := PoliceSiren.doppler(Vector3.ZERO, Vector3(0, 0, -30), Vector3(0, 0, 100), Vector3.ZERO)
	check(coming > 1.05 and going < 0.95 and PoliceSiren.note(0.0, false) < PoliceSiren.note(1.0, false),
		"the siren wails, and its pitch is higher coming (%.2f) and lower going (%.2f)" % [coming, going])
	await _free(p)


## Caught: stopped with the police on you, pulled over, the officer walks up and has his say,
## and the fine comes out of your own money (more for a second time that day; if you can't pay
## it all, what you have and points on your licence); then you're let go.
func test_caught() -> void:
	_active()
	check(AdventurePolice.fine_amount(30.0, 1) == 100 and AdventurePolice.fine_amount(45.0, 1) == 250 and AdventurePolice.fine_amount(45.0, 2) > 250
		and AdventurePolice.fine_amount(200.0, 1) == 600, "fines: £100 at 30 mph over, more the faster, more again for repeat offences, £600 at most")
	var keep := Progress.money()
	var points_before := AdventurePolice.licence_points()
	Progress.set_money(1000)
	var sim := {Shed.me(): {"s": 0.0, "v": 0.0}}
	var me := Shed.me()
	var p := _police(7, sim)
	var s0 := _straight(p.world.route, 3000.0, 1500.0)
	var id := p.spawn(s0, 1, false, 0.85)
	sim[me]["s"] = s0 - 60.0
	sim[me]["v"] = float(p.driver.state(id)["v"]) + 20.0
	_run(p, sim, 15.0, func(): return p.chasing(me) and float(sim[me]["s"]) > float(p.driver.state(id)["s"]) + 20.0)
	var excess := float(p.cars[id]["excess"])
	# Past it and away, then you stop by the road.
	sim[me]["brake"] = true
	var pulled := _run(p, sim, 30.0, func(): return p.holding(me))
	check(pulled and _has(p, "caught", me) and p.messages[-1].begins_with("Pulled over"), "you stop, and you're pulled over: \"%s\"" % p.messages[-1])
	var walked := _run(p, sim, 30.0, func(): return str(p.cars[id]["stage"]) == "walk")
	var fig: StaffFigure = p._officers.get(id)
	check(walked and fig != null, "the officer gets out and walks up to you")
	var talking := _run(p, sim, 30.0, func(): return str(p.cars[id]["stage"]) == "talk")
	_run(p, sim, 1.0)
	var fines := AdventurePolice.fines_of(me)
	var amount := int(fines[-1]["amount"]) if not fines.is_empty() else -1
	check(talking and fig != null and fig._said != "", "and has his say: \"%s\"" % (fig._said if fig else ""))
	check(amount == AdventurePolice.fine_amount(excess, 1) and int(fines[-1]["paid"]) == amount and Progress.money() == 1000 - amount,
		"fined £%d (%.0f mph too fast), paid from your own money: £1000 -> £%d" % [amount, excess, Progress.money()])
	check(p.messages[-1].begins_with("Fined £%d" % amount), "the HUD says so: \"%s\"" % p.messages[-1])
	var still := p.holding(me)
	var released := _run(p, sim, 30.0, func(): return not p.holding(me) and p.cars[id]["mode"] == "patrol")
	check(still and released and float(p.driver.state(id)["v"]) >= 0.0, "held till he's done, then let go, and the car drives off")
	# Again the same day with £50 to your name: what you have, and points for the rest.
	Progress.set_money(50)
	sim[me]["brake"] = false
	p.cars[id]["let_off"].clear()
	sim[me]["s"] = float(p.driver.state(id)["s"]) - 60.0
	sim[me]["v"] = float(p.driver.state(id)["v"]) + 20.0
	_run(p, sim, 15.0, func(): return p.chasing(me) and float(sim[me]["s"]) > float(p.driver.state(id)["s"]) + 20.0)
	sim[me]["brake"] = true
	_run(p, sim, 90.0, func(): return AdventurePolice.fines_of(me).size() == 2 and int(AdventurePolice.fines_of(me)[-1]["paid"]) >= 0)
	fines = AdventurePolice.fines_of(me)
	var second: Dictionary = fines[-1] if fines.size() == 2 else {}
	check(not second.is_empty() and int(second["n"]) == 2 and int(second["amount"]) > amount and int(second["paid"]) == 50 and Progress.money() == 0
		and int(second["points"]) >= AdventurePolice.POINTS and AdventurePolice.licence_points() == points_before + int(second["points"]),
		"a second time that day costs more (£%d), and with only £50 the rest's %d points on your licence" % [int(second.get("amount", 0)), int(second.get("points", 0))])
	Progress.set_money(keep)
	if not Progress.profile.is_empty():
		Progress.profile["stats"]["licence_points"] = points_before
	await _free(p)


## Outrun: get well away from it and keep away, and it gives up.
func test_outrun() -> void:
	var sim := {1: {"s": 0.0, "v": 0.0}}
	var p := _police(7, sim)
	var s0 := _straight(p.world.route, 3000.0)
	var id := p.spawn(s0, 1, false, 0.85)
	sim[1]["s"] = s0 - 60.0
	sim[1]["v"] = float(p.driver.state(id)["v"]) + 20.0
	_run(p, sim, 10.0, func(): return p.chasing(1))
	sim[1]["v"] = 80.0
	var gave := _run(p, sim, 90.0, func(): return _has(p, "gave_up", 1))
	var gap := float(sim[1]["s"]) - float(p.driver.state(id)["s"])
	check(gave and p.cars[id]["mode"] == "patrol" and gap > AdventurePolice.LOSE_DIST and p.driver.body(id).blues == Vector2.ZERO,
		"outrun it (%.0f m ahead) and it gives up, lights off" % gap)
	check(p.messages[-1].begins_with("You've lost the police"), "and you're told: \"%s\"" % p.messages[-1])
	await _free(p)


## A speed trap: a car parked in a lay-by with an officer and his speed gun; 30 over the limit
## past it is fine, more and it pulls out after you.
func test_trap() -> void:
	var sim := {1: {"s": 0.0, "v": 0.0}}
	var p := _police(7, sim, 150.0)
	var site := {}
	for st in p.world.route.sites_of("layby"):
		if float(st["s"]) > 2000.0:
			site = st
			break
	check(not site.is_empty(), "there's a lay-by to park in")
	if site.is_empty():
		await _free(p)
		return
	var ss := float(site["s"])
	var id := p.spawn(ss, 1, true, 0.9, int(site["side"]))
	var st0 := p.driver.state(id)
	var limit := AdventurePolice.limit_at(p.world.route, ss)
	var hw := p.world.route.width_at_s(ss) * 0.5
	var lat := -float(st0["lane"]) * int(st0["dir"])   # metres right of the centre line
	check(p.cars[id]["mode"] == "parked" and float(st0["v"]) == 0.0 and absf(lat) > hw + 1.0 and signf(lat) == float(site["side"]),
		"parked in the lay-by, %.1f m off the centre line on its side" % lat)
	var way := int(st0["dir"])
	sim[1]["s"] = ss - way * 150.0
	p.tick(DT)
	var fig: StaffFigure = p._officers.get(id)
	check(fig != null and fig.hand.get_child_count() > 0, "with an officer beside it holding a speed gun")
	for case in [[AdventurePolice.THRESHOLD - 0.5, false], [AdventurePolice.THRESHOLD + 0.5, true]]:
		p.cars[id]["let_off"].clear()
		sim[1]["s"] = ss - way * 150.0
		sim[1]["v"] = way * (limit + float(case[0]))
		_run(p, sim, 12.0, func(): return (float(sim[1]["s"]) - ss) * way > 150.0 or p.chasing(1))
		check(p.chasing(1) == case[1], "past it at %.0f mph (limit %.0f): %s" % [absf(float(sim[1]["v"])) * AdventurePolice.MPH, limit * AdventurePolice.MPH,
			"it comes after you" if p.chasing(1) else "left alone"])
	_run(p, sim, 4.0)
	var out := p.driver.state(id)
	check(float(out["lane"]) < hw and float(out["v"]) > 10.0 and not p._officers.has(id), "it pulls out of the lay-by and gets going (officer in the car)")
	await _free(p)


## Co-op: two riders past the same car, only the one too fast is chased, pulled over and fined
## (on their own machine: here, the host's, the other's fine is theirs to pay); the cars, lights
## and the stop go to the crew in pack / unpack.
func test_coop() -> void:
	_active()
	var keep := Progress.money()
	Progress.set_money(500)
	var me := Shed.me()
	var mate := me + 1
	var sim := {me: {"s": 0.0, "v": 0.0}, mate: {"s": 0.0, "v": 0.0}}
	var p := _police(7, sim)
	var s0 := _straight(p.world.route, 3000.0, 1500.0)
	var id := p.spawn(s0, 1, false, 0.85)
	var pv := float(p.driver.state(id)["v"])
	sim[me]["s"] = s0 - 70.0
	sim[mate]["s"] = s0 - 60.0
	sim[me]["v"] = pv + 6.0
	sim[mate]["v"] = pv + 20.0
	_run(p, sim, 15.0, func(): return p.chasing(mate) and float(sim[mate]["s"]) > float(p.driver.state(id)["s"]) + 20.0)
	check((p.chasing(mate) or p.holding(mate)) and not p.chasing(me) and not p.holding(me), "two riders go past: only the one too fast is chased")
	sim[mate]["brake"] = true
	sim[me]["v"] = 24.0
	_run(p, sim, 40.0, func(): return p.holding(mate))
	check(p.holding(mate) and not p.holding(me), "and only they're pulled over; the other rides on")
	# The crew's copy of it.
	var client := AdventurePolice.new()
	client.world = p.world
	client.rider_source = p.rider_source
	t.add_child(client)
	client.set_physics_process(false)
	client.plan = []
	client.host = false
	client.driver.host = false
	var lit := false
	for i in 60:
		_run(p, sim, DT)
		client.unpack(p.pack())
		client.tick(DT)
		lit = lit or (client.driver.body(id) != null and client.driver.body(id).blues != Vector2.ZERO)
	var cb: Dictionary = client.cars.get(id, {})
	check(not cb.is_empty() and cb["mode"] == "stop" and int(cb["target"]) == mate and client.holding(mate)
		and absf(float(client.driver.state(id)["s"]) - float(p.driver.state(id)["s"])) < 1.0 and lit,
		"the crew see the same car, in the same place, lights going, stopping the same rider")
	_run(p, sim, 60.0, func(): return not AdventurePolice.fines_of(mate).is_empty())
	_run(p, sim, 1.0)
	var theirs := AdventurePolice.fines_of(mate)
	check(theirs.size() == 1 and AdventurePolice.fines_of(me).is_empty() and Progress.money() == 500 and int(theirs[0]["paid"]) < 0,
		"the fine's theirs (£%d, for them to pay from their own money); nothing for the other rider, whose money's untouched" % int(theirs[0]["amount"] if theirs.size() > 0 else 0))
	client.queue_free()
	Progress.set_money(keep)
	await _free(p)


## Out in the adventure's traffic the police car is one of the stream's vehicles, taken over:
## a "police" vehicle the stream draws (and sends the crew), driven by the police, the rest of the
## traffic for it to get round, its lights and siren in its aux; gone, it's off the road.
func test_stream() -> void:
	var sim := {1: {"s": 0.0, "v": 0.0}}
	var w := AdventureWorld.new()
	w.setup(7, 60.0)
	for f in w.route.forks.size():
		w.route.choose(f, 0)
	w.focus = func(): return [w.transform_at(float(sim[1]["s"]), -1.5).origin]
	w.process_mode = Node.PROCESS_MODE_DISABLED
	t.add_child(w)
	var tr := AdventureTraffic.new()
	w.add_child(tr)
	tr.set_physics_process(false)
	var p := AdventurePolice.new()
	p.world = w
	p.rider_source = func() -> Array:
		return [{"peer": 1, "s": sim[1]["s"], "v": sim[1]["v"]}]
	w.add_child(p)
	p.set_physics_process(false)
	p.plan = []
	check(p.driver is PoliceStreamDriver, "with the adventure's traffic about, the police drive in it")
	var s0 := _straight(w.route, 3000.0, 1500.0)
	sim[1]["s"] = s0 - 200.0
	tr._physics_process(DT)
	var id := p.spawn(s0, 1, false, 0.85)
	var k := p.driver.stream_id(id)
	var sl := tr.stream.slot(k)
	check(id >= 0 and k >= 0 and str(sl.get("kind", "")) == "police" and bool(sl.get("scripted", false)) and p.driver.body(id) != null,
		"a police car goes into the stream as one of its vehicles, taken over (%s)" % str(sl.get("kind", "?")))
	var ours := false
	for o in p.driver.traffic():
		ours = ours or absf(float(o["s"]) - float(sl.get("s", -1.0))) < 0.01
	check(not ours, "the traffic it sees to get round is everyone else's")
	var patrol_v := float(p.driver.state(id)["v"])
	sim[1]["s"] = s0 - 60.0
	sim[1]["v"] = patrol_v + 20.0
	var seen := {"aux": 0}
	_run(p, sim, 14.0, func(): return p.chasing(1) and int(seen["aux"]) == 3, func():
		tr._physics_process(DT)
		seen["aux"] = int(seen["aux"]) | int(tr.stream.find(k).get("aux", 0)))
	var moved := tr.stream.slot(k)
	check(p.chasing(1) and int(seen["aux"]) == 3 and absf(float(moved.get("s", -1.0)) - float(p.driver.state(id)["s"])) < 0.01,
		"chasing, the stream's car is where the police put it, its lights and siren in its aux (%d)" % int(seen["aux"]))
	# The crew: their stream brings the car, the police say which one it is.
	var cs := TrafficStream.new()
	cs.sample = tr.stream.sample
	cs.host = false
	t.add_child(cs)
	cs.set_physics_process(false)
	cs.unpack(tr.stream.pack())
	var client := AdventurePolice.new()
	var cd := PoliceStreamDriver.new()
	cd.stream = cs
	cd.name = "PoliceDriver"
	client.driver = cd
	client.world = w
	client.rider_source = p.rider_source
	client.plan = []
	t.add_child(client)
	client.set_physics_process(false)
	client.host = false
	cd.host = false
	client.unpack(p.pack())
	var cst := cd.state(id)
	check(cd.stream_id(id) == k and not cst.is_empty() and absf(float(cst["s"]) - float(p.driver.state(id)["s"])) < 0.5 and cd.body(id) != null,
		"the crew's police find the same car in their own stream")
	client.queue_free()
	cs.queue_free()
	# A car parked in a lay-by isn't in anyone's lane.
	var hw := float(tr.stream.sample.call(s0)["hw"])
	check(not TrafficStream._in_lane({"dir": 1, "lat": hw + 2.5}, hw) and TrafficStream._in_lane({"dir": 1, "lat": -hw * 0.45}, hw)
		and TrafficStream._in_lane({"dir": 1, "lat": NAN}, hw),
		"the traffic queues behind a car in its lane, not one in a lay-by")
	p.remove(id)
	check(tr.stream.find(k).is_empty() and not p.driver.has(id), "gone off the police, it's off the road")
	p.queue_free()
	w.queue_free()
	Shed.adventure = {}
	await t.get_tree().process_frame
	await t.get_tree().process_frame
