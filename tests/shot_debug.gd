extends "res://tests/screenshots.gd"
## Quick screenshots of the newest features only, for checking them without the full set:
##   xvfb-run godot --path . res://tests/shot_debug.tscn -- --out=/tmp/shots


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main._start_session()
	await _frames(20)
	var c := Workshop.CENTER
	var h := Workshop.HALF
	# Two posters on the side wall, flat to it.
	for k in 2:
		Shed._new_furniture("poster", Transform3D(Basis(Vector3.UP, PI * 0.5),
			c + Vector3(-h.x + 0.025, 1.3, -1.5 + k * 1.2)), ["poster_cafe", "poster_mx"][k])
	# A paint booth with two parts hanging in it.
	var booth := Shed._new_furniture("booth", Transform3D(Basis(), c + Vector3(2.5, 0.0, -3.6)), "booth_standard")
	var spots: Array = Shed.furniture_spots(booth)
	var tank := Shed._new_item("teardrop_tank", 0.0, 0.0, 0.0) if PartsDB.parts.has("teardrop_tank") else Shed._new_item(PartsDB.by_kind["tank"][0], 0.0, 0.0, 0.0)
	var guard := Shed._new_item(PartsDB.by_kind["exhaust"][0], 0.0, 0.0, 0.0)
	Shed._move(tank, "spot", spots[1])
	Shed._move(guard, "spot", spots[2])
	Shed.changed.emit()
	await _frames(5)
	await _look_from(c + Vector3(-1.5, 0.0, 1.0), c + Vector3(-h.x, 1.4, -0.9), "r6_1_posters")
	# Half sprayed: the wet paint shows where it's landed.
	var w: Walker = main.walker
	w.set_tool("gun")
	var frame: Dictionary = main.workshop.item_frame(tank)
	var centre: Vector3 = frame["xf"] * (frame["box"] as AABB).get_center()
	await _look_from(Vector3(centre.x, 0.0, centre.z + 1.4), centre, "r6_2_booth")
	var job: Dictionary = w._start_cover(tank, "shot", {"action": {"a": "paint", "item": tank, "color": 3, "finish": "gloss"}})
	if not job.is_empty():
		var pts: PackedVector3Array = job["points"]
		for i in pts.size():
			if pts[i].x < 0.0:
				job["splats"].set_coats(i, 1.0 if pts[i].y > 0.0 else 0.5)
			if i % 17 == 0:
				job["splats"].set_coats(i, 6.0)
	Input.action_press("act")
	await _frames(20)
	await _shot("r6_3_wet_paint_and_mist")
	Input.action_release("act")
	# The stopwatch in hand.
	w.set_tool("watch")
	w.stopwatch.start_stop()
	await _frames(40)
	await _shot("r6_4_stopwatch")
	w.set_tool("hands")
	# The door switches, then the door half up from outside.
	await _look_from(c + Vector3(Workshop.DOOR_HALF + 0.6, 0.0, h.y - 1.2), c + Vector3(Workshop.DOOR_HALF + 0.55, 1.3, h.y), "r6_5_switches")
	Shed.door_open = false
	await _frames(180)
	await _look_from(c + Vector3(1.0, 0.0, h.y + 6.0), c + Vector3(0.0, 1.5, h.y), "r6_6_door_shut")
	Shed.door_open = true
	# A touring bike: horn, ECU, panniers, top box and fog lights.
	var m := BikeModel.new()
	main.add_child(m)
	m.build_from(BikeBuild.new({"horn": "air_horn", "ecu": "race_ecu", "panniers": "aluminium_boxes",
		"top_box": "alloy_top_box", "fog_lights": "rally_lamps"}), Color(0.6, 0.15, 0.1), {}, null, false)
	m.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.25), c + Vector3(-3.0, 0.32, h.y + 5.0))
	await _frames(5)
	await _look_from(c + Vector3(-0.8, 0.0, h.y + 7.0), m.global_position + Vector3.UP * 0.4, "r6_7_touring_bike")
	# A burnout outside.
	var faithful := _bike_named("Old Faithful")
	main._try_mount(faithful)
	await _frames(10)
	main.bike.start_engine()
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	await _frames(30)
	Input.action_press("front_brake", 1.0)
	Input.action_press("throttle", 1.0)
	await _frames(150)
	print("burnout level: ", main.bike.burnout)
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	await _frames(20)
	await _shot("r6_8_burnout")
	Input.action_release("throttle")
	Input.action_release("front_brake")
	# Dusk and night.
	for t in [[18.6, "r6_9_dusk"], [22.5, "r6_10_night"]]:
		Daylight.current.set_time(t[0])
		await _frames(30)
		await _shot(t[1])
	get_tree().quit()
