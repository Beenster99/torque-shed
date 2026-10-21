extends Node
## Two-process co-op check of a ride along a real road with a fork (the Dales epic, see RealPack and
## AdventureRoute.plan_real), run by tests/mp_test.sh after the others: a host and a client start the
## real game, the host starts the real road for both, and both must be on it with the same copy of
## it (its hash). At the first fork the client votes for the other way and the host picks it, and both
## must have the road built along it. Past the fork each must see the other at the right spot on the
## road to within a few centimetres (the path is the other way's, a different length from the main
## road's). Then the client rides to the finish: both must arrive at the set piece. The host ends it.

const PACK := "dales"
const SEED := 4204

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Real %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var pack := RealPack.get_pack(PACK)
	var km := floorf(pack.max_km())
	var ok_start := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
			Shed.request({"a": "adventure_start", "seed": SEED, "km": km, "theme": "hills", "dest": "dales_rally", "real": PACK,
				"title": "The Dales Epic"})
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 60.0)
	var same_road := ok_start and str(Shed.adventure.get("real", "")) == PACK and str(Shed.adventure.get("real_hash", "")) == pack.hash \
		and trip.world != null and trip.world.route.real == pack and AdventureTrip.real_mismatch(Shed.adventure) == ""
	var forks := trip.world.route.forks.size() if trip.world else 0
	print("MP real note %s: on the road %s, the same copy %s, %d forks, %.1f km" % [role, ok_start, same_road, forks, trip.world.route.length / 1000.0 if trip.world else 0.0])
	var wait_until := Time.get_ticks_msec() + 4000
	await _until(func(): return Time.get_ticks_msec() > wait_until, 5.0)
	# The first fork: the client votes for the other way (1), the host picks it, both roads are built along it.
	var fork_ok := false
	if same_road and forks > 0:
		var other := 0
		for peer in Shed.crew:
			if int(peer) != Shed.me():
				other = int(peer)
		if role == "client":
			Shed.request({"a": "adventure_vote", "fork": 0, "way": 1})
		var seen_vote := await _until(func():
			if role == "host" and int(AdventureForks.votes_of(0).get(other, -1)) == 1 and AdventureForks.pick_of(0) < 0:
				Shed.request({"a": "adventure_vote", "fork": 0, "way": 1})
			return int(AdventureForks.votes_of(0).get(1 if role == "client" else other, -1)) >= 1, 20.0)
		var built := await _until(func(): return trip.world != null and trip.world.route.decided.has(0) and int(trip.world.route.choices[0]) == 1, 20.0)
		fork_ok = seen_vote and built
		print("MP real note %s: votes at the fork %s, pick %d, my road along way %d, path %.1f km" % [role, str(AdventureForks.votes_of(0)),
			AdventureForks.pick_of(0), int(trip.world.route.choices.get(0, -1)) if trip.world else -1, trip.world.route.total / 1000.0 if trip.world else 0.0])
	# Past the fork, each seen by the other where it stands.
	var seen_ok := false
	if fork_ok and trip.on_trip():
		var rejoin := trip.world.route.rejoin_s(0)
		var mine := rejoin + (400.0 if role == "host" else 700.0)
		var theirs := rejoin + (700.0 if role == "host" else 400.0)
		var my_lat := -1.5 if role == "host" else 1.0
		var their_lat := 1.0 if role == "host" else -1.5
		_jump_to(trip, mine, my_lat)
		var err := [Vector2(INF, INF)]
		seen_ok = await _until(func():
			_hold(trip, mine, my_lat)
			err[0] = _seen_error(trip, theirs, their_lat)
			return err[0].x < 0.1 and err[0].y < 0.1, 30.0)
		print("MP real note %s: at %.0f m past the fork, the other seen off by %.3f m along, %.3f m across" % [role, mine, err[0].x, err[0].y])
	# The client rides to the finish; both arrive at the set piece.
	var arrived := false
	var both_there := false
	if seen_ok:
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
		print("MP real note %s: arrived %s, both at the set piece %s" % [role, arrived, both_there])
	# Home: the host ends it, after the client has had time to check.
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and not Adventure.active(), 30.0)
	var ok := ok_start and same_road and forks > 0 and fork_ok and seen_ok and arrived and both_there and home
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP real %s %s: on the real road=%s with the same copy=%s, a fork=%s, the other way taken by both=%s, each seen by the other past it=%s, arrived=%s, together at the set piece=%s, home=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, same_road, forks > 0, fork_ok, seen_ok, arrived, both_there, home])
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
