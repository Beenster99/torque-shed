extends Node
## Two-process co-op check of a ride on the road network (Ride Anywhere v2 T9), run by tests/mp_test.sh: the host
## (its Esc > Debug network toggle on; the client's left off) sets off alone on the Dales with the crew's agreed
## route, rides it a little and heads off to one corner of the map. The client joins the ride in progress: it must be
## on the network too (the host's choice), told its game matches, and put by the host. It then rides to a road in
## another cell of the world, kilometres away: each game must stream the roads round its own rider only, and each must
## see the other at the right map point. The client asks the crew to leave the route and the host says yes: both are
## off it. The host asks to get back on and the client says no: a tie, so both stay off. The host ends the ride.

const REGION := "dales"
const SEED := 4207
## The two map points the riders head for (region frame): the roads nearest them, either side of 2 degrees west, so
## in different cells of the world.
const HOST_AT := Vector2(-3000.0, 0.0)
const CLIENT_AT := Vector2(6000.0, 0.0)

var role := "host"
var main: Node
var trip: AdventureTrip


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Net %s" % role
	AdventureWorld.network = role == "host"   # (the client's own toggle is off: the host's choice is everyone's)
	var plan := AdventurePlans.tour(REGION, 2)
	AdventurePlans.pack_for(plan)   # (planned before connecting: it holds the game for a moment)
	var region := RealRegion.get_region(REGION)
	var spots := [_road_near(region, HOST_AT), _road_near(region, CLIENT_AT)]
	var cells := []
	for p: Vector2 in spots:
		var g := region.xz_to_geo(p.x, p.y)
		cells.append(RealRegion.cell_of(g[0], g[1]))
	print("MP network note %s: the host heads for %s (cell %s), the client for %s (cell %s)" % [role, spots[0], cells[0], spots[1], cells[1]])
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	trip = main.trip
	var ok := false
	if role == "host":
		ok = await _host(plan, spots, cells[0] != cells[1])
	else:
		ok = await _client(spots, cells[0] != cells[1])
	var linger := Time.get_ticks_msec() + (12000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	get_tree().quit(0 if ok else 1)


func _host(plan: Dictionary, spots: Array, apart: bool) -> bool:
	main._host()
	# Off alone along the agreed route.
	var started := await _until(func():
		if not Adventure.active():
			Shed.request({"a": "adventure_start", "plan": plan, "seed": SEED, "title": "Round the Dales"})
		return trip.on_trip() and main.bike != null, 40.0)
	var on_net := started and trip.world.roads != null and Adventure.network()
	var rode := false
	if on_net:
		await _until(func(): return main.bike.global_position.y > -1000.0, 1.0)
		var from: Vector3 = main.bike.global_position
		main.bike.engine_on = true
		main.bike.assist = 1.0
		var t_end := Time.get_ticks_msec() + 3500
		await _until(func():
			main.bike.throttle = 0.45
			return Time.get_ticks_msec() > t_end, 5.0)
		main.bike.throttle = 0.0
		var here: Vector3 = main.bike.global_position
		var xz := trip.world.route_xz(here)
		rode = Vector2(here.x - from.x, here.z - from.z).length() > 8.0 and trip.world.roads.has_ground(xz[0], xz[1])
	print("MP network note host: on the network %s, rode the agreed route from the start %s" % [on_net, rode])
	# To this rider's corner of the map, and held there.
	var mine := Vector2.INF
	if rode:
		await trip._join_by(spots[0])
		mine = _region_of(main.bike.global_position)
	var joined := await _until(func():
		_hold(spots[0])
		return Shed.crew.size() == 2 and Adventure.riders_out().size() == 2, 60.0)
	var lobby := joined and str(Shed.crew.get(_other(), {}).get("builds", "")) == AdventureCrew.builds()
	print("MP network note host: the client joined the ride %s, its game the same version %s" % [joined, lobby])
	# The client off to its own cell: seen there, and none of its roads streamed here.
	var their := _region_of_spot(spots[1])
	var err := [INF]
	var seen := joined and await _until(func():
		_hold(spots[0])
		var at = trip.crew_at.get(_other(), null)
		err[0] = (at as Vector2).distance_to(their) if at is Vector2 else INF
		return err[0] < 0.5, 40.0)
	var own_only := seen and trip.world.roads.has_ground(mine.x, mine.y) and not _blocks_near(their) and trip.focus_points().size() == 1
	var listed := seen and trip.friends().any(func(f): return bool(f["off"]) and float(f["ahead"]) > 5000.0)
	print("MP network note host: the client seen at its map point %s (off by %.3f m), only my own roads streamed %s, on the HUD %s" % [seen, err[0], own_only, listed])
	# The client asks to leave the route; the host says yes.
	var left := seen and await _until(func():
		_hold(spots[0])
		var c := Adventure.route_call()
		if not c.is_empty() and not (c["votes"] as Dictionary).has(Shed.me()):
			trip.route_vote(true)
		return Adventure.route_mode() == "free" and Adventure.route_version() == 1, 40.0)
	# The host asks to get back on; the client says no: a tie, so it stays off.
	var stayed := false
	if left:
		await _wait(1.0)
		trip.route_ask("rejoin")
		var asked := await _until(func(): return not Adventure.route_call().is_empty() or Adventure.route_version() != 1, 5.0)
		stayed = asked and await _until(func():
			_hold(spots[0])
			return Adventure.route_call().is_empty(), 40.0) and Adventure.route_mode() == "free" and Adventure.route_version() == 1
	print("MP network note host: the crew agreed to leave the route %s, a tie kept it off %s" % [left, stayed])
	await _wait(3.0)
	var home := await _until(func():
		if Adventure.active():
			Shed.request({"a": "adventure_end"})
		return not trip.on_trip() and not Adventure.active(), 20.0)
	var ok := started and apart and on_net and rode and joined and lobby and seen and own_only and listed and left and stayed and home
	print("MP network %s host: on the network=%s, rode the route=%s, in different cells=%s, the client joined=%s the same version=%s, seen across the map=%s, own roads only=%s, on the HUD=%s, left the route together=%s, a tie kept it=%s, home=%s" % [
		"PASS" if ok else "FAIL", on_net, rode, apart, joined, lobby, seen, own_only, listed, left, stayed, home])
	return ok


func _client(spots: Array, apart: bool) -> bool:
	# Joins once the host is well under way.
	await _wait(14.0)
	main._join("127.0.0.1")
	var on := await _until(func(): return trip.on_trip() and main.bike != null and Adventure.riders_out().size() == 2, 60.0)
	var host_at = trip.crew_at.get(1, null)
	var by_host := on and host_at is Vector2 and _region_of(main.bike.global_position).distance_to(host_at) < 40.0
	var on_net := on and trip.world.roads != null and Adventure.network() and not AdventureWorld.network \
		and AdventureTrip.real_mismatch(Shed.adventure) == ""
	var lobby := on and str(Shed.crew.get(Shed.me(), {}).get("builds", "")) == AdventureCrew.builds()
	print("MP network note client: on the ride %s, on the network (the host's choice, the same map) %s, told the shed my version %s, put by the host %s (%.1f m off)" % [
		on, on_net, lobby, by_host, _region_of(main.bike.global_position).distance_to(host_at) if by_host or host_at is Vector2 else INF])
	# Off to my own cell, kilometres away.
	var mine := Vector2.INF
	if on:
		await trip._join_by(spots[1])
		mine = _region_of(main.bike.global_position)
	var their := _region_of_spot(spots[0])
	var err := [INF]
	var seen := on and await _until(func():
		_hold(spots[1])
		var rb := _remote_bike()
		err[0] = _region_of(rb.global_position).distance_to(their) if rb != null else INF
		return err[0] < 0.5 and trip.crew_at.has(1) and (trip.crew_at[1] as Vector2).distance_to(their) < 0.5, 40.0)
	# (the blocks round the host, where this rider was put on joining, let go once they're past)
	var own_only := seen and await _until(func():
		_hold(spots[1])
		return trip.world.roads.has_ground(mine.x, mine.y) and not _blocks_near(their) and trip.focus_points().size() == 1, 10.0)
	print("MP network note client: the host seen at its map point %s (off by %.3f m), only my own roads streamed %s" % [seen, err[0], own_only])
	# Hold here a while so the host sees us too, then ask to leave the route.
	await _hold_for(spots[1], 4.0)
	var left := false
	if seen:
		trip.route_ask("leave")
		left = await _until(func():
			_hold(spots[1])
			return Adventure.route_mode() == "free" and Adventure.route_version() == 1, 40.0)
	# The host asks to get back on: no.
	var answered := [false]   # (a lambda gets its own copy of a variable: this one is shared)
	var stayed := left and await _until(func():
		_hold(spots[1])
		var c := Adventure.route_call()
		if not c.is_empty() and str(c["kind"]) == "rejoin":
			if not (c["votes"] as Dictionary).has(Shed.me()):
				trip.route_vote(false)
			answered[0] = true
		return answered[0] and c.is_empty(), 40.0) and Adventure.route_mode() == "free" and Adventure.route_version() == 1
	print("MP network note client: left the route together %s, said no to getting back on and it held %s" % [left, stayed])
	var home := await _until(func(): return not trip.on_trip() and not Adventure.active(), 40.0)
	var ok := apart and on and on_net and lobby and by_host and seen and own_only and left and stayed and home
	print("MP network %s client: in different cells=%s, joined in progress=%s, on the network=%s, the same version=%s, put by the host=%s, seen across the map=%s, own roads only=%s, left the route together=%s, a tie kept it=%s, home=%s" % [
		"PASS" if ok else "FAIL", apart, on, on_net, lobby, by_host, seen, own_only, left, stayed, home])
	return ok


## The point on the road nearest `want` at a node with two roads or more (region frame): the same on both machines.
func _road_near(region: RealRegion, want: Vector2) -> Vector2:
	var best := -1
	for n in region.node_count():
		if region.adjacent[n].size() >= 2 and (best < 0 or region.node_pos[n].distance_squared_to(want) < region.node_pos[best].distance_squared_to(want)):
			best = n
	return region.node_pos[best]


## Where a rider joining by `at` is put (region frame x, z): what each machine works out alike.
func _region_of_spot(at: Vector2) -> Vector2:
	var xf := trip.join_xf(at)
	return _region_of(xf.origin)


func _region_of(local: Vector3) -> Vector2:
	var xz := trip.world.route_xz(local)
	return Vector2(xz[0], xz[1])


## Whether this game has any road block within 1.5 km of `at` (region frame).
func _blocks_near(at: Vector2) -> bool:
	for k: Vector2i in trip.world.roads.blocks:
		if ((Vector2(k) + Vector2(0.5, 0.5)) * RoadBlock.SIZE).distance_to(at) < 1500.0:
			return true
	return false


func _other() -> int:
	for p in Shed.crew:
		if int(p) != Shed.me():
			return int(p)
	return 0


## Keeps this rider where they were put by `at` (a bike rolls).
func _hold(at: Vector2) -> void:
	if not trip.on_trip() or main.bike == null:
		return
	var xf := trip.join_xf(at)
	if main.bike.global_position.distance_to(xf.origin) > 0.05 or main.bike.is_crashed:
		trip._put(xf)


func _hold_for(at: Vector2, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	await _until(func():
		_hold(at)
		return Time.get_ticks_msec() > end, seconds + 1.0)


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	await _until(func(): return Time.get_ticks_msec() > end, seconds + 1.0)


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
