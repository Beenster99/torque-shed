extends Node
## Two-process co-op check of the other bikers on an adventure (AdventureBikers), run by
## tests/mp_test.sh: a host and a client start the real game and an adventure, and stand on the
## road a little apart. The host puts a biker on the road just ahead of the client, going their
## way; the client sees it, rides up behind it and keeps its pace, and the host has it join the
## client (it's the client's machine that's riding, the host that decides): both see it riding
## with the crew, in front of the client at its place in the line, on both screens. The client
## nods and it nods back (on the client's machine). Then the client stops: the biker stops too, on
## both, and the host has it wave and part, which both see. Finally the host ends the adventure.

const SEED := 321
const KM := 50.0
const CLIENT_S := 6000.0
const HOST_S := 5650.0
const PACE := 14.0

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Bikers %s" % role
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var note := [""]
	var ok_start := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip():
			Adventure.start(SEED, KM)
		return trip.on_trip() and main.bike != null and AdventureTraffic.current != null and _remote_bike() != null, 40.0)
	if not ok_start:
		note[0] = "crew %d, on the trip %s, bike %s, the other's bike %s, traffic %s" % [Shed.crew.size(), trip.on_trip(), main.bike != null,
			_remote_bike() != null, AdventureTraffic.current != null]
	var mine := CLIENT_S if role == "client" else HOST_S
	var lat := -1.5
	var joined_ok := false
	var line_ok := false
	var nod_ok := role == "host"
	var stop_ok := false
	var part_ok := false
	if ok_start:
		var tr := AdventureTraffic.current
		tr.bikers._spawn_timer = INF   # just the one, ours
		if role == "host":
			tr.bikers.clear()
		_jump_to(trip, mine, lat)
		if role == "host":
			var r := await _host_side(trip, tr, mine, lat, note)
			joined_ok = r[0]
			line_ok = r[1]
			stop_ok = r[2]
			part_ok = r[3]
		else:
			var r := await _client_side(trip, tr, mine, lat, note)
			joined_ok = r[0]
			line_ok = r[1]
			nod_ok = r[2]
			stop_ok = r[3]
			part_ok = r[4]
	# Home: the host ends it (once the client has had time to check, too).
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 4000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and not Adventure.active(), 25.0)
	var ok := ok_start and joined_ok and line_ok and nod_ok and stop_ok and part_ok and home_ok
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP bikers %s %s: on the adventure=%s, the biker rides with the client=%s, at its place in front of them=%s, nods back=%s, stops when they stop=%s, waves and parts=%s, back at the shed=%s (%s)" % [
		"PASS" if ok else "FAIL", role, ok_start, joined_ok, line_ok, nod_ok, stop_ok, part_ok, home_ok, note[0]])
	get_tree().quit(0 if ok else 1)


## The host: stands still well back, puts the biker in just ahead of the client once they're
## there, watches it join them (the client's riding), keep its place, and stop when they stop;
## then has it part.
func _host_side(trip: AdventureTrip, tr: AdventureTraffic, mine: float, lat: float, note: Array) -> Array:
	var b := tr.bikers
	var client_s := func() -> float:
		if tr.rider_spots.size() < 2 or (tr.rider_spots[1] as Array).is_empty():
			return NAN
		return float(tr.rider_spots[1][0])
	var there := await _until(func():
		_hold(trip, mine, lat)
		var s: float = client_s.call()
		return not is_nan(s) and absf(s - CLIENT_S) < 30.0, 60.0)
	if not there:
		note[0] = "the client never turned up at %.0f m (seen at %s)" % [CLIENT_S, str(tr.rider_spots)]
		return [false, false, false, false]
	tr.stream.clear()
	b.clear()
	var id := int(b.spawn_group(float(client_s.call()) + 25.0, 1, 1, PACE)[0])
	var d := b.find(id)
	d["pace"] = PACE / tr.limit_at(float(d["s"]))
	d["jtime"] = 1000.0
	var joined := await _until(func():
		_hold(trip, mine, lat)
		tr.stream.clear()
		return int(d["rider"]) == 1, 30.0)
	note[0] = "host: joined %s (place %d)" % [joined, int(d.get("jslot", 0))]
	# Riding with them: in front, its place kept (once it's dropped back into it).
	await _until_for(func():
		_hold(trip, mine, lat)
		tr.stream.clear()
		return true, 6.0)
	var worst := [0.0]
	var line := await _until_for(func():
		_hold(trip, mine, lat)
		tr.stream.clear()
		var gap := float(d["s"]) - float(client_s.call())
		worst[0] = maxf(worst[0], absf(gap - maxf(AdventureBikers.FORM_GAP, PACE * AdventureBikers.FORM_TIME)))
		return int(d["rider"]) == 1, 6.0)
	line = line and worst[0] < 4.0
	# They stop: it stops.
	var stopped := await _until(func():
		_hold(trip, mine, lat)
		tr.stream.clear()
		return float(b.riders[1]["v"]) < 0.3 and float(d["v"]) < 0.3 and int(d["rider"]) == 1, 30.0)
	var at_stop := [float(b.riders[1]["v"]), float(d["v"]), float(d["s"]) - float(client_s.call())]
	var still_t := Time.get_ticks_msec() + 3000
	await _until(func():
		_hold(trip, mine, lat)
		return Time.get_ticks_msec() > still_t, 4.0)
	b._part(d, true)
	var parted := int(d["rider"]) < 0 and int(d["gesture"]) == AdventureBikers.WAVE
	# Long enough for the client to see it go.
	var stay := Time.get_ticks_msec() + 8000
	await _until(func():
		_hold(trip, mine, lat)
		tr.stream.clear()
		return Time.get_ticks_msec() > stay, 9.0)
	note[0] += ", its place kept to %.1f m, stopped %s (the client at %.1f m/s, the biker %.1f, %.1f m ahead), parted %s" % [worst[0], stopped,
		at_stop[0], at_stop[1], at_stop[2], parted]
	return [joined, line, stopped, parted]


