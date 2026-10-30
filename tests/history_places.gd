extends Node
## History at real places on the network ride (scripts/scenery/history.gd, scripts/building_looks.gd), by day and by
## night, for the Before/After pictures:
##   xvfb-run -a godot --path . res://tests/history_places.tscn -- --out=/tmp/history [--only=conwy,york]
##     [--before]         the same views with history's scenery hidden and the buildings without their mapped looks
##     [--features=DIR]   cells' features baked by tools/feature_bake.py (DIR/<place>.json) in place of the store's (the
##                        store's carry no building looks until Map the features runs again)
## Each place is ridden from its first pin to its second, over its cell, from the live world store; once the scenery
## round the camera is in, the camera on the road turns to the nearest thing of the place's own kinds (a gate's arch,
## a tower on the wall, a church) and takes it from the road and from above.

const Postcards := preload("res://tests/postcards/postcards.gd")

const PLACES := [
	{"id": "conwy", "want": ["arch_", "tower_round_", "wall_"], "title": "Conwy's walls, Wales", "from": [53.2797, -3.8372], "to": [53.2817, -3.8290]},
	{"id": "york", "want": ["arch_", "tower_round_", "wall_"], "title": "York's walls, Micklegate Bar", "from": [53.9530, -1.0925], "to": [53.9578, -1.0852]},
	{"id": "bavaria", "want": ["church"], "title": "Oberammergau to Ettal, Bavaria", "from": [47.5975, 11.0665], "to": [47.5690, 11.0940]},
	{"id": "chester", "want": ["arch_", "tower_round_", "wall_"], "title": "Chester's walls, the Eastgate", "from": [53.1928, -2.8822], "to": [53.1902, -2.8930]},
]

