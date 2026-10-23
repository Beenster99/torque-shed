extends RefCounted
## Respawn protection (see BikeGhost) and riders passing through each other on an adventure,
## run from tests/run_tests.gd (its _test_ghost_* functions hand over to these).

const Rides := preload("res://tests/rides.gd")

var t: Node   # the test runner: check(), ride(), get_tree()


func _init(runner: Node) -> void:
	t = runner


func check(cond: bool, what: String) -> void:
	t.check(cond, what)


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


## How see-through a model's meshes are drawn: [faintest, most solid] of them.
static func _drawn(m: Node3D) -> Vector2:
	var lo := INF
	var hi := -INF
	for n in m.find_children("*", "GeometryInstance3D", true, false):
		var v := (n as GeometryInstance3D).transparency
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(hi, lo)


## The look: faint from the start, fading back to solid over the last moments with a flicker in
## the last second, and solid once it's over.
func test_look() -> void:
	check(BikeGhost.look(0.0) == 0.0 and BikeGhost.look(-1.0) == 0.0, "no ghost: solid")
	check(is_equal_approx(BikeGhost.look(BikeGhost.TIME), BikeGhost.FAINT) and is_equal_approx(BikeGhost.look(2.5), BikeGhost.FAINT),
		"just respawned, see-through (%.2f)" % BikeGhost.look(BikeGhost.TIME))
	var most := 0.0
	var ups := 0
	var last := BikeGhost.look(1.0)
	var left := 1.0
	while left > 0.0:
		left -= 1.0 / 120.0
		var v := BikeGhost.look(left)
		most = maxf(most, v)
		if v > last + 0.001:
			ups += 1
		last = v
	check(most <= BikeGhost.FAINT * 0.7 and ups >= 3, "the last second fades back to solid with a gentle flicker (%d flickers, at most %.2f)" % [ups, most])
	var prev := INF
	var fading := true
	for k in range(15, 50):
		var v := BikeGhost.look(k / 10.0)
		fading = fading and v <= prev + 0.0001
		prev = v
	check(fading and BikeGhost.look(1.2) < BikeGhost.look(1.5), "and before that it's fading, not flickering")