## The client: waits for the host's biker, rides up behind it at its pace till it's riding with
## us, rides on a while (it should be in front at its place), nods (it nods back), stops (it
## should stop), and waits for it to part with a wave.
func _client_side(trip: AdventureTrip, tr: AdventureTraffic, mine: float, lat: float, note: Array) -> Array:
	var b := tr.bikers
	var s := [mine]
	# The host's: just ahead of us (any others turn up hundreds of metres off).
	var found := [{}]
	var seen := await _until(func():
		_hold(trip, s[0], lat)
		for o in b.bikers:
			if float(o["s"]) - s[0] > 0.0 and float(o["s"]) - s[0] < 60.0:
				found[0] = o
		return not found[0].is_empty(), 70.0)
	if not seen:
		note[0] = "the host's biker never turned up"
		return [false, false, false, false, false]
	var d: Dictionary = found[0]
	s[0] = float(d["s"]) - 20.0
	# Keeping its pace 20 m behind it.
	var joined := await _until(func():
		var v := float(d["v"])
		s[0] += v * get_physics_process_delta_time()
		s[0] += (float(d["s"]) - 20.0 - s[0]) * 0.02
		_ride_at(trip, s[0], lat, v)
		return bool(d.get("joined", false)), 30.0)
	await _until_for(func():
		s[0] += PACE * get_physics_process_delta_time()
		_ride_at(trip, s[0], lat, PACE)
		return true, 6.0)
	var worst := [0.0]
	var line := await _until_for(func():
		s[0] += PACE * get_physics_process_delta_time()
		_ride_at(trip, s[0], lat, PACE)
		var gap: float = float(d["s"]) - float(s[0])
		worst[0] = maxf(worst[0], absf(gap - maxf(AdventureBikers.FORM_GAP, PACE * AdventureBikers.FORM_TIME)))
		return bool(d.get("joined", false)), 6.0)
	line = line and worst[0] < 4.0
	var drawn: Vector3 = b.pool[int(d["id"])]["body"].global_position
	var hit := trip.world.locate_local(drawn)
	var drawn_off := absf(float(hit.get("s", -1000.0)) - float(d["s"]))
	line = line and drawn_off < 1.5
	var nods := AdventureBikers.nod_back(main.bike.global_position)
	var head := [0.0]
	await _until_for(func():
		s[0] += PACE * get_physics_process_delta_time()
		_ride_at(trip, s[0], lat, PACE)
		var p: Dictionary = b.pool[int(d["id"])]
		head[0] = maxf(head[0], maxf(absf((p["head"] as Node3D).rotation.x), absf((p["arm"] as Node3D).rotation.z)))
		return true, 2.5)
	var nodded: bool = nods == 1 and head[0] > 0.3
	# Stop: brake to a stand over a few seconds.
	var v := [PACE]
	var stop_v := [0.0, 0.0]
	var stopped := await _until(func():
		v[0] = maxf(0.0, v[0] - 4.0 * get_physics_process_delta_time())
		s[0] += v[0] * get_physics_process_delta_time()
		_ride_at(trip, s[0], lat, v[0])
		stop_v[0] = float(d["v"])
		stop_v[1] = float(d["s"]) - s[0]
		return v[0] <= 0.0 and float(d["v"]) < 0.3 and bool(d.get("joined", false)) and float(d["s"]) > s[0], 30.0)
	var waved := [false]
	var parted := await _until(func():
		_hold(trip, s[0], lat)
		if int(d.get("gesture", 0)) == AdventureBikers.WAVE:
			waved[0] = true
		return not bool(d.get("joined", false)) and waved[0], 30.0)
	note[0] = "client: joined %s, its place kept to %.1f m (drawn %.2f m from its place), nodded back %s, stopped %s (the biker at %.1f m/s, %.1f m ahead), parted %s" % [
		joined, worst[0], drawn_off, nodded, stopped, stop_v[0], stop_v[1], parted]
	return [joined, line, nodded, stopped, parted]


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


## Calls `cond` every tick for `seconds`; true if it held all the while.
func _until_for(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var ok := true
	while Time.get_ticks_msec() < end:
		if not cond.call():
			ok = false
		await get_tree().physics_frame
	return ok


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


## Our bike put at `s`, going `v` along the road.
func _ride_at(trip: AdventureTrip, s: float, lat: float, v: float) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	var xf := trip.world.transform_at(s, lat)
	main.bike.place(xf.origin, trip.world.heading_at(s))
	main.bike.linear_velocity = xf.basis * Vector3(0.0, 0.0, -v)