var out_dir := "/tmp/history"
var only: Array = []
var features_dir := ""
var before := false
var looks: Array = []   # (the place's building looks, kept for aiming even when --before leaves them out)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a == "--before":
			before = true
		elif a.begins_with("--features="):
			features_dir = a.trim_prefix("--features=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	Settings.day_night_cycle = false
	var sky := World.new()
	sky.name = "Sky"
	add_child(sky)
	sky._build_environment()
	var cam := Camera3D.new()
	cam.far = 9000.0
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	for place: Dictionary in PLACES:
		if not only.is_empty() and not only.has(place["id"]):
			continue
		await _place(place, cam)
	get_tree().quit()


func _place(place: Dictionary, cam: Camera3D) -> void:
	var plan := Postcards.plan_of(place)
	if plan.is_empty():
		print("history: %s: its pins aren't in one cell" % place["id"])
		return
	var fetched := RealRegion.fetch_area(str(plan["region"]))
	if fetched != "":
		print("history: %s: %s" % [place["id"], fetched])
		return
	var region := RealRegion.get_region(str(plan["region"]))
	if region == null:
		print("history: %s: no region (its cells aren't in the world's store)" % place["id"])
		return
	var path := features_dir.path_join("%s.json" % place["id"])
	if region != null and features_dir != "" and FileAccess.file_exists(path):
		var rows = JSON.parse_string(FileAccess.get_file_as_string(path))
		if rows is Dictionary:
			region.features = {"points": [], "lines": [], "areas": []}
			RealRegion.add_features(region.features, rows, Vector2(region.frame_lat, region.frame_lon))
	looks = region.features.get("buildings", [])
	if before:
		region.features.erase("buildings")
	print("history: %s: %d building looks, %d lines" % [place["id"], (region.features.get("buildings", []) as Array).size(),
		(region.features["lines"] as Array).size()])
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		print("history: %s: no ride (%s)" % [place["id"], res.get("error", "")])
		return
	var w := AdventureWorld.new()
	AdventureWorld.network = true
	w.roads_region = region
	w.setup(res["pack"], 1)
	if w.roads == null or w.scenery == null:
		print("history: %s: not on the network" % place["id"])
		w.free()
		return
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	Daylight.adventure_rate = 0.0
	var s := w.route.length * 0.5
	cam.global_transform = Postcards.view_xf(w, s, "road")
	w.follow(cam.global_position)
	await _settle(w)
	# Along the ride, where it passes nearest the place's own thing (under a gate's arch, past a wall, by a church):
	# the camera 70 m back from there on the road.
	var things := _things(w, place["want"])
	var best := INF
	var step := 0.0
	while step < w.route.length:
		var eye := Postcards.view_xf(w, step, "road").origin
		for th: Array in things:
			var d := Vector2(eye.x, eye.z).distance_to(Vector2((th[1] as Vector3).x, (th[1] as Vector3).z)) + float(th[0]) * 40.0
			if d < best:
				best = d
				# (a building from closer: it's smaller than a town's walls)
				s = maxf(0.0, step - (35.0 if str(place["want"][int(th[0])]) in ["church", "temple", "shrine", "mosque"] else 70.0))
		step += 5.0
	cam.global_transform = Postcards.view_xf(w, s, "road")
	w.follow(cam.global_position)
	await _settle(w)
	var target := _target(w, Postcards.view_xf(w, s, "road").origin, place["want"])
	print("history: %s: %d scenery blocks, %s, aiming at %s" % [place["id"], w.scenery.blocks.size(), w.scenery.stats, target])
	var counts := {}
	for node: Node3D in w.scenery.blocks.values():
		for mmi in node.get_children():
			if mmi is MultiMeshInstance3D and str(mmi.name).begins_with("history_"):
				counts[str(mmi.name)] = int(counts.get(str(mmi.name), 0)) + (mmi as MultiMeshInstance3D).multimesh.instance_count
	print("history: %s: %s" % [place["id"], counts])
	for when in ["day", "night"]:
		if Daylight.current:
			Daylight.current.set_time(11.0 if when == "day" else 22.5)
		for view in ["road", "above"]:
			var eye := Postcards.view_xf(w, s, "road")
			target = _target(w, eye.origin, place["want"])
			cam.global_transform = eye
			var aim: Vector3 = target[1] if target[0] != "" else eye.origin - eye.basis.z * 50.0
			if view == "above":
				cam.global_position = eye.origin + Vector3(0, 55.0, 0) - (aim - eye.origin).normalized() * 90.0
				cam.look_at(aim + Vector3.UP * 4.0, Vector3.UP)
			elif (aim - eye.origin).normalized().dot(-eye.basis.z) < 0.6:
				# (from the road, along it, unless the thing is well off to one side: then turned to it)
				cam.look_at(aim + Vector3.UP * 4.0, Vector3.UP)
			else:
				cam.rotate_object_local(Vector3.RIGHT, 0.08)
			w.scenery.visible = not before
			for i in 12:
				await get_tree().process_frame
			var name := "%s_%s_%s.png" % [place["id"], view, when]
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
			print("history: saved ", name)
	w.queue_free()
	await get_tree().process_frame


## Waits (up to two minutes, without drawing) for the roads, the land near the camera and the scenery round it, as the
## postcards do.
func _settle(w: AdventureWorld) -> void:
	RenderingServer.render_loop_enabled = false
	var end := Time.get_ticks_msec() + 120000
	var near_in := -1
	while Time.get_ticks_msec() < end:
		for i in 3:
			await get_tree().process_frame
		var roads_in := RoadStreamer.wanted(w.roads.riders(), 600.0).all(func(k): return w.roads.blocks.has(k) or not w.roads.can_build(k))
		var scenery_in := w.scenery._tasks.is_empty() and w.scenery._done.is_empty()
		if not roads_in or not scenery_in:
			continue
		if w.land == null or not w.land.busy():
			break
		if Postcards._near_land_in(w.land):
			if near_in < 0:
				near_in = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - near_in > 15000:
				break
	RenderingServer.render_loop_enabled = true
	for i in 6:
		await get_tree().process_frame


## Every one of the place's own things laid out: [[rank (its kind's place in `want`), where (world)]], the mapped
## churches' too where it wants one.
func _things(w: AdventureWorld, want: Array) -> Array:
	var out: Array = []
	for node: Node3D in w.scenery.blocks.values():
		for mmi in node.get_children():
			if not mmi is MultiMeshInstance3D:
				continue
			var model := str(mmi.name).trim_prefix("history_")
			for i in want.size():
				if model.begins_with(str(want[i])):
					var mm: MultiMesh = mmi.multimesh
					for k in mm.instance_count:
						out.append([i, ((mmi as Node3D).global_transform * mm.get_instance_transform(k)).origin])
					break
	for i in want.size():
		var cls := str(want[i])
		var of: Array = ["church", "chapel", "cathedral"] if cls == "church" else [cls]
		if cls in ["church", "temple", "shrine", "mosque"]:
			for b: Array in looks:
				if str(b[2]) in of:
					out.append([i, Vector3(float(b[0]), 0, float(b[1])) - w.origin])
	return out


## The nearest of the place's own things to `eye` between 30 m and 1.5 km off: [model, where (world)], or ["", eye]. A
## "church" is looked for among the road blocks' buildings' places of worship: its nearest building of the worship kind.
func _target(w: AdventureWorld, eye: Vector3, want: Array) -> Array:
	var best := {}
	for node: Node3D in w.scenery.blocks.values():
		for mmi in node.get_children():
			if not mmi is MultiMeshInstance3D:
				continue
			var model := str(mmi.name).trim_prefix("history_")
			var rank := -1
			for i in want.size():
				if model.begins_with(str(want[i])):
					rank = i
					break
			if rank < 0:
				continue
			var mm: MultiMesh = mmi.multimesh
			for i in mm.instance_count:
				var xf: Transform3D = (mmi as Node3D).global_transform * mm.get_instance_transform(i)
				var d := xf.origin.distance_to(eye)
				if d < 30.0 or d > 1500.0:
					continue
				if best.is_empty() or rank < int(best["rank"]) or (rank == int(best["rank"]) and d < float(best["d"])):
					best = {"rank": rank, "d": d, "at": xf.origin, "model": model}
	if best.is_empty() and (want.has("church") or want.has("temple")):
		return _church(w, eye)
	if best.is_empty():
		return ["", eye]
	return [best["model"], best["at"]]


## The nearest mapped place of worship's building to `eye`, by the region's building looks: ["church", where].
func _church(w: AdventureWorld, eye: Vector3) -> Array:
	var best := ["", eye]
	var bd := 1500.0
	var o := w.origin
	for b: Array in looks:
		if str(b[2]) not in ["church", "chapel", "cathedral", "temple", "shrine", "mosque"]:
			continue
		var p := Vector3(float(b[0]), eye.y, float(b[1])) - Vector3(o.x, 0, o.z)
		var d := Vector2(p.x, p.z).distance_to(Vector2(eye.x, eye.z))
		if d > 40.0 and d < bd:
			bd = d
			best = ["church", p]
	return best
