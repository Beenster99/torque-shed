extends Node
## Two-process co-op check of a ride along a real road (the tour of the Dales, see AdventurePlans.TOURS and
## AdventureRoute.plan_real), run by tests/mp_test.sh after the others: a host and a client start the
## real game, the host starts the ride for both, and both must be on it with the same road planned
## (its hash). Some way along it each must see the other at the right spot on the road to within a few
## centimetres. Both sleep at an inn along it, then the client rides to the finish: both must arrive at the
## destination. The host ends it.

const Rides := preload("res://tests/rides.gd")

const REGION := "dales"
const SEED := 4204
## Where along the road (m) the two stand to see each other.
const ALONG := 9000.0

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Real %s" % role
	# Planned before connecting: planning a long ride holds the game for seconds, longer than the link waits.
	var plan := AdventurePlans.tour(REGION)
	var pack := AdventurePlans.pack_for(plan)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var ok_start := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
			Shed.request({"a": "adventure_start", "plan": plan, "seed": SEED, "title": "Round the Dales"})
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 60.0)
	var same_road := ok_start and str(Shed.adventure.get("real", "")) == pack.id and str(Shed.adventure.get("real_hash", "")) == pack.hash \
		and trip.world != null and trip.world.route.real == pack and AdventureTrip.real_mismatch(Shed.adventure) == ""
	print("MP real note %s: on the road %s, the same copy %s, %.1f km" % [role, ok_start, same_road, trip.world.route.length / 1000.0 if trip.world else 0.0])
	var wait_until := Time.get_ticks_msec() + 4000
	await _until(func(): return Time.get_ticks_msec() > wait_until, 5.0)
	# Some way along the road, each seen by the other where it stands.
	var seen_ok := false
	if same_road and trip.on_trip():
		var mine := ALONG + (400.0 if role == "host" else 700.0)
		var theirs := ALONG + (700.0 if role == "host" else 400.0)
		var my_lat := -1.5 if role == "host" else 1.0
		var their_lat := 1.0 if role == "host" else -1.5
		_jump_to(trip, mine, my_lat)
		var err := [Vector2(INF, INF)]
		seen_ok = await _until(func():
			_hold(trip, mine, my_lat)
			err[0] = _seen_error(trip, theirs, their_lat)
			return err[0].x < 0.1 and err[0].y < 0.1, 30.0)
		print("MP real note %s: at %.0f m along, the other seen off by %.3f m along, %.3f m across" % [role, mine, err[0].x, err[0].y])
	# Stay put a while so the other has seen us here too (the checks end at different moments on each side).
	if seen_ok and trip.on_trip():
		var stay := Time.get_ticks_msec() + 8000
		var holder_s := trip.world.distance_of(main.bike.global_position, "stay") if main.bike else 0.0
		await _until(func():
			_hold(trip, holder_s, -1.5 if role == "host" else 1.0)
			return Time.get_ticks_msec() > stay, 10.0)
	# The night stop: both get off at the real inn's room, the host calls it a night, both wake rested in the morning.
	var slept := false
	if seen_ok and trip.on_trip():
		slept = await _night_stop(trip)
	# The client rides to the finish; both arrive at the set piece.
	var arrived := false
	var both_there := false
	if seen_ok and slept:
		var settle := Time.get_ticks_msec() + 4000
		await _until(func(): return Time.get_ticks_msec() > settle, 5.0)
		if role == "client":
			trip.jump(trip.world.route.length - trip.world.distance_of(main.bike.global_position, "own") - 4.0)
		arrived = await _until(func():
			if role == "client" and main.bike and int(Shed.adventure.get("arrived", 0)) == 0:
				main.bike.throttle = 0.3
			return int(Shed.adventure.get("arrived", 0)) != 0 and trip.moment_done, 30.0)
		var ds := AdventureDest.dest_s(trip.world) if trip.world else 0.0
		both_there = await _until(func():
			if trip.world == null or main.bike == null or _remote_bike() == null:
				return false
			var m := trip.world.distance_of(main.bike.global_position, "check_me")
			var t := trip.world.distance_of(_remote_bike().global_position, "check_them")
			return absf(m - ds) < 25.0 and absf(t - ds) < 25.0, 20.0)
		print("MP real note %s: arrived %s, both at the destination %s" % [role, arrived, both_there])
	# Home: the host ends it, after the client has had time to check.
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and not Adventure.active(), 30.0)
	var ok := ok_start and same_road and seen_ok and slept and arrived and both_there and home
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP real %s %s: on the real road=%s with the same copy=%s, each seen by the other along it=%s, a night at the inn=%s, arrived=%s, together at the destination=%s, home=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, same_road, seen_ok, slept, arrived, both_there, home])
	get_tree().quit(0 if ok else 1)


