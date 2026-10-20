extends Node
## Two-process co-op check of the Adventure Diary, run by tests/mp_test.sh: a host and a client
## start the real game and the host starts a short adventure for both. The client pulls in at a
## stop and stands there (its own highlight), the host's game notes a sunset (the host's), and
## each takes a photo of their own. Both must see the same highlights from the host, with the
## right who; both ride to the destination, and each machine's diary must hold those shared
## highlights and only its own photos, kept on its own machine.

const KM := 8.0

var role := "host"
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.trim_prefix("--role=")
	Settings.player_name = "Diary %s" % role
	AdventureDest.album_path = "user://zz_mp_diary_album_%s.json" % role
	DirAccess.remove_absolute(AdventureDest.album_path)
	AdventureDiary.root = "user://zz_mp_diaries_%s" % role
	_wipe(AdventureDiary.root)
	# Headless there's no screen to photograph: each machine's photos are a colour of its own.
	var frame := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	frame.fill(Color(0.9, 0.3, 0.2) if role == "host" else Color(0.2, 0.4, 0.9))
	PhotoCapture.fake_source = func(): return frame
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
			Adventure.start(4102, KM, "hills")
		return trip.on_trip() and main.bike != null and _remote_bike() != null, 40.0)
	var me := str(Shed.crew.get(Shed.me(), {}).get("name", Settings.player_name))
	print("MP diary note %s: on the adventure %s, diary %s" % [role, ok_start, str(Shed.adventure.get("diary", ""))])
	# The client stops at a stop; the host notes a sunset; each takes a photo.
	var stop_key := ""
	var stop_ok := false
	if ok_start:
		var r := trip.world.route
		var site := {}
		for st in r.sites:
			if AdventureStops.NAV.has(str(st["kind"])) and float(st["s"]) > 400.0 and float(st["s"]) < r.length - 600.0:
				site = st
				break
		stop_key = "stop_%d" % int(float(site.get("s", 0.0)))
		if role == "client" and not site.is_empty():
			trip.jump(float(site["s"]) - trip.world.distance_of(main.bike.global_position, "own"))
		if role == "host":
			await _until(func(): return false, 2.0)
			Shed.request({"a": "adventure_highlight", "kind": "sunset", "key": "sunset_test", "s": 100.0})
		trip.photos.snap("photo", "")
		stop_ok = await _until(func():
			if role == "client" and main.bike:
				main.bike.linear_velocity = Vector3.ZERO
			var e := AdventureDiary.find(stop_key)
			return not site.is_empty() and not e.is_empty() and (e["who"] as Array) == ["Diary client"] \
				and not AdventureDiary.find("sunset_test").is_empty(), 25.0)
	var keys := AdventureDiary.log_entries().map(func(e): return "%d:%s:%s" % [int(e["n"]), str(e["kind"]), ",".join(e["who"])])
	print("MP diary note %s: highlights %s" % [role, str(keys)])
	# Both to the destination.
	var arrived := false
	if stop_ok:
		if role == "client":
			trip.jump(trip.world.route.length - trip.world.distance_of(main.bike.global_position, "own") - 4.0)
		arrived = await _until(func():
			if role == "client" and main.bike and int(Shed.adventure.get("arrived", 0)) == 0:
				main.bike.throttle = 0.3
			return int(Shed.adventure.get("arrived", 0)) != 0 and trip.moment_done and trip.moment_t < 0.0, 30.0)
	# Each machine's diary: the same shared highlights, and only its own photos.
	var d := AdventureDiary.load_diary(trip.photos.diary_id)
	var log_ok := false
	var photos_ok := false
	if arrived and not d.is_empty():
		var kinds := (d["log"] as Array).map(func(e): return str(e["kind"]))
		log_ok = kinds.has("start") and kinds.has("stop") and kinds.has("sunset") and kinds.has("arrive") \
			and (d["log"] as Array).size() == AdventureDiary.log_entries().size()
		var mine := (d["photos"] as Array).filter(func(p): return str(p.get("by", "")) == me)
		photos_ok = not (d["photos"] as Array).is_empty() and mine.size() == (d["photos"] as Array).size() \
			and (d["photos"] as Array).any(func(p): return str(p["kind"]) == "photo") \
			and (d["photos"] as Array).all(func(p): return FileAccess.file_exists(AdventureDiary.folder(str(d["id"])).path_join(str(p["file"]))))
		# The colour of this machine's own photos in its files.
		var first := Image.load_from_file(AdventureDiary.folder(str(d["id"])).path_join(str(d["photos"][0]["file"]))) if photos_ok else null
		if first:
			var c := first.get_pixel(first.get_width() / 2, first.get_height() / 2)
			photos_ok = photos_ok and ((c.r > c.b) if role == "host" else (c.b > c.r))
		print("MP diary note %s: diary %s, log %s, %d photos all mine %s" % [role, str(d["id"]), str(kinds), (d["photos"] as Array).size(), photos_ok])
	# Home.
	var asked := [false]
	var end_at := Time.get_ticks_msec() + 3000
	var home_ok := await _until(func():
		if role == "host" and Adventure.active() and not asked[0] and Time.get_ticks_msec() > end_at:
			asked[0] = true
			Adventure.menu_action()
		return not trip.on_trip() and not Adventure.active(), 25.0)
	var kept := AdventureDiary.load_diary(trip.photos.diary_id)
	var kept_ok := not kept.is_empty() and bool(kept["done"]) and trip.diary_open()
	var ok := ok_start and stop_ok and arrived and log_ok and photos_ok and home_ok and kept_ok
	var linger := Time.get_ticks_msec() + (15000 if role == "client" else 3000)
	while Time.get_ticks_msec() < linger:
		await get_tree().physics_frame
		if role == "client" and not main.in_session:
			break
	DirAccess.remove_absolute(AdventureDest.album_path)
	_wipe(AdventureDiary.root)
	PhotoCapture.fake_source = Callable()   # (a lambda of this script's, not left behind it)
	print("MP diary %s %s: on it=%s, the client's stop and the host's sunset in both logs=%s, arrived=%s, the diary's highlights the shared ones=%s, its photos only this machine's=%s, home with the diary kept and open=%s" % [
		"PASS" if ok else "FAIL", role, ok_start, stop_ok, arrived, log_ok, photos_ok, home_ok and kept_ok])
	get_tree().quit(0 if ok else 1)


static func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)


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
