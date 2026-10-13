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
	await _frames(10)
	var c := Workshop.CENTER
	var yard := c + Vector3(-6.0, 0.0, 16.0)
	# Equipment laid out in the yard, one row per kind, facing the camera.
	var rows := ["washer", "repair", "bench", "shelf"]
	for r in rows.size():
		var x := 0.0
		for model in Equipment.by_kind(rows[r]):
			var size: Vector3 = Equipment.get_model(model)["size"]
			x += size.x * 0.5
			Shed._new_furniture(rows[r], Transform3D(Basis(), yard + Vector3(x, 0.0, -r * 3.2)), model)
			x += size.x * 0.5 + 0.5
	# Parts on some of them.
	for id in Shed.furniture:
		var spots := Shed.furniture_spots(id)
		var kind := str(Shed.furniture[id]["kind"])
		if kind in ["shelf", "repair", "bench", "washer"] and Shed.furniture[id]["xf"].origin.z > c.z + 8.0:
			var parts := ["stock_muffler", "cafe_15", "cast_17", "paper_oil", "twin_carbs", "iridium_plugs"]
			for n in mini(spots.size(), 5 if kind == "shelf" else 2):
				var item := Shed._new_item(parts[(n + id) % parts.size()], 0.5, 0.6, 0.3)
				Shed._move(item, "spot", spots[n])
	Shed.changed.emit()
	await _frames(5)
	for r in rows.size():
		var z := yard.z - r * 3.2
		await _look_from(Vector3(yard.x + 4.5, 0.0, z + 3.6), Vector3(yard.x + 4.5, 0.8, z), "r4_%d_%s" % [r + 1, rows[r]])
	# Posters and a TV on the front wall inside, a sofa and stools under them.
	var wall_z := c.z + Workshop.HALF.y - 0.01
	var hang := [["poster_tt", -5.6, 2.2], ["poster_cafe", -4.8, 2.2], ["tv_55", 4.6, 2.3], ["poster_shed", -5.2, 3.3], ["poster_oil", 5.6, 3.4]]
	for h in hang:
		Shed._new_furniture(Equipment.kind_of(h[0]), Transform3D(Basis(Vector3.UP, PI), Vector3(c.x + h[1], h[2], wall_z)), h[0])
	Shed._new_furniture("seat", Transform3D(Basis(Vector3.UP, PI), c + Vector3(-1.2, 0.0, 3.0)), "seat_sofa")
	Shed._new_furniture("seat", Transform3D(Basis(Vector3.UP, PI * 0.8), c + Vector3(1.0, 0.0, 2.6)), "seat_stool")
	Shed._new_furniture("seat", Transform3D(Basis(Vector3.UP, PI * 1.2), c + Vector3(2.0, 0.0, 2.4)), "seat_chair")
	Shed.changed.emit()
	await _frames(5)
	await _look_from(c + Vector3(-2.5, 0.0, -1.5), c + Vector3(-3.5, 1.6, 5.0), "r4_5_posters_and_sofa")
	await _look_from(c + Vector3(2.5, 0.0, -0.5), c + Vector3(4.0, 1.8, 5.0), "r4_6_tv")
	# Wheels on the floor.
	var i := 0
	for w in ["wire_16_bobber", "excel_21_black", "cast_18_three", "cast_19_six", "cast_17_y", "forged_17_alu", "forged_17_mag", "spoked_19_adventure"]:
		var item := Shed._new_item(w, 0.0, 0.0, 0.0)
		Shed._move(item, "floor", Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 0.0), c + Vector3(-3.0 + (i % 4) * 0.9, 0.0, -0.6 + (i / 4) * 1.0)))
		i += 1
	Shed.changed.emit()
	await _frames(5)
	await _look_from(c + Vector3(-1.6, 0.0, 2.2), c + Vector3(-1.6, 0.0, -0.1), "r4_7_wheels")
	# The chain on Old Faithful, from low down on its left.
	var faithful := _bike_named("Old Faithful")
	var model: BikeModel = main.workshop.bike_model(faithful)
	var chain: Vector3 = model.global_transform * model.slot_bounds("chain").get_center()
	var side: Vector3 = model.global_transform.basis.x
	main.walker.set_crouched(true)
	await _frames(30)
	var feet := chain - Vector3(side.x, 0.0, side.z).normalized() * 0.9
	feet.y = 0.0
	main.walker.place(Transform3D(Basis(), feet))
	await _frames(20)
	var eye: Vector3 = main.walker.camera.global_position
	var d := chain - eye
	main.walker.rotation.y = atan2(-d.x, -d.z)
	main.walker._pitch = 0.0
	main.walker._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
	await _frames(10)
	await _shot("r4_8_chain")
	main.walker.set_crouched(false)
	# Riding: first person, and the jet in the wash bay.
	main._try_mount(faithful)
	await _frames(10)
	main.bike.start_engine()
	await _frames(60)
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.set_mode(ChaseCamera.Mode.HELMET)
	Input.action_press("throttle", 0.6)
	await _frames(40)
	await _shot("r4_9_first_person")
	Input.action_release("throttle")
	get_tree().quit()
