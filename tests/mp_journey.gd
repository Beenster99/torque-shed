extends Node
## Two-process co-op check of a journey planned together on the shed's map (see JourneyMap, AdventureJourney,
## RoutePlanner), run by tests/mp_test.sh after the others: the client and the host each put pins on the map and
## both must see all of them, and the style of ride the client picks. Each game plans the same journey itself; the host
## starts the ride and both must be riding the same planned road (the same hash, checked by AdventureTrip.real_mismatch),
## each seen by the other at the right spot on it. The host ends it. On the way, the Route planner TVs: the client
## moves the world's map on the Dyno Room's wall TV and the host types in its search, and both must show the same; then
## each says "I'm in", the host's Start waiting for the client's, and the host starts the ride from the TV.

const REGION := "shodoshima"

var role := "host"
var main: Node


func _ready() -> void:
	AdventureWorld.network = false   # (the single planned road: this pair checks it, the network has its own)
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	CellStore.offline = true   # (the TV's world needs no cells from the network here)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Plan %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var r := RealRegion.get_region(REGION)
	var a := r.geo_to_xz(34.518638, 134.269646)
	var mid := r.geo_to_xz(34.53, 134.22)
	var b := r.geo_to_xz(34.499373, 134.347915)
	await _until(func(): return Shed.crew.size() == 2, 60.0)
	# The pins: the client puts the first and the last, the host the one between (so the order is the board's, not whose).
	if role == "client":
		Shed.request({"a": "adventure_pin", "region": REGION, "x": a.x, "z": a.y})
	var first := await _until(func(): return (Shed.journey.get("pins", []) as Array).size() >= 1, 20.0)
	if role == "host":
		Shed.request({"a": "adventure_pin", "region": REGION, "x": b.x, "z": b.y})
		Shed.request({"a": "adventure_pin", "region": REGION, "x": mid.x, "z": mid.y, "at": 1})
	var pinned := await _until(func(): return (Shed.journey.get("pins", []) as Array).size() == 3, 20.0)
	var pins: Array = Shed.journey.get("pins", [])
	var by_ok := pinned and str(pins[0]["by"]).ends_with("client") and str(pins[1]["by"]).ends_with("host") and str(pins[2]["by"]).ends_with("host")
	print("MP journey note %s: pins %s" % [role, str(pins.map(func(p): return "%s %s" % [p["by"], str(Vector2(p["x"], p["z"]))]))])
	# The style of ride: the client picks scenic, and both see it.
	if role == "client":
		Shed.request({"a": "adventure_mode", "mode": "scenic"})
	var mode_ok := await _until(func(): return str(Shed.journey.get("mode", "")) == "scenic", 20.0)
	# The TV: one view for the crew. Both walk into the Dyno Room (its planner comes on as they come near), the client
	# moves the world's map there, the host turns it to the search and types in it.
	main.walker.place(Transform3D(Basis(Vector3.UP, PI * 0.5), DynoRoom.CENTER + Vector3(1.0 if role == "host" else 2.0, 0.0, 0.5)))
	var tv_ok := await _until(func(): return main.workshop.dyno_room.plan_tv._route != null, 20.0)
	var board: RouteTv = main.workshop.dyno_room.plan_tv._route if tv_ok else null
	var at := Vector2(34.53, 134.22)
	if tv_ok and role == "client":
		board.ask({"lat": at.x, "lon": at.y, "span": 4000.0})
	if tv_ok and role == "host":
		await _until(func(): return Shed.route_tv.has("lat"), 20.0)
		board.ask({"tab": "find"})
		for ch in "TAK":
			board.type(ch)
	var view_ok := false
	if tv_ok:
		view_ok = await _until(func():
			return board._q() == "tak" and is_equal_approx(board.view.span, 4000.0) and Vector2(board.view.lat, board.view.lon).distance_to(at) < 1e-5 \
				and board._find_box.visible and board._query.text.contains("TAK"), 20.0)
	print("MP journey note %s: the TV at %.4f, %.4f, %.0f m across, the %s tab, typed %s (channel %s)" % [role,
		board.view.lat if board else 0.0, board.view.lon if board else 0.0, board.view.span if board else 0.0,
		Shed.route_tv.get("tab", "?"), board._q() if board else "?", str(Shed.screen_channel("dyno").get("ch", "?"))])
	# The client says its screen has caught up (another letter), and the host waits for that before the ride: out on
	# the road, the shed and its TVs sleep.
	if view_ok and role == "client":
		board.type("a")
	if view_ok:
		view_ok = await _until(func(): return board._q() == "taka", 20.0)
	# Each plans it: the same road, the same hash.
	var plan := AdventureJourney.plan_of(Shed.journey)
	var res := AdventurePlans.result(plan, true)
	var hash := (res["pack"] as RealPack).hash if bool(res.get("ok", false)) else ""
	print("MP journey note %s: planned %s km, hash %s" % [role, "%.1f" % (res["pack"] as RealPack).max_km() if hash != "" else "?", hash])
	# "I'm in": the host first, and its Start waits for the client; then the client, and the host starts it from the TV.
	var in_ok := false
	if view_ok and role == "host":
		board.im_in()
		var waits := await _until(func(): return AdventureJourney.riders_in(Shed.journey).size() == 1 and board._sig == board._signature(), 20.0)
		in_ok = waits and board._start.disabled and board._crew.text == "Plan host is in; waiting for Plan client."
		print("MP journey note host: on its own say-so, Start %s (%s)" % ["waits" if board._start.disabled else "is lit", board._crew.text])
	if view_ok and role == "client":
		await _until(func(): return AdventureJourney.riders_in(Shed.journey).size() == 1, 20.0)
		board.im_in()
	var all_in := view_ok and await _until(func(): return AdventureJourney.riders_in(Shed.journey).size() == 2 and board._sig == board._signature(), 20.0)
	if role == "host":
		in_ok = in_ok and all_in and not board._start.disabled and board._start.text == "Start the ride"
	else:
		in_ok = all_in and board._crew.text == "Everyone's in." and board._in.button_pressed
		board.ask({"q": "in"})   # (the client's screen has caught up: the host may start, which clears the marks)
	if role == "host" and in_ok:
		in_ok = await _until(func(): return board._q() == "in", 20.0)
	print("MP journey note %s: everyone in %s (%s), Start %s" % [role, all_in, board._crew.text if board else "?", board._start.text if board else "?"])
	var started := await _until(func():
		if role == "host" and not Adventure.active() and not trip.on_trip():
			board.start()
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 60.0)
	var same_road := started and hash != "" and str(Shed.adventure.get("real_hash", "")) == hash and trip.world != null \
		and trip.world.route.real != null and trip.world.route.real.hash == hash and AdventureTrip.real_mismatch(Shed.adventure) == ""
	print("MP journey note %s: riding %s, same road %s (%.1f km)" % [role, started, same_road, trip.world.route.length / 1000.0 if trip.world else 0.0])
	# Each seen by the other where it stands.
	var seen_ok := false
	if same_road:
		var mine := 1500.0 if role == "host" else 2200.0
		var theirs := 2200.0 if role == "host" else 1500.0
		var my_lat := -1.5 if role == "host" else 1.0
		var their_lat := 1.0 if role == "host" else -1.5
		_jump_to(trip, mine, my_lat)
		var err := [Vector2(INF, INF)]
		seen_ok = await _until(func():
			_hold(trip, mine, my_lat)
			err[0] = _seen_error(trip, theirs, their_lat)
			return err[0].x < 0.1 and err[0].y < 0.1, 30.0)
		print("MP journey note %s: the other seen off by %.3f m along, %.3f m across" % [role, err[0].x, err[0].y])
		var stay := Time.get_ticks_msec() + 6000
		await _until(func():
			_hold(trip, mine, my_lat)
			return Time.get_ticks_msec() > stay, 10.0)
	# Home: the host ends it.
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and not Adventure.active(), 30.0)
	var ok := first and pinned and by_ok and mode_ok and view_ok and in_ok and hash != "" and started and same_road and seen_ok and home
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP journey %s %s: pins shared=%s (by whom=%s), style of ride shared=%s, the TV's view shared=%s, everyone in=%s, planned=%s, riding=%s on the same road=%s, each seen by the other=%s, home=%s" % [
		"PASS" if ok else "FAIL", role, pinned, by_ok, mode_ok, view_ok, in_ok, hash != "", started, same_road, seen_ok, home])
	get_tree().quit(0 if ok else 1)


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
