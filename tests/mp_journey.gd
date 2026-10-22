extends Node
## Two-process co-op check of a journey planned together on the shed's map (see JourneyMap, AdventureJourney,
## RoutePlanner), run by tests/mp_test.sh after the others: the client and the host each put pins on the map and
## both must see all of them, and the style of ride the client picks. Each game plans the same journey itself; the host
## starts the ride and both must be riding the same planned road (the same hash, checked by AdventureTrip.real_mismatch),
## each seen by the other at the right spot on it. The host ends it. On the way, the Route planner TVs: the client
## moves the map on the Dyno Room's wall TV and the host turns it to the places, and both must show the same.

const REGION := "shodoshima"

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
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
	# The TV: one view for the crew. The client moves the Dyno Room's map, the host turns it to the places.
	var tv_ok := await _until(func(): return main.workshop.dyno_room.plan_tv._route != null \
		and main.workshop.dyno_room.plan_tv._route.region != null, 20.0)
	var board: RouteTv = main.workshop.dyno_room.plan_tv._route if tv_ok else null
	var at := mid + Vector2(250.0, -120.0)
	if tv_ok and role == "client":
		board._ask_view(at, 4000.0)
	if tv_ok and role == "host":
		await _until(func(): return Shed.route_tv.has("x"), 20.0)
		board.ask({"tab": "places", "cat": 1, "page": 0})
	var view_ok := false
	if tv_ok:
		view_ok = await _until(func():
				return str(Shed.route_tv.get("region", "")) == REGION and str(Shed.route_tv.get("tab", "")) == "places" \
				and board.region.id == REGION and board.view.view_centre().distance_to(at) < 0.2 \
				and absf(board.view.view_span() - 4000.0) < 1.0 and board._places_box.visible and board._category() == 1, 20.0)
	print("MP journey note %s: the TV on %s at %s (asked %s), %.1f m across, the %s tab, places shown %s, kind %d (channel %s)" % [role,
		board.region.id if board else "?", str(board.view.view_centre()) if board else "?", str(at), board.view.view_span() if board else 0.0,
		Shed.route_tv.get("tab", "?"), board._places_box.visible if board else false, board._category() if board else -1,
		str(Shed.screen_channel("dyno").get("ch", "?"))])
	# The client says its screen has caught up (the next page), and the host waits for that before the ride: out on the
	# road, the shed and its TVs sleep.
	if view_ok and role == "client":
		board.ask({"page": 1})
	if view_ok:
		view_ok = await _until(func(): return int(Shed.route_tv.get("page", 0)) == 1, 20.0)
	# Each plans it: the same road, the same hash.
	var plan := AdventureJourney.plan_of(Shed.journey)
	var res := AdventurePlans.result(plan, true)
	var hash := (res["pack"] as RealPack).hash if bool(res.get("ok", false)) else ""
	print("MP journey note %s: planned %s km, hash %s" % [role, "%.1f" % (res["pack"] as RealPack).max_km() if hash != "" else "?", hash])
	# The host starts it.
	var started := await _until(func():
		if role == "host" and not Adventure.active() and not trip.on_trip():
			Shed.request({"a": "adventure_start", "plan": plan, "seed": 5, "title": "Across the island"})
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
	var ok := first and pinned and by_ok and mode_ok and view_ok and hash != "" and started and same_road and seen_ok and home
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP journey %s %s: pins shared=%s (by whom=%s), style of ride shared=%s, the TV's view shared=%s, planned=%s, riding=%s on the same road=%s, each seen by the other=%s, home=%s" % [
		"PASS" if ok else "FAIL", role, pinned, by_ok, mode_ok, view_ok, hash != "", started, same_road, seen_ok, home])
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