## A respawn makes the bike a ghost: see-through, rider and all, said in its snapshot, passing
## through other bikes (its mask has the world alone), still on its wheels on the ground; 5 s on
## it's solid again, drawn and bumping as before.
func test_respawn() -> void:
	var r: Dictionary = await t.ride({}, 0.5, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	check(not bike.is_ghost() and bike.collision_mask == Bike.SOLID_MASK and _drawn(bike.model).x == 0.0, "riding along: solid")
	bike.crash()
	await _frames(2)
	bike.respawn()
	await _frames(2)
	var d := _drawn(bike.model)
	check(bike.is_ghost() and bike.ghost_left > BikeGhost.TIME - 0.1 and d.y > 0.5,
		"respawned: a ghost for %.1f s, drawn see-through (%.2f to %.2f)" % [bike.ghost_left, d.y, d.x])
	check(bike.model._rider != null and bike.model._rider.visible and (bike.model._rider.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).transparency > 0.5,
		"the rider's back on and see-through too")
	check(bike.collision_mask == 1, "it passes through other bikes and the traffic (bumping into the world alone)")
	check(bike.get_net_state().size() > 27 and bike.get_net_state()[27] > BikeGhost.TIME - 0.1, "and its snapshot says so (%.2f)" % bike.get_net_state()[27])
	var ground := true
	for i in 120 * 4:
		await t.get_tree().physics_frame
		if i > 60:   # (put back on a little above the ground)
			ground = ground and bike.wheels[0]["contact"] and bike.wheels[1]["contact"]
	check(ground and bike.is_ghost() and not bike.is_crashed, "four seconds on it's still a ghost, on its wheels on the ground")
	var mid := _drawn(bike.model).x
	await _frames(int(120 * 1.1))
	d = _drawn(bike.model)
	check(not bike.is_ghost() and d.x == 0.0 and d.y == 0.0 and bike.collision_mask == Bike.SOLID_MASK and bike.get_net_state()[27] == 0.0,
		"5 s after the respawn it's solid again, drawn and bumping as before (it was %.2f a second before)" % mid)
	# Coming off by itself (tipped over) ends a ghost; the next respawn starts another.
	bike.respawn()
	await _frames(2)
	bike.crash()
	check(not bike.is_ghost() and bike.collision_mask == Bike.SOLID_MASK and BikeGhost.drawn(bike.model) == 0.0, "a ghost that comes off is solid again")
	await t._done(r)


## A tall block on the road at the bike's layer (another bike, a car), and one on the world's
## (a wall), `at` m ahead.
static func _block(root: Node3D, at: float, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.4, 1.0)
	cs.shape = box
	body.add_child(cs)
	root.add_child(body)
	body.global_position = Vector3(0.0, 1.2, -at)
	return body


## Rides at 10 m/s into a block `at` m ahead on `layer`: {crashed, past (got by it), ground}.
func _ride_into(ghost: bool, layer: int) -> Dictionary:
	var out := {"crashed": false, "past": false, "ground": true, "z": 0.0}
	var r: Dictionary = await t.ride({}, 0.3, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	_block(r["root"], 14.0, layer)
	if ghost:
		bike.start_ghost()
	bike.linear_velocity = -bike.global_transform.basis.z * 10.0
	bike.gear = 2
	for i in 120 * 3:
		bike.throttle = 0.25
		await t.get_tree().physics_frame
		out["crashed"] = out["crashed"] or bike.is_crashed
		out["ground"] = out["ground"] and (bike.wheels[0]["contact"] or bike.wheels[1]["contact"] or bike.is_crashed)
	out["z"] = bike.global_position.z
	out["past"] = bike.global_position.z < -16.0
	await t._done(r)
	return out


## Nothing knocks a ghost off: riding into another bike or a car it passes through, still on the
## ground; into a wall, it's stopped but stays on. Solid, the same block stops it (the traffic
## throwing you off is test_adventure's).
func test_pass_through() -> void:
	var solid := await _ride_into(false, 2)
	check(not solid["past"], "solid, riding into another bike or a car at 10 m/s, it stops you (%.1f m on)" % -float(solid["z"]))
	var ghost := await _ride_into(true, 2)
	check(not ghost["crashed"] and ghost["past"] and ghost["ground"], "a ghost passes straight through it, on its wheels (now %.1f m on)" % -float(ghost["z"]))
	var wall := await _ride_into(true, 1)
	check(not wall["crashed"] and not wall["past"], "a ghost riding into a wall is stopped by it, and not knocked off")


## A crew member's respawn: their snapshot makes your copy of their bike a ghost, drawn
## see-through, and your bike passes through it (in the shed's yard as well); once it's over
## it's solid again and yours bumps into it as before.
func test_remote() -> void:
	var r: Dictionary = await t.ride({}, 0.2, func(_b, _t): pass)
	var bike: Bike = r["bike"]
	var rb := RemoteBike.new()
	r["root"].add_child(rb)
	rb.setup("Crew", BikeBuild.new({}), Color.RED)
	var state := bike.get_net_state()
	state[0] += 3.0
	rb.push_state(state)
	await _frames(3)
	check(not rb.is_ghost() and BikeGhost.drawn(rb.model) == 0.0 and not bike.passes(rb), "not respawned: their bike's solid and yours bumps into it")
	state[27] = 1.0
	rb.push_state(state)
	await _frames(3)
	check(rb.is_ghost() and BikeGhost.drawn(rb.model) > 0.2 and _drawn(rb.model).y > 0.2, "they respawn: their bike's drawn as a ghost on your screen (%.2f)" % BikeGhost.drawn(rb.model))
	check(bike.passes(rb) and bike.get_collision_exceptions().has(rb), "and your bike passes through it")
	var since := Time.get_ticks_msec()
	while Time.get_ticks_msec() - since < 1300:
		await _frames(1)
	check(not rb.is_ghost() and BikeGhost.drawn(rb.model) == 0.0 and _drawn(rb.model).x == 0.0, "over on their side: solid again here")
	check(not bike.passes(rb) and not bike.get_collision_exceptions().has(rb), "and your bike bumps into it again")
	var old := state.slice(0, 27)
	rb.push_state(old)
	await _frames(3)
	check(not rb.is_ghost(), "an older game's shorter snapshot is never a ghost")
	await t._done(r)


## Out on an adventure: the crew's bikes pass through each other (nobody's knocked off by a
## mate), the traffic still throws you off, and not in your first 5 s after a respawn.
func test_adventure() -> void:
	AdventureTrip.instant = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.get_tree().process_frame
	main._start_session()
	Shed.start_new("Tester", 9)
	await t.get_tree().physics_frame
	var faithful: int = t._bike_named("Old Faithful")
	main.walker.place(Transform3D(Basis(), (Shed.bikes[faithful]["xf"] as Transform3D).origin + Vector3(1.0, 0.0, 0.0)))
	check(not Bike.riders_pass(), "in the shed's yard riders bump into each other as before")
	Rides.start(20.0, 3)
	for i in 30:
		await t.get_tree().physics_frame
	var trip: AdventureTrip = main.trip
	check(trip.on_trip() and main.bike != null, "out on an adventure")
	if not trip.on_trip() or main.bike == null:
		await _end(main)
		return
	await Rides.take_main_roads(trip)
	var w := trip.world
	var s := 600.0
	trip.jump(s - w.distance_of(main.bike.global_position, "own"))
	await _frames(30)
	check(Bike.riders_pass(), "out here riders pass through each other")
	# A mate's bike stood just ahead in your lane, not a ghost: yours passes through it.
	var rb := RemoteBike.new()
	main.world.add_child(rb)
	rb.setup("Mate", BikeBuild.new({}), Color.BLUE)
	var bike: Bike = main.bike
	var ahead := w.transform_at(s + 10.0, -1.6)
	bike.place(w.transform_at(s, -1.6).origin, w.heading_at(s))
	var st := bike.get_net_state()
	var q := ahead.basis.get_rotation_quaternion()
	for k in 3:
		st[k] = ahead.origin[k] + (0.4 if k == 1 else 0.0)
	st[3] = q.x
	st[4] = q.y
	st[5] = q.z
	st[6] = q.w
	st[27] = 0.0
	for i in 20:
		rb.push_state(st)
		await t.get_tree().physics_frame
	check(not rb.is_ghost() and bike.passes(rb), "a mate's bike, solid, is one yours passes through")
	var hit := await _ride_along(trip, s, 12.0, 2.5, null, -1, rb)
	check(float(hit["closest"]) < 0.6, "riding straight at them (%.2f m apart at the closest)" % float(hit["closest"]))
	check(not hit["crashed"] and float(hit["s"]) > s + 14.0, "riding into a mate at 12 m/s: straight through, nobody knocked off (%.1f m on)" % (float(hit["s"]) - s))
	rb.queue_free()
	# The traffic still throws you off, a ghost excepted.
	var tr := AdventureTraffic.current
	check(tr != null and tr.host, "the adventure has its traffic")
	if tr == null:
		await _end(main)
		return
	tr.stream.clear()
	var crashes := []
	for ghost in [false, true]:
		s += 400.0
		tr.stream.clear()
		trip.jump(s - w.distance_of(main.bike.global_position, "own"))
		await _frames(20)
		bike = main.bike
		bike.place(w.transform_at(s, -1.6).origin, w.heading_at(s))
		var id := tr.stream.spawn_at("van", s + 20.0, -1, 0.0)
		check(id >= 0, "a van stopped in your lane ahead")
		if ghost:
			bike.start_ghost()
		var ride := await _ride_along(trip, s, 12.0, 2.5, tr, id)
		crashes.append(ride["crashed"])
		if bike.is_crashed:
			bike.respawn()
		bike.ghost_left = 0.0
		bike.collision_mask = Bike.SOLID_MASK
	check(crashes[0], "riding into a stopped van at 12 m/s throws you off, as before")
	check(not crashes[1], "but not in the 5 s after a respawn: a ghost passes through it")
	await _end(main)


## Rides `main.bike` on from `s` at `v` m/s for `seconds`, the van `id` (when given) held stopped
## in your lane. {crashed, closest (to `near`), s (how far along it got)}.
func _ride_along(trip: AdventureTrip, s: float, v: float, seconds: float, tr: AdventureTraffic = null, id := -1, near: Node3D = null) -> Dictionary:
	var bike: Bike = trip.main.bike
	var w := trip.world
	bike.engine_on = true
	bike.gear = 3
	bike.linear_velocity = w.transform_at(s, -1.6).basis * Vector3(0.0, 0.0, -v)
	var crashed := false
	var closest := INF
	for i in int(seconds * 120.0):
		bike.throttle = 0.3
		bike.lean_input = 0.0
		if tr != null:
			var d := tr.stream.take(id)
			if not d.is_empty():
				d["v"] = 0.0
				d["lat"] = -1.6   # stopped in your lane
		await t.get_tree().physics_frame
		if trip.main.bike == null:
			break
		crashed = crashed or bike.is_crashed
		if near != null:
			closest = minf(closest, bike.global_position.distance_to(near.global_position))
	return {"crashed": crashed, "closest": closest, "s": w.distance_of(bike.global_position, "own") if is_instance_valid(bike) else -1.0}


func _end(main: Node) -> void:
	main.queue_free()
	AdventureTrip.instant = false
	Shed.stop()
	await _frames(3)
