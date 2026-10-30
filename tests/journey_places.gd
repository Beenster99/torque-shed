extends Node
## Borders, tolls and airfields at real places on the network ride (scripts/scenery/journey_marks.gd), from the road and
## from above, by day and at night:
##   xvfb-run -a godot --path . res://tests/journey_places.tscn -- --out=/tmp/journey [--only=gandria,calais]
##     [--before]         the same views with the scenery hidden: the Before
##     [--features=DIR]   cells' features baked by tools/feature_bake.py (DIR/cROW_COL.json), for the cells the world's
##                        store hasn't baked with the borders named yet (Borders reads them too)
## Each place is ridden as the postcards ride theirs (tests/postcards: from its first pin to its second, over its cell),
## from the live world store; the camera stands on the road short of the place's own spot ("at") and looks at it.

const Postcards := preload("res://tests/postcards/postcards.gd")

const PLACES := [
	{"id": "gandria", "want": "board", "title": "Gandria, Switzerland into Italy", "from": [46.0080, 9.0040], "to": [46.0240, 9.0600], "at": [46.0189, 9.0253]},
	{"id": "st_stephen", "want": "board", "title": "Calais, Maine into St Stephen, New Brunswick", "from": [44.8520, -66.9950], "to": [44.8700, -66.9700], "at": [44.8586, -66.9829]},
	{"id": "kadena", "want": "booth", "title": "Kadena, Okinawa: a gate post", "from": [26.3250, 127.7520], "to": [26.3400, 127.7700], "at": [26.3318, 127.7540]},
	{"id": "calais", "want": "toll_roof", "title": "The A16 at Calais: a toll plaza", "from": [50.9200, 1.8100], "to": [50.9500, 1.8200], "at": [50.9359, 1.8150]},
	{"id": "copiapo", "want": "toll_roof", "title": "Ruta 5 by Copiapó, Chile: a toll plaza", "from": [-27.3470, -70.6330], "to": [-27.3600, -70.6500], "at": [-27.3482, -70.6363]},
	{"id": "matsuyama", "want": "toll_roof", "title": "Matsuyama, Shikoku: a toll gate", "from": [33.8500, 132.7000], "to": [33.8800, 132.7200], "at": [33.8643, 132.7097]},
	{"id": "leeds_bradford", "want": "threshold", "title": "Leeds Bradford airport from the A658", "from": [53.8560, -1.6800], "to": [53.8780, -1.6450], "at": [53.8660, -1.6610], "night_far": 700.0},
	{"id": "copiapo_air", "want": "threshold", "title": "Desierto de Atacama airport, Chile", "from": [-27.2700, -70.7600], "to": [-27.3000, -70.7900], "at": [-27.2610, -70.7790], "night_far": 700.0},
]

var out_dir := "/tmp/journey"
var only: Array = []
var features_dir := ""
var before := false


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
	cam.far = 12000.0
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
		print("journey: %s: its pins aren't in one cell" % place["id"])
		return
	var fetched := RealRegion.fetch_area(str(plan["region"]))
	if fetched != "":
		print("journey: %s: %s" % [place["id"], fetched])
		return
	var region := RealRegion.get_region(str(plan["region"]))
	var a: Array = place["from"]
	var cell := RealRegion.cell_of(float(a[0]), float(a[1]))
	var key := "%d_%d" % [cell.x, cell.y]
	var path := features_dir.path_join("c%s.json" % key)
	if region != null and features_dir != "" and FileAccess.file_exists(path):
		var rows = JSON.parse_string(FileAccess.get_file_as_string(path))
		if rows is Dictionary:
			region.features = {"points": [], "lines": [], "areas": []}
			RealRegion.add_features(region.features, rows, Vector2(region.frame_lat, region.frame_lon))
			Borders.given[key] = rows
			RegionKit.forget()
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		print("journey: %s: no ride (%s)" % [place["id"], res.get("error", "")])
		return
	var w := AdventureWorld.new()
	AdventureWorld.network = true
	w.roads_region = region
	w.setup(res["pack"], 1)
	if w.roads == null or w.scenery == null:
		print("journey: %s: not on the network" % place["id"])
		w.free()
		return
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	Daylight.adventure_rate = 0.0
	var at: Array = place["at"]
	var spot := RealRegion.to_frame(Vector2(region.frame_lat, region.frame_lon), float(at[0]), float(at[1]))
	var s := _nearest_s(w, spot)
	cam.global_position = Vector3(spot.x - w.origin.x, cam.global_position.y, spot.y - w.origin.z)
	w.follow(cam.global_position)
	await _settle(w)
	_aim(w, cam, str(place["want"]), spot, "road", "day", 0.0)
	w.follow(cam.global_position)
	await _settle(w)
	print("journey: %s: %d scenery blocks, %s, the spot %.0f m along" % [place["id"], w.scenery.blocks.size(), w.scenery.stats, s])
	_census(w, place["id"])
	for when in ["day", "night"]:
		if Daylight.current:
			Daylight.current.set_time(11.0 if when == "day" else 21.5)
		for view in ["road", "above"]:
			_aim(w, cam, str(place["want"]), spot, view, when, float(place.get("night_far", 0.0)))
			if view == "above" and when == "day":
				w.follow(cam.global_position)
				await _settle(w)
				_aim(w, cam, str(place["want"]), spot, view, when, float(place.get("night_far", 0.0)))
			w.scenery.visible = not before
			for i in 12:
				await get_tree().process_frame
			var name := "%s_%s_%s.png" % [place["id"], view, when]
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
			print("journey: saved ", name)
	w.queue_free()
	Borders.given.erase(key)
	await get_tree().process_frame


