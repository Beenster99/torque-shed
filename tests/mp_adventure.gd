extends Node
## Two-process co-op check of an adventure ride, run by tests/mp_test.sh after the shed's own: a
## host and a client start the real game, the host starts an adventure, and both must load it
## and be on a bike at the start, seeing each other there. Then each skips 30 km and more down
## the road (the host to 30 km, the client 700 m further on), which moves both worlds' floating
## origins, to different places: each must still see the other at the right spot on the road,
## to within a few centimetres, and again after the client rides its origin on once more. Out
## there both must see the same traffic (AdventureTraffic: the same vehicles at the same places
## along the road, each drawn where it should be in its own frame).
## Finally the host ends the adventure and both must be back at the shed, off their bikes.

const SEED := 321
const KM := 50.0
const HOST_S := 30000.0
const CLIENT_S := 30700.0
const CLIENT_ON := 900.0

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Adv %s" % role
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
			Adventure.start(SEED, KM)
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 40.0)
	var start_seen := false
	if ok_start:
		start_seen = await _until(func():
			var s := trip.world.distance_of(_remote_bike().global_position, "check")
			return s >= 0.0 and s < 60.0, 10.0)
		if not start_seen:
			print("MP adv note %s: the other's bike is at %s, %.1f m along; mine at %s" % [role, _remote_bike().global_position,
				trip.world.distance_of(_remote_bike().global_position, "check"), main.bike.global_position])
	print("MP adv note %s: on the adventure %s, the other's bike seen at the start %s" % [role, ok_start, start_seen])
	# Out past 30 km: both origins move, each to its own place.
	var mine := HOST_S if role == "host" else CLIENT_S
	var theirs := CLIENT_S if role == "host" else HOST_S
	var my_lat := -1.5 if role == "host" else 1.0
	var their_lat := 1.0 if role == "host" else -1.5
	var far_ok := false
	var traffic_ok := false
	var again_ok := false
	var err := [Vector2(INF, INF)]
	if start_seen:
		# Give the other side time to see us at the start too before setting off.
		var wait_until := Time.get_ticks_msec() + 4000
		await _until(func(): return Time.get_ticks_msec() > wait_until, 5.0)
	# The first fork (22 km in): the client votes B, everyone sees it, the host picks C, and both
	# roads are built along C (the 30 km spots below are on C and just past it).
	var fork_ok := false
	if start_seen and trip.on_trip():
		var other := 0
		for peer in Shed.crew:
			if int(peer) != Shed.me():
				other = int(peer)
		if role == "client":
			Shed.request({"a": "adventure_vote", "fork": 0, "way": 1})
		var seen_vote := await _until(func():
			if role == "host" and int(AdventureForks.votes_of(0).get(other, -1)) == 1 and AdventureForks.pick_of(0) < 0:
				Shed.request({"a": "adventure_vote", "fork": 0, "way": 2})
			return int(AdventureForks.votes_of(0).get(1 if role == "client" else other, -1)) >= 1, 15.0)
		var built := await _until(func(): return trip.world != null and trip.world.route.decided.has(0) and int(trip.world.route.choices[0]) == 2, 15.0)
		var votes := AdventureForks.votes_of(0)
		fork_ok = seen_vote and built and int(votes.get(other if role == "host" else Shed.me(), -1)) == 1 and int(votes.get(1, -1)) == 2
		print("MP adv note %s: votes at the fork %s, pick %d, my road along way %d" % [role, str(votes), AdventureForks.pick_of(0),
			int(trip.world.route.choices.get(0, -1)) if trip.world else -1])
	if start_seen and trip.on_trip():
		_jump_to(trip, mine, my_lat)
		far_ok = await _until(func():
			_hold(trip, mine, my_lat)
			err[0] = _seen_error(trip, theirs, their_lat)
			return err[0].x < 0.1 and err[0].y < 0.1, 20.0)
		print("MP adv note %s: at %.0f m, origin %s; the other seen off by %.3f m along, %.3f m across" % [role, mine, trip.world.origin if trip.world else Vector3.ZERO, err[0].x, err[0].y])
		traffic_ok = await _traffic_check(trip, mine, my_lat)
		if role == "client":
			# On again past another shift: the host, standing still, must stay put on the road.
			# Stay put a while first, so the host has seen us here too (the fork ends at
			# different moments on each side).
			var stay_until := Time.get_ticks_msec() + 6000
			await _until(func():
				_hold(trip, mine, my_lat)
				return Time.get_ticks_msec() > stay_until, 7.0)
			var before: Vector3 = trip.world.origin if trip.world else Vector3.ZERO
			mine += CLIENT_ON
			_jump_to(trip, mine, my_lat)
			await _until(func(): return trip.world != null and trip.world.origin != before, 5.0)
		var expect := (CLIENT_S + CLIENT_ON) if role == "host" else HOST_S
		again_ok = await _until(func():
			_hold(trip, mine, my_lat)
			err[0] = _seen_error(trip, expect, their_lat)
			return err[0].x < 0.1 and err[0].y < 0.1, 20.0)
		print("MP adv note %s: after the client rode on, origin %s; the other seen off by %.3f m along, %.3f m across" % [role, trip.world.origin if trip.world else Vector3.ZERO, err[0].x, err[0].y])
	# Home: the host ends it (once the client has had time to check, too).
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and Shed.riding(Shed.me()) == 0 and not Adventure.active(), 25.0)
	var ok := ok_start and start_seen and fork_ok and far_ok and traffic_ok and again_ok and home_ok
	# The client stays until the host has gone, so the host's checks finish first.
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP adv %s %s: both on the adventure=%s, seen at the start=%s, voted at the fork and both took the host's pick=%s, seen 30 km out after the origins moved=%s, both see the same traffic there=%s, and after another shift=%s, back at the shed=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, start_seen, fork_ok, far_ok, traffic_ok, again_ok, home_ok])
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------------------- the traffic

