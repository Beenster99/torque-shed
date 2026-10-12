extends Node
## Captures a few screenshots of the running game for visual checks:
##   xvfb-run godot --path . res://tests/screenshots.tscn -- --out=/tmp/shots

var out_dir := "user://screenshots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	await _shot("01_title")
	main._start_session()
	main.hud.toggle_help()
	await _frames(60)
	await _shot("02_yard_start")
	var road_t: Transform3D = main.world.road_transform(0.12)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.snap()
	Input.action_press("throttle", 0.7)
	await _frames(120)
	await _shot("03_riding_tarmac")
	Input.action_press("lean_right", 0.6)
	await _frames(60)
	await _shot("04_leaning")
	Input.action_release("lean_right")
	Input.action_release("throttle")
	road_t = main.world.road_transform(0.66)
	main.bike.place(road_t.origin, road_t.basis.get_euler().y)
	main.camera.snap()
	await _frames(60)
	await _shot("05_dirt_section")
	main.camera.cycle_mode()
	await _frames(20)
	await _shot("06_helmet_cam")
	main.camera.cycle_mode()
	main._open_garage()
	await _frames(60)
	await _shot("07_garage")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)
