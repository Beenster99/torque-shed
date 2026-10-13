extends Node
## Captures screenshots of the running game for visual checks:
##   xvfb-run godot --path . res://tests/screenshots.tscn -- --out=/tmp/shots

var out_dir := "user://screenshots"
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	await _shot("01_title")
	main._start_session()
	await _frames(30)
	var c := Workshop.CENTER
	await _look_from(c + Vector3(0.5, 0.0, 4.6), c + Vector3(-0.5, 1.0, -5.0), "02_shed_overview")
	var ranger := _bike_named("Rusty Ranger")
	var model: BikeModel = main.workshop.bike_model(ranger)
	var engine: Vector3 = model.global_transform * model.slot_bounds("engine").get_center()
	await _look_from(engine + Vector3(1.5, -engine.y, 0.6), engine, "03_rusty_engine")
	var faithful_id := _bike_named("Old Faithful")
	var sport: BikeModel = main.workshop.bike_model(faithful_id)
	var wheel: Vector3 = sport.global_transform * sport.slot_bounds("front_disc").get_center()
	await _look_from(wheel + Vector3(1.2, -wheel.y, -0.6), wheel + Vector3(0.0, 0.1, 0.0), "04_brakes_and_wheel")
	var stand: Vector3 = Shed.spot_transform(Shed.stand_spots()[0]).origin
	await _look_from(stand + Vector3(-1.6, -stand.y, 0.5), stand + Vector3(0.0, 0.1, 0.0), "05_engine_stand")
	await _look_from(c + Vector3(-3.6, 0.0, 0.6), c + Vector3(-6.5, 1.5, 0.6), "06_workbench_and_crew_board")
	await _look_from(c + Vector3(-1.6, 0.0, -0.6), c + Vector3(-1.6, 2.3, -5.5), "07_bay_dashboard")
	await _look_from(c + Vector3(1.0, 0.0, 1.0), c + Vector3(-4.6, 0.4, 4.6), "08_deliveries_and_bin")
	await _look_from(c + Vector3(3.6, 0.0, 1.2), c + Vector3(6.5, 1.0, 2.0), "09_parts_computer")
	main._open_computer()
	await _frames(10)
	await _shot("10_parts_computer_screen")
	main.computer.close_computer()
	var barn := _bike_named("Barn Find")
	var barn_xf: Transform3D = Shed.bikes[barn]["xf"]
	await _look_from(barn_xf.origin + Vector3(-1.9, 0.0, 0.9), barn_xf.origin + Vector3(0.0, 0.6, 0.0), "11_barn_find")
	main.walker.set_tool("spray")
	var tank: Vector3 = model.global_transform * model.slot_bounds("tank").get_center()
	await _look_from(tank + Vector3(1.1, -tank.y, 0.2), tank, "12_spray_can_on_tank")
	# Five tanks on the floor, one in each spray finish.
	var finishes := ["gloss", "matte", "metallic", "chrome", "patina"]
	var colors := [0, 1, 3, 9, 2]
	for i in finishes.size():
		var id: int = Shed._new_item("cafe_15", 0.0, 0.0, 0.0, Shed.PAINTS[colors[i]])
		Shed.items[id]["finish"] = finishes[i]
		Shed._move(id, "floor", Transform3D(Basis(Vector3.UP, 0.4), c + Vector3(-1.6 + i * 0.75, 0.0, 1.6)))
	Shed.changed.emit()
	await _look_from(c + Vector3(0.0, 0.0, 3.4), c + Vector3(0.0, 0.1, 1.6), "15_paint_finishes_on_the_floor")
	Shed.request({"a": "radio", "on": true, "station": 0})
	var radio_at: Vector3 = main.workshop.radio.global_position
	main.walker.set_tool("hands")
	await _look_from(radio_at + Vector3(1.5, -radio_at.y, 0.0), radio_at + Vector3(0.0, 0.15, 0.0), "16_shed_radio")
	# Deliveries waiting outside, and a labelled shelving unit with stock on it.
	for part in ["sport_road", "iridium_plugs", "usd_sport"]:
		Shed.request({"a": "order_part", "part": part})
	Shed.request({"a": "order_furniture", "kind": "shelf"})
	var shelf := 0
	for id in Shed.furniture:
		if Shed.furniture[id]["kind"] == "shelf":
			shelf = id
	Shed.request({"a": "grab", "furniture": shelf})
	Shed.request({"a": "release", "furniture": shelf, "xf": Transform3D(Basis(Vector3.UP, PI), c + Vector3(-4.8, 0.0, 5.15))})
	await _look_from(c + Vector3(4.0, 0.0, 10.5), c + Vector3(4.5, 0.2, 7.0), "17_deliveries_outside")
	var n := 0
	for id in Shed.items.keys():
		if Shed.items[id].get("boxed", false) and n < 2:
			Shed.request({"a": "take", "item": id})
			Shed.request({"a": "place", "spot": "shelf_%d_%d" % [shelf, n * 3]})
			n += 1
	Shed.request({"a": "label", "furniture": shelf, "text": "Tyres and plugs"})
	await _look_from(c + Vector3(-4.8, 0.0, 2.9), c + Vector3(-4.8, 1.0, 5.15), "18_labelled_shelf")
	# Fluids: a jerry can, a bottle of oil and brake fluid on the floor.
	var i := 0
	for part in ["unleaded_95", "synthetic_5w40", "dot4", "drain_pan"]:
		var fid: int = Shed._new_item(part, 0.0, 0.0, 0.0)
		Shed._move(fid, "floor", Transform3D(Basis(Vector3.UP, 0.3 * i), c + Vector3(-1.2 + i * 0.8, 0.0, 2.4)))
		i += 1
	Shed.changed.emit()
	await _look_from(c + Vector3(0.0, 0.0, 4.0), c + Vector3(0.0, 0.1, 2.4), "19_fluids")
	# Old Faithful wheeled outside and left on its side stand.
	var faithful := _bike_named("Old Faithful")
	var outside := c + Vector3(2.5, 0.0, 9.5)
	Shed.request({"a": "grab_bike", "bike": faithful})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Transform3D(Basis(), outside)})
	await _frames(5)
	await _look_from(outside + Vector3(-2.0, 0.0, 1.2), outside + Vector3(0.0, 0.5, 0.0), "20_on_the_side_stand")
	# Muddy and in the wash bay, getting the pressure washer.
	Shed.request({"a": "grab_bike", "bike": faithful})
	Shed.request({"a": "release_bike", "bike": faithful, "xf": Transform3D(Basis(), Workshop.WASH_CENTER)})
	for slot in PartsDB.SLOTS:
		var on: int = Shed.item_on(faithful, slot)
		if on != 0:
			Shed.items[on]["dirt"] = 0.85
	Shed.changed.emit()
	await _frames(5)
	var fsport: BikeModel = main.workshop.bike_model(faithful)
	var tyre: Vector3 = fsport.global_transform * fsport.slot_bounds("front_tyre").get_center()
	main.walker.set_tool("lance")
	await _look_from(Vector3(tyre.x + 1.6, 0.0, tyre.z + 0.9), tyre, "21_wash_bay_before")
	Input.action_press("act")
	await _frames(45)
	await _shot("22_pressure_washing")
	Input.action_release("act")
	await _look_from(Workshop.WASH_CENTER + Vector3(4.5, 0.0, 4.5), Workshop.WASH_CENTER + Vector3(0.0, 1.0, 0.0), "23_wash_bay_outside")
	main.walker.set_tool("hands")
	main._try_mount(faithful)
	await _frames(30)
	main.bike.start_engine()
	await _frames(120)
	Input.action_press("throttle", 0.3)
	await _frames(90)
	await _shot("13_riding_out_the_door")
	Input.action_release("throttle")
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.snap()
	Input.action_press("throttle", 0.6)
	await _frames(100)
	await _shot("14_riding_outside")
	main.camera.set_mode(ChaseCamera.Mode.HELMET)
	await _frames(40)
	await _shot("24_first_person")
	main.camera.set_mode(ChaseCamera.Mode.CHASE)
	Input.action_release("throttle")
	road_t = main.world.road_transform(0.62)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.snap()
	Input.action_press("throttle", 0.8)
	await _frames(150)
	await _shot("25_dust_on_the_dirt")
	Input.action_release("throttle")
	get_tree().quit()


func _look_from(feet: Vector3, at: Vector3, name: String) -> void:
	var w: Walker = main.walker
	w.place(Transform3D(Basis(), feet))
	var eye := feet + Vector3.UP * Walker.EYE
	var d := at - eye
	w.rotation.y = atan2(-d.x, -d.z)
	w._pitch = 0.0
	w._look(0.0, atan2(d.y, Vector2(d.x, d.z).length()))
	await _frames(20)
	await _shot(name)


func _bike_named(n: String) -> int:
	for id in Shed.bikes:
		if Shed.bikes[id]["name"] == n:
			return id
	return 0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)
