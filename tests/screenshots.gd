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
	var model: BikeModel = main.workshop.bike_views[ranger].get_child(0)
	var engine: Vector3 = model.global_transform * model.slot_bounds("engine").get_center()
	await _look_from(engine + Vector3(1.5, -engine.y, 0.6), engine, "03_rusty_engine")
	var faithful_id := _bike_named("Old Faithful")
	var sport: BikeModel = main.workshop.bike_views[faithful_id].get_child(0)
	var wheel: Vector3 = sport.global_transform * sport.slot_bounds("front_disc").get_center()
	await _look_from(wheel + Vector3(1.2, -wheel.y, -0.6), wheel + Vector3(0.0, 0.1, 0.0), "04_brakes_and_wheel")
	var stand: Vector3 = Workshop.spot_transform("engine_stand").origin
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
	var faithful := _bike_named("Old Faithful")
	main._try_mount(faithful)
	await _frames(30)
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
