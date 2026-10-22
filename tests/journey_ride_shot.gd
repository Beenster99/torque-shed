extends Node
## A planned journey ridden in the real game, screenshots on the way (what the player sees, with the real trip, bike,
## weather and sky): pins go down, the host starts it, and a picture is taken at the start and further along.
##   xvfb-run -a godot --path . res://tests/journey_ride_shot.tscn -- --out=/tmp/shots [--s=0,3000] [--tour=dales]
## With --tour it rides that region's whole tour (AdventurePlans.TOURS) instead.

var out_dir := "/tmp/shots"
var stops := [0.0, 2000.0, 6000.0]
var main: Node


func _ready() -> void:
	Shed.demo_bikes = true
	AdventureTrip.instant = true
	var tour := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--s="):
			stops = Array(a.trim_prefix("--s=").split(",")).map(func(v): return float(v))
		elif a.begins_with("--tour="):
			tour = a.trim_prefix("--tour=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	SaveGame.slot_override = "shots"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main.menu.new_shed = true
	main._start_session()
	await _frames(20)
	var trip: AdventureTrip = main.trip
	if tour != "":
		Adventure.start(AdventurePlans.tour(tour), 4104)
	else:
		var r := RealRegion.get_region("shodoshima")
		var a := r.geo_to_xz(34.518638, 134.269646)
		var b := r.geo_to_xz(34.499373, 134.347915)
		Shed.request({"a": "adventure_pin", "region": "shodoshima", "x": a.x, "z": a.y})
		Shed.request({"a": "adventure_pin", "region": "shodoshima", "x": b.x, "z": b.y})
		var plan := AdventureJourney.plan_of(Shed.journey)
		Shed.request({"a": "adventure_start", "plan": plan, "seed": 5, "title": "Across the island"})
	var t0 := Time.get_ticks_msec()
	while not (trip.on_trip() and main.bike != null) and Time.get_ticks_msec() - t0 < 120000:
		await _frames(5)
	print("on trip ", trip.on_trip(), " bike ", main.bike != null, " real ", Shed.adventure.get("real", ""), " km ", Shed.adventure.get("km", 0))
	if not trip.on_trip():
		get_tree().quit(1)
		return
	for s: float in stops:
		if s > 0.0:
			trip.jump(s - trip.world.distance_of(main.bike.global_position, "shot"))
		var end := Time.get_ticks_msec() + 120000
		await _frames(30)
		while Time.get_ticks_msec() < end:
			await _frames(5)
			if trip.world.wanted_chunks().all(func(c): return trip.world.chunks.has(c)) and (trip.world.land == null or not trip.world.land.busy()):
				break
		await _frames(30)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("ride_%s_%05d.png" % ["baked" if baked else "plan", int(s)]))
		print("saved at ", s, " land ", trip.world.land.level_counts() if trip.world.land else "none", " bike y ", main.bike.global_position.y)
	SaveGame.delete_slot("shots")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
