extends RefCounted
## Riding on adventures (Simon: "brakes seem to fade on adventures", later "remove brake fade",
## "too many rattles", "a sharper handlebar turn at <10mph"): the brakes after a long ride, how
## often something goes wrong over a whole ride, and how tight a turn the bars make slow. Run from
## tests/run_tests.gd: its _test_adv_ride_* functions hand over to these.

const Rides := preload("res://tests/rides.gd")
## The ride lengths the odds are checked over (km).
const LENGTHS := {"Short": 100.0, "Ride": 150.0, "Epic": 220.0}

var t: Node   # the test runner: check(), ride(), _done()

const MPH60 := 26.8224   # m/s


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _ticks(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## The speed a rider takes the road at `s` at: up to `cruise`, slowing for the tightest bend in
## the next 120 m (about a quarter of a g round it), and to a stop at a junction ahead (`stop_at`, m).
static func _road_speed(r: AdventureRoute, s: float, cruise: float, stop_at := INF) -> float:
	var most := 0.0
	var i0 := int(s / AdventureRoute.STEP)
	for k in 30:
		var i := clampi(i0 + k, 0, r.curv.size() - 1)
		# Further off, a bend needs less slowing for yet: there's room to brake down to it.
		most = maxf(most, absf(r.curv[i]) / (1.0 + k * AdventureRoute.STEP / 60.0))
	var want := minf(cruise, sqrt(2.5 / maxf(most, 1e-4)))
	return minf(want, sqrt(2.0 * 3.0 * maxf(stop_at - s - 2.0, 0.0)))


## Brakes: 12 km of an adventure's road ridden with ordinary braking (slowing for every bend at
## the speed its curves ask for at up to 60 mph, and stopping at each junction and a give-way
## every 2 km, with the whole lever, as a key gives it, whenever it's well over the speed)
## doesn't fade them, and a 60-0 stop after it is as short as on fresh brakes: on discs with the
## pads that fade soonest (organic), and on an old bike's drums. The road's bends and junctions are
## played out on flat test tarmac, so the ride is quick to run and nothing else gets in the way.
func test_brakes() -> void:
	await _brakes_ride(_with_pads(Contracts.style_build("classic"), "organic"), "discs, organic pads")
	await _brakes_ride(_merge(Contracts.style_build("classic"), {"front_disc": "drum_tls_200", "rear_disc": "drum_sls_180"}), "drums")


func _brakes_ride(build: Dictionary, nm: String) -> void:
	var route := Rides.route(40.0, 7)
	var stops := []
	for site in route.sites:
		if str(site["kind"]) in ["junction", "fork", "fuel"]:
			stops.append(float(site["s"]))
	for k in range(1, 7):
		stops.append(k * 2000.0 - 300.0)
	stops.sort()
	var root := Node3D.new()
	t.add_child(root)
	root.add_child(TestGround.new(4000.0, "tarmac"))
	var bike := Bike.new()
	bike.setup(BikeBuild.new(build))
	root.add_child(bike)
	bike.place(Vector3.ZERO, 0.0)
	bike.auto_shift = true
	bike.assist = 0.5
	var weather = Weather.current
	Weather.current = null
	BikeHeat.fixed_air = 15.0
	var st := {"s": 0.0, "hottest": 0.0, "least": 1.0, "braked": 0.0, "next": 2000.0, "line": [], "stops": 0, "wait": 0.0, "slowed": 0, "was": 9.0, "work": 0.0}
	var dt := 1.0 / Engine.physics_ticks_per_second
	var steps := 0
	while float(st["s"]) < 12000.0 and steps < 1200 * Engine.physics_ticks_per_second and not bike.is_crashed:
		steps += 1
		var s: float = st["s"]
		while not stops.is_empty() and float(stops[0]) < s - 1.0:
			stops.pop_front()
		var want := _road_speed(route, s, MPH60, float(stops[0]) if not stops.is_empty() else INF)
		if not stops.is_empty() and float(stops[0]) - s < 4.0 and bike.speed < 0.5:
			# Stopped at the junction: a look both ways, and away.
			st["wait"] += dt
			want = 0.0
			if st["wait"] > 3.0:
				stops.pop_front()
				st["wait"] = 0.0
				st["stops"] += 1
		var over := bike.speed - want
		bike.throttle = clampf(0.25 - over * 0.35, 0.0, 1.0)
		bike.front_brake = 1.0 if over > 2.0 or want == 0.0 else (0.4 if over > 0.8 else 0.0)
		bike.rear_brake = bike.front_brake * 0.5
		await t.get_tree().physics_frame
		st["s"] += maxf(bike.speed, 0.0) * dt
		if bike.front_brake > 0.0 and bike.speed > 1.0:
			st["braked"] += dt
		# Each time it slows (the brakes on after a second or more off them).
		if bike.front_brake > 0.0 and st["was"] > 1.0:
			st["slowed"] += 1
		st["was"] = 0.0 if bike.front_brake > 0.0 else st["was"] + dt
		st["work"] += float(bike.wheels[0].get("brake_used", 0.0)) * absf(float(bike.wheels[0]["omega"])) * dt
		st["hottest"] = maxf(st["hottest"], bike.heat.discs[0])
		st["least"] = minf(st["least"], bike.heat.bite[0])
		if absf(bike.global_position.z) > 1500.0:
			# The test tarmac runs out: carry on from the middle of it, going just as fast.
			var xf := bike.global_transform
			xf.origin = Vector3(0.0, xf.origin.y, 0.0)
			PhysicsServer3D.body_set_state(bike.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		if float(st["s"]) > float(st["next"]):
			st["next"] += 2000.0
			st["line"].append("%d km %d °C" % [roundi(float(st["s"]) / 1000.0), roundi(bike.heat.discs[0])])
	print("    %s, front brake along the ride: %s; %.0f s on the brakes, %d times, %d junction stops, %.1f MJ into the front brake" % [
		nm, ", ".join(st["line"]), st["braked"], st["slowed"], st["stops"], st["work"] / 1e6])
	var ridden := BikeHeat.new()
	ridden.setup(bike.build)
	ridden.copy_from(bike.heat)
	var crashed := bike.is_crashed
	root.queue_free()
	Weather.current = weather if is_instance_valid(weather) else null
	await _ticks(2)
	check(not crashed and float(st["s"]) >= 12000.0 and st["slowed"] >= 20 and st["stops"] >= 6,
		"%s: 12 km of the road ridden, braking %d times for its bends and junctions (%d stops)" % [nm, st["slowed"], st["stops"]])
	check(st["least"] > 0.97, "%s: the brakes never fade along it (front brake %d °C at the hottest, bite never under x%.2f)" % [
		nm, roundi(st["hottest"]), st["least"]])
	var fresh := await _stop60(build, null)
	var after := await _stop60(build, ridden)
	BikeHeat.fixed_air = NAN
	check(fresh > 0.0 and after > 0.0 and after < fresh * 1.03,
		"%s: a 60-0 stop after the ride takes %.1f m, on fresh brakes %.1f m" % [nm, after, fresh])


## Brought up to just past 60 mph on flat tarmac and stopped as hard as it goes (as the realism
## tests do), with the brakes' heat `heat` copied in as the brakes go on (null: fresh, warm
## brakes). Metres from 60 mph to a stop, or -1 if it crashed.
func _stop60(build: Dictionary, heat: BikeHeat) -> float:
	var st := {"braking": false, "from": Vector3.ZERO, "at": -1.0, "dist": -1.0}
	var r: Dictionary = await t.ride(build, 14.0, func(bike, at):
		if not st["braking"]:
			bike.throttle = 1.0
			bike.body_shift = 0.6
			st["braking"] = bike.speed >= MPH60 + 1.0
			if st["braking"] and heat:
				bike.heat.discs = heat.discs.duplicate()
				bike.heat.pads = heat.pads.duplicate()
			return
		bike.throttle = 0.0
		bike.body_shift = 0.0
		bike.front_brake = 1.0
		bike.rear_brake = 0.6
		if st["at"] < 0.0 and bike.speed <= MPH60:
			st["at"] = at
			st["from"] = bike.global_position
		if st["at"] >= 0.0 and st["dist"] < 0.0 and bike.speed < 0.3:
			st["dist"] = bike.global_position.distance_to(st["from"]))
	var out: float = st["dist"] if not r["crashed"] else -1.0
	await t._done(r)
	return out


## Nothing fades them now (Simon: "remove brake fade"), not even a long steep descent (4 km at
## 12%, 60 km/h) held on the brakes alone, three quarters of it on the front: the discs and drums
## come down it hot, but organic pads, sintered ones and an old bike's drums all keep their full
## bite, and a 60-0 stop at the foot of it is as short as on fresh brakes.
func test_descent_brakes() -> void:
	var out := {}
	var builds := {"organic": _with_pads(Contracts.style_build("classic"), "organic"),
		"sintered": _with_pads(Contracts.style_build("classic"), "sintered"),
		"drum": _merge(Contracts.style_build("classic"), {"front_disc": "drum_tls_200", "rear_disc": "drum_sls_180"})}
	for pad in builds:
		var hb: Array = t._heat_of(builds[pad], 15.0)
		var h: BikeHeat = hb[0]
		var b: BikeBuild = hb[1]
		h.warm_through()
		var v := 16.7
		var held := b.total_mass * Bike.G * 0.12 * v
		t._heat_run(h, b, 4000.0 / v, v, 300.0, 3000.0, 0.0, held * 0.75)
		var hot := h.brake_temp_mult(0)
		var disc := h.discs[0]
		t._heat_run(h, b, 180.0, 25.0, 400.0, 5000.0, 7.0)
		out[pad] = [hot, h.brake_temp_mult(0), disc]
		print("    %s: front brake %d °C at the foot of the descent, bite x%.3f; x%.3f after 3 min riding on" % [pad, roundi(disc), hot, h.brake_temp_mult(0)])
	check(out["organic"][2] > 300.0 and out["drum"][2] > 300.0,
		"a long steep descent on the brakes cooks them (front disc %d °C, drum %d °C)" % [roundi(out["organic"][2]), roundi(out["drum"][2])])
	check(out["organic"][0] > 0.999 and out["sintered"][0] > 0.999 and out["drum"][0] > 0.999,
		"but none of them fade: full bite at the foot of it (organic x%.3f, sintered x%.3f, drums x%.3f)" % [out["organic"][0], out["sintered"][0], out["drum"][0]])
	# A hard 60-0 stop on the brakes as they come off the descent.
	BikeHeat.fixed_air = 15.0
	for pad in ["organic", "drum"]:
		var hb: Array = t._heat_of(builds[pad], 15.0)
		var h: BikeHeat = hb[0]
		var b: BikeBuild = hb[1]
		h.warm_through()
		var v := 16.7
		t._heat_run(h, b, 4000.0 / v, v, 300.0, 3000.0, 0.0, b.total_mass * Bike.G * 0.12 * v * 0.75)
		var fresh := await _stop60(builds[pad], null)
		var after := await _stop60(builds[pad], h)
		check(fresh > 0.0 and after > 0.0 and after < fresh * 1.02,
			"%s: a 60-0 stop at the foot of the descent (%d °C) takes %.1f m, on fresh brakes %.1f m" % [pad, roundi(h.discs[0]), after, fresh])
	BikeHeat.fixed_air = NAN


static func _with_pads(build: Dictionary, pad: String) -> Dictionary:
	return _merge(build, {"front_pads": pad, "rear_pads": pad})


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


## A bike in the state most ridden ones are in: not new, looked after now and then.
const TYPICAL := {"chain_wear": 0.25, "chain_lube": 0.6, "chain_slack": 34.0, "oil_age": 0.6, "oil_level": 0.9,
	"engine_wear": 0.25, "wear": 0.3}


## Breakdowns and punctures over whole adventures: rides of about 90 minutes, two hours and three hours (100, 150 and
## 220 km) on the tours' own mix of surfaces (round them as many times as it takes), ridden km by km on a typical bike a
## few hundred times. About one thing goes wrong on a ride, not several; a ride with three or more is rare.
func test_breakdown_odds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1808
	var means := {}
	for length in LENGTHS:
		var km := float(LENGTHS[length])
		var rides := 0
		var events := 0
		var many := 0
		var expected := 0.0
		var punctures := 0
		var seeds := [3, 11, 27, 40, 52]
		for seed in seeds:
			var route := Rides.tour_route("dales" if seed % 2 == 1 else "shodoshima", seed)
			var surfs := []
			for k in int(km):
				surfs.append(route.surface_at_s(fmod(k * 1000.0 + 500.0, route.length)))
			var rates := {}
			for surf in surfs:
				if not rates.has(surf):
					rates[surf] = Roadside.rates(TYPICAL, surf)
			for surf in surfs:
				for k in rates[surf]:
					expected += float(rates[surf][k]) / seeds.size()
				expected += 2.0 * float(Puncture.PER_KM.get(surf, 0.003)) / seeds.size()
			for ride in 60:
				var n := 0
				for surf in surfs:
					if Roadside.roll(rates[surf], 1.0, rng.randf()) != "":
						n += 1
					for tyre in 2:
						if Puncture.ride_punctures(surf, 1.0, rng.randf()):
							n += 1
							punctures += 1
				rides += 1
				events += n
				many += 1 if n >= 3 else 0
		var mean := float(events) / rides
		means[length] = mean
		var nm := str(length)
		print("    %s (%d km): %.2f things go wrong a ride (%.2f expected, %.2f of them punctures), %d of %d rides with 3 or more" % [
			nm, roundi(km), mean, expected, float(punctures) / rides, many, rides])
		check(absf(mean - expected) < 0.2, "%s: the rolls come out as the odds say (%.2f a ride against %.2f)" % [nm, mean, expected])
		check(mean > 0.3 and mean < 1.25 and float(many) / rides < 0.15,
			"%s (%d km, about %d minutes): %.2f things go wrong a ride on a typical bike, %d%% of rides see 3 or more" % [
				nm, roundi(km), AdventureDest.minutes_for(km), mean, roundi(100.0 * many / rides)])
	check(means["Short"] < means["Ride"] and means["Ride"] < means["Epic"], "the longer the ride, the more chance of something")
	check(not Puncture.hit_punctures(20.0, 0.0, 0.4) and Puncture.hit_punctures(20.0, 0.0, 3.0) and not Puncture.hit_punctures(5.0, 0.0, 3.0),
		"a pothole hit at speed can pinch a tyre; the fork sinking on to its stop under the brakes can't")


## The widest a full-input turn at 15 mph may be (m), by style (before: 7.4 and 11.6 m).
const WIDEST_15 := {"classic": 6.5, "cruiser": 9.0}


## How tight a turn the input held full makes at `mph` (at Riding realism `assist`): [radius m,
## lean deg, bars deg, crashed].
func _full_turn(build: Dictionary, mph: float, assist := 0.5) -> Array:
	var v := mph * 0.44704
	var acc := {"r": 0.0, "lean": 0.0, "steer": 0.0, "n": 0}
	var r: Dictionary = await t.ride(build, 14.0, func(bike, at):
		bike.assist = assist
		bike.throttle = clampf(0.12 + (v - bike.speed) * 0.5, 0.0, 1.0)
		bike.front_brake = clampf((bike.speed - v) * 0.3, 0.0, 0.3)
		bike.lean_input = 0.0 if at < 6.0 else 1.0
		if at > 10.0:
			acc["r"] += absf(bike.speed / maxf(absf(bike.angular_velocity.y), 0.01))
			acc["lean"] += absf(rad_to_deg(bike.lean_angle))
			acc["steer"] += absf(rad_to_deg(bike.steer))
			acc["n"] += 1)
	var n := maxi(int(acc["n"]), 1)
	var out := [acc["r"] / n, acc["lean"] / n, acc["steer"] / n, r["crashed"]]
	await t._done(r)
	return out


## The widest a full-input turn at 5 and 8 mph may be (m), by style (before, with the bars short
## of full lock below 10 mph: 2.7 and 3.3 m on both).
const WIDEST_5 := {"classic": 2.35, "cruiser": 2.6}
const WIDEST_8 := {"classic": 2.9, "cruiser": 3.1}


## Slow, the input held full turns the bike as sharply as the bars let it (Simon: "a sharper
## handlebar turn at <10mph"): full lock at walking pace, a tight U-turn at 5-8 mph, still a sharp
## junction at 10-15 mph. The faster it goes the less lock it takes and the wider the turn, as on
## a real bike.
func test_tight_turns() -> void:
	# A cruiser grounds its footboards about 30 degrees over, which sets its turn at 15 mph.
	var lock := rad_to_deg(Bike.STEER_LOCK)
	for style in ["classic", "cruiser"]:
		var nm := PartsDB.style_name(style)
		var line := []
		var radii := []
		var bars := []
		var crashed := false
		for mph in [2.0, 5.0, 8.0, 10.0, 15.0, 25.0]:
			var got: Array = await _full_turn(Contracts.style_build(style), mph)
			line.append("%d mph %.1f m (lean %d°, bars %d°)" % [roundi(mph), got[0], roundi(got[1]), roundi(got[2])])
			radii.append(got[0])
			bars.append(got[2])
			crashed = crashed or got[3]
		print("    %s, input held full: %s" % [nm, ", ".join(line)])
		check(not crashed, "%s: full-input turns from 2 to 25 mph all hold" % nm)
		check(bars[0] > lock * 0.97, "%s: at walking pace the bars go to full lock (%.1f° of %.0f°)" % [nm, bars[0], lock])
		check(radii[1] < float(WIDEST_5[style]) and radii[2] < float(WIDEST_8[style]) and bars[1] > lock * 0.85,
			"%s: a much sharper turn below 10 mph: %.1f m at 5 mph (bars %.1f°), %.1f m at 8 mph" % [nm, radii[1], bars[1], radii[2]])
		check(radii[3] < 4.5 and radii[4] < float(WIDEST_15[style]), "%s: a sharp turn at 10 mph (%.1f m) and 15 mph (%.1f m)" % [nm, radii[3], radii[4]])
		var opening := true
		for i in range(1, radii.size()):
			opening = opening and radii[i] > radii[i - 1] and bars[i] < bars[i - 1]
		check(opening, "%s: less lock and a wider turn the faster it goes" % nm)


## A full input held round at B-road speeds, at Riding realism 0 where nothing helps: the bike
## holds the lean it's asked for rather than swinging past it and sliding off (a race bike and an
## MX bike did from 40-45 km/h, where a full input stopped keeping a little lean in hand).
func test_full_turns_hold() -> void:
	for c in [["race", 45.0], ["mx", 50.0], ["supermoto", 80.0]]:
		var got: Array = await _full_turn(Contracts.style_build(c[0]), float(c[1]) / 1.609344, 0.0)
		check(not got[3], "%s, realism 0: a full-input turn at %d km/h holds (%.1f m, lean %d°)" % [PartsDB.style_name(c[0]), roundi(c[1]), got[0], roundi(got[1])])
