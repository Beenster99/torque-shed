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
	var w: Walker = main.walker
	# Full-width bay screens either side of the narrower dyno room doorway.
	await _look_from(Workshop.CENTER + Vector3(0.0, 0.0, 4.5), Vector3(0.0, 1.9, 59.2), "c1_bay_screens_doorway")
	# The dyno room: a bike strapped down at all four posts, the extraction hose on its
	# exhaust, the fan running, and the ear defenders on their hook by the door.
	var faithful := _bike_named("Old Faithful")
	Shed.request({"a": "grab_bike", "bike": faithful})
	var near := DynoRoom.rig_transform().translated(Vector3(0.2, 0.0, 0.4))
	Shed.request({"a": "move_bike", "bike": faithful, "xf": near})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": near})
	for i in 4:
		Shed.request({"a": "dyno_strap", "point": i})
	Shed.request({"a": "dyno_hose", "to": "held"})
	Shed.request({"a": "dyno_hose", "to": "bike"})
	Shed.request({"a": "dyno_fan", "on": true})
	await _frames(10)
	await _look_from(Vector3(-3.4, 0.0, 53.0), Vector3(0.6, 0.8, 57.2), "c2_dyno_room_strapped_hose")
	await _look_from(Vector3(3.6, 0.0, 58.6), Vector3(-0.4, 0.7, 54.4), "c3_dyno_fan_and_hose")
	await _look_from(Vector3(-1.0, 0.0, 57.4), Vector3(-1.7, 1.45, 59.2), "c4_dyno_switches_and_ear_defenders")
	Shed.request({"a": "dyno_headphones", "on": true})
	await _frames(10)
	await _look_from(Vector3(-2.6, 0.0, 57.8), Vector3(0.0, 0.8, 55.0), "c5_wearing_ear_defenders")
	Shed.request({"a": "dyno_headphones", "on": false})
	Shed.request({"a": "dyno_hose", "to": "held"})
	Shed.request({"a": "dyno_hose", "to": "hook"})
	for i in 4:
		Shed.request({"a": "dyno_strap", "point": i})
	Shed.request({"a": "grab_bike", "bike": faithful})
	var home := Workshop.CENTER + Vector3(-4.0, 0.0, 1.0)
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Transform3D(Basis(), home)})
	# The sandblaster, mid-blast: the barn find's engine turning on the turntable, bare metal
	# coming up where the jet has been.
	Shed.request({"a": "order_furniture", "model": "blaster_cabinet"})
	var cab := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "blaster":
			cab = id
	var spot := "blast_%d_0" % cab
	var at := Workshop.CENTER + Vector3(1.5, 0.0, 1.8)
	Shed.request({"a": "grab", "furniture": cab})
	Shed.request({"a": "release", "furniture": cab, "xf": Transform3D(Basis(), at)})
	var engine := 0
	for s in Shed.stand_spots():
		if engine == 0 and Shed.is_engine(Shed.item_at_spot(s)):
			engine = Shed.item_at_spot(s)
			Shed.request({"a": "take", "spot": s})
	Shed.request({"a": "place", "spot": spot})
	await _frames(10)
	var view: EquipmentView = main.workshop.furniture_nodes[cab]
	var pivot: Node3D = view.get_node("Pivot")
	await _look_from(at + Vector3(1.6, 0.0, 2.2), at + Vector3(0.0, 0.9, 0.0), "c6_sandblaster_cabinet")
	await _look_from(at + Vector3(0.0, 0.0, 0.95), pivot.global_position, "c7_sandblaster_ready")
	Shed.request({"a": "blast_use", "spot": spot, "on": true})
	await _frames(5)
	Input.action_press("act")
	for i in 420:
		await get_tree().physics_frame
		if w.blast:
			w.blast.turn(Vector2(0.012, 0.004 * sin(i * 0.05)))
		if i % 40 == 0:
			w._look(0.0, 0.03 if (i / 40) % 2 == 0 else -0.03)
	await _shot("c8_sandblaster_mid_blast")
	Input.action_release("act")
	await _frames(10)
	await _shot("c9_sandblaster_bare_patches")
	w.finish_blast()
	await _frames(10)
	# The headlight at night: a soft beam in the night air rather than a solid cone.
	Daylight.current.set_time(22.0)
	main._try_mount(faithful)
	await _frames(10)
	main.bike.start_engine()
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	await _frames(40)
	await _shot("c10_low_beam_night")
	main.bike.cycle_beam()
	await _frames(20)
	await _shot("c11_high_beam_night")
	SaveGame.delete_slot("shots")
	get_tree().quit()
