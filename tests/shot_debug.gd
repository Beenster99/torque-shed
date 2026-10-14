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
	if "--beam" in OS.get_cmdline_user_args():
		await _beam_shots()
		get_tree().quit()
		return
	if "--geo" in OS.get_cmdline_user_args():
		await _geo_shots()
		SaveGame.delete_slot("shots")
		get_tree().quit()
		return
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
	await _beam_shots()
	SaveGame.delete_slot("shots")
	get_tree().quit()


## The headlight at night: a soft beam in the night air rather than a solid cone. (Only the
## stand-in glow shows here: volumetric fog needs Forward+, which the cloud can't render.)
## `-- --beam` takes just these.
func _beam_shots() -> void:
	Daylight.current.set_time(22.0)
	main._try_mount(_bike_named("Old Faithful"))
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


## Geometry mode on the Rusty Ranger (move, rotate and scale handles on its tank), and a
## blueprint build: the hologram in an empty bay, then half built with ghosts for the rest.
## `-- --geo` takes just these.
func _geo_shots() -> void:
	var w: Walker = main.walker
	var ranger := _bike_named("Rusty Ranger")
	var view: Node3D = main.workshop.bike_views[ranger]
	w.place(Transform3D(Basis(), view.global_position + Vector3(1.6, 0.1, 0.4)))
	await _frames(5)
	main.open_geometry()
	var geo: GeometryMode = main.geometry
	geo.select("tank")
	geo.set_part_offset("tank", {"p": Vector3(0.0, 0.04, -0.03), "r": Vector3(-8.0, 0.0, 0.0), "s": Vector3(1.0, 1.0, 1.15)})
	await _frames(20)
	await _shot("g1_geometry_move")
	geo.set_mode(GeoGizmo.Mode.ROTATE)
	await _frames(5)
	await _shot("g2_geometry_rotate")
	geo.set_mode(GeoGizmo.Mode.SCALE)
	geo.select("handlebars")
	await _frames(5)
	await _shot("g3_geometry_scale_bars")
	geo.save_blueprint("Desert Ranger")
	geo.request_exit()
	await _frames(5)
	var bp := Shed.blueprint_named("Desert Ranger")
	Shed.request({"a": "bp_build", "bp": bp, "bay": 3})
	await _frames(10)
	var bay := Workshop.bay_transform(3)
	await _look_from(bay.origin + Vector3(-1.9, 0.0, 2.6), bay.origin + Vector3(0.0, 0.7, 0.0), "g4_hologram_in_bay")
	await _look_from(bay.origin + Vector3(-0.6, 0.0, 3.0), Vector3(Workshop.BAY_SCREEN_X[3], 2.5, Workshop.CENTER.z - Workshop.HALF.y), "g5_bay_screen_blueprint")
	var frame := Shed._new_item(str(Shed.blueprints[bp]["parts"]["frame"]), 0.0, 0.0, 0.0)
	Shed._move(frame, "held", Shed.me())
	Shed.request({"a": "start_build", "bay": 3})
	var built := Shed.bike_in_bay(3)
	for slot in ["fork", "front_wheel", "front_tyre", "tank", "engine"]:
		var item := Shed._new_item(str(Shed.blueprints[bp]["parts"][slot]), 0.0, 0.0, 0.0)
		Shed.bikes[built]["slots"][slot] = item
		Shed._move(item, "bike", built)
	Shed.changed.emit()
	await _frames(10)
	await _look_from(bay.origin + Vector3(-1.9, 0.0, 2.6), bay.origin + Vector3(0.0, 0.7, 0.0), "g6_half_built_with_ghosts")