## The host's traffic as it has it (sent to the client by this test's own call, not the game's):
## [seed, s, kind, v] for each vehicle; and the client's verdict, sent back.
var _host_view := PackedFloat32Array()
var _host_view_new := false
var _verdict := -1
var _traffic_note := ""


## Both see the same vehicles on the road 30 km out (the host's and the client's origins in
## different places): the host sends what it has, the client compares its own (same vehicles,
## same kinds, the same distance along the road, and each drawn in its own frame where its
## distance says), and says whether they match.
func _traffic_check(trip: AdventureTrip, s: float, lat: float) -> bool:
	var end := Time.get_ticks_msec() + 25000
	var send_t := 0
	while Time.get_ticks_msec() < end and _verdict < 0:
		_hold(trip, s, lat)
		var tr := AdventureTraffic.current
		if tr == null:
			await get_tree().physics_frame
			continue
		if role == "host":
			if Time.get_ticks_msec() > send_t:
				send_t = Time.get_ticks_msec() + 500
				var view := PackedFloat32Array()
				for d in tr.stream.vehicles:
					view.append_array([float(d["seed"]), float(d["s"]), float(VehicleModel.KINDS.find(d["kind"])), float(d["v"])])
				if view.size() >= 12:   # three or more out
					_host_view_from.rpc(view)
		elif _host_view_new:
			_host_view_new = false
			var ok := _compare(tr, trip)
			if ok:
				_verdict = 1
				_verdict_from.rpc(1, _traffic_note)
		await get_tree().physics_frame
	print("MP adv note %s: traffic %s (%s)" % [role, "matches" if _verdict == 1 else "doesn't match", _traffic_note])
	# Stood afresh where we were (a bike left standing creeps a few centimetres in that time,
	# and the checks after this one look to within 10 cm).
	if trip.on_trip() and main.bike != null:
		var xf := trip.world.transform_at(s, lat)
		main.bike.place(xf.origin, trip.world.heading_at(s))
	return _verdict == 1


func _compare(tr: AdventureTraffic, trip: AdventureTrip) -> bool:
	var mine := {}
	for d in tr.stream.vehicles:
		mine[int(d["seed"])] = d
	var count := _host_view.size() / 4
	var worst := 0.0
	var worst_drawn := 0.0
	for k in count:
		var b := k * 4
		var d: Dictionary = mine.get(int(_host_view[b]), {})
		if d.is_empty() or VehicleModel.KINDS.find(d["kind"]) != int(_host_view[b + 2]):
			_traffic_note = "the host's %d vehicles, mine %d: one of its isn't here" % [count, mine.size()]
			return false
		var off := absf(float(d["s"]) - _host_view[b + 1])
		if off > 0.6 * absf(_host_view[b + 3]) + 4.0:
			_traffic_note = "vehicle %d %.1f m off along the road" % [int(_host_view[b]), off]
			return false
		worst = maxf(worst, off)
		var hit := trip.world.locate_local((d["body"] as Node3D).global_position)
		var drawn := absf(float(hit.get("s", -1000.0)) - float(d["s"]))
		worst_drawn = maxf(worst_drawn, drawn)
		if drawn > 1.0:
			_traffic_note = "vehicle %d drawn %.1f m from where its distance says" % [int(_host_view[b]), drawn]
			return false
	if mine.size() != count:
		_traffic_note = "the host has %d vehicles and I have %d" % [count, mine.size()]
		return false
	_traffic_note = "%d vehicles, the same kinds, within %.1f m along the road of the host's, each drawn within %.2f m of its place" % [count, worst, worst_drawn]
	return true


@rpc("any_peer", "call_remote", "reliable")
func _host_view_from(view: PackedFloat32Array) -> void:
	_host_view = view
	_host_view_new = true


@rpc("any_peer", "call_remote", "reliable")
func _verdict_from(v: int, note: String) -> void:
	_verdict = v
	_traffic_note = note


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


## Keeps our bike stood at `s`, `lat`: put back if it creeps (a few mm a second on a slope adds up
## past the 10 cm checks) or falls over.
func _hold(trip: AdventureTrip, s: float, lat: float) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	var xf := trip.world.transform_at(s, lat)
	if main.bike.global_position.distance_to(xf.origin) > 0.05 or main.bike.is_crashed:
		main.bike.place(xf.origin, trip.world.heading_at(s))


## How far off (along, across) the other player's bike is from where they stand.
func _seen_error(trip: AdventureTrip, s: float, lat: float) -> Vector2:
	var rb := _remote_bike()
	if rb == null or not trip.on_trip():
		return Vector2(INF, INF)
	var hit := trip.world.locate_local(rb.global_position, "check")
	if hit.is_empty():
		return Vector2(INF, INF)
	return Vector2(absf(float(hit["s"]) - s), absf(float(hit["lat"]) - lat))
