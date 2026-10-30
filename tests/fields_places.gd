extends Node
## Land texture at real places on the network ride (scripts/scenery/fields.gd): the Mosel's vines, Almería's plastic
## houses, the Camargue's salt pans, Swaledale's walls, Bali's paddies and the rest, from the road and from above:
##   xvfb-run -a godot --path . res://tests/fields_places.tscn -- --out=/tmp/fields [--only=mosel,almeria]
##     [--before]         the same views with the scenery hidden: the Before
##     [--features=DIR]   cells' features baked by tools/feature_bake.py (DIR/<place>.json), for the cells the world's
##                        store hasn't mapped yet (or not with this round's classes: Bali's rice fields)
## Each place is ridden as the postcards ride theirs (tests/postcards: from its first pin to its second, over its cell),
## from the live world store; once the scenery round the camera is in, the camera on the road turns to the nearest of
## the place's own kinds in view and takes it from the road and from above.

const Postcards := preload("res://tests/postcards/postcards.gd")

const PLACES := [
	{"id": "mosel", "want": ["vine", "bush_vine"], "title": "The Mosel, Bernkastel to Wehlen", "from": [49.9160, 7.0700], "to": [49.9330, 7.0450]},
	{"id": "almeria", "want": ["house_plastic", "house_glass", "house_tunnel"], "title": "El Ejido, Almería", "from": [36.7900, -2.8600], "to": [36.7800, -2.7800]},
	{"id": "camargue", "want": ["pan_pink", "pan_white", "pan_brine"], "title": "Salin-de-Giraud, the Camargue", "from": [43.4050, 4.7280], "to": [43.3700, 4.7180]},
	{"id": "swaledale", "want": ["wall_gritstone"], "title": "Swaledale, Muker to Gunnerside", "from": [54.3750, -2.1400], "to": [54.3800, -2.0800]},
	{"id": "bali", "want": ["paddy_water", "paddy_rice"], "title": "Bedugul, Bali", "from": [-8.2850, 115.1500], "to": [-8.2700, 115.1750]},
	{"id": "shodoshima", "want": ["tree_citrus", "stone_haka"], "title": "Shodoshima, Kusakabe", "from": [34.4760, 134.2620], "to": [34.4780, 134.2900]},
]

var out_dir := "/tmp/fields"
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
		print("fields: %s: its pins aren't in one cell" % place["id"])
		return
	var fetched := "" if own_world else RealRegion.fetch_area(str(plan["region"]))
	if fetched != "":
		print("fields: %s: %s" % [place["id"], fetched])
		return
	var region := RealRegion.get_region(str(plan["region"]))
	var path := features_dir.path_join("%s.json" % place["id"])
	if region != null and features_dir != "" and FileAccess.file_exists(path):
		region.features = {"points": [], "lines": [], "areas": []}
		var rows = JSON.parse_string(FileAccess.get_file_as_string(path))
		if rows is Dictionary:
			RealRegion.add_features(region.features, rows, Vector2(region.frame_lat, region.frame_lon))
	var res := AdventurePlans.result(plan, true)
	if not bool(res.get("ok", false)):
		print("fields: %s: no ride (%s)" % [place["id"], res.get("error", "")])
		return
	var w := AdventureWorld.new()
	AdventureWorld.network = true
	w.roads_region = region
	w.setup(res["pack"], 1)
	if w.roads == null or w.scenery == null:
		print("fields: %s: not on the network" % place["id"])
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
	print("fields: %s: %d scenery blocks, %s, aiming at %s" % [place["id"], w.scenery.blocks.size(), w.scenery.stats, target])
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
			print("fields: saved ", name)
	w.queue_free()
	await get_tree().process_frame


## Puts the camera on the road `s` m along (or above and behind it) looking at the field there (_target).
func _aim(w: AdventureWorld, cam: Camera3D, s: float, view: String, want: Array) -> void:
	var eye := Postcards.view_xf(w, s, "road")
	var target := _target(w, eye.origin, want)
	var aim: Vector3 = target[1]
	cam.global_transform = eye
	if view == "above":
		var back := Vector3(eye.origin.x - aim.x, 0.0, eye.origin.z - aim.z).normalized()
		cam.global_position = aim + back * 170.0 + Vector3(0, 75.0, 0)
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


## The field to look at from `eye`: [model, where (world), how tall], the nearest of the place's own models standing
## between 60 m and 900 m off; ["", eye, 0] for none.
func _target(w: AdventureWorld, eye: Vector3, want := []) -> Array:
	var best := {}
	var nearest := INF
	var sample := Vector3.ZERO
	for node: Node3D in w.scenery.blocks.values():
		for mmi in node.get_children():
			if not mmi is MultiMeshInstance3D:
				continue
			var model := str(mmi.name).trim_prefix("fields_")
			if not want.has(model):
				continue
			var mm: MultiMesh = mmi.multimesh
			for i in range(0, mm.instance_count, maxi(1, mm.instance_count / 400)):
				var xf: Transform3D = (mmi as Node3D).global_transform * mm.get_instance_transform(i)
				var d := xf.origin.distance_to(eye)
				if d < nearest:
					nearest = d
					sample = xf.origin
				if d < 60.0 or d > 4000.0:
					continue
				if best.is_empty() or d < float(best["d"]):
					best = {"d": d, "at": xf.origin, "model": model}
	if best.is_empty():
		var names := []
		for node: Node3D in w.scenery.blocks.values():
			for mmi in node.get_children():
				if not str(mmi.name) in names:
					names.append(str(mmi.name))
		print("fields: nothing of %s in view (the nearest %.0f m off, at %s; the eye at %s); the blocks have %s" % [want, nearest, sample, eye, names])
		return ["", eye, 0.0]
	print("fields: aiming at %s %.0f m off" % [best["model"], float(best["d"])])
	return [best["model"], best["at"], 2.0]
