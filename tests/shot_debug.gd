extends "res://tests/screenshots.gd"
## Quick screenshots of the newest features only, for checking them without the full set:
##   xvfb-run godot --path . res://tests/shot_debug.tscn -- --out=/tmp/shots


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveGame.slot_override = "shots"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	main.menu.new_shed = true
	main._start_session()
	await _frames(20)
	var r := Workshop.BOOTH_ROOM_CENTER
	var h := Workshop.BOOTH_ROOM_HALF
	# The paint shop from the yard, then inside with two parts hung in the booth.
	await _look_from(r + Vector3(-1.0, 0.0, h.y + 6.0), r + Vector3(0.0, 1.4, 0.0), "r7_1_paint_shop_outside")
	var booth := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "booth":
			booth = id
	var spots: Array = Shed.furniture_spots(booth)
	var tank := Shed._new_item(PartsDB.by_kind["tank"][0], 0.0, 0.0, 0.0)
	var guard := Shed._new_item(PartsDB.by_kind["exhaust"][0], 0.0, 0.0, 0.0)
	Shed._move(tank, "spot", spots[2])
	Shed._move(guard, "spot", spots[3])
	Shed.changed.emit()
	await _frames(5)
	var w: Walker = main.walker
	w.set_tool("gun")
	var frame: Dictionary = main.workshop.item_frame(tank)
	var centre: Vector3 = frame["xf"] * (frame["box"] as AABB).get_center()
	await _look_from(Vector3(centre.x - 0.3, 0.0, centre.z + 1.6), centre, "r7_2_booth_inside")
	Input.action_press("act")
	await _frames(45)
	await _shot("r7_3_spraying")
	Input.action_release("act")
	w.set_tool("hands")
	# Shed lights off in the evening: just the screens.
	Daylight.current.set_time(21.0)
	Shed.lights_on = false
	main.workshop.set_lights(false)
	await _look_from(Workshop.CENTER + Vector3(0.0, 0.0, 3.0), Workshop.CENTER + Vector3(0.0, 1.8, -5.0), "r7_4_lights_off")
	main.workshop.set_lights(true)
	# High beam at night on the road.
	var faithful := _bike_named("Old Faithful")
	main._try_mount(faithful)
	await _frames(10)
	main.bike.start_engine()
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	await _frames(40)
	await _shot("r7_5_low_beam")
	main.bike.cycle_beam()
	await _frames(10)
	await _shot("r7_6_high_beam")
	SaveGame.delete_slot("shots")
	get_tree().quit()