## The first inn or campsite on the road as it runs now (past the start), or {}.
func _sleep_site(route: AdventureRoute) -> Dictionary:
	for st: Dictionary in route.sites:
		if ["inn", "campsite"].has(str(st["kind"])) and float(st["s"]) > 500.0 and float(st["s"]) < route.length - 1000.0:
			return st
	return {}


## The beds (an inn's rooms, a campsite's pitches) within 120 m of `s` along the road, by name.
func _beds_near(trip: AdventureTrip, s: float) -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group(AdventureNeeds.BED_GROUP):
		var n3 := node as Node3D
		if n3 != null and n3.is_inside_tree() and absf(trip.world.distance_of(n3.global_position, "bed") - s) < 120.0:
			out.append(n3)
	out.sort_custom(func(a, b): return str(a.get_meta("name", "")) < str(b.get_meta("name", "")))
	return out


func _night_stop(trip: AdventureTrip) -> bool:
	var inn := _sleep_site(trip.world.route)
	if inn.is_empty():
		print("MP real note %s: no inn or campsite on the road" % role)
		return false
	var s := float(inn["s"])
	var my_s := s - 25.0 - (0.0 if role == "host" else 4.0)
	_jump_to(trip, my_s, -1.0)
	var holder := [null]   # (a lambda gets its own copy of a variable: this one is shared)
	var found := await _until(func():
		_hold(trip, my_s, -1.0)
		holder[0] = _beds_near(trip, s)
		return (holder[0] as Array).size() >= 2, 40.0)
	print("MP real note %s: the %s '%s' at %.0f m, its bed found %s" % [role, inn["kind"], inn["name"], s, found])
	if not found:
		return false
	var bed := (holder[0] as Array)[0 if role == "host" else 1] as Node3D   # a room each
	var view: AdventureNeedsView = trip.needs
	var bike_id := Shed.riding(Shed.me())
	await _until(func(): return main.bike != null and Time.get_ticks_msec() - main._mounted_at > 800, 5.0)
	# Brought to a stop, then off: a bike still rolling from the ride in (or down in a heap) won't let
	# its rider off on the first try, so keep at it for a moment.
	var off := func() -> bool:
		if main.bike != null:
			main.bike.linear_velocity = Vector3.ZERO
			main._get_off()
		return main.bike == null
	await _until(off, 5.0)
	Progress.set_money(400)
	await _ticks(3)
	main.walker.place(bed.global_transform)
	await _ticks(3)
	var why := view.take(view.find_near())
	print("MP real note %s: took the bed: '%s'" % [role, why])
	if why != "":
		return false
	var other := 0
	for peer in Shed.crew:
		if int(peer) != Shed.me():
			other = int(peer)
	var slept := false
	if role == "host":
		await _until(func(): return AdventureNeeds.all_abed(), 20.0)
		Shed.request({"a": "needs_sleep"})
	slept = await _until(func():
		return int(Shed.adventure.get("nights", 0)) == 1 and AdventureNeeds.level(Shed.me(), "rest") == 1.0 \
			and AdventureNeeds.level(other, "rest") == 1.0, 30.0)
	print("MP real note %s: slept till morning %s (%s)" % [role, slept, Daylight.clock_text(Daylight.time_of_day())])
	if not slept:
		return false
	# Up, and back on the bike for the rest of the road.
	view.stand_up()
	await _ticks(10)
	var bike_xf: Transform3D = Shed.bikes[bike_id]["xf"] if Shed.bikes.has(bike_id) else Transform3D()
	main.walker.place(bike_xf)
	await _ticks(5)
	main._try_mount(bike_id)
	var back := await _until(func(): return main.bike != null, 10.0)
	print("MP real note %s: back on the bike %s" % [role, back])
	return back


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _remote_bike() -> Node3D:
	for peer in main.remotes:
		var rp = main.remotes[peer]
		if is_instance_valid(rp) and rp.bike != null:
			return rp.bike
	return null


func _jump_to(trip: AdventureTrip, s: float, lat: float) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	trip.jump(s - trip.world.distance_of(main.bike.global_position, "own"))
	var xf := trip.world.transform_at(s, lat)
	main.bike.place(xf.origin, trip.world.heading_at(s))


func _hold(trip: AdventureTrip, s: float, lat: float) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	var xf := trip.world.transform_at(s, lat)
	if main.bike.global_position.distance_to(xf.origin) > 0.05 or main.bike.is_crashed:
		main.bike.place(xf.origin, trip.world.heading_at(s))


func _seen_error(trip: AdventureTrip, s: float, lat: float) -> Vector2:
	var rb := _remote_bike()
	if rb == null or not trip.on_trip():
		return Vector2(INF, INF)
	var hit := trip.world.locate_local(rb.global_position, "check")
	if hit.is_empty():
		return Vector2(INF, INF)
	return Vector2(absf(float(hit["s"]) - s), absf(float(hit["lat"]) - lat))
