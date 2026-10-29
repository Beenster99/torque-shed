extends Node
## The skyline at real places on the network ride (scripts/scenery/skyline.gd), by day and by night:
##   xvfb-run -a godot --path . res://tests/skyline_places.tscn -- --out=/tmp/skyline [--only=griffin,polder]
##     [--own-world]      read the postcards' own copy of the world (tests/postcards/world, offline, its heights
##                        fetched: postcards.sh --fetch --network) instead of the live store
##     [--before]         the same views with the skyline hidden: the Before
##     [--features=DIR]   cells' features baked by tools/feature_bake.py (DIR/<place>.json), for the cells the world's
##                        store hasn't mapped yet
## Each place is ridden as the postcards ride theirs (tests/postcards: from its first pin to its second, over its cell),
## from the live world store; once the scenery round the camera is in, the camera on the road turns to the tallest
## thing of the skyline in view (a turbine, a pylon, a mast, a lift...) and takes it from the road and from above.

const Postcards := preload("res://tests/postcards/postcards.gd")

const PLACES := [
	{"id": "dales", "title": "Wensleydale, the Dales", "from": [54.3045, -2.1975], "to": [54.3135, -2.0775]},
	{"id": "griffin", "want": ["turbine"], "title": "Griffin wind farm, Perthshire", "from": [56.5900, -3.7600], "to": [56.5650, -3.8500]},
	{"id": "polder", "want": ["turbine"], "title": "Flevoland, the Netherlands", "from": [52.4100, 5.5200], "to": [52.4250, 5.6000]},
	{"id": "pordoi", "want": ["lift_station", "lift_pylon", "lift_terminal"], "at": 0.95, "title": "Passo Pordoi, the Dolomites", "from": [46.4930, 11.7880], "to": [46.4880, 11.8120]},
	{"id": "texas", "want": ["water_sphere", "pylon_wide", "turbine"], "title": "Lubbock, Texas", "from": [33.5800, -101.9000], "to": [33.5800, -101.8300]},
	{"id": "gujarat", "want": ["turbine", "pylon_wide"], "title": "Kutch, Gujarat", "from": [22.9201, 69.5325], "to": [22.9413, 69.5487]},
]
## The kinds the camera turns to, the first found in view first.
const FIRST := ["turbine", "cooling", "tv_tower", "pylon", "pylon_danube", "pylon_wide", "pylon_tall", "mast", "lift_station",
	"lift_pylon", "water_tower", "water_sphere", "water_chalice", "water_square", "silo", "minaret", "campanile", "pole", "pole_concrete"]

var out_dir := "/tmp/skyline"
var only: Array = []
var features_dir := ""
var own_world := false
var before := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a == "--before":
			before = true
		elif a == "--own-world":
			own_world = true
		elif a.begins_with("--features="):
			features_dir = a.trim_prefix("--features=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if own_world:
		Postcards.use_own_world()

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
		print("skyline: %s: its pins aren't in one cell" % place["id"])
		return
	var fetched := "" if own_world else RealRegion.fetch_area(str(plan["region"]))
	if fetched != "":
		print("skyline: %s: %s" % [place["id"], fetched])
		return
	var region := RealRegion.get_region(str(plan["region"]))
	var path := features_dir.path_join("%s.json" % place["id"])
	if region != null and (region.features["points"] as Array).is_empty() and features_dir != "" and FileAccess.file_exists(path):
		var rows = JSON.parse_string(FileAccess.get_file_as_string(path))
		if rows is Dictionary:
			RealRegion.add_features(region.features, rows, Vector2(region.frame_lat, region.frame_lon))
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		print("skyline: %s: no ride (%s)" % [place["id"], res.get("error", "")])
		return
	var w := AdventureWorld.new()
	AdventureWorld.network = true
	w.roads_region = region
	w.setup(res["pack"], 1)
	if w.roads == null or w.scenery == null:
		print("skyline: %s: not on the network" % place["id"])
		w.free()
		return
	w.focus = func(): return [cam.global_position]
	w.origin_shifted.connect(func(d): cam.global_position -= d)
	add_child(w)
	Daylight.adventure_rate = 0.0
	var s := w.route.length * float(place.get("at", 0.5))
	var eye := Postcards.view_xf(w, s, "road")
	cam.global_transform = eye
	w.follow(cam.global_position)
	await _settle(w)
	eye = Postcards.view_xf(w, s, "road")   # (the world's origin may have moved under the camera while it settled)
	cam.global_transform = eye
	var target := _target(w, cam.global_position)
	print("skyline: %s: %d scenery blocks, %s, aiming at %s" % [place["id"], w.scenery.blocks.size(), w.scenery.stats, target])
	for when in ["day", "night"]:
		if Daylight.current:
			Daylight.current.set_time(11.0 if when == "day" else 22.5)
		for view in ["road", "above"]:
			_aim(w, cam, s, view, place.get("want", []))
			if view == "above" and when == "day":
				w.follow(cam.global_position)
				await _settle(w)
				_aim(w, cam, s, view, place.get("want", []))   # (the world's origin may have moved while it settled)
			w.scenery.visible = not before
			for i in 12:
				await get_tree().process_frame
			var name := "%s_%s_%s.png" % [place["id"], view, when]
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
			print("skyline: saved ", name)
	w.queue_free()
	await get_tree().process_frame


## Puts the camera on the road `s` m along (or above and behind it) looking at the skyline's thing there (_target).
func _aim(w: AdventureWorld, cam: Camera3D, s: float, view: String, want: Array) -> void:
	var eye := Postcards.view_xf(w, s, "road")
	var target := _target(w, eye.origin, want)
	var aim: Vector3 = target[1]
	cam.global_transform = eye
	if view == "above":
		cam.global_position = eye.origin + Vector3(0, 45.0, 0) - (aim - eye.origin).normalized() * 120.0
	if target[0] != "":
		cam.look_at(aim + Vector3.UP * float(target[2]) * 0.5, Vector3.UP)


## Waits (up to two minutes, without drawing: a frame on a machine without a graphics card is slow) for the roads, the
## land near the camera and the scenery round it, as the postcards do (tests/postcards/postcards.gd _settle).
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


## The skyline thing to look at from `eye`: [model, where (world), how tall], the first kind of FIRST that stands between
## 120 m and 3 km off, the nearest of it; ["", eye, 0] for none.
func _target(w: AdventureWorld, eye: Vector3, want := []) -> Array:
	var best := {}
	for node: Node3D in w.scenery.blocks.values():
		for mmi in node.get_children():
			if not mmi is MultiMeshInstance3D:
				continue
			var model := str(mmi.name).trim_prefix("skyline_")
			if not FIRST.has(model) and not want.has(model):
				continue
			var mm: MultiMesh = mmi.multimesh
			for i in mm.instance_count:
				var xf: Transform3D = (mmi as Node3D).global_transform * mm.get_instance_transform(i)
				var d := xf.origin.distance_to(eye)
				if d < 120.0 or d > (6000.0 if want.has(model) else 3000.0):
					continue
				# (the place's own kinds first, out to 6 km; then a near one of the rest before a far one)
				var rank := want.find(model) if want.has(model) else 1000 + FIRST.find(model) + (100 if d > 1800.0 else 0)
				if best.is_empty() or rank < int(best["rank"]) or (rank == int(best["rank"]) and d < float(best["d"])):
					best = {"rank": rank, "d": d, "at": xf.origin, "model": model, "h": xf.basis.y.length() * float(Skyline.SUPPORTS.get(model, {"h": 60.0})["h"])}
	if best.is_empty():
		return ["", eye, 0.0]
	return [best["model"], best["at"], best["h"]]
