extends Node
## Two-process co-op check of an adventure's destination, run by tests/mp_test.sh: a host and a
## client start the real game; the host starts an adventure for both (a short one, so it loads quickly). The client rides to the finish: both
## must be brought to the destination together (each parked past the finish, seeing the other
## there), both get XP, the photo must hang on the shed wall on both games and be in each
## player's own album. Then the host rides everyone home.

const Rides := preload("res://tests/rides.gd")

const KM := 8.0

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Dest %s" % role
	AdventureDest.album_path = "user://zz_mp_album_%s.json" % role
	DirAccess.remove_absolute(AdventureDest.album_path)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if role == "host":
		main._host()
	else:
		main._join("127.0.0.1")
	var trip: AdventureTrip = main.trip
	var xp0 := [-1]
	# The host starts the adventure for both.
	var started := [false]
	var ok_start := await _until(func():
		if role == "host" and Shed.crew.size() == 2 and not Adventure.active() and not trip.on_trip() and not started[0]:
			started[0] = true
			Rides.start(KM, 4101)
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 40.0)
	var adv := Shed.adventure.duplicate(true)
	xp0[0] = int(Progress.profile.get("xp", 0))   # your own character by now, whoever's shed it is
	ok_start = ok_start and str(adv.get("dest", "")) == str(Rides.plan(KM)["names"][-1]) and absf(float(adv.get("km", 0.0)) - Rides.full(KM)) < 0.1
	print("MP dest note %s: on the adventure %s %s" % [role, ok_start, str(adv)])
	# The client rides to the finish; both end up at the destination.
	var arrived_ok := false
	var both_there := false
	if ok_start:
		var wait_until := Time.get_ticks_msec() + 3000
		await _until(func(): return Time.get_ticks_msec() > wait_until, 4.0)
		if role == "client":
			trip.jump(trip.world.route.length - trip.world.distance_of(main.bike.global_position, "own") - 4.0)
		arrived_ok = await _until(func():
			if role == "client" and main.bike and int(Shed.adventure.get("arrived", 0)) == 0:
				main.bike.throttle = 0.3
			return int(Shed.adventure.get("arrived", 0)) != 0 and trip.moment_done, 20.0)
		var ds := AdventureDest.dest_s(trip.world) if trip.world else 0.0
		both_there = await _until(func():
			if trip.world == null or main.bike == null or _remote_bike() == null:
				return false
			var mine := trip.world.distance_of(main.bike.global_position, "check_me")
			var theirs := trip.world.distance_of(_remote_bike().global_position, "check_them")
			return absf(mine - ds) < 25.0 and absf(theirs - ds) < 25.0, 15.0)
		print("MP dest note %s: arrived %s (by peer %d), both at the destination %s, me %.0f m along, them %.0f, it's at %.0f" % [role, arrived_ok,
			int(Shed.adventure.get("arrived", 0)), both_there,
			trip.world.distance_of(main.bike.global_position, "check_me") if trip.world and main.bike else -1.0,
			trip.world.distance_of(_remote_bike().global_position, "check_them") if trip.world and _remote_bike() else -1.0, ds])
	# The photo: on the shed wall on both games, and in each player's own album; XP for both.
	var photo_ok := false
	var key := [""]
	if arrived_ok:
		photo_ok = await _until(func():
			var p: Dictionary = Shed.adventure.get("photo", {})
			key[0] = str(p.get("key", ""))
			var hung := AdventureDest.photo_on_wall(key[0])
			var mine := AdventureDest.album_of(Settings.player_name).filter(func(x): return str(x["key"]) == key[0])
			return key[0] != "" and not hung.is_empty() and (p["names"] as Array).size() == 2 and mine.size() == 1, 15.0)
	var xp_ok := await _until(func(): return int(Progress.profile.get("xp", 0)) - xp0[0] >= 10, 10.0)
	print("MP dest note %s: photo %s on the wall %s and in my album %d, XP %d -> %d" % [role, key[0],
		not AdventureDest.photo_on_wall(key[0]).is_empty(), AdventureDest.album_of(Settings.player_name).size(), xp0[0], int(Progress.profile.get("xp", 0))])
	# Nothing ends by itself: the host rides everyone home.
	var stays := Adventure.active() and trip.on_trip()
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 4000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Adventure.menu_action()
		return not trip.on_trip() and main.bike == null and not Adventure.active(), 25.0)
	var still_hung := not AdventureDest.photo_on_wall(key[0]).is_empty()
	var ok := ok_start and arrived_ok and both_there and photo_ok and xp_ok and stays and home_ok and still_hung
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	DirAccess.remove_absolute(AdventureDest.album_path)
	print("MP dest %s %s: host started it=%s, arrived=%s, both brought to the destination=%s, photo on the wall and in the album=%s, XP=%s, stays till Ride home=%s, home with the photo still up=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, arrived_ok, both_there, photo_ok, xp_ok, stays, home_ok and still_hung])
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