## How far along the road (m) it comes nearest region point `spot`.
func _nearest_s(w: AdventureWorld, spot: Vector2) -> float:
	var best := INF
	var at := 0.0
	var s := 0.0
	while s < w.route.length:
		var p := w.transform_at(s, 0.0).origin
		var d := Vector2(p.x + w.origin.x, p.z + w.origin.z).distance_to(spot)
		if d < best:
			best = d
			at = s
		s += 10.0
	return at


## The camera on the nearest road to the place's own model nearest its spot, `back` m along it (90, or `far` at night at
## an airfield, so the runway's lights are seen), looking at it; or above and behind it.
func _aim(w: AdventureWorld, cam: Camera3D, want: String, spot: Vector2, view: String, when: String, far: float) -> void:
	var back := 90.0 if far <= 0.0 or when == "day" else far
	var net: RoadNet = w.roads.net
	var thing := _thing(w, want, spot)
	var road := _road_near(net, thing)
	var eye_at := thing + Vector2(back, 0.0)
	var y := float(net.height.call(thing.x, thing.y))
	if not road.is_empty():
		var e := int(road[0])
		var s := float(road[1])
		var es := s - back if s > back else s + back
		eye_at = net.point_at(e, clampf(es, 0.0, net.length_of(e)))
		var ry := net.road_y(e, clampf(es, 0.0, net.length_of(e)))
		y = ry if is_finite(ry) else float(net.height.call(eye_at.x, eye_at.y))
	var ground := float(net.height.call(thing.x, thing.y))
	var eye := Vector3(eye_at.x - w.origin.x, y + 1.8, eye_at.y - w.origin.z)
	var aim := Vector3(thing.x - w.origin.x, (ground if is_finite(ground) else y) + 2.5, thing.y - w.origin.z)
	cam.global_position = eye
	if view == "above":
		var away := Vector3(eye.x - aim.x, 0.0, eye.z - aim.z).normalized()
		cam.global_position = aim + away * 170.0 + Vector3(0, 80.0, 0)
	if cam.global_position.distance_to(aim) > 1.0:
		cam.look_at(aim, Vector3.UP)


## Where (region frame) the nearest of the place's own models ("journey_marks:WANT...") to `spot` stands, or `spot`.
func _thing(w: AdventureWorld, want: String, spot: Vector2) -> Vector2:
	var best := spot
	var nearest := INF
	for node: Node3D in w.scenery.blocks.values():
		var key: Vector2i = node.get_meta("key")
		for mmi in node.get_children():
			if not mmi is MultiMeshInstance3D or not str(mmi.name).begins_with("journey_marks_" + want):
				continue
			var mm: MultiMesh = mmi.multimesh
			for i in mm.instance_count:
				var o := mm.get_instance_transform(i).origin
				var p := Vector2(o.x + key.x * 512.0, o.z + key.y * 512.0)
				if p.distance_to(spot) < nearest:
					nearest = p.distance_to(spot)
					best = p
	print("journey: aiming at %s %.0f m from the spot" % [want, nearest])
	return best


## The road nearest region point `p` within a block or so: [edge, s], or [].
func _road_near(net: RoadNet, p: Vector2) -> Array:
	var k := RoadBlock.key_of(p.x, p.y)
	var best := INF
	var out := []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e in net.edges_in(k + Vector2i(dx, dz)):
				var line := net.line_of(e)
				var s := 0.0
				for i in line.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
					var d := q.distance_to(p)
					if d < best:
						best = d
						out = [e, s + line[i].distance_to(q)]
					s += line[i].distance_to(line[i + 1])
	return out


## What the blocks round the place hold of this round's: how many of each model.
func _census(w: AdventureWorld, id: String) -> void:
	var counts := {}
	var worst := 0.0
	for node: Node3D in w.scenery.blocks.values():
		for mmi in node.get_children():
			if mmi is MultiMeshInstance3D and str(mmi.name).begins_with("journey_marks_"):
				var m := str(mmi.name).trim_prefix("journey_marks_")
				counts[m] = int(counts.get(m, 0)) + (mmi as MultiMeshInstance3D).multimesh.instance_count
	# (this round's own share of laying a block out, block by block, the second time: the roads' heights in hand)
	var net: RoadNet = w.roads.net
	for key: Vector2i in w.scenery.blocks:
		var here: Dictionary = w.scenery._filed.get(key, {})
		var rows := {"points": [], "lines": [], "areas": []}
		for part: String in rows:
			for i in here.get(part, PackedInt32Array()):
				var row: Array = net.region.features[part][i]
				var k := SceneryStreamer.kit(str(row[0]))
				if str(k.get("model", "")).begins_with("journey_marks:"):
					(rows[part] as Array).append([row, k])
		if rows["points"].is_empty() and rows["lines"].is_empty() and rows["areas"].is_empty():
			continue
		JourneyMarks.lay_out(net, key, rows)
		var t0 := Time.get_ticks_usec()
		JourneyMarks.lay_out(net, key, rows)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	print("journey: %s: %s; this round's slowest block %.2f ms (all rounds' %.1f ms)" % [id, counts, worst, float(w.scenery.stats.get("build_ms_max", 0.0))])


## Waits (up to two minutes, without drawing) for the roads, the land near the camera and the scenery round it, as the
## postcards do (tests/postcards/postcards.gd _settle).
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
