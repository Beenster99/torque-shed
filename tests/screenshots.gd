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
	await _look_from(c + Vector3(2.0, 0.0, 6.5), c + Vector3(-2.0, 1.0, -6.0), "02_shed_overview")
	var ranger := _bike_named("Rusty Ranger")
	var model: BikeModel = main.workshop.bike_views[ranger].get_child(0)
	var engine: Vector3 = model.global_transform * model.slot_bounds("engine").get_center()
	await _look_from(engine + Vector3(1.5, -engine.y, 0.6), engine, "03_rusty_engine")
	await _look_from(c + Vector3(-10.5, 0.0, -1.0), c + Vector3(-14.0, 1.4, -4.0), "04_workbench_and_crew_board")
	await _look_from(c + Vector3(10.0, 0.0, -3.0), c + Vector3(14.0, 1.4, -4.5), "05_parts_rack")
	await _look_from(c + Vector3(-3.0, 0.0, -1.5), c + Vector3(-3.0, 2.9, -9.0), "06_bay_dashboard")
	await _look_from(c + Vector3(6.0, 0.0, 4.0), c + Vector3(9.0, 1.2, 9.0), "07_washer_and_repair_bench")
	main.walker.set_tool("wrench")
	await _look_from(engine + Vector3(1.2, -engine.y, 0.2), engine, "08_wrench_on_part")
	var faithful := _bike_named("Old Faithful")
	main._try_mount(faithful)
	await _frames(30)
	Input.action_press("throttle", 0.3)
	await _frames(90)
	await _shot("09_riding_out_the_door")
	Input.action_release("throttle")
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.snap()
	Input.action_press("throttle", 0.6)
	await _frames(100)
	await _shot("10_riding_outside")
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
