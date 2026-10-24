extends Node
## Two-process co-op check of an adventure ride, run by tests/mp_test.sh after the shed's own: a
## host and a client start the real game, the host starts an adventure, and both must load it
## and be on a bike at the start, seeing each other there. At the first fork the client votes for the other way and the
## host picks the main road, and both build it. Then each skips 20 km and more down the road, past the fork (the host to
## 20 km, the client 700 m further on), which moves both worlds' floating
## origins, to different places: each must still see the other at the right spot on the road,
## to within a few centimetres, and again after the client rides its origin on once more. Out
## there both must see the same traffic (AdventureTraffic: the same vehicles at the same places
## along the road, each drawn where it should be in its own frame). Each must say how far along
## the road the other is (the host "4.0 km ahead", the client "4.0 km behind"), and with both
## menus up (the game doesn't pause in co-op) neither bike may move, on either screen. Then the
## client respawns: the host must see its bike drawn as a ghost, and solid again about 5 s on.
## Finally the host ends the adventure and both must be back at the shed, off their bikes.

const Rides := preload("res://tests/rides.gd")

const SEED := 321
## Shodoshima's tour as far as Obe (42.6 km): its first fork is 8.8 to 12 km in, its second not till 29.8 km.
const KM := 40.0
const HOST_S := 20000.0
const CLIENT_S := 20700.0
const CLIENT_ON := 3300.0   # (to 24 km: 1.3 km off as the crow flies, so its origin moves)

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Adv %s" % role
	# Planned before connecting: planning a long ride holds the game for seconds, longer than the link waits.
	Rides.pack(KM)
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
			Rides.start(KM, SEED)
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
	# Out past 20 km: both origins move, each to its own place.
	var mine := HOST_S if role == "host" else CLIENT_S
	var theirs := CLIENT_S if role == "host" else HOST_S
	var my_lat := -1.5 if role == "host" else 1.0
	var their_lat := 1.0 if role == "host" else -1.5
	var far_ok := false
	var traffic_ok := false
	var again_ok := false
	var friends_ok := false
	var menu_ok := false
	var ghost_ok := false
	var err := [Vector2(INF, INF)]
	if start_seen:
		# Give the other side time to see us at the start too before setting off.
		var wait_until := Time.get_ticks_msec() + 4000
		await _until(func(): return Time.get_ticks_msec() > wait_until, 5.0)
	# The first fork: the client votes for the other way, everyone sees it, the host picks the main road, and both
	# roads are built along it (the 20 km spots below are past it).
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
				Shed.request({"a": "adventure_vote", "fork": 0, "way": 0})
			var v := AdventureForks.votes_of(0)
			return int(v.get(other if role == "host" else Shed.me(), -1)) == 1 and int(v.get(1, -1)) == 0, 15.0)
		var built := await _until(func(): return trip.world != null and trip.world.route.decided.has(0) and int(trip.world.route.choices[0]) == 0, 15.0)
		var votes := AdventureForks.votes_of(0)
		fork_ok = seen_vote and built and AdventureForks.pick_of(0) == 0
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
		if again_ok:
			friends_ok = await _friends_check(trip, mine, expect, my_lat)
			menu_ok = await _menu_check(trip, mine, my_lat)
			ghost_ok = await _ghost_check(trip, mine, my_lat)
	# Home: the host ends it (once the client has had time to check, too).
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and main.bike == null and Shed.riding(Shed.me()) == 0 and not Adventure.active(), 25.0)
	var ok := ok_start and start_seen and fork_ok and far_ok and traffic_ok and again_ok and friends_ok and menu_ok and ghost_ok and home_ok
	# The client stays until the host has gone, so the host's checks finish first.
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	print("MP adv %s %s: both on the adventure=%s, seen at the start=%s, voted at the fork and both took the host's pick=%s, seen 20 km out after the origins moved=%s, both see the same traffic there=%s, and after another shift=%s, how far ahead or behind the other is along the road=%s, held still with the menu up=%s, the client's respawn seen as a ghost then solid=%s, back at the shed=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, start_seen, fork_ok, far_ok, traffic_ok, again_ok, friends_ok, menu_ok, ghost_ok, home_ok])
	get_tree().quit(0 if ok else 1)


# ---------------------------------------------------------------------------- the crew, the menu

## How far the other is along the road (AdventureTrip.friends): the client 4 km on from the
## host, so the host's HUD, sat nav and paper map say "Adv client 4.0 km ahead", the client's
## "Adv host 4.0 km behind".
func _friends_check(trip: AdventureTrip, mine: float, theirs: float, lat: float) -> bool:
	var want := "%s %.1f km %s" % ["Adv client" if role == "host" else "Adv host", absf(theirs - mine) / 1000.0, "ahead" if theirs > mine else "behind"]
	var note := [""]
	var ok := await _until(func():
		_hold(trip, mine, lat)
		var f := trip.friends()
		if f.size() != 1:
			note[0] = "%d friends" % f.size()
			return false
		var view := Satnav.view_for(Satnav.AdventureNav.new(trip.world), main.bike.global_position, -main.bike.global_transform.basis.z)
		var on_nav: Array = view.get("friends", [])
		note[0] = "%.1f m along (want %.1f); HUD '%s'" % [float(f[0]["ahead"]), theirs - mine, trip.crew_text()]
		return absf(float(f[0]["ahead"]) - (theirs - mine)) < 3.0 and trip.crew_text() == want and on_nav.size() == 1 \
			and AdventureTrip.friend_text(str(on_nav[0]["name"]), float(on_nav[0]["ahead"])) == want, 10.0)
	print("MP adv note %s: the other along the road: %s (%s)" % [role, note[0], "ok" if ok else "want '%s'" % want])
	return ok


## The menu up, out on the road: the game doesn't pause in co-op, and the bike mustn't roll. Both
## open it at once and stand there with it up: neither bike moves, on either screen.
func _menu_check(trip: AdventureTrip, s: float, lat: float) -> bool:
	if not trip.on_trip() or main.bike == null:
		return false
	# Let the bikes settle first, and both get here (the client's on later from its own checks), still held where we
	# stand: left to itself a bike can roll back down a hill, and the other is still looking for it there.
	var settle := Time.get_ticks_msec() + 3000
	await _until(func():
		_hold(trip, s, lat)
		return Time.get_ticks_msec() > settle, 4.0)
	main.menu.show()
	await _until(func(): return main.bike != null and main.bike.freeze, 3.0)
	var mine: Vector3 = main.bike.global_position
	# The other opens theirs when they get here: wait till they say their bike's held, and a moment more for it to
	# come over the network.
	_menu_up_from.rpc()
	await _until(func(): return _other_menu_up, 20.0)
	var seen_at := Time.get_ticks_msec() + 1000
	await _until(func(): return Time.get_ticks_msec() > seen_at, 2.0)
	var rb := _remote_bike()
	var theirs: Vector3 = rb.global_position if rb else Vector3.INF
	var until := Time.get_ticks_msec() + 4000
	await _until(func(): return Time.get_ticks_msec() > until, 5.0)
	var moved: float = main.bike.global_position.distance_to(mine) if main.bike else INF
	rb = _remote_bike()
	var seen: float = rb.global_position.distance_to(theirs) if rb and theirs != Vector3.INF else INF
	# The menu stays up till the other has looked too (put down, a bike on a hill rolls back, and they'd see it go).
	_menu_done_from.rpc()
	await _until(func(): return _other_menu_done, 20.0)
	main.menu.hide()
	print("MP adv note %s: 4 s with the menu up, my bike moved %.3f m, the other's %.3f m" % [role, moved, seen])
	return moved < 0.02 and seen < 0.05


# ---------------------------------------------------------------------------- the respawn ghost

var _other_ghost := false
var _ghost_verdict := -1
var _ghost_note := ""


## The client respawns (see BikeGhost): its own bike is a ghost for 5 s of game time, and the host
## sees its bike drawn see-through, its own bike passing through it, and solid again once the
## client's is. The host says what it saw. (Run with --fixed-fps, each side's game time runs as
## fast as its machine can step it, not with the clock: the 5 s is checked in the client's own
## physics ticks, and the host only checks it was a ghost for a good while, then solid.)
func _ghost_check(trip: AdventureTrip, s: float, lat: float) -> bool:
	if not trip.on_trip() or main.bike == null:
		return false
	if role == "client":
		var settle := Time.get_ticks_msec() + 1500
		await _until(func():
			_hold(trip, s, lat)
			return Time.get_ticks_msec() > settle, 3.0)
		main.bike.respawn()
		var t0 := Time.get_ticks_msec()
		var f0 := Engine.get_physics_frames()
		_ghost_from.rpc()
		var mine_ok: bool = main.bike.is_ghost() and BikeGhost.drawn(main.bike.model) > 0.3
		await _until(func():
			_hold(trip, s, lat)
			return main.bike == null or not main.bike.is_ghost(), 8.0)
		var lasted := (Engine.get_physics_frames() - f0) / float(Engine.physics_ticks_per_second)
		var wall := (Time.get_ticks_msec() - t0) / 1000.0
		mine_ok = mine_ok and main.bike != null and BikeGhost.drawn(main.bike.model) == 0.0 and absf(lasted - BikeGhost.TIME) < 0.1
		await _until(func():
			_hold(trip, s, lat)
			return _ghost_verdict >= 0, 15.0)
		print("MP adv note %s: my respawn a ghost for %.2f s of game time (%.1f s on the clock) %s; the host saw it: %s" % [role, lasted, wall, mine_ok, _ghost_note])
		return mine_ok and _ghost_verdict == 1
	await _until(func():
		_hold(trip, s, lat)
		return _other_ghost, 25.0)
	var rb := _remote_bike() as RemoteBike
	var seen := await _until(func():
		_hold(trip, s, lat)
		rb = _remote_bike() as RemoteBike
		return rb != null and rb.is_ghost() and BikeGhost.drawn(rb.model) > 0.3, 3.0)
	# (how long in this game's own time: a fast machine gets through the client's 5 s of game time in about a second)
	var f0 := Engine.get_physics_frames()
	var passes: bool = seen and main.bike != null and main.bike.passes(rb)
	var solid := await _until(func():
		_hold(trip, s, lat)
		rb = _remote_bike() as RemoteBike
		return rb != null and not rb.is_ghost() and BikeGhost.drawn(rb.model) == 0.0, 8.0)
	var lasted := (Engine.get_physics_frames() - f0) / float(Engine.physics_ticks_per_second)
	var ok := seen and passes and solid and lasted > 1.0
	_ghost_note = "seen ghosted %s (my bike passing through it %s), solid again %.1f s of game time later %s" % [seen, passes, lasted, solid]
	print("MP adv note %s: the client's respawn %s" % [role, _ghost_note])
	_ghost_verdict_from.rpc(1 if ok else 0, _ghost_note)
	return ok


@rpc("any_peer", "call_remote", "reliable")
func _ghost_from() -> void:
	_other_ghost = true


@rpc("any_peer", "call_remote", "reliable")
func _ghost_verdict_from(v: int, note: String) -> void:
	_ghost_verdict = v
	_ghost_note = note


# ---------------------------------------------------------------------------- the traffic

## The host's traffic as it has it (sent to the client by this test's own call, not the game's):
## [seed, s, kind, v] for each vehicle; and the client's verdict, sent back.
var _host_view := PackedFloat32Array()
var _host_view_new := false
var _verdict := -1
var _traffic_note := ""


## Both see the same vehicles on the road 20 km out (the host's and the client's origins in
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
				_traffic_note = "the host has %d vehicles out" % tr.stream.vehicles.size()
				var view := PackedFloat32Array()
				for d in tr.stream.vehicles:
					view.append_array([float(d["seed"]), float(d["s"]), float(VehicleModel.KINDS.find(d["kind"])), float(d["v"])])
				if view.size() >= 8:   # two or more out (a quiet country road)
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


var _other_menu_up := false
var _other_menu_done := false


@rpc("any_peer", "call_remote", "reliable")
func _menu_up_from() -> void:
	_other_menu_up = true


@rpc("any_peer", "call_remote", "reliable")
func _menu_done_from() -> void:
	_other_menu_done = true


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
