extends "res://tests/screenshots.gd"
## Pictures of the route planner TV in the shed:
##   xvfb-run -a godot --path . res://tests/route_tv_shots.tscn -- --out=/tmp/shots
## The shed from the doorway with the world on the TV, then (each as the room sees it and as the TV's page) the world
## close up, the main roads further out (northern England and Shikoku), Shodoshima close in with its roads (its cells fetched from the world's store), a road planned there, the
## search, and the Dyno Room's wall TV, which shows the same.


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
	Shed.screens["crew"] = {"ch": "route", "rider": 0}   # the crew board, tuned to the route planner
	var dash: Dashboard = main.workshop._crew_screen
	var tv: Vector3 = dash.global_position
	var close := c + Vector3(-2.4, 0.0, -3.4)
	await _look_from(close, tv, "00_warm_up")
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and (dash._route == null or dash._route.view.busy()):
		await _frames(10)
	var board: RouteTv = dash._route
	await _frames(20)
	await _look_from(c + Vector3(2.0, 0.0, 4.0), tv, "01_route_tv_from_the_door")
	await _tv_shot(close, tv, dash, "02_the_world")
	# Further out than the roads: the sketch of the main roads, northern England (motorways and trunk roads) and then
	# Shikoku closer (the A roads too).
	for at: Array in [[54.2, -2.0, 400000.0, "02a_main_roads_england"], [33.9, 133.6, 200000.0, "02b_main_roads_shikoku"]]:
		board.ask({"lat": at[0], "lon": at[1], "span": at[2]})
		end = Time.get_ticks_msec() + 120000
		while Time.get_ticks_msec() < end and (board.view.busy() or board.view._sketch.is_empty()):
			await _frames(10)
		await _frames(20)
		await _tv_shot(close, tv, dash, at[3])
	# Shodoshima, close in: its cells come from the world's store.
	var r := RealRegion.get_region("shodoshima")
	var geo := func(lat: float, lon: float) -> Vector2: return Vector2(lat, lon)
	board.ask({"lat": 34.51, "lon": 134.28, "span": 30000.0})
	end = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < end and (board.view.busy() or not board.view.roads_shown()):
		await _frames(10)
	await _frames(20)
	await _tv_shot(close, tv, dash, "03_shodoshima_close_in")
	for p: Vector2 in [geo.call(34.518638, 134.269646), geo.call(34.53, 134.22), geo.call(34.499373, 134.347915)]:
		Shed.request({"a": "adventure_pin", "lat": p.x, "lon": p.y, "name": ""})
	end = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < end and board.view.route_geo.size() < 2:
		await _frames(10)
	await _frames(40)
	await _tv_shot(close, tv, dash, "04_a_road_planned")
	board.ask({"tab": "find", "q": "taka"})
	await _frames(40)
	await _tv_shot(close, tv, dash, "05_find_a_place")
	board.ask({"tab": "plan", "q": ""})
	var wall: Vector3 = main.workshop.dyno_room.plan_tv.global_position
	await _look_from(Vector3(2.8, 0.0, 57.6), wall, "06_dyno_room_warm_up")
	end = Time.get_ticks_msec() + 60000
	var plan_tv: Dashboard = main.workshop.dyno_room.plan_tv
	while Time.get_ticks_msec() < end and (plan_tv._route == null or plan_tv._route.view.busy() or plan_tv._route.view.route_geo.size() < 2):
		await _frames(10)
	await _frames(40)
	await _look_from(Vector3(2.8, 0.0, 57.6), wall, "07_dyno_room_planning_tv")
	SaveGame.delete_slot("shots")
	get_tree().quit()


## A picture from `from` looking at `at`, and the TV's own page.
func _tv_shot(from: Vector3, at: Vector3, dash: Dashboard, name: String) -> void:
	await _look_from(from, at, name)
	var img := dash._viewport.get_texture().get_image()
	img.save_png(out_dir.path_join(name + "_page.png"))
