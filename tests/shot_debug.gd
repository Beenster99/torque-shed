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
	# The yard kit from above, then the jump line from the run-up.
	await _look_from(Vector3(-2.0, 0.0, 103.0), Vector3(2.0, 0.0, 124.0), "r5_1_yard")
	await _look_from(Vector3(-6.0, 0.4, 108.0), Vector3(-2.0, 1.0, 120.0), "r5_2_jump_line")
	await _look_from(Vector3(6.0, 0.6, 140.0), Vector3(-6.0, 0.5, 128.0), "r5_3_obstacles")
	# Every engine layout at 1000 cc, side on, on bikes in a row outside the shed.
	var x := -8.0
	for layout in ["boxer", "twin", "parallel", "vtwin", "2stroke", "inline"]:
		var m := BikeModel.new()
		main.add_child(m)
		m.build_from(BikeBuild.new({"engine": "%s_1000" % layout, "frame": "steel_cradle"}), Color(0.2, 0.3, 0.6), {}, null, false)
		m.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0.32, 84.0))
		var l := Label3D.new()
		l.text = layout
		l.position = Vector3(0.0, 1.2, 0.0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.add_child(l)
		x += 2.2
	await _frames(5)
	await _look_from(Vector3(-2.5, 0.0, 88.5), Vector3(-2.5, 0.6, 84.0), "r5_4_engines")
	# Old Faithful and the barn find side on: tanks behind the bars, seats behind the tanks.
	var faithful := _bike_named("Old Faithful")
	var model: BikeModel = main.workshop.bike_model(faithful)
	var at: Vector3 = model.global_position
	var side: Vector3 = model.global_transform.basis.x
	await _look_from(at - side * 2.2 - Vector3.UP * at.y, at + Vector3.UP * 0.5, "r5_5_tank_and_seat")
	# The clocks from the rider's seat, and first person riding out on the road.
	main._try_mount(faithful)
	await _frames(10)
	main.bike.start_engine()
	await _frames(90)
	main.camera.set_mode(ChaseCamera.Mode.HELMET)
	await _frames(5)
	await _shot("r5_6_first_person_parked")
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	Input.action_press("throttle", 0.7)
	await _frames(150)
	await _shot("r5_7_first_person_riding")
	Input.action_release("throttle")
	# Lock the back wheel for skid marks, from the chase camera.
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	Input.action_press("rear_brake", 1.0)
	await _frames(70)
	Input.action_release("rear_brake")
	await _frames(20)
	var p: Vector3 = main.bike.global_position
	var back: Vector3 = main.bike.global_transform.basis.z
	main.camera.orbit_center = p + back * 5.0
	main.camera.orbit_radius = 6.0
	main.camera.orbit_height = 3.5
	main.camera.set_mode(ChaseCamera.Mode.ORBIT)
	await _frames(10)
	await _shot("r5_8_skid_marks")
	print("skid strips: ", SkidMarks.shared(get_tree()).count())
	get_tree().quit()
