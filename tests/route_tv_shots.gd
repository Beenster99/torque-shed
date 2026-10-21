extends "res://tests/screenshots.gd"
## Pictures of the route planner TV in the shed:
##   xvfb-run -a godot --path . res://tests/route_tv_shots.tscn -- --out=/tmp/shots
## The shed from the doorway, the TV close up empty, with pins and a planned road, and on the places tab.


func _ready() -> void:
	Shed.demo_bikes = true
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
	await _frames(30)
	var c := Workshop.CENTER
	var tv: Vector3 = main.workshop._route_screen.global_position
	await _look_from(c + Vector3(2.0, 0.0, 4.0), tv, "01_route_tv_from_the_door")
	await _look_from(c + Vector3(-2.4, 0.0, -3.4), tv, "02_route_tv_close")
	var r := RealRegion.get_region("shodoshima")
	var a := r.geo_to_xz(34.518638, 134.269646)
	var b := r.geo_to_xz(34.499373, 134.347915)
	var mid := r.geo_to_xz(34.53, 134.22)
	Shed.request({"a": "adventure_pin", "region": "shodoshima", "x": a.x, "z": a.y})
	Shed.request({"a": "adventure_pin", "region": "shodoshima", "x": mid.x, "z": mid.y})
	Shed.request({"a": "adventure_pin", "region": "shodoshima", "x": b.x, "z": b.y})
	var end := Time.get_ticks_msec() + 60000
	var board: RouteTv = main.workshop._route_screen._route
	while Time.get_ticks_msec() < end and board.view.route_pts.size() < 2:
		await _frames(10)
	await _frames(40)
	await _look_from(c + Vector3(-2.4, 0.0, -3.4), tv, "03_route_tv_planned")
	board._tab = "places"
	board.refresh()
	await _frames(40)
	await _look_from(c + Vector3(-2.4, 0.0, -3.4), tv, "04_route_tv_places")
	SaveGame.delete_slot("shots")
	get_tree().quit()
